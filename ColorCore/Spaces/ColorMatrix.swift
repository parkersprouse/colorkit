//
//  ColorMatrix.swift
//  ColorKit
//

import Foundation

/// A row-major 3x3 matrix used for linear color-space conversion.
///
/// Stored as nine scalars rather than nested arrays: conversions run in tight
/// loops over large fixture sets, and this keeps the values in registers with
/// no heap traffic or bounds checking.
nonisolated struct ColorMatrix: Sendable, Hashable {
  // MARK: Lifecycle

  init(
    _ m00: Double, _ m01: Double, _ m02: Double,
    _ m10: Double, _ m11: Double, _ m12: Double,
    _ m20: Double, _ m21: Double, _ m22: Double,
  ) {
    self.m00 = m00; self.m01 = m01; self.m02 = m02
    self.m10 = m10; self.m11 = m11; self.m12 = m12
    self.m20 = m20; self.m21 = m21; self.m22 = m22
  }

  // MARK: Internal

  let m00: Double
  let m01: Double
  let m02: Double
  let m10: Double
  let m11: Double
  let m12: Double
  let m20: Double
  let m21: Double
  let m22: Double

  /// Multiplies this matrix by a column vector.
  func callAsFunction(_ v: SIMD3<Double>) -> SIMD3<Double> {
    SIMD3(
      m00 * v.x + m01 * v.y + m02 * v.z,
      m10 * v.x + m11 * v.y + m12 * v.z,
      m20 * v.x + m21 * v.y + m22 * v.z,
    )
  }
}
