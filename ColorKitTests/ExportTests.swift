//
//  ExportTests.swift
//  ColorKitTests
//

@testable import ColorKit
import Foundation
import Testing
import UniformTypeIdentifiers

/// Proof for the export layer, which has an oracle nothing else in `Transform/` had:
/// **this app's own parser**.
///
/// A harmony can only be checked against its defining properties, because no reference
/// implementation has a notion of one. An exported declaration is different — it is CSS,
/// and CSS is exactly what ``CSSColorParser`` reads. So the discriminating test here is a
/// round trip: pull the value back out of the document, parse it, and require the color
/// that comes back to be the color that went in. That single assertion covers the whole
/// chain — format selection, precision plumbing, and the string surgery of every shape —
/// and it fails loudly if any link rounds when it should not.
@Suite("Export round trip")
struct ExportRoundTripTests {
  /// In sRGB and already on the 8-bit grid, so *every* exportable format can name it
  /// exactly. A wide color would be gamut-mapped by hex, and the round trip would then
  /// be measuring the mapper rather than the exporter.
  static let base = ColorValue.srgb8(0x3B, 0x82, 0xF6)

  /// Extracts the value from every `--name: value;` line.
  ///
  /// Not private: ``ExportShapeTests`` reuses it to pull *both* of `p3WithFallback`'s
  /// blocks out at once, which works unchanged because the media block's lines are the
  /// same declarations one indent deeper and this trims before matching.
  static func propertyValues(in document: String) -> [String] {
    document.split(separator: "\n").compactMap { line in
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard trimmed.hasPrefix("--"), trimmed.hasSuffix(";"),
            let colon = trimmed.firstIndex(of: ":")
      else { return nil }
      return String(trimmed[trimmed.index(after: colon)...])
        .dropLast()
        .trimmingCharacters(in: .whitespaces)
    }
  }

  /// Every exportable format survives a trip through a custom-property block.
  ///
  /// Parameterized over the whole catalog rather than spot-checking `oklch()`, because
  /// the formats fail differently: hex quantizes, `color()` uses a different function
  /// name, and the polar spaces are where a wrong per-component precision shows up.
  @Test("A value survives the document", arguments: CSSOutputFormat.exportable)
  func valueRoundTripsThroughACustomPropertyBlock(format: CSSOutputFormat) throws {
    var options = ExportOptions.default
    options.shape = .customProperties
    options.format = format

    let document = options.render([PaletteEntry(color: Self.base)], formatting: .lossless)
    let value = try #require(
      Self.propertyValues(in: document).first,
      "No custom property in:\n\(document)",
    )

    let parsed = try CSSColorParser.parse(value).color

    let original = Self.base.converted(to: .srgb).components
    let returned = parsed.converted(to: .srgb).components
    for index in 0 ..< 3 {
      #expect(
        abs(original[index] - returned[index]) < 1e-7,
        "\(format) round-tripped \(original) to \(returned) via \(value)",
      )
    }
  }

  /// Precision reaches every shape, at both cardinalities.
  ///
  /// This is the mutation check made permanent. Swap `.lossless` for `.default` anywhere
  /// a shape renders and the exact string stops appearing, so a shape that quietly
  /// ignored its `formatting` argument — the easiest mistake to make when there are seven
  /// of them and they were written one after another — cannot pass.
  ///
  /// **Both a lone color and a palette**, because `json` and `tailwindConfig` fork on
  /// exactly that: a single color is a bare string and a scale is a nested object, which
  /// are two separate render paths. A single-entry-only version of this test passed
  /// against a deliberately broken multi-entry branch, which is how that came to light.
  ///
  /// **The format asserted is the one the shape actually writes, not the one set.**
  /// `p3WithFallback` ignores `format` and fixes its own two, so the claim has to be made
  /// against one of those — and it has to be the wide one, because **hex is
  /// precision-invariant**. Reading the fallback block would leave this test unable to
  /// fail, and the `lossless != coarse` guard below could not catch that, since the guard
  /// is computed from whatever is chosen here.
  ///
  /// **`designTokens` (M34) is a third branch, not a shoehorned fourth case of the
  /// above.** It writes no CSS string at all — see `usesFormat`'s second reason — so
  /// there is no `cssStringOrHex` spelling to look for in the document, only the raw
  /// JSON number `tokenValue(_:formatting:)` writes. The evidence is the document
  /// itself, and it specifically checks that an *srgb* component still rounds on its
  /// own 0–1 scale rather than the 0–255 scale `rgb()` writes in — the regression
  /// `nativeGrammars(for:)` exists to prevent, and the one this branch is built to
  /// catch, not merely to exercise.
  @Test("Every shape honors the formatting it is handed", arguments: ExportShape.allCases)
  func formattingReachesEveryShape(shape: ExportShape) {
    var options = ExportOptions.default
    options.shape = shape
    options.format = .oklch
    let coarseOptions = CSSFormatOptions(precision: 2)

    if shape == .designTokens {
      let lossless = options.render([PaletteEntry(color: Self.base)], formatting: .lossless)
      let coarse = options.render([PaletteEntry(color: Self.base)], formatting: coarseOptions)
      #expect(lossless != coarse, "The two precisions produced the same document; test is blind")
      #expect(
        coarse.contains("0.23"),
        "an srgb component did not round on its own 0–1 scale: \(coarse)",
      )
      return
    }

    let written = shape.usesFormat ? options.format : ExportOptions.wideFormat
    let lossless = Self.base.cssStringOrHex(as: written, options: .lossless)
    let coarse = Self.base.cssStringOrHex(as: written, options: coarseOptions)
    #expect(lossless != coarse, "The two precisions produce the same string; test is blind")

    let cardinalities: [(String, [PaletteEntry])] = [
      ("a lone color", [PaletteEntry(color: Self.base)]),
      ("a palette", [
        PaletteEntry(key: "500", color: Self.base),
        PaletteEntry(key: "600", color: Self.base),
      ]),
    ]

    for (description, entries) in cardinalities {
      #expect(
        options.render(entries, formatting: .lossless).contains(lossless),
        "\(shape) dropped the lossless value for \(description)",
      )
      #expect(
        options.render(entries, formatting: coarseOptions).contains(coarse),
        "\(shape) ignored the coarse precision for \(description)",
      )
    }
  }
}

/// The syntax each shape produces, asserted exactly.
///
/// Exact strings are the right standard here and the wrong one three files over. What
/// ``HarmonyPresentation`` says about a triad is editorial and will be reworded; a
/// `:root` block either has its braces or is not a `:root` block. These are the same
/// kind of claim the CSS serializer's own tests make.
@Suite("Export shapes")
struct ExportShapeTests {
  static let blue = ColorValue.srgb8(0x3B, 0x82, 0xF6)
  static let red = ColorValue.srgb8(0xEF, 0x44, 0x44)

  static let palette = [
    PaletteEntry(key: "500", color: blue),
    PaletteEntry(key: "600", color: red),
  ]

  /// A lone color is a bare declaration you can paste inside any rule, with no comment
  /// and no wrapper — the thing you would have typed.
  @Test("One color, one declaration")
  func singleDeclaration() {
    var options = ExportOptions.default
    options.shape = .declaration
    options.template = .border
    options.format = .hex

    let rendered = options.render([PaletteEntry(color: Self.blue)])
    #expect(rendered == "border: 1px solid #3b82f6;")
  }

