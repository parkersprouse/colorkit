//
//  Conversion.swift
//  ColorKit
//

import Foundation

/// Converts color components between spaces.
///
/// Everything pivots through **XYZ D65** as a connection space, so adding a space
/// later means implementing two functions rather than N pairwise conversions.
/// Conversions within a family (`rgb`/`hsl`/`hwb`, `lab`/`lch`, `oklab`/`oklch`)
/// short-circuit the pivot — see `direct(_:from:to:)`.
nonisolated enum Conversion {
  // MARK: Internal

  // MARK: - Thresholds

  /// How far apart two sRGB channels must be before the color has a hue worth reporting.
  ///
  /// The sibling of ``ColorSpace/polarEpsilon`` and derived the same way — the channel's
  /// reference range (0–1) over 100000 — so the RGB-based polar forms and the Lab-based
  /// ones agree about what counts as grey.
  ///
  /// It has margin at both ends by eleven orders of magnitude: the float dust it exists to
  /// reject is around `1e-16`, and the smallest difference it suppresses is `1e-5` of a
  /// channel, which is 1/400th of an 8-bit step and carries a saturation that rounds to
  /// `0%` at any precision this app offers.
  static let achromaticChannelEpsilon = 1.0 / 100_000.0

  // MARK: - Entry point

  static func convert(
    _ components: SIMD3<Double>,
    from source: ColorSpace,
    to target: ColorSpace,
  ) -> SIMD3<Double> {
    if source == target {
      return components
    }
    if let shortcut = direct(components, from: source, to: target) {
      return shortcut
    }
    return fromXYZD65(toXYZD65(components, from: source), to: target)
  }

  // MARK: - To the connection space

  static func toXYZD65(_ c: SIMD3<Double>, from space: ColorSpace) -> SIMD3<Double> {
    switch space {
    case .xyzD65:
      return c
    case .xyzD50:
      return Matrices.bradfordD50ToD65(c)
    case .srgb:
      return Matrices.srgbLinearToXYZD65(TransferFunction.map(c, TransferFunction.srgbDecode))
    case .srgbLinear:
      return Matrices.srgbLinearToXYZD65(c)
    case .hsl:
      return toXYZD65(hslToSRGB(c), from: .srgb)
    case .hwb:
      return toXYZD65(hsvToSRGB(hwbToHSV(c)), from: .srgb)
    case .displayP3:
      return Matrices.p3LinearToXYZD65(TransferFunction.map(c, TransferFunction.srgbDecode))
    case .a98RGB:
      return Matrices.a98LinearToXYZD65(TransferFunction.map(c, TransferFunction.a98Decode))
    case .rec2020:
      return Matrices.rec2020LinearToXYZD65(
        TransferFunction.map(c, TransferFunction.rec2020Decode),
      )
    case .proPhotoRGB:
      // ProPhoto is natively D50-referenced, so it lands in XYZ D50 and needs
      // adapting — unlike every other RGB space here.
      let d50 = Matrices.proPhotoLinearToXYZD50(
        TransferFunction.map(c, TransferFunction.proPhotoDecode),
      )
      return Matrices.bradfordD50ToD65(d50)
    case .lab:
      // CSS lab() is D50-referenced. Skipping this adaptation is the single
      // most common source of "looks right, disagrees with the browser".
      return Matrices.bradfordD50ToD65(labToXYZD50(c))
    case .lch:
      return toXYZD65(polarToRectangular(c), from: .lab)
    case .oklab:
      return okLabToXYZD65(c)
    case .oklch:
      return okLabToXYZD65(polarToRectangular(c))
    }
  }

  // MARK: - From the connection space

  static func fromXYZD65(_ xyz: SIMD3<Double>, to space: ColorSpace) -> SIMD3<Double> {
    switch space {
    case .xyzD65:
      return xyz
    case .xyzD50:
      return Matrices.bradfordD65ToD50(xyz)
    case .srgb:
      return TransferFunction.map(Matrices.xyzD65ToSRGBLinear(xyz), TransferFunction.srgbEncode)
    case .srgbLinear:
      return Matrices.xyzD65ToSRGBLinear(xyz)
    case .hsl:
      return srgbToHSL(fromXYZD65(xyz, to: .srgb))
    case .hwb:
      return hsvToHWB(srgbToHSV(fromXYZD65(xyz, to: .srgb)))
    case .displayP3:
      return TransferFunction.map(Matrices.xyzD65ToP3Linear(xyz), TransferFunction.srgbEncode)
    case .a98RGB:
      return TransferFunction.map(Matrices.xyzD65ToA98Linear(xyz), TransferFunction.a98Encode)
    case .rec2020:
      return TransferFunction.map(
        Matrices.xyzD65ToRec2020Linear(xyz), TransferFunction.rec2020Encode,
      )
    case .proPhotoRGB:
      let d50 = Matrices.bradfordD65ToD50(xyz)
      return TransferFunction.map(
        Matrices.xyzD50ToProPhotoLinear(d50), TransferFunction.proPhotoEncode,
      )
    case .lab:
      return xyzD50ToLab(Matrices.bradfordD65ToD50(xyz))
    case .lch:
      return rectangularToPolar(
        fromXYZD65(xyz, to: .lab), epsilon: ColorSpace.lch.polarEpsilon!,
      )
    case .oklab:
      return xyzD65ToOKLab(xyz)
    case .oklch:
      return rectangularToPolar(
        xyzD65ToOKLab(xyz), epsilon: ColorSpace.oklch.polarEpsilon!,
      )
    }
  }

  static func xyzD50ToLab(_ xyz: SIMD3<Double>) -> SIMD3<Double> {
    let scaled = xyz / WhitePoint.d50
    let f = TransferFunction.map(scaled) { $0 > ε ? cbrt($0) : (κ * $0 + 16) / 116 }
    return SIMD3(
      116 * f.y - 16,
      500 * (f.x - f.y),
      200 * (f.y - f.z),
    )
  }

  static func labToXYZD50(_ lab: SIMD3<Double>) -> SIMD3<Double> {
    let f1 = (lab.x + 16) / 116
    let f0 = lab.y / 500 + f1
    let f2 = f1 - lab.z / 200

    let xyz = SIMD3<Double>(
      f0 > ε3 ? pow(f0, 3) : (116 * f0 - 16) / κ,
      lab.x > 8 ? pow((lab.x + 16) / 116, 3) : lab.x / κ,
      f2 > ε3 ? pow(f2, 3) : (116 * f2 - 16) / κ,
    )
    return xyz * WhitePoint.d50
  }

  // MARK: - OKLab (D65)

  static func xyzD65ToOKLab(_ xyz: SIMD3<Double>) -> SIMD3<Double> {
    let lms = Matrices.xyzD65ToLMS(xyz)
    let nonlinear = SIMD3<Double>(cbrt(lms.x), cbrt(lms.y), cbrt(lms.z))
    return Matrices.lmsToOKLab(nonlinear)
  }

  static func okLabToXYZD65(_ oklab: SIMD3<Double>) -> SIMD3<Double> {
    let nonlinear = Matrices.okLabToLMS(oklab)
    let lms = SIMD3<Double>(
      nonlinear.x * nonlinear.x * nonlinear.x,
      nonlinear.y * nonlinear.y * nonlinear.y,
      nonlinear.z * nonlinear.z * nonlinear.z,
    )
    return Matrices.lmsToXYZD65(lms)
  }

  // MARK: - Polar forms (shared by lch and oklch)

  /// Rectangular a/b to polar chroma/hue.
  ///
  /// Below `epsilon` the color is achromatic and hue is genuinely undefined —
  /// reported as `0` here and flagged missing by the caller, rather than
  /// fabricating whatever `atan2` returns for numerical dust.
  static func rectangularToPolar(_ lab: SIMD3<Double>, epsilon: Double) -> SIMD3<Double> {
    let isAchromatic = abs(lab.y) < epsilon && abs(lab.z) < epsilon
    if isAchromatic {
      return SIMD3(lab.x, 0, 0)
    }
    let hue = atan2(lab.z, lab.y) * 180 / .pi
    let chroma = (lab.y * lab.y + lab.z * lab.z).squareRoot()
    return SIMD3(lab.x, chroma, constrainAngle(hue))
  }

  static func polarToRectangular(_ lch: SIMD3<Double>) -> SIMD3<Double> {
    let chroma = max(0, lch.y) // negative chroma is meaningless; clamp
    let radians = lch.z * .pi / 180
    return SIMD3(lch.x, chroma * cos(radians), chroma * sin(radians))
  }

  static func constrainAngle(_ angle: Double) -> Double {
    let wrapped = angle.truncatingRemainder(dividingBy: 360)
    return wrapped < 0 ? wrapped + 360 : wrapped
  }

  // MARK: - HSL / HSV / HWB

  //
  // These operate on *gamma-encoded* sRGB, not linear light — a quirk of their
  // 1970s origins that CSS preserved.

  /// The hue shared by HSL and HSV, in degrees.
  ///
  /// **One implementation because the two had the same six lines and the same missing
  /// guard.** Both used to compute a hue whenever `delta != 0` — an *exact* comparison —
  /// where ``rectangularToPolar`` has always used an epsilon and says why: a hue derived
  /// from numerical dust is a real number that means nothing.
  ///
  /// The exact test is not merely imprecise, it is wrong in a way you can read. A neutral
  /// grey reaching sRGB *through a conversion* has channels that differ in the last ULP
  /// rather than not at all, so `delta` is around `1e-16` and the hue becomes a ratio of
  /// two pieces of noise — any angle at all. That is how an exported greyscale ramp came
  /// to read `hsl(336 0% 96.06%)`, `hsl(350 0% 87.86%)`, `hsl(345 0% 79.79%)`, with the
  /// hue wandering across a set of colors that have no hue. It rendered correctly, because
  /// a browser ignores hue at zero saturation; it was the *text* that was wrong, and the
  /// text is what gets pasted into somebody's stylesheet.
  ///
  /// A grey typed directly in sRGB was always fine — its channels are bit-identical, so
  /// `delta` is exactly `0`. Only converted greys were affected, which is what kept this
  /// out of every hand-written test.
  static func hueFromRGB(_ rgb: SIMD3<Double>, maxC: Double, delta: Double) -> Double {
    guard delta > achromaticChannelEpsilon else { return 0 }
    let hue: Double = if maxC == rgb.x {
      (rgb.y - rgb.z) / delta + (rgb.y < rgb.z ? 6 : 0)
    } else if maxC == rgb.y {
      (rgb.z - rgb.x) / delta + 2
    } else {
      (rgb.x - rgb.y) / delta + 4
    }
    return hue * 60
  }

  static func srgbToHSL(_ rgb: SIMD3<Double>) -> SIMD3<Double> {
    let maxC = max(rgb.x, rgb.y, rgb.z)
    let minC = min(rgb.x, rgb.y, rgb.z)
    let lightness = (minC + maxC) / 2
    let delta = maxC - minC

    var hue = hueFromRGB(rgb, maxC: maxC, delta: delta)
    var saturation = 0.0

    // Saturation keeps the exact `delta != 0` test on purpose, where the hue does not.
    // A near-grey has a real, if minute, saturation and zeroing it would lose the only
    // information distinguishing it from a grey — where its *hue* was never information
    // in the first place. Keeping it is also what holds the round trip: reconstructing
    // from hue 0 and the true saturation lands within `achromaticChannelEpsilon`.
    if delta != 0 {
      saturation = (lightness == 0 || lightness == 1)
        ? 0
        : (maxC - lightness) / min(lightness, 1 - lightness)
    }

    // Very out-of-gamut colors can produce negative saturation; rotating the hue
    // by 180° and taking the magnitude expresses the same color legally.
    // See w3c/csswg-drafts#9222.
    if saturation < 0 {
      hue += 180
      saturation = abs(saturation)
    }
    if hue >= 360 {
      hue -= 360
    }

    return SIMD3(hue, saturation * 100, lightness * 100)
  }

  static func hslToSRGB(_ hsl: SIMD3<Double>) -> SIMD3<Double> {
    var hue = hsl.x.truncatingRemainder(dividingBy: 360)
    if hue < 0 {
      hue += 360
    }
    let saturation = hsl.y / 100
    let lightness = hsl.z / 100

    func channel(_ n: Double) -> Double {
      let k = (n + hue / 30).truncatingRemainder(dividingBy: 12)
      let a = saturation * min(lightness, 1 - lightness)
      return lightness - a * max(-1, min(k - 3, 9 - k, 1))
    }

    return SIMD3(channel(0), channel(8), channel(4))
  }

  static func srgbToHSV(_ rgb: SIMD3<Double>) -> SIMD3<Double> {
    let maxC = max(rgb.x, rgb.y, rgb.z)
    let minC = min(rgb.x, rgb.y, rgb.z)
    let delta = maxC - minC

    // Shared with `srgbToHSL`, which is what stops the two drifting apart again — see
    // `hueFromRGB`. HWB rides on this too: `hsvToHWB` passes the hue straight through.
    var hue = hueFromRGB(rgb, maxC: maxC, delta: delta)
    var saturation = 0.0

    if maxC != 0 {
      saturation = delta / maxC
    }
    if hue >= 360 {
      hue -= 360
    }

    return SIMD3(hue, saturation * 100, maxC * 100)
  }

  static func hsvToSRGB(_ hsv: SIMD3<Double>) -> SIMD3<Double> {
    var hue = hsv.x.truncatingRemainder(dividingBy: 360)
    if hue < 0 {
      hue += 360
    }
    let saturation = hsv.y / 100
    let value = hsv.z / 100

    func channel(_ n: Double) -> Double {
      let k = (n + hue / 60).truncatingRemainder(dividingBy: 6)
      return value - value * saturation * max(0, min(k, 4 - k, 1))
    }

    return SIMD3(channel(5), channel(3), channel(1))
  }

  static func hsvToHWB(_ hsv: SIMD3<Double>) -> SIMD3<Double> {
    SIMD3(hsv.x, (hsv.z * (100 - hsv.y)) / 100, 100 - hsv.z)
  }

  static func hwbToHSV(_ hwb: SIMD3<Double>) -> SIMD3<Double> {
    let whiteness = hwb.y / 100
    let blackness = hwb.z / 100

    // White + black saturating past 1 means gray; the ratio picks which gray.
    let sum = whiteness + blackness
    if sum >= 1 {
      return SIMD3(hwb.x, 0, (whiteness / sum) * 100)
    }

    let value = 1 - blackness
    let saturation = value == 0 ? 0 : 1 - whiteness / value
    return SIMD3(hwb.x, saturation * 100, value * 100)
  }

  // MARK: Private

  // MARK: - CIE Lab (D50)

  private static let ε = 216.0 / 24389.0 // 6³/29³
  private static let ε3 = 24.0 / 116.0
  private static let κ = 24389.0 / 27.0 // 29³/3³

  /// Conversions that must not detour through XYZ.
  ///
  /// These pairs describe *identical* underlying values in different coordinates,
  /// so a trip through XYZ would only add float error — and for achromatic colors
  /// it would lose the hue entirely.
  private static func direct(
    _ c: SIMD3<Double>,
    from source: ColorSpace,
    to target: ColorSpace,
  ) -> SIMD3<Double>? {
    guard source.family == target.family else { return nil }

    switch (source, target) {
    case (.srgb, .hsl): return srgbToHSL(c)
    case (.hsl, .srgb): return hslToSRGB(c)
    case (.srgb, .hwb): return hsvToHWB(srgbToHSV(c))
    case (.hwb, .srgb): return hsvToSRGB(hwbToHSV(c))
    case (.hsl, .hwb): return hsvToHWB(srgbToHSV(hslToSRGB(c)))
    case (.hwb, .hsl): return srgbToHSL(hsvToSRGB(hwbToHSV(c)))
    case (.lab, .lch): return rectangularToPolar(c, epsilon: ColorSpace.lch.polarEpsilon!)
    case (.lch, .lab): return polarToRectangular(c)
    case (.oklab, .oklch): return rectangularToPolar(c, epsilon: ColorSpace.oklch.polarEpsilon!)
    case (.oklch, .oklab): return polarToRectangular(c)
    default: return nil
    }
  }
}

// MARK: - ColorValue conversion

nonisolated extension ColorValue {
  /// Returns this color expressed in another space.
  func converted(to target: ColorSpace) -> ColorValue {
    guard space != target else { return self }
    let converted = Conversion.convert(components, from: space, to: target)

    // Alpha's missing flag survives; component flags do not, since components
    // don't correspond across spaces.
    let carriedMissing: ComponentMask = missing.contains(.alpha) ? .alpha : []

    return ColorValue(
      space: target,
      components: converted,
      alpha: alpha,
      missing: carriedMissing,
    )
  }
}
