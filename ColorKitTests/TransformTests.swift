//
//  TransformTests.swift
//  ColorKitTests
//

@testable import ColorKit
import Foundation
import Testing

/// Proof for the transforms, which have **no oracle** — and that is a feature.
///
/// colorjs.io converts and it maps, but it has no notion of a harmony, a ramp or a
/// relative adjustment, so there is nothing to diff against. The same situation
/// ``GamutBoundaryTests`` is in, and the same answer: assert the *properties* the
/// results are supposed to have. A fixture could only ever pin one implementation's
/// output; a hue exactly 180° away and a chroma preserved to the last bit stay true if
/// the arithmetic is rewritten.
///
/// The conversions underneath are a different matter, and those *are* oracle-validated
/// — 6,384 vectors in ``ReferenceVectorTests``. These tests take that as given and
/// check only what is built on top.
@Suite("OKLCH adjustment")
struct OKLCHAdjustmentTests {
  /// Built in OKLCH so the assertions are exact: nothing converts, so nothing rounds.
  static let base = ColorValue(space: .oklch, 0.65, 0.18, 250)

  @Test("Lightness adds, chroma multiplies, hue rotates")
  func eachAxisUsesItsOwnOperator() {
    let adjusted = OKLCHAdjustment(
      lightnessDelta: 0.1,
      chromaScale: 0.5,
      hueRotation: 40,
    ).applied(to: Self.base)

    let result = adjusted.oklchComponents
    #expect(abs(result.lightness - 0.75) < 1e-12)
    #expect(abs(result.chroma - 0.09) < 1e-12)
    #expect(abs(result.hue - 290) < 1e-12)
  }

  @Test("Identity changes nothing")
  func identityIsIdentity() {
    let adjusted = OKLCHAdjustment.identity.applied(to: Self.base)
    #expect(adjusted.oklchComponents == Self.base.oklchComponents)
    #expect(OKLCHAdjustment.identity.isIdentity)
  }

  /// Hue is an angle, so it comes back into `0..<360` rather than running off.
  @Test(
    "Hue wraps",
    arguments: [
      (350.0, 30.0, 20.0),
      (10.0, -30.0, 340.0),
      (100.0, 720.0, 100.0),
      (0.0, -450.0, 270.0),
    ],
  )
  func hueWrapsIntoRange(start: Double, rotation: Double, expected: Double) {
    let color = ColorValue(space: .oklch, 0.5, 0.1, start)
    let rotated = OKLCHAdjustment(hueRotation: rotation).applied(to: color)
    #expect(abs(rotated.oklchComponents.hue - expected) < 1e-9)
  }

  /// The inverse really inverts, which is what lets a UI offer "reset" as an
  /// adjustment rather than as remembered state.
  @Test("The inverse restores the original")
  func inverseRoundTrips() {
    let adjustment = OKLCHAdjustment(
      lightnessDelta: 0.12,
      chromaScale: 1.8,
      hueRotation: 137,
    )
    let there = adjustment.applied(to: Self.base)
    let back = adjustment.inverted.applied(to: there).oklchComponents

    #expect(abs(back.lightness - 0.65) < 1e-12)
    #expect(abs(back.chroma - 0.18) < 1e-12)
    #expect(abs(back.hue - 250) < 1e-9)
  }

  /// Lightness has real endpoints, so pushing past one and coming back does **not**
  /// restore the color. Pinned rather than fixed: the alternative is a lightness that
  /// runs past white, which is not a color, and clamping is the honest response.
  @Test("Lightness clamps, and clamping is not reversible")
  func lightnessClampsIrreversibly() {
    let adjustment = OKLCHAdjustment(lightnessDelta: 0.9)
    let clipped = adjustment.applied(to: Self.base)
    #expect(clipped.oklchComponents.lightness == 1)

    let back = adjustment.inverted.applied(to: clipped).oklchComponents
    #expect(abs(back.lightness - 0.1) < 1e-12, "expected 1 - 0.9, not the original 0.65")
  }

