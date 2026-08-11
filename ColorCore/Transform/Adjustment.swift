//
//  Adjustment.swift
//  ColorKit
//

import Foundation

/// A color's OKLCH coordinate, which is where every transform in this folder works.
///
/// OKLCH rather than HSL for the reason the whole app leans on it: its lightness is
/// perceptual, so nudging `L` by the same amount looks like the same amount of change
/// at every hue. HSL's lightness does not — `hsl(60 100% 50%)` (yellow) and
/// `hsl(240 100% 50%)` (blue) claim the same lightness while one is nearly white and
/// the other nearly black, so a ramp built on it lurches.
///
/// A struct rather than a tuple so the three numbers cannot be passed in the wrong
/// order, and mirroring ``HSVComponents`` — the other coordinate the app keeps on the
/// side of the space model.
nonisolated struct OKLCHComponents: Sendable, Hashable {
  // MARK: Lifecycle

  init(lightness: Double, chroma: Double, hue: Double) {
    self.lightness = lightness
    self.chroma = chroma
    self.hue = Conversion.constrainAngle(hue)
  }

  // MARK: Internal

  /// Perceptual lightness, `0` (black) to `1` (white).
  var lightness: Double
  /// Distance from the neutral axis. Unbounded in principle; sRGB tops out near
  /// `0.32` and most hues fall well short — see ``GamutBoundary``.
  var chroma: Double
  /// Degrees, normalized to `0..<360`.
  var hue: Double
}

nonisolated extension ColorValue {
  /// This color's OKLCH coordinate.
  ///
  /// Unlike ``hsvComponents`` this does **not** gamut-map first, and must not: OKLCH
  /// is unbounded, so it can describe a Display P3 sample exactly, and mapping on the
  /// way in would silently narrow every wide color the moment a transform touched it
  /// — the same clipping the eyedropper goes out of its way to avoid.
  ///
  /// Hue is `0` for a gray, meaninglessly. Callers that hold a hue the user chose
  /// should keep theirs; see ``isAchromatic``.
  var oklchComponents: OKLCHComponents {
    let oklch = converted(to: .oklch)
    return OKLCHComponents(
      lightness: oklch.components.x,
      chroma: oklch.components.y,
      hue: oklch.components.z,
    )
  }

  /// A new OKLCH color carrying this one's alpha — how every transform returns.
  ///
  /// **Results stay in OKLCH rather than returning to the input's space.** Two
  /// reasons, and the second is the one that bites. A round trip back to `#3b82f6`
  /// would quantize onto the 8-bit grid, so nudging lightness by a hundredth would
  /// produce the color you started with; and any transform that leaves the sRGB
  /// gamut — most hue rotations of a saturated color do — has no honest spelling in
  /// a bounded space at all. OKLCH can hold every result exactly, and the badge and
  /// serializer already know what to do with a value that sits outside sRGB.
  ///
  /// Negative chroma is folded to zero rather than reflected across the hue: it means
  /// "less saturated than gray", which is not a color.
  func derivedOKLCH(_ components: OKLCHComponents) -> ColorValue {
    ColorValue(
      space: .oklch,
      components.lightness,
      max(components.chroma, 0),
      components.hue,
      alpha: alpha,
      // Alpha's missingness is the only part that survives: a rotated hue is
      // present by construction, and so is a scaled chroma.
      missing: missing.contains(.alpha) ? .alpha : [],
    )
  }
}

