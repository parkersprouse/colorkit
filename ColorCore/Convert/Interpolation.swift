//
//  Interpolation.swift
//  ColorKit
//

import Foundation

// MARK: - Hue arcs

/// Which way round the wheel a polar interpolation travels.
///
/// Two hues describe two arcs, not one, and nothing about the numbers says which is
/// meant: 20° and 340° are 40° apart the short way and 320° apart the long way. CSS
/// makes the choice explicit rather than picking for you, and the four spellings are
/// the ones ``ColorInterpolation`` accepts after `in oklch` and friends.
///
/// The fixup is stated on the *pair of angles*, not on the interpolation, which is
/// what makes it testable on its own: each case returns the two endpoints of the arc
/// it wants, and the interpolation that follows is an ordinary lerp between them.
/// Endpoints may therefore leave `[0, 360)` — that is the mechanism, not a bug, and
/// the result is constrained once at the end.
nonisolated enum HueInterpolationMethod: String, CaseIterable, Sendable, Hashable, Identifiable {
  /// The shorter of the two arcs. CSS's default, and the one that reads as "between
  /// these colors" rather than "around the wheel".
  case shorter
  /// The longer arc — deliberately the scenic route, which is how you get a mix that
  /// passes through hues neither endpoint contains.
  case longer
  /// Always counter-clockwise-to-clockwise in increasing degrees, whatever the
  /// endpoints are.
  case increasing
  /// The same, in the other direction.
  case decreasing

  // MARK: Internal

  var id: String {
    rawValue
  }

  /// The two angles to interpolate between, per CSS Color 4 §12.4.
  ///
  /// Both inputs are constrained to `[0, 360)` first, because the rules are stated in
  /// terms of a difference that only means anything once they are — an unconstrained
  /// 720° would otherwise read as "already the long way round".
  func arc(from start: Double, to end: Double) -> (Double, Double) {
    let first = Conversion.constrainAngle(start)
    let second = Conversion.constrainAngle(end)
    let difference = second - first

    switch self {
    case .shorter:
      if difference > 180 {
        return (first + 360, second)
      }
      if difference < -180 {
        return (first, second + 360)
      }
      return (first, second)

    case .longer:
      guard difference > -180, difference < 180 else { return (first, second) }
      // Equal hues take this branch too, and should: the long arc between a hue and
      // itself is the whole wheel, which is what `longer` asks for.
      return difference > 0 ? (first + 360, second) : (first, second + 360)

    case .increasing:
      return difference < 0 ? (first, second + 360) : (first, second)

    case .decreasing:
      return difference > 0 ? (first + 360, second) : (first, second)
    }
  }
}

// MARK: - How much of each color

/// What `color-mix()`'s two percentages resolve to: one position along the mix, and
/// what happens to the result's alpha.
///
/// The second half is the part that surprises people, and it is the spec's rule
/// rather than a flourish: percentages that sum to *less* than 100% do not merely
/// re-normalize, they make the result correspondingly transparent. So
/// `color-mix(in srgb, red 20%, blue 20%)` is an even mix at 40% alpha, while
/// `red 80%, blue 80%` is the same even mix, opaque. A sum over 100% only scales.
nonisolated struct MixWeights: Sendable, Hashable {
  // MARK: Lifecycle

  /// Resolves the two written percentages, each `nil` when it was omitted.
  ///
  /// - Returns: `nil` when both percentages are `0%`, which the spec calls invalid —
  ///   there is no color at either end to return and no honest way to pick one.
  init?(first: Double?, second: Double?) {
    let p1: Double
    let p2: Double
    if let first, let second {
      p1 = first
      p2 = second
    } else if let first {
      // One written percentage decides both: the other is what is left of 100%.
      p1 = first
      p2 = 100 - first
    } else if let second {
      p1 = 100 - second
      p2 = second
    } else {
      // Omit both and you mean half and half.
      p1 = 50
      p2 = 50
    }

    let sum = p1 + p2
    guard sum > 0 else { return nil }

    progress = p2 / sum
    // Only a shortfall reaches the alpha. Scaling *up* would make a color more
    // opaque than either input, which nothing in the spec asks for.
    alphaMultiplier = sum < 100 ? sum / 100 : 1
  }

  private init(progress: Double, alphaMultiplier: Double) {
    self.progress = progress
    self.alphaMultiplier = alphaMultiplier
  }

  // MARK: Internal

  /// Half of each, opaque — what both percentages omitted resolves to.
  static let even = MixWeights(progress: 0.5, alphaMultiplier: 1)

  /// How far along the mix the result sits, `0` being the first color.
  let progress: Double

  /// What the result's alpha is multiplied by. `1` unless the written percentages
  /// summed to under 100%.
  let alphaMultiplier: Double
}

