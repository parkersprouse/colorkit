//
//  MissingComponentTests.swift
//  ColorKitTests
//
//  CSS Color 4 §13.2 — carrying missing components across a conversion.
//
//  There is no oracle here, and that is measured rather than assumed: colorjs.io
//  *resolves* `none` on conversion (`hsl(none 50% 50%).to("oklch")` comes back with a
//  real hue), so it cannot answer the question this file asks. The spec's own worked
//  examples are therefore the fixtures — each `@Test` below names the one it encodes —
//  and everything else asserts a property of the role table.
//

@testable import ColorKit
import Foundation
import Testing

@Suite("Missing components")
struct MissingComponentTests {
  // MARK: Internal

  // MARK: - The spec's worked examples

  @Test("lab(50% none none) carries both into LCH as a set")
  func labSetCarriesIntoLCH() {
    // Lightness is individually analogous; a and b have no analog in LCH, so they
    // form a set with C and h. Both are missing, so the whole set travels — the
    // spec's stated result is lch(50% none none), not lch(50% 0 0).
    let lab = ColorValue(space: .lab, 50, 0, 0, missing: [.second, .third])
    let lch = lab.convertedForInterpolation(to: .lch)

    #expect(lch.missing == [.second, .third])
    #expect(!lch.missing.contains(.first))
  }

  @Test("A half-missing set carries nothing")
  func partialSetDoesNotCarry() {
    // The discriminating half of the rule above. A set travels whole or not at all,
    // so one missing opponent component leaves LCH with neither flag — and an
    // implementation that carried per-component instead would mark chroma here.
    let lab = ColorValue(space: .lab, 50, 20, 0, missing: [.third])
    #expect(lab.convertedForInterpolation(to: .lch).missing == [])
  }

  @Test("rgb(none none none / 50%) carries into OKLab, sharing no role")
  func rgbSetCarriesIntoOKLab() {
    // sRGB and OKLab have no individually analogous components at all, so all three
    // components are the set. This is the case an implementation with only the
    // individual rule loses completely, and it still passes every same-family test.
    let rgb = ColorValue(space: .srgb, 0, 0, 0, alpha: 0.5, missing: [.first, .second, .third])
    let oklab = rgb.convertedForInterpolation(to: .oklab)

    #expect(oklab.missing == [.first, .second, .third])
    #expect(oklab.alpha == 0.5)
  }

  @Test("A missing hue carries into OKLCH where a missing blue does not")
  func specPairInterpolatedInOKLCH() {
    // The spec's two-color example. lch's hue is analogous to oklch's; display-p3's
    // blue is analogous to nothing in oklch, and its two present siblings keep the
    // set rule from firing.
    let lch = ColorValue(space: .lch, 50, 0.02, 0, missing: .third)
    let p3 = ColorValue(space: .displayP3, 0.7, 0.5, 0, missing: .third)

    #expect(lch.convertedForInterpolation(to: .oklch).missing == .third)
    #expect(p3.convertedForInterpolation(to: .oklch).missing == [])
  }

  @Test("The spec's printed OKLCH values for that pair")
  func specPairConvertsToPrintedValues() {
    // The spec prints what those two colors convert to, at four to five decimals
    // each. Asserted as *roundings* rather than with a tolerance, because that is
    // the actual claim available — a printed `0.0001` says only that the value is
    // in that bucket, and the true chroma here is 5.9e-5. This pins the pipeline
    // reaching the spec's example, not the conversions, which ReferenceVectorTests
    // already validates against colorjs.io to nine decimals.
    let lch = ColorValue(space: .lch, 50, 0.02, 0, missing: .third)
      .convertedForInterpolation(to: .oklch)
    #expect(rounds(lch.components.x, to: 0.56897, decimals: 5))
    #expect(rounds(lch.components.y, to: 0.0001, decimals: 4))

    let p3 = ColorValue(space: .displayP3, 0.7, 0.5, 0, missing: .third)
      .convertedForInterpolation(to: .oklch)
    #expect(rounds(p3.components.x, to: 0.63612, decimals: 5))
    #expect(rounds(p3.components.y, to: 0.1522, decimals: 4))
    #expect(rounds(p3.components.z, to: 78.748, decimals: 3))
  }

  // MARK: - Individual analogy

  @Test("hsl(none 50% 50%) matches OKLCH on all three components")
  func hslMatchesOKLCHComponentwise() {
    // The example this milestone exists for. Hue↔Hue is the obvious pairing;
    // Saturation↔Chroma is the one the spec spells out and nobody guesses, and
    // Lightness↔Lightness is at a different *index* in each space, which is why
    // analogy is by role and never by position.
    let hsl = ColorValue(space: .hsl, 0, 50, 50, missing: .first)
    #expect(hsl.convertedForInterpolation(to: .oklch).missing == .third)

    let missingSaturation = ColorValue(space: .hsl, 120, 0, 50, missing: .second)
    #expect(missingSaturation.convertedForInterpolation(to: .oklch).missing == .second)

    let missingLightness = ColorValue(space: .hsl, 120, 50, 0, missing: .third)
    #expect(missingLightness.convertedForInterpolation(to: .oklch).missing == .first)
  }

  @Test("Opponent b is not Blue")
  func opponentBIsNotBlue() {
    // `b` names two unrelated quantities, and a role table read off the labels
    // would match them. Lab's b has no analog in sRGB, and with a present alongside
    // it the set rule does not fire either, so nothing carries.
    let lab = ColorValue(space: .lab, 50, 20, 0, missing: .third)
    #expect(lab.convertedForInterpolation(to: .srgb).missing == [])
    #expect(ColorSpace.lab.componentRoles.2 != ColorSpace.srgb.componentRoles.2)
  }

