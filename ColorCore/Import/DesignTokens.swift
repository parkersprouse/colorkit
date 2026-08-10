//
//  DesignTokens.swift
//  ColorKit
//

import Foundation

// MARK: - What comes out

/// One color token as it arrived: where it sat in the file, what it named, and the key
/// it will be written back out under.
///
/// ``path`` is retained alongside ``key`` rather than being replaced by it, because the
/// two answer different questions. The path is where the token lives in the document —
/// what a diagnostic has to name for anybody to find it. The key is a CSS identifier and
/// a JavaScript object key by the time it is emitted, so it is sanitized and made unique
/// here; that transformation is *lossy*, which is exactly why the original is kept.
nonisolated struct DesignToken: Sendable, Hashable {
  /// The group names above the token, then the token's own name.
  let path: [String]

  /// The export key: ``name`` reduced to a CSS identifier and disambiguated against the
  /// rest of the document. See ``DesignTokenImport/keyed(_:)``.
  let key: String

  let color: ColorValue

  /// The token's `$description`, empty when it had none. Carried because a design system
  /// tends to say *why* a color exists exactly once, in the token file.
  let description: String

  /// The dotted path, which is how the format itself refers to a token — `{color.brand.500}`.
  ///
  /// Joining on `.` is unambiguous rather than merely convenient: the format forbids `.`
  /// in a token or group name precisely so that a dotted path has one reading.
  var name: String {
    path.joined(separator: ".")
  }
}

/// Why a token that *should* have been a color was not imported.
///
/// Only failures appear here. A token of some other `$type` is not a failure — a real
/// token file is mostly dimensions and typography — so those are counted rather than
/// listed, and the panel can say "148 were not colors" without printing 148 lines.
/// - Note: `Error` so that decoding one token can be a `Result`. Nothing here is ever
///   *thrown* — a bad token is data about the file, not a failure of the import — but
///   `Result`'s failure type has to conform, and the alternative is a bespoke two-case
///   enum that says the same thing.
nonisolated enum TokenSkipReason: Error, Sendable, Hashable {
  /// A `colorSpace` this build does not know, with no usable `hex` to fall back to.
  case unknownColorSpace(String)
  /// The right shape was there and the contents were not readable.
  case malformedValue(String)
  /// `{a.b}` naming a token the file does not contain.
  case unresolvedAlias(String)
  /// An alias chain that comes back to where it started.
  case aliasCycle(String)

  // MARK: Internal

  var message: String {
    switch self {
    case let .unknownColorSpace(id):
      "“\(id)” is not a color space this app knows, and the token has no hex fallback."
    case let .malformedValue(what):
      "The value is not a color: \(what)."
    case let .unresolvedAlias(reference):
      "“{\(reference)}” names a token that is not in this file."
    case let .aliasCycle(name):
      "“\(name)” is defined in terms of itself."
    }
  }
}

nonisolated struct SkippedToken: Sendable, Hashable {
  let name: String
  let reason: TokenSkipReason
}

/// Everything one token file yielded.
///
/// Three counts rather than one, because "nothing was imported" has three causes a user
/// needs told apart: the file held no color tokens at all, it held colors this build
/// could not read, or it held colors and they are in ``colors``.
nonisolated struct DesignTokenDocument: Sendable, Hashable {
  /// The colors, in a deterministic order. See ``DesignTokenImport/isOrderedBefore(_:_:)``.
  let colors: [DesignToken]

  /// Color tokens that failed, each with a reason worth showing.
  let skipped: [SkippedToken]

  /// Tokens whose `$type` is something other than `color`, or that have no determinable
  /// type at all. Counted, not listed — see ``TokenSkipReason``.
  let otherTypeCount: Int
}

/// A file that is not a token file at all, as distinct from one whose tokens failed.
///
/// The distinction is the point. A sandbox denial, a JSON syntax error and a perfectly
/// good file full of spacing tokens are three different things to be told, and collapsing
/// them into "nothing imported" makes the first one undiagnosable — see the note on the
/// panel's error handling.
nonisolated enum DesignTokenError: Error, Equatable, Sendable {
  case notJSON
  case notAnObject
  case noTokens

  // MARK: Internal

  var message: String {
    switch self {
    case .notJSON:
      "That file is not JSON."
    case .notAnObject:
      "A design token file is a JSON object of groups and tokens; this is not one."
    case .noTokens:
      "That JSON file contains no Design tokens (DTCG) — nothing in it has a "
        + "“$value”. CSS, a Tailwind config, or plain color JSON is a different "
        + "reader's job, not this one's."
    }
  }
}

// MARK: - The decoder

