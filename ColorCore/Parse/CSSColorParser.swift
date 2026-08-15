//
//  CSSColorParser.swift
//  ColorKit
//

import Foundation

/// The form a color was written in, so the UI can echo it back the same way.
nonisolated enum ColorNotation: Equatable, Sendable {
  case hex(digits: Int)
  case keyword(String)
  case function(ColorFunction, legacy: Bool)
  /// `rgb(from …)` and friends — CSS Color 5 relative color syntax.
  ///
  /// A case of its own rather than a flag on ``function``, and it carries no
  /// `legacy:` because there is no such thing: the spec says relative color syntax
  /// applies to modern syntax only and that combining the two is an error. Encoding
  /// that in the type means no caller has to remember it.
  case relative(ColorFunction)
  /// `color-mix(in oklch, …)` — CSS Color 5's mixing function.
  ///
  /// Not a ``ColorFunction`` case, because that enum is a list of functions whose
  /// arguments are *components*: every one of them has a per-component grammar, a
  /// legacy question and a space of its own, and `color-mix()` has none of the three.
  /// It carries its interpolation method instead, which is the only thing about the
  /// written form the value itself cannot tell you afterwards.
  case mix(ColorInterpolation)
}

nonisolated struct ParseResult: Equatable, Sendable {
  var color: ColorValue
  var notation: ColorNotation
  /// Syntax that parsed but is not valid CSS. Empty for well-formed input.
  var warnings: [ParseWarning] = []
}

