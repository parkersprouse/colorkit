//
//  ContrastTests.swift
//  ColorKitTests
//
//  Regenerate the fixture with: node Tools/generate-contrast-fixtures.mjs
//

@testable import ColorKit
import Foundation
import Testing

// MARK: - Fixture loading

struct ContrastFixture: Decodable {
  struct Generator: Decodable {
    let library: String
    let version: String
    let apcaVersion: String
    let wcagMaxRelativeDivergence: Double
  }

  struct Pair: Decodable {
    let text: String
    let background: String
    let wcag: Double
    let apca: Double
    let apcaReversed: Double
  }

  let generator: Generator
  let pairs: [Pair]
}

enum ContrastVectors {
  static let shared: ContrastFixture = {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .appendingPathComponent("Fixtures/contrast-vectors.json")
    guard let data = try? Data(contentsOf: url) else {
      fatalError(
        "Missing fixture at \(url.path) — run: node Tools/generate-contrast-fixtures.mjs",
      )
    }
    return try! JSONDecoder().decode(ContrastFixture.self, from: data)
  }()

  static func parse(_ css: String) throws -> ColorValue {
    try CSSColorParser.parse(css).color
  }
}

// MARK: - WCAG

/// Correctness here rests on the **published anchors**, not on the fixture.
///
/// colorjs.io is the oracle for conversions but only a cross-check for WCAG, because
/// it computes luminance two ways that WCAG does not: XYZ-D65 Y uses the
/// full-precision matrix row where WCAG's text specifies rounded coefficients, and it
/// linearizes at sRGB's 0.04045 where WCAG specifies 0.03928. Measured divergence
/// reaches 1.97e-4 relative. The anchors below are immune to both — they are exact
/// under any variant — which is precisely what makes them the proof.
@Suite("WCAG contrast")
struct WCAGContrastTests {
  // MARK: Internal

  /// The one number everyone knows, and the only one that pins the flare constant:
  /// without the +0.05 terms this would be infinite rather than 21.
  @Test("Black on white is exactly 21:1")
  func blackOnWhiteIsTwentyOne() throws {
    let ratio = try color("#000000").contrastRatio(with: color("#ffffff"))
    #expect(abs(ratio - 21) < 1e-12)
  }

  @Test("A color against itself is exactly 1:1", arguments: ["#000000", "#ffffff", "#3b82f6", "#767676"])
  func selfContrastIsUnity(css: String) throws {
    let c = try color(css)
    #expect(abs(c.contrastRatio(with: c) - 1) < 1e-12)
  }

  /// WCAG's ratio cannot tell text from background — the criticism APCA exists to
  /// answer. Asserting it here documents the limitation rather than leaving someone
  /// to discover it by getting a surprising result.
  @Test("The ratio is symmetric")
  func ratioIsSymmetric() throws {
    let a = try color("#3b82f6")
    let b = try color("#fef08a")
    #expect(abs(a.contrastRatio(with: b) - b.contrastRatio(with: a)) < 1e-12)
  }

  @Test("Every ratio lands between 1:1 and 21:1")
  func ratioStaysInRange() {
    for pair in ContrastVectors.shared.pairs {
      #expect(pair.wcag >= 1 - 1e-9 && pair.wcag <= 21 + 1e-9)
    }
  }

  /// The thresholds themselves, so a mistyped constant fails here rather than
  /// silently passing an inaccessible pairing in the UI.
  @Test("Requirement thresholds match WCAG 2.2")
  func requirementThresholds() {
    #expect(ContrastRequirement.aaNormalText.minimumRatio == 4.5)
    #expect(ContrastRequirement.aaLargeText.minimumRatio == 3)
    #expect(ContrastRequirement.aaaNormalText.minimumRatio == 7)
    #expect(ContrastRequirement.aaaLargeText.minimumRatio == 4.5)
    #expect(ContrastRequirement.nonText.minimumRatio == 3)

    #expect(ContrastRequirement.aaNormalText.criterion == "1.4.3")
    #expect(ContrastRequirement.aaaNormalText.criterion == "1.4.6")
    #expect(ContrastRequirement.nonText.criterion == "1.4.11")
  }

  /// Black on white clears everything; white on white clears nothing. Anything in
  /// between is a judgement about a specific ratio, and these two are not.
  @Test("Pass sets bracket correctly at the extremes")
  func passSetsAtExtremes() throws {
    let maximal = try color("#000000").passedRequirements(on: color("#ffffff"))
    #expect(maximal == Set(ContrastRequirement.allCases))

    let none = try color("#ffffff").passedRequirements(on: color("#ffffff"))
    #expect(none.isEmpty)
  }

  /// An out-of-sRGB color has negative components once converted, and `pow` of a
  /// negative is NaN — which would propagate through the ratio and surface in the UI
  /// as "nan:1" without anything erroring.
  @Test("Out-of-gamut colors produce a real number, not NaN")
  func outOfGamutDoesNotProduceNaN() throws {
    let wide = try color("color(display-p3 1 0 0)")
    let ratio = try wide.contrastRatio(with: color("#ffffff"))
    #expect(ratio.isFinite)
    #expect(ratio >= 1 && ratio <= 21)
  }

