//
//  ContrastSolverTests.swift
//  ColorKitTests
//

@testable import ColorKit
import Foundation
import Testing

/// Proof for the contrast solver, checked definitionally rather than against a fixture.
///
/// There is no oracle for "the nearest color that reaches 4.5:1" — and WCAG is the one
/// area where colorjs.io is explicitly *not* ground truth for this app anyway (it
/// implements a different definition; see ``ContrastTests``). So the two properties that
/// matter are asserted directly, which is stronger than any recorded output:
///
/// 1. **The answer works** — the returned color satisfies ``ColorValue/meets(_:on:)``.
/// 2. **The answer is minimal** — stepping back toward the original, by more than the
///    search's own resolution, fails. That is the same trick ``GamutBoundaryTests`` uses
///    on the chroma boundary, and it pins "nearest" without pinning an implementation.
@Suite("Contrast solver")
struct ContrastSolverTests {
  static let blue = ColorValue.srgb8(0x3B, 0x82, 0xF6)
  static let white = ColorValue.srgb8(0xFF, 0xFF, 0xFF)
  static let black = ColorValue.srgb8(0x00, 0x00, 0x00)
  static let midGray = ColorValue.srgb8(0x80, 0x80, 0x80)

  /// Comfortably wider than the solver's 1e-5 lightness resolution, so an
  /// off-by-a-search-step passes and a genuinely non-minimal answer does not.
  static let probe = 1e-3

  // MARK: - Web-friendly mode (M22)

  /// Chroma `0.35` fits nowhere in sRGB, at any lightness or hue — sRGB's own peak is
  /// close to `0.32`, at the most saturated blue. Chosen deliberately so
  /// ``candidate(at:)`` needs pulling at every step of the search, not merely near
  /// the edges of the lightness range.
  static let unreachablyVivid = ColorValue(space: .oklch, 0.5, 0.35, 250)

  // MARK: - The two defining properties