  /// Chroma cannot go negative: less saturated than gray is not a direction.
  @Test("Negative chroma folds to zero, not to the opposite hue")
  func chromaFloorsAtZero() {
    let adjusted = OKLCHAdjustment(chromaScale: -2).applied(to: Self.base)
    #expect(adjusted.oklchComponents.chroma == 0)
  }

  /// A scale of zero destroys the chroma, and no inverse brings it back. Asserted so
  /// the reciprocal in ``OKLCHAdjustment/inverted`` is never "tidied" into a divide by
  /// zero that returns infinity.
  @Test("A zero chroma scale has no inverse, and says so by staying zero")
  func zeroScaleHasNoInverse() {
    let flattened = OKLCHAdjustment(chromaScale: 0).applied(to: Self.base)
    #expect(flattened.oklchComponents.chroma == 0)

    let back = OKLCHAdjustment(chromaScale: 0).inverted.applied(to: flattened)
    #expect(back.oklchComponents.chroma == 0)
    #expect(back.oklchComponents.chroma.isFinite)
  }

  @Test("Alpha survives every axis")
  func alphaIsCarried() {
    let translucent = ColorValue(space: .oklch, 0.5, 0.1, 20, alpha: 0.4)
    let adjusted = OKLCHAdjustment(
      lightnessDelta: 0.2, chromaScale: 2, hueRotation: 90,
    ).applied(to: translucent)
    #expect(adjusted.alpha == 0.4)
  }

  /// Results stay in OKLCH rather than returning to the input's space, and the reason
  /// is this: a round trip through hex would quantize onto the 8-bit grid, so a nudge
  /// finer than 1/255 would come back as the color you started with. The picker
  /// learned the same lesson in M6.
  @Test("An sRGB input does not drag the result back onto the 8-bit grid")
  func resultsAreNotQuantized() {
    let hexColor = ColorValue.srgb8(0x3B, 0x82, 0xF6)

    let nudged = OKLCHAdjustment(lightnessDelta: 1e-6).applied(to: hexColor)
    let unnudged = OKLCHAdjustment.identity.applied(to: hexColor)

    #expect(nudged.space == .oklch)
    #expect(nudged != unnudged, "a sub-8-bit nudge was rounded away")
    #expect(
      abs(nudged.oklchComponents.lightness - unnudged.oklchComponents.lightness - 1e-6)
        < 1e-12,
    )
  }
}

@Suite("Lightness curve")
struct LightnessCurveTests {
  /// Black, mid-gray and white are the curve's fixed points, which is what keeps it
  /// from pushing anything out of the lightness range.
  @Test("The curve pins 0, 0.5 and 1", arguments: [-1.0, -0.5, 0.0, 0.5, 1.0])
  func fixedPoints(strength: Double) {
    let gamma = LightnessCurve(strength: strength).gamma
    #expect(abs(LightnessCurve.curve(0, gamma: gamma) - 0) < 1e-12)
    #expect(abs(LightnessCurve.curve(0.5, gamma: gamma) - 0.5) < 1e-12)
    #expect(abs(LightnessCurve.curve(1, gamma: gamma) - 1) < 1e-12)
  }

  /// Monotonic, or the curve could reorder a ramp — turning a tidy set of shades into
  /// one where stop 4 is lighter than stop 3.
  @Test("The curve never goes backwards", arguments: [-1.0, -0.3, 0.3, 1.0])
  func monotonic(strength: Double) {
    let gamma = LightnessCurve(strength: strength).gamma
    var previous = -1.0
    for step in 0 ... 200 {
      let value = LightnessCurve.curve(Double(step) / 200, gamma: gamma)
      #expect(value >= previous, "curve dipped at \(Double(step) / 200)")
      previous = value
    }
  }

