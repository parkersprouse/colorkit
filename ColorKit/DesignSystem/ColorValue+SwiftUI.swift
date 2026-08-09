//
//  ColorValue+SwiftUI.swift
//  ColorKit
//

import SwiftUI

extension ColorValue {
  /// This color as SwiftUI can draw it.
  ///
  /// Goes through **Display P3**, not sRGB. Every Mac shipped in years has a P3
  /// panel, and routing through sRGB first would clip `color(display-p3 1 0 0)`
  /// down to ordinary red — the app would then be *showing* the user precisely the
  /// inaccuracy it exists to expose.
  ///
  /// Colors beyond P3 are gamut-mapped rather than handed over raw. SwiftUI clamps
  /// out-of-range components per channel, and clamping channels independently
  /// shifts hue; ``ColorValue/gamutMapped(to:)`` gives up chroma instead and keeps
  /// the color recognizable. The swatch's job is to be the closest showable color —
  /// telling the user that a compromise happened is the badge's job, not the
  /// swatch's.
  var displayColor: Color {
    let p3 = convertedAndMapped(to: .displayP3)
    return Color(
      .displayP3,
      red: p3.components.x,
      green: p3.components.y,
      blue: p3.components.z,
      // CSS clamps alpha at used-value time, so `/ 300%` shows as opaque
      // rather than as a rendering artifact.
      opacity: min(max(alpha, 0), 1),
    )
  }

  /// Whether this color needs more gamut than the display can show.
  ///
  /// Distinct from being outside sRGB: an author writing `oklch()` for a P3 site
  /// wants to know when their color exceeds *sRGB*, but the swatch's own fidelity
  /// is limited by P3.
  var exceedsDisplayGamut: Bool {
    !inGamut(of: .displayP3, epsilon: Self.gamutNoiseTolerance)
  }

  /// Whether this color falls outside plain sRGB — the practical question for
  /// anyone writing CSS that has to work everywhere.
  var exceedsSRGB: Bool {
    !inGamut(of: .srgb, epsilon: Self.gamutNoiseTolerance)
  }
}