  @Test(
    "A solution reaches the target it was asked for",
    arguments: [3.0, 4.5, 7.0],
  )
  func solutionsActuallyPass(target: Double) {
    let solutions = ContrastSolver.solutions(for: Self.blue, on: Self.white, target: target)
    #expect(!solutions.isEmpty)

    for solution in solutions {
      #expect(
        solution.color.contrastRatio(with: Self.white) >= target,
        "\(solution.direction) reached only \(solution.ratio)",
      )
      #expect(abs(solution.ratio - solution.color.contrastRatio(with: Self.white)) < 1e-12)
    }
  }

  /// The requirement vocabulary agrees with the raw number, and the result passes the
  /// same predicate the contrast panel prints — one definition, not two.
  @Test("A solution satisfies the spec predicate, not just the arithmetic")
  func solutionsMeetTheRequirement() throws {
    let solution = try #require(
      ContrastSolver.solutions(
        for: Self.blue, on: Self.white, meeting: .aaNormalText,
      ).first,
    )
    #expect(solution.color.meets(.aaNormalText, on: Self.white))
  }

  /// Minimality, asserted by stepping back. The color one probe-width toward the
  /// original must fail — otherwise the solver overshot and moved further than it had
  /// to.
  @Test(
    "Stepping back toward the original fails the target",
    arguments: [
      (ColorValue.srgb8(0x3B, 0x82, 0xF6), ColorValue.srgb8(0xFF, 0xFF, 0xFF), 4.5),
      (ColorValue.srgb8(0x3B, 0x82, 0xF6), ColorValue.srgb8(0x00, 0x00, 0x00), 7.0),
      (ColorValue.srgb8(0xC0, 0x40, 0x40), ColorValue.srgb8(0x80, 0x80, 0x80), 3.0),
      (ColorValue(space: .oklch, 0.6, 0.2, 140), ColorValue.srgb8(0xFF, 0xFF, 0xFF), 4.5),
    ],
  )
  func solutionsAreMinimal(color: ColorValue, background: ColorValue, target: Double) {
    let origin = color.oklchComponents

    for solution in ContrastSolver.solutions(for: color, on: background, target: target) {
      let solved = solution.color.oklchComponents
      // Back toward where we came from.
      let step = solution.direction == .lighter ? -Self.probe : Self.probe
      let retreated = color.derivedOKLCH(
        OKLCHComponents(
          lightness: solved.lightness + step,
          chroma: origin.chroma,
          hue: origin.hue,
        ),
      )

      #expect(
        retreated.contrastRatio(with: background) < target,
        """
        \(solution.direction) is not minimal: retreating to L \
        \(solved.lightness + step) still reaches \
        \(retreated.contrastRatio(with: background))
        """,
      )
    }
  }

  // MARK: - Only lightness moves

  @Test("Hue and chroma come through untouched")
  func onlyLightnessMoves() {
    let origin = Self.blue.oklchComponents

    for solution in ContrastSolver.solutions(for: Self.blue, on: Self.white, target: 7) {
      let solved = solution.color.oklchComponents
      #expect(abs(solved.chroma - origin.chroma) < 1e-12)
      #expect(abs(solved.hue - origin.hue) < 1e-9)
      #expect(solved.lightness != origin.lightness)
      #expect(
        abs(solution.lightnessDelta - (solved.lightness - origin.lightness)) < 1e-12,
      )
    }
  }

  @Test("Alpha is carried")
  func alphaIsCarried() throws {
    let translucent = ColorValue(space: .oklch, 0.6, 0.15, 250, alpha: 0.5)
    let solution = try #require(
      ContrastSolver.nearest(for: translucent, on: Self.white, target: 4.5),
    )
    #expect(solution.color.alpha == 0.5)
  }

  // MARK: - Which directions exist

  /// Against white there is nowhere lighter to go, and against black nowhere darker.
  /// One solution each, and it is the obvious one.
  @Test("An extreme background leaves only one direction")
  func extremeBackgroundsHaveOneSolution() {
    let onWhite = ContrastSolver.solutions(for: Self.blue, on: Self.white, target: 7)
    #expect(onWhite.count == 1)
    #expect(onWhite.first?.direction == .darker)

    let onBlack = ContrastSolver.solutions(for: Self.blue, on: Self.black, target: 7)
    #expect(onBlack.count == 1)
    #expect(onBlack.first?.direction == .lighter)
  }

  /// A mid-tone background can be escaped in either direction, which is why the solver
  /// returns a list rather than an answer.
  @Test("A mid-tone background offers both directions")
  func midToneBackgroundsHaveTwo() {
    let solutions = ContrastSolver.solutions(for: Self.blue, on: Self.midGray, target: 3)
    #expect(solutions.count == 2)
    #expect(Set(solutions.map(\.direction)) == [.lighter, .darker])
  }

  @Test("Nearest is the smaller move")
  func nearestPicksTheSmallerMove() throws {
    let solutions = ContrastSolver.solutions(for: Self.blue, on: Self.midGray, target: 3)
    let nearest = try #require(
      ContrastSolver.nearest(for: Self.blue, on: Self.midGray, target: 3),
    )
    let smallest = try #require(solutions.map { abs($0.lightnessDelta) }.min())
    #expect(abs(abs(nearest.lightnessDelta) - smallest) < 1e-12)
  }

  // MARK: - The ceiling

  /// **The finding that makes an honest failure mode necessary.** Against a mid-gray
  /// background nothing whatsoever reaches 7:1 — black manages 5.32:1 and white only
  /// 3.95:1. AAA there is not difficult, it is impossible, and a solver that searched
  /// for it would either spin or lie.
  @Test("A target above the ceiling has no solutions at all")
  func unreachableTargetsReturnNothing() {
    let ceiling = ContrastSolver.ceiling(against: Self.midGray)
    #expect(abs(ceiling - 5.3172) < 1e-3, "mid-gray's ceiling moved: \(ceiling)")

    #expect(ContrastSolver.solutions(for: Self.blue, on: Self.midGray, target: 7).isEmpty)
    #expect(ContrastSolver.nearest(for: Self.blue, on: Self.midGray, target: 7) == nil)
    // And just under the ceiling, something is found.
    #expect(!ContrastSolver.solutions(for: Self.blue, on: Self.midGray, target: 5.2).isEmpty)
  }

  /// The closed form agrees with the app's own ratio function evaluated at the
  /// extremes — an independent path to the same number, rather than a restatement of
  /// the algebra.
  @Test(
    "The ceiling is the better of black and white",
    arguments: [
      ColorValue.srgb8(0xFF, 0xFF, 0xFF),
      ColorValue.srgb8(0x00, 0x00, 0x00),
      ColorValue.srgb8(0x80, 0x80, 0x80),
      ColorValue.srgb8(0x3B, 0x82, 0xF6),
      ColorValue.srgb8(0x1A, 0x1A, 0x2E),
    ],
  )
  func ceilingMatchesTheExtremes(background: ColorValue) {
    let measured = max(
      Self.black.contrastRatio(with: background),
      Self.white.contrastRatio(with: background),
    )
    #expect(abs(ContrastSolver.ceiling(against: background) - measured) < 1e-9)
  }

  @Test("Black and white can always reach 21:1")
  func extremesReachTheTop() {
    #expect(abs(ContrastSolver.ceiling(against: Self.white) - 21) < 1e-9)
    #expect(abs(ContrastSolver.ceiling(against: Self.black) - 21) < 1e-9)
  }

  /// **The ceiling has a floor, and it is exactly `√21`.**
  ///
  /// The two candidates — against black, `(l + 0.05) / 0.05`, rising with the
  /// background's luminance, and against white, `1.05 / (l + 0.05)`, falling — cross
  /// where `(l + 0.05)² = 0.05 × 1.05`. So the worst background in existence still
  /// permits `√21 ≈ 4.5826:1`, the geometric mean of WCAG's own range, at a luminance
  /// of `0.1791`.
  ///
  /// Which settles a question the UI would otherwise have to guess at: **AA body text
  /// is always reachable**, by a margin of 0.08, and so is every requirement below it.
  /// Only AAA's 7:1 can actually be impossible. Worth pinning because it is the
  /// difference between an "out of reach" message that fires for a real reason and one
  /// nobody ever sees.
  @Test("No background pushes the ceiling below √21, so AA is always reachable")
  func theCeilingHasAFloor() {
    let floor = 21.0.squareRoot()

    // The worst background, constructed rather than searched for. It sits at
    // luminance `√21 × 0.05 − 0.05 = 0.1791`, which is channel 0.4604 — between the
    // 8-bit grays 117 and 118, so no sweep over hex colors can land on it.
    let worstLuminance = floor * 0.05 - 0.05
    let channel = 1.055 * pow(worstLuminance, 1 / 2.4) - 0.055
    let worst = ColorValue(space: .srgb, channel, channel, channel)

    #expect(abs(worst.wcagRelativeLuminance - worstLuminance) < 1e-9)
    #expect(
      abs(ContrastSolver.ceiling(against: worst) - floor) < 1e-6,
      "the worst case is not √21: \(ContrastSolver.ceiling(against: worst))",
    )

    // And nothing beats it. Swept continuously, since the minimum falls between two
    // 8-bit values.
    for step in 0 ... 1000 {
      let value = Double(step) / 1000
      let gray = ColorValue(space: .srgb, value, value, value)
      #expect(
        ContrastSolver.ceiling(against: gray) >= floor - 1e-9,
        "gray \(value) dropped the ceiling to \(ContrastSolver.ceiling(against: gray))",
      )
    }

    #expect(
      floor > ContrastRequirement.aaNormalText.minimumRatio,
      "AA body text is no longer always reachable",
    )
    #expect(floor < ContrastRequirement.aaaNormalText.minimumRatio)
  }

  /// The other side of that coin: AA really is solvable everywhere, including at the
  /// luminance where the ceiling bottoms out.
  @Test("AA body text has a solution against every gray")
  func aaIsAlwaysSolvable() {
    for step in stride(from: 0, through: 255, by: 5) {
      let gray = ColorValue.srgb8(UInt8(step), UInt8(step), UInt8(step))
      let solutions = ContrastSolver.solutions(
        for: Self.blue, on: gray, meeting: .aaNormalText,
      )
      #expect(!solutions.isEmpty, "no AA solution against gray \(step)")
      for solution in solutions {
        #expect(solution.color.meets(.aaNormalText, on: gray))
      }
    }
  }

  // MARK: - Pushing by hand

  /// "Apart" means the same thing in both polarities, which is the whole point of
  /// deciding the direction from the colors rather than from a fixed sign.
  @Test(
    "Away from the background is away, whichever side you start on",
    arguments: [
      // Dark text on a light background pushes darker.
      (ColorValue.srgb8(0x3B, 0x82, 0xF6), ColorValue.srgb8(0xFF, 0xFF, 0xFF),
       ContrastSolution.Direction.darker),
      // Light text on a dark background pushes lighter.
      (ColorValue.srgb8(0x3B, 0x82, 0xF6), ColorValue.srgb8(0x00, 0x00, 0x00),
       ContrastSolution.Direction.lighter),
      (ColorValue.srgb8(0xFF, 0xFF, 0xFF), ColorValue.srgb8(0x80, 0x80, 0x80),
       ContrastSolution.Direction.lighter),
      (ColorValue.srgb8(0x11, 0x11, 0x11), ColorValue.srgb8(0x80, 0x80, 0x80),
       ContrastSolution.Direction.darker),
    ],
  )
  func directionFollowsTheColors(
    color: ColorValue,
    background: ColorValue,
    expected: ContrastSolution.Direction,
  ) {
    #expect(ContrastSolver.awayFromBackground(for: color, on: background) == expected)
  }

  /// The defining property of the push control: dragging right always raises the ratio,
  /// no matter which polarity the pair is. A fixed "lighter means more contrast" sign
  /// would fail half of these.
  @Test(
    "Pushing apart raises the ratio in both polarities",
    arguments: [
      ColorValue.srgb8(0xFF, 0xFF, 0xFF),
      ColorValue.srgb8(0x00, 0x00, 0x00),
      ColorValue.srgb8(0x80, 0x80, 0x80),
      ColorValue.srgb8(0x1A, 0x1A, 0x2E),
    ],
  )
  func pushingApartRaisesTheRatio(background: ColorValue) {
    let start = Self.blue.contrastRatio(with: background)
    var previous = start
    for step in 1 ... 20 {
      let pushed = ContrastSolver.pushed(
        Self.blue, on: background, by: Double(step) / 40,
      )
      let ratio = pushed.contrastRatio(with: background)
      #expect(
        ratio >= previous - 1e-6,
        "push \(Double(step) / 40) dropped the ratio from \(previous) to \(ratio)",
      )
      previous = ratio
    }
    // Non-decreasing alone is satisfied by a push that does nothing at all, so
    // require that it actually went somewhere.
    #expect(
      previous > start + 0.5,
      "pushing the whole range moved the ratio only \(start) → \(previous)",
    )
  }

  /// The other half of the slider, and the half every other test here skips.
  ///
  /// Pushing *together* walks the color toward the background's own luminance, so the
  /// ratio falls toward 1:1 — in both polarities, which is the same sign-independence
  /// that makes pushing apart work. Asserted rather than assumed to be "the same
  /// arithmetic with a minus sign": the negative half of the range is otherwise never
  /// exercised.
  @Test(
    "Pushing together lowers the ratio, in both polarities",
    arguments: [
      // Blue is darker than white, so together means lighter.
      ColorValue.srgb8(0xFF, 0xFF, 0xFF),
      // Blue is lighter than black, so together means darker.
      ColorValue.srgb8(0x00, 0x00, 0x00),
    ],
  )
  func pushingTogetherLowersTheRatio(background: ColorValue) {
    let start = Self.blue.contrastRatio(with: background)
    var previous = start

    for step in 1 ... 10 {
      let pushed = ContrastSolver.pushed(
        Self.blue, on: background, by: -Double(step) / 50,
      )
      let ratio = pushed.contrastRatio(with: background)
      #expect(
        ratio <= previous + 1e-6,
        "pushing together raised the ratio from \(previous) to \(ratio)",
      )
      previous = ratio
    }

    #expect(previous < start - 0.5, "together moved the ratio only \(start) → \(previous)")
    // And it is heading for 1:1, which is what "together" means.
    #expect(previous > 1)
  }

  /// Pushed far enough *together*, the color crosses the background's own luminance and
  /// contrast starts climbing again — the V, reached from the manual control rather
  /// than from the solver. Pinned because it is exactly the behavior that makes the
  /// panel's live ratio necessary: the slider's sign stops predicting the answer here,
  /// and a UI that inferred the ratio from the sign would be wrong past the crossing.
  @Test("Pushed far enough together, the color crosses over and contrast climbs again")
  func pushingTogetherEventuallyCrossesOver() {
    let background = ColorValue.srgb8(0x80, 0x80, 0x80)
    let start = Self.blue.contrastRatio(with: background)

    // `#3b82f6` is *lighter* than mid-gray — luminance 0.2355 against 0.2159, a much
    // narrower margin than it looks — so away is lighter and "together" darkens it,
    // down through the gray and out the other side. Asserted rather than assumed;
    // assuming it was wrong the first time.
    #expect(ContrastSolver.awayFromBackground(for: Self.blue, on: background) == .lighter)
    #expect(start < 1.1, "the pair should start close to the background's own luminance")

    var lowest = start
    var lowestAt = 0.0
    for step in 0 ... 40 {
      let amount = -Double(step) / 200
      let ratio = ContrastSolver.pushed(Self.blue, on: background, by: amount)
        .contrastRatio(with: background)
      if ratio < lowest {
        lowest = ratio
        lowestAt = amount
      }
    }

    #expect(lowest < 1.02, "never actually reached the background's luminance: \(lowest)")
    #expect(lowestAt < 0, "the minimum should be somewhere along the together half")

    // Past the minimum the ratio climbs again, which a monotone function cannot do.
    let past = ContrastSolver.pushed(Self.blue, on: background, by: lowestAt - 0.2)
      .contrastRatio(with: background)
    #expect(
      past > lowest + 0.5,
      "contrast did not recover past the crossing: \(lowest) → \(past)",
    )
  }

  @Test("A push of nothing changes nothing")
  func zeroPushIsIdentity() {
    #expect(ContrastSolver.pushed(Self.blue, on: Self.white, by: 0) == Self.blue)
  }

  @Test("Pushing keeps hue and chroma, like every transform here")
  func pushingOnlyMovesLightness() {
    let origin = Self.blue.oklchComponents
    let pushed = ContrastSolver.pushed(Self.blue, on: Self.white, by: 0.2)
      .oklchComponents

    #expect(abs(pushed.chroma - origin.chroma) < 1e-12)
    #expect(abs(pushed.hue - origin.hue) < 1e-9)
    #expect(abs(pushed.lightness - (origin.lightness - 0.2)) < 1e-12)
  }

  /// Lightness has ends, so a push runs out rather than running off.
  @Test("A push past the end of the scale clamps")
  func pushingClamps() {
    let far = ContrastSolver.pushed(Self.blue, on: Self.white, by: 5)
    #expect(far.oklchComponents.lightness == 0)
    #expect(abs(far.contrastRatio(with: Self.white) - 21) < 1e-9)
  }

  /// The per-direction ceilings are wildly asymmetric away from mid-luminance, which is
  /// exactly why a push control has to ask for one rather than for the overall figure.
  @Test("Each direction has its own ceiling")
  func directionalCeilings() {
    let navy = ColorValue.srgb8(0x1A, 0x1A, 0x2E)
    let lighter = ContrastSolver.ceiling(against: navy, going: .lighter)
    let darker = ContrastSolver.ceiling(against: navy, going: .darker)

    #expect(lighter > 15, "expected plenty of headroom upward, got \(lighter)")
    #expect(darker < 2, "expected almost none downward, got \(darker)")
    #expect(ContrastSolver.ceiling(against: navy) == max(lighter, darker))

    // And each really is reached by the corresponding extreme.
    #expect(abs(Self.white.contrastRatio(with: navy) - lighter) < 1e-9)
    #expect(abs(Self.black.contrastRatio(with: navy) - darker) < 1e-9)
  }

  // MARK: - Why the solver does not bisect the ratio

  /// **The measured fact the solver's design rests on, pinned so nobody "simplifies"
  /// it into a bisection on the ratio.**
  ///
  /// Contrast against a mid-tone background is not monotonic in lightness — it is a V.
  /// Walking lightness upward, the ratio falls to 1:1 as the color passes through the
  /// background's own luminance and rises again beyond it, so any target has *two*
  /// crossings. A bisection on the ratio would converge on whichever branch its
  /// initial bracket happened to straddle, silently returning the further answer half
  /// the time.
  ///
  /// The solver sidesteps this by inverting the ratio into a target *luminance*, which
  /// **is** monotonic in lightness, and bisecting that instead.
  @Test("Contrast is not monotonic in lightness, which is why luminance is inverted")
  func theRatioIsNotMonotonic() throws {
    let target = 3.0
    let solutions = ContrastSolver.solutions(
      for: Self.blue, on: Self.midGray, target: target,
    )
    #expect(solutions.count == 2)

    let lighter = try #require(solutions.first { $0.direction == .lighter }).color
    let darker = try #require(solutions.first { $0.direction == .darker }).color
    let origin = Self.blue.oklchComponents

    let low = darker.oklchComponents.lightness
    let high = lighter.oklchComponents.lightness
    #expect(low < high)

    // Both ends reach the target...
    #expect(darker.contrastRatio(with: Self.midGray) >= target)
    #expect(lighter.contrastRatio(with: Self.midGray) >= target)

    // ...and the middle does not, which is exactly what a monotonic function
    // cannot do.
    let between = Self.blue.derivedOKLCH(
      OKLCHComponents(
        lightness: (low + high) / 2,
        chroma: origin.chroma,
        hue: origin.hue,
      ),
    )
    #expect(
      between.contrastRatio(with: Self.midGray) < target,
      "the V has flattened — re-derive the solver's assumptions before trusting it",
    )
  }

  /// Luminance, by contrast, really is monotonic in OKLCH lightness — the property the
  /// bisection depends on. Checked at a chroma high enough that gamut mapping is doing
  /// real work at both ends, with a tolerance for the mapper's own jitter (measured at
  /// 5e-5 over 215,000 samples).
  @Test("Relative luminance climbs with lightness", arguments: [0.0, 0.1, 0.2, 0.3])
  func luminanceIsMonotonicInLightness(chroma: Double) {
    let jitter = 1e-4
    for hue in stride(from: 0.0, to: 360.0, by: 45) {
      var previous = -1.0
      for step in 0 ... 200 {
        let lightness = Double(step) / 200
        let luminance = ColorValue(space: .oklch, lightness, chroma, hue)
          .wcagRelativeLuminance
        #expect(
          luminance >= previous - jitter,
          "L \(lightness) C \(chroma) h \(hue): luminance fell to \(luminance)",
        )
        previous = luminance
      }
    }
  }

  // MARK: - Degenerate input

  /// A color already meeting the target still gets an answer, and it is the boundary:
  /// the point at which it would *stop* meeting it. Worth pinning because it is the
  /// reason a UI should ask whether the pair passes before offering a fix — the solver
  /// answers "where is the target", not "what should I do".
  @Test("A passing pair solves to the boundary, not to itself")
  func alreadyPassingSolvesToTheBoundary() throws {
    #expect(Self.black.meets(.aaNormalText, on: Self.white))

    let solution = try #require(
      ContrastSolver.nearest(for: Self.black, on: Self.white, target: 4.5),
    )
    #expect(abs(solution.ratio - 4.5) < 0.01)
    #expect(solution.lightnessDelta > 0, "black should have had to lighten toward the bar")
  }

  /// A gray has no chroma to preserve, so the solver reduces to a plain lightness
  /// search — the simplest case, and the one a UI hits whenever the user is working in
  /// neutrals.
  @Test("An achromatic color solves fine")
  func achromaticInputWorks() throws {
    let solution = try #require(
      ContrastSolver.nearest(for: Self.midGray, on: Self.white, target: 4.5),
    )
    #expect(solution.color.meets(.aaNormalText, on: Self.white))
    #expect(solution.color.oklchComponents.chroma < 1e-4)
  }

  /// 1:1 is the floor of the scale — every pair already reaches it — so the solver
  /// should not fall over on it.
  @Test("A target of 1 is trivially satisfiable")
  func trivialTarget() {
    let solutions = ContrastSolver.solutions(for: Self.blue, on: Self.white, target: 1)
    #expect(!solutions.isEmpty)
    for solution in solutions {
      #expect(solution.ratio >= 1)
    }
  }

  /// Without a `gamut`, today's behavior: the solution keeps the origin's chroma
  /// exactly, wherever that leaves it relative to sRGB. Asserted first so the next
  /// test's "now it stays inside" is a real change, not two tests that happen to
  /// agree.
  @Test("With no gamut, a solution keeps chroma the search cannot express in sRGB")
  func noGamutKeepsChromaAsGiven() throws {
    let solution = try #require(
      ContrastSolver.solutions(for: Self.unreachablyVivid, on: Self.white, target: 4.5).first,
    )
    #expect(abs(solution.color.oklchComponents.chroma - 0.35) < 1e-12)
    #expect(!solution.color.inGamut(of: .srgb))
  }

  /// **The correctness property M22 depends on**: every solution found under a
  /// `gamut` both meets the target *and* fits inside it — never one without the
  /// other. This is what requires the clamp to sit inside the bisection rather than
  /// be applied to its answer afterward: pulling chroma in changes relative
  /// luminance, so a color clamped only at the end could fall back under the target
  /// the search thought it had reached.
  @Test(
    "Under a gamut, every solution both meets the target and fits inside it",
    arguments: [3.0, 4.5, 7.0],
  )
  func gamutClampedSolutionsStillMeetTheTarget(target: Double) {
    let solutions = ContrastSolver.solutions(
      for: Self.unreachablyVivid, on: Self.white, target: target, gamut: .srgb,
    )
    #expect(!solutions.isEmpty)
    for solution in solutions {
      #expect(solution.color.inGamut(of: .srgb), "\(solution.direction) escaped sRGB")
      #expect(
        solution.color.contrastRatio(with: Self.white) >= target,
        "\(solution.direction) reached only \(solution.ratio) after clamping",
      )
      // The reported ratio is the clamped color's own, not the unclamped search's.
      #expect(abs(solution.ratio - solution.color.contrastRatio(with: Self.white)) < 1e-9)
    }
  }

  /// ``pushed(_:on:by:gamut:)`` takes the same parameter, for the manual half of the
  /// tool — no bisection here, so no matching correctness trap, but the result
  /// should still land inside the gamut it was given.
  @Test("A gamut on `pushed` pulls the result inside it")
  func pushedHonorsGamut() {
    let pushed = ContrastSolver.pushed(
      Self.unreachablyVivid, on: Self.white, by: -0.2, gamut: .srgb,
    )
    #expect(pushed.inGamut(of: .srgb))
  }

  /// `gamut: nil` is the default, so every existing call site — and every other test
  /// in this file — keeps behaving exactly as before M22.
  @Test("A nil gamut changes nothing")
  func nilGamutIsANoOp() {
    let without = ContrastSolver.solutions(for: Self.blue, on: Self.white, target: 4.5)
    let withNil = ContrastSolver.solutions(for: Self.blue, on: Self.white, target: 4.5, gamut: nil)
    #expect(without.map(\.color.oklchComponents) == withNil.map(\.color.oklchComponents))
  }
}