  @Test("Positive strength pushes away from mid-gray, negative pulls toward it")
  func directionOfTheBend() {
    let punchy = LightnessCurve(strength: 0.6).gamma
    let flat = LightnessCurve(strength: -0.6).gamma

    #expect(LightnessCurve.curve(0.25, gamma: punchy) < 0.25)
    #expect(LightnessCurve.curve(0.75, gamma: punchy) > 0.75)
    #expect(LightnessCurve.curve(0.25, gamma: flat) > 0.25)
    #expect(LightnessCurve.curve(0.75, gamma: flat) < 0.75)
  }

  /// Exact, not approximate — the reason ``LightnessCurve/gamma`` is exponential in
  /// the strength rather than linear. A linear mapping would leave `+0.5` and `-0.5`
  /// failing to cancel.
  @Test("Opposite strengths cancel exactly", arguments: [0.2, 0.5, 1.0])
  func inverseIsExact(strength: Double) {
    let curve = LightnessCurve(strength: strength)
    for step in 0 ... 20 {
      let x = Double(step) / 20
      let there = LightnessCurve.curve(x, gamma: curve.gamma)
      let back = LightnessCurve.curve(there, gamma: curve.inverted.gamma)
      #expect(abs(back - x) < 1e-12, "\(x) round-tripped to \(back)")
    }
  }

  @Test("Zero strength is a no-op on a whole set")
  func identityLeavesASetAlone() {
    let colors = [
      ColorValue(space: .oklch, 0.3, 0.1, 40),
      ColorValue(space: .oklch, 0.6, 0.1, 40),
    ]
    #expect(LightnessCurve.identity.applied(to: colors) == colors)
  }

  /// What the curve is actually for: applied to a set it keeps the order and the
  /// middle while spreading the ends, which a lightness offset cannot do — an offset
  /// slides the whole ramp instead.
  @Test("On a set, the ends spread and the order holds")
  func spreadsASet() {
    let ramp = (0 ... 10).map {
      ColorValue(space: .oklch, Double($0) / 10, 0.08, 200)
    }
    let punched = LightnessCurve(strength: 0.7).applied(to: ramp)

    let before = ramp.map(\.oklchComponents.lightness)
    let after = punched.map(\.oklchComponents.lightness)

    #expect(after == after.sorted(), "the curve reordered the ramp")
    #expect(abs(after[5] - before[5]) < 1e-12, "the midpoint moved")
    #expect(after[1] < before[1], "the dark end did not darken")
    #expect(after[9] > before[9], "the light end did not lighten")
    // Chroma and hue are none of this transform's business.
    #expect(abs(punched[3].oklchComponents.chroma - 0.08) < 1e-12)
    #expect(abs(punched[3].oklchComponents.hue - 200) < 1e-12)
  }
}

@Suite("Harmony")
struct HarmonyTests {
  static let base = ColorValue(space: .oklch, 0.65, 0.18, 250)