// MARK: - Interpolation

/// CSS's `<color-interpolation-method>`: a space to interpolate in, and — where that
/// space has a hue — which way round the wheel to go.
///
/// The space is the whole substance of the choice. Mixing white and blue in `srgb`
/// runs through a washed-out periwinkle; the same mix in `oklch` keeps its chroma and
/// reads as the same blue getting lighter. Neither is more correct, which is exactly
/// why CSS makes it a required part of the syntax rather than a default.
///
/// Nothing here gamut-maps. A mix in a bounded space can land outside that space's
/// gamut — mix a Display P3 green with black `in srgb` and the result has a negative
/// red channel — and CSS Color 4 §12 has no mapping step, so neither does this. The
/// app's "outside sRGB" badge is what reports it. Note that this is one of the two
/// places the reference implementation answers a *different* question; see
/// `Tools/generate-mix-fixtures.mjs`.
nonisolated struct ColorInterpolation: Sendable, Hashable {
  // MARK: Lifecycle

  init(space: ColorSpace, hue: HueInterpolationMethod = .shorter) {
    self.space = space
    self.hue = hue
  }

  // MARK: Internal

  var space: ColorSpace
  /// Ignored by spaces with no hue, where CSS also forbids writing one down.
  var hue: HueInterpolationMethod

  /// The `color-mix()` of two colors: interpolate, then apply the alpha shortfall.
  ///
  /// The multiplier is skipped on a result whose alpha is *missing*, because there is
  /// no value there to scale — a missing alpha takes the other color's at the point
  /// of use, and scaling the placeholder underneath it would invent a number the
  /// serializer prints as `none` anyway.
  func mix(
    _ first: ColorValue,
    _ second: ColorValue,
    weights: MixWeights = .even,
  ) -> ColorValue {
    var mixed = interpolated(from: first, to: second, at: weights.progress)
    if !mixed.missing.contains(.alpha) {
      mixed.alpha *= weights.alphaMultiplier
    }
    return mixed
  }

  /// The color `progress` of the way from `first` to `second`, in this method's space.
  ///
  /// The order of operations is the specification's, and every step of it is load
  /// bearing:
  ///
  /// 1. **Convert with carry-forward**, not with plain ``ColorValue/converted(to:)`` —
  ///    CSS Color 4 §13.2, which is what makes `hsl(none 50% 50%)` still hueless once
  ///    it reaches OKLCH.
  /// 2. **Then** mark whatever is powerless in the destination space as missing too.
  ///    In that order and never the reverse — see M12 — but it does have to happen,
  ///    and it is the step whose absence is most visible: a gray's hue is noise, so
  ///    mixing white into blue `in oklch` with white's hue taken literally as 0°
  ///    averages 0° and 264° into 132° and returns a **green**. Treating it as
  ///    missing gives the light blue anyone would expect.
  /// 3. **Substitute missing components**, each taking the other color's value, so a
  ///    component missing on one side interpolates as though it had always agreed.
  ///    A component missing on *both* stays missing in the result.
  /// 4. **Fix up the hue arc** — after substitution, because a hue that has just
  ///    borrowed the other's value must not then be arced against it.
  /// 5. **Premultiply by alpha**, interpolate, un-premultiply. This is what stops a
  ///    transparent red mixed with an opaque blue from passing through a color that
  ///    is 50% red-you-cannot-see.
  func interpolated(
    from first: ColorValue,
    to second: ColorValue,
    at progress: Double,
  ) -> ColorValue {
    var start = first.convertedForInterpolation(to: space).markingPowerlessComponents()
    var end = second.convertedForInterpolation(to: space).markingPowerlessComponents()

    // Only what is absent from *both* sides survives into the result.
    let absent = start.missing.intersection(end.missing)

    for index in 0 ..< 3 {
      let slot = ComponentMask.component(index)
      if start.missing.contains(slot), !end.missing.contains(slot) {
        start[index] = end[index]
      } else if end.missing.contains(slot), !start.missing.contains(slot) {
        end[index] = start[index]
      }
    }
    if start.missing.contains(.alpha), !end.missing.contains(.alpha) {
      start.alpha = end.alpha
    } else if end.missing.contains(.alpha), !start.missing.contains(.alpha) {
      end.alpha = start.alpha
    }

    // Absent on both sides there is no arc to take — and `longer` would otherwise
    // turn two zeros into a half-turn stored underneath a flag that says the value
    // is not there.
    if let hueIndex = space.hueIndex, !absent.contains(.component(hueIndex)) {
      let (startHue, endHue) = hue.arc(from: start[hueIndex], to: end[hueIndex])
      start[hueIndex] = startHue
      end[hueIndex] = endHue
    }

    let startComponents = premultiplied(start, leaving: absent)
    let endComponents = premultiplied(end, leaving: absent)

    var components = SIMD3<Double>()
    for index in 0 ..< 3 {
      components[index] = lerp(startComponents[index], endComponents[index], progress)
    }
    let alpha = lerp(start.alpha, end.alpha, progress)

    // Un-premultiplying is the same operation divided rather than multiplied, and it
    // is skipped in the two cases where it has nothing to undo: a missing alpha was
    // never premultiplied, and a zero one multiplied everything to zero with no way
    // back — dividing there is a NaN, not a recovery.
    if !absent.contains(.alpha), alpha != 0 {
      for index in 0 ..< 3 where !isHeldConstant(index, in: absent) {
        components[index] /= alpha
      }
    }

    if let hueIndex = space.hueIndex {
      // The arc did its work during the lerp; past that a hue of 400° is just 40°,
      // and every other producer of a `ColorValue` in this app hands back a
      // constrained one.
      components[hueIndex] = Conversion.constrainAngle(components[hueIndex])
    }

    return ColorValue(space: space, components: components, alpha: alpha, missing: absent)
  }

  // MARK: Private

  /// Components multiplied by their own alpha, per CSS Color 4 §12.3.
  ///
  /// A hue is never premultiplied — it is an angle, and scaling an angle by opacity
  /// is meaningless. Neither is a component missing on both sides: there is no value
  /// there, and the result keeps the flag rather than whatever arithmetic fell out.
  ///
  /// Every exemption here is stated against `absent` — what is missing on **both**
  /// sides — and never against this color's own `missing`, alpha included. Substitution
  /// has already run by this point, so a one-sided `none` alpha *has* the other color's
  /// value and has to scale by it like any other: both ends then premultiply by the same
  /// number and it cancels, which is why the reference answers such a mix with the plain
  /// average. Consulting the flag skips the scaling on one side only and then divides
  /// the other side's components by an alpha they never gained — `rgb(255 0 0 / none)`
  /// mixed with `rgb(0 0 255 / 0.25)` comes back at 200% red. It is also, on its face,
  /// not symmetric: it would make an even mix depend on the order of its operands.
  private func premultiplied(_ color: ColorValue, leaving absent: ComponentMask) -> SIMD3<Double> {
    guard !absent.contains(.alpha) else { return color.components }

    var components = color.components
    for index in 0 ..< 3 where !isHeldConstant(index, in: absent) {
      components[index] *= color.alpha
    }
    return components
  }

  /// Whether premultiplication must leave this component alone.
  private func isHeldConstant(_ index: Int, in absent: ComponentMask) -> Bool {
    index == space.hueIndex || absent.contains(.component(index))
  }

  private func lerp(_ start: Double, _ end: Double, _ progress: Double) -> Double {
    start + (end - start) * progress
  }
}

// MARK: - Convenience

nonisolated extension ColorValue {
  /// This color mixed with `other`, both converted into `interpolation`'s space.
  ///
  /// The plain half-and-half spelling of ``ColorInterpolation/mix(_:_:weights:)``,
  /// for callers with a position rather than a pair of percentages — a panel with a
  /// slider on it, mostly. `at: 0` is this color and `at: 1` is `other`.
  func mixed(
    with other: ColorValue,
    using interpolation: ColorInterpolation,
    at progress: Double = 0.5,
  ) -> ColorValue {
    interpolation.interpolated(from: self, to: other, at: progress)
  }
}
