import Foundation

/// The CLI's own vocabulary: the words a caller types for things ColorCore models.
///
/// This is the CLI's half of the layering rule the app already follows — ColorCore owns
/// facts, a front end owns the words for them. The app's `FormatPresentation` names the
/// same formats "Hex" and "OKLCH" because it is drawing a menu; these are *identifiers*
/// typed into a shell, so they are lowercase, hyphenated and stable. Two front ends
/// legitimately hold two tables; what neither may do is reach into the other's.
///
/// Most of these are not tables at all, because most of the types already carry raw
/// values that *are* CSS identifiers — `Harmony`, `ExportShape`, `ExportTemplate`,
/// `ColorVisionDeficiency`, `ColorSpace`. Deriving from those is the same call
/// `ColorGrammar.interpolationSpace(named:)` makes, and for the same reason: there is
/// no fact a derivation could lose. The two hand-written tables below are the two types
/// with nothing to derive from.
enum Names {
  // MARK: Internal

  // MARK: Contrast requirements

  /// What a caller types for a `ContrastRequirement`, and how it is printed.
  ///
  /// One of the two hand-written tables: `ContrastRequirement` has no raw value, and
  /// giving it one in ColorCore would be putting a front end's spelling in the core.
  /// The spec *criterion* number beside each one is a fact and does come from core.
  static let requirements: [(name: String, label: String, requirement: ContrastRequirement)] = [
    ("aa", "AA normal text", .aaNormalText),
    ("aa-large", "AA large text", .aaLargeText),
    ("aaa", "AAA normal text", .aaaNormalText),
    ("aaa-large", "AAA large text", .aaaLargeText),
    ("non-text", "Non-text", .nonText),
  ]

  /// What a caller types for an `ExportShape`.
  ///
  /// The second hand-written table, and the reason is worth stating because every
  /// neighbouring type *is* derived from its raw values. `ExportShape`'s raw values are
  /// internal identifiers — `Identifiable` conformance and nothing more — and they are
  /// not uniform: three carry an explicit hyphenated string, three fall back to their
  /// case names, and one of those, `customProperties`, is camelCase. Deriving would put
  /// `--shape customProperties` next to `--shape p3-with-fallback` on one command line.
  /// Splitting that one mechanically would work today and is the trap `channelKeywords`
  /// warns about: those raw values answer to SwiftUI, not to this CLI, and a rename
  /// there would silently change the spelling a shell script depends on.
  static let shapes: [(name: String, shape: ExportShape)] = [
    ("declaration", .declaration),
    ("custom-properties", .customProperties),
    ("json", .json),
    ("tailwind-theme", .tailwindTheme),
    ("tailwind-config", .tailwindConfig),
    ("p3-with-fallback", .p3WithFallback),
  ]

  static var formatList: String {
    list(CSSOutputFormat.catalog.map(name(for:)))
  }

  static var requirementList: String {
    list(requirements.map(\.name))
  }

  static var harmonyList: String {
    list(Harmony.allCases.map(\.rawValue))
  }

  static var shapeList: String {
    list(shapes.map(\.name))
  }

  static var templateList: String {
    list(ExportTemplate.allCases.map(\.rawValue))
  }

  static var deficiencyList: String {
    list(ColorVisionDeficiency.allCases.map(\.rawValue))
  }

  static var spaceList: String {
    list(ColorSpace.allCases.map(\.rawValue))
  }

  // MARK: Formats

  /// What a caller types for a `CSSOutputFormat`.
  ///
  /// The `color()` formats are named by their space's raw value, which *is* the CSS
  /// identifier inside `color(…)`. Note `rgb` and `srgb` are different formats and
  /// different words — `rgb(255 0 0)` against `color(srgb 1 0 0)`.
  static func name(for format: CSSOutputFormat) -> String {
    switch format {
    case .hex: "hex"
    case .keyword: "keyword"
    case .rgb: "rgb"
    case .hsl: "hsl"
    case .hwb: "hwb"
    case .lab: "lab"
    case .lch: "lch"
    case .oklab: "oklab"
    case .oklch: "oklch"
    case let .color(space): space.rawValue
    }
  }

  /// Inverted from ``name(for:)`` over the catalog rather than transcribed a second
  /// time, so the two cannot disagree and a format added to the catalog is reachable
  /// the moment it is named.
  static func format(named name: String) -> CSSOutputFormat? {
    CSSOutputFormat.catalog.first { Self.name(for: $0) == name }
  }

  static func requirement(named name: String) -> ContrastRequirement? {
    requirements.first { $0.name == name }?.requirement
  }

  static func label(for requirement: ContrastRequirement) -> String {
    requirements.first { $0.requirement == requirement }?.label ?? ""
  }

  // MARK: Everything else

  static func harmony(named name: String) -> Harmony? {
    Harmony(rawValue: name)
  }

  static func shape(named name: String) -> ExportShape? {
    shapes.first { $0.name == name }?.shape
  }

  static func name(for shape: ExportShape) -> String {
    shapes.first { $0.shape == shape }?.name ?? shape.rawValue
  }

  static func template(named name: String) -> ExportTemplate? {
    ExportTemplate(rawValue: name)
  }

  static func deficiency(named name: String) -> ColorVisionDeficiency? {
    ColorVisionDeficiency(rawValue: name)
  }

  static func space(named name: String) -> ColorSpace? {
    ColorSpace(rawValue: name)
  }

  // MARK: Private

  private static func list(_ names: [String]) -> String {
    names.joined(separator: ", ")
  }
}