  /// The angles, checked as angles rather than as remembered output.
  @Test(
    "Each harmony turns the hue by its defining angles",
    arguments: [
      (Harmony.complementary, [0.0, 180.0]),
      (.splitComplementary, [0.0, 150.0, 210.0]),
      (.triad, [0.0, 120.0, 240.0]),
      (.tetrad, [0.0, 90.0, 180.0, 270.0]),
      (.analogous, [-30.0, 0.0, 30.0]),
    ],
  )
  func hueOffsetsAreTheClassicAngles(harmony: Harmony, expected: [Double]) {
    #expect(harmony.hueOffsets() == expected)

    let members = Self.base.harmony(harmony)
    #expect(members.count == expected.count)
    for (member, offset) in zip(members, expected) {
      let wanted = Conversion.constrainAngle(250 + offset)
      #expect(
        abs(member.oklchComponents.hue - wanted) < 1e-9,
        "expected hue \(wanted), got \(member.oklchComponents.hue)",
      )
    }
  }

  /// Members differ in exactly one dimension. That is what makes them read as a
  /// family rather than as four unrelated colors.
  @Test("Lightness and chroma are untouched", arguments: Harmony.allCases.filter { $0 != .monochromatic })
  func onlyHueMoves(harmony: Harmony) {
    for member in Self.base.harmony(harmony) {
      #expect(abs(member.oklchComponents.lightness - 0.65) < 1e-12)
      #expect(abs(member.oklchComponents.chroma - 0.18) < 1e-12)
    }
  }

  /// The decision this suite exists to pin: harmonies are **not** pulled into the
  /// sRGB gamut. Rotating a vivid hue routinely leaves it — the gamut is nothing like
  /// a cylinder — and mapping the result would hand back a color that is not the
  /// complement of anything. The base here is inside sRGB and its complement is
  /// outside, confirmed against colorjs.io.
  @Test("An out-of-gamut member keeps its chroma rather than being mapped in")
  func harmoniesAreNotGamutMapped() {
    let vivid = ColorValue(space: .oklch, 0.65, 0.2, 30)
    #expect(vivid.inGamut(of: .srgb), "the base should be inside sRGB")

    let members = vivid.harmony(.complementary)
    let complement = members[1]

    #expect(!complement.inGamut(of: .srgb), "the complement should be outside sRGB")
    #expect(
      abs(complement.oklchComponents.chroma - 0.2) < 1e-12,
      "the complement was quietly pulled into gamut",
    )
    #expect(abs(complement.oklchComponents.hue - 210) < 1e-9)
  }

  /// A gray has no hue, so it has no relatives. The arithmetic says so by returning
  /// the same color repeatedly — documented behavior, not a case to special-case away.
  @Test("Hue harmonies of a gray are all the same gray")
  func achromaticHarmoniesCollapse() {
    let gray = ColorValue.srgb8(0x80, 0x80, 0x80)
    #expect(gray.isAchromatic)

    for harmony in Harmony.allCases where harmony != .monochromatic {
      let members = gray.harmony(harmony)
      for member in members {
        #expect(
          member.deltaEOK(to: members[0]) < 1e-9,
          "\(harmony.rawValue) produced a distinct color from a gray",
        )
      }
    }
  }

  /// Monochromatic is the odd one out — one hue, many lightnesses — so it delegates
  /// to ``ShadeRamp`` rather than reimplementing a lightness family badly.
  @Test("Monochromatic is a ramp, and inherits the ramp's guarantees")
  func monochromaticDelegatesToTheRamp() {
    let members = Self.base.harmony(.monochromatic)
    #expect(members.count == 5)
    #expect(Harmony.monochromatic.count() == 5)

    // Every stop displayable, and lightness descending — the ramp's contract.
    for member in members {
      #expect(member.inGamut(of: .srgb))
    }
    let lightnesses = members.map(\.oklchComponents.lightness)
    #expect(lightnesses == lightnesses.sorted(by: >))
  }

  /// A panel has to mark the user's own color in the row, and comparing floats to
  /// find it would be fragile.
  @Test("The base index points at the original", arguments: Harmony.allCases)
  func baseIndexFindsTheOriginal(harmony: Harmony) {
    let members = Self.base.harmony(harmony)
    let index = harmony.baseIndex()

    #expect(index < members.count)
    #expect(
      members[index].deltaEOK(to: Self.base) < 1e-9,
      "\(harmony.rawValue) index \(index) is not the base color",
    )
  }

  @Test("Analogous spread is configurable")
  func analogousSpreadIsConfigurable() {
    var options = HarmonyOptions.default
    options.analogousSpread = 15

    let members = Self.base.harmony(.analogous, options: options)
    #expect(abs(members[0].oklchComponents.hue - 235) < 1e-9)
    #expect(abs(members[2].oklchComponents.hue - 265) < 1e-9)
  }

  /// The disagreement M22's web-friendly mode exists to produce: the same vivid base
  /// as ``harmoniesAreNotGamutMapped``, with only `options.gamut` changed. The default
  /// still escapes sRGB — pinned above, and re-asserted here so the two tests cannot
  /// silently agree by testing different colors — while `.srgb` pulls the complement
  /// back in rather than dropping it or reporting a wrong hue.
  @Test("HarmonyOptions.gamut pulls an escaping member back in, on request")
  func gamutOptionPullsMemberIn() {
    let vivid = ColorValue(space: .oklch, 0.65, 0.2, 30)
    #expect(!vivid.harmony(.complementary)[1].inGamut(of: .srgb), "default should still escape")

    var options = HarmonyOptions.default
    options.gamut = .srgb
    let pulled = vivid.harmony(.complementary, options: options)[1]

    #expect(pulled.inGamut(of: .srgb))
    // Pulled by chroma alone — the hue that defines "complement" is untouched.
    #expect(abs(pulled.oklchComponents.hue - 210) < 1e-9)
  }
}

