//
//  CSSFormatter.swift
//  ColorKit
//

import Foundation

/// A CSS serialization target.
///
/// Distinct from `ColorSpace` because one space has several spellings: sRGB can be
/// written as a hex triplet, a keyword, `rgb()`, or `color(srgb …)`, and those are
/// not interchangeable in output.
nonisolated enum CSSOutputFormat: Hashable, Sendable {
  case hex
  case keyword
  case rgb
  case hsl
  case hwb
  case lab
  case lch
  case oklab
  case oklch
  case color(ColorSpace)

  // MARK: Internal

  /// The space a color must be converted into for this format.
  var space: ColorSpace {
    switch self {
    case .hex, .keyword, .rgb: .srgb
    case .hsl: .hsl
    case .hwb: .hwb
    case .lab: .lab
    case .lch: .lch
    case .oklab: .oklab
    case .oklch: .oklch
    case let .color(space): space
    }
  }

  /// Formats that cannot express an out-of-gamut value at all.
  ///
  /// Hex is 8-bit unsigned, so a negative channel simply has no spelling; a keyword
  /// is one of 148 fixed points. Both must be gamut-mapped regardless of policy.
  /// `rgb()` and friends, by contrast, accept out-of-range numbers syntactically.
  var cannotRepresentOutOfGamut: Bool {
    switch self {
    case .hex, .keyword: true
    default: false
    }
  }
}

/// Written by hand rather than derived: `CSSOutputFormat` is not `RawRepresentable`
/// (`.color` carries a `ColorSpace`), so there is no raw value for `Codable` synthesis
/// to key off. The spelling below is the same one `ColorKitCLI/Names.swift` uses for
/// its `--format` argument — the `color()` cases named by their space's own raw value,
/// which *is* the CSS identifier — chosen for the same reason, not shared code: the two
/// targets cannot import one another (see the CLI/app module split in CLAUDE.md), so
/// this is a second, independently-checked transcription of one fact rather than a
/// second decision.
nonisolated extension CSSOutputFormat: Codable {
  // MARK: Lifecycle

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let raw = try container.decode(String.self)
    switch raw {
    case "hex": self = .hex
    case "keyword": self = .keyword
    case "rgb": self = .rgb
    case "hsl": self = .hsl
    case "hwb": self = .hwb
    case "lab": self = .lab
    case "lch": self = .lch
    case "oklab": self = .oklab
    case "oklch": self = .oklch
    default:
      guard let space = ColorSpace(rawValue: raw) else {
        throw DecodingError.dataCorruptedError(
          in: container,
          debugDescription: "Unknown CSSOutputFormat identifier \"\(raw)\"",
        )
      }
      self = .color(space)
    }
  }

  // MARK: Internal

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .hex: try container.encode("hex")
    case .keyword: try container.encode("keyword")
    case .rgb: try container.encode("rgb")
    case .hsl: try container.encode("hsl")
    case .hwb: try container.encode("hwb")
    case .lab: try container.encode("lab")
    case .lch: try container.encode("lch")
    case .oklab: try container.encode("oklab")
    case .oklch: try container.encode("oklch")
    case let .color(space): try container.encode(space.rawValue)
    }
  }
}

