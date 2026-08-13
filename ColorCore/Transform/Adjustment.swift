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

  /// The Lightness slider's fixed, color-independent track: `-1` always means "as far
  /// down as `color` can go," `0` is always the identity delta (no change), and `+1`
  /// always means "as far up as `color` can go." Pass this as a `Slider`'s own
  /// `in:` range and convert its value through ``lightnessDelta(atFraction:for:)`` /
  /// ``lightnessFraction(forDelta:for:)``.
  ///
  /// This replaced a version that reported a *range of deltas* (`lightnessDeltaRange`)
  /// mirrored about `0` so a linear slider's center would land on the identity value —
  /// which worked, but only by capping the more open side down to match whichever side
  /// had less room. At `L = 0.9`, the wall above sits `0.1` away and the fixed extent
  /// below allowed `0.5`; mirroring took the tighter `0.1` for *both* sides, so the
  /// slider's dark end stopped at `0.8` with `0.9` of real room to black sitting
  /// unused — the bug this shape exists to fix. A single linear scale cannot put the
  /// identity value at its center *and* pin both ends to the true walls unless
  /// `L = 0.5` exactly, so there is no range of deltas that does both; the fix is a
  /// fixed range of *fractions* whose two halves scale against different amounts of
  /// room, not a differently-computed range of deltas.
  static let lightnessFractionRange: ClosedRange<Double> = -1 ... 1

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

  /// Converts a position on ``lightnessFractionRange`` to the delta it stands for,
  /// given `color`'s own lightness.
  ///
  /// The two halves of the track scale independently against whatever room
  /// `applied(to:)`'s `0...1` clamp actually leaves on that side — `downRoom` is
  /// `color`'s own lightness (the distance to black), `upRoom` is `1` minus it (the
  /// distance to white) — which is why the same drag distance moves the color by a
  /// different amount depending on which half of the track it is in. That is the
  /// point: it is what lets `-1` and `+1` mean "true black" and "true white" for
  /// every base color rather than only the one where the two rooms happen to match.
  ///
  /// **Not mode-dependent**, for the same reason the old range function was not — the
  /// clamp inside `applied(to:)` runs whether or not web-friendly mode is on, so a
  /// track that reached past it would have the identical dead zone either way.
  ///
  /// A base already at black or white leaves one side with *no* room at all, so every
  /// fraction on that half maps to `0` — the honest answer, since there is nowhere
  /// further to go, but note it is a different shape of "clamped" than the far side:
  /// dragging into a zero-room half snaps the reported delta (and so the slider's own
  /// thumb, which reads its position back through ``lightnessFraction(forDelta:for:)``)
  /// straight back to the center rather than letting it settle partway down the track.
  static func lightnessDelta(atFraction fraction: Double, for color: ColorValue) -> Double {
    let lightness = color.oklchComponents.lightness
    let downRoom = lightness
    let upRoom = 1 - lightness
    let clamped = min(max(fraction, lightnessFractionRange.lowerBound), lightnessFractionRange.upperBound)
    return clamped < 0 ? clamped * downRoom : clamped * upRoom
  }

  /// The inverse of ``lightnessDelta(atFraction:for:)`` — where a given delta
  /// currently sits on ``lightnessFractionRange``, so a slider's thumb reflects
  /// `adjustment.lightnessDelta` even though the track's two halves scale
  /// differently. See that method's doc comment for what a zero-room half does here.
  static func lightnessFraction(forDelta delta: Double, for color: ColorValue) -> Double {
    guard delta != 0 else { return 0 }
    let lightness = color.oklchComponents.lightness
    let room = delta < 0 ? lightness : 1 - lightness // downRoom / upRoom, as above
    guard room > 0 else { return 0 }
    return min(max(delta / room, lightnessFractionRange.lowerBound), lightnessFractionRange.upperBound)
  }

  /// The ``chromaScale`` range past which every larger scale clamps to the same
  /// chroma under web-friendly mode — because ``ColorValue/pulledInto(_:)`` pulls
  /// every one of them back to `gamut`'s own boundary chroma regardless of how much
  /// further the scale still climbs — **mirrored about the identity scale (`1`)**, so
  /// a linear slider's own center always means "no change" and its two ends read as
  /// equally far from it. `extent`'s un-narrowed `0...2` already put `×1.00` at the
  /// middle by the same kind of accident that used to put Lightness's `0` at the
  /// middle of a fixed `-0.5...0.5` — an interval picked so the identity sits in the
  /// middle, not a claim about how far the color can honestly go.
  ///
  /// Reducing chroma toward `0` never clamps — it only ever moves a color further
  /// *inside* the gamut — so unlike lightness there is no wall on that side to
  /// discover, only `extent`'s own choice of how much reduction one drag should
  /// cover. That is treated as the fixed quantity to mirror the increase side
  /// against: the real wall, when increasing finds one, gives way to match it.
  ///
  /// **Lightness no longer works this way** — see ``lightnessFractionRange`` — and
  /// this range has the same stranding lightness's did, left in deliberately rather
  /// than defended. Mirroring the reduce side down to match a narrow ceiling costs
  /// real reach: measured for `#3b82f6` under web-friendly mode, the range comes back
  /// `×0.917 ... ×1.083`, so the slider cannot reach `×0` — the user cannot fully
  /// desaturate their own color even though nothing in the gamut stops them. `×0` is
  /// a real destination (fully gray), not the last sliver of an arbitrary `extent`,
  /// which is exactly the argument that retired lightness's mirrored range.
  ///
  /// The fix is the same shape lightness now uses — a fraction track whose `-1` is
  /// `×0` and whose `+1` is the gamut ceiling, two halves scaling independently — and
  /// it is deferred rather than folded in here, because the reported bug was about
  /// Lightness and this changes what a second slider means. Do not read the paragraph
  /// above as a case for keeping the mirroring; it explains the shape, it does not
  /// justify the reach it costs.
  ///
  /// Derived from `color`'s own lightness and hue, **not** the pending adjustment's —
  /// reading the adjusted lightness or hue instead would make dragging the Lightness
  /// or Hue slider silently rescale a Chroma the user already set for a reason of its
  /// own. That leaves this ceiling exact only while Lightness and Hue sit at their
  /// identity and a hair loose once they have moved too, which is the smaller and
  /// more predictable kind of wrong.
  ///
  /// A base already at or past `gamut` — a typed wide-gamut color under web-friendly
  /// mode, say, since the mode hides tools rather than rejecting input — leaves *no*
  /// room to increase at all, the chroma equivalent of a lightness already at black
  /// or white. Mirroring against that zero would collapse the reduce side to a
  /// single point at the very moment it is most worth keeping open, so it is left at
  /// its own full `1 - extent.lowerBound`, unmirrored, with the identity scale
  /// sitting at that range's own edge rather than its center.
  static func chromaScaleRange(
    for color: ColorValue,
    in gamut: ColorSpace,
    extent: ClosedRange<Double> = 0 ... 2,
  ) -> ClosedRange<Double> {
    guard !color.isAchromatic else { return extent }
    let components = color.oklchComponents
    let boundary = GamutBoundary.maxChroma(lightness: components.lightness, hue: components.hue, in: gamut)
    let ceiling = boundary / components.chroma

    let upRoom = min(extent.upperBound - 1, max(0, ceiling - 1))
    let downRoom = 1 - extent.lowerBound
    guard upRoom > 0, downRoom > 0 else {
      return (1 - downRoom) ... (1 + upRoom)
    }
    let room = min(upRoom, downRoom)
    return (1 - room) ... (1 + room)
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
}