  /// A set gets its keys in trailing comments, because eleven `background-color` lines
  /// are otherwise indistinguishable from each other.
  @Test("A palette's declarations name themselves")
  func paletteDeclarationsCarryKeys() {
    var options = ExportOptions.default
    options.shape = .declaration
    options.template = .backgroundColor
    options.format = .hex

    #expect(options.render(Self.palette) == """
    background-color: #3b82f6; /* 500 */
    background-color: #ef4444; /* 600 */
    """)
  }

  @Test("Custom properties nest under the family name")
  func customPropertyBlock() {
    var options = ExportOptions.default
    options.shape = .customProperties
    options.format = .hex
    options.name = "brand"

    #expect(options.render(Self.palette) == """
    :root {
      --brand-500: #3b82f6;
      --brand-600: #ef4444;
    }
    """)
  }

  /// A palette of one has no position to name, so it is `--brand` rather than
  /// `--brand-1` — a suffix nothing would reference.
  @Test("A lone color takes the family name unsuffixed")
  func singleCustomProperty() {
    var options = ExportOptions.default
    options.shape = .customProperties
    options.format = .hex

    #expect(options.render([PaletteEntry(color: Self.blue)]) == """
    :root {
      --brand: #3b82f6;
    }
    """)
  }

  /// Tailwind v4's namespace prefix is load-bearing: `--color-brand-500` generates
  /// `bg-brand-500`, and `--brand-500` generates nothing at all.
  @Test("The @theme block carries Tailwind's color namespace")
  func tailwindThemeBlock() {
    var options = ExportOptions.default
    options.shape = .tailwindTheme
    options.format = .hex

    let rendered = options.render(Self.palette)
    #expect(rendered.contains("--color-brand-500: #3b82f6;"))
    #expect(rendered.hasPrefix("@theme {"))
    #expect(rendered.hasSuffix("}"))
  }

  /// Under `theme.extend`, which is the difference between adding a color and replacing
  /// the entire default palette with this one.
  @Test("The v3 config extends rather than replaces")
  func tailwindConfigBlock() {
    var options = ExportOptions.default
    options.shape = .tailwindConfig
    options.format = .hex

    #expect(options.render(Self.palette) == """
    /** @type {import('tailwindcss').Config} */
    module.exports = {
      theme: {
        extend: {
          colors: {
            brand: {
              500: '#3b82f6',
              600: '#ef4444',
            },
          },
        },
      },
    }
    """)
  }

  /// JSON mirrors Tailwind's own shape — a string for a lone color, an object for a
  /// scale — and carries CSS strings rather than this app's internals.
  @Test("JSON is a string or an object, never a ColorValue")
  func jsonShape() {
    var options = ExportOptions.default
    options.shape = .json
    options.format = .hex

    #expect(options.render([PaletteEntry(color: Self.blue)]) == """
    {
      "brand": "#3b82f6"
    }
    """)

    #expect(options.render(Self.palette) == """
    {
      "brand": {
        "500": "#3b82f6",
        "600": "#ef4444"
      }
    }
    """)

    // The failure this shape exists to prevent: `ColorValue` is `Codable`, so the
    // one-line version would have emitted the program's own field names.
    let rendered = options.render(Self.palette)
    #expect(!rendered.contains("components"))
    #expect(!rendered.contains("missing"))
  }

  // MARK: - P3 with fallback

  /// The whole document, pinned exactly — the braces, the query, and the blank line
  /// between the two blocks are the syntax, which is what an exact string is for here.
  ///
  /// The P3 *values* are computed from the app's own serializer rather than transcribed.
  /// Those conversions are oracle-validated in the fixture suite and re-typing them here
  /// would only test whether the numbers were copied correctly.
  @Test("The fallback comes first, then the same properties behind the query")
  func p3WithFallbackBlockStructure() {
    var options = ExportOptions.default
    options.shape = .p3WithFallback

    let blue = Self.blue.cssStringOrHex(as: ExportOptions.wideFormat)
    let red = Self.red.cssStringOrHex(as: ExportOptions.wideFormat)

    #expect(options.render(Self.palette) == """
    :root {
      --brand-500: #3b82f6;
      --brand-600: #ef4444;
    }

    @media (color-gamut: p3) {
      :root {
        --brand-500: \(blue);
        --brand-600: \(red);
      }
    }
    """)
  }

  /// The claim `usesFormat == false` buys.
  ///
  /// A live Format picker here would let somebody choose the panel's default, `oklch()`,
  /// which is unbounded — and fill the block a browser reaches *when it cannot do wide
  /// gamut* with out-of-sRGB values, defeating the shape entirely. Setting `format` to
  /// anything at all must not move a character.
  ///
  /// Mutation: make the fallback honour `options.format`, and this fails.
  @Test(
    "The fallback is hex whatever the format says",
    arguments: [CSSOutputFormat.oklch, .rgb, .lab, .color(.rec2020)],
  )
  func p3FallbackIgnoresTheChosenFormat(format: CSSOutputFormat) {
    var options = ExportOptions.default
    options.shape = .p3WithFallback
    options.format = format

    var hexOnly = options
    hexOnly.format = .hex

    let rendered = options.render(Self.palette)
    #expect(rendered == hexOnly.render(Self.palette), "\(format) reached the document")
    #expect(rendered.contains("--brand-500: #3b82f6;"))
    #expect(!rendered.contains("oklch("), "The fallback is not hex:\n\(rendered)")
  }

  /// **Every entry gets an override, including colors already inside sRGB.**
  ///
  /// The per-entry conditional is the obvious saving and it is what this test forbids:
  /// with one, the media block's contents would depend on the palette's contents, so
  /// widening a single color would silently change *which properties exist* in the
  /// document. This palette is entirely inside sRGB — the case where a conditional
  /// emits nothing at all — so it discriminates on the first entry rather than needing a
  /// mixed palette to reveal a gap.
  ///
  /// Mutation: skip entries that are `inGamut(of: .srgb)`, and this fails.
  @Test("Every color is overridden, in gamut or not")
  func p3OverrideCoversEveryEntry() {
    var options = ExportOptions.default
    options.shape = .p3WithFallback

    // Both on the 8-bit grid and unambiguously inside sRGB.
    #expect(Self.blue.inGamut(of: .srgb))
    #expect(Self.red.inGamut(of: .srgb))

    let rendered = options.render(Self.palette)
    guard let media = rendered.range(of: "@media (color-gamut: p3) {") else {
      Issue.record("No media block at all:\n\(rendered)")
      return
    }
    let overrides = rendered[media.upperBound...]
    #expect(overrides.contains("--brand-500:"), "An in-gamut color lost its override")
    #expect(overrides.contains("--brand-600:"), "An in-gamut color lost its override")
  }

  /// An override that misses its base is a `@media` block with no effect, and nothing
  /// about the document looks wrong — which is why the two property *name* lists are
  /// asserted equal rather than spot-checked.
  ///
  /// Mutation: give either block its own naming (a prefix, a different fallback), and
  /// this fails.
  @Test("Both blocks name exactly the same properties, in the same order")
  func p3BlocksNameTheSameProperties() {
    var options = ExportOptions.default
    options.shape = .p3WithFallback
    options.name = "My Brand!"

    let rendered = options.render(Self.palette)
    let halves = rendered.components(separatedBy: "@media (color-gamut: p3) {")
    #expect(halves.count == 2, "Expected exactly one media block:\n\(rendered)")
    guard halves.count == 2 else { return }

    let names = { (block: String) in
      block.split(separator: "\n").compactMap { line -> String? in
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("--"), let colon = trimmed.firstIndex(of: ":") else {
          return nil
        }
        return String(trimmed[..<colon])
      }
    }

    #expect(names(halves[0]) == ["--My-Brand-500", "--My-Brand-600"])
    #expect(names(halves[1]) == names(halves[0]))
  }

  /// The round trip, which is this layer's oracle — applied to *both* blocks at once.
  ///
  /// A wide color is the interesting input: the fallback must come back inside sRGB
  /// (hex has no other option) and the override must come back as the color that went
  /// in. Asserting only that every value parses would pass a document that wrote the
  /// same rounded hex twice.
  @Test("Both blocks parse, and only the fallback was moved")
  func p3BlockValuesSurviveTheParser() throws {
    var options = ExportOptions.default
    options.shape = .p3WithFallback

    // Outside sRGB, inside Display P3 — the case the shape exists for.
    let wide = ColorValue(space: .displayP3, 0.0, 1.0, 0.0)
    #expect(!wide.inGamut(of: .srgb))

    let rendered = options.render([PaletteEntry(color: wide)], formatting: .lossless)
    let values = ExportRoundTripTests.propertyValues(in: rendered)
    #expect(values.count == 2, "Expected one value per block:\n\(rendered)")

    let parsed = try values.map { value in
      try CSSColorParser.parse(value).color
    }
    #expect(parsed.count == 2)
    guard parsed.count == 2 else { return }

    #expect(parsed[0].inGamut(of: .srgb), "The hex fallback is out of sRGB")
    let returned = parsed[1].converted(to: .displayP3).components
    for index in 0 ..< 3 {
      #expect(
        abs(wide.components[index] - returned[index]) < 1e-7,
        "The override moved \(wide.components) to \(returned)",
      )
    }
  }

  /// The fallback block gets the formatting too, which nothing else here can show.
  ///
  /// `formattingReachesEveryShape` reads this shape's *wide* block, and it has to — hex is
  /// precision-invariant, so a precision claim made against the fallback could not fail.
  /// That leaves the fallback's `formatting` argument unpinned: hardcoding `.default`
  /// there would survive every other test in this file. Hex casing is the cheapest setting
  /// that hex does observe, so it is the one asserted.
  @Test("The fallback honors the formatting, not just the override")
  func p3FallbackReceivesTheFormatting() {
    var options = ExportOptions.default
    options.shape = .p3WithFallback

    let rendered = options.render(
      Self.palette,
      formatting: CSSFormatOptions(uppercaseHex: true),
    )
    #expect(rendered.contains("--brand-500: #3B82F6;"), "The fallback ignored it:\n\(rendered)")
  }

  /// **The `@media` block promises nothing about exactness, and a color outside *P3*
  /// shows why.**
  ///
  /// `color(display-p3 …)` is not `cannotRepresentOutOfGamut`, so unlike the hex fallback
  /// the override has no fixed answer: it follows the **app-wide gamut policy**, exactly
  /// as choosing `color(display-p3 …)` in any other shape does. Under `.map` — what
  /// `ColorStore.formatOptions` starts as, so what the panel actually shows — a Rec.2020
  /// primary is brought into gamut in *both* blocks. Under `.preserve` the same input
  /// keeps its negative components.
  ///
  /// Both are asserted, because it is the *dependence* that makes the wording claim
  /// unsafe. The panel's note said the media block "carries them exactly": true of the
  /// P3-reachable colors that motivate the shape, and false of every color outside P3 —
  /// which this same badge counts, since the count is measured against hex. A substring
  /// test cannot catch a false claim, so the fact is pinned by an input.
  ///
  /// This was written against `.lossless` first and failed, which is the finding: that
  /// constant is `.preserve`, so it silently asked the other half of the question.
  @Test("The override follows the gamut policy, so it cannot promise exactness")
  func p3OverrideIsNotAnExactnessPromise() throws {
    var options = ExportOptions.default
    options.shape = .p3WithFallback

    // Outside sRGB *and* outside Display P3 — confirmed against colorjs.io, which is the
    // rule for any gamut-containment claim: space "widths" do not nest.
    let wider = ColorValue(space: .rec2020, 0.0, 1.0, 0.0)
    #expect(!wider.inGamut(of: .srgb))
    #expect(!wider.inGamut(of: .displayP3))

    func override(_ formatting: CSSFormatOptions) throws -> ColorValue {
      let rendered = options.render([PaletteEntry(color: wider)], formatting: formatting)
      let values = ExportRoundTripTests.propertyValues(in: rendered)
      #expect(values.count == 2, "Expected one value per block:\n\(rendered)")
      return try CSSColorParser.parse(values[values.count - 1]).color
    }

    // The panel's own setting: the override is mapped, which is what the old note denied.
    let mapped = try override(CSSFormatOptions())
    #expect(
      mapped.inGamut(of: .displayP3, epsilon: ColorValue.gamutNoiseTolerance),
      "The override kept a value P3 cannot hold under .map: \(mapped.components)",
    )

    // And the other policy, so the test states the dependence rather than one instance of
    // it — an override that always mapped would pass the assertion above.
    let preserved = try override(.lossless)
    #expect(
      !preserved.inGamut(of: .displayP3, epsilon: ColorValue.gamutNoiseTolerance),
      "The override mapped under .preserve: \(preserved.components)",
    )
  }

  @Test("An empty palette renders nothing at all")
  func emptyPaletteIsEmpty() {
    for shape in ExportShape.allCases {
      var options = ExportOptions.default
      options.shape = shape
      #expect(options.render([PaletteEntry]()).isEmpty, "\(shape) rendered a wrapper around nothing")
    }
  }
}

/// Identifiers and keys, which are where an export stops being valid syntax.
@Suite("Export identifiers")
struct ExportIdentifierTests {
  @Test(
    "Free text becomes a usable identifier",
    arguments: [
      ("brand", "brand"),
      ("my brand", "my-brand"),
      ("my  brand!", "my-brand"),
      ("  spaced  ", "spaced"),
      ("--already--hyphenated--", "already-hyphenated"),
      ("emoji🎨here", "emoji-here"),
      ("Brand", "Brand"),
      ("", "color"),
      ("!!!", "color"),
    ],
  )
  func sanitizing(input: String, expected: String) {
    #expect(ExportOptions.cssIdentifier(input) == expected)
  }

  /// The bug this prevents is a config file that will not load. Tailwind writes shade
  /// keys bare because `50:` is a legal numeric key, but a bare `triad-2:` parses as a
  /// subtraction.
  @Test(
    "JavaScript keys are quoted exactly when they must be",
    arguments: [
      ("50", "50"),
      ("950", "950"),
      ("base", "base"),
      ("_private", "_private"),
      ("triad-2", "'triad-2'"),
      ("split-complementary", "'split-complementary'"),
      ("2x", "'2x'"),
      ("", "''"),
    ],
  )
  func javaScriptKeyQuoting(input: String, expected: String) {
    #expect(ExportOptions.javaScriptKey(input) == expected)
  }

  /// A typed family name reaches the output sanitized, not raw — the panel's field
  /// accepts anything, so this is the only thing standing between a space bar and a
  /// broken stylesheet.
  @Test("A messy family name still emits valid CSS")
  func messyNameIsSanitizedInOutput() {
    var options = ExportOptions.default
    options.shape = .customProperties
    options.format = .hex
    options.name = "My Brand!"

    #expect(options.render([PaletteEntry(color: ExportShapeTests.blue)]) == """
    :root {
      --My-Brand: #3b82f6;
    }
    """)
  }

  /// Clearing the field produces the name the panel showed in it while it was empty.
  ///
  /// These were two literals before: the prompt read `brand` while an emptied name
  /// exported `--color`, because the fallback came from `cssIdentifier`'s own default.
  /// Now both are ``ExportOptions/defaultName``, and the failure mode — a property you
  /// were never shown — is a test away rather than a reading away.
  @Test("An emptied name falls back to what the placeholder promises")
  func emptyNameUsesTheDefault() {
    var options = ExportOptions.default
    options.format = .hex
    options.name = ""

    for shape in [ExportShape.customProperties, .json, .tailwindConfig] {
      options.shape = shape
      let rendered = options.render([PaletteEntry(color: ExportShapeTests.blue)])
      #expect(
        rendered.contains(ExportOptions.defaultName),
        "\(shape) named an emptied family something other than the placeholder:\n\(rendered)",
      )
      #expect(!rendered.contains("color\""), "\(shape) fell back to cssIdentifier's default")
    }

    // And the starting value is the same constant, so a fresh panel and an emptied
    // one export identically.
    #expect(ExportOptions.default.name == ExportOptions.defaultName)
  }

  /// Every exportable format can name any color, which is what makes
  /// ``ExportOptions/value(for:formatting:)``'s fallback unreachable rather than merely
  /// unused. `.keyword` is the one that cannot, and it is excluded for exactly this
  /// reason — a palette where two shades became keywords and nine did not is a document
  /// whose reader cannot tell a substitution happened.
  @Test("Exportable formats are total; keyword is not")
  func exportableFormatsNameEveryColor() {
    // Deliberately not a keyword color, and outside sRGB so the wide formats are
    // exercised too.
    let awkward = ColorValue(space: .oklch, 0.72, 0.28, 142)

    #expect(!CSSOutputFormat.exportable.contains(.keyword))
    #expect(CSSOutputFormat.exportable.count == CSSOutputFormat.catalog.count - 1)

    for format in CSSOutputFormat.exportable {
      #expect(
        awkward.cssString(as: format, options: .lossless) != nil,
        "\(format) could not name a color, so it does not belong in `exportable`",
      )
    }
    #expect(awkward.cssString(as: .keyword) == nil)
  }
}

/// M20's grouped renderer — a document written from more than one named set of colors
/// at once, the shape a whole-project export needs.
///
/// ``ExportShapeTests`` above is the oracle for what one group looks like; these pin
/// what changes and what does not once there are two. The one-group case is not
/// re-pinned here — every exact string in ``ExportShapeTests`` already is that check,
/// since ``ExportOptions/render(_:formatting:)`` over a single list is now a one-line
/// call into the grouped renderer below it. A header-condition mutation that always (or
/// never) wrote the `/* From "…" */` comment would fail those tests, not these.
@Suite("Grouped export")
struct GroupedExportTests {
  static let blue = ColorValue.srgb8(0x3B, 0x82, 0xF6)
  static let red = ColorValue.srgb8(0xEF, 0x44, 0x44)

  /// The whole document, pinned exactly — the blank line and the header comment between
  /// groups are the syntax a hand-written string can get subtly wrong, which is what an
  /// exact string is for.
  @Test("Two groups get a header comment and a blank line between them")
  func twoGroupsGetHeaders() {
    var options = ExportOptions.default
    options.shape = .customProperties
    options.format = .hex

    let groups = [
      PaletteGroup(name: "primary", entries: [PaletteEntry(key: "500", color: Self.blue)]),
      PaletteGroup(name: "secondary", entries: [PaletteEntry(key: "500", color: Self.red)]),
    ]

    #expect(options.render(groups) == """
    :root {
      /* From "primary" */
      --primary-500: #3b82f6;

      /* From "secondary" */
      --secondary-500: #ef4444;
    }
    """)
  }

  /// `declaration` is a separate implementation from the other three CSS shapes' shared
  /// `groupedPropertyLines` — its own header condition, its own join — so the header
  /// mutation that fails ``twoGroupsGetHeaders`` above does not touch this one at all.
  /// Pinned on its own for that reason.
  @Test("Two groups get headers in the declaration shape too")
  func declarationGroupsGetHeaders() {
    var options = ExportOptions.default
    options.shape = .declaration
    options.format = .hex

    let groups = [
      PaletteGroup(name: "primary", entries: [PaletteEntry(key: "500", color: Self.blue)]),
      PaletteGroup(name: "secondary", entries: [PaletteEntry(key: "500", color: Self.red)]),
    ]

    #expect(options.render(groups) == """
    /* From "primary" */
    color: #3b82f6; /* 500 */

    /* From "secondary" */
    color: #ef4444; /* 500 */
    """)
  }

  /// `tailwindTheme` *does* share `groupedPropertyLines` with `customProperties`, but its
  /// own pre-M20 test (`tailwindThemeBlock`) only checks `.contains`/`.hasPrefix`/
  /// `.hasSuffix` — none of which would notice an extra header comment appearing (or a
  /// real one going missing), so that test cannot stand in for this one. The Tailwind
  /// namespace prefix has to reach *every* group, not just the first.
  @Test("Two groups get headers in the @theme shape, with the color- prefix on each")
  func tailwindThemeGroupsGetHeaders() {
    var options = ExportOptions.default
    options.shape = .tailwindTheme
    options.format = .hex

    let groups = [
      PaletteGroup(name: "primary", entries: [PaletteEntry(key: "500", color: Self.blue)]),
      PaletteGroup(name: "secondary", entries: [PaletteEntry(key: "500", color: Self.red)]),
    ]

    #expect(options.render(groups) == """
    @theme {
      /* From "primary" */
      --color-primary-500: #3b82f6;

      /* From "secondary" */
      --color-secondary-500: #ef4444;
    }
    """)
  }

  /// The single-group case for `tailwindTheme`, pinned exactly rather than left to the
  /// pre-existing `.contains`/`.hasPrefix`/`.hasSuffix` check in `tailwindThemeBlock`.
  /// That check cannot tell an unwanted header apart from none at all, and a two-group
  /// test cannot either — with two groups a header belongs regardless of whether the
  /// condition guarding it is `groups.count > 1` or simply `true`. Only an exact match
  /// on the *one*-group case proves the header is conditional rather than unconditional.
  ///
  /// Mutation: force `groupedPropertyLines` to always write the header, and this fails
  /// where ``tailwindThemeGroupsGetHeaders`` above does not.
  @Test("A single group gets no header in the @theme shape")
  func tailwindThemeSingleGroupHasNoHeader() {
    var options = ExportOptions.default
    options.shape = .tailwindTheme
    options.format = .hex

    #expect(options.render(ExportShapeTests.palette) == """
    @theme {
      --color-brand-500: #3b82f6;
      --color-brand-600: #ef4444;
    }
    """)
  }

  /// Both cardinalities per group — ``json`` and ``tailwindConfig`` fork on lone-color
  /// versus scale, and that fork applies group by group, not document-wide. A palette
  /// export mixes both in one document: a single saved color sits beside a ramp.
  @Test("JSON nests a lone-color group as a string and a scale as an object")
  func jsonGroupsForkPerGroup() {
    var options = ExportOptions.default
    options.shape = .json
    options.format = .hex

    let groups = [
      PaletteGroup(name: "primary", entries: [PaletteEntry(color: Self.blue)]),
      PaletteGroup(name: "secondary", entries: [
        PaletteEntry(key: "500", color: Self.blue),
        PaletteEntry(key: "600", color: Self.red),
      ]),
    ]

    #expect(options.render(groups) == """
    {
      "primary": "#3b82f6",
      "secondary": {
        "500": "#3b82f6",
        "600": "#ef4444"
      }
    }
    """)
  }

  /// Same fork, the Tailwind v3 shape — a bare string for the lone-color group, nested
  /// under `theme.extend.colors` alongside a scale for the other.
  @Test("Tailwind config nests a lone-color group as a string and a scale as an object")
  func tailwindConfigGroupsForkPerGroup() {
    var options = ExportOptions.default
    options.shape = .tailwindConfig
    options.format = .hex

    let groups = [
      PaletteGroup(name: "primary", entries: [PaletteEntry(color: Self.blue)]),
      PaletteGroup(name: "secondary", entries: [
        PaletteEntry(key: "500", color: Self.blue),
        PaletteEntry(key: "600", color: Self.red),
      ]),
    ]

    #expect(options.render(groups) == """
    /** @type {import('tailwindcss').Config} */
    module.exports = {
      theme: {
        extend: {
          colors: {
            primary: '#3b82f6',
            secondary: {
              500: '#3b82f6',
              600: '#ef4444',
            },
          },
        },
      },
    }
    """)
  }

  /// Every color a document names has to survive being read back — the ``Export/``
  /// oracle rule applied to more than one group at once, since nothing about the parser
  /// knows groups exist.
  @Test("Every color in a multi-group document survives the parser")
  func multiGroupDocumentRoundTrips() throws {
    var options = ExportOptions.default
    options.shape = .customProperties
    // Hex, and both colors already on the 8-bit grid — so the round trip is exact,
    // not merely close. `options.format` defaults to `oklch()`, which is a real
    // conversion round trip and would need a tolerance instead of `==`.
    options.format = .hex

    let groups = [
      PaletteGroup(name: "primary", entries: [PaletteEntry(key: "500", color: Self.blue)]),
      PaletteGroup(name: "secondary", entries: [PaletteEntry(key: "500", color: Self.red)]),
    ]

    let rendered = options.render(groups, formatting: .lossless)
    let values = ExportRoundTripTests.propertyValues(in: rendered)
    #expect(values.count == 2, "Expected one value per group:\n\(rendered)")

    let parsed = try values.map { value in
      try CSSColorParser.parse(value).color
    }
    #expect(parsed.map { $0.converted(to: .srgb) } == [Self.blue, Self.red].map { $0.converted(to: .srgb) })
  }

  /// **Two group names that sanitize to the same identifier must not collapse into one
  /// property set.** `brand` and `brand!` are distinct as typed and identical once
  /// `!` is stripped, which is exactly why uniquing has to run over the *sanitized*
  /// name rather than the raw one — the same reasoning `DesignTokenImport.keyed` and
  /// `ProjectLibrary.paletteKeys` already follow.
  ///
  /// Mutation: unique against the raw name instead, and this fails — `brand` and
  /// `brand!` would both sanitize to `brand`, colliding anyway, but the *test* would no
  /// longer be exercising the sanitized-uniquing path if the names it used did not
  /// collide only after sanitizing.
  @Test("Colliding group names still produce two distinct properties")
  func collidingGroupNamesStaySeparate() {
    var options = ExportOptions.default
    options.shape = .customProperties
    options.format = .hex

    let groups = [
      PaletteGroup(name: "brand", entries: [PaletteEntry(key: "500", color: Self.blue)]),
      PaletteGroup(name: "brand!", entries: [PaletteEntry(key: "500", color: Self.red)]),
    ]

    let rendered = options.render(groups)
    #expect(rendered.contains("--brand-500: #3b82f6;"))
    #expect(rendered.contains("--brand-2-500: #ef4444;"), "The second group did not get a suffix:\n\(rendered)")

    // Neither color is lost, and the properties really are two distinct names —
    // the failure mode collapses them into one and drops the second color.
    let names = ExportRoundTripTests.propertyValues(in: rendered)
    #expect(names.count == 2, "One group's properties overwrote the other's:\n\(rendered)")
  }

  /// Three colliding names in a row need the loop, not just the first suffix —
  /// `-2` is already taken by the second `brand`, so the third has to keep counting.
  @Test("A third collision skips past an already-taken suffix")
  func thirdCollisionSkipsTakenSuffix() {
    var options = ExportOptions.default
    options.shape = .customProperties
    options.format = .hex

    let groups = [
      PaletteGroup(name: "brand", entries: [PaletteEntry(color: Self.blue)]),
      PaletteGroup(name: "brand-2", entries: [PaletteEntry(color: Self.red)]),
      PaletteGroup(name: "brand", entries: [PaletteEntry(color: Self.blue)]),
    ]

    let rendered = options.render(groups)
    #expect(rendered.contains("--brand:"))
    #expect(rendered.contains("--brand-2:"))
    #expect(rendered.contains("--brand-3:"), "The loop stopped at an already-taken suffix:\n\(rendered)")
  }

  /// **Every group appears in both of `p3WithFallback`'s blocks, not just the
  /// fallback.** The per-entry version of this rule is pinned in ``ExportShapeTests``;
  /// this is the per-*group* version M20 adds, and it fails the same way an override
  /// that only covered the base would — silently, with a `@media` block that looks
  /// complete and is not.
  @Test("p3WithFallback writes every group in both blocks")
  func p3WithFallbackCoversEveryGroup() {
    var options = ExportOptions.default
    options.shape = .p3WithFallback

    let blue = Self.blue.cssStringOrHex(as: ExportOptions.wideFormat)
    let red = Self.red.cssStringOrHex(as: ExportOptions.wideFormat)

    let groups = [
      PaletteGroup(name: "primary", entries: [PaletteEntry(color: Self.blue)]),
      PaletteGroup(name: "secondary", entries: [PaletteEntry(color: Self.red)]),
    ]

    #expect(options.render(groups) == """
    :root {
      /* From "primary" */
      --primary: #3b82f6;

      /* From "secondary" */
      --secondary: #ef4444;
    }

    @media (color-gamut: p3) {
      :root {
        /* From "primary" */
        --primary: \(blue);

        /* From "secondary" */
        --secondary: \(red);
      }
    }
    """)
  }

  /// An empty group is filtered out entirely rather than emitting a header with nothing
  /// under it — the same "no wrapper around nothing" rule ``emptyPaletteIsEmpty`` pins
  /// for the single-group case, extended to a group that happens to have no entries.
  @Test("An empty group among non-empty ones leaves no trace")
  func emptyGroupIsDropped() {
    var options = ExportOptions.default
    options.shape = .customProperties
    options.format = .hex

    let groups = [
      PaletteGroup(name: "primary", entries: [PaletteEntry(color: Self.blue)]),
      PaletteGroup(name: "empty", entries: []),
    ]

    let rendered = options.render(groups)
    #expect(!rendered.contains("empty"), "An empty group left a header behind:\n\(rendered)")
    // With the empty group dropped, only one group remains — so no header at all,
    // matching the single-group case exactly.
    #expect(rendered == """
    :root {
      --primary: #3b82f6;
    }
    """)
  }

  /// Every group vanishing at once is the same "no wrapper around nothing" case as an
  /// empty palette.
  @Test("A document with no groups at all is empty, not an empty wrapper")
  func noGroupsRendersNothing() {
    for shape in ExportShape.allCases {
      var options = ExportOptions.default
      options.shape = shape
      #expect(options.render([PaletteGroup]()).isEmpty, "\(shape) rendered a wrapper around nothing")
    }
  }

  /// **`ExportOptions.name` reaches the filename and not the document, once there is
  /// more than one group.** Every family in a grouped render comes from the group's own
  /// name, never from `options.name` — so `ExportPanel`'s Name field, still shown
  /// because `shape.usesName` does not know about groups, is live and genuinely does
  /// something (`suggestedFilename`) without touching a single character of the
  /// preview. Recorded as accepted behavior in PLAN.md rather than left implicit: this
  /// is exactly the shape of thing `usesFormat`'s doc comment warns a control can look
  /// like it worked without doing anything — the difference here is that it *does* do
  /// something, just not to the part being previewed.
  @Test("The Name field changes the suggested filename but not a grouped document")
  func nameDoesNotReachAGroupedDocument() {
    var options = ExportOptions.default
    options.shape = .customProperties
    options.format = .hex
    options.name = "brand"

    let groups = [PaletteGroup(name: "primary", entries: [PaletteEntry(color: Self.blue)])]
    let withBrand = options.render(groups)

    options.name = "something else entirely"
    let withSomethingElse = options.render(groups)

    #expect(withBrand == withSomethingElse, "Changing `name` moved a grouped document")
    #expect(withBrand.contains("--primary:"), "The group's own name should be what appears")
    #expect(!withBrand.contains("brand"), "options.name should not reach the document at all")

    // …but the filename does follow it, which is the one place `name` still matters
    // once a project is staged.
    #expect(options.suggestedFilename == "something-else-entirely.css")
  }
}

/// What a saved export is called and what type it claims to be.
///
/// The write itself is unreachable from here — `.fileExporter` presents `NSSavePanel`,
/// which is a separate process XCUITest cannot drive and `osascript` cannot reach without
/// assistive access. So everything decidable *before* the panel opens is pinned here, and
/// the write is a recorded manual check in PLAN.md. That split is deliberate: it is the
/// same one `fileImporter` forced on M17, and the alternative is a green suite implying
/// coverage that does not exist.
@Suite("Export file naming")
struct ExportFileNamingTests {
  /// Transcribed, so asserted case by case rather than against a rule. Four of the
  /// seven answer `css`, which is the part a derivation would get wrong:
  /// `p3WithFallback` writes a `@media` block and is still a stylesheet, and
  /// `designTokens` (M34) shares `json`'s extension rather than inventing its own.
  @Test(
    "Each shape names its own file type",
    arguments: [
      (ExportShape.declaration, "css"),
      (.customProperties, "css"),
      (.tailwindTheme, "css"),
      (.p3WithFallback, "css"),
      (.json, "json"),
      (.tailwindConfig, "js"),
      (.designTokens, "json"),
    ],
  )
  func fileExtensionPerShape(shape: ExportShape, expected: String) {
    #expect(shape.fileExtension == expected)
  }

  /// A leading dot or a capital would both produce a filename the system treats as
  /// something else — `brand..css`, or a type lookup that misses.
  @Test("Every extension is a bare lowercase suffix")
  func extensionsAreWellFormed() {
    for shape in ExportShape.allCases {
      let suffix = shape.fileExtension
      #expect(!suffix.isEmpty, "\(shape) has no extension")
      #expect(!suffix.contains("."), "\(shape) carries its own dot: \(suffix)")
      #expect(suffix == suffix.lowercased(), "\(shape) is not lowercase: \(suffix)")
    }
  }

  /// **The claim worth having**: the file is named the same thing the properties inside
  /// it are named. Both go through ``ExportOptions/cssIdentifier(_:fallback:)``, so a
  /// typed `My Brand!` writes `--My-Brand` and saves as `My-Brand.css`.
  ///
  /// This is what fails if ``ExportOptions/suggestedFilename`` is ever built from the raw
  /// `name` instead — the document and the file would disagree, and a filename containing
  /// a space or a `!` is the sort of thing nobody notices until a build script chokes.
  @Test("The filename matches the family name in the document")
  func filenameMatchesTheDocument() {
    var options = ExportOptions.default
    options.shape = .customProperties
    options.format = .hex
    options.name = "My Brand!"

    let document = options.render([PaletteEntry(color: ExportShapeTests.blue)])
    #expect(document.contains("--My-Brand:"))
    #expect(options.suggestedFilename == "My-Brand.css")
  }

  /// An emptied name proposes the placeholder, not an empty filename — the same fallback
  /// the document itself uses, for the same reason ``emptyNameUsesTheDefault`` gives.
  @Test("An emptied name still proposes a filename")
  func emptyNameStillNamesTheFile() {
    var options = ExportOptions.default
    options.name = ""
    options.shape = .json

    #expect(options.suggestedFilename == "\(ExportOptions.defaultName).json")
    #expect(!options.suggestedFilename.hasPrefix("."))
  }

  /// Switching shape re-types the file, since the extension is the shape's and not the
  /// name's. A stale `.css` on a Tailwind config is the failure this catches.
  @Test("The proposed extension follows the shape")
  func extensionFollowsTheShape() {
    var options = ExportOptions.default
    options.name = "brand"

    options.shape = .customProperties
    #expect(options.suggestedFilename == "brand.css")
    options.shape = .tailwindConfig
    #expect(options.suggestedFilename == "brand.js")
    options.shape = .json
    #expect(options.suggestedFilename == "brand.json")
  }

  /// `brand.tokens.json` is DTCG's own convention, not this app's invention — and the
  /// stem suffix is the only shape-specific piece of ``ExportOptions/suggestedFilename``,
  /// everything else already covered by ``extensionFollowsTheShape``.
  @Test("designTokens proposes the .tokens stem")
  func designTokensProposesTheConventionalStem() {
    var options = ExportOptions.default
    options.name = "brand"
    options.shape = .designTokens
    #expect(options.suggestedFilename == "brand.tokens.json")
  }

  /// The three extensions resolve to three *different* content types.
  ///
  /// **This assertion replaced a tautology, and the mutation run is what exposed it.** The
  /// first version asked whether every shape's `contentType` appeared in
  /// `writableContentTypes` — but that list is derived from `contentType`, so the claim was
  /// true by construction. It passed a mutation that collapsed all six shapes onto `css`,
  /// which is precisely the bug it was supposed to catch.
  ///
  /// Distinctness is not derivable that way. It fails if the extension table collapses,
  /// and it also fails if `UTType(filenameExtension:)` stops resolving and every shape
  /// falls back to `.plainText` — which would tag a Tailwind config as plain text in the
  /// save panel while the filename still said `.js`.
  @Test("The shapes resolve to distinct content types")
  func contentTypesAreDistinct() {
    let types = Set(ExportShape.allCases.map(\.contentType))
    #expect(
      types.count == 3,
      "Expected css, json and js to be three types, got \(types.count): \(types)",
    )
    #expect(ExportShape.json.contentType != ExportShape.tailwindConfig.contentType)
    #expect(ExportShape.json.contentType != ExportShape.customProperties.contentType)

    // Text-based, or a save panel would refuse the string this document hands it. True of
    // the `.plainText` fallback too, so this survives a system that has no CSS type.
    for shape in ExportShape.allCases {
      #expect(
        shape.contentType.conforms(to: .text),
        "\(shape) claims a non-text type: \(shape.contentType)",
      )
    }
  }

  /// Every shape's type must be one the exporter will accept, or saving that shape fails
  /// at the panel with nothing in the UI to explain it.
  ///
  /// Deliberately paired with ``contentTypesAreDistinct`` rather than standing alone: this
  /// one checks the *derivation held* (a future hardcoded list that missed a type would
  /// fail here), and that one checks the derivation is producing something meaningful.
  /// Either without the other passes a mutation the pair catches.
  @Test("Every shape's content type is writable")
  func everyShapeIsWritable() {
    for shape in ExportShape.allCases {
      #expect(
        ExportDocument.writableContentTypes.contains(shape.contentType),
        "\(shape) claims a type the exporter will not write: \(shape.contentType)",
      )
    }
    // Deduped, so four css shapes contribute one entry rather than four.
    #expect(ExportDocument.writableContentTypes.count == 3)

    // Write-only on purpose: reading a stylesheet back is not this type's job, and
    // declaring it readable puts the app in Finder's "Open With" for every .css there is.
    #expect(ExportDocument.readableContentTypes.isEmpty)
  }

  /// The document carries exactly the text it was handed, unmodified.
  ///
  /// **`fileWrapper(configuration:)` itself is not reachable from a test**:
  /// `FileDocumentWriteConfiguration` has no public initializer, so there is no way to
  /// call it. What is assertable is the half that could actually be wrong — that the
  /// document stores the export text verbatim rather than re-deriving or trimming it. The
  /// one line the wrapper adds is `Data(text.utf8)`, and a UTF-8 encoding that lost
  /// characters would fail the round trip below anyway.
  @Test("The document is the export text, unmodified")
  func documentCarriesItsText() {
    var options = ExportOptions.default
    options.shape = .customProperties
    options.format = .hex
    let text = options.render([PaletteEntry(key: "500", color: ExportShapeTests.blue)])

    let document = ExportDocument(text: text)
    #expect(document.text == text)
    #expect(String(decoding: Data(document.text.utf8), as: UTF8.self) == text)
  }
}

/// Palette keys, which have to be unique or entries silently overwrite each other.
@Suite("Palette naming")
struct PaletteNamingTests {
  /// The scale is Tailwind's, and it is eleven long. A list stopping at `900` looks
  /// right and is a version out of date.
  @Test("Tailwind's scale is 50 through 950")
  func tailwindScaleIsElevenSteps() {
    #expect(PaletteNaming.tailwindScale.count == 11)
    #expect(PaletteNaming.tailwindScale.first == "50")
    #expect(PaletteNaming.tailwindScale.last == "950")
    #expect(PaletteNaming.rampKeys(count: 11) == PaletteNaming.tailwindScale)
  }

  /// A ramp that is not eleven stops gets indices instead of a mapping invented for it.
  /// Not hypothetical: ``Harmony/monochromatic`` asks for five.
  @Test("Other stop counts fall back to indices", arguments: [3, 5, 7, 9, 13, 21])
  func nonTailwindCountsUseIndices(count: Int) {
    let keys = PaletteNaming.rampKeys(count: count)
    #expect(keys.count == count)
    #expect(keys.first == "1")
    #expect(keys.last == String(count))
  }

  /// One key per member, all distinct. Two entries sharing a key would collapse into a
  /// single custom property, losing a color with no error anywhere.
  @Test("Every harmony's keys match its members and are unique", arguments: Harmony.allCases)
  func harmonyKeysAreOneToOneAndUnique(harmony: Harmony) {
    let keys = PaletteNaming.harmonyKeys(harmony)
    let members = ColorValue.srgb8(0x3B, 0x82, 0xF6).harmony(harmony)

    #expect(keys.count == members.count, "\(harmony) has \(members.count) members, \(keys.count) keys")
    #expect(Set(keys).count == keys.count, "\(harmony) repeats a key: \(keys)")
  }

  /// The key marked `base` is the member the harmony itself calls the base. These are
  /// computed independently — one from a switch here, one from the offset table in
  /// ``Harmony`` — so they can drift, and analogous is where they would: it is the only
  /// hue harmony whose base is not first.
  @Test("The base key sits where the harmony puts the base", arguments: Harmony.allCases)
  func baseKeyAgreesWithBaseIndex(harmony: Harmony) {
    let keys = PaletteNaming.harmonyKeys(harmony)
    let baseIndex = harmony.baseIndex()

    guard harmony != .monochromatic else {
      // A ramp's keys are positions on a scale, so its middle is `500`, not `base`.
      #expect(keys[baseIndex] == "3", "A five-stop ramp's middle stop is the third")
      return
    }
    #expect(keys[baseIndex] == "base", "\(harmony) marks \(keys[baseIndex]) as its base")
  }
}

@Suite("Web-friendly export (M22)")
struct WebFriendlyExportTests {
  static let palette = [
    PaletteEntry(key: "500", color: ColorValue.srgb8(0x3B, 0x82, 0xF6)),
    PaletteEntry(key: "600", color: ColorValue.srgb8(0xEF, 0x44, 0x44)),
  ]

  /// Two shapes are excluded now (M34 added `designTokens`), each structurally rather
  /// than by a gamut check — see ``ExportShape/isWebFriendly``.
  @Test("Only p3WithFallback and designTokens are excluded from the shape list")
  func onlyStructurallyWideShapesAreExcluded() {
    for shape in ExportShape.allCases {
      #expect(shape.isWebFriendly == (shape != .p3WithFallback && shape != .designTokens))
    }
  }

  @Test("webFriendlyExportable is exportable minus every color() format")
  func webFriendlyExportableExcludesColorFamily() {
    #expect(Set(CSSOutputFormat.webFriendlyExportable).isSubset(of: Set(CSSOutputFormat.exportable)))
    #expect(!CSSOutputFormat.webFriendlyExportable.contains {
      if case .color = $0 {
        true
      } else {
        false
      }
    })
    // Nothing lost besides the color() family: exportable already excludes keyword.
    #expect(CSSOutputFormat.exportable.count - CSSOutputFormat.webFriendlyExportable.count == 8)
  }

  @Test("effective(webFriendly: false) returns self, unchanged")
  func effectiveIsANoOpWhenOff() {
    var options = ExportOptions.default
    options.shape = .p3WithFallback
    options.format = .color(.rec2020)
    #expect(options.effective(webFriendly: false) == options)
  }

  /// The gap the plan's own review named after M19 landed: `shape` and `format` are
  /// *persisted* preferences, so the mode can be turned on with `p3WithFallback`
  /// already chosen from an earlier session. Hiding the picker does not change the
  /// stored value — only `effective` does, which is why ``ColorStore/exportDocument``
  /// has to read it rather than ``ExportOptions`` directly.
  @Test("effective(webFriendly: true) replaces p3WithFallback")
  func effectiveReplacesP3WithFallback() {
    var options = ExportOptions.default
    options.shape = .p3WithFallback
    let effective = options.effective(webFriendly: true)

    #expect(effective.shape != .p3WithFallback)
    #expect(effective.shape.isWebFriendly)
    // The stored preference is untouched — turning the mode back off restores it,
    // the same promise `mixSpace`/`mixHueMethod` make.
    #expect(options.shape == .p3WithFallback)
  }

  /// The regression this test exists for: `effective` used to check
  /// `shape == .p3WithFallback` directly, which would have hidden `designTokens`
  /// from the web-friendly picker (M34) while leaving the stored preference free to
  /// keep rendering a token document — the exact M22 bug this function exists to
  /// prevent, just against a shape that did not exist when the fix was first written.
  @Test("effective(webFriendly: true) replaces designTokens too")
  func effectiveReplacesDesignTokens() {
    var options = ExportOptions.default
    options.shape = .designTokens
    let effective = options.effective(webFriendly: true)

    #expect(effective.shape != .designTokens)
    #expect(effective.shape.isWebFriendly)
    #expect(options.shape == .designTokens)
  }

  @Test("effective(webFriendly: true) replaces a color() format")
  func effectiveReplacesColorFormat() {
    var options = ExportOptions.default
    options.format = .color(.displayP3)
    let effective = options.effective(webFriendly: true)

    #expect(CSSOutputFormat.webFriendly.contains(effective.format))
    #expect(options.format == .color(.displayP3))
  }

  @Test("effective(webFriendly: true) leaves an already-web-friendly choice alone")
  func effectiveIsANoOpWhenAlreadySafe() {
    var options = ExportOptions.default
    options.shape = .customProperties
    options.format = .oklch
    #expect(options.effective(webFriendly: true) == options)
  }

  /// The document itself, not just the picker's underlying value: rendering through
  /// `effective` never produces the wide-gamut block `p3WithFallback` exists for.
  @Test("A document rendered through effective(webFriendly:) never writes @media or color()")
  func renderedDocumentNeverEscapes() {
    var options = ExportOptions.default
    options.shape = .p3WithFallback
    options.name = "brand"

    let rendered = options.effective(webFriendly: true).render(Self.palette)
    #expect(!rendered.contains("@media"))
    #expect(!rendered.contains("color("))
  }
}

/// M34's seventh shape — the W3C Design Tokens (DTCG) format ``DesignTokenImport``
/// already reads (M17), now writable too.
///
/// **The oracle is this app's own decoder**, exactly the way `Export/`'s oracle is
/// always its own parser (see this file's header) — render, feed the document
/// straight back through ``DesignTokenImport/decode(_:)``, and require the colors to
/// survive **in their own spaces**, not merely to parse. `PaletteImportTests` covers
/// the higher layer above this (`PaletteImport.parse(_:as:)`'s grouping and key
/// inference); this suite is the layer underneath it, matching every other shape's
/// exact-string tests against the lowest oracle that can discriminate.
@Suite("Design tokens export (M34)")
struct DesignTokensExportTests {
  static let blue = ColorValue.srgb8(0x3B, 0x82, 0xF6)

  private static func decode(_ document: String) throws -> DesignTokenDocument {
    try DesignTokenImport.decode(Data(document.utf8))
  }

  /// Three different spaces, not one repeated — the mutation this pins is "canonicalize
  /// to one format," which a same-space fixture cannot catch since the writer's actual
  /// output and a canonicalized one would coincide by accident.
  @Test("A color round-trips through the decoder, in its own space", arguments: [
    ("srgb", ColorValue.srgb8(0x3B, 0x82, 0xF6)),
    ("oklch", ColorValue(space: .oklch, 0.5236, 0.1839, 309.99)),
    ("hsl", ColorValue(space: .hsl, 217, 91, 60)),
  ])
  func loneColorRoundTrips(label: String, color: ColorValue) throws {
    var options = ExportOptions.default
    options.shape = .designTokens
    options.name = "Primary-Base"

    let rendered = options.render([PaletteEntry(color: color)], formatting: .lossless)
    let document = try Self.decode(rendered)

    #expect(document.colors.count == 1, "\(label): \(rendered)")
    let token = try #require(document.colors.first)
    #expect(token.color.space == color.space, "\(label) did not keep its own space")
    for index in 0 ..< 3 {
      #expect(
        abs(token.color.components[index] - color.components[index]) < 1e-7,
        "\(label) component \(index) drifted: \(token.color.components) vs \(color.components)",
      )
    }
  }

  /// The other cardinality ``json`` and ``tailwindConfig`` fork on — a single-entry-only
  /// test happily passed a broken multi-entry branch once already (M8), which is why
  /// this app's export tests never stop at one.
  @Test("A palette round-trips as a scale, each entry keeping its own space")
  func paletteRoundTrips() throws {
    var options = ExportOptions.default
    options.shape = .designTokens
    options.name = "Greyscale"

    let entries = [
      PaletteEntry(key: "50", color: ColorValue(space: .oklch, 0.97, 0, 0)),
      PaletteEntry(key: "100", color: ColorValue(space: .oklch, 0.9068, 0, 0)),
    ]
    let rendered = options.render(entries, formatting: .lossless)
    let document = try Self.decode(rendered)

    #expect(document.colors.count == 2, "\(rendered)")
    for (entry, token) in zip(entries, document.colors) {
      #expect(token.color.space == .oklch)
      for index in 0 ..< 3 {
        #expect(abs(token.color.components[index] - entry.color.components[index]) < 1e-7)
      }
    }
  }

  /// Pinned exactly against the plan's own worked example, not a string this test
  /// invented to match whatever the writer happens to do — the values are chosen so
  /// default precision (4) reproduces them digit for digit.
  @Test("A lone color writes as a single top-level token")
  func loneColorExactString() {
    var options = ExportOptions.default
    options.shape = .designTokens
    options.name = "Primary-Base"

    let color = ColorValue(space: .oklch, 0.5236, 0.1839, 309.99)
    let rendered = options.render([PaletteEntry(color: color)])

    #expect(rendered == """
    {
      "$type": "color",
      "Primary-Base": { "$value": { "colorSpace": "oklch", "components": [0.5236, 0.1839, 309.99] } }
    }
    """)
  }

  /// The scale half of the same worked example — a group nests its entries as tokens
  /// under it, and `$type` is declared once, at the root, not per token.
  @Test("A scale nests entries as tokens under their group")
  func scaleExactString() {
    var options = ExportOptions.default
    options.shape = .designTokens
    options.name = "Greyscale"

    let entries = [
      PaletteEntry(key: "50", color: ColorValue(space: .oklch, 0.97, 0, 0)),
      PaletteEntry(key: "100", color: ColorValue(space: .oklch, 0.9068, 0, 0)),
    ]

    #expect(options.render(entries) == """
    {
      "$type": "color",
      "Greyscale": {
        "50": { "$value": { "colorSpace": "oklch", "components": [0.97, 0, 0] } },
        "100": { "$value": { "colorSpace": "oklch", "components": [0.9068, 0, 0] } }
      }
    }
    """)
  }

  /// `alpha` is DTCG's own default, so writing it on an opaque color would be pure
  /// repetition — and the flip side matters just as much, or a translucent color
  /// would silently import back fully opaque.
  @Test("Alpha is written only when the color is not opaque")
  func alphaWrittenOnlyWhenTranslucent() {
    var options = ExportOptions.default
    options.shape = .designTokens

    let opaque = options.render([PaletteEntry(color: Self.blue)])
    #expect(!opaque.contains("alpha"))

    var translucent = Self.blue
    translucent.alpha = 0.5
    let withAlpha = options.render([PaletteEntry(color: translucent)])
    #expect(withAlpha.contains("\"alpha\": 0.5"))
  }

  /// A missing component or alpha writes as the literal `"none"` string and reads back
  /// as missing — self-consistent with this app's own decoder, which is the claim this
  /// pins. It is **not** a claim that `"none"` is legal DTCG for a third party: the
  /// decoder's own comment calls reading it *leniency*, and `tokenValue`'s doc comment
  /// says so — this test is the other half of that admission, not a contradiction of it.
  @Test("A missing component or alpha survives as none, self-consistently")
  func missingComponentsSurviveAsNone() throws {
    var options = ExportOptions.default
    options.shape = .designTokens

    let color = ColorValue(space: .oklch, 0, 0.19, 260, alpha: 1, missing: [.component(0), .alpha])

    let rendered = options.render([PaletteEntry(color: color)], formatting: .lossless)
    #expect(rendered.contains("\"components\": [\"none\", "), "\(rendered)")
    #expect(rendered.contains("\"alpha\": \"none\""), "\(rendered)")

    let document = try Self.decode(rendered)
    let token = try #require(document.colors.first)
    #expect(token.color.missing.contains(.component(0)))
    #expect(token.color.missing.contains(.alpha))
  }

  /// **The riskiest assumption this shape makes, pinned rather than asserted from
  /// reasoning.** Every round-trip test above would pass just as well if each token
  /// carried its own `$type: "color"` — they cannot tell "the root's type applies to
  /// every token beneath it" apart from "each token happens to be typed already,"
  /// because the writer never does the latter. This test forces the distinction: it
  /// removes exactly the root-level `$type` a genuine per-token writer would never
  /// have needed, leaving the token with no explicit type of its own and nothing
  /// above it to inherit from. If the root were not load-bearing, the token would
  /// still decode as a color; it does not.
  @Test("Colors depend on the root-level $type — removing it makes every token typeless")
  func rootLevelTypeIsLoadBearing() throws {
    var options = ExportOptions.default
    options.shape = .designTokens
    options.name = "Primary-Base"
    let rendered = options.render([PaletteEntry(color: Self.blue)])

    let withoutRootType = rendered.replacingOccurrences(
      of: "\"$type\": \"color\",\n  ",
      with: "",
    )
    #expect(!withoutRootType.contains("$type"), "the surgery missed: \(withoutRootType)")

    let document = try Self.decode(withoutRootType)
    #expect(document.colors.isEmpty)
    #expect(document.otherTypeCount == 1)
  }

  /// This shape hand-builds JSON the way ``json(_:formatting:)`` does, and that shape's
  /// freedom from escaping depends on its keys going through `cssIdentifier`, which
  /// strips everything outside `[A-Za-z0-9_-]`. `tokenName(_:fallback:)` is
  /// deliberately more permissive — DTCG allows spaces and case — so it has to do its
  /// own escaping instead of inheriting `json`'s for free. A palette or an entry key
  /// typed with a quote and a backslash is the regression this pins: broken JSON
  /// fails to decode at all, not merely looks wrong.
  @Test("A name or key containing JSON-breaking characters still produces valid JSON")
  func namesWithJSONBreakingCharactersStayValid() throws {
    var options = ExportOptions.default
    options.shape = .designTokens
    options.name = "say \"hi\"\\"

    let entries = [
      PaletteEntry(key: "a\"b\\c", color: Self.blue),
      PaletteEntry(key: "d", color: ExportShapeTests.red),
    ]
    let rendered = options.render(entries)
    let document = try Self.decode(rendered)
    #expect(document.colors.count == 2, "\(rendered)")
  }

  /// A token file never gamut-maps, so there is no format to count against at all —
  /// `nil`, not the fallback format some other hidden-format shape would answer.
  @Test("designTokens has no mapped-count format")
  func noMappedCountFormat() {
    var options = ExportOptions.default
    options.shape = .designTokens
    #expect(options.mappedCountFormat == nil)
  }
}
