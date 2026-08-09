//
//  GamutBoundary.swift
//  ColorKit
//

import Foundation

/// Where a gamut ends, expressed the way a picker needs it: how much chroma is left
/// at a given lightness and hue.
///
/// ``ColorValue/inGamut(of:epsilon:)`` answers *whether* a color fits; this answers
/// *how far it could go*, which is the question a chroma axis has to draw. The search
/// below is that same predicate, called repeatedly — there is no second notion of the
/// edge anywhere in the app.
///
/// It is called **strictly**, unlike the gamut badge, and the difference is a unit
/// error waiting to happen. ``ColorValue/gamutNoiseTolerance`` is `7.5e-5` *of a
/// channel*, sized to stop serialization noise like `rgb(255.0191 0 0)` from being
/// flagged. Chroma is a different unit, and OKLab's cube root makes the exchange rate
/// between them wildly non-constant: at `L = 0` that same 7.5e-5 of channel buys
/// **0.041 of chroma**, so a boundary drawn at the badge's tolerance bulges to a
/// visible width at pure black, where the true answer is zero. The curve is therefore
/// exact and the badge stays forgiving; they differ only over colors that are
/// indistinguishable from black or white anyway.
///
/// **Not the same question as gamut mapping**, which is the trap here.
/// ``ColorValue/gamutMapped(to:)`` returns the nearest *displayable* color and takes
/// clipping whenever clipping happens to be perceptually free — so at a sharp corner
/// of the cube it lands beyond this boundary, legitimately. Pure blue is the case:
/// §13 maps `oklch(0.452014 0.313214 264.052)` straight to `#0000ff` at full chroma,
/// while the boundary at that lightness and hue is `0.2656`. Both are right about
/// their own question. Drawing the curve from the mapper, or the badge from the
/// curve, would make them contradict each other on screen.
nonisolated enum GamutBoundary {
  /// The largest OKLCH chroma at `lightness` and `hue` that still fits in `space`.
  ///
  /// Returns `.infinity` for unbounded spaces, which is the literal truth and also
  /// the useful answer: `min(chroma, maxChroma(…))` then clamps correctly everywhere
  /// without a special case at the call site.
  ///
  /// Found by bisection outward from the neutral axis, which assumes the ray leaves
  /// the gamut once and stays out. **That assumption is false**, and worth knowing
  /// exactly how false before trusting or "fixing" it. Along blue's own ray the sRGB
  /// red channel goes negative at chroma `0.2656`, bottoms out at `-0.009` near
  /// `0.29` — three orders of magnitude past float noise, so this is real geometry
  /// and not a precision artifact — and only returns to zero as the ray grazes the
  /// blue vertex at `0.3132`. The in-gamut set is genuinely two pieces.
  ///
  /// Bisection therefore reports the first exit and misses the far sliver, which is
  /// the behavior to want: everything between is *outside* sRGB, so a picker that
  /// drew the boundary at the second island would present a band of unreachable
  /// colors as reachable. Sampling 3,420 lightness/hue pairs against colorjs.io
  /// found no other disconnected ray — the blue corner is the counterexample, not
  /// the rule.
  ///
  /// - Parameters:
  ///   - tolerance: Slack in the gamut test itself, in channel units. Zero by
  ///     default — see the note above on why the badge's tolerance is the wrong
  ///     number here.
  ///   - resolution: How finely the search converges, in chroma.
  /// - Returns: A chroma that is *inside* the gamut, never merely near it. The
  ///   search keeps the fitting end of the bracket and returns that, so the result
  ///   can be used directly as a color rather than nudged inward first.
  static func maxChroma(
    lightness: Double,
    hue: Double,
    in space: ColorSpace,
    tolerance: Double = 0,
    resolution: Double = 1e-4,
  ) -> Double {
    guard space.rgbBasis != nil else { return .infinity }

    func fits(_ chroma: Double) -> Bool {
      ColorValue(space: .oklch, lightness, chroma, hue)
        .inGamut(of: space, epsilon: tolerance)
    }

    // Bisection needs an interior point to start from, and on the neutral axis
    // that is the gray of this lightness. Past either end of the lightness range
    // even gray has left the cube, and there is no chroma to find at all.
    guard fits(0) else { return 0 }

    // Expand to find a chroma that does *not* fit rather than assuming a ceiling:
    // sRGB tops out near 0.32, ProPhoto RGB far above that. Eight doublings reach
    // 12.8, which no RGB space comes close to.
    var high = 0.05
    var doublings = 0
    while fits(high), doublings < 8 {
      high *= 2
      doublings += 1
    }

    var low = 0.0
    while high - low > resolution {
      let middle = (low + high) / 2
      if fits(middle) {
        low = middle
      } else {
        high = middle
      }
    }
    return low
  }

  /// The boundary sampled evenly across the whole lightness range, for drawing.
  ///
  /// A picker plane needs one of these per hue and then reuses it for every pixel in
  /// the column, which turns a per-pixel gamut search into a per-row one. It is also
  /// the curve the overlay strokes, so the line drawn on screen and the clamping
  /// applied to the pixels underneath come from a single array — the edge cannot be
  /// drawn in one place and enforced in another.
  ///
  /// - Parameter samples: Points returned, spanning lightness `0...1` inclusive.
  static func maxChromaCurve(
    hue: Double,
    in space: ColorSpace,
    samples: Int,
    tolerance: Double = 0,
    resolution: Double = 1e-4,
  ) -> [Double] {
    guard samples > 1 else {
      return samples == 1
        ? [maxChroma(lightness: 0, hue: hue, in: space,
                     tolerance: tolerance, resolution: resolution)]
        : []
    }
    return (0 ..< samples).map { index in
      maxChroma(
        lightness: Double(index) / Double(samples - 1),
        hue: hue,
        in: space,
        tolerance: tolerance,
        resolution: resolution,
      )
    }
  }
}

nonisolated extension ColorValue {
  /// This color, chroma pulled straight in to fit `gamut` — untouched if it already
  /// fits.
  ///
  /// Extracted from ``ShadeRamp``'s own clamp (M22), which is where this rule was
  /// first written and proved: a stop is asked whether it fits *before* it is moved,
  /// so the common case — an in-gamut color — returns unchanged rather than nudged to
  /// within a search step of itself, and a constant-chroma family (a harmony, a pushed
  /// contrast solution) is only ever pulled at the members that actually need it.
  ///
  /// Unconditional clamping would be wrong twice over: it moves an already-fitting
  /// color off itself, and at an unbounded `gamut` ``GamutBoundary/maxChroma`` returns
  /// `.infinity`, which would set every chroma to it.
  func pulledInto(_ gamut: ColorSpace) -> ColorValue {
    guard !inGamut(of: gamut) else { return self }
    var pulled = oklchComponents
    pulled.chroma = GamutBoundary.maxChroma(lightness: pulled.lightness, hue: pulled.hue, in: gamut)
    return derivedOKLCH(pulled)
  }
}
