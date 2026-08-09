//
//  APCAContrast.swift
//  ColorKit
//

import Foundation

/// APCA — Accessible Perceptual Contrast Algorithm, the candidate successor to WCAG's
/// contrast ratio.
///
/// Two things make it different from ``ColorValue/contrastRatio(with:)``, and both are
/// the point rather than details:
///
/// - **It is not symmetric.** Dark text on a light background and light text on a dark
///   background are different problems with different answers, which WCAG's ratio
///   cannot express at all. The result is signed: positive means dark-on-light.
/// - **It is not a ratio.** `Lc` is a lightness *difference* on a roughly perceptual
///   scale running to about ±108, so "Lc 75" and "4.5:1" are not convertible.
///
/// - Important: This is **APCA 0.0.98G**, transcribed from colorjs.io 0.7.0 — the same
///   pinned package that is the conversion oracle. The version matters: APCA's
///   constants have changed across revisions, and a bare constant with no version
///   beside it is the field most likely to rot. APCA is also a *draft*; nothing here
///   is normative, and WCAG 2.2 conformance still means the ratio.
nonisolated enum APCA {
  // MARK: - Constants (APCA 0.0.98G)

  // Exponents.
  static let normBG = 0.56
  static let normTXT = 0.57
  static let revTXT = 0.62
  static let revBG = 0.65

  // Clamps.
  static let blackThreshold = 0.022
  static let blackClamp = 1.414
  static let lowClip = 0.1
  static let deltaYMin = 0.0005

  // Scalers.
  static let scale = 1.14
  static let lowOffset = 0.027

  /// Luminance coefficients — **not** CSS Color 4's `0.2126 / 0.7152 / 0.0722`.
  ///
  /// APCA specifies these (via Lindbloom) and colorjs.io's implementation carries a
  /// comment noting the discrepancy with CSS. Substituting the CSS values would
  /// produce a small, plausible, everywhere-wrong divergence — the exact shape of
  /// bug that looks like a rounding artifact and isn't.
  static let coefficients = (red: 0.2126729, green: 0.7151522, blue: 0.072175)

  /// APCA's own linearization: a plain 2.4 power, sign-preserving.
  ///
  /// Deliberately *not* the sRGB transfer function. colorjs.io's source calls it a
  /// "non-standard simple gamma EOTF" — APCA models display response rather than
  /// inverting sRGB encoding, so there is no piecewise linear segment near black.
  static func linearize(_ channel: Double) -> Double {
    let sign: Double = channel < 0 ? -1 : 1
    return sign * pow(abs(channel), 2.4)
  }

  /// Lifts very dark values to account for screen flare, which is why APCA does not
  /// simply run out of resolution against black.
  static func flareClamp(_ y: Double) -> Double {
    y >= blackThreshold ? y : y + pow(blackThreshold - y, blackClamp)
  }
}

nonisolated extension ColorValue {
  /// APCA lightness contrast (`Lc`) for **this color as text** on `background`.
  ///
  /// Positive values mean dark text on a light background, negative means light on
  /// dark. Roughly ±108 at the extremes; black on white measures about 106.
  ///
  /// Reads `self` as the text and the argument as the background, which is the
  /// opposite order to colorjs.io's `contrast(background, foreground)`. Getting this
  /// backwards does not fail loudly — it returns a plausible number of the wrong
  /// sign — so both polarities are asserted in the tests.
  ///
  /// Alpha is ignored, as in WCAG: composite first if it matters.
  func apcaContrast(on background: ColorValue) -> Double {
    // APCA is defined on sRGB. Gamut-mapped rather than passed through, matching
    // `wcagRelativeLuminance` — and necessary besides, because a negative
    // component survives `linearize` only to reach `pow(negative, 0.56)` below and
    // become NaN. colorjs.io's source leaves this case explicitly unspecified
    // ("Should these be clamped to in-gamut values?"), so the fixture that
    // validates against it stays inside sRGB.
    let textY = APCA.flareClamp(Self.apcaLuminance(of: self))
    let backgroundY = APCA.flareClamp(Self.apcaLuminance(of: background))

    // A noise gate, not a perceptual judgement: below this the two colors are the
    // same to the algorithm, and the exponent maths would amplify float error into
    // a confident-looking answer.
    guard abs(backgroundY - textY) >= APCA.deltaYMin else { return 0 }

    let darkOnLight = backgroundY > textY
    let difference =
      darkOnLight
        ? pow(backgroundY, APCA.normBG) - pow(textY, APCA.normTXT)
        : pow(backgroundY, APCA.revBG) - pow(textY, APCA.revTXT)
    let contrast = difference * APCA.scale

    // Everything below the clip is reported as zero rather than as a small number,
    // because APCA makes no claim to be meaningful down there.
    guard abs(contrast) >= APCA.lowClip else { return 0 }
    return (contrast > 0 ? contrast - APCA.lowOffset : contrast + APCA.lowOffset) * 100
  }

  private static func apcaLuminance(of color: ColorValue) -> Double {
    let srgb = color.convertedAndMapped(to: .srgb)
    return APCA.linearize(srgb.components.x) * APCA.coefficients.red
      + APCA.linearize(srgb.components.y) * APCA.coefficients.green
      + APCA.linearize(srgb.components.z) * APCA.coefficients.blue
  }
}