/// Parses CSS Color Module Level 4 syntax.
///
/// Targets the CSS grammar itself rather than any convenience library's reading of
/// it. That distinction matters: permissive parsers accept `rgb(a b c)` as
/// `rgb(none none none)`, which would turn a user's typo into a silently valid color
/// — the opposite of useful in a tool whose job is telling you what your CSS means.
/// Invalid input is rejected with a specific reason.
nonisolated enum CSSColorParser {
  // MARK: Internal

  // MARK: - Entry point

  static func parse(_ input: String) throws(ParseError) -> ParseResult {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw ParseError.empty }

    // Checked before tokenizing so the user hears "clamp() isn't supported"
    // rather than a complaint from somewhere inside its argument list. `calc()`
    // used to be caught here and is now evaluated — see `CalcExpression`.
    if let unsupported = UnsupportedFunctions.firstCalled(in: trimmed) {
      throw ParseError.unsupportedFunction(unsupported)
    }

    let tokens = try CSSTokenizer.tokenize(trimmed)
    guard let first = tokens.first else { throw ParseError.empty }

    switch first {
    case let .hash(digits):
      guard tokens.count == 1 else {
        throw ParseError.trailingContent(tokens[1].description)
      }
      return try parseHex(digits)

    case let .ident(name):
      guard tokens.count == 1 else {
        throw ParseError.trailingContent(tokens[1].description)
      }
      guard let color = ColorValue.named(name) else {
        throw ParseError.unknownKeyword(name)
      }
      return ParseResult(color: color, notation: .keyword(name))

    case let .function(name):
      return try parseFunction(name, tokens: Array(tokens.dropFirst()))

    default:
      throw ParseError.unexpectedToken(first.description)
    }
  }

  /// Convenience for callers that only care whether it parsed.
  static func color(_ input: String) -> ColorValue? {
    try? parse(input).color
  }

  // MARK: Private

  /// One written component value, before per-space interpretation.
  private enum Value: Equatable {
    case number(Double)
    case percentage(Double)
    case angle(Double)
    case none

    // MARK: Lifecycle

    /// A resolved `calc()` becomes an ordinary written value.
    ///
    /// The types line up exactly, which is the reason `calc()` costs so little
    /// here: everything downstream — the per-component grammar, the legacy
    /// same-type rules, the angle-slot check — runs unchanged and cannot tell a
    /// computed value from a typed one. That last part is a decision, not an
    /// accident; `CalcTests` pins both sides of it.
    init(_ term: CalcTerm) {
      switch term {
      case let .number(n): self = .number(n)
      case let .percentage(p): self = .percentage(p)
      case let .angle(d): self = .angle(d)
      }
    }

    // MARK: Internal

    var isNone: Bool {
      self == .none
    }

    var isPercentage: Bool {
      if case .percentage = self {
        true
      } else {
        false
      }
    }

    var isPlainNumber: Bool {
      if case .number = self {
        true
      } else {
        false
      }
    }
  }

  private enum Separator: Equatable {
    case space, comma, slash
  }

  // MARK: - hex

  private static func parseHex(_ digits: String) throws(ParseError) -> ParseResult {
    let chars = Array(digits)
    guard [3, 4, 6, 8].contains(chars.count) else {
      throw ParseError.invalidHexLength(chars.count)
    }

    // Short forms duplicate each digit: #f0a → #ff00aa.
    let expanded: [String] =
      chars.count <= 4
        ? chars.map { String(repeating: String($0), count: 2) }
        : stride(from: 0, to: chars.count, by: 2).map { String(chars[$0 ... $0 + 1]) }

    let channels = expanded.map { Double(UInt8($0, radix: 16) ?? 0) / 255 }
    let color = ColorValue(
      space: .srgb,
      channels[0],
      channels[1],
      channels[2],
      alpha: channels.count == 4 ? channels[3] : 1,
    )
    return ParseResult(color: color, notation: .hex(digits: chars.count))
  }

  private static func parseFunction(
    _ name: String,
    tokens: [CSSToken],
  ) throws(ParseError) -> ParseResult {
    // Dispatched here rather than at the entry point so that nesting works in both
    // directions for free: `consumeColor` routes through this function, which is what
    // lets a mix be an origin color and either side of a mix be another mix.
    if name == "color-mix" {
      return try parseColorMix(tokens)
    }

    guard let function = ColorFunction(rawValue: name) else {
      throw ParseError.unknownFunction(name)
    }

    var rest = tokens
    var space: ColorSpace

    // `from` comes before the space identifier, not after: the grammar is
    // `color( [from <color>]? <space> …)`, so the origin is consumed first even
    // though the space is what it will be converted into.
    var origin: ColorValue?
    if case let .ident(keyword)? = rest.first, keyword == "from" {
      let (result, next) = try consumeColor(rest, from: 1)
      origin = result.color
      rest = Array(rest[next...])
    }

    if function == .color {
      guard case let .ident(id)? = rest.first else {
        throw ParseError.unknownColorSpace(rest.first?.description ?? "")
      }
      guard let resolved = ColorGrammar.colorFunctionSpaces[id] else {
        throw ParseError.unknownColorSpace(id)
      }
      space = resolved
      rest = Array(rest.dropFirst())
    } else {
      space = function.space!
    }

    let channels = origin.map { ChannelBindings(origin: $0, function: function, space: space) }
    let (values, separators) = try scanArguments(rest, channels: channels)
    return try assemble(
      function: function,
      space: space,
      values: values,
      separators: separators,
      isRelative: origin != nil,
    )
  }

  /// Reads one complete color starting at `index`, returning it and the index just
  /// past its last token.
  ///
  /// Needed because an origin color is a *nested* color written inside another
  /// one's argument list, so the top-level string-based entry point cannot reach
  /// it. Unlike a `calc()` body — which cannot nest, so its first `)` is its own —
  /// color functions nest freely (`rgb(from color(display-p3 1 0 0) r g b)`, and
  /// an origin may itself be relative), so the closing paren is found by depth.
  private static func consumeColor(
    _ tokens: [CSSToken],
    from index: Int,
  ) throws(ParseError) -> (ParseResult, Int) {
    guard index < tokens.count else { throw ParseError.missingOriginColor }

    switch tokens[index] {
    case .closeParen:
      // `rgb(from)`. There *is* a token, it just closes the function, so the
      // bounds check above does not catch this one.
      throw ParseError.missingOriginColor

    case let .hash(digits):
      return try (parseHex(digits), index + 1)

    case let .ident(name):
      guard let color = ColorValue.named(name) else {
        throw ParseError.unknownKeyword(name)
      }
      return (ParseResult(color: color, notation: .keyword(name)), index + 1)

    case let .function(name):
      var depth = 1
      var scan = index + 1
      while scan < tokens.count, depth > 0 {
        if case .function = tokens[scan] {
          depth += 1
        } else if tokens[scan] == .openParen {
          depth += 1
        } else if tokens[scan] == .closeParen {
          depth -= 1
        }
        scan += 1
      }
      guard depth == 0 else { throw ParseError.unterminatedFunction(name) }
      let body = Array(tokens[(index + 1) ..< scan])
      return try (parseFunction(name, tokens: body), scan)

    default:
      throw ParseError.unexpectedToken(tokens[index].description)
    }
  }

  // MARK: - color-mix()

  /// Parses `color-mix(<interpolation-method>, <color> <percentage>?,
  /// <color> <percentage>?)`.
  ///
  /// A separate function rather than a case in ``ColorFunction`` because it is a
  /// different kind of thing: every function in that enum takes *components*, with a
  /// per-component grammar, a legacy question and a fixed space. `color-mix()` takes
  /// two colors and a method, and forcing it into that shape would mean four tables
  /// gaining an entry that means nothing.
  ///
  /// The result is an ordinary ``ColorValue`` in the interpolation space — a mix is a
  /// color, not a recipe, and nothing downstream needs to know it was written as one.
  private static func parseColorMix(_ tokens: [CSSToken]) throws(ParseError) -> ParseResult {
    var index = 0

    // The method is required and comes first. CSS deliberately has no default here,
    // because which space you mix in changes the answer completely.
    guard token(tokens, index) == .ident("in") else {
      throw ParseError.mixNeedsInterpolationMethod
    }
    index += 1

    guard case let .some(.ident(identifier)) = token(tokens, index) else {
      throw ParseError.mixNeedsInterpolationMethod
    }
    guard let space = ColorGrammar.interpolationSpace(named: identifier) else {
      throw ParseError.unknownInterpolationSpace(identifier)
    }
    index += 1

    var interpolation = ColorInterpolation(space: space)
    if case let .some(.ident(name)) = token(tokens, index) {
      guard let method = HueInterpolationMethod(rawValue: name) else {
        throw ParseError.unexpectedToken(name)
      }
      guard space.hueIndex != nil else {
        // Not merely redundant — a space with no hue has no arc to choose, so the
        // spec's grammar has nowhere to put this and rejects it.
        throw ParseError.hueMethodNeedsPolarSpace(method: name, space: identifier)
      }
      guard token(tokens, index + 1) == .ident("hue") else {
        throw ParseError.hueMethodNeedsHueKeyword(name)
      }
      interpolation.hue = method
      index += 2
    }

    guard token(tokens, index) == .comma else {
      throw ParseError.mixNeedsTwoColors
    }
    index += 1

    let first = try consumeMixOperand(tokens, from: index)
    switch token(tokens, first.next) {
    case .some(.comma):
      break
    case .none, .some(.closeParen):
      throw ParseError.mixNeedsTwoColors
    case let .some(other):
      throw ParseError.unexpectedToken(other.description)
    }

    let second = try consumeMixOperand(tokens, from: first.next + 1)
    guard token(tokens, second.next) == .closeParen else {
      if let stray = token(tokens, second.next) {
        throw ParseError.unexpectedToken(stray.description)
      }
      throw ParseError.unterminatedFunction("color-mix")
    }
    if let trailing = token(tokens, second.next + 1) {
      throw ParseError.trailingContent(trailing.description)
    }

    guard let weights = MixWeights(first: first.percentage, second: second.percentage) else {
      throw ParseError.mixPercentagesAreBothZero
    }

    return ParseResult(
      color: interpolation.mix(first.color, second.color, weights: weights),
      notation: .mix(interpolation),
    )
  }

  /// One side of a `color-mix()`: a color, and optionally a percentage.
  ///
  /// The percentage is read before *and* after the color because the grammar joins
  /// them with `&&`, which means either order — `red 30%` and `30% red` are the same
  /// color-mix operand, and a parser that only looks on one side rejects valid CSS.
  private static func consumeMixOperand(
    _ tokens: [CSSToken],
    from index: Int,
  ) throws(ParseError) -> (color: ColorValue, percentage: Double?, next: Int) {
    var cursor = index
    var percentage = try mixPercentage(tokens, at: &cursor)

    // Caught here so an empty slot reports what is actually wrong. `consumeColor`
    // would answer `missingOriginColor`, which is about `from` and has nothing to
    // do with this function.
    switch token(tokens, cursor) {
    case .none, .some(.closeParen), .some(.comma):
      throw ParseError.mixNeedsTwoColors
    default:
      break
    }

    let (result, afterColor) = try consumeColor(tokens, from: cursor)
    cursor = afterColor

    if percentage == nil {
      percentage = try mixPercentage(tokens, at: &cursor)
    }
    return (result.color, percentage, cursor)
  }

  /// Reads the optional percentage at `cursor`, leaving it untouched when there is
  /// none.
  ///
  /// `calc()` is accepted here for the reason it is accepted in a component slot: a
  /// resolved `calc()` is indistinguishable from a written value downstream, so the
  /// range rule below applies to both alike rather than gaining a second reading.
  private static func mixPercentage(
    _ tokens: [CSSToken],
    at cursor: inout Int,
  ) throws(ParseError) -> Double? {
    guard let current = token(tokens, cursor) else { return nil }

    let value: Double
    switch current {
    case let .percentage(p):
      value = p
      cursor += 1

    case let .function(name) where name == "calc":
      let (term, next) = try consumeCalc(tokens, openedAt: cursor, channels: nil)
      guard case let .percentage(p) = term else {
        throw ParseError.mixNeedsPercentage(describe(term))
      }
      value = p
      cursor = next

    default:
      return nil
    }

    // The grammar spells this slot `<percentage [0, 100]>`, and out of range is
    // rejected rather than clamped — unlike alpha, where there is an obvious
    // intention to read. `red 150%` has none: it is either a typo or arithmetic the
    // author has not finished.
    guard value >= 0, value <= 100 else {
      throw ParseError.mixPercentageOutOfRange(value)
    }
    return value
  }

  /// The token at `index`, or `nil` past the end.
  ///
  /// `color-mix()`'s grammar is positional rather than separator-driven, so it reads
  /// ahead constantly and every one of those reads can run off the end.
  private static func token(_ tokens: [CSSToken], _ index: Int) -> CSSToken? {
    index < tokens.count ? tokens[index] : nil
  }

  /// How a resolved `calc()` value is named back to the user, mirroring
  /// ``CSSToken/description``.
  private static func describe(_ term: CalcTerm) -> String {
    switch term {
    case let .number(n): "\(n)"
    case let .percentage(p): "\(p)%"
    case let .angle(d): "\(d)deg"
    }
  }

  /// Splits the argument list into values and the separators between them.
  ///
  /// Iterates by index rather than with `for in` because of one case: a `calc()`
  /// body has to be consumed **as a unit**, before any of this sees the tokens
  /// inside it. `/` is both the alpha separator and calc's division operator, so
  /// `rgb(0 0 0 / calc(1/2))` has two slashes meaning different things and the only
  /// thing that tells them apart is which side of `calc(`…`)` they fall on.
  private static func scanArguments(
    _ tokens: [CSSToken],
    channels: ChannelBindings?,
  ) throws(ParseError) -> ([Value], [Separator]) {
    var values: [Value] = []
    var separators: [Separator] = []
    var pendingSeparator: Separator?
    var closed = false
    var index = 0

    while index < tokens.count {
      let token = tokens[index]
      if closed {
        throw ParseError.trailingContent(token.description)
      }

      // Consumed whole, so `index` jumps past the closing paren rather than
      // advancing by one.
      if case let .function(name) = token, name == "calc" {
        let (term, next) = try consumeCalc(tokens, openedAt: index, channels: channels)
        try append(Value(term), &values, &separators, &pendingSeparator)
        index = next
        continue
      }

      switch token {
      case .closeParen:
        closed = true

      case .comma:
        guard !values.isEmpty, pendingSeparator == nil else {
          throw ParseError.unexpectedToken(",")
        }
        pendingSeparator = .comma

      case .slash:
        guard !values.isEmpty, pendingSeparator == nil else {
          throw ParseError.unexpectedToken("/")
        }
        pendingSeparator = .slash

      case let .number(n):
        try append(.number(n), &values, &separators, &pendingSeparator)

      case let .percentage(p):
        try append(.percentage(p), &values, &separators, &pendingSeparator)

      case let .dimension(value, unit):
        guard let degrees = ColorGrammar.degrees(value, unit: unit) else {
          throw ParseError.unexpectedToken("\(value)\(unit)")
        }
        try append(.angle(degrees), &values, &separators, &pendingSeparator)

      case let .ident(name) where name == "none":
        try append(.none, &values, &separators, &pendingSeparator)

      case let .ident(name):
        // The single gate for every channel keyword. `channels` is nil outside a
        // relative color function, so this stays the plain rejection it was —
        // `rgb(r g b)` on its own is still a typo, not a color.
        guard let value = channels?.value(for: name) else {
          throw ParseError.unexpectedToken(name)
        }
        switch value {
        case let .number(n):
          try append(.number(n), &values, &separators, &pendingSeparator)
        case .missing:
          // Written bare, a missing channel stays missing. Inside a calc() the
          // spec reads it as zero instead — see `CalcExpression.term`.
          try append(.none, &values, &separators, &pendingSeparator)
        }

      case let .function(name):
        throw ParseError.unexpectedToken(name)

      case let .hash(h):
        throw ParseError.unexpectedToken("#\(h)")

      case .plus, .minus, .asterisk, .openParen:
        // Arithmetic outside a calc(). Reachable now that the tokenizer has
        // operator classes at all, and still not valid CSS.
        throw ParseError.unexpectedToken(token.description)
      }

      index += 1
    }

    if pendingSeparator == .slash {
      throw ParseError.missingAlphaAfterSlash
    }
    if pendingSeparator != nil {
      throw ParseError.unexpectedToken(",")
    }

    return (values, separators)
  }

  /// Evaluates the `calc()` opening at `openedAt`, returning its value and the
  /// index just past its closing paren.
  ///
  /// The body ends at the first `)`, which is sound only because the supported
  /// subset has no nesting — a `calc(` or `(` inside is rejected by
  /// ``CalcExpression`` rather than tracked by a depth counter here.
  private static func consumeCalc(
    _ tokens: [CSSToken],
    openedAt: Int,
    channels: ChannelBindings?,
  ) throws(ParseError) -> (term: CalcTerm, next: Int) {
    let bodyStart = openedAt + 1
    guard let close = tokens[bodyStart...].firstIndex(of: .closeParen) else {
      throw ParseError.calcUnterminated
    }
    let term = try CalcExpression.evaluate(
      Array(tokens[bodyStart ..< close]),
      channels: channels,
    )
    return (term, close + 1)
  }

  private static func append(
    _ value: Value,
    _ values: inout [Value],
    _ separators: inout [Separator],
    _ pending: inout Separator?,
  ) throws(ParseError) {
    if !values.isEmpty {
      separators.append(pending ?? .space)
    }
    pending = nil
    values.append(value)
  }

  // MARK: - Validation and assembly

  /// Applies the legacy/modern rules, then resolves each written value.
  ///
  /// Legacy and modern are two distinct grammars, not merely comma-vs-space, so the
  /// form is decided once from separator shape and then the whole rule set for that
  /// form is enforced.
  private static func assemble(
    function: ColorFunction,
    space: ColorSpace,
    values: [Value],
    separators: [Separator],
    isRelative: Bool,
  ) throws(ParseError) -> ParseResult {
    var warnings: [ParseWarning] = []

    let hasComma = separators.contains(.comma)
    let hasSlash = separators.contains(.slash)
    if hasComma && hasSlash {
      throw ParseError.commaAndSlashMixed
    }

    let isLegacy = hasComma
    if isRelative, isLegacy {
      // A hard error rather than a warning, unlike the other comma leniencies
      // here. Those parse because the intent is unambiguous; this one the spec
      // rules out outright — relative color syntax is modern-only.
      throw ParseError.relativeSyntaxRequiresModernForm(function: function.rawValue)
    }
    if isLegacy && !function.hasLegacyForm {
      // Unambiguous about intent, so parse it — but it is not valid CSS.
      warnings.append(.commasInModernFunction(function.rawValue))
    }

    guard values.count == 3 || values.count == 4 else {
      throw ParseError.wrongComponentCount(
        function: function.rawValue, expected: 3, got: values.count,
      )
    }

    if isLegacy {
      // Every separator must be a comma; a stray space means malformed input.
      guard separators.allSatisfy({ $0 == .comma }) else {
        throw ParseError.inconsistentSeparators
      }
    } else {
      // Modern: the three components are space-separated and alpha, if any,
      // follows a slash. Four space-separated values is not valid CSS.
      let componentSeparators = separators.prefix(2)
      guard componentSeparators.allSatisfy({ $0 == .space }) else {
        throw ParseError.inconsistentSeparators
      }
      if values.count == 4 {
        guard separators.count == 3, separators[2] == .slash else {
          throw ParseError.alphaWithoutSlash
        }
      }
    }

    let componentValues = Array(values.prefix(3))
    let alphaValue: Value? = values.count == 4 ? values[3] : nil

    if isLegacy, function.hasLegacyForm {
      try validateLegacyBody(function: function, values: componentValues, alpha: alphaValue)
      if componentValues.contains(where: \.isNone) || alphaValue?.isNone == true {
        warnings.append(.noneInLegacySyntax)
      }
    }

    // Resolve each written value against its component's grammar.
    let grammars = ColorGrammar.components(for: function)
    var components = SIMD3<Double>()
    var missing: ComponentMask = []

    for index in 0 ..< 3 {
      switch componentValues[index] {
      case .none:
        components[index] = 0
        missing.insert(.component(index))
      case let .number(n):
        components[index] = n * grammars[index].numberScale
      case let .percentage(p):
        components[index] = p / 100 * grammars[index].percentReference
      case let .angle(degrees):
        guard grammars[index].isAngle else {
          throw ParseError.unexpectedToken("\(degrees)deg")
        }
        components[index] = degrees
      }
    }

    var alpha = 1.0
    if let alphaValue {
      switch alphaValue {
      case .none:
        alpha = 1
        missing.insert(.alpha)
      case let .number(n):
        alpha = n
      case let .percentage(p):
        alpha = p / 100
      case .angle:
        throw ParseError.unexpectedToken("angle as alpha")
      }
      // Alpha is clamped and the three components deliberately are not, which
      // looks like an inconsistency and is the spec's rule in both directions.
      // Components must stay unclamped or an out-of-gamut color could not be
      // written down at all — the "Outside sRGB" badge exists to report exactly
      // those. Alpha has no such story: there is nothing beyond fully opaque, so
      // CSS clamps it at computed-value time. CSS Color 5 restates the rule for
      // relative syntax specifically, where a `calc(alpha * 3)` makes it easy to
      // reach.
      alpha = min(max(alpha, 0), 1)
    }

    let color = ColorValue(
      space: space,
      components: components,
      alpha: alpha,
      missing: missing,
    )
    return ParseResult(
      color: color,
      notation: isRelative ? .relative(function) : .function(function, legacy: isLegacy),
      warnings: warnings,
    )
  }

  /// The extra restrictions that apply only inside legacy comma syntax.
  private static func validateLegacyBody(
    function: ColorFunction,
    values: [Value],
    alpha: Value?,
  ) throws(ParseError) {
    switch function {
    case .rgb, .rgba:
      // All three channels must be the same type — no mixing 255 with 50%.
      let percentages = values.filter(\.isPercentage).count
      let numbers = values.filter(\.isPlainNumber).count
      if percentages > 0, numbers > 0 {
        throw ParseError.mixedNumberAndPercentageInLegacy(function: function.rawValue)
      }

    case .hsl, .hsla:
      // Saturation and lightness must be written as percentages.
      for index in 1 ... 2 where values[index].isPlainNumber {
        throw ParseError.percentageRequiredInLegacy(function: function.rawValue)
      }

    default:
      break
    }
    _ = alpha
  }
}
