//
//  PaletteImportTests.swift
//  ColorKitTests
//

@testable import ColorKit
import Foundation
import Testing

/// Reading a pasted document back into groups, keys and colors.
///
/// **The round trip is the oracle**, the same standard `Export/` is held to: render a
/// document with `ExportOptions.render`, parse it back, and require the same groups, keys
/// and colors to come out. No output string is pinned here — that claim already belongs
/// to `ExportShapeTests` and `GroupedExportTests` — so this file is free to change either
/// side without re-typing syntax.
@Suite("Palette import")
struct PaletteImportTests {
  // MARK: Internal

  static let blue = ColorValue.srgb8(0x3B, 0x82, 0xF6)
  static let red = ColorValue.srgb8(0xEF, 0x44, 0x44)

  // MARK: - Detection

  @Test("Every export shape is detected from its own output", arguments: [
    ExportShape.customProperties, .declaration, .json, .tailwindTheme, .tailwindConfig,
  ])
  func detectsItsOwnExportShapes(shape: ExportShape) {
    var options = ExportOptions.default
    options.shape = shape
    let document = options.render([PaletteEntry(key: "500", color: Self.blue)], formatting: .lossless)

    #expect(PaletteImport.detect(document) == Self.importShape(for: shape))
  }

  /// `p3WithFallback` on its own: it needs the wide color out of sRGB or the shape's own
  /// `@media` marker is still present regardless, but keeping the fixture consistent with
  /// the shape's actual purpose is worth it.
  @Test("p3WithFallback is detected from its own output")
  func detectsP3WithFallback() {
    var options = ExportOptions.default
    options.shape = .p3WithFallback
    let document = options.render([PaletteEntry(key: "500", color: Self.blue)], formatting: .lossless)
    #expect(PaletteImport.detect(document) == .p3WithFallback)
  }

