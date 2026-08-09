//
//  CVDSimulation.swift
//  ColorKit
//

import Foundation

/// A colour-vision deficiency the Machado et al. (2009) model can simulate at any
/// severity.
///
/// The three anomalous-trichromacy types, each a defective cone class. Their
/// dichromatic endpoints — protanopia, deuteranopia, tritanopia — are severity `1.0`;
/// severity `0.0` is normal vision. Carried as a *fact* only: the display names
/// ("Red-blind", "Deuteranomaly") are editorial copy and belong to the UI layer, the
/// same split ``ContrastRequirement`` keeps.
nonisolated enum ColorVisionDeficiency: String, CaseIterable, Sendable, Hashable, Codable {
  /// Defective long-wavelength (L / "red") cones. Severity 1.0 is protanopia.
  case protanomaly
  /// Defective medium-wavelength (M / "green") cones. Severity 1.0 is deuteranopia.
  case deuteranomaly
  /// Defective short-wavelength (S / "blue") cones. Severity 1.0 is tritanopia.
  case tritanomaly

  // MARK: Internal

  /// The eleven Table 1 matrices for this deficiency, severity 0.0…1.0 in 0.1 steps.
  var matrices: [ColorMatrix] {
    switch self {
    case .protanomaly: CVDMatrices.protanomaly
    case .deuteranomaly: CVDMatrices.deuteranomaly
    case .tritanomaly: CVDMatrices.tritanomaly
    }
  }

  /// The simulation matrix at an arbitrary severity.
  ///
  /// Table 1 tabulates severity in 0.1 increments; a value between two steps is a
  /// linear blend of its neighbours, matching the reference implementations
  /// (daltonlens, colour-science). An exact 0.1 step returns its published matrix
  /// untouched, so those cases are Table 1 verbatim rather than an approximation.
  func matrix(severity: Double) -> ColorMatrix {
    let scaled = min(max(severity, 0), 1) * 10
    let lower = min(Int(scaled), 10)
    let upper = min(lower + 1, 10)
    let t = scaled - Double(lower)

    let a = matrices[lower]
    let b = matrices[upper]
    func lerp(_ x: Double, _ y: Double) -> Double {
      x + t * (y - x)
    }
    return ColorMatrix(
      lerp(a.m00, b.m00), lerp(a.m01, b.m01), lerp(a.m02, b.m02),
      lerp(a.m10, b.m10), lerp(a.m11, b.m11), lerp(a.m12, b.m12),
      lerp(a.m20, b.m20), lerp(a.m21, b.m21), lerp(a.m22, b.m22),
    )
  }
}

nonisolated extension ColorValue {
  /// This colour as someone with `deficiency` at `severity` would see it, in sRGB.
  ///
  /// Machado's matrices operate on **linear light**, not gamma-encoded sRGB — a
  /// distinction that is easy to get wrong and visibly wrong when you do. The
  /// pipeline therefore:
  ///
  /// 1. Gamut-maps into sRGB. An out-of-sRGB `oklch()` has no on-screen appearance to
  ///    simulate, and its negative channels would make the matrix meaningless; an
  ///    already-in-gamut colour passes through unchanged.
  /// 2. Decodes to linear sRGB and applies the severity-interpolated matrix.
  /// 3. Clamps back into `[0, 1]` — the matrices can push a channel just past the
  ///    display range (tritanomaly's first row sums above one) — and re-encodes.
  ///
  /// Alpha is carried through untouched: a deficiency changes which colours are
  /// confused, not how opaque they are. Severity `0.0` returns the colour unchanged
  /// (to within an sRGB decode/encode round trip).
  func simulating(_ deficiency: ColorVisionDeficiency, severity: Double) -> ColorValue {
    let matrix = deficiency.matrix(severity: severity)

    let linear = convertedAndMapped(to: .srgb).converted(to: .srgbLinear).components
    let simulated = matrix(linear)

    let clamped = SIMD3<Double>(
      min(max(simulated.x, 0), 1),
      min(max(simulated.y, 0), 1),
      min(max(simulated.z, 0), 1),
    )

    var result = ColorValue(space: .srgbLinear, components: clamped)
      .converted(to: .srgb)
    result.alpha = alpha
    result.missing = missing.contains(.alpha) ? .alpha : []
    return result
  }
}