  /// The assertion that actually pins the implementation to **WCAG's text** rather
  /// than to the oracle.
  ///
  /// Every other test here would pass just as happily against colorjs.io's
  /// definition — a loose tolerance cannot tell "correct" from "correct enough", and
  /// quietly adopting the reference's rounded-vs-full coefficients would sail
  /// through. This pair was found by searching 20,000 random 8-bit pairs for the
  /// widest disagreement between the two definitions: the two answers sit 3.09e-4
  /// apart, which is 1.97e-4 in relative terms and exactly the divergence the
  /// fixture records. Matching one value here means failing the other.
  @Test("Luminance follows WCAG's rounded coefficients, not the full matrix row")
  func usesWCAGCoefficientsNotTheReferenceRow() throws {
    let ratio = try color("#ef0b17").contrastRatio(with: color("#0a3ef5"))

    // WCAG 2.2 as written: 0.2126/0.7152/0.0722, linearizing at 0.03928.
    #expect(abs(ratio - 1.5661090453855218) < 1e-12)
    // What colorjs.io returns for the same pair, via XYZ-D65 Y. Asserted as a
    // *mismatch* so an accidental switch to the reference's definition fails here.
    #expect(abs(ratio - 1.5664180488869563) > 1e-5)
  }

  /// A wide net for gross error only. The tolerance is the *measured* divergence
  /// between the two definitions, not a number chosen to make the test pass.
  @Test("Ratios agree with colorjs.io to within the known definitional gap")
  func agreesWithReferenceWithinKnownGap() throws {
    let allowed = ContrastVectors.shared.generator.wcagMaxRelativeDivergence * 2
    for pair in ContrastVectors.shared.pairs {
      let mine = try color(pair.text).contrastRatio(with: color(pair.background))
      let relative = abs(mine - pair.wcag) / pair.wcag
      #expect(relative < allowed, "\(pair.text) on \(pair.background)")
    }
  }

  // MARK: Private

  private func color(_ css: String) throws -> ColorValue {
    try ContrastVectors.parse(css)
  }
}

// MARK: - APCA

/// Unlike WCAG, colorjs.io **is** a real oracle here: the Swift implementation is
/// transcribed from that package's source, so agreement should be near float-exact and
/// any drift is a transcription bug rather than a definitional difference.
@Suite("APCA contrast")
struct APCAContrastTests {
  // MARK: Internal

  /// Polarity is the whole point of APCA, and swapping the arguments does not fail
  /// loudly — it returns a plausible number of the wrong sign.
  @Test("Dark on light is positive, light on dark is negative, and they differ")
  func polarityIsSigned() throws {
    let black = try color("#000000")
    let white = try color("#ffffff")

    let darkOnLight = black.apcaContrast(on: white)
    let lightOnDark = white.apcaContrast(on: black)

    #expect(darkOnLight > 0)
    #expect(lightOnDark < 0)
    // Not merely opposite in sign: the two directions genuinely score differently,
    // which is the fact WCAG's symmetric ratio cannot express.
    #expect(abs(darkOnLight) != abs(lightOnDark))
  }

  /// An independent anchor, measured from colorjs.io before any Swift existed, so
  /// this suite is not entirely self-referential against its own fixture.
  @Test("Black text on white measures Lc ≈ 106")
  func blackOnWhiteAnchor() throws {
    let lc = try color("#000000").apcaContrast(on: color("#ffffff"))
    #expect(abs(lc - 106.04067321268862) < 1e-9)
  }

  @Test("A color on itself has no contrast")
  func selfContrastIsZero() throws {
    let c = try color("#3b82f6")
    #expect(c.apcaContrast(on: c) == 0)
  }

  /// Below `loClip` APCA reports exactly zero rather than a small number, because it
  /// makes no claim to be meaningful down there. The fixture contains such pairs.
  @Test("Near-identical colors clip to exactly zero")
  func lowContrastClipsToZero() throws {
    let clipped = ContrastVectors.shared.pairs.filter { $0.apca == 0 }
    try #require(!clipped.isEmpty, "fixture no longer exercises the low clip")

    for pair in clipped {
      let lc = try color(pair.text).apcaContrast(on: color(pair.background))
      #expect(lc == 0, "\(pair.text) on \(pair.background)")
    }
  }

  @Test("Out-of-gamut colors produce a real number, not NaN")
  func outOfGamutDoesNotProduceNaN() throws {
    let lc = try color("color(display-p3 0 1 0)").apcaContrast(on: color("#000000"))
    #expect(lc.isFinite)
  }

  /// Both polarities, so a swapped argument cannot hide behind a symmetric fixture.
  @Test("Lc matches colorjs.io in both directions")
  func matchesReferenceBothWays() throws {
    for pair in ContrastVectors.shared.pairs {
      let text = try color(pair.text)
      let background = try color(pair.background)

      #expect(
        abs(text.apcaContrast(on: background) - pair.apca) < 1e-9,
        "\(pair.text) on \(pair.background)",
      )
      #expect(
        abs(background.apcaContrast(on: text) - pair.apcaReversed) < 1e-9,
        "\(pair.background) on \(pair.text)",
      )
    }
  }

  // MARK: Private

  private func color(_ css: String) throws -> ColorValue {
    try ContrastVectors.parse(css)
  }
}