  @Test("A design token document is detected by its $value")
  func detectsDesignTokens() {
    let text = #"""
    { "brand": { "$type": "color", "500": { "$value": {
      "colorSpace": "srgb", "components": [0.5, 0.5, 0.5] } } } }
    """#
    #expect(PaletteImport.detect(text) == .designTokens)
  }

  @Test("A JSON object with no $value is the json shape")
  func detectsPlainJSON() {
    #expect(PaletteImport.detect(##"{"brand": "#3b82f6"}"##) == .json)
  }

  @Test("Order matters: @theme is recognized ahead of the JSON and declaration checks")
  func tailwindThemeTakesPriority() {
    let text = "@theme {\n  --color-brand-500: #3b82f6;\n}"
    #expect(PaletteImport.detect(text) == .tailwindTheme)
  }

  @Test("Freeform text with no structure at all is loose colors")
  func detectsLooseColors() {
    #expect(PaletteImport.detect("red, blue, oklch(0.7 0.2 140)") == .looseColors)
  }

  // MARK: - Segment-wise family extraction

  /// The case that discriminates segment-wise extraction from character-wise: `primary`
  /// and `primar` share seven raw characters and zero hyphen segments. A character-wise
  /// prefix would collapse them into `primar`, a family nothing in the document named.
  @Test("Family extraction is segment-wise, not character-wise")
  func familyExtractionIsSegmentWise() throws {
    let text = """
    :root {
      --primary-100: #3b82f6;
      --primar-200: #ef4444;
    }
    """
    let imported = try PaletteImport.parse(text, as: .customProperties)
    // No shared *segment* prefix, so each property becomes its own single-entry group —
    // the inverse of M20's loose-color rule — rather than one bogus "primar" family.
    #expect(imported.groups.count == 2)
    #expect(Set(imported.groups.map(\.name)) == ["primary-100", "primar-200"])
    for group in imported.groups {
      #expect(group.entries.count == 1)
      #expect(group.entries[0].key.isEmpty)
    }
  }

  @Test("A genuine shared segment prefix becomes the family, with the rest as keys")
  func sharedSegmentPrefixBecomesFamily() throws {
    let text = """
    :root {
      --primary-100: #3b82f6;
      --primary-200: #ef4444;
    }
    """
    let imported = try PaletteImport.parse(text, as: .customProperties)
    #expect(imported.groups.count == 1)
    let group = try #require(imported.groups.first)
    #expect(group.name == "primary")
    #expect(Set(group.entries.map(\.key)) == ["100", "200"])
  }

  // MARK: - Round trip, every export shape, both cardinalities

  @Test(
    "A lone color round-trips through every shape",
    arguments: [
      ExportShape.customProperties, .declaration, .json, .tailwindTheme, .tailwindConfig,
    ],
  )
  func loneColorRoundTrips(shape: ExportShape) throws {
    var options = ExportOptions.default
    options.shape = shape
    options.name = "brand"
    let document = options.render([PaletteEntry(color: Self.blue)], formatting: .lossless)

    let imported = try PaletteImport.parse(document, as: Self.importShape(for: shape))
    let group = try #require(imported.groups.first, "No group parsed from:\n\(document)")
    #expect(imported.groups.count == 1)
    let entry = try #require(group.entries.first)
    #expect(entry.key.isEmpty)
    #expect(entry.color.deltaEOK(to: Self.blue) < 1e-6)
  }

  @Test(
    "A two-group document round-trips through every shape",
    arguments: [
      ExportShape.customProperties, .declaration, .json, .tailwindTheme, .tailwindConfig,
    ],
  )
  func twoGroupsRoundTrip(shape: ExportShape) throws {
    var options = ExportOptions.default
    options.shape = shape
    let groups = [
      PaletteGroup(name: "primary", entries: [
        PaletteEntry(key: "500", color: Self.blue),
        PaletteEntry(key: "600", color: Self.red),
      ]),
      PaletteGroup(name: "secondary", entries: [PaletteEntry(key: "500", color: Self.red)]),
    ]
    let document = options.render(groups, formatting: .lossless)

    let imported = try PaletteImport.parse(document, as: Self.importShape(for: shape))
    #expect(imported.groups.count == 2)

    let primary = try #require(imported.groups.first { $0.name == "primary" })
    #expect(primary.entries.count == 2)
    let primary500 = try #require(primary.entries.first { $0.key == "500" })
    let primary600 = try #require(primary.entries.first { $0.key == "600" })
    #expect(primary500.color.deltaEOK(to: Self.blue) < 1e-6)
    #expect(primary600.color.deltaEOK(to: Self.red) < 1e-6)

    let secondary = try #require(imported.groups.first { $0.name == "secondary" })
    #expect(secondary.entries.count == 1)
    #expect(secondary.entries[0].key == "500")
    #expect(secondary.entries[0].color.deltaEOK(to: Self.red) < 1e-6)
  }

  /// The group-name comparison above is against the *sanitized* identifier
  /// (`ExportOptions.resolvedGroups`), not the original `PaletteGroup.name` — worth its
  /// own case, since a name containing something the sanitizer removes would otherwise
  /// pass the fixture above by accident.
  ///
  /// Two entries, not one: a single-group document with exactly one *keyed* property and
  /// no header (`--My-Brand-500`) is genuinely ambiguous on its own — nothing says
  /// whether `500` is a key or the last segment of the family's own name — so this needs
  /// a second property sharing the family for `commonFamily` to have anything to infer
  /// the boundary from.
  @Test("A sanitized group name round-trips as the sanitized form")
  func sanitizedGroupNameRoundTrips() throws {
    var options = ExportOptions.default
    options.shape = .customProperties
    let groups = [
      PaletteGroup(name: "My Brand!", entries: [
        PaletteEntry(key: "500", color: Self.blue),
        PaletteEntry(key: "600", color: Self.red),
      ]),
    ]
    let document = options.render(groups, formatting: .lossless)
    let imported = try PaletteImport.parse(document, as: .customProperties)
    #expect(imported.groups.map(\.name) == ["My-Brand"])
  }

  // MARK: - p3WithFallback reads the override, not the fallback

  /// A pure Display P3 green: outside sRGB, so hex `cannotRepresentOutOfGamut` and would
  /// round it away. Reading the fallback block here would report a *different* color
  /// than went in; only the `@media` override can carry it exactly.
  @Test("p3WithFallback is read from its @media override, not its hex fallback")
  func p3WithFallbackReadsTheOverride() throws {
    let wide = ColorValue(space: .displayP3, 0.0, 1.0, 0.0)
    var options = ExportOptions.default
    options.shape = .p3WithFallback
    let document = options.render([PaletteEntry(color: wide)], formatting: .lossless)

    let imported = try PaletteImport.parse(document, as: .p3WithFallback)
    let entry = try #require(imported.groups.first?.entries.first)
    #expect(entry.color.deltaEOK(to: wide) < 1e-6)
    // The discriminating check: the fallback block's hex answer is a materially
    // different color, so a correct read cannot be mistaken for a lucky rounding.
    #expect(entry.color.deltaEOK(to: wide.pulledInto(.srgb)) > 1e-2)
  }

  @Test("p3WithFallback covers every group when read back")
  func p3WithFallbackTwoGroups() throws {
    let wide = ColorValue(space: .displayP3, 0.0, 1.0, 0.0)
    var options = ExportOptions.default
    options.shape = .p3WithFallback
    let groups = [
      PaletteGroup(name: "primary", entries: [PaletteEntry(key: "500", color: wide)]),
      PaletteGroup(name: "secondary", entries: [PaletteEntry(key: "500", color: Self.red)]),
    ]
    let document = options.render(groups, formatting: .lossless)

    let imported = try PaletteImport.parse(document, as: .p3WithFallback)
    #expect(imported.groups.count == 2)
    let primary = try #require(imported.groups.first { $0.name == "primary" })
    #expect(primary.entries.first?.color.deltaEOK(to: wide) ?? .infinity < 1e-6)
  }

  // MARK: - Skipped values

  @Test("A malformed value is skipped and reported; its neighbours still import")
  func malformedValueIsSkippedNotFatal() throws {
    let text = """
    :root {
      --brand-500: #3b82f6;
      --brand-600: not-a-color;
      --brand-700: #ef4444;
    }
    """
    let imported = try PaletteImport.parse(text, as: .customProperties)
    let group = try #require(imported.groups.first)
    #expect(group.entries.count == 2)
    #expect(Set(group.entries.map(\.key)) == ["500", "700"])
    #expect(imported.skipped.count == 1)
    #expect(imported.skipped[0].message.contains("not-a-color"))
  }

  @Test("An empty paste throws rather than returning an empty palette")
  func emptyPasteThrows() {
    #expect(throws: PaletteImportError.empty) {
      try PaletteImport.parse("   \n  ", as: .looseColors)
    }
  }

  // MARK: - looseColors

  @Test("A single loose color is a lone color, not a scale of one")
  func singleLooseColorHasNoKey() throws {
    let imported = try PaletteImport.parse("#3b82f6", as: .looseColors)
    let group = try #require(imported.groups.first)
    #expect(group.entries.count == 1)
    #expect(group.entries[0].key.isEmpty)
  }

  @Test("Several loose colors get sequential positional keys")
  func multipleLooseColorsGetPositionalKeys() throws {
    let imported = try PaletteImport.parse("#3b82f6, #ef4444, oklch(0.7 0.2 140)", as: .looseColors)
    let group = try #require(imported.groups.first)
    #expect(group.entries.map(\.key) == ["1", "2", "3"])
  }

  @Test("A function call's internal commas are not separators")
  func functionCallCommasAreNotSeparators() throws {
    // color-mix's own grammar has commas at the top level *inside* one color value —
    // exactly the shape a naive comma split would misread as three colors. The count
    // alone does not discriminate: splitting on every comma regardless of depth breaks
    // this into four candidates ("color-mix(in oklch", "red", "blue)", "#3b82f6"), two
    // of which happen to parse as colors on their own — "red" and "#3b82f6" — so a
    // wrong split still reports `entries.count == 2`. Asserting the first entry's own
    // text is what actually tells a correct split from a coincidentally-sized wrong one.
    let text = "color-mix(in oklch, red, blue), #3b82f6"
    let imported = try PaletteImport.parse(text, as: .looseColors)
    let group = try #require(imported.groups.first)
    #expect(imported.skipped.isEmpty, "Skipped: \(imported.skipped)")
    #expect(group.entries.count == 2)
    #expect(group.entries.first?.text == "color-mix(in oklch, red, blue)")
  }

  // MARK: - designTokens delegation

  @Test("designTokens delegates to DesignTokenImport and keeps the description as notes")
  func designTokensDelegates() throws {
    let text = #"""
    { "color": { "$type": "color", "brand": { "500": { "$description": "Primary brand color",
      "$value": { "colorSpace": "srgb", "components": [0.231, 0.51, 0.965] } } } } }
    """#
    let imported = try PaletteImport.parse(text, as: .designTokens)
    let entry = try #require(imported.groups.first?.entries.first)
    #expect(entry.notes == "Primary brand color")
    #expect(entry.color.deltaEOK(to: ColorValue(space: .srgb, 0.231, 0.51, 0.965)) < 1e-6)
  }

  @Test("A broken token is skipped, not fatal to the rest of the file")
  func designTokensSkipsBrokenEntries() throws {
    let text = #"""
    { "color": { "$type": "color",
      "good": { "$value": { "colorSpace": "srgb", "components": [0.5, 0.5, 0.5] } },
      "bad": { "$value": { "colorSpace": "not-a-space" } } } }
    """#
    let imported = try PaletteImport.parse(text, as: .designTokens)
    let allEntries = imported.groups.flatMap(\.entries)
    #expect(allEntries.count == 1)
    #expect(imported.skipped.count == 1)
  }

  // MARK: - M30: a single color imports as a color

  /// A **recorded artifact**, not a self-consistent round trip: `Fixtures/
  /// project-export-p3-with-fallback.css` is a real document this app produced — exported
  /// by Parker from a real project on 2026-08-09 and the artifact that prompted M30, not a
  /// string hand-written to match what the parser already does. That is why it earns its
  /// place beside a render-then-parse test: it catches the one failure a round trip
  /// structurally cannot, both halves drifting *together* and still agreeing.
  ///
  /// **Do not re-export this file to make it agree.** Unlike the five machine-generated
  /// fixtures (CLAUDE.md's "regenerate, never hand-edit"), this one is the opposite: the
  /// moment it stops matching what a newer exporter writes is the moment it has something
  /// to say. A disagreement here is a finding, not stale data.
  ///
  /// It reads as `p3WithFallback` (the `@media (color-gamut` test runs before `:root {`),
  /// so only the `@media` override block is read — the imported values are the
  /// `color(display-p3 …)` spellings, never the lossy hex fallback above them. Three
  /// palettes of eleven, seven loose colors. Two honest limitations, stated here rather
  /// than discovered: the seven colors come back named after the **sanitized** header
  /// (`cssIdentifier` is lossy and has no inverse — M17's limitation, and what M32 exists
  /// to repair), and their values are Display P3 rounded to the export's precision, not
  /// the original hex.
  @Test("A real project export splits into loose colors and palettes")
  func projectExportSplitsColorsFromPalettes() throws {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .appendingPathComponent("Fixtures/project-export-p3-with-fallback.css")
    let document = try String(contentsOf: url, encoding: .utf8)

    #expect(PaletteImport.detect(document) == .p3WithFallback)
    let imported = try PaletteImport.parse(document, as: .p3WithFallback)

    let colors = imported.groups.filter { $0.soleColor != nil }
    let palettes = imported.groups.filter { $0.soleColor == nil }
    #expect(colors.count == 7)
    #expect(palettes.count == 3)

    // The three palettes keep their names and all eleven stops — `Primary-Base` is a
    // separate loose color and must **not** be absorbed into the `Primary` family, which
    // naive prefix inference would do. A header is authoritative over segment inference.
    #expect(Set(palettes.map(\.name)) == ["Greyscale", "Primary", "Accent"])
    for palette in palettes {
      #expect(palette.entries.count == 11, "\(palette.name) had \(palette.entries.count) entries")
    }

    // The seven come back named after the sanitized header, empty-keyed.
    #expect(Set(colors.map(\.name)) == [
      "Primary-Base", "Backgound", "Body-Text-Base", "Body-Text-Callout",
      "Body-Text-Callout-Strong", "Body-Text-Accent", "Body-Text-Accent-Strong",
    ])

    // The override block was read, not the hex fallback: every stored text is a
    // `color(display-p3 …)` spelling. A `.derived(_:preferring:)` regression in the save
    // door — or reading the hex block here — fails this immediately.
    for color in colors {
      let entry = try #require(color.soleColor)
      #expect(entry.key.isEmpty)
      #expect(
        entry.text.hasPrefix("color(display-p3"),
        "\(color.name) stored \(entry.text), not a P3 override spelling",
      )
    }
  }

  /// The opposite failure from the fixture above: the two halves disagreeing *today*. A
  /// project export holding one loose color **and** one one-entry palette, rendered and
  /// parsed back — the only test of the pair that discriminates the palette-of-one case,
  /// since the fixture has no one-entry palette in it. Asserting only that loose colors
  /// survive would pass under the naive `count == 1` rule, the lesson `json` and
  /// `tailwindConfig` taught at both cardinalities in M8.
  ///
  /// `.declaration` and `.tailwindTheme` are left out on purpose, not by oversight: the
  /// first derives keys through the trailing `/* key */` comment and the second strips a
  /// `color-` namespace, and neither is obviously safe for a mixed empty-key/keyed
  /// multi-group document — a claim for its own milestone, not to be forced here.
  @Test(
    "A loose color and a one-entry palette come back as one of each",
    arguments: [ExportShape.customProperties, .json, .tailwindConfig],
  )
  func looseColorAndOneEntryPaletteRoundTrip(shape: ExportShape) throws {
    var options = ExportOptions.default
    options.shape = shape
    let groups = [
      // Empty key: a loose color, `soleEntry`/`soleColor`'s "this is a color" signal.
      PaletteGroup(name: "brand", entries: [PaletteEntry(color: Self.blue)]),
      // A real key: a palette of one, which must stay a palette.
      PaletteGroup(name: "ramp", entries: [PaletteEntry(key: "1", color: Self.red)]),
    ]
    let document = options.render(groups, formatting: .lossless)

    let imported = try PaletteImport.parse(document, as: Self.importShape(for: shape))
    let colors = imported.groups.filter { $0.soleColor != nil }
    let palettes = imported.groups.filter { $0.soleColor == nil }

    #expect(colors.map(\.name) == ["brand"], "from:\n\(document)")
    #expect(palettes.map(\.name) == ["ramp"], "from:\n\(document)")
    #expect(colors.first?.soleColor?.color.deltaEOK(to: Self.blue) ?? .infinity < 1e-6)
    #expect(palettes.first?.entries.first?.key == "1")
  }

  // MARK: Private

  private static func importShape(for shape: ExportShape) -> ImportShape {
    switch shape {
    case .customProperties: .customProperties
    case .declaration: .declaration
    case .json: .json
    case .tailwindTheme: .tailwindTheme
    case .tailwindConfig: .tailwindConfig
    case .p3WithFallback: .p3WithFallback
    }
  }
}
