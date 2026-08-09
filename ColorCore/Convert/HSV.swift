//
//  HSV.swift
//  ColorKit
//

import Foundation

/// The coordinate a square-and-strip picker actually moves in.
///
/// Deliberately **not** a ``ColorSpace`` case. CSS has no `hsv()` function, so a case
/// here would have to be excluded by hand from the parser, the serializer, the format
/// catalog and every `allCases` loop — and the first one forgotten would offer the
/// user a format no browser accepts. HSV is a parameterization of sRGB that one panel
/// needs, so it lives as a coordinate on the side rather than as a space in the model.
///
/// Scales follow the rest of ColorCore: hue in degrees, saturation and value as
/// percentages, matching how HSL and HWB components are stored.
nonisolated struct HSVComponents: Sendable, Hashable {
  // MARK: Lifecycle

  init(hue: Double, saturation: Double, value: Double) {
    self.hue = Conversion.constrainAngle(hue)
    self.saturation = saturation
    self.value = value
  }

  // MARK: Internal

  /// Degrees, normalized to `0..<360`.
  var hue: Double
  /// Percent, `0...100`.
  var saturation: Double
  /// Percent, `0...100`.
  var value: Double
}

nonisolated extension ColorValue {
  /// This color's HSV coordinate.
  ///
  /// Gamut-maps into sRGB on the way, because HSV is a description of the sRGB cube
  /// and a wider color has no honest coordinate in it. Mapping rather than clipping
  /// so that seeding the picker from a P3 sample lands on the nearest color the
  /// square can actually show, with its hue intact.
  ///
  /// Hue survives an achromatic color as `0` — meaninglessly, since gray has no hue.
  /// Callers holding a hue the user chose should keep theirs; see
  /// ``ColorValue/isAchromatic``.
  var hsvComponents: HSVComponents {
    let hsv = Conversion.srgbToHSV(convertedAndMapped(to: .srgb).components)
    return HSVComponents(hue: hsv.x, saturation: hsv.y, value: hsv.z)
  }

  /// An sRGB color from an HSV coordinate.
  ///
  /// The result is stored as ``ColorSpace/srgb`` rather than carrying HSV with it:
  /// the two are the same value, and sRGB is the one the rest of the app can
  /// serialize.
  init(hsv: HSVComponents, alpha: Double = 1) {
    self.init(
      space: .srgb,
      components: Conversion.hsvToSRGB(
        SIMD3(hsv.hue, hsv.saturation, hsv.value),
      ),
      alpha: alpha,
    )
  }
}
