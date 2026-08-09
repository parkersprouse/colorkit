//
//  ColorCoreTests.swift
//  ColorKitTests
//
//  Anchors and invariants that do NOT come from the reference fixture.
//
//  ReferenceVectorTests proves ColorCore agrees with colorjs.io. That is worth a
//  lot, but it cannot catch a fixture that was generated wrong — a broken generator
//  producing garbage both sides agree on would sail straight through. These tests
//  assert values derived from the definitions themselves, so they fail
//  independently.
//

@testable import ColorKit
import Foundation
import Testing

@Suite("Color core invariants")
struct ColorCoreTests {
  // MARK: - Definitional anchors

  @Test("White is the reference white in every lightness-bearing space")
  func whiteIsDefinitional() {
    let white = ColorValue(space: .srgb, 1, 1, 1)

    // Lab is D50-referenced, and sRGB white adapts exactly onto that white
    // point — so L must be 100 with no chroma. If the Bradford adaptation were
    // missing or reversed, a and b would drift off zero here.
    let lab = white.converted(to: .lab).components
    #expect(abs(lab.x - 100) < 1e-9)
    #expect(abs(lab.y) < 1e-9)
    #expect(abs(lab.z) < 1e-9)

    // OKLab is defined so that D65 white sits at L = 1.
    let oklab = white.converted(to: .oklab).components
    #expect(abs(oklab.x - 1) < 1e-9)
    #expect(abs(oklab.y) < 1e-9)
    #expect(abs(oklab.z) < 1e-9)
  }

  @Test("Black is zero everywhere")
  func blackIsZero() {
    let black = ColorValue(space: .srgb, 0, 0, 0)
    #expect(abs(black.converted(to: .lab).components.x) < 1e-9)
    #expect(abs(black.converted(to: .oklab).components.x) < 1e-9)
    #expect(abs(black.converted(to: .xyzD65).components.y) < 1e-9)
  }

  @Test("sRGB primaries land on their textbook HSL values")
  func primariesMatchTextbookHSL() {
    let cases: [(ColorValue, Double)] = [
      (.srgb8(255, 0, 0), 0),
      (.srgb8(255, 255, 0), 60),
      (.srgb8(0, 255, 0), 120),
      (.srgb8(0, 255, 255), 180),
      (.srgb8(0, 0, 255), 240),
      (.srgb8(255, 0, 255), 300),
    ]
    for (color, expectedHue) in cases {
      let hsl = color.converted(to: .hsl).components
      #expect(abs(hsl.x - expectedHue) < 1e-9, "hue for \(color.components)")
      #expect(abs(hsl.y - 100) < 1e-9, "saturation should be 100%")
      #expect(abs(hsl.z - 50) < 1e-9, "lightness should be 50%")
    }
  }

  @Test("Mid gray has zero saturation and is achromatic")
  func grayIsAchromatic() {
    let gray = ColorValue.srgb8(128, 128, 128)
    #expect(abs(gray.converted(to: .hsl).components.y) < 1e-9)
    #expect(gray.isAchromatic)

    // And its powerless hue is flagged rather than fabricated.
    let marked = gray.converted(to: .oklch).markingPowerlessComponents()
    #expect(marked.missing.contains(.component(2)))
    #expect(marked.components.z == 0)
  }

  @Test("A saturated color is not mistaken for achromatic")
  func saturatedColorIsNotAchromatic() {
    #expect(!ColorValue.srgb8(255, 0, 0).isAchromatic)
    #expect(!ColorValue.srgb8(130, 128, 128).isAchromatic)
  }

  // MARK: - Named colors

  @Test("Named colors resolve and round-trip to their keyword")
  func namedColorsResolve() {
    #expect(NamedColors.table.count == 148, "CSS Color 4 defines 148 named colors")

    let rebecca = ColorValue.named("rebeccapurple")
    #expect(rebecca == .srgb8(102, 51, 153))
    #expect(rebecca?.namedKeyword == "rebeccapurple")

    #expect(ColorValue.named("red") == .srgb8(255, 0, 0))
    #expect(ColorValue.named("RED") == .srgb8(255, 0, 0), "keywords are case-insensitive")
    #expect(ColorValue.named("notacolor") == nil)

    // `transparent` is black at zero alpha, per spec.
    let transparent = ColorValue.named("transparent")
    #expect(transparent?.alpha == 0)
    #expect(transparent?.components == SIMD3(0, 0, 0))
  }

