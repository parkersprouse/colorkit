//
//  FormatCatalogTests.swift
//  ColorKitTests
//

@testable import ColorKit
import Foundation
import Testing

/// The catalog is what the conversion panel renders, so these tests stand in for the
/// UI checks that cannot be automated here: if every catalog entry produces a string
/// that re-parses to the same color, and every badge agrees with the string beside
/// it, then the panel is showing the truth even though nothing has looked at it.
@Suite("Format catalog")
struct FormatCatalogTests {
  // MARK: Internal

  // MARK: - Coverage

  @Test("An ordinary color offers every format but a keyword")
  func catalogCoverage() {
    // #3b82f6 has no keyword, so it exercises the one format that can decline.
    let blue = ColorValue.srgb8(59, 130, 246)
    let formats = blue.allFormats()

    #expect(formats.count == CSSOutputFormat.catalog.count - 1)
    #expect(!formats.contains { $0.format == .keyword })
    #expect(formats.allSatisfy { !$0.css.isEmpty })
  }

  @Test("A named color offers the keyword too")
  func keywordAppearsWhenItExists() throws {
    let purple = try #require(ColorValue.named("rebeccapurple"))
    let keyword = try #require(purple.allFormats().first { $0.format == .keyword })

    #expect(keyword.css == "rebeccapurple")
    #expect(purple.allFormats().count == CSSOutputFormat.catalog.count)
  }

  // MARK: - Round-trip

