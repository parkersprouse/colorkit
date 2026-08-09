//
//  Harmony.swift
//  ColorKit
//

import Foundation

/// Classic color-wheel relationships, measured on OKLCH's wheel rather than the
/// painter's one.
///
/// The angles below are the traditional ones — 180° for a complement, 120° for a triad
/// — but *which* wheel they are turned on changes the answer completely. Rotate 180° in
/// HSL and the "complement" of a saturated blue comes back a dim mustard, because HSL's
/// hue is a raw RGB angle in which equal degrees are wildly unequal steps. OKLCH's hue
/// is perceptually spaced, so the same 180° lands where the eye expects it and the two
/// colors keep the same apparent lightness.
///
/// Members are returned **exactly as the rotation produces them**, not mapped into any
/// gamut. Rotating a vivid color's hue routinely leaves sRGB — the gamut is far from a
/// cylinder, so a chroma that fits at one hue may not fit at another — and quietly
/// pulling those results in would hand back a "complement" that is not the complement.
/// The value stays honest and the app's existing gamut badge does what it is there for.
/// The one place this app *does* pull colors in is ``ShadeRamp``, and for a reason
/// spelled out there: a ramp is a set built to be used together, where a harmony is a
/// question about where a hue's relatives sit.
nonisolated enum Harmony: String, CaseIterable, Sendable, Hashable, Identifiable {
  /// The hue directly opposite.
  case complementary
  /// The two hues either side of the complement — the complement's contrast without
  /// its harshness.
  case splitComplementary = "split-complementary"
  /// Three hues evenly spaced around the wheel.
  case triad
  /// Four hues evenly spaced: two complementary pairs.
  case tetrad
  /// Immediate neighbours, at a configurable spread.
  case analogous
  /// One hue, many lightnesses. The odd one out — see ``members(of:options:)``.
  case monochromatic

  // MARK: Internal

  var id: String {
    rawValue
  }

  /// Hue rotations from the base, in degrees and in display order, or `nil` for the
  /// harmony that is not about hue at all.
  ///
  /// Analogous is the only one that does not lead with the base: its members read as
  /// a neighbourhood, and showing the middle of that neighbourhood first would break
  /// the sequence for no gain. ``baseIndex(options:)`` is how a caller finds the
  /// user's own color in the result.
  func hueOffsets(options: HarmonyOptions = .default) -> [Double]? {
    switch self {
    case .complementary: [0, 180]
    case .splitComplementary: [0, 150, 210]
    case .triad: [0, 120, 240]
    case .tetrad: [0, 90, 180, 270]
    case .analogous: [-options.analogousSpread, 0, options.analogousSpread]
    case .monochromatic: nil
    }
  }

  /// Where the base color sits in this harmony's output, so a panel can mark it
  /// without comparing floats.
  func baseIndex(options: HarmonyOptions = .default) -> Int {
    guard let offsets = hueOffsets(options: options) else {
      // Monochromatic is a ramp, and a ramp's base is its middle stop.
      return ShadeRamp.stopCount(for: options.monochromaticStops) / 2
    }
    return offsets.firstIndex(of: 0) ?? 0
  }

  /// How many colors this harmony produces.
  func count(options: HarmonyOptions = .default) -> Int {
    hueOffsets(options: options)?.count
      ?? ShadeRamp.stopCount(for: options.monochromaticStops)
  }
}

/// The knobs a harmony takes, kept in one value so every call site does not grow a
/// parameter list.
nonisolated struct HarmonyOptions: Sendable, Equatable {
  static let `default` = HarmonyOptions()

  /// Degrees either side of the base for ``Harmony/analogous``. 30° is the
  /// conventional spread — wide enough to read as three colors, narrow enough to
  /// still read as one family.
  var analogousSpread: Double = 30

  /// Stops in a ``Harmony/monochromatic`` set. Fewer than a full ``ShadeRamp``,
  /// because this one sits in a row beside the other harmonies and has to stay
  /// comparable to a triad rather than dominate them.
  var monochromaticStops: Int = 5

  /// When set, every member is pulled inside this gamut before being returned.
  ///
  /// `nil` by default — a harmony is normally returned exactly as the rotation
  /// produces it, honestly reporting when a vivid hue leaves sRGB, and the app's
  /// gamut badge is what says so. Set to `.srgb` under ``ColorStore/webFriendly``
  /// (M22), where a tool that cannot stay in sRGB is recalibrated rather than left to
  /// escape it.
  var gamut: ColorSpace?
}

nonisolated extension ColorValue {
  /// This color's relatives under `harmony`.
  ///
  /// Hue-based harmonies keep lightness and chroma untouched and turn only the hue,
  /// which is the point: the members differ in exactly one dimension, so they read as
  /// a family. Monochromatic inverts that — one hue, lightness varying — and is
  /// therefore delegated to ``ShadeRamp``, which already knows the two things a
  /// lightness family needs (taper the chroma, respect the gamut) and would otherwise
  /// be reimplemented worse here.
  ///
  /// **A gray has no hue**, so every hue-based harmony of one returns the same gray
  /// repeated. That is the arithmetic being honest rather than a special case worth
  /// suppressing: there is no third color related to `#808080` by 120°. Callers that
  /// want to say so can ask ``isAchromatic`` first.
  func harmony(_ harmony: Harmony, options: HarmonyOptions = .default) -> [ColorValue] {
    guard let offsets = harmony.hueOffsets(options: options) else {
      var ramp = ShadeRamp.default
      ramp.stops = options.monochromaticStops
      if let gamut = options.gamut {
        ramp.gamut = gamut
      }
      return ramp.generated(from: self)
    }

    let origin = oklchComponents
    return offsets.map { offset in
      let member = derivedOKLCH(
        OKLCHComponents(
          lightness: origin.lightness,
          chroma: origin.chroma,
          hue: origin.hue + offset,
        ),
      )
      return options.gamut.map(member.pulledInto) ?? member
    }
  }
}