  @Test("XYZ is a super-saturated RGB space")
  func xyzSharesRGBRoles() {
    // The spec's note, and it has teeth: x/y/z pair off individually with r/g/b, so
    // a single missing channel carries where the set rule would not have fired.
    let xyz = ColorValue(space: .xyzD65, 0.2, 0.3, 0, missing: .third)
    #expect(xyz.convertedForInterpolation(to: .srgb).missing == .third)
    #expect(ColorSpace.xyzD65.componentRoles == ColorSpace.srgb.componentRoles)
  }

  @Test("HWB's whiteness and blackness have no analog anywhere")
  func hwbHasNoAnalogForWhitenessOrBlackness() {
    for space in ColorSpace.allCases where space != .hwb {
      #expect(space.componentIndex(of: .whiteness) == nil)
      #expect(space.componentIndex(of: .blackness) == nil)
    }

    // They still take part in the set rule, which is a separate mechanism — both
    // missing, so HSL's own leftovers (saturation and lightness) both go missing.
    let hwb = ColorValue(space: .hwb, 120, 0, 0, missing: [.second, .third])
    #expect(hwb.convertedForInterpolation(to: .hsl).missing == [.second, .third])
  }

  // MARK: - Alpha

  @Test("Alpha is analogous to alpha and to nothing else")
  func alphaCarriesAlone() {
    let color = ColorValue(space: .oklch, 0.5, 0.1, 200, alpha: 1, missing: .alpha)
    for target in ColorSpace.allCases where target != .oklch {
      #expect(color.convertedForInterpolation(to: target).missing == .alpha)
    }
  }

  @Test("An unflagged color carries nothing anywhere")
  func nothingIsInventedFromNothing() {
    let color = ColorValue(space: .srgb, 0.2, 0.4, 0.6)
    for target in ColorSpace.allCases {
      #expect(color.convertedForInterpolation(to: target).missing == [])
    }
  }

  @Test("A same-space conversion keeps its own flags")
  func sameSpaceIsIdentity() {
    let color = ColorValue(space: .oklch, 0.5, 0, 0, missing: [.third, .alpha])
    #expect(color.convertedForInterpolation(to: .oklch).missing == [.third, .alpha])
  }

  // MARK: - Ordering against powerless components

  @Test("A carried component keeps its converted value")
  func carryDoesNotZeroWhatItFlags() {
    // `hsl(none 80% 50%)`, exactly as the parser stores it — hue zeroed by `none`,
    // which is a perfectly ordinary red once converted. The spec requires carry-
    // forward to run *before* powerless handling "to prevent conversion of that
    // value to zero", and the difference is downstream: a carried-forward component
    // takes the other color's value when interpolated, where a powerless one is
    // zero. `markingPowerlessComponents()` blanks what it flags; this must not.
    let hsl = ColorValue(space: .hsl, 0, 80, 50, missing: .first)
    let oklch = hsl.convertedForInterpolation(to: .oklch)

    #expect(oklch.missing == .third)
    #expect(oklch.components.z > 1, "the carried hue was zeroed")
    #expect(!oklch.isAchromatic)
  }

  @Test("Carry-forward is not powerless marking")
  func powerlessComponentsAreNotCarriedForward() {
    // A gray has a powerless hue in every polar space, and the serializer says so
    // when asked. Interpolation asks a different question, and folding the two
    // together here would answer it wrongly — `none` in the *source* is the only
    // thing that carries.
    let gray = ColorValue(space: .srgb, 0.5, 0.5, 0.5)
    #expect(gray.isAchromatic)
    #expect(gray.convertedForInterpolation(to: .oklch).missing == [])
    #expect(gray.converted(to: .oklch).markingPowerlessComponents().missing == .third)
  }

  @Test("Plain conversion still drops component flags")
  func plainConversionIsUnchanged() {
    // The boundary this milestone deliberately did not move: `converted(to:)` is a
    // numeric operation, and carry-forward is something interpolation asks for.
    let lab = ColorValue(space: .lab, 50, 0, 0, missing: [.second, .third])
    #expect(lab.converted(to: .lch).missing == [])
  }

  // MARK: - The role table itself

  @Test("Every space names three distinct roles")
  func rolesAreDistinctWithinASpace() {
    // Analogy is decided by equality, so a repeated role inside one space would make
    // `componentIndex(of:)` a lookup with two answers and silently pick the first.
    for space in ColorSpace.allCases {
      let roles = space.orderedComponentRoles
      #expect(Set(roles).count == 3, "\(space.rawValue) repeats a role")
    }
  }

  @Test("hueIndex still answers what it answered when it was a list")
  func hueIndexSurvivesDerivation() {
    // It is derived from the role table now, so this pins the derivation against the
    // values that were hand-written before — a mistyped role would otherwise move
    // the picker's hue axis with nothing to say so. `ColorCoreTests.hueIndices`
    // asserts six of these already; this one is exhaustive over `allCases`, which is
    // what catches a role typed into a space nobody thinks of as having a hue.
    let expected: [ColorSpace: Int] = [.hsl: 0, .hwb: 0, .lch: 2, .oklch: 2]
    for space in ColorSpace.allCases {
      #expect(space.hueIndex == expected[space], "\(space.rawValue)")
    }
  }

  // MARK: Private

  /// Whether `value` rounds to `printed` at the precision `printed` was written to.
  private func rounds(_ value: Double, to printed: Double, decimals: Int) -> Bool {
    let scale = pow(10.0, Double(decimals))
    return (value * scale).rounded() == (printed * scale).rounded()
  }
}