  @Test("Colors with two spellings resolve to a stable, conventional keyword")
  func collidingKeywordsAreDeterministic() {
    // Nine RGB values have two names, and every pair is the same length — so a
    // length-only tie-break would leave the winner to Dictionary iteration order,
    // which Swift randomizes per launch. These assertions pin the choice.
    #expect(ColorValue.srgb8(128, 128, 128).namedKeyword == "gray")
    #expect(ColorValue.srgb8(0, 255, 255).namedKeyword == "aqua")
    #expect(ColorValue.srgb8(255, 0, 255).namedKeyword == "fuchsia")
    #expect(ColorValue.srgb8(169, 169, 169).namedKeyword == "darkgray")
    #expect(ColorValue.srgb8(105, 105, 105).namedKeyword == "dimgray")
    #expect(ColorValue.srgb8(211, 211, 211).namedKeyword == "lightgray")
    #expect(ColorValue.srgb8(112, 128, 144).namedKeyword == "slategray")
    #expect(ColorValue.srgb8(47, 79, 79).namedKeyword == "darkslategray")
    #expect(ColorValue.srgb8(119, 136, 153).namedKeyword == "lightslategray")

    // Both spellings must still parse, even though only one serializes back.
    #expect(ColorValue.named("grey") == ColorValue.named("gray"))
    #expect(ColorValue.named("cyan") == ColorValue.named("aqua"))
    #expect(ColorValue.named("magenta") == ColorValue.named("fuchsia"))
  }

  @Test("A color with no keyword spelling reports none")
  func unnamedColorHasNoKeyword() {
    #expect(ColorValue(space: .srgb, 0.123, 0.456, 0.789).namedKeyword == nil)
    #expect(ColorValue.srgb8(255, 0, 0, alpha: 0.5).namedKeyword == nil, "alpha has no keyword")
  }

  // MARK: - Round trips

