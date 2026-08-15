//
//  CSSFormattingTests.swift
//  ColorKitTests
//

@testable import ColorKit
import Foundation
import Testing

/// Formats that round-trip any color at full precision — including out-of-gamut
/// ones, provided serialization is told to preserve rather than map.
///
/// Worth stating because HSL looks like it should be the exception and isn't. Its
/// negative-saturation normalization (rotate hue 180°, take the magnitude —
/// w3c/csswg-drafts#9222) fires whenever HSL lightness falls outside [0, 1], which
/// happens well beyond the sRGB gamut. That is a *renormalization*, not a collapse:
/// it produces a different HSL triple describing the same sRGB color, and
/// `hslToSRGB` maps it straight back. The out-of-gamut samples below exercise that
/// branch and still round-trip.
///
/// hex is excluded — 8-bit quantization genuinely does lose information.
private let fullPrecisionFormats: [CSSOutputFormat] = [
  .lab, .lch, .oklab, .oklch, .color(.xyzD65), .color(.xyzD50),
  .rgb, .hsl, .hwb, .color(.srgb), .color(.displayP3), .color(.rec2020),
]

private let allFormats: [CSSOutputFormat] = fullPrecisionFormats + [.hex]

private let sampleColors: [ColorValue] = [
  .srgb8(255, 0, 0),
  .srgb8(0, 128, 64),
  .srgb8(17, 34, 51),
  .srgb8(128, 128, 128),
  .srgb8(0, 0, 0),
  .srgb8(255, 255, 255),
  ColorValue(space: .srgb, 0.3, 0.6, 0.9, alpha: 0.5),
  ColorValue(space: .oklch, 0.7, 0.15, 200),
  ColorValue(space: .lab, 62.2, -34.9, 47.6),
  // Out of sRGB, so bounded formats serialize negative / >1 channels.
  ColorValue(space: .oklch, 0.9, 0.35, 140),
  // Far enough out that HSL lightness leaves [0, 1] and the negative-saturation
  // branch fires — the case most likely to break a round trip, and doesn't.
  ColorValue(space: .oklch, 1.05, 0.1, 140),
  ColorValue(space: .lab, -20, 40, 40),
]

@Suite("CSS formatting")
struct CSSFormattingTests {
  // MARK: - Round trips