  /// Serializing then re-parsing must land back on the same color. This is the
  /// property that makes a copy button trustworthy: what lands on the clipboard has
  /// to mean what the panel showed.
  @Test(
    "Every format re-parses to the color it was written from",
    arguments: [
      ColorValue.srgb8(59, 130, 246),
      ColorValue.srgb8(0, 0, 0),
      ColorValue.srgb8(255, 255, 255),
      ColorValue.srgb8(220, 38, 38, alpha: 0.4),
      ColorValue(space: .oklch, 0.7, 0.15, 250),
      ColorValue(space: .lab, 62.2, -34.9, 47.6),
    ],
  )
  func roundTrip(color: ColorValue) throws {
    // Full precision: the panel's default of 4 decimals is a display choice, and
    // asserting round-trips through it would only be measuring rounding.
    let options = CSSFormatOptions(precision: 12)

    for formatted in color.allFormats(options: options) {
      let reparsed = try CSSColorParser.parse(formatted.css).color

      // Compared in OKLab because the two colors live in different spaces by
      // construction; deltaEOK asks the only question that matters — whether
      // anyone could tell them apart.
      let difference = reparsed.deltaEOK(to: color)

      #expect(
        difference < Self.tolerance(for: formatted),
        // Named by the raw case, not by any UI label: this suite tests
        // ColorCore, and reaching into the presentation layer for a string
        // would couple the two in the one direction the layering forbids.
        "\(formatted.format) → \(formatted.css) → ΔEOK \(difference)",
      )
      #expect(abs(reparsed.alpha - color.alpha) < 1e-9)
    }
  }

  // MARK: - The gamut badge

  /// The badge and the string it labels come from one predicate. These pin the
  /// consequence: a `true` badge means the value really was moved, and a `false`
  /// badge means it really was not.
  /// Gamut membership per color, verified against colorjs.io before being written
  /// down. The expectations here are *facts about these two colors*, not a ranking
  /// of spaces by width — see ``badgeFollowsTheColorNotTheSpaceOrdering``.
  @Test(
    "The badge marks exactly the formats that cannot hold the color",
    arguments: [
      // A green so vivid only ProPhoto contains it.
      (
        color: ColorValue(space: .oklch, 0.9, 0.3, 140),
        mapped: [
          CSSOutputFormat.hex, .rgb, .hsl, .hwb,
          .color(.srgb), .color(.srgbLinear),
          .color(.displayP3), .color(.rec2020), .color(.a98RGB),
        ] as [CSSOutputFormat],
        intact: [CSSOutputFormat.color(.proPhotoRGB)] as [CSSOutputFormat],
      ),
      // A red outside sRGB and A98 but comfortably inside P3.
      (
        color: ColorValue(space: .oklch, 0.62, 0.26, 29.23),
        mapped: [
          CSSOutputFormat.hex, .rgb, .hsl, .hwb,
          .color(.srgb), .color(.srgbLinear), .color(.a98RGB),
        ] as [CSSOutputFormat],
        intact: [
          CSSOutputFormat.color(.displayP3), .color(.rec2020),
          .color(.proPhotoRGB),
        ] as [CSSOutputFormat],
      ),
    ],
  )
  func badgeMarksBoundedFormatsOnly(
    color: ColorValue,
    mapped: [CSSOutputFormat],
    intact: [CSSOutputFormat],
  ) throws {
    let byFormat = Dictionary(
      uniqueKeysWithValues: color.allFormats().map { ($0.format, $0) },
    )

    for format in mapped {
      #expect(
        try #require(byFormat[format]).isGamutMapped,
        "\(format) cannot hold this color and should be badged",
      )
    }

    // Unbounded spaces have no gamut to leave, so nothing was ever given up.
    let unbounded: [CSSOutputFormat] = [
      .oklch, .oklab, .lch, .lab, .color(.xyzD65), .color(.xyzD50),
    ]
    for format in intact + unbounded {
      #expect(
        try !#require(byFormat[format]).isGamutMapped,
        "\(format) holds this color exactly and should not be badged",
      )
    }
  }

  /// Wide-gamut spaces do not nest. A98 RGB is "wider" than sRGB by area yet fails
  /// to contain a color Rec.2020 holds easily, because containment follows the
  /// chromaticity triangle. Any shortcut that ranks spaces and skips the check
  /// would badge this row wrongly.
  @Test("Gamut membership follows the color, not an ordering of spaces")
  func badgeFollowsTheColorNotTheSpaceOrdering() throws {
    let p3Green = ColorValue(space: .displayP3, 0, 1, 0)
    let byFormat = Dictionary(
      uniqueKeysWithValues: p3Green.allFormats().map { ($0.format, $0) },
    )

    #expect(try #require(byFormat[.color(.a98RGB)]).isGamutMapped)
    #expect(try !#require(byFormat[.color(.rec2020)]).isGamutMapped)
  }

  @Test("An in-gamut color badges nothing")
  func inGamutColorHasNoBadges() {
    let blue = ColorValue.srgb8(59, 130, 246)
    #expect(blue.allFormats().allSatisfy { !$0.isGamutMapped })
  }

  /// The reason the badge carries a tolerance while serialization does not.
  ///
  /// `#ff0000` routed through Lab and back lands a hair outside the sRGB cube. That
  /// is float residue, not a color the screen cannot show, and reporting it as
  /// out of gamut would put a warning on the most ordinary red there is.
  @Test("Float residue from a round trip is not reported as out of gamut")
  func conversionNoiseDoesNotBadge() throws {
    let red = ColorValue.srgb8(255, 0, 0).converted(to: .lab)
    let backInSRGB = red.converted(to: .srgb)

    // Establish that the premise is real: strict membership rejects it.
    let strictlyOutside = (0 ..< 3).contains {
      backInSRGB.components[$0] < 0 || backInSRGB.components[$0] > 1
    }

    if strictlyOutside {
      #expect(red.isGamutMapped(as: .hex)) // no tolerance
      #expect(!red.isGamutMapped(as: .hex, epsilon: ColorValue.gamutNoiseTolerance))
    }

    // Either way, the panel must not badge it.
    #expect(try !#require(red.formatted(as: .hex)).isGamutMapped)
    #expect(try #require(red.formatted(as: .hex)).css == "#ff0000")
  }

  @Test("Preserving out-of-gamut values reports no mapping, because none happened")
  func preservePolicySuppressesTheBadge() throws {
    let vivid = ColorValue(space: .oklch, 0.9, 0.3, 140)
    let options = CSSFormatOptions(gamut: .preserve)

    let rgb = try #require(vivid.formatted(as: .rgb, options: options))
    #expect(!rgb.isGamutMapped)
    // rgb() accepts out-of-range numbers syntactically, so the authored value
    // survives intact — that is what `.preserve` is for.
    #expect(rgb.css.contains("-") || rgb.css.contains("2"))

    // hex still has to map: there is no spelling for a negative channel.
    let hex = try #require(vivid.formatted(as: .hex, options: options))
    #expect(hex.isGamutMapped)
  }

  // MARK: - Web-friendly mode (M22)

  @Test("webFriendly is a subset of the full catalog")
  func webFriendlyIsASubsetOfCatalog() {
    #expect(Set(CSSOutputFormat.webFriendly).isSubset(of: Set(CSSOutputFormat.catalog)))
  }

  /// Every web-friendly format can hold any in-gamut sRGB color exactly — the
  /// property "hand-authorable and sRGB-safe" actually cashes out to.
  @Test("Every web-friendly format holds an sRGB color without mapping it")
  func webFriendlyFormatsAreSRGBExpressible() {
    let blue = ColorValue.srgb8(59, 130, 246)
    for format in CSSOutputFormat.webFriendly {
      #expect(
        !blue.isGamutMapped(as: format),
        "\(format) mapped an ordinary sRGB color, so it cannot be sRGB-safe",
      )
    }
  }

  /// The discriminating case the table exists for. `color(srgb …)` is fully inside
  /// sRGB, so a rule derived from gamut membership (`if case .color` excluded, say)
  /// would let it through by accident; it stays excluded because nobody hand-authors
  /// the `color()` family, which a table can say and a predicate cannot.
  @Test("color(srgb …) is excluded despite being fully inside sRGB")
  func colorSRGBIsExcludedDespiteFittingSRGB() {
    let blue = ColorValue.srgb8(59, 130, 246)
    #expect(!blue.isGamutMapped(as: .color(.srgb)), "premise: color(srgb) really does hold it")
    #expect(!CSSOutputFormat.webFriendly.contains(.color(.srgb)))
  }

  // MARK: - spelling(preferring:allowingWideGamut:) (M22)

  @Test("allowingWideGamut defaults to true, unchanged from before M22")
  func allowingWideGamutDefaultsTrue() {
    let p3Green = ColorValue(space: .displayP3, 0, 1, 0)
    #expect(p3Green.spelling(preferring: .hex) == p3Green.spelling(preferring: .hex, allowingWideGamut: true))
  }

  /// The mutation the plan names by hand: drop this guard, and a color that would
  /// have promoted to `color(display-p3 …)` does so regardless of the flag — putting
  /// exactly the family web-friendly mode hides back into the adopted string.
  @Test("allowingWideGamut: false never promotes to color(display-p3 …)")
  func disallowingWideGamutNeverPromotes() {
    let p3Green = ColorValue(space: .displayP3, 0, 1, 0)
    // Premise: with wide gamut allowed, hex really would promote for this color.
    #expect(p3Green.spelling(preferring: .hex) == .color(.displayP3))

    #expect(p3Green.spelling(preferring: .hex, allowingWideGamut: false) == .hex)
    #expect(p3Green.spelling(preferring: .oklch, allowingWideGamut: false) == .oklch)
  }

  // MARK: Private

  /// How far a round trip may drift before it counts as a defect.
  ///
  /// Three regimes, and conflating them is what makes a round-trip test either
  /// vacuous or permanently red:
  ///
  /// - **Gamut-mapped** values were moved on purpose, by up to one JND.
  /// - **hex** quantizes to 8 bits per channel, so `oklch(0.7 0.15 250)` comes back
  ///   as `#4ba3f7` — off by ~0.0005 ΔEOK no matter how much precision is asked
  ///   for. That is the format working correctly, not losing data unexpectedly.
  /// - **Everything else** is decimal text at 12 places and should be exact.
  private static func tolerance(for formatted: FormattedColor) -> Double {
    if formatted.isGamutMapped {
      return 0.02
    }
    switch formatted.format {
    // Still far below the 0.02 JND, so the assertion keeps its teeth.
    case .hex, .keyword: return 0.005
    default: return 1e-9
    }
  }
}
