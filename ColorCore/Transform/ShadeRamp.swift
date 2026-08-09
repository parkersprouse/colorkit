//
//  ShadeRamp.swift
//  ColorKit
//

import Foundation

/// A Tailwind-shaped tint-and-shade ramp built around one chosen color.
///
/// **The naive version of this is the whole reason the type exists.** Hold chroma
/// constant and walk lightness from dark to light, and both ends fall out of the sRGB
/// gamut — there is no such thing as a very light color with the chroma of a mid-tone,
/// because the gamut pinches to a point at white and at black (see ``GamutBoundary``).
/// A ramp built that way gets silently clipped on the way to the screen, and clipping
/// shifts hue, so the light end drifts and the dark end goes muddy.
///
/// Two rules fix it, and they do different jobs:
///
/// - **Taper chroma toward the ends** (``chromaTaper``). This is the aesthetic rule.
///   Light stops read as *tints* — washes of the color — rather than as the same
///   saturated ink at higher lightness, which is what makes a designed ramp look
///   designed.
/// - **Never exceed the gamut boundary** (``gamut``). This is the correctness rule.
///   The taper alone still leaves the gamut for a saturated base, so each stop is
///   additionally held at or inside the edge — and because the edge comes from
///   ``GamutBoundary``, which bisects the same predicate the badge uses, every stop is
///   in gamut *by construction* rather than by a mapping applied afterwards.
///
/// The clamp is applied only where it is needed: a stop that already fits is passed
/// through untouched, so the chosen color comes back out of its own ramp bit-for-bit
/// rather than nudged by a search step. That is not merely an optimization — clamping
/// unconditionally moves the base off itself by up to one search step, and in an
/// unbounded ``gamut`` it would set every chroma to infinity. Both are pinned by tests.
nonisolated struct ShadeRamp: Sendable, Equatable {
  static let `default` = ShadeRamp()

  /// How many stops, including the base. Forced odd — see ``stopCount(for:)`` — so
  /// there is an exact middle for the chosen color to occupy.
  var stops: Int = 11

  /// OKLCH lightness of the first stop. `0.97` is a near-white tint, matching where
  /// Tailwind's `50` sits.
  var lightest: Double = 0.97

  /// OKLCH lightness of the last stop. `0.18` rather than pure black, because a ramp
  /// ending at black ends at a color with no hue left in it.
  var darkest: Double = 0.18

  /// How much chroma the ends give up, `0` (constant chroma — the naive ramp) to `1`
  /// (fully neutral ends). Falls off with the *square* of the distance from the base,
  /// so the stops nearest the base keep almost all their color and only the extremes
  /// wash out.
  var chromaTaper: Double = 0.5

  /// The gamut every stop is kept inside.
  ///
  /// sRGB by default, which is the honest floor for CSS. Choosing `.displayP3` widens
  /// the ramp for a display that can show it; choosing an unbounded space disables
  /// the clamp entirely and leaves only the taper.
  var gamut: ColorSpace = .srgb

  /// Rounds a requested stop count to something with a middle.
  ///
  /// An even ramp has no center stop, so the chosen color would have to sit slightly
  /// off-center or be dropped from its own ramp. Rounding up is the least surprising
  /// resolution: you asked for ten shades and got eleven, all of them useful.
  static func stopCount(for requested: Int) -> Int {
    let floored = max(requested, 3)
    return floored.isMultiple(of: 2) ? floored + 1 : floored
  }

  /// The ramp, lightest first — the order Tailwind numbers it in, and the order it
  /// reads on screen.
  ///
  /// The base color occupies the exact middle index, unchanged, whenever it fits in
  /// ``gamut``. A base that does *not* fit is pulled to the boundary like every other
  /// stop: the ramp's promise is that every color in it can be displayed, and honoring
  /// that for ten stops but not the eleventh would hand back a set that cannot be used
  /// as one.
  ///
  /// A base lighter than ``lightest`` or darker than ``darkest`` compresses that side
  /// of the ramp rather than extending past the base, so the chosen color is never
  /// somewhere other than the middle. Near either extreme the short side can flatten
  /// to near-duplicates, which is the truth about a near-white color: it has no
  /// lighter tints.
  func generated(from base: ColorValue) -> [ColorValue] {
    let count = Self.stopCount(for: stops)
    let middle = count / 2
    let origin = base.oklchComponents

    let top = max(lightest, origin.lightness)
    let bottom = min(darkest, origin.lightness)
    let taper = min(max(chromaTaper, 0), 1)

    return (0 ..< count).map { index in
      // -1 at the lightest stop, 0 at the base, +1 at the darkest.
      let distance = Double(index - middle) / Double(middle)

      let lightness: Double
      if index < middle {
        lightness = top + (origin.lightness - top) * (Double(index) / Double(middle))
      } else if index == middle {
        lightness = origin.lightness
      } else {
        let travelled = Double(index - middle) / Double(middle)
        lightness = origin.lightness + (bottom - origin.lightness) * travelled
      }

      let tapered = max(origin.chroma * (1 - taper * distance * distance), 0)
      let candidate = OKLCHComponents(
        lightness: lightness,
        chroma: tapered,
        hue: origin.hue,
      )

      // `pulledInto` asks first, and only searches when the answer is no — exact
      // for the common case, where an in-gamut stop is returned untouched rather
      // than moved to within a search step of itself, and it skips ~20 conversions
      // per stop that already fits.
      return base.derivedOKLCH(candidate).pulledInto(gamut)
    }
  }
}
