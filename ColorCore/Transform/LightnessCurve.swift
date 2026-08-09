//
//  LightnessCurve.swift
//  ColorKit
//

import Foundation

/// An S-curve on OKLCH lightness: contrast without a second color.
///
/// The other contrast tool in this app — ``ContrastSolver`` — answers "how do I make
/// *this* readable on *that*". This one answers the question that has no second color
/// in it: take what I have and make it punchier. Darks go darker, lights go lighter,
/// and mid-gray stays put. It is the curves adjustment every image editor has, applied
/// to a color or a palette instead of to pixels.
///
/// **The pivot is fixed at `L = 0.5`** rather than configurable, and that is what makes
/// the transform well behaved: the curve is then exactly symmetric, its fixed points
/// are black, mid-gray and white, and ``inverted`` undoes it to the last bit. A movable
/// pivot would cost all three for a knob nobody reaches for.
///
/// Applied to a **set** it earns its keep — see ``applied(to:)-([ColorValue])``. On a
/// single color it only moves lightness, which ``OKLCHAdjustment`` can also do; across
/// a ramp or a harmony it widens the whole spread at once, which nothing else here can.
nonisolated struct LightnessCurve: Sendable, Equatable {
  static let identity = LightnessCurve()

  /// How hard the curve bends, `-1` (flattest) through `0` (no change) to `1`
  /// (punchiest).
  ///
  /// Signed and centered on zero because this is a slider before it is a number, and
  /// a control whose neutral position is `1.0` invites being left somewhere it does
  /// nothing useful. The exponent it drives is ``gamma``.
  var strength: Double = 0

  var isIdentity: Bool {
    strength == 0
  }

  /// The reverse bend. Exact, not approximate — see ``curve(_:gamma:)``.
  var inverted: LightnessCurve {
    LightnessCurve(strength: -strength)
  }

  /// The exponent the strength maps onto: `3` at full punch, `1/3` at full flatten.
  ///
  /// Exponential rather than linear so that opposite strengths are reciprocal
  /// exponents, which is precisely the condition for the curve to invert exactly.
  /// A linear mapping would make `+0.5` and `-0.5` fail to cancel.
  var gamma: Double {
    pow(3, min(max(strength, -1), 1))
  }

  /// The scalar curve, on `0...1`.
  ///
  /// Two mirrored power functions meeting at the midpoint. Monotonic for any positive
  /// gamma, so it never reorders a ramp; fixed at `0`, `0.5` and `1`, so it cannot
  /// push a color out of the lightness range.
  static func curve(_ x: Double, gamma: Double) -> Double {
    let clamped = min(max(x, 0), 1)
    if clamped < 0.5 {
      return 0.5 * pow(2 * clamped, gamma)
    } else {
      return 1 - 0.5 * pow(2 - 2 * clamped, gamma)
    }
  }

  /// Bends one color's lightness, leaving chroma and hue exactly as they were.
  func applied(to color: ColorValue) -> ColorValue {
    guard !isIdentity else { return color }
    var components = color.oklchComponents
    components.lightness = Self.curve(components.lightness, gamma: gamma)
    return color.derivedOKLCH(components)
  }

  /// Bends a whole set, which is what this is for.
  ///
  /// Every member moves by the same rule rather than by the same amount, so the set
  /// keeps its order and its midpoint while its ends spread apart. That is the
  /// difference between a curve and a lightness offset: an offset slides a ramp,
  /// a curve stretches it.
  func applied(to colors: [ColorValue]) -> [ColorValue] {
    guard !isIdentity else { return colors }
    return colors.map { applied(to: $0) }
  }
}
