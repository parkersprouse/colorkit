//
//  TransferFunctions.swift
//  ColorKit
//

import Foundation

/// Gamma encode/decode curves for the RGB spaces.
///
/// Every curve here is **sign-preserving**: it mirrors around zero rather than
/// clamping. That is what lets a color sit meaningfully outside its gamut (negative
/// channels and all) until something explicitly asks for it to be mapped back in.
/// Clamping here instead would quietly destroy out-of-gamut colors on every
/// conversion.
nonisolated enum TransferFunction {
  // MARK: Internal

  // MARK: sRGB — also used verbatim by Display P3

  static func srgbEncode(_ v: Double) -> Double {
    let sign: Double = v < 0 ? -1 : 1
    let magnitude = v * sign
    if magnitude > 0.0031308 {
      return sign * (1.055 * pow(magnitude, 1 / 2.4) - 0.055)
    }
    return 12.92 * v
  }

  static func srgbDecode(_ v: Double) -> Double {
    let sign: Double = v < 0 ? -1 : 1
    let magnitude = v * sign
    if magnitude <= 0.04045 {
      return v / 12.92
    }
    return sign * pow((magnitude + 0.055) / 1.055, 2.4)
  }

  // MARK: A98 RGB — a pure power curve of 256/563

  static func a98Encode(_ v: Double) -> Double {
    let sign: Double = v < 0 ? -1 : 1
    return pow(abs(v), 256.0 / 563.0) * sign
  }

  static func a98Decode(_ v: Double) -> Double {
    let sign: Double = v < 0 ? -1 : 1
    return pow(abs(v), 563.0 / 256.0) * sign
  }

  static func proPhotoEncode(_ v: Double) -> Double {
    let sign: Double = v < 0 ? -1 : 1
    let magnitude = v * sign
    if magnitude >= proPhotoEt {
      return sign * pow(magnitude, 1 / 1.8)
    }
    return 16 * v
  }

  static func proPhotoDecode(_ v: Double) -> Double {
    let sign: Double = v < 0 ? -1 : 1
    let magnitude = v * sign
    if magnitude < proPhotoEt2 {
      return v / 16
    }
    return sign * pow(magnitude, 1.8)
  }

  // MARK: Rec.2020

  //
  // CSS `color(rec2020 …)` uses the BT.1886 display-referred EOTF — a pure 2.4
  // gamma — *not* the piecewise BT.2020 OETF with its α/β constants. The two are
  // easy to confuse and disagree visibly; the scene-referred OETF is a different
  // space that CSS does not expose.

  static func rec2020Encode(_ v: Double) -> Double {
    let sign: Double = v < 0 ? -1 : 1
    return sign * pow(v * sign, 1 / 2.4)
  }

  static func rec2020Decode(_ v: Double) -> Double {
    let sign: Double = v < 0 ? -1 : 1
    return sign * pow(v * sign, 2.4)
  }

  // MARK: Vector helpers

  static func map(_ v: SIMD3<Double>, _ f: (Double) -> Double) -> SIMD3<Double> {
    SIMD3(f(v.x), f(v.y), f(v.z))
  }

  // MARK: Private

  // MARK: ProPhoto — gamma 1.8 with a short linear toe

  private static let proPhotoEt = 1.0 / 512.0
  private static let proPhotoEt2 = 16.0 / 512.0
}

/// CIE standard illuminant tristimulus values, matching the four-digit
/// chromaticity-derived form used across the CSS ecosystem.
nonisolated enum WhitePoint {
  static let d50 = SIMD3<Double>(
    0.3457 / 0.3585,
    1.00000,
    (1.0 - 0.3457 - 0.3585) / 0.3585,
  )

  static let d65 = SIMD3<Double>(
    0.3127 / 0.3290,
    1.00000,
    (1.0 - 0.3127 - 0.3290) / 0.3290,
  )
}