/// Reads the W3C Design Tokens format's color tokens.
///
/// **`$value` is an object, not a CSS string**, so ``CSSColorParser`` is deliberately not
/// the entry point here: a color token is `{colorSpace, components, alpha?, hex?}` and
/// this is component-based construction. The parser is still used for one thing — the
/// optional `hex` member, which *is* CSS — and nothing about hex is re-implemented.
///
/// **The 14 `colorSpace` identifiers are byte-identical to ``ColorSpace``'s raw values**,
/// because both follow CSS Color 4's naming. So `ColorSpace(rawValue:)` is the whole
/// decoder and there is no mapping table to keep in step. Note that this is *not*
/// ``ColorGrammar/colorFunctionSpaces``, which additionally accepts CSS's `xyz` alias:
/// the token format has no such alias, so a token written `xyz` is honestly unknown.
///
/// **The component values need no scaling.** The format's ranges are CSS Color 4's own
/// *number* forms — `srgb` 0–1, `hsl` 0–360/0–100/0–100, `lab` 0–100/±∞, `oklch`
/// 0–1/0–∞/0–360 — and this app stores number forms, so a token's components are the
/// stored components. The single trap is `rgb()`, whose number form runs 0–255 while the
/// format's `srgb` runs 0–1: scale a token's `[1, 0, 0]` by that and red imports as a
/// near-black that still renders and still round-trips.
///
/// So there is **no arithmetic here at all**, and deliberately no reference to
/// ``ColorGrammar`` either. Those tables are CSS *syntax*, which has no authority over
/// this format — coupling to them would mean a future change to how `color()` is written
/// silently changing what a token file means. `DesignTokenImportTests` holds the tripwire
/// instead: it asserts that the grammar each space *would* be written with has a
/// `numberScale` of 1, so the assumption underneath this decision fails loudly rather than
/// quietly if it ever stops holding.
///
/// PLAN.md's M17 note said to reuse ``ComponentGrammar/fullScale`` as the range table.
/// That was written before the Color module was read and is wrong: the module leaves
/// `lab`'s a/b, `oklab`'s a/b and both chromas **unbounded**, while `fullScale` reports
/// 125, 0.4 and 0.4 — it is a precision hint ("how many decimals are worth printing"),
/// not a bound, and validating against it would reject legal tokens. Nothing here clamps
/// a component; alpha is the one exception, for the reason the parser gives.
nonisolated enum DesignTokenImport {
  // MARK: Internal

  /// The `$type` this importer is looking for.
  static let colorType = "color"

  /// Decodes every color token in a token file.
  ///
  /// Throws only when the file is not a token file. A token that cannot be read is
  /// reported in ``DesignTokenDocument/skipped`` instead, because one bad token in three
  /// hundred should not cost you the other 299.
  static func decode(_ data: Data) throws(DesignTokenError) -> DesignTokenDocument {
    let json: Any
    do {
      json = try JSONSerialization.jsonObject(with: data)
    } catch {
      throw .notJSON
    }
    guard let root = json as? [String: Any] else { throw .notAnObject }

    var raw: [String: RawToken] = [:]
    collect(root, path: [], inheritedType: nil, into: &raw)
    guard !raw.isEmpty else { throw .noTokens }

    var colors: [(path: [String], color: ColorValue, description: String)] = []
    var skipped: [SkippedToken] = []
    var otherTypeCount = 0

    for token in raw.values.sorted(by: { isOrderedBefore($0.path, $1.path) }) {
      var visiting: Set<String> = []
      switch resolve(token, in: raw, visiting: &visiting) {
      case let .failure(reason):
        // An unresolvable reference is only a *color* failure if the token was going to
        // be a color, and an unresolved alias is exactly the case where that cannot be
        // known. Reported rather than counted, because a broken reference is a defect in
        // the file whatever its type.
        skipped.append(SkippedToken(name: token.name, reason: reason))
      case let .success(resolved):
        guard resolved.type == colorType else {
          otherTypeCount += 1
          continue
        }
        switch color(from: resolved.value) {
        case let .success(color):
          colors.append((token.path, color, token.description))
        case let .failure(reason):
          skipped.append(SkippedToken(name: token.name, reason: reason))
        }
      }
    }

    return DesignTokenDocument(
      colors: keyed(colors),
      skipped: skipped,
      otherTypeCount: otherTypeCount,
    )
  }

  // MARK: Private

  /// A token before its references are followed: the tree walk's output.
  private struct RawToken {
    let path: [String]
    /// `$type` written on the token itself.
    let explicitType: String?
    /// `$type` from the nearest group above it.
    let inheritedType: String?
    let value: Any
    let description: String

    var name: String {
      path.joined(separator: ".")
    }
  }

  /// A token after its references are followed.
  private struct ResolvedToken {
    let value: Any
    /// The effective `$type`, by the format's precedence: the token's own, else the one
    /// the reference resolved to, else the nearest group's.
    let type: String?
  }

  // MARK: - Walking

  /// Collects every token in the tree, keyed by dotted path.
  ///
  /// The rule for telling a token from a group is the format's own and is pleasantly
  /// blunt: **an object with a `$value` is a token**, and anything else with children is
  /// a group. Names beginning with `$` are reserved by the format, which is what makes
  /// "everything else is a child" safe.
  private static func collect(
    _ node: [String: Any],
    path: [String],
    inheritedType: String?,
    into raw: inout [String: RawToken],
  ) {
    if let value = node["$value"] {
      let token = RawToken(
        path: path,
        explicitType: node["$type"] as? String,
        inheritedType: inheritedType,
        value: value,
        description: node["$description"] as? String ?? "",
      )
      raw[token.name] = token
      return
    }

    // A group's `$type` applies to everything below it until something says otherwise.
    let groupType = node["$type"] as? String ?? inheritedType
    for (name, child) in node where !name.hasPrefix("$") {
      guard let child = child as? [String: Any] else { continue }
      collect(child, path: path + [name], inheritedType: groupType, into: &raw)
    }
  }

  /// Deterministic order, since there is none to preserve.
  ///
  /// `JSONSerialization` hands back an unordered dictionary, so the document's own
  /// ordering is not available at any price — and a palette's order is load-bearing, for
  /// the reason ``SavedColor/sortIndex`` gives at length. Alphabetical alone would file a
  /// shade ramp as `100, 1000, 50`, so all-digit names compare numerically and everything
  /// else compares as text. That covers the case that matters: a ramp is keyed by number
  /// and nothing else in a token file is.
  private static func isOrderedBefore(_ lhs: [String], _ rhs: [String]) -> Bool {
    for (left, right) in zip(lhs, rhs) where left != right {
      if let leftNumber = Int(left), let rightNumber = Int(right) {
        return leftNumber < rightNumber
      }
      return left < right
    }
    return lhs.count < rhs.count
  }

  // MARK: - References

  /// Follows `$value` references until a concrete value is reached.
  ///
  /// **Resolution happens before the type filter, not after**, because the format's
  /// precedence puts a resolved reference's type *above* the enclosing group's: a token
  /// with no `$type` of its own that aliases a color token is a color token. Filtering
  /// first would drop exactly those, silently.
  ///
  /// `visiting` is what stops a file that defines a token in terms of itself from hanging
  /// the app. It is a cycle *detector*, not an optimization: the shape it catches is
  /// legal JSON and a plausible hand-editing mistake.
  private static func resolve(
    _ token: RawToken,
    in raw: [String: RawToken],
    visiting: inout Set<String>,
  ) -> Result<ResolvedToken, TokenSkipReason> {
    guard visiting.insert(token.name).inserted else {
      return .failure(.aliasCycle(token.name))
    }
    defer { visiting.remove(token.name) }

    guard let reference = reference(in: token.value) else {
      return .success(
        ResolvedToken(value: token.value, type: token.explicitType ?? token.inheritedType),
      )
    }
    guard let target = raw[reference] else {
      return .failure(.unresolvedAlias(reference))
    }
    return resolve(target, in: raw, visiting: &visiting).map { resolved in
      ResolvedToken(
        value: resolved.value,
        type: token.explicitType ?? resolved.type ?? token.inheritedType,
      )
    }
  }

  /// The dotted path a `$value` refers to, in either of the format's two spellings.
  ///
  /// `{color.blue}` is the widespread one; `{"$ref": "#/color/blue/$value"}` is the JSON
  /// Pointer form the current draft adds. Both are supported because they are one lookup
  /// with two spellings — declining the second would mean a file that uses it imports as
  /// empty, and "unsupported alias syntax" is a worse answer than four lines of pointer
  /// unescaping.
  private static func reference(in value: Any) -> String? {
    if let text = value as? String, text.hasPrefix("{"), text.hasSuffix("}") {
      return String(text.dropFirst().dropLast())
    }
    if let object = value as? [String: Any], let pointer = object["$ref"] as? String {
      return path(fromJSONPointer: pointer)
    }
    return nil
  }

  /// `#/color/blue/$value` as `color.blue`.
  ///
  /// The `~1` → `/` and `~0` → `~` unescaping is RFC 6901's, in its order, and it is not
  /// hypothetical here: the token format forbids `$`, `{`, `}` and `.` in a name and
  /// permits `/`, so a pointer segment genuinely can carry an escape.
  private static func path(fromJSONPointer pointer: String) -> String? {
    var segments = pointer.split(separator: "/", omittingEmptySubsequences: false).map {
      $0.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
    }
    guard segments.first == "#" || segments.first == "" else { return nil }
    segments.removeFirst()
    if segments.last == "$value" {
      segments.removeLast()
    }
    return segments.isEmpty ? nil : segments.joined(separator: ".")
  }

  // MARK: - Colors

  /// One `$value` object as a color.
  ///
  /// `hex` is a *fallback*, not the value: it is consulted only when `colorSpace` names
  /// something this build cannot construct, which mirrors how ``ColorRecord/colorValue``
  /// treats a stored space it does not recognize. A known space with unreadable
  /// components is a broken token and is reported as one — falling back to `hex` there
  /// would quietly substitute a 6-digit sRGB approximation for a wide-gamut color and say
  /// so nowhere.
  private static func color(from value: Any) -> Result<ColorValue, TokenSkipReason> {
    guard let object = value as? [String: Any] else {
      return .failure(.malformedValue("expected an object with a “colorSpace” and “components”"))
    }
    guard let identifier = object["colorSpace"] as? String else {
      return .failure(.malformedValue("no “colorSpace”"))
    }

    let alpha: Double
    var missing: ComponentMask = []
    switch object["alpha"] {
    case nil:
      // "When omitted, the alpha value MUST be assumed to be 1."
      alpha = 1
    case let written as NSNumber:
      // Clamped, where the three components are not — the parser's rule, restated: there
      // is nothing beyond fully opaque, while an out-of-gamut color has to stay writable.
      alpha = min(max(written.doubleValue, 0), 1)
    case let keyword as String where keyword.lowercased() == "none":
      // Leniency: the module describes alpha as a number, but `none` has exactly one
      // reading in CSS and rejecting it would help nobody.
      alpha = 1
      missing.insert(.alpha)
    default:
      return .failure(.malformedValue("“alpha” is not a number"))
    }

    guard let space = ColorSpace(rawValue: identifier) else {
      guard let hex = object["hex"] as? String,
            let parsed = try? CSSColorParser.parse(hex).color
      else {
        return .failure(.unknownColorSpace(identifier))
      }
      return .success(ColorValue(
        space: parsed.space,
        components: parsed.components,
        alpha: alpha,
        missing: missing,
      ))
    }

    guard let written = object["components"] as? [Any], written.count == 3 else {
      return .failure(.malformedValue("“components” is not three values"))
    }

    var components = SIMD3<Double>()
    for index in 0 ..< 3 {
      switch written[index] {
      case let number as NSNumber:
        components[index] = number.doubleValue
      case let keyword as String where keyword.lowercased() == "none":
        // The same pair the parser writes for a CSS `none`: zero in the slot, and the
        // fact that it is absent in the mask. Deliberately *not* followed by
        // `markingPowerlessComponents()` — that is an interpolation step and it blanks
        // what it flags, where this is a value being read in.
        components[index] = 0
        missing.insert(.component(index))
      default:
        return .failure(.malformedValue("component \(index + 1) is neither a number nor “none”"))
      }
    }

    return .success(ColorValue(
      space: space,
      components: components,
      alpha: alpha,
      missing: missing,
    ))
  }

  // MARK: - Keys

  /// Assigns each token the key it will be exported under: its path, sanitized, and made
  /// unique.
  ///
  /// **The uniquing is against the *sanitized* key, and that is the whole point.** Paths
  /// are unique by construction, so it is tempting to conclude the keys are too — but
  /// `-` is a legal name character and `.` is not, so `brand.500` and `brand-500` are two
  /// distinct, legal tokens that ``ExportOptions/cssIdentifier(_:fallback:)`` maps onto
  /// one identifier. Two entries sharing a key do not produce a duplicate property; they
  /// produce a *single* one, and a color disappears from the export with nothing in the
  /// document to say so. Same rule, and same `-2` suffix, as
  /// ``ProjectLibrary/paletteKeys(for:)``.
  ///
  /// The key is the **whole path**, not the token's own name. `brand.500` and
  /// `accent.500` would otherwise collide into `500` and `500-2`, which is a worse answer
  /// than a long name: the suffix says nothing about which family it came from.
  private static func keyed(
    _ colors: [(path: [String], color: ColorValue, description: String)],
  ) -> [DesignToken] {
    var used: Set<String> = []
    return colors.enumerated().map { index, entry in
      var key = ExportOptions.cssIdentifier(
        entry.path.joined(separator: "."),
        fallback: String(index + 1),
      )
      if used.contains(key) {
        var suffix = 2
        while used.contains("\(key)-\(suffix)") {
          suffix += 1
        }
        key = "\(key)-\(suffix)"
      }
      used.insert(key)
      return DesignToken(
        path: entry.path,
        key: key,
        color: entry.color,
        description: entry.description,
      )
    }
  }
}
