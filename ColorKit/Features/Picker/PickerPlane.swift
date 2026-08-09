//
//  PickerPlane.swift
//  ColorKit
//

import CoreGraphics
import Foundation

/// One rendered picker plane: the pixels, and the gamut edges drawn over them.
///
/// They arrive together because they are computed together. The chroma at which each
/// row stops being displayable is what the pixels are clamped to *and* what the
/// overlay strokes, so shipping them as one value makes it impossible to draw a line
/// the pixels underneath do not obey.
nonisolated struct PickerPlane: @unchecked Sendable {
  /// `CGImage` is immutable once built, so this crosses actors safely; the
  /// annotation is only because CoreGraphics does not say so itself.
  let image: CGImage

  /// Boundary chroma per image row, **top row first** — the same order as the
  /// pixels, so neither the renderer nor the overlay has to flip an index. Row 0 is
  /// lightness 1. Empty for the HSV plane, which has no edge to draw: every point on
  /// it is sRGB by construction.
  let srgbEdge: [Double]
  let displayEdge: [Double]

  var rows: Int {
    srgbEdge.count
  }
}

/// Draws the picker's planes and strips into bitmaps.
///
/// Lives in the feature layer rather than in ColorCore, which imports nothing but
/// Foundation. Everything numeric here comes from the core; what this file adds is
/// pixels.
///
/// `nonisolated` so it can run off the main actor — the app builds with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, and a plane is tens of thousands of
/// color conversions. Doing that on the main thread would hitch the drag that asked
/// for it.
///
/// Every loop checks `Task.isCancelled` and abandons the buffer. A drag queues one
/// render per frame and only the last is wanted; without a check inside the work, a
/// cancelled render still runs to completion, because the caller detaches it and a
/// detached task has no parent to inherit cancellation from.
nonisolated enum PickerPlaneRenderer {
  // MARK: Internal

  /// Rendered edge length. Deliberately below the drawn size and scaled up with
  /// interpolation: a picker plane is a smooth gradient, so the eye cannot tell,
  /// while the cost is quadratic in this number. The parts that must stay crisp —
  /// the boundary curve, the cursor — are strokes drawn over the top, not pixels.
  static let resolution = 200

  /// The strip is one-dimensional, so it can afford more steps than the plane.
  static let stripResolution = 360

  // MARK: - Planes

  static func plane(mode: PickerMode, state: PickerState, webFriendly: Bool) -> PickerPlane? {
    switch mode {
    case .hsv: hsvPlane(hue: state.hsvHue)
    case .oklch: oklchPlane(hue: state.oklchHue, webFriendly: webFriendly)
    }
  }

  // MARK: - Hue strip

  /// The full turn of hues, at the lightness and chroma currently selected.
  ///
  /// Showing the hues *as they are at this position* rather than a generic rainbow.
  /// In OKLCH that is the honest version and also the useful one: at high lightness
  /// the strip visibly runs out of chroma in the blues long before the greens, which
  /// is a real fact about the gamut rather than a rendering shortfall.
  static func hueStrip(mode: PickerMode, state: PickerState, webFriendly: Bool) -> CGImage? {
    let steps = stripResolution
    var pixels = [UInt8](repeating: 255, count: steps * 4)

    for step in 0 ..< steps {
      // Every 32nd step: the strip is a fraction of a plane's work, and checking
      // 360 times would cost more than it saves.
      if step.isMultiple(of: 32), Task.isCancelled {
        return nil
      }
      let hue = Double(step) / Double(steps) * 360
      let displayP3: SIMD3<Double>
      switch mode {
      case .hsv:
        displayP3 = Conversion.convert(
          Conversion.hsvToSRGB(SIMD3(hue, max(state.saturation, 1), max(state.value, 1))),
          from: .srgb,
          to: .displayP3,
        )
      case .oklch:
        // The plane's own edge under web-friendly mode (M22): a strip that still
        // offered hues past sRGB would be a boundary the plane refuses to draw.
        let limit = GamutBoundary.maxChroma(
          lightness: state.lightness, hue: hue, in: webFriendly ? .srgb : .displayP3,
        )
        displayP3 = Conversion.convert(
          SIMD3(state.lightness, min(state.chroma, limit), hue),
          from: .oklch,
          to: .displayP3,
        )
      }
      write(displayP3, into: &pixels, at: step * 4)
    }

    return makeImage(width: 1, height: steps, pixels: pixels)
  }

  // MARK: Private

  /// Saturation across, value down, at a fixed hue.
  ///
  /// Rendered per pixel rather than as two crossed gradients. At a fixed hue the HSV
  /// square really is bilinear — `channel = value · (1 − saturation · k)` for a
  /// constant `k` per channel — and every design tool draws it by layering a
  /// white-to-hue gradient under a clear-to-black one. That shortcut is declined
  /// here because it moves the arithmetic into SwiftUI, whose gradients do not
  /// document which space they interpolate in; if it is linear light, the square is
  /// subtly not the HSV square. The exact version costs a few milliseconds off the
  /// main actor.
  private static func hsvPlane(hue: Double) -> PickerPlane? {
    let size = resolution
    var pixels = [UInt8](repeating: 255, count: size * size * 4)

    for row in 0 ..< size {
      if Task.isCancelled {
        return nil
      }
      let value = (1 - Double(row) / Double(size - 1)) * 100
      for column in 0 ..< size {
        let saturation = Double(column) / Double(size - 1) * 100
        let rgb = Conversion.hsvToSRGB(SIMD3(hue, saturation, value))
        write(
          Conversion.convert(rgb, from: .srgb, to: .displayP3),
          into: &pixels,
          at: (row * size + column) * 4,
        )
      }
    }

    guard let image = makeImage(width: size, height: size, pixels: pixels) else { return nil }
    return PickerPlane(image: image, srgbEdge: [], displayEdge: [])
  }

  /// Chroma across, lightness down, at a fixed hue — with both gamut edges measured.
  ///
  /// Pixels past the display's own edge are drawn at that edge's chroma rather than
  /// gamut-mapped individually: §13 mapping is a bisection per color, and sixty
  /// thousand of them is not a frame budget. Clamping chroma at a fixed lightness and
  /// hue is what §13 spends its search doing anyway, so the plane flattens toward the
  /// right in the same direction the real map moves — it just stops looking for the
  /// last percent. The user is never misled about it, because the sRGB edge is
  /// stroked on top and the value they picked is reported exactly.
  private static func oklchPlane(hue: Double, webFriendly: Bool) -> PickerPlane? {
    let size = resolution
    var pixels = [UInt8](repeating: 255, count: size * size * 4)
    var srgbEdge = [Double](repeating: 0, count: size)
    var displayEdge = [Double](repeating: 0, count: size)

    for row in 0 ..< size {
      if Task.isCancelled {
        return nil
      }
      let lightness = 1 - Double(row) / Double(size - 1)
      let srgbMax = GamutBoundary.maxChroma(lightness: lightness, hue: hue, in: .srgb)
      let displayMax = GamutBoundary.maxChroma(lightness: lightness, hue: hue, in: .displayP3)
      srgbEdge[row] = srgbMax
      displayEdge[row] = displayMax
      // Under web-friendly mode (M22) the pixels themselves stop at the sRGB edge
      // rather than the display's — a color past it is not merely undrawn, it is
      // unreachable by dragging, which is the mode's whole promise for the picker.
      let pixelLimit = webFriendly ? srgbMax : displayMax

      for column in 0 ..< size {
        let chroma = Double(column) / Double(size - 1) * PickerState.chromaAxisMaximum
        let oklch = SIMD3(lightness, min(chroma, pixelLimit), hue)
        write(
          Conversion.convert(oklch, from: .oklch, to: .displayP3),
          into: &pixels,
          at: (row * size + column) * 4,
        )
      }
    }

    guard let image = makeImage(width: size, height: size, pixels: pixels) else { return nil }
    return PickerPlane(image: image, srgbEdge: srgbEdge, displayEdge: displayEdge)
  }

  // MARK: - Bitmap plumbing

  /// Clamps into the display's cube and writes one 8-bit pixel.
  ///
  /// The clamp is the last resort rather than the strategy: callers have already
  /// pulled chroma back to the display edge, so what remains here is the float
  /// residue either side of `0` and `1`. Clipping *that* shifts no hue anybody can
  /// see, where clipping a genuinely wide color would.
  private static func write(_ displayP3: SIMD3<Double>, into pixels: inout [UInt8], at offset: Int) {
    for channel in 0 ..< 3 {
      let clamped = min(max(displayP3[channel], 0), 1)
      pixels[offset + channel] = UInt8((clamped * 255).rounded())
    }
    pixels[offset + 3] = 255
  }

  /// Tagged **Display P3**, matching how the app draws every other swatch. Tagging
  /// sRGB would wash out exactly the wide colors this panel is for.
  private static func makeImage(width: Int, height: Int, pixels: [UInt8]) -> CGImage? {
    guard let space = CGColorSpace(name: CGColorSpace.displayP3),
          let provider = CGDataProvider(data: Data(pixels) as CFData)
    else { return nil }

    return CGImage(
      width: width,
      height: height,
      bitsPerComponent: 8,
      bitsPerPixel: 32,
      bytesPerRow: width * 4,
      space: space,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
      provider: provider,
      decode: nil,
      shouldInterpolate: true,
      intent: .defaultIntent,
    )
  }
}