@Suite("Shade ramp")
struct ShadeRampTests {
  static let base = ColorValue(space: .oklch, 0.55, 0.18, 260)

  /// **The premise the whole type is built on**, asserted rather than assumed. Hold
  /// chroma constant across the lightness range and the ends fall out of sRGB — so a
  /// ramp that skipped the taper and the boundary clamp would be silently clipped on
  /// the way to the screen, and clipping shifts hue.
  ///
  /// If this ever stops failing, the ramp's design has lost its reason to exist.
  @Test("A naive constant-chroma ramp really does leave the gamut")
  func theNaiveRampIsBroken() {
    var naive = ShadeRamp.default
    naive.chromaTaper = 0 // no taper
    naive.gamut = .oklch // unbounded: disables the clamp

    let stops = naive.generated(from: Self.base)
    let escaped = stops.filter { !$0.inGamut(of: .srgb) }

    #expect(!escaped.isEmpty, "the naive ramp stayed in gamut — the premise has changed")
    #expect(
      stops.allSatisfy { abs($0.oklchComponents.chroma - 0.18) < 1e-12 },
      "chroma was not actually held constant, so this proves nothing",
    )
  }

  /// The correctness rule. Every stop is displayable, by construction rather than by
  /// a mapping applied afterwards.
  @Test(
    "Every stop of a real ramp is in gamut",
    arguments: [
      ColorValue(space: .oklch, 0.55, 0.18, 260),
      ColorValue(space: .oklch, 0.65, 0.20, 30),
      ColorValue(space: .oklch, 0.86, 0.29, 142), // near sRGB green's corner
      ColorValue.srgb8(0x3B, 0x82, 0xF6),
      ColorValue.srgb8(0x80, 0x80, 0x80), // no chroma to taper
    ],
  )
  func everyStopIsDisplayable(base: ColorValue) {
    for stop in ShadeRamp.default.generated(from: base) {
      #expect(
        stop.inGamut(of: .srgb),
        "stop \(stop.oklchComponents) left sRGB",
      )
    }
  }

  /// The chosen color comes back out of its own ramp untouched — not nudged by a
  /// search step, which is why the clamp is applied only where it is needed.
  @Test("The middle stop is the base, exactly")
  func theBaseIsTheMiddleStop() {
    let stops = ShadeRamp.default.generated(from: Self.base)
    let middle = stops[stops.count / 2]

    #expect(middle.oklchComponents == Self.base.oklchComponents)
  }

  @Test("Lightness descends from the light end")
  func lightnessIsOrdered() throws {
    let lightnesses = ShadeRamp.default
      .generated(from: Self.base)
      .map(\.oklchComponents.lightness)

    #expect(lightnesses == lightnesses.sorted(by: >))
    #expect(try #require(lightnesses.first) > 0.9)
    #expect(try #require(lightnesses.last) < 0.25)
  }

  /// The aesthetic rule: ends give up chroma, so light stops read as tints rather
  /// than as the same ink at a higher lightness.
  @Test("Chroma tapers toward both ends")
  func chromaTapers() throws {
    let stops = ShadeRamp.default.generated(from: Self.base)
    let chromas = stops.map(\.oklchComponents.chroma)
    let middle = stops.count / 2

    #expect(try #require(chromas.first) < chromas[middle])
    #expect(try #require(chromas.last) < chromas[middle])
    #expect(chromas[middle] == chromas.max()!)
  }

  @Test("Hue survives the whole ramp")
  func hueIsPreserved() {
    for stop in ShadeRamp.default.generated(from: Self.base) {
      #expect(abs(stop.oklchComponents.hue - 260) < 1e-9)
    }
  }

  /// An even count has no middle, so the chosen color would have to sit off-center or
  /// drop out of its own ramp. Rounding up is the least surprising fix.
  @Test(
    "Stop counts are rounded up to something with a middle",
    arguments: [(3, 3), (10, 11), (11, 11), (12, 13), (0, 3), (-5, 3), (2, 3)],
  )
  func stopCountsAreOdd(requested: Int, expected: Int) {
    #expect(ShadeRamp.stopCount(for: requested) == expected)

    var ramp = ShadeRamp.default
    ramp.stops = requested
    #expect(ramp.generated(from: Self.base).count == expected)
  }

  /// A base outside the target gamut is pulled in like every other stop. The ramp's
  /// promise is that all of it is usable together, and honoring that for ten stops
  /// but not the eleventh would hand back a set that cannot be used as one.
  @Test("An out-of-gamut base is brought in, and the ramp says so")
  func anOutOfGamutBaseIsPulledIn() {
    let wide = ColorValue(space: .oklch, 0.7, 0.3, 140)
    #expect(!wide.inGamut(of: .srgb))

    let stops = ShadeRamp.default.generated(from: wide)
    let middle = stops[stops.count / 2]

    #expect(middle.inGamut(of: .srgb))
    #expect(middle.oklchComponents.chroma < 0.3, "the base was left out of gamut")
    // Lightness and hue are still exactly the base's; only chroma gave way.
    #expect(abs(middle.oklchComponents.lightness - 0.7) < 1e-12)
    #expect(abs(middle.oklchComponents.hue - 140) < 1e-9)
  }

  /// A near-white base has no lighter tints. The light side compresses rather than
  /// running past the base, so the chosen color is never somewhere other than the
  /// middle.
  @Test("A base outside the default range compresses that side instead of moving")
  func extremeBaseKeepsItsPlace() throws {
    let nearWhite = ColorValue(space: .oklch, 0.99, 0.02, 250)
    let stops = ShadeRamp.default.generated(from: nearWhite)
    let lightnesses = stops.map(\.oklchComponents.lightness)

    #expect(lightnesses == lightnesses.sorted(by: >), "the ramp inverted")
    #expect(abs(lightnesses[stops.count / 2] - 0.99) < 1e-12)
    #expect(try #require(lightnesses.first) <= 0.99 + 1e-12, "the ramp invented lightness above the base")
  }

  /// A wider gamut leaves more chroma available, so the same base ramps richer.
  /// Asserted as a per-stop comparison, never as a claim about which space is
  /// "wider" — that reasoning is what the Rec.2020/P3 finding exists to warn against.
  @Test("A P3 ramp is never less colorful than the sRGB one")
  func widerGamutKeepsMoreChroma() {
    var p3 = ShadeRamp.default
    p3.gamut = .displayP3

    let vivid = ColorValue(space: .oklch, 0.65, 0.28, 30)
    let narrow = ShadeRamp.default.generated(from: vivid).map(\.oklchComponents.chroma)
    let wide = p3.generated(from: vivid).map(\.oklchComponents.chroma)

    for (index, (a, b)) in zip(narrow, wide).enumerated() {
      #expect(b >= a - 1e-9, "stop \(index): P3 gave \(b) where sRGB gave \(a)")
    }
    #expect(zip(narrow, wide).contains { $1 > $0 + 1e-6 }, "P3 changed nothing at all")
  }

  @Test("Alpha carries into every stop")
  func alphaIsCarried() {
    let translucent = ColorValue(space: .oklch, 0.55, 0.15, 260, alpha: 0.35)
    for stop in ShadeRamp.default.generated(from: translucent) {
      #expect(stop.alpha == 0.35)
    }
  }
}