  @Test("sRGB survives a round trip through every space", arguments: ColorSpace.allCases)
  func roundTripThroughSpace(space: ColorSpace) {
    // Deliberately in-gamut and non-gray, so nothing is legitimately lossy.
    let samples: [ColorValue] = [
      .srgb8(255, 0, 0),
      .srgb8(0, 128, 64),
      .srgb8(17, 34, 51),
      .srgb8(240, 248, 255),
      ColorValue(space: .srgb, 0.3, 0.6, 0.9),
    ]

    for original in samples {
      let returned = original.converted(to: space).converted(to: .srgb)
      for i in 0 ..< 3 {
        #expect(
          abs(returned.components[i] - original.components[i]) < 1e-9,
          "\(space.rawValue) round trip drifted on channel \(i): \(original.components) → \(returned.components)",
        )
      }
    }
  }

  @Test("Alpha is preserved across conversions", arguments: ColorSpace.allCases)
  func alphaSurvivesConversion(space: ColorSpace) {
    let color = ColorValue(space: .srgb, 0.2, 0.4, 0.6, alpha: 0.35)
    #expect(color.converted(to: space).alpha == 0.35)
  }

  // MARK: - Gamut behavior

  @Test("Gamut containment is per-color, not a ranking of space widths")
  func wideGamutDetection() {
    let p3Red = ColorValue(space: .displayP3, 1, 0, 0)
    #expect(!p3Red.inGamut(of: .srgb), "P3 red exceeds sRGB")
    #expect(p3Red.inGamut(of: .displayP3))

    // Counterintuitive but true, and worth pinning down: Rec.2020 is the "wider"
    // space by area, yet it does NOT contain Display P3. Containment depends on
    // the shape of the chromaticity triangle, and P3's red primary sits just
    // outside the edge between Rec.2020's red and green corners — the blue
    // channel comes out at about -0.061.
    #expect(!p3Red.inGamut(of: .rec2020), "P3 red falls outside the Rec.2020 triangle")
    #expect(p3Red.converted(to: .rec2020).components.z < 0)

    // sRGB, by contrast, genuinely is a subset of both.
    let srgbRed = ColorValue.srgb8(255, 0, 0)
    #expect(srgbRed.inGamut(of: .displayP3))
    #expect(srgbRed.inGamut(of: .rec2020))
  }

  @Test("Gamut mapping lands inside the target and preserves hue better than clipping")
  func gamutMappingBeatsClipping() {
    // A vivid out-of-sRGB green — the case where naive clipping shifts hue most.
    let vivid = ColorValue(space: .oklch, 0.85, 0.35, 145)
    #expect(!vivid.inGamut(of: .srgb))

    let mapped = vivid.gamutMapped(to: .srgb)
    #expect(mapped.inGamut(of: .srgb, epsilon: 1e-9), "mapped color must be in gamut")

    let mappedHue = mapped.converted(to: .oklch).components.z
    let clippedHue = vivid.clipped(to: .srgb).converted(to: .oklch).components.z

    func hueDistance(_ a: Double, _ b: Double) -> Double {
      let d = abs(Conversion.constrainAngle(a - b))
      return min(d, 360 - d)
    }

    #expect(
      hueDistance(mappedHue, 145) <= hueDistance(clippedHue, 145) + 1e-9,
      "chroma reduction should hold hue at least as well as clipping",
    )
  }

  @Test("Unbounded spaces are always in gamut")
  func unboundedSpacesAlwaysInGamut() {
    let extreme = ColorValue(space: .oklch, 0.5, 0.9, 200)
    #expect(extreme.inGamut(of: .oklch))
    #expect(extreme.inGamut(of: .lab))
    #expect(!extreme.inGamut(of: .srgb))
  }

  @Test("Lightness past either end maps to black or white")
  func extremeLightnessClamps() {
    let tooLight = ColorValue(space: .oklch, 1.5, 0.2, 100).gamutMapped(to: .srgb)
    #expect(tooLight.components.min() > 1 - 1e-6, "should be white")

    let tooDark = ColorValue(space: .oklch, -0.5, 0.2, 100).gamutMapped(to: .srgb)
    #expect(tooDark.components.max() < 1e-6, "should be black")
  }

  // MARK: - Space metadata

  @Test("Space families route conversions correctly")
  func familyGrouping() {
    #expect(ColorSpace.srgb.family == .srgbEncoded)
    #expect(ColorSpace.hsl.family == .srgbEncoded)
    #expect(ColorSpace.hwb.family == .srgbEncoded)
    #expect(ColorSpace.lab.family == ColorSpace.lch.family)
    #expect(ColorSpace.oklab.family == ColorSpace.oklch.family)
    #expect(ColorSpace.lab.family != ColorSpace.oklab.family, "different white points")
  }

  @Test("Hue indices are correct where they exist")
  func hueIndices() {
    #expect(ColorSpace.hsl.hueIndex == 0)
    #expect(ColorSpace.hwb.hueIndex == 0)
    #expect(ColorSpace.lch.hueIndex == 2)
    #expect(ColorSpace.oklch.hueIndex == 2)
    #expect(ColorSpace.srgb.hueIndex == nil)
    #expect(ColorSpace.lab.hueIndex == nil)
  }

  @Test("Transfer functions are sign-preserving, not clamping")
  func transferFunctionsPreserveSign() {
    // Out-of-gamut colors carry negative channels. A clamping transfer function
    // would silently destroy them on every conversion.
    #expect(TransferFunction.srgbEncode(-0.5) < 0)
    #expect(TransferFunction.srgbDecode(-0.5) < 0)
    #expect(abs(TransferFunction.srgbDecode(TransferFunction.srgbEncode(-0.5)) + 0.5) < 1e-12)
    #expect(abs(TransferFunction.a98Decode(TransferFunction.a98Encode(-0.3)) + 0.3) < 1e-12)
    #expect(abs(TransferFunction.proPhotoDecode(TransferFunction.proPhotoEncode(-0.3)) + 0.3) < 1e-12)
    #expect(abs(TransferFunction.rec2020Decode(TransferFunction.rec2020Encode(-0.3)) + 0.3) < 1e-12)
  }

  @Test("deltaEOK is zero for identical colors and grows with difference")
  func deltaEOKBehaves() {
    let red = ColorValue.srgb8(255, 0, 0)
    #expect(red.deltaEOK(to: red) < 1e-12)

    let nearRed = ColorValue.srgb8(250, 5, 5)
    let blue = ColorValue.srgb8(0, 0, 255)
    #expect(red.deltaEOK(to: nearRed) < red.deltaEOK(to: blue))
  }

  // MARK: - Achromatic hues

  /// A grey that arrives through a conversion has hue `0`, not numerical dust.
  ///
  /// **This is a regression test with a shipped artifact behind it.** A greyscale ramp
  /// exported as `hsl()` read `hsl(336 0% 96.06%)`, `hsl(350 0% 87.86%)`,
  /// `hsl(345 0% 79.79%)` — the hue wandering across eleven colors that have no hue.
  /// `srgbToHSL` and `srgbToHSV` guarded on `delta != 0`, an *exact* test, so a grey whose
  /// channels differ in the last ULP took the chromatic branch and computed its hue as a
  /// ratio of two pieces of noise.
  ///
  /// **The competing hypothesis is not "slightly off" but "any angle at all"**, which is
  /// why this asserts exact equality rather than a tolerance. The unfixed code returned
  /// 336° for the first stop here; there is no tolerance that separates 336 from 0 without
  /// also admitting every other wrong answer.
  ///
  /// `lch()` and `oklch()` were always right — ``rectangularToPolar`` has had the epsilon
  /// guard from the start — so they are included to pin the agreement rather than because
  /// they were broken.
  @Test(
    "A converted grey has no hue in any polar space",
    arguments: [0.97, 0.9068, 0.8436, 0.7804, 0.654, 0.3696, 0.18],
  )
  func convertedGreysHaveNoHue(lightness: Double) throws {
    let grey = ColorValue(space: .oklch, lightness, 0, 0)

    for space in [ColorSpace.hsl, .hwb, .lch, .oklch] {
      let hueIndex = try #require(space.hueIndex, "\(space) should have a hue component")
      let hue = grey.converted(to: space).components[hueIndex]
      #expect(
        hue == 0,
        "\(space) fabricated a hue of \(hue) for a neutral grey at lightness \(lightness)",
      )
    }
  }

  /// The epsilon rejects dust without swallowing a hue that is real.
  ///
  /// The other half of the claim, and the one that stops the fix from being a blunt
  /// "greys are hueless" rule that also flattens near-greys. `#010203` is the sharpest
  /// case in the 8-bit grid: adjacent channel values at the darkest end, a saturation of
  /// 50%, and a genuine hue of 210°. Its channel delta is `2/255 ≈ 7.8e-3`, which is 780×
  /// the threshold — so the margin is not close.
  @Test("A real hue survives, however faint")
  func faintHuesAreNotFlattened() {
    let darkNearGrey = ColorValue.srgb8(0x01, 0x02, 0x03).converted(to: .hsl)
    #expect(abs(darkNearGrey.components[0] - 210) < 1e-9)
    #expect(darkNearGrey.components[1] > 49)

    // And one just above the threshold, constructed rather than found: a delta of 1e-4 is
    // ten times `achromaticChannelEpsilon` and must still report its hue.
    let barelyBlue = ColorValue(space: .srgb, 0.5, 0.5, 0.5001).converted(to: .hsl)
    #expect(barelyBlue.components[0] == 240)
  }

  /// The threshold sits far from anything either side could care about.
  ///
  /// Stated as a discrimination rather than a magic number: the dust it rejects is around
  /// `1e-16`, and the smallest real difference the 8-bit grid can express is `1/255`. The
  /// epsilon must sit between them with room to spare, and it is derived the same way
  /// ``ColorSpace/polarEpsilon`` is — the channel's reference range over 100000 — so the
  /// RGB-based polar forms and the Lab-based ones agree about what grey means.
  @Test("The achromatic threshold has margin at both ends")
  func thresholdIsWellPlaced() {
    let epsilon = Conversion.achromaticChannelEpsilon
    #expect(epsilon == 1.0 / 100_000.0)

    // Eleven orders of magnitude above float dust.
    #expect(epsilon > 1e-12)
    // And two below the smallest step the 8-bit grid can express, so no authored color
    // can land under it.
    #expect(epsilon < (1.0 / 255.0) / 100)
  }
}
