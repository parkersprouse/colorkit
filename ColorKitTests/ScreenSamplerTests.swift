//
//  ScreenSamplerTests.swift
//  ColorKitTests
//

import AppKit
@testable import ColorKit
import Foundation
import Testing

/// Covers the `NSColor` → ``ColorValue`` bridge only. Nothing here calls
/// ``ScreenSampler/sample()``: it puts a loupe on screen and blocks until a human
/// clicks a pixel, which is not a thing a test suite can or should do.
@Suite("Screen sampler")
struct ScreenSamplerTests {
  // MARK: Internal

  /// The regression the bridge exists to prevent, asserted next to the bug itself so
  /// the difference is visible rather than described.
  @Test("A Display P3 color survives the bridge, where the obvious route flattens it")
  func wideGamutSurvivesTheBridge() throws {
    let bridged = try #require(ScreenSampler.colorValue(from: p3Red))

    #expect(bridged.space == .srgbLinear)
    #expect(bridged.exceedsSRGB, "P3 red was flattened into sRGB somewhere in the bridge")

    // What `usingColorSpace(.sRGB)` — the call every naive eyedropper makes —
    // returns for the same color: 1, 0, 0. Indistinguishable from plain sRGB red,
    // with nothing to signal that anything was lost.
    let naive = try #require(p3Red.usingColorSpace(.sRGB))
    #expect(naive.redComponent == 1)
    #expect(naive.greenComponent == 0)
    #expect(naive.blueComponent == 0)
  }

  /// ColorSync converts through the display's ICC profile; CSS Color 4 uses
  /// idealized matrices. They are not the same numbers, so a sampled color is as
  /// exact as the system's color management rather than as exact as arithmetic —
  /// worth measuring rather than assuming.
  @Test("Bridged P3 red matches the reference to within ColorSync's own error")
  func wideGamutMatchesReference() throws {
    let bridged = try #require(ScreenSampler.colorValue(from: p3Red))

    // colorjs.io 0.7.0: new Color('color(display-p3 1 0 0)').to('srgb-linear')
    let reference = ColorValue(
      space: .srgbLinear,
      1.22494017628056,
      -0.04205695470968818,
      -0.01963755459033439,
    )

    // Measured at 3.4e-5 — far under a just-noticeable difference of 0.02, but a
    // thousand times looser than the same-primaries path below, which comes in at
    // 3.3e-8. Crossing primaries is where the display profile and the spec's
    // matrices actually disagree; staying inside them costs only float32.
    #expect(bridged.deltaEOK(to: reference) < 1e-4)
  }

  /// The everyday case: a color authored in sRGB comes back spelled the way it was
  /// written. Same primaries means only the transfer function is involved, and that
  /// part agrees with the reference to eight decimal places.
  @Test("An sRGB color round-trips to the hex it was authored as")
  func srgbRoundTripsExactly() throws {
    let authored = NSColor(srgbRed: 59 / 255, green: 130 / 255, blue: 246 / 255, alpha: 1)
    let bridged = try #require(ScreenSampler.colorValue(from: authored))

    #expect(bridged.cssString(as: .hex) == "#3b82f6")
    #expect(!bridged.exceedsSRGB)
  }

  @Test("Alpha comes through the bridge")
  func alphaSurvives() throws {
    let translucent = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 0.5)
    let bridged = try #require(ScreenSampler.colorValue(from: translucent))

    #expect(abs(bridged.alpha - 0.5) < 1e-6)
  }

  /// Grey has no chroma to lose, so this is the case that would still look right if
  /// the bridge were wrong — which is exactly why it is worth pinning.
  @Test("Neutrals are unchanged", arguments: [0.0, 0.25, 0.5, 1.0])
  func neutralsAreUnchanged(level: Double) throws {
    let grey = NSColor(srgbRed: level, green: level, blue: level, alpha: 1)
    let bridged = try #require(ScreenSampler.colorValue(from: grey))
    let expected = ColorValue(space: .srgb, level, level, level)

    #expect(bridged.deltaEOK(to: expected) < 1e-6)
  }

  // MARK: Private

  private var p3Red: NSColor {
    NSColor(displayP3Red: 1, green: 0, blue: 0, alpha: 1)
  }
}