/// A relative nudge to a color's OKLCH coordinate.
///
/// **Relative on purpose.** The M6 picker already sets `L`, `C` and `h` absolutely, so
/// a second panel of absolute sliders would be the same tool twice. What that panel
/// cannot do is *transform*: take the color you have and ask for it a little lighter,
/// a little less saturated, thirty degrees round. That is a different question, and it
/// is the one that composes — the same adjustment applied to a whole palette keeps the
/// relationships between its members, which is exactly what absolute values destroy.
///
/// Hence the three different operators, which are not arbitrary:
///
/// - **Lightness adds.** `L` is already perceptually uniform on a fixed `0...1` scale,
///   so "10% lighter" is a fixed distance, not a proportion of where you started.
/// - **Chroma multiplies.** It has no upper bound and its useful range depends on both
///   lightness and hue, so a fixed `+0.05` would be a rounding error on a vivid color
///   and would double a muted one. Halving is meaningful everywhere.
/// - **Hue adds**, in degrees, and wraps. It is an angle.
nonisolated struct OKLCHAdjustment: Sendable, Equatable {
  static let identity = OKLCHAdjustment()

  /// Added to lightness, on the `0...1` scale.
  var lightnessDelta: Double = 0
  /// Multiplied into chroma. `1` leaves it alone, `0` neutralizes the color.
  var chromaScale: Double = 1
  /// Added to hue, in degrees.
  var hueRotation: Double = 0

  /// Whether this would leave a color untouched, so the UI can say "no change" rather
  /// than showing a result swatch identical to its input.
  var isIdentity: Bool {
    self == .identity
  }

  /// The reverse nudge, which returns an adjusted color to where it started.
  ///
  /// Exact for hue and chroma; lightness clamps at the ends of the scale, so pushing
  /// a color past white and back does not restore it. That is a property of the
  /// range, not a bug in the arithmetic — asserted in the tests rather than papered
  /// over.
  var inverted: OKLCHAdjustment {
    OKLCHAdjustment(
      lightnessDelta: -lightnessDelta,
      // A scale of zero has no inverse: every color it touches becomes the same
      // gray, and no multiplier brings a distinct chroma back out of it.
      chromaScale: chromaScale == 0 ? 0 : 1 / chromaScale,
      hueRotation: -hueRotation,
    )
  }

  /// Applies this nudge, in OKLCH.
  ///
  /// Lightness is clamped to `0...1` because it has real endpoints — nothing is
  /// darker than black — while chroma and hue are left unbounded, since a result
  /// outside the sRGB gamut is a legitimate answer this app is built to carry.
  func applied(to color: ColorValue) -> ColorValue {
    var components = color.oklchComponents
    components.lightness = min(max(components.lightness + lightnessDelta, 0), 1)
    components.chroma = max(components.chroma * chromaScale, 0)
    components.hue = Conversion.constrainAngle(components.hue + hueRotation)
    return color.derivedOKLCH(components)
  }

  /// How far ``lightnessDelta`` can move `color` before ``applied(to:)``'s own
  /// `0...1` clamp swallows the rest — the same fact expressed as a range up front
  /// rather than discovered a slider-width later.
  ///
  /// **Not mode-dependent.** The clamp inside `applied(to:)` runs whether or not
  /// web-friendly mode is on — nothing is darker than black or lighter than white in
  /// either case — so a slider whose travel reached past it would have the identical
  /// dead zone with the mode off. `lightness` sits in `0...1` by construction, which
  /// is what guarantees `lower <= 0 <= upper`: the identity delta is always in range.
  static func lightnessDeltaRange(
    for color: ColorValue,
    extent: ClosedRange<Double> = -0.5 ... 0.5,
  ) -> ClosedRange<Double> {
    let lightness = color.oklchComponents.lightness
    let lower = max(extent.lowerBound, -lightness)
    let upper = min(extent.upperBound, 1 - lightness)
    return lower ... upper
  }

  /// The ``chromaScale`` past which every larger scale clamps to the same chroma
  /// under web-friendly mode, because ``ColorValue/pulledInto(_:)`` pulls every one
  /// of them back to `gamut`'s own boundary chroma regardless of how much further the
  /// scale still climbs.
  ///
  /// Derived from `color`'s own lightness and hue, **not** the pending adjustment's —
  /// reading the adjusted lightness or hue instead would make dragging the Lightness
  /// or Hue slider silently rescale a Chroma the user already set for a reason of its
  /// own. That leaves this ceiling exact only while Lightness and Hue sit at their
  /// identity and a hair loose once they have moved too, which is the smaller and
  /// more predictable kind of wrong.
  ///
  /// Floored at `1` so the identity scale (`×1.00`) always stays reachable, even when
  /// `color` itself already sits outside `gamut` — web-friendly mode hides tools, it
  /// does not reject a typed wide-gamut color, so that state is reachable in practice.
  static func chromaScaleRange(
    for color: ColorValue,
    in gamut: ColorSpace,
    extent: ClosedRange<Double> = 0 ... 2,
  ) -> ClosedRange<Double> {
    guard !color.isAchromatic else { return extent }
    let components = color.oklchComponents
    let boundary = GamutBoundary.maxChroma(lightness: components.lightness, hue: components.hue, in: gamut)
    let ceiling = boundary / components.chroma
    let upper = min(extent.upperBound, max(1, ceiling))
    return extent.lowerBound ... upper
  }
}
