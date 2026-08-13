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

  /// The Chroma slider's fixed, color-independent track, the exact counterpart of
  /// ``lightnessFractionRange``: `-1` is always `×0` (fully gray), `0` is always the
  /// identity scale (`×1`), and `+1` is always as saturated as this color can get.
  ///
  /// This replaced a `chromaScaleRange` that reported a range of *scales* mirrored
  /// about `×1`, and it went for the reason lightness's mirrored range went. Mirroring
  /// caps the more open side down to match the tighter one, and under web-friendly
  /// mode the ceiling is often very tight: measured for `#3b82f6`, the mirrored range
  /// came back `×0.917 ... ×1.083`, so the slider could not reach `×0` at all. Fully
  /// gray is a real destination, not the last sliver of an arbitrary interval, and
  /// stranding it is the same bug that retired lightness's version.
  static let chromaFractionRange: ClosedRange<Double> = -1 ... 1

  /// Converts a position on ``chromaFractionRange`` to the ``chromaScale`` it stands
  /// for, given how much room `color` has left inside `gamut`.
  ///
  /// The two halves scale independently, as lightness's do, but against *differently
  /// shaped* rooms — chroma's operator is a multiplier, not an addend, so this is a
  /// counterpart rather than a copy:
  ///
  /// - **Down is always `1`.** `×0` is a true wall (nothing is less saturated than
  ///   gray) and reducing chroma never clamps, since it only ever moves a color
  ///   further *inside* the gamut. So `-1` maps to `×0` for every color, always.
  /// - **Up is `min(ceiling, maxScale) - 1`**, where `ceiling` is
  ///   ``GamutBoundary/maxChroma`` divided by `color`'s own chroma.
  ///
  /// `gamut` is optional because chroma's increase side, unlike lightness's, has no
  /// wall at all when nothing is clamping: pass `nil` (web-friendly mode off) and the
  /// ceiling is unbounded, so `upRoom` falls back to `maxScale - 1`. With the default
  /// `maxScale` that makes the whole track map onto exactly `×0 ... ×2` — **identical
  /// to the fixed range this slider used before any of the M35 work**, which is what
  /// keeps this change scoped to web-friendly mode rather than quietly redefining a
  /// control everyone else was happy with.
  ///
  /// **`maxScale` is not decoration, and dropping it makes the slider unusable.**
  /// `ceiling` is a *ratio*, so a nearly-neutral color has an enormous one — measured
  /// at chroma `0.001`, the sRGB ceiling is `×141.5`. Letting `+1` mean that would
  /// squeeze the entire useful `×1`–`×2` span into the first 0.7% of the track's right
  /// half. Lightness needs no such cap because its two rooms sum to `1` by
  /// construction and neither can run away from the other.
  ///
  /// Derived from `color`'s own lightness and hue, **not** the pending adjustment's —
  /// reading the adjusted lightness or hue instead would make dragging the Lightness
  /// or Hue slider silently rescale a Chroma the user already set for a reason of its
  /// own. That leaves this ceiling exact only while Lightness and Hue sit at their
  /// identity and a hair loose once they have moved too, which is the smaller and
  /// more predictable kind of wrong.
  ///
  /// A base at or past `gamut`'s edge gets `upRoom == 0`, so the whole increase half
  /// maps to `×1` — and here that is **protective, not merely honest**. Measured after
  /// the `pulledInto` guard fix: pure blue holds its chroma of `0.31321` at `×1.000`
  /// and drops to `0.26553` at `×1.001`, a 15.2% fall that then stays flat. Blue's own
  /// chroma sits past sRGB's *first* exit (the disconnected ray ``GamutBoundary``
  /// documents), so the first nudge rightward would not be a small increase but a
  /// cliff. A dead half of the track is the right answer to a cliff.
  static func chromaScale(
    atFraction fraction: Double,
    for color: ColorValue,
    in gamut: ColorSpace?,
    maxScale: Double = 2,
  ) -> Double {
    let clamped = min(max(fraction, chromaFractionRange.lowerBound), chromaFractionRange.upperBound)
    guard clamped != 0 else { return 1 }
    // Down is the same wall for every color, so the reduce half needs no gamut at all.
    guard clamped > 0 else { return 1 + clamped }
    return 1 + clamped * chromaUpRoom(for: color, in: gamut, maxScale: maxScale)
  }

  /// The inverse of ``chromaScale(atFraction:for:in:maxScale:)`` — where a given scale
  /// sits on ``chromaFractionRange``, so the slider's thumb reflects
  /// `adjustment.chromaScale` even though the track's two halves scale differently.
  /// A scale above a zero-room ceiling reports `0`, the same snap-to-center a walled
  /// lightness half has.
  static func chromaFraction(
    forScale scale: Double,
    for color: ColorValue,
    in gamut: ColorSpace?,
    maxScale: Double = 2,
  ) -> Double {
    guard scale != 1 else { return 0 }
    guard scale > 1 else { return max(scale - 1, chromaFractionRange.lowerBound) }
    let upRoom = chromaUpRoom(for: color, in: gamut, maxScale: maxScale)
    guard upRoom > 0 else { return 0 }
    return min((scale - 1) / upRoom, chromaFractionRange.upperBound)
  }

  /// How much *more* than `×1` the increase half of the chroma track is worth — the
  /// one place the ceiling is derived, so the two conversions above cannot come to
  /// disagree about where the right end of the slider is.
  private static func chromaUpRoom(
    for color: ColorValue,
    in gamut: ColorSpace?,
    maxScale: Double,
  ) -> Double {
    let headroom = maxScale - 1
    // A gray has no chroma to scale, so there is no ratio to take — the guard is
    // `isAchromatic` rather than a `chroma > 0` test of its own, matching how
    // ``TransformPanel``'s harmony section already asks this question.
    guard let gamut, !color.isAchromatic else { return headroom }
    let components = color.oklchComponents
    let boundary = GamutBoundary.maxChroma(lightness: components.lightness, hue: components.hue, in: gamut)
    return min(headroom, max(0, boundary / components.chroma - 1))
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