nonisolated struct CSSFormatOptions: Sendable, Equatable, Codable {
  /// `String` raw values, and `Codable`, purely so ``Preferences`` can persist a whole
  /// `CSSFormatOptions` by synthesis rather than a mirrored copy that can drift — the
  /// same reasoning ``ColorSpace``'s raw values already follow.
  nonisolated enum AlphaPolicy: String, Sendable, Hashable, Codable {
    case whenNotOpaque, always, never
  }

  nonisolated enum GamutPolicy: String, Sendable, Hashable, Codable {
    /// Map into the target's gamut so the output renders as shown.
    case map
    /// Keep out-of-range values wherever the syntax permits them. Faithful to the
    /// authored color, but a browser will clamp it at used-value time.
    case preserve
  }

  static let `default` = CSSFormatOptions()

  /// Serialization detailed enough to survive a round trip back through the parser.
  ///
  /// Storage precision and display precision are different concerns and must not
  /// share a setting. A panel showing `oklch(0.62 0.19 259.81)` has rounded a value
  /// it will re-derive from the original next frame; a *stored* string that rounds
  /// has destroyed the original. Anything adopted into the input field — an
  /// eyedropper sample, a picker result — takes this instead of the user's chosen
  /// precision, which governs only what is shown.
  ///
  /// `preserve` matters as much as the digits: a sample from a P3 display sits
  /// outside sRGB, and mapping it into gamut on the way in would discard the very
  /// wideness worth capturing.
  static let lossless = CSSFormatOptions(precision: 10, gamut: .preserve)

  /// Decimal places for a component measured on a 0–1 scale. Trailing zeros are
  /// stripped, and components on larger scales get proportionally fewer — see
  /// ``decimals(forFullScale:)``.
  var precision: Int = 4
  /// Comma-separated output. Only valid for `rgb`/`hsl`; ignored elsewhere.
  var legacy: Bool = false
  /// Write `rgb()` channels as percentages instead of 0–255 numbers.
  var rgbAsPercentage: Bool = false
  /// Shorten `#ffcc00` to `#fc0` when every channel pair repeats.
  var collapseHex: Bool = false
  var uppercaseHex: Bool = false
  var alpha: AlphaPolicy = .whenNotOpaque
  var gamut: GamutPolicy = .map
  /// Also write `none` for hues that are powerless because the color is gray,
  /// not only for components explicitly authored as `none`.
  var noneForPowerlessComponents: Bool = false

  /// Decimal places for a component whose values run up to `fullScale`.
  ///
  /// A flat decimal count is the wrong unit for CSS colors, because components do
  /// not share a scale. Four decimals is right for an OKLCH lightness of `0.6231`
  /// and ridiculous for a hue of `217.2193` — the hue is being reported to a
  /// ten-thousandth of a degree, which no display can show and no eye can see. Both
  /// numbers claim the same *absolute* accuracy while differing by three orders of
  /// magnitude in what that accuracy means.
  ///
  /// So precision is defined relative to each component's own range: `precision`
  /// decimals at unit scale, one fewer for each power of ten above it. At the
  /// default of 4 that yields `oklch(0.6231 0.188 259.81)` and
  /// `hsl(217.22 91.22% 59.8%)` — every component carried to about the same number
  /// of meaningful digits.
  func decimals(forFullScale fullScale: Double) -> Int {
    guard fullScale > 0, fullScale.isFinite else { return precision }
    let magnitude = Int(floor(log10(fullScale)))
    // Never exceed `precision`: sub-unit components like OKLab's ±0.4 would
    // otherwise gain digits, which is accuracy nobody asked for.
    return min(max(precision - magnitude, 0), precision)
  }
}

