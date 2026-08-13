//
//  GamutBoundaryTests.swift
//  ColorKitTests
//

@testable import ColorKit
import Foundation
import Testing

/// Proof that the chroma boundary is where the picker says it is.
///
/// There is no oracle to compare against — colorjs.io answers "does this fit?", never
/// "how far could it go?". That turns out to be an advantage: the boundary is checked
/// *definitionally* instead, by asking the gamut predicate either side of the answer.
/// A fixture could only ever encode one library's search tolerance; this asserts the
/// property the value is supposed to have, so it stays true if the search is rewritten.
@Suite("Gamut boundary")
struct GamutBoundaryTests {
  /// Spaces a picker can plausibly draw an edge for.
  static let boundedSpaces: [ColorSpace] = [.srgb, .displayP3, .rec2020]

  /// Far wider than the search's own 1e-4 convergence, so a genuine off-by-a-search
  /// -step passes and a wrong boundary does not.
  static let probe = 1e-3

  // MARK: - The defining property

  /// The returned chroma fits and the next one along does not. That is the whole
  /// contract, checked on a grid rather than at a handful of chosen points, because
  /// the failure mode being guarded against — bisection converging on the wrong side
  /// of the surface — is hue-dependent and would hide at any single hue.
  @Test(
    "The answer is inside the gamut and one step further is outside",
    arguments: boundedSpaces,
  )
  func boundaryIsExactlyTheBoundary(space: ColorSpace) {
    for lightnessStep in 1 ... 9 {
      let lightness = Double(lightnessStep) / 10
      for hueStep in 0 ..< 12 {
        let hue = Double(hueStep) * 30
        let chroma = GamutBoundary.maxChroma(lightness: lightness, hue: hue, in: space)

        #expect(
          ColorValue(space: .oklch, lightness, chroma, hue).inGamut(of: space),
          "L \(lightness) h \(hue) in \(space.rawValue): returned chroma \(chroma) is outside",
        )
        #expect(
          !ColorValue(space: .oklch, lightness, chroma + Self.probe, hue)
            .inGamut(of: space),
          "L \(lightness) h \(hue) in \(space.rawValue): chroma past \(chroma) still fits",
        )
      }
    }
  }

  // MARK: - External anchors

  /// A primary is a *vertex* of the RGB cube, so along the ray at its own lightness
  /// and hue it is where the gamut ends. That makes red and green independent checks
  /// on the search — their OKLCH chroma comes from colorjs.io, and nothing in the
  /// Swift knows they are special.
  ///
  /// Blue is deliberately absent; see ``blueIsNotOnItsOwnBoundary``.
  @Test(
    "sRGB primaries sit exactly on their own boundary",
    arguments: [
      (0.627955, 29.233880, 0.257683), // #ff0000
      (0.866440, 142.495345, 0.294827), // #00ff00
    ],
  )
  func primariesAreOnTheBoundary(lightness: Double, hue: Double, chroma: Double) {
    let found = GamutBoundary.maxChroma(lightness: lightness, hue: hue, in: .srgb)
    #expect(
      abs(found - chroma) < Self.probe,
      "expected the boundary at L \(lightness) h \(hue) to be \(chroma), found \(found)",
    )
  }

  /// The counterexample, pinned so nobody "fixes" it.
  ///
  /// Blue is the one primary that is *not* the end of its own ray. Walking chroma
  /// outward at blue's lightness and hue, the sRGB red channel goes negative at
  /// `0.2656`, bottoms out at `-0.009` around `0.29` — three orders of magnitude
  /// past float noise, so this is the shape of the gamut and not a rounding artifact
  /// — and climbs back to zero only as the ray grazes the blue vertex at `0.3132`.
  /// The in-gamut set along that ray is two disconnected pieces, which is exactly
  /// the OKLab blue-hue curvature everyone runs into eventually.
  ///
  /// Reporting the first exit is the wanted behavior: the band between the pieces is
  /// genuinely outside sRGB, and a picker drawing the boundary at the far island
  /// would present a wide stripe of unreachable colors as reachable. The value comes
  /// from bisecting colorjs.io's own `inGamut`, so this is a cross-check and not a
  /// transcription of what the Swift already returns.
  @Test("Blue is not the end of its own ray")
  func blueIsNotOnItsOwnBoundary() {
    let lightness = 0.452014
    let hue = 264.052023
    let blueChroma = 0.313214

    let boundary = GamutBoundary.maxChroma(lightness: lightness, hue: hue, in: .srgb)

    #expect(abs(boundary - 0.265592) < Self.probe, "boundary moved: \(boundary)")
    #expect(boundary < blueChroma - 0.04, "the ray no longer exits early — check the search")

    // The middle of the gap really is outside, which is what makes stopping early
    // correct rather than merely conservative.
    #expect(!ColorValue(space: .oklch, lightness, 0.29, hue).inGamut(of: .srgb))
  }

  /// Gamut *mapping* may legitimately land outside this boundary, and that is not a
  /// contradiction to be reconciled — it is two different questions.
  ///
  /// ``ColorValue/gamutMapped(to:)`` takes a clipped result whenever clipping costs
  /// less than a JND, and at a cube corner it costs almost nothing: §13 maps blue's
  /// coordinates to `#0000ff` at full chroma `0.3132`, well past the `0.2656`
  /// boundary. The invariant that must hold is with the *badge*, asserted below —
  /// deriving the drawn curve from the mapper instead would put the cursor inside
  /// the line for colors the badge calls out of gamut.
  @Test("Gamut mapping is allowed past the boundary, and is")
  func mappingIsADifferentQuestion() {
    let blue = ColorValue(space: .oklch, 0.452014, 0.313214, 264.052023)
    let mapped = blue.gamutMapped(to: .srgb).converted(to: .oklch)

    #expect(mapped.components.y > 0.30, "§13 no longer keeps blue's chroma: \(mapped.components.y)")
    #expect(mapped.components.y > GamutBoundary.maxChroma(
      lightness: 0.452014, hue: 264.052023, in: .srgb,
    ))
  }

  /// The agreement that has to hold: no color the picker draws as inside the curve
  /// may wear an "Outside sRGB" badge. If that failed, the cursor and the badge
  /// would contradict each other on the same screen.
  ///
  /// One-directional on purpose. The badge is deliberately the *more forgiving* of
  /// the two — see ``channelToleranceIsNotAChromaTolerance`` — so the converse does
  /// not hold near black, and asserting it would be asserting a bug.
  @Test("Nothing inside the curve is badged out of gamut")
  func insideTheCurveIsNeverBadged() {
    for hueStep in 0 ..< 24 {
      let hue = Double(hueStep) * 15
      for lightnessStep in 1 ... 9 {
        let lightness = Double(lightnessStep) / 10
        let chroma = GamutBoundary.maxChroma(lightness: lightness, hue: hue, in: .srgb)

        #expect(
          !ColorValue(space: .oklch, lightness, chroma, hue).exceedsSRGB,
          "L \(lightness) h \(hue): the boundary itself is badged out of gamut",
        )
      }
    }
  }

  /// The extremes ``insideTheCurveIsNeverBadged`` deliberately skips (it samples
  /// `0.1...0.9`) — and the exact case a real bug shipped in: at `L = 1`,
  /// ``GamutBoundary/maxChroma(lightness:hue:in:tolerance:resolution:)`` returns `0`
  /// through its own `guard fits(0) else { return 0 }`, never through bisection, so
  /// this is a different code path from the rest of the curve, not just its
  /// endpoint. `TransformPanel`'s Adjust section reached exactly this: dragging
  /// Lightness past white leaves ``OKLCHAdjustment/applied(to:)``'s own clamp at
  /// `lightness == 1` with the *original* chroma still attached, and
  /// ``ColorValue/pulledInto(_:)`` pulls that chroma to the boundary here — which
  /// must not still read as outside sRGB, or the badge lies about a swatch that is
  /// now pure white.
  @Test("Black and white's own boundary chroma is not badged out of gamut either")
  func theExtremesAreNeverBadged() {
    for hueStep in 0 ..< 24 {
      let hue = Double(hueStep) * 15
      for lightness in [0.0, 1.0] {
        let chroma = GamutBoundary.maxChroma(lightness: lightness, hue: hue, in: .srgb)
        #expect(chroma == 0, "L \(lightness) h \(hue): expected the boundary to be the neutral axis itself")
        #expect(
          !ColorValue(space: .oklch, lightness, chroma, hue).exceedsSRGB,
          "L \(lightness) h \(hue): the boundary itself is badged out of gamut",
        )
      }
    }
  }

  /// The panel-level reproduction, pinned end to end rather than only at the
  /// boundary: adjust past white, pull the result back to the sRGB edge the way
  /// `TransformPanel.adjusted(_:)` does under web-friendly mode, and require the
  /// forgiving badge predicate — not the strict one ``ColorValue/pulledInto(_:)``
  /// itself searches with — to agree the result fits. Measured false before this fix:
  /// `pulled.inGamut(of: .srgb)` is `false` at the strict tolerance even though
  /// `pulled` is exactly the boundary chroma, which is why the panel must read
  /// ``ColorValue/exceedsSRGB`` and not call `inGamut(of:)` directly.
  @Test("Pulling an over-lightened color into sRGB clears the badge")
  func pullingPastWhiteClearsTheBadge() {
    let blue = ColorValue.srgb8(0x3B, 0x82, 0xF6)
    let overLightened = OKLCHAdjustment(lightnessDelta: 0.5).applied(to: blue)
    #expect(overLightened.oklchComponents.lightness == 1, "expected the clamp to have already capped this")

    let pulled = overLightened.pulledInto(.srgb)
    #expect(!pulled.inGamut(of: .srgb), "the strict predicate is allowed to be this fussy at the boundary")
    #expect(!pulled.exceedsSRGB, "the badge must not be, or the swatch reads out of gamut while showing white")
  }

  /// Why the boundary uses a strict gamut test where the badge uses a forgiving one.
  ///
  /// ``ColorValue/gamutNoiseTolerance`` is 7.5e-5 *of a channel*. Chroma is a
  /// different unit, and OKLab's cube root makes the exchange rate between them
  /// enormous near black: the same slack buys **more than 0.04 of chroma at
  /// `L = 0`**, some 500× the search's own resolution. Handing the badge's constant
  /// to the boundary looks like consistency and is a unit error — the curve would
  /// bulge to a visible width at pure black, which has no chroma at all.
  @Test("A channel tolerance is not a chroma tolerance")
  func channelToleranceIsNotAChromaTolerance() {
    let strict = GamutBoundary.maxChroma(lightness: 0, hue: 0, in: .srgb)
    let forgiving = GamutBoundary.maxChroma(
      lightness: 0, hue: 0, in: .srgb,
      tolerance: ColorValue.gamutNoiseTolerance,
    )

    #expect(strict < Self.probe)
    #expect(forgiving > 0.04, "the amplification near black has changed: \(forgiving)")
  }

  /// sRGB really is contained in Display P3 — verified by sampling 20,000 random
  /// sRGB colors against colorjs.io, none of which left P3, while 9,626 of 20,000
  /// P3 colors left sRGB. Asserted here because the containment is *not* something
  /// to reason about from space "widths": Rec.2020 does not contain Display P3, and
  /// a picker that assumed nesting would draw its two boundary curves crossing.
  @Test("Display P3 has at least sRGB's chroma everywhere")
  func p3ContainsSRGB() {
    for lightnessStep in 1 ... 9 {
      let lightness = Double(lightnessStep) / 10
      for hueStep in 0 ..< 12 {
        let hue = Double(hueStep) * 30
        let srgb = GamutBoundary.maxChroma(lightness: lightness, hue: hue, in: .srgb)
        let p3 = GamutBoundary.maxChroma(lightness: lightness, hue: hue, in: .displayP3)
        #expect(
          p3 >= srgb - Self.probe,
          "L \(lightness) h \(hue): P3 boundary \(p3) is inside sRGB's \(srgb)",
        )
      }
    }
  }

  // MARK: - Ends of the range

  /// Black and white are the only colors at their lightness, so there is no chroma
  /// to be had. The picker's plane collapses to a point at both ends, which is what
  /// gives the boundary curve its characteristic pinch.
  @Test("Chroma vanishes at both ends of lightness", arguments: [0.0, 1.0])
  func noChromaAtTheExtremes(lightness: Double) {
    for hueStep in 0 ..< 12 {
      let hue = Double(hueStep) * 30
      let chroma = GamutBoundary.maxChroma(lightness: lightness, hue: hue, in: .srgb)
      #expect(chroma < Self.probe, "L \(lightness) h \(hue) claimed chroma \(chroma)")
    }
  }

  /// Past the ends even gray is out of gamut, so the honest answer is zero rather
  /// than a search that never brackets anything.
  @Test("Lightness outside 0…1 has no gamut at all", arguments: [-0.5, 1.5, 2.0])
  func nothingBeyondTheLightnessRange(lightness: Double) {
    #expect(GamutBoundary.maxChroma(lightness: lightness, hue: 120, in: .srgb) == 0)
  }

  /// Unbounded spaces answer `.infinity` — literally true, and the reason callers can
  /// write `min(chroma, maxChroma(…))` without a special case.
  @Test("Unbounded spaces have no boundary", arguments: [ColorSpace.oklch, .lab, .xyzD65])
  func unboundedSpacesAreInfinite(space: ColorSpace) {
    #expect(GamutBoundary.maxChroma(lightness: 0.5, hue: 200, in: space) == .infinity)
  }

  // MARK: - The sampled curve

  /// The curve is what the picker both draws *and* clamps pixels against, so it has
  /// to be the same numbers as the point query — a curve computed even slightly
  /// differently would stroke a line the pixels underneath do not obey.
  @Test("The sampled curve agrees with point queries")
  func curveMatchesPointQueries() {
    let samples = 17
    let hue = 264.0
    let curve = GamutBoundary.maxChromaCurve(hue: hue, in: .srgb, samples: samples)

    #expect(curve.count == samples)
    for (index, chroma) in curve.enumerated() {
      let lightness = Double(index) / Double(samples - 1)
      #expect(chroma == GamutBoundary.maxChroma(lightness: lightness, hue: hue, in: .srgb))
    }
  }

  /// The curve spans lightness inclusively, so it pinches to nothing at both ends.
  @Test("The curve starts and ends at zero chroma")
  func curvePinchesAtBothEnds() throws {
    let curve = GamutBoundary.maxChromaCurve(hue: 30, in: .srgb, samples: 64)
    #expect(try #require(curve.first) < Self.probe)
    #expect(try #require(curve.last) < Self.probe)
    // And bulges in between, or the picker would have nothing to draw.
    #expect(curve.max() ?? 0 > 0.2)
  }

  // MARK: - pulledInto

  /// The M22 extraction from ``ShadeRamp``'s own clamp: a color that already fits
  /// comes back **unchanged**, not merely close. Not an optimization to skip — a
  /// caller relying on this (``ShadeRamp`` chief among them) needs its own base color
  /// to survive the round trip bit-for-bit, or the chosen color would not appear in
  /// its own ramp.
  @Test("A color already inside the gamut is returned untouched")
  func pulledIntoLeavesAFittingColorAlone() {
    let inGamut = ColorValue(space: .oklch, 0.6, 0.05, 30)
    #expect(inGamut.inGamut(of: .srgb))
    #expect(inGamut.pulledInto(.srgb) == inGamut)
  }

  /// A color outside the gamut comes back on the boundary — the same chroma
  /// ``maxChroma`` reports at that lightness and hue — with its hue and lightness
  /// untouched. That last part is the whole difference between this and gamut
  /// *mapping*, which is free to move lightness too.
  @Test("An out-of-gamut color is pulled to the boundary chroma, hue and lightness held")
  func pulledIntoReachesTheBoundary() {
    let wide = ColorValue(space: .oklch, 0.65, 0.3, 30)
    #expect(!wide.inGamut(of: .srgb))

    let pulled = wide.pulledInto(.srgb)
    let boundary = GamutBoundary.maxChroma(lightness: 0.65, hue: 30, in: .srgb)

    #expect(pulled.inGamut(of: .srgb))
    #expect(abs(pulled.oklchComponents.chroma - boundary) < 1e-9)
    #expect(abs(pulled.oklchComponents.lightness - 0.65) < 1e-12)
    #expect(abs(pulled.oklchComponents.hue - 30) < 1e-9)
  }

  /// An sRGB color that has been through OKLCH and back must survive `pulledInto`
  /// **unchanged**, and the guard is why it does not for free.
  ///
  /// `pulledInto` asks "does this already fit?" and that is the *badge's* question,
  /// not the curve's — so it is asked with ``ColorValue/gamutNoiseTolerance``, the
  /// same forgiving predicate ``ColorValue/exceedsSRGB`` uses, while the clamp below
  /// it keeps calling ``GamutBoundary/maxChroma`` strictly. The two are not
  /// interchangeable and the split is deliberate: this test would also pass if the
  /// *search* were loosened, which is exactly what
  /// ``channelToleranceIsNotAChromaTolerance`` forbids, so read them together.
  ///
  /// Asked strictly, the guard rejects on float noise and the cost is enormous.
  /// `#00003c` round-trips to a red channel of **−2.24e-16**; `inGamut(epsilon: 0)`
  /// tests `< 0`, fails, and the chroma is then pulled all the way to the strict
  /// boundary — `0.847×` where it started. That is the competing hypothesis here and
  /// it sits **15% away**, four orders of magnitude past any formatting tolerance, so
  /// there is no reading of this assertion where the two answers are near each other.
  ///
  /// Measured across 5,814 sampled sRGB colors: 883 of them (15.2%) were desaturated
  /// this way, worst case 15.3%. It reached far past this one test — ``ShadeRamp``,
  /// ``Harmony``, ``ContrastSolver``, the picker and `ColorStore`'s `adopt`/`respell`
  /// all route through `pulledInto` under web-friendly mode.
  @Test(
    "An sRGB color survives a round trip through OKLCH, whatever the last bit says",
    arguments: [(0x00, 0x00, 0x3C), (0x00, 0x00, 0xFF), (0x1E, 0x3A, 0x8A)],
  )
  func pulledIntoSurvivesRoundTripNoise(red: Int, green: Int, blue: Int) {
    let color = ColorValue.srgb8(UInt8(red), UInt8(green), UInt8(blue))
    let chroma = color.oklchComponents.chroma

    // The round trip an adjustment performs — `derivedOKLCH` re-expresses the color
    // in OKLCH, which is where the sub-ULP channel error is introduced.
    let roundTripped = OKLCHAdjustment.identity.applied(to: color)
    let pulled = roundTripped.pulledInto(.srgb)

    #expect(
      abs(pulled.oklchComponents.chroma - chroma) < 1e-9,
      "a strict guard would answer \(GamutBoundary.maxChroma(lightness: color.oklchComponents.lightness, hue: color.oklchComponents.hue, in: .srgb)) here, not \(chroma)",
    )
  }

  /// The other half of the guard: loosening it must not stop a genuinely wide color
  /// from being pulled in. `gamutNoiseTolerance` is 7.5e-5 of a channel, so a real
  /// Display P3 primary misses sRGB by orders of magnitude more than the slack.
  @Test("A genuinely out-of-gamut color is still pulled in by the forgiving guard")
  func forgivingGuardStillPullsRealWideColors() {
    let wide = ColorValue(space: .displayP3, 0, 1, 0)
    #expect(!wide.inGamut(of: .srgb, epsilon: ColorValue.gamutNoiseTolerance))

    let pulled = wide.pulledInto(.srgb)
    #expect(pulled.oklchComponents.chroma < wide.oklchComponents.chroma, "it was not pulled at all")
    #expect(!pulled.exceedsSRGB)
  }

  /// An unbounded space has no boundary to pull toward — ``maxChroma`` answers
  /// `.infinity` there — so `pulledInto` must take the early "already fits" exit
  /// rather than setting the chroma to it.
  @Test("An unbounded gamut leaves every color alone")
  func pulledIntoUnboundedGamutIsANoOp() {
    let wide = ColorValue(space: .oklch, 0.65, 0.4, 30)
    let pulled = wide.pulledInto(.oklch)
    #expect(pulled == wide)
  }
}
