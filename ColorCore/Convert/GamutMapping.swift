//
//  GamutMapping.swift
//  ColorKit
//

import Foundation

nonisolated extension ColorValue {
  /// Perceptual color difference — Euclidean distance in OKLab.
  ///
  /// Roughly 0.02 is one just-noticeable difference, which is why that value
  /// anchors the gamut-mapping search below.
  func deltaEOK(to other: ColorValue) -> Double {
    let a = converted(to: .oklab).components
    let b = other.converted(to: .oklab).components
    let d = a - b
    return (d.x * d.x + d.y * d.y + d.z * d.z).squareRoot()
  }

  /// Whether this color fits inside `space`'s gamut.
  ///
  /// Unbounded spaces (Lab, OKLab, XYZ and their polar forms) always return true —
  /// they have no gamut to fall outside of.
  func inGamut(of space: ColorSpace, epsilon: Double = 0) -> Bool {
    guard let basis = space.rgbBasis else { return true }
    let rgb = converted(to: basis).components
    for i in 0 ..< 3 where rgb[i] < -epsilon || rgb[i] > 1 + epsilon {
      return false
    }
    return true
  }

  /// Whether this color fits inside its own space's gamut.
  var isInGamut: Bool {
    inGamut(of: space)
  }

  /// Whether this color is a neutral gray, making any hue component powerless.
  ///
  /// Worth asking before *displaying* a hue: converting a gray into HSL or OKLCH
  /// yields a hue derived from last-ULP differences between channels that are
  /// meant to be equal. The number is real but meaningless, and showing
  /// `hsl(330 0% 52.5%)` invites the user to read significance into noise.
  /// CSS Color 4 calls such components "powerless" and serializes them as `none`.
  var isAchromatic: Bool {
    let oklab = converted(to: .oklab).components
    guard let epsilon = ColorSpace.oklch.polarEpsilon else { return false }
    return abs(oklab.y) < epsilon && abs(oklab.z) < epsilon
  }

  /// This color with powerless components flagged, ready for honest serialization.
  func markingPowerlessComponents() -> ColorValue {
    guard let hueIndex = space.hueIndex, isAchromatic else { return self }
    var result = self
    result.missing.insert(.component(hueIndex))
    result.components[hueIndex] = 0
    return result
  }

  /// Clamps each channel into `space`'s gamut, ignoring perceptual cost.
  ///
  /// Fast and predictable, but hue-shifting on saturated colors. Used as the inner
  /// step of `gamutMapped(to:)` rather than as a user-facing operation.
  func clipped(to space: ColorSpace) -> ColorValue {
    guard let basis = space.rgbBasis else { return converted(to: space) }
    var rgb = converted(to: basis)
    for i in 0 ..< 3 {
      rgb.components[i] = min(max(rgb.components[i], 0), 1)
    }
    return rgb.converted(to: space)
  }

  /// Brings this color into `space`'s gamut using the CSS Color 4 §13 algorithm.
  ///
  /// Reduces OKLCH chroma by binary search, comparing each candidate against its
  /// clipped self and stopping once the difference falls under one JND. This keeps
  /// lightness and hue intact and sacrifices only saturation — the reason a
  /// gamut-mapped `oklch()` still looks like the color you asked for, where naive
  /// clipping would shift its hue.
  func gamutMapped(to space: ColorSpace) -> ColorValue {
    let jnd = 0.02
    let epsilon = 0.0001

    guard !space.isUnbounded else { return converted(to: space) }

    let originOKLCH = converted(to: .oklch)
    let lightness = originOKLCH.components.x

    // Past the ends of the lightness range there is nothing to search for.
    if lightness >= 1 {
      var white = ColorValue(space: .oklab, 1, 0, 0, alpha: alpha).converted(to: space)
      white.alpha = alpha
      return white
    }
    if lightness <= 0 {
      var black = ColorValue(space: .oklab, 0, 0, 0, alpha: alpha).converted(to: space)
      black.alpha = alpha
      return black
    }

    if originOKLCH.inGamut(of: space) {
      return originOKLCH.converted(to: space)
    }

    var low = 0.0
    var high = originOKLCH.components.y // chroma
    var lowIsInGamut = true
    var current = originOKLCH
    var clipped = current.clipped(to: space)

    var difference = clipped.deltaEOK(to: current)
    if difference < jnd {
      return clipped
    }

    while high - low > epsilon {
      let chroma = (low + high) / 2
      current.components.y = chroma

      if lowIsInGamut, current.inGamut(of: space) {
        low = chroma
      } else {
        clipped = current.clipped(to: space)
        difference = clipped.deltaEOK(to: current)

        if difference < jnd {
          // Close enough that further searching cannot help.
          if jnd - difference < epsilon {
            break
          }
          // The clipped result is acceptable but not optimal — keep
          // searching upward, and stop trusting plain in-gamut tests.
          lowIsInGamut = false
          low = chroma
        } else {
          high = chroma
        }
      }
    }

    return clipped
  }

  /// Convenience: converts to `space`, gamut-mapping only when needed.
  func convertedAndMapped(to space: ColorSpace) -> ColorValue {
    let direct = converted(to: space)
    return direct.isInGamut ? direct : gamutMapped(to: space)
  }
}
