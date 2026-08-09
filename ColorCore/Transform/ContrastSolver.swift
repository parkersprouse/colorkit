//
//  ContrastSolver.swift
//  ColorKit
//

import Foundation

/// A color that reaches a contrast target, and which way it had to move to get there.
nonisolated struct ContrastSolution: Sendable, Equatable {
  /// Which way the lightness moved to reach the target.
  nonisolated enum Direction: String, Sendable, Hashable {
    case lighter
    case darker
  }

  /// The solved color: the original's hue and chroma at a new lightness.
  let color: ColorValue

  /// What it actually achieves against the background it was solved for.
  ///
  /// Reported rather than assumed to equal the target. It lands a hair *above* by
  /// construction — see ``ContrastSolver/solutions(for:on:target:resolution:)`` — and
  /// showing the real number keeps this panel honest in the same way the contrast
  /// panel is.
  let ratio: Double

  let direction: Direction

  /// How far the OKLCH lightness moved, signed. The measure of "nearest".
  let lightnessDelta: Double
}

/// Finds the nearest color that hits a WCAG contrast target, by moving lightness alone.
///
/// **Lightness alone, and deliberately.** Hue and chroma are what make a color *that*
/// color; a solver free to move them would answer a question nobody asked, and the
/// "nearest color" would become a two-dimensional search with no obvious metric. Moving
/// one axis makes the result predictable — the brand color, lighter — and makes the
/// answer exactly checkable.
///
/// **The search inverts the ratio rather than bisecting it, because the ratio is not
/// monotonic.** Walking lightness upward past a mid-tone background, contrast *falls*
/// to 1:1 as the two colors meet and rises again beyond it — a V, with two crossings of
/// any target. Bisecting that directly would land on whichever branch the initial
/// bracket happened to straddle. Relative luminance, though, *is* monotonic in OKLCH
/// lightness (measured: over 215,000 samples spanning six backgrounds, twelve hues and
/// six chromas, the only backwards steps were 5e-5 of gamut-mapper jitter). So the
/// target ratio is converted into the two luminances that produce it, and each is found
/// by one clean bisection on a monotonic function.
///
/// That inversion also makes the result *exact* rather than approximate. `luminance ≥
/// (bgLuminance + 0.05) × target − 0.05` is algebraically equivalent to `ratio ≥
/// target`, so keeping the bracket's passing end — the same trick
/// ``GamutBoundary/maxChroma(lightness:hue:in:tolerance:resolution:)`` uses — returns a
/// color that provably satisfies ``ColorValue/meets(_:on:)`` rather than one sitting a
/// rounding error under the bar.
nonisolated enum ContrastSolver {
  // MARK: Internal

  /// The best contrast **any** color can reach against this background.
  ///
  /// Closed-form, no search: relative luminance is bounded by black and white, and the
  /// ratio grows monotonically as the two luminances separate, so one of those two
  /// extremes is always the answer. Worth surfacing, because the ceiling is much lower
  /// than people expect in the middle of the range — against a mid-gray `#808080`
  /// nothing whatsoever beats 5.32:1, so AAA's 7:1 is not "hard" there, it is
  /// unreachable, and a tool that spun looking for it would be lying.
  static func ceiling(against background: ColorValue) -> Double {
    max(
      ceiling(against: background, going: .lighter),
      ceiling(against: background, going: .darker),
    )
  }

  /// The best contrast reachable against this background **in one direction**.
  ///
  /// The two are wildly asymmetric everywhere except the middle, which is why a UI
  /// that offers to push a color one way has to ask this rather than
  /// ``ceiling(against:)``: on a `#1a1a2e` background, going lighter reaches 16:1 while
  /// going darker manages barely 1.3:1.
  static func ceiling(
    against background: ColorValue,
    going direction: ContrastSolution.Direction,
  ) -> Double {
    let luminance = background.wcagRelativeLuminance
    switch direction {
    case .lighter: return (1 + flare) / (luminance + flare)
    case .darker: return (luminance + flare) / flare
    }
  }

  /// Which way is *away* from the background — the direction that raises contrast.
  ///
  /// A color already lighter than its background gets more legible by getting lighter
  /// still; one already darker, by getting darker. Deciding this from the colors
  /// themselves is what lets a "push apart" control mean the same thing in both
  /// directions, so dragging right raises the ratio whether the text is dark on light
  /// or light on dark.
  ///
  /// On an exact tie there is no side to be on, so the direction with more headroom
  /// wins — the useful answer rather than an arbitrary one.
  static func awayFromBackground(
    for color: ColorValue,
    on background: ColorValue,
  ) -> ContrastSolution.Direction {
    let theirs = background.wcagRelativeLuminance
    let ours = color.wcagRelativeLuminance
    if ours > theirs {
      return .lighter
    }
    if ours < theirs {
      return .darker
    }
    return ceiling(against: background, going: .lighter)
      >= ceiling(against: background, going: .darker)
      ? .lighter
      : .darker
  }

  /// This color pushed away from the background along OKLCH lightness.
  ///
  /// The manual half of the contrast tool, where ``solutions(for:on:target:resolution:)``
  /// is the automatic one: rather than naming a ratio and being handed a color, you move
  /// the color and watch the ratio. Both move lightness alone and neither touches hue or
  /// chroma, so a color pushed to legibility is still recognizably itself.
  ///
  /// - Parameters:
  ///   - amount: Lightness to move, positive *away* from the background and negative
  ///     toward it. Pushing far enough toward the background crosses it and the
  ///     contrast starts climbing again — the V described above. That is the honest
  ///     behavior and the reason a caller should show the live ratio rather than
  ///     assume the slider's sign is the answer.
  ///   - gamut: When set, the result is pulled inside it. `nil` by default — see the
  ///     note on the ``solutions(for:on:target:resolution:gamut:)`` overload below,
  ///     which recalibrates the same way for the same reason (M22).
  static func pushed(
    _ color: ColorValue,
    on background: ColorValue,
    by amount: Double,
    gamut: ColorSpace? = nil,
  ) -> ColorValue {
    guard amount != 0 else { return color }
    let origin = color.oklchComponents
    let sign: Double = awayFromBackground(for: color, on: background) == .lighter ? 1 : -1
    let pushed = color.derivedOKLCH(
      OKLCHComponents(
        lightness: min(max(origin.lightness + sign * amount, 0), 1),
        chroma: origin.chroma,
        hue: origin.hue,
      ),
    )
    return gamut.map(pushed.pulledInto) ?? pushed
  }

  /// Every direction in which `color` can reach `target` against `background`.
  ///
  /// Returns up to two solutions — one lighter, one darker — and fewer when the
  /// target is out of reach that way. An empty result means no color of any lightness
  /// reaches it; compare `target` against ``ceiling(against:)`` to say so in words.
  ///
  /// - Parameters:
  ///   - target: The ratio to reach, as WCAG writes it (4.5 for AA body text).
  ///   - resolution: How finely the lightness search converges. `1e-5` is far below
  ///     any visible step and well above the gamut mapper's own noise.
  ///   - gamut: When set, every lightness the search considers — and the color it
  ///     finally returns — is pulled inside it first (M22, web-friendly mode). `nil`
  ///     by default, leaving today's behavior untouched.
  ///
  ///     **The clamp has to sit inside the search, not be applied to its answer
  ///     afterward.** Pulling chroma in changes ``ColorValue/wcagRelativeLuminance``,
  ///     so a color clamped only after bisecting could fall back under the target —
  ///     the whole reason this solver keeps its bracket's *passing* end is that the
  ///     result provably satisfies ``ColorValue/meets(_:on:)``, and that proof only
  ///     holds if the color measured at each step is the color the caller receives.
  ///     Applying the same transform inside ``ColorValue/pulledInto(_:)`` to both the
  ///     lightness the bisection tests and the lightness it returns is what keeps
  ///     that guarantee under the flag too.
  static func solutions(
    for color: ColorValue,
    on background: ColorValue,
    target: Double,
    resolution: Double = 1e-5,
    gamut: ColorSpace? = nil,
  ) -> [ContrastSolution] {
    let origin = color.oklchComponents
    let backgroundLuminance = background.wcagRelativeLuminance

    /// The color at `lightness`, holding the original's chroma and hue — pulled
    /// inside `gamut` when one is given, exactly as ``candidate(at:)`` is measured.
    func candidate(at lightness: Double) -> ColorValue {
      let color = color.derivedOKLCH(
        OKLCHComponents(
          lightness: lightness,
          chroma: origin.chroma,
          hue: origin.hue,
        ),
      )
      return gamut.map(color.pulledInto) ?? color
    }

    /// The luminance at `lightness`, holding the original's chroma and hue.
    func luminance(at lightness: Double) -> Double {
      candidate(at: lightness).wcagRelativeLuminance
    }

    func solution(_ direction: ContrastSolution.Direction) -> ContrastSolution? {
      // The two luminances that produce exactly `target`, from rearranging
      // `(lighter + flare) / (darker + flare)`.
      let wanted: Double = switch direction {
      case .lighter: (backgroundLuminance + flare) * target - flare
      case .darker: (backgroundLuminance + flare) / target - flare
      }

      // Passing end first: white is the brightest anything gets, black the
      // darkest. Evaluated rather than assumed to be 1 and 0 — at a lightness of
      // 1 the gamut mapper has to bring any chroma back to white for that to
      // hold, and an assumption is exactly the kind of thing this codebase pins.
      let passingEnd: Double = direction == .lighter ? 1 : 0
      let failingEnd: Double = direction == .lighter ? 0 : 1

      func reaches(_ lightness: Double) -> Bool {
        direction == .lighter
          ? luminance(at: lightness) >= wanted
          : luminance(at: lightness) <= wanted
      }

      guard reaches(passingEnd) else { return nil }

      var passing = passingEnd
      var failing = failingEnd
      while abs(passing - failing) > resolution {
        let middle = (passing + failing) / 2
        if reaches(middle) {
          passing = middle
        } else {
          failing = middle
        }
      }

      let solved = candidate(at: passing)
      return ContrastSolution(
        color: solved,
        ratio: solved.contrastRatio(with: background),
        direction: direction,
        lightnessDelta: passing - origin.lightness,
      )
    }

    return [ContrastSolution.Direction.lighter, .darker].compactMap(solution)
  }

  /// The solution that moves the color least, which is what an "auto-fix" should do.
  ///
  /// Nearest in OKLCH lightness — the only axis that moved, so the only one that can
  /// measure the distance.
  static func nearest(
    for color: ColorValue,
    on background: ColorValue,
    target: Double,
    resolution: Double = 1e-5,
    gamut: ColorSpace? = nil,
  ) -> ContrastSolution? {
    solutions(for: color, on: background, target: target, resolution: resolution, gamut: gamut)
      .min { abs($0.lightnessDelta) < abs($1.lightnessDelta) }
  }

  /// The same search, expressed in the vocabulary of the spec.
  static func solutions(
    for color: ColorValue,
    on background: ColorValue,
    meeting requirement: ContrastRequirement,
    resolution: Double = 1e-5,
    gamut: ColorSpace? = nil,
  ) -> [ContrastSolution] {
    solutions(
      for: color,
      on: background,
      target: requirement.minimumRatio,
      resolution: resolution,
      gamut: gamut,
    )
  }

  // MARK: Private

  /// WCAG's flare allowance. Both the ratio and its inverse are built around it.
  private static let flare = 0.05
}