nonisolated extension ColorValue {
  /// Serializes this color as CSS.
  ///
  /// Returns `nil` only for `.keyword` when no keyword matches — every other format
  /// can represent any color.
  func cssString(
    as format: CSSOutputFormat,
    options: CSSFormatOptions = .default,
  ) -> String? {
    let prepared = prepare(for: format, options: options)

    switch format {
    case .hex:
      return prepared.hexString(options: options)
    case .keyword:
      return prepared.namedKeyword
    case .rgb:
      return prepared.functionString(.rgb, options: options)
    case .hsl:
      return prepared.functionString(.hsl, options: options)
    case .hwb:
      return prepared.functionString(.hwb, options: options)
    case .lab:
      return prepared.functionString(.lab, options: options)
    case .lch:
      return prepared.functionString(.lch, options: options)
    case .oklab:
      return prepared.functionString(.oklab, options: options)
    case .oklch:
      return prepared.functionString(.oklch, options: options)
    case let .color(space):
      return prepared.colorFunctionString(space: space, options: options)
    }
  }

  /// Serializes as CSS, falling back to hex when a keyword was requested but none
  /// exists. Convenient for UI that must always show something.
  func cssStringOrHex(
    as format: CSSOutputFormat,
    options: CSSFormatOptions = .default,
  ) -> String {
    cssString(as: format, options: options)
      ?? cssString(as: .hex, options: options)
      ?? "#000000"
  }

  // MARK: - Gamut decision

  /// Whether serializing as `format` moves the color to make it expressible.
  ///
  /// The single place that decision is made. `prepare(for:options:)` asks it to
  /// choose between mapping and plain conversion, and the UI asks it to decide
  /// whether to badge a value as gamut-mapped. Computing those separately would let
  /// the badge disagree with the string it labels — a mismatch nothing would catch,
  /// since both sides would still compile and still look plausible.
  ///
  /// The two callers differ only in `epsilon`, and deliberately so. Serialization
  /// passes `0`, mapping on any excursion at all so the emitted number is clean
  /// rather than `rgb(255.0191 0 0)`. The badge passes ``gamutNoiseTolerance``, so a
  /// float artifact from a round trip through Lab is not reported to the user as an
  /// out-of-gamut color. Badge-true therefore always implies mapping happened, and
  /// badge-false implies any movement was smaller than a fifty-fifth of an 8-bit step.
  func isGamutMapped(
    as format: CSSOutputFormat,
    options: CSSFormatOptions = .default,
    epsilon: Double = 0,
  ) -> Bool {
    guard format.cannotRepresentOutOfGamut || options.gamut == .map else { return false }
    // `inGamut(of:)` already answers `true` for unbounded spaces, which have no
    // gamut to leave, so Lab and XYZ fall out here without a special case.
    return !inGamut(of: format.space, epsilon: epsilon)
  }

  /// Channel slack below which an out-of-gamut reading is float noise, not a color.
  ///
  /// Matches the reference implementation's tolerance. At `0.000075` of a 0–1
  /// channel this is roughly 1/55th of an 8-bit step — far too small to be a color
  /// anyone authored, and exactly the size of the residue left by converting
  /// `#ff0000` to Lab and back.
  static let gamutNoiseTolerance = 0.000075

  // MARK: - Preparation

  /// Converts into the target space, gamut-mapping when the format or policy
  /// requires it.
  private func prepare(
    for format: CSSOutputFormat,
    options: CSSFormatOptions,
  ) -> ColorValue {
    let target = format.space

    var result: ColorValue = if isGamutMapped(as: format, options: options) {
      gamutMapped(to: target)
    } else {
      converted(to: target)
    }

    if options.noneForPowerlessComponents {
      result = result.markingPowerlessComponents()
    }
    // The alpha flag survives conversion; component flags do not, so re-apply the
    // authored ones when the space is unchanged.
    if space == target {
      result.missing.formUnion(missing)
    } else if missing.contains(.alpha) {
      result.missing.insert(.alpha)
    }
    return result
  }

  // MARK: - Hex

  private func hexString(options: CSSFormatOptions) -> String {
    func channel(_ value: Double) -> Int {
      Int((value * 255).rounded().clamped(to: 0 ... 255))
    }

    var pairs = [channel(components.x), channel(components.y), channel(components.z)]
    let includeAlpha = shouldEmitAlpha(options: options) && !missing.contains(.alpha)
    if includeAlpha {
      pairs.append(Int((alpha * 255).rounded().clamped(to: 0 ... 255)))
    }

    let digits = pairs.map { String(format: "%02x", $0) }
    let collapsible = options.collapseHex && digits.allSatisfy { $0.first == $0.last }
    let body = collapsible ? digits.map { String($0.first!) }.joined() : digits.joined()

    return "#" + (options.uppercaseHex ? body.uppercased() : body)
  }

  // MARK: - Functions

  private func functionString(
    _ function: ColorFunction,
    options: CSSFormatOptions,
  ) -> String {
    let grammars = ColorGrammar.components(for: function)
    // Legacy syntax has no spelling for `none`, so those components fall back to
    // their zero value rather than emitting invalid CSS.
    let useLegacy = options.legacy && function.hasLegacyForm

    var parts: [String] = []
    for index in 0 ..< 3 {
      if missing.contains(.component(index)), !useLegacy {
        parts.append("none")
        continue
      }
      parts.append(
        componentString(
          components[index],
          grammar: grammars[index],
          function: function,
          index: index,
          options: options,
        ),
      )
    }

    let name = legacyFunctionName(function, options: options)
    let alphaText = alphaString(options: options, allowNone: !useLegacy)

    if useLegacy {
      let body = parts.joined(separator: ", ")
      if let alphaText {
        return "\(name)(\(body), \(alphaText))"
      }
      return "\(name)(\(body))"
    }

    let body = parts.joined(separator: " ")
    if let alphaText {
      return "\(name)(\(body) / \(alphaText))"
    }
    return "\(name)(\(body))"
  }

  private func colorFunctionString(space: ColorSpace, options: CSSFormatOptions) -> String? {
    guard let identifier = ColorGrammar.colorFunctionIdentifier(for: space) else {
      return nil
    }
    var parts: [String] = []
    for index in 0 ..< 3 {
      if missing.contains(.component(index)) {
        parts.append("none")
      } else {
        parts.append(formatNumber(components[index], options: options))
      }
    }
    let body = parts.joined(separator: " ")
    if let alphaText = alphaString(options: options, allowNone: true) {
      return "color(\(identifier) \(body) / \(alphaText))"
    }
    return "color(\(identifier) \(body))"
  }

  private func legacyFunctionName(
    _ function: ColorFunction,
    options: CSSFormatOptions,
  ) -> String {
    // rgba()/hsla() exist only so legacy syntax can carry alpha; modern syntax
    // uses the base name with a slash.
    guard options.legacy, function.hasLegacyForm, shouldEmitAlpha(options: options) else {
      return function.rawValue
    }
    switch function {
    case .rgb, .rgba: return "rgba"
    case .hsl, .hsla: return "hsla"
    default: return function.rawValue
    }
  }

  // MARK: - Components

  private func componentString(
    _ value: Double,
    grammar: ComponentGrammar,
    function: ColorFunction,
    index: Int,
    options: CSSFormatOptions,
  ) -> String {
    if grammar.isAngle {
      return formatNumber(value, fullScale: grammar.fullScale, options: options)
    }

    // Percentage-only slots, plus rgb() when the caller asked for percentages.
    let forcePercentage =
      grammar.requiresPercentageInLegacy
        || (function == .hwb && index > 0)
        || ((function == .rgb || function == .rgba) && options.rgbAsPercentage)
        || ((function == .lab || function == .lch) && index == 0)

    if forcePercentage {
      let percent = value / grammar.percentReference * 100
      // Written as a percentage, so the scale is 100 regardless of what the
      // component stores natively.
      return formatNumber(percent, fullScale: 100, options: options) + "%"
    }

    return formatNumber(
      value / grammar.numberScale,
      fullScale: grammar.fullScale,
      options: options,
    )
  }

  private func shouldEmitAlpha(options: CSSFormatOptions) -> Bool {
    switch options.alpha {
    case .always: true
    case .never: false
    case .whenNotOpaque: alpha < 1 || missing.contains(.alpha)
    }
  }

  private func alphaString(options: CSSFormatOptions, allowNone: Bool) -> String? {
    guard shouldEmitAlpha(options: options) else { return nil }
    if missing.contains(.alpha) {
      return allowNone ? "none" : formatNumber(alpha, options: options)
    }
    return formatNumber(alpha, options: options)
  }

  /// - Parameter fullScale: the component's own range, so precision can be relative
  ///   to it rather than absolute. Defaults to 1 for values already on a unit
  ///   scale — alpha and the `color()` channels.
  private func formatNumber(
    _ value: Double,
    fullScale: Double = 1,
    options: CSSFormatOptions,
  ) -> String {
    guard value.isFinite else { return "0" }

    let decimals = options.decimals(forFullScale: fullScale)
    let factor = pow(10.0, Double(decimals))
    let rounded = (value * factor).rounded() / factor

    // Avoid "-0", which is valid CSS but reads as a bug.
    if rounded == 0 {
      return "0"
    }

    var text = String(format: "%.\(decimals)f", rounded)
    if text.contains(".") {
      while text.hasSuffix("0") {
        text.removeLast()
      }
      if text.hasSuffix(".") {
        text.removeLast()
      }
    }
    return text
  }
}

private nonisolated extension Double {
  func clamped(to range: ClosedRange<Double>) -> Double {
    Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
  }
}
