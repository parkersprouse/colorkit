//
//  HSVTests.swift
//  ColorKitTests
//

@testable import ColorKit
import Foundation
import Testing

/// HSV is the one coordinate in this app with no CSS spelling, so it has no fixture
/// and no parser test standing behind it. These cover it directly.
@Suite("HSV coordinates")
struct HSVTests {
  // MARK: - Anchors

  /// Values from colorjs.io, which carries `hsv` as a non-CSS space.
  @Test(
    "Known colors land on known coordinates",
    arguments: [
      ("#ff0000", 0.0, 100.0, 100.0),
      ("#3b82f6", 217.219251, 76.016260, 96.470588),
    ],
  )
  func knownCoordinates(css: String, hue: Double, saturation: Double, value: Double) throws {
    let hsv = try CSSColorParser.parse(css).color.hsvComponents

    #expect(abs(hsv.hue - hue) < 1e-4)
    #expect(abs(hsv.saturation - saturation) < 1e-4)
    #expect(abs(hsv.value - value) < 1e-4)
  }

  // MARK: - Round trips

  /// The picker writes a coordinate and reads it back on the next frame, so any
  /// drift here would show up as a cursor that walks while nobody is touching it.
  @Test("Coordinates survive a round trip through sRGB")
  func roundTripIsStable() {
    for hueStep in 0 ..< 24 {
      for saturationStep in 1 ... 10 {
        for valueStep in 1 ... 10 {
          let original = HSVComponents(
            hue: Double(hueStep) * 15,
            saturation: Double(saturationStep) * 10,
            value: Double(valueStep) * 10,
          )
          let returned = ColorValue(hsv: original).hsvComponents

          #expect(abs(returned.hue - original.hue) < 1e-9, "hue \(original)")
          #expect(abs(returned.saturation - original.saturation) < 1e-9, "saturation \(original)")
          #expect(abs(returned.value - original.value) < 1e-9, "value \(original)")
        }
      }
    }
  }

  /// Hue is normalized on the way in, so a picker that accumulates drag deltas past a
  /// full turn does not produce a coordinate nothing else will accept.
  @Test("Hue wraps rather than running away", arguments: [(-30.0, 330.0), (390.0, 30.0), (720.0, 0.0)])
  func hueIsNormalized(input: Double, expected: Double) {
    let hsv = HSVComponents(hue: input, saturation: 50, value: 50)
    #expect(abs(hsv.hue - expected) < 1e-9)
  }

  // MARK: - Powerless hue

  /// Gray has no hue, and this returns `0` for it rather than `none`.
  ///
  /// A deliberate difference from colorjs.io, which reports `null`. Neither is wrong
  /// — the number is meaningless either way — but a *picker* must not adopt it: the
  /// classic bug is dragging saturation down to zero and watching the hue strip snap
  /// to red, then dragging back up in a color you never chose. The panel keeps the
  /// hue the user set; this getter is only consulted when a color arrives from
  /// somewhere else.
  @Test("An achromatic color reports a meaningless hue", arguments: ["#ffffff", "#808080", "#000000"])
  func grayHasNoUsefulHue(css: String) throws {
    let hsv = try CSSColorParser.parse(css).color.hsvComponents

    #expect(hsv.saturation == 0)
    #expect(hsv.hue == 0)
  }

  // MARK: - Wide colors

  /// HSV describes the sRGB cube, so a wider color has to come into it somehow —
  /// and *how* is the whole argument of this app.
  ///
  /// The last assertion is the one that matters: clipping Display P3 red would give
  /// exactly `#ff0000`, so a difference from pure red is proof the §13 map ran. The
  /// measured gap is 0.0035 ΔEOK, small in absolute terms and infinitely larger than
  /// the zero that clipping would produce.
  @Test("A Display P3 color is mapped into the cube, not clipped into it")
  func wideColorsAreMapped() throws {
    let p3Red = try CSSColorParser.parse("color(display-p3 1 0 0)").color
    let coordinate = ColorValue(hsv: p3Red.hsvComponents)

    #expect(coordinate.inGamut(of: .srgb, epsilon: 1e-9))
    #expect(coordinate.deltaEOK(to: p3Red.gamutMapped(to: .srgb)) < 1e-9)
    #expect(
      coordinate.deltaEOK(to: .srgb8(255, 0, 0)) > 1e-3,
      "Display P3 red came back as plain red — it was clipped, not gamut-mapped",
    )
  }

  /// Alpha rides alongside rather than through the coordinate, since HSV has no
  /// opinion about it.
  @Test("Alpha is carried")
  func alphaIsCarried() {
    let color = ColorValue(hsv: HSVComponents(hue: 200, saturation: 50, value: 80), alpha: 0.25)
    #expect(color.alpha == 0.25)
    #expect(color.space == .srgb)
  }
}