  @Test("Serializing is a fixed point from the first pass onward")
  func serializationIsIdempotent() throws {
    // The naive invariant `parse(serialize(c)) == c` is false for unavoidable
    // reasons: precision rounds, and hex is 8-bit. What must hold is that
    // serializing is stable once it has happened — otherwise a value could drift
    // every time the UI re-renders it.
    for color in sampleColors {
      for format in allFormats {
        guard let first = color.cssString(as: format) else { continue }
        let reparsed = try CSSColorParser.parse(first).color
        let second = reparsed.cssString(as: format)
        #expect(
          first == second,
          "\(describe(format)) not idempotent: \(first) → \(second ?? "nil")",
        )
      }
    }
  }

  @Test("Full-precision formats round-trip back to the same color")
  func losslessFormatsPreserveValue() throws {
    // Never applied to hex, which is 8-bit by definition. Bounded formats are
    // additionally skipped for colors outside their gamut — see the note on
    // `boundedFormats` for why HSL in particular cannot round-trip there.
    let options = CSSFormatOptions(precision: 12, gamut: .preserve)

    for color in sampleColors {
      for format in fullPrecisionFormats {
        guard let text = color.cssString(as: format, options: options) else { continue }
        let returned = try CSSColorParser.parse(text).color.converted(to: color.space)

        for i in 0 ..< 3 {
          let expected = color.components[i]
          #expect(
            abs(returned.components[i] - expected) <= 1e-6 * max(1, abs(expected)),
            "\(describe(format)) drifted: \(text) → \(returned.components) vs \(color.components)",
          )
        }
        #expect(abs(returned.alpha - color.alpha) < 1e-9)
      }
    }
  }

  // MARK: - Gamut behavior on output

  @Test("Formats that cannot express out-of-gamut values always map")
  func boundedFormatsAlwaysMap() throws {
    // Out of sRGB by a wide margin.
    let vivid = ColorValue(space: .oklch, 0.9, 0.3, 140)
    #expect(!vivid.inGamut(of: .srgb))

    // hex is 8-bit unsigned — a negative channel has no spelling, so mapping is
    // not optional even when the caller asks to preserve.
    let hex = try #require(vivid.cssString(as: .hex, options: CSSFormatOptions(gamut: .preserve)))
    #expect(hex.count == 7, "expected #rrggbb, got \(hex)")
    let reparsed = try CSSColorParser.parse(hex).color
    #expect(reparsed.inGamut(of: .srgb))
  }

  @Test("Gamut policy controls formats that can hold out-of-range values")
  func gamutPolicyIsRespected() throws {
    let vivid = ColorValue(space: .oklch, 0.9, 0.3, 140)

    // `.map` — output renders as shown in a browser.
    let mapped = try #require(vivid.cssString(as: .rgb, options: CSSFormatOptions(gamut: .map)))
    let mappedColor = try CSSColorParser.parse(mapped).color
    #expect(mappedColor.inGamut(of: .srgb, epsilon: 1e-6), "\(mapped) should be in gamut")

    // `.preserve` — faithful to the authored color; a browser would clamp it.
    let preserved = try #require(
      vivid.cssString(as: .rgb, options: CSSFormatOptions(gamut: .preserve)),
    )
    let preservedColor = try CSSColorParser.parse(preserved).color
    #expect(!preservedColor.inGamut(of: .srgb), "\(preserved) should stay out of gamut")
  }

  @Test("HSL's negative-saturation normalization is reversible")
  func hslNegativeSaturationRoundTrips() {
    // When HSL lightness leaves [0, 1], CSS rewrites the color by rotating the
    // hue 180° and taking |saturation| (w3c/csswg-drafts#9222). It looks lossy —
    // it isn't. The rewritten triple describes the same sRGB color, so the
    // inverse recovers the original exactly. Pinned because the plausible
    // assumption here is the wrong one.
    let extreme = ColorValue(space: .oklch, 1.05, 0.1, 140)
    let srgb = extreme.converted(to: .srgb).components
    let hslLightness = (min(srgb.x, srgb.y, srgb.z) + max(srgb.x, srgb.y, srgb.z)) / 2
    #expect(hslLightness > 1, "sample must actually trigger the branch")

    let hsl = extreme.converted(to: .hsl)
    #expect(hsl.components.y >= 0, "saturation is normalized to a magnitude")

    let returned = hsl.converted(to: .oklch)
    for i in 0 ..< 3 {
      #expect(abs(returned.components[i] - extreme.components[i]) < 1e-9)
    }
  }

  @Test("Mapping preserves hue rather than clipping it")
  func mappingIsPerceptual() throws {
    let vivid = ColorValue(space: .oklch, 0.85, 0.35, 145)
    let text = try #require(vivid.cssString(as: .rgb))
    let mappedHue = try CSSColorParser.parse(text).color.converted(to: .oklch).components.z
    let distance = min(abs(mappedHue - 145), 360 - abs(mappedHue - 145))
    #expect(distance < 5, "hue drifted to \(mappedHue) from 145")
  }

  // MARK: - Format specifics

  @Test("Default output is modern syntax with alpha only when needed")
  func defaultOutput() {
    let red = ColorValue.srgb8(255, 0, 0)
    #expect(red.cssString(as: .rgb) == "rgb(255 0 0)")
    #expect(red.cssString(as: .hex) == "#ff0000")

    let translucent = ColorValue.srgb8(255, 0, 0, alpha: 0.5)
    #expect(translucent.cssString(as: .rgb) == "rgb(255 0 0 / 0.5)")
    #expect(translucent.cssString(as: .hex) == "#ff000080")
  }

  @Test("Legacy output uses commas and the rgba/hsla spelling")
  func legacyOutput() {
    let opaque = ColorValue.srgb8(255, 0, 0)
    let translucent = ColorValue.srgb8(255, 0, 0, alpha: 0.5)
    let legacy = CSSFormatOptions(legacy: true)

    #expect(opaque.cssString(as: .rgb, options: legacy) == "rgb(255, 0, 0)")
    #expect(translucent.cssString(as: .rgb, options: legacy) == "rgba(255, 0, 0, 0.5)")
    #expect(
      ColorValue(space: .hsl, 120, 50, 50).cssString(as: .hsl, options: legacy)
        == "hsl(120, 50%, 50%)",
    )
  }

  @Test("Legacy output never emits none, which is invalid there")
  func legacyNeverEmitsNone() throws {
    let gray = ColorValue(space: .hsl, 0, 0, 50, missing: .first)
    let legacy = try #require(gray.cssString(as: .hsl, options: CSSFormatOptions(legacy: true)))
    #expect(!legacy.contains("none"), "legacy syntax has no spelling for none: \(legacy)")
    // And it must still parse.
    #expect(throws: Never.self) { try CSSColorParser.parse(legacy) }
  }

  @Test("Authored none survives a serialize/parse round trip")
  func nonePreserved() throws {
    let authored = try CSSColorParser.parse("oklch(0.5 none 200)").color
    let text = try #require(authored.cssString(as: .oklch))
    #expect(text.contains("none"), "expected none in \(text)")
    #expect(try CSSColorParser.parse(text).color.missing.contains(.second))
  }

  @Test("Powerless hues can be written as none on request")
  func powerlessHueOutput() throws {
    let gray = ColorValue.srgb8(128, 128, 128)
    let plain = try #require(gray.cssString(as: .oklch))
    #expect(!plain.contains("none"), "off by default")

    let flagged = try #require(
      gray.cssString(as: .oklch, options: CSSFormatOptions(noneForPowerlessComponents: true)),
    )
    #expect(flagged.contains("none"), "expected a powerless hue in \(flagged)")
  }

  @Test("hex options behave")
  func hexOptions() {
    let color = ColorValue.srgb8(255, 204, 0)
    #expect(color.cssString(as: .hex) == "#ffcc00")
    #expect(color.cssString(as: .hex, options: CSSFormatOptions(collapseHex: true)) == "#fc0")
    #expect(color.cssString(as: .hex, options: CSSFormatOptions(uppercaseHex: true)) == "#FFCC00")

    // Not collapsible — every pair must repeat.
    let odd = ColorValue.srgb8(255, 204, 1)
    #expect(odd.cssString(as: .hex, options: CSSFormatOptions(collapseHex: true)) == "#ffcc01")
  }

  @Test("Keyword output returns nil when no keyword exists, and hex fills in")
  func keywordFallback() {
    #expect(ColorValue.srgb8(255, 0, 0).cssString(as: .keyword) == "red")
    #expect(ColorValue.srgb8(102, 51, 153).cssString(as: .keyword) == "rebeccapurple")

    let unnamed = ColorValue(space: .srgb, 0.123, 0.456, 0.789)
    #expect(unnamed.cssString(as: .keyword) == nil)
    #expect(unnamed.cssStringOrHex(as: .keyword).hasPrefix("#"))
  }

  @Test("rgb() can be written as percentages")
  func rgbPercentages() {
    let red = ColorValue.srgb8(255, 0, 0)
    #expect(
      red.cssString(as: .rgb, options: CSSFormatOptions(rgbAsPercentage: true))
        == "rgb(100% 0% 0%)",
    )
  }

  @Test("Lightness uses each space's conventional form")
  func lightnessConventions() {
    // Lab/LCH lightness runs 0–100 and is conventionally written as a percentage;
    // OKLab/OKLCH runs 0–1 and is conventionally a number.
    #expect(ColorValue(space: .lab, 50, 20, 30).cssString(as: .lab) == "lab(50% 20 30)")
    #expect(ColorValue(space: .lch, 50, 30, 200).cssString(as: .lch) == "lch(50% 30 200)")
    #expect(ColorValue(space: .oklab, 0.5, 0.1, 0.1).cssString(as: .oklab) == "oklab(0.5 0.1 0.1)")
    #expect(ColorValue(space: .oklch, 0.7, 0.15, 200).cssString(as: .oklch) == "oklch(0.7 0.15 200)")
  }

  @Test("color() emits each predefined space identifier")
  func colorFunctionOutput() {
    let red = ColorValue.srgb8(255, 0, 0)
    #expect(red.cssString(as: .color(.srgb)) == "color(srgb 1 0 0)")
    #expect(red.cssString(as: .color(.displayP3))?.hasPrefix("color(display-p3 ") == true)
    #expect(red.cssString(as: .color(.xyzD50))?.hasPrefix("color(xyz-d50 ") == true)
    // hsl has no color() spelling.
    #expect(red.cssString(as: .color(.hsl)) == nil)
  }

  @Test("Decimal Precision is honored and trailing zeros stripped")
  func precision() {
    let color = ColorValue(space: .oklch, 0.123456789, 0.198765, 200.5)
    // Hue is on a 0–360 scale, so it loses two decimals relative to lightness.
    // At precision 2 that leaves whole degrees — which is the point: `oklch(0.12
    // 0.2 201)` is a coherent compact form, where 0.12 alongside 200.5 would be
    // claiming three more significant digits for the hue than for the lightness.
    #expect(color.cssString(as: .oklch, options: CSSFormatOptions(precision: 2)) == "oklch(0.12 0.2 201)")
    #expect(color.cssString(as: .oklch, options: CSSFormatOptions(precision: 5)) == "oklch(0.12346 0.19877 200.5)")
  }

  /// The defect this fixes: at a flat four decimals the panel reported a hue of
  /// `217.2193` — a ten-thousandth of a degree, which is noise dressed as accuracy.
  @Test("Decimal Precision follows each component's scale, not a flat decimal count")
  func precisionIsRelativeToComponentScale() {
    let blue = ColorValue.srgb8(59, 130, 246)

    #expect(blue.cssString(as: .hsl) == "hsl(217.22 91.22% 59.8%)")
    #expect(blue.cssString(as: .hwb) == "hwb(217.22 23.14% 3.53%)")
    #expect(blue.cssString(as: .oklch) == "oklch(0.6231 0.188 259.81)")
    #expect(blue.cssString(as: .oklab) == "oklab(0.6231 -0.0332 -0.1851)")
    #expect(blue.cssString(as: .lch) == "lch(54.62% 66.37 277.59)")
    #expect(blue.cssString(as: .lab) == "lab(54.62% 8.76 -65.79)")
    // Unit-scale channels keep the full four.
    #expect(blue.cssString(as: .color(.displayP3)) == "color(display-p3 0.3047 0.5035 0.9338)")
  }

  @Test(
    "Decimals fall by one per power of ten above unit scale",
    arguments: [
      (fullScale: 1.0, expected: 4), // oklch lightness, color() channels
      (fullScale: 0.4, expected: 4), // oklab a/b — clamped, never gains digits
      (fullScale: 100.0, expected: 2), // percentages
      (fullScale: 125.0, expected: 2), // lab a/b
      (fullScale: 150.0, expected: 2), // lch chroma
      (fullScale: 255.0, expected: 2), // rgb channels
      (fullScale: 360.0, expected: 2), // hue
    ],
  )
  func decimalsForScale(fullScale: Double, expected: Int) {
    #expect(CSSFormatOptions(precision: 4).decimals(forFullScale: fullScale) == expected)
  }

  @Test("Component grammars report the scale they are written on")
  func grammarsKnowTheirScale() {
    #expect(ColorGrammar.components(for: .rgb)[0].fullScale == 255)
    #expect(ColorGrammar.components(for: .hsl)[0].fullScale == 360)
    #expect(ColorGrammar.components(for: .hsl)[1].fullScale == 100)
    #expect(ColorGrammar.components(for: .lab)[1].fullScale == 125)
    #expect(ColorGrammar.components(for: .lch)[1].fullScale == 150)
    #expect(ColorGrammar.components(for: .oklab)[1].fullScale == 0.4)
    #expect(ColorGrammar.components(for: .oklch)[2].fullScale == 360)
    #expect(ColorGrammar.components(for: .color)[0].fullScale == 1)
  }

  @Test("Alpha policy is honored")
  func alphaPolicy() {
    let opaque = ColorValue.srgb8(255, 0, 0)
    #expect(opaque.cssString(as: .rgb, options: CSSFormatOptions(alpha: .always)) == "rgb(255 0 0 / 1)")
    #expect(opaque.cssString(as: .rgb, options: CSSFormatOptions(alpha: .never)) == "rgb(255 0 0)")

    let translucent = ColorValue.srgb8(255, 0, 0, alpha: 0.25)
    #expect(translucent.cssString(as: .rgb, options: CSSFormatOptions(alpha: .never)) == "rgb(255 0 0)")
  }

  @Test("Negative zero is never emitted")
  func noNegativeZero() {
    let color = ColorValue(space: .oklab, 0.5, -0.0000001, 0)
    let text = color.cssString(as: .oklab, options: CSSFormatOptions(precision: 3))
    #expect(text?.contains("-0") == false, "got \(text ?? "nil")")
  }

  // MARK: - Codable (M19: Preferences persists both types)

  /// `CSSOutputFormat` is hand-written Codable, unlike `CSSFormatOptions` below —
  /// see the doc comment on its conformance for why. Exercised over the whole
  /// catalog rather than one case, so a copy-paste slip in one branch of the
  /// encoder or decoder switch has somewhere to show up.
  @Test("Every catalog format survives an encode/decode round trip")
  func formatCodableRoundTrips() throws {
    for format in CSSOutputFormat.catalog {
      let data = try JSONEncoder().encode(format)
      let decoded = try JSONDecoder().decode(CSSOutputFormat.self, from: data)
      #expect(decoded == format, Comment(rawValue: describe(format)))
    }
  }

  @Test("An unrecognized format identifier fails to decode rather than substituting one")
  func unknownFormatIdentifierFailsToDecode() throws {
    let data = try JSONEncoder().encode("not-a-format")
    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(CSSOutputFormat.self, from: data)
    }
  }

  /// `CSSFormatOptions` is synthesized Codable, so this is a sanity check that the
  /// two new `String`-raw-value enums it gained — `AlphaPolicy` and `GamutPolicy` —
  /// actually participate rather than tripping synthesis silently.
  @Test("CSSFormatOptions survives an encode/decode round trip with every field changed")
  func formatOptionsCodableRoundTrips() throws {
    let options = CSSFormatOptions(
      precision: 7,
      legacy: true,
      rgbAsPercentage: true,
      collapseHex: true,
      uppercaseHex: true,
      alpha: .never,
      gamut: .preserve,
      noneForPowerlessComponents: true,
    )

    let data = try JSONEncoder().encode(options)
    let decoded = try JSONDecoder().decode(CSSFormatOptions.self, from: data)

    #expect(decoded == options)
    #expect(decoded != CSSFormatOptions())
  }
}

private func describe(_ format: CSSOutputFormat) -> String {
  switch format {
  case let .color(space): "color(\(space.rawValue))"
  case .hex: "hex"
  case .keyword: "keyword"
  case .rgb: "rgb"
  case .hsl: "hsl"
  case .hwb: "hwb"
  case .lab: "lab"
  case .lch: "lch"
  case .oklab: "oklab"
  case .oklch: "oklch"
  }
}
