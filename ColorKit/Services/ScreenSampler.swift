//
//  ScreenSampler.swift
//  ColorKit
//

import AppKit

/// Reads a color off the screen — the pixel's actual color, not a clipped copy of it.
///
/// This file exists because of one call: `NSColor.usingColorSpace(.sRGB)`. Handed
/// Display P3 red it returns `1, 0, 0` — byte-identical to ordinary sRGB red. Two
/// visibly different colors collapse into one answer, silently, with no error to
/// notice. That is why most eyedroppers on a modern Mac quietly lie about anything
/// vivid, and it is the single thing this app must not do.
///
/// Colors are read into **linear extended sRGB** instead: sRGB primaries, no transfer
/// function, and components free to leave `0…1`. Nothing is clipped, there is no
/// question of how a transfer function behaves below zero, and it lands directly on a
/// space ColorCore already has — ``ColorSpace/srgbLinear``.
enum ScreenSampler {
  // MARK: Internal

  /// Shows the loupe and waits for a pixel, or `nil` if the user cancels.
  static func sample() async -> ColorValue? {
    // Re-entrancy would leave two loupes fighting over the same click.
    guard active == nil else { return nil }

    let sampler = NSColorSampler()
    active = sampler
    defer { active = nil }

    return await withCheckedContinuation { continuation in
      sampler.show { nsColor in
        // Bridged here rather than after the `await`, so the value crossing
        // the continuation is `ColorValue` — which is `Sendable` — instead of
        // an `NSColor`, which is a class AppKit makes no such promise about.
        continuation.resume(returning: nsColor.flatMap(colorValue(from:)))
      }
    }
  }

  // MARK: - Bridge

  /// An AppKit color as a ``ColorValue``, without discarding anything the display
  /// can show.
  ///
  /// Pure and `nonisolated` on purpose: this is the part worth testing, and a
  /// `@MainActor` bridge would drag every test that touches it onto the main actor.
  ///
  /// - Note: A sampled color is as exact as the system's color management, not as
  ///   exact as arithmetic, and the two ways it falls short differ by a thousandfold.
  ///   Measured against colorjs.io 0.7.0:
  ///
  ///   - **Same primaries** (sRGB → linear sRGB): ΔEOK 3.3e-8. This is ColorSync's
  ///     float32 pipeline showing through — the components differ by 1.1e-7 at a
  ///     value of 0.92, which is exactly one `Float` ulp there. Nothing else is lost.
  ///   - **Across primaries** (P3 → sRGB): ΔEOK 3.4e-5, from the display profile's
  ///     primaries not matching CSS Color 4's idealized matrices.
  ///
  ///   Both sit far under a just-noticeable difference of 0.02, but neither is zero,
  ///   so tests here assert a tolerance rather than equality.
  nonisolated static func colorValue(from nsColor: NSColor) -> ColorValue? {
    for (nsSpace, space) in readingSpaces {
      guard let nsSpace, let converted = nsColor.usingColorSpace(nsSpace) else { continue }
      guard converted.numberOfComponents >= 4 else { continue }

      var components = [CGFloat](repeating: 0, count: converted.numberOfComponents)
      converted.getComponents(&components)
      return ColorValue(
        space: space,
        Double(components[0]),
        Double(components[1]),
        Double(components[2]),
        alpha: Double(components[3]),
      )
    }
    return nil
  }

  // MARK: Private

  /// Whether a sample is already in progress.
  ///
  /// Doubles as the strong reference `NSColorSampler` needs. The loupe is driven by
  /// the sampler object, not by AppKit, so letting it deallocate while the user is
  /// still choosing a pixel dismisses the loupe out from under them.
  private static var active: NSColorSampler?

  /// Spaces to try, in order, each paired with its ColorCore counterpart.
  ///
  /// Both preserve out-of-range components, which is the whole requirement — there
  /// is deliberately no `.sRGB` last resort, because succeeding with a clipped
  /// answer is worse than failing with none. A wrong color that looks right is the
  /// failure mode this app is built to eliminate.
  private nonisolated static var readingSpaces: [(NSColorSpace?, ColorSpace)] {
    [
      (CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        .flatMap(NSColorSpace.init(cgColorSpace:)), .srgbLinear),
      (NSColorSpace.extendedSRGB, .srgb),
    ]
  }
}
