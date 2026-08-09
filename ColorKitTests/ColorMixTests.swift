//
//  ColorMixTests.swift
//  ColorKitTests
//
//  M15. The oracle covers exactly one half of this milestone and cannot be asked
//  about the other, which is why the file is split the way it is:
//
//  - **Numbers** are generated. colorjs.io mixes colors, so every interpolation here
//    is checked against 1,700-odd recorded vectors — but only with
//    `premultiplied: true`, and only where both endpoints are inside the
//    interpolation space's gamut. See Tools/generate-mix-fixtures.mjs for both traps.
//  - **Grammar and the percentage rules** are hand-written, because colorjs.io's
//    parser rejects `color-mix()` outright (`Color.parse` throws) and the percentage
//    normalization is CSS Color 5 syntax rather than interpolation arithmetic. This
//    is the fourth distinct reason a milestone here has had no oracle; M12's was that
//    the reference resolves `none`, M13's that it rejects `calc()`, M14's that it has
//    no relative syntax at all.
//
//  Regenerate the fixture with: node Tools/generate-mix-fixtures.mjs
//

@testable import ColorKit
import Foundation
import Testing

// MARK: - Fixture loading

struct MixFixture: Decodable {
  struct Generator: Decodable {
    let library: String
    let version: String
    let premultiplied: Bool
  }

  struct Endpoint: Decodable {
    let space: ColorSpace
    let components: [Double]
    let alpha: Double
  }

  struct Expected: Decodable {
    /// `null` where the reference says the component is missing — which happens
    /// exactly when it was missing or powerless on *both* sides.
    let components: [Double?]
    let alpha: Double
  }

  struct Case: Decodable {
    let space: ColorSpace
    let hue: String
    let progress: Double
    let from: Endpoint
    let to: Endpoint
    let expected: Expected
  }

  let generator: Generator
  let mixes: [Case]
}

enum MixVectors {
  static let shared: MixFixture = {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .appendingPathComponent("Fixtures/mix-vectors.json")
    guard let data = try? Data(contentsOf: url) else {
      fatalError(
        "Missing fixture at \(url.path) — run: node Tools/generate-mix-fixtures.mjs",
      )
    }
    return try! JSONDecoder().decode(MixFixture.self, from: data)
  }()

  static func color(_ endpoint: MixFixture.Endpoint) -> ColorValue {
    ColorValue(
      space: endpoint.space,
      endpoint.components[0],
      endpoint.components[1],
      endpoint.components[2],
      alpha: endpoint.alpha,
    )
  }
}

// MARK: - Shared helpers

/// Distance between two angles the short way round, in degrees.
private func hueDistance(_ actual: Double, _ expected: Double) -> Double {
  let delta = abs(Conversion.constrainAngle(actual - expected))
  return min(delta, 360 - delta)
}

private func parse(_ css: String) throws -> ColorValue {
  try CSSColorParser.parse(css).color
}

// MARK: - Grammar

@Suite("color-mix() — grammar")
struct ColorMixGrammarTests {
  // MARK: Internal

  @Test("The interpolation method is required and names any of the fourteen spaces")
  func interpolationMethod() throws {
    // CSS has no default space here, and that is the point: which space you mix in
    // changes the answer, so the syntax makes you say it.
    expectRejected("color-mix(red, blue)", .mixNeedsInterpolationMethod)
    expectRejected("color-mix(in, red, blue)", .mixNeedsInterpolationMethod)
    expectRejected("color-mix(oklch, red, blue)", .mixNeedsInterpolationMethod)
    expectRejected("color-mix(in nonsense, red, blue)", .unknownInterpolationSpace("nonsense"))

    // Every space is a legal interpolation space — unlike `color()`, which takes
    // eight of the fourteen. That difference is the whole reason the lookup here is
    // derived from the raw values rather than transcribed.
    for space in ColorSpace.allCases {
      let result = try CSSColorParser.parse("color-mix(in \(space.rawValue), red, blue)")
      #expect(result.color.space == space, "\(space.rawValue) should be mixable in")
    }

    // The same alias `color()` accepts.
    #expect(try parse("color-mix(in xyz, red, blue)").space == .xyzD65)
  }

  @Test("A hue arc can be named, and only where there is a hue")
  func hueMethodGrammar() throws {
    for method in HueInterpolationMethod.allCases {
      let result = try CSSColorParser.parse(
        "color-mix(in oklch \(method.rawValue) hue, red, blue)",
      )
      #expect(result.notation == .mix(ColorInterpolation(space: .oklch, hue: method)))
    }

    // `shorter` is the default, so naming it must produce the same color as
    // omitting it — the one claim that says the default is real rather than
    // whatever the struct happened to initialize to.
    #expect(
      try parse("color-mix(in oklch, red, blue)")
        == parse("color-mix(in oklch shorter hue, red, blue)"),
    )

    expectRejected("color-mix(in oklch longer, red, blue)", .hueMethodNeedsHueKeyword("longer"))
    expectRejected(
      "color-mix(in srgb shorter hue, red, blue)",
      .hueMethodNeedsPolarSpace(method: "shorter", space: "srgb"),
    )
    expectRejected("color-mix(in oklch sideways hue, red, blue)", .unexpectedToken("sideways"))
  }

  @Test("Exactly two colors, and they may be any color syntax at all")
  func operands() throws {
    expectRejected("color-mix(in srgb, red)", .mixNeedsTwoColors)
    expectRejected("color-mix(in srgb)", .mixNeedsTwoColors)
    expectRejected("color-mix(in srgb, red, )", .mixNeedsTwoColors)
    expectRejected("color-mix(in srgb, , blue)", .mixNeedsTwoColors)
    expectRejected("color-mix(in srgb, red, blue, green)")
    expectRejected("color-mix(in srgb, red, blue", .unterminatedFunction("color-mix"))
    expectRejected("color-mix(in srgb, red, blue) x", .trailingContent("x"))

    // Each side goes through the same `consumeColor` every other nested color uses,
    // so every syntax this parser knows is available on both.
    #expect(try parse("color-mix(in srgb, #ff0000, rgb(0 0 255))") == parse("color-mix(in srgb, red, blue)"))
    #expect(
      try parse("color-mix(in srgb, rgb(from red r g b), color(srgb 0 0 1))")
        == parse("color-mix(in srgb, red, blue)"),
    )
  }

  @Test("Mixes nest, in both directions")
  func nesting() throws {
    // A mix is a color, so it can be an operand of another mix and the origin of a
    // relative color. The second case is the one that exercises `consumeColor`'s
    // paren-depth counting against a nested function containing commas.
    let purple = try parse("color-mix(in srgb, red, blue)")
    #expect(try parse("rgb(from color-mix(in srgb, red, blue) r g b)") == purple)

    let outer = try parse("color-mix(in srgb, color-mix(in srgb, red, blue), color-mix(in srgb, red, blue))")
    #expect(outer == purple)

    // Half of a half is a quarter — nesting that would be invisible if the inner
    // mix were being dropped or mis-scoped.
    let quarter = try parse("color-mix(in srgb, color-mix(in srgb, red, blue), red)")
    #expect(abs(quarter.components[2] - 0.25) < 1e-12)
  }

  @Test("Case and whitespace are as free as everywhere else")
  func lexicalFreedom() throws {
    let canonical = try parse("color-mix(in oklch, red, blue)")
    #expect(try parse("COLOR-MIX(IN OKLCH, RED, BLUE)") == canonical)
    #expect(try parse("color-mix(in oklch,red,blue)") == canonical)
    #expect(try parse("  color-mix( in   oklch ,  red , blue )  ") == canonical)
  }

  @Test("The notation reports how the color was written")
  func notation() throws {
    #expect(
      try CSSColorParser.parse("color-mix(in srgb, red, blue)").notation
        == .mix(ColorInterpolation(space: .srgb)),
    )
    #expect(
      try CSSColorParser.parse("color-mix(in hsl longer hue, red, blue)").notation
        == .mix(ColorInterpolation(space: .hsl, hue: .longer)),
    )
    // Not a `ColorFunction`, so it cannot be confused with one.
    #expect(try CSSColorParser.parse("color-mix(in srgb, red, blue)").warnings.isEmpty)
  }

  // MARK: Private

  private func expectRejected(_ input: String, _ expected: ParseError? = nil) {
    if let expected {
      #expect(throws: expected) { try CSSColorParser.parse(input) }
    } else {
      #expect(throws: ParseError.self, "\(input) should be rejected") {
        try CSSColorParser.parse(input)
      }
    }
  }
}

// MARK: - Percentages

@Suite("color-mix() — percentages")
struct ColorMixPercentageTests {
  @Test("Omitted percentages fill themselves in")
  func defaulting() throws {
    let even = try parse("color-mix(in srgb, red, blue)")
    #expect(abs(even.components[0] - 0.5) < 1e-12)
    #expect(abs(even.components[2] - 0.5) < 1e-12)

    // One written percentage decides both, so these are three spellings of one mix.
    let quarter = try parse("color-mix(in srgb, red 25%, blue)")
    #expect(try quarter == parse("color-mix(in srgb, red, blue 75%)"))
    #expect(try quarter == parse("color-mix(in srgb, red 25%, blue 75%)"))
    #expect(abs(quarter.components[0] - 0.25) < 1e-12)
  }

  @Test("A percentage may be written on either side of its color")
  func orderIsFree() throws {
    // `<color> && <percentage>` in the grammar means either order, and a parser
    // that only looks after the color rejects valid CSS.
    #expect(try parse("color-mix(in srgb, 25% red, blue)") == parse("color-mix(in srgb, red 25%, blue)"))
    #expect(try parse("color-mix(in srgb, red, 75% blue)") == parse("color-mix(in srgb, red, blue 75%)"))
  }

  @Test("Percentages summing under 100% make the result transparent")
  func alphaShortfall() throws {
    // The spec's own worked example, and the rule people are most surprised by:
    // 20% + 20% is still an even mix, but only 40% of it is there.
    let faded = try parse("color-mix(in srgb, red 20%, blue 20%)")
    #expect(abs(faded.components[0] - 0.5) < 1e-12)
    #expect(abs(faded.components[2] - 0.5) < 1e-12)
    #expect(abs(faded.alpha - 0.4) < 1e-12)

    // Over 100% only re-normalizes. Scaling *up* would make the result more opaque
    // than either input, which nothing in the spec asks for.
    let opaque = try parse("color-mix(in srgb, red 80%, blue 80%)")
    #expect(abs(opaque.components[0] - 0.5) < 1e-12)
    #expect(opaque.alpha == 1)

    // And the shortfall composes with an alpha that was already there.
    let both = try parse("color-mix(in srgb, rgb(255 0 0 / 0.5) 20%, rgb(0 0 255 / 0.5) 20%)")
    #expect(abs(both.alpha - 0.2) < 1e-12)
  }

  @Test("Out-of-range and empty percentages are rejected")
  func percentageRange() {
    // Rejected rather than clamped, unlike alpha. `red 150%` carries no intention
    // to read: it is a typo, or arithmetic that is not finished.
    #expect(throws: ParseError.mixPercentageOutOfRange(150)) {
      try CSSColorParser.parse("color-mix(in srgb, red 150%, blue)")
    }
    #expect(throws: ParseError.mixPercentageOutOfRange(-10)) {
      try CSSColorParser.parse("color-mix(in srgb, red -10%, blue)")
    }
    // Both at zero leaves no color to return, which the spec calls invalid.
    #expect(throws: ParseError.mixPercentagesAreBothZero) {
      try CSSColorParser.parse("color-mix(in srgb, red 0%, blue 0%)")
    }
    // One at zero is fine — it is the other color, whole.
    #expect(throws: Never.self) { try CSSColorParser.parse("color-mix(in srgb, red 0%, blue)") }
  }

  @Test("A calc() may stand in for a percentage, under the same rules")
  func calcPercentages() throws {
    #expect(
      try parse("color-mix(in srgb, red calc(10% * 3), blue)")
        == parse("color-mix(in srgb, red 30%, blue)"),
    )
    // A resolved calc() is indistinguishable from a written value downstream, so
    // the range rule applies to it identically rather than gaining a second reading.
    #expect(throws: ParseError.mixPercentageOutOfRange(120)) {
      try CSSColorParser.parse("color-mix(in srgb, red calc(60% * 2), blue)")
    }
    // And a calc() that is not a percentage is not a mix percentage.
    #expect(throws: ParseError.mixNeedsPercentage("30.0")) {
      try CSSColorParser.parse("color-mix(in srgb, red calc(10 * 3), blue)")
    }
  }

  @Test("Weights resolve without a parser in sight")
  func weightsDirectly() throws {
    let even = try #require(MixWeights(first: nil, second: nil))
    #expect(even.progress == 0.5)
    #expect(even.alphaMultiplier == 1)

    let shortfall = try #require(MixWeights(first: 20, second: 20))
    #expect(shortfall.progress == 0.5)
    #expect(abs(shortfall.alphaMultiplier - 0.4) < 1e-12)

    let over = try #require(MixWeights(first: 80, second: 80))
    #expect(over.progress == 0.5)
    #expect(over.alphaMultiplier == 1)

    // The one input with no answer.
    #expect(MixWeights(first: 0, second: 0) == nil)
  }
}

// MARK: - Interpolation

@Suite("color-mix() — interpolation")
struct ColorMixInterpolationTests {
  @Test("The ends of the mix are the colors themselves")
  func endpoints() throws {
    let red = try #require(ColorValue.named("red"))
    #expect(try parse("color-mix(in srgb, red 100%, blue)") == red)
    #expect(try parse("color-mix(in srgb, red 0%, blue)") == ColorValue.named("blue"))

    // Across a conversion the claim is the same one, held to float tolerance
    // rather than equality — the endpoint has been through OKLCH and back.
    let inOKLCH = try parse("color-mix(in oklch, red 100%, blue)")
    let converted = red.converted(to: .oklch)
    #expect(inOKLCH.space == .oklch)
    for index in 0 ..< 3 {
      #expect(abs(inOKLCH.components[index] - converted.components[index]) < 1e-12)
    }
  }

  @Test("Alpha is premultiplied, so a faded color does not wash out the other")
  func premultipliedAlpha() throws {
    // The trap this milestone is most likely to fall into, because the wrong answer
    // is plausible: without premultiplication this is `rgb(50% 0% 50%)`, an even
    // split with half of it invisible. Premultiplied, the opaque blue carries twice
    // the weight of the half-transparent red.
    let mixed = try parse("color-mix(in srgb, rgb(255 0 0 / 0.5), blue)")
    #expect(abs(mixed.components[0] - 1.0 / 3.0) < 1e-12)
    #expect(abs(mixed.components[2] - 2.0 / 3.0) < 1e-12)
    #expect(abs(mixed.alpha - 0.75) < 1e-12)

    // A fully transparent color contributes its alpha and nothing else — the
    // clearest statement of what premultiplication is for.
    let overBlue = try parse("color-mix(in srgb, transparent, blue)")
    #expect(overBlue.components[0] == 0)
    #expect(abs(overBlue.components[2] - 1) < 1e-12)
    #expect(abs(overBlue.alpha - 0.5) < 1e-12)
  }

  @Test("A missing alpha is substituted before premultiplication, not exempted from it")
  func missingAlphaIsSubstitutedFirst() throws {
    // §12.2's substitution runs before §12.3 premultiplies, so a `none` alpha on one
    // side has become the other side's alpha by the time anything is scaled — both
    // ends premultiply by the same number and the scaling cancels. The answer is the
    // plain average, and the reference agrees.
    //
    // Reading the *flag* instead of the substituted value premultiplies only the side
    // that had an alpha written, and then divides the other side's components by it on
    // the way out: `rgb(200% 0% 50%)` here, a red channel at twice its own maximum.
    let mixed = try parse("color-mix(in srgb, rgb(255 0 0 / none), rgb(0 0 255 / 0.25))")
    #expect(abs(mixed.components[0] - 0.5) < 1e-12)
    #expect(abs(mixed.components[2] - 0.5) < 1e-12)
    #expect(abs(mixed.alpha - 0.25) < 1e-12)
    #expect(!mixed.missing.contains(.alpha), "only one side was missing it")

    // The same claim stated so it cannot be satisfied by arithmetic that happens to
    // land: an even mix does not depend on the order of its operands, and a rule that
    // consults one side's `missing` flag and not the other's is not symmetric whatever
    // numbers fall out of it.
    let swapped = try parse("color-mix(in srgb, rgb(0 0 255 / 0.25), rgb(255 0 0 / none))")
    for index in 0 ..< 3 {
      #expect(abs(mixed.components[index] - swapped.components[index]) < 1e-12)
    }
    #expect(abs(mixed.alpha - swapped.alpha) < 1e-12)

    // Missing on *both* sides is the case where premultiplication genuinely is
    // skipped — there is no alpha to scale by — and the flag survives into the result.
    let neither = try parse("color-mix(in srgb, rgb(255 0 0 / none), rgb(0 0 255 / none))")
    #expect(abs(neither.components[0] - 0.5) < 1e-12)
    #expect(abs(neither.components[2] - 0.5) < 1e-12)
    #expect(neither.missing.contains(.alpha))
  }

  @Test("Two fully transparent colors mix to a color, not to a NaN")
  func fullyTransparentPair() throws {
    // Premultiplication multiplies both sides by zero; un-premultiplying would divide
    // them by it again, and 0 / 0 is a NaN rather than a recovery. The guard on the
    // divide is the only thing making this a color at all — and the reference agrees
    // on the answer it leaves behind, `rgb(0 0 0 / 0)`.
    let mixed = try parse("color-mix(in srgb, transparent, rgb(0 0 255 / 0))")
    for index in 0 ..< 3 {
      #expect(
        mixed.components[index].isFinite,
        "component \(index) came back \(mixed.components[index])",
      )
      #expect(mixed.components[index] == 0)
    }
    #expect(mixed.alpha == 0)
  }

  @Test("A component missing on both sides keeps its carried value, unscaled")
  func absentComponentsAreNotPremultiplied() throws {
    // Contrived, and it has to be: the value underneath a `none` never reaches CSS
    // output, so this is close to the only shape that can observe the rule. Both
    // operands carry all three components into sRGB by §13.2's set rule — no sRGB
    // role is analogous to any of theirs — and they carry *different* values, because
    // `lab(none none none)` is black where `hwb(none none none)` is pure red.
    //
    // With the flag set on both sides there is no alpha to scale by, so the red
    // channel is the plain average of 0 and 1. Premultiplying it anyway divides by the
    // interpolated alpha on the way out and lands on 2/3 instead.
    let mixed = try parse("color-mix(in srgb, lab(none none none / 0.5), hwb(none none none))")
    for index in 0 ..< 3 {
      #expect(mixed.missing.contains(.component(index)), "component \(index) should carry across")
    }
    #expect(abs(mixed.components[0] - 0.5) < 1e-9)
    #expect(abs(mixed.alpha - 0.75) < 1e-12)
  }

  @Test("A powerless hue takes the other color's, rather than counting as zero")
  func powerlessHue() throws {
    // Reading white's OKLCH hue literally is the single most visible way to get
    // this wrong: white's hue is 0° by convention, so averaging it with blue's
    // 264° gives 132° — a green. Marking it powerless, as the spec requires,
    // gives the light blue anyone would expect.
    let blue = try #require(ColorValue.named("blue")).converted(to: .oklch)
    let mixed = try parse("color-mix(in oklch, white, blue)")
    let mixedHue = try #require(mixed.hue)

    #expect(hueDistance(mixedHue, blue.components[2]) < 1e-9)
    #expect(
      hueDistance(mixedHue, 132) > 100,
      "the naive reading of a powerless hue lands near 132°, and must not",
    )
    // Lightness and chroma still interpolate ordinarily.
    #expect(abs(mixed.components[1] - blue.components[1] / 2) < 1e-9)
  }

  @Test("Missing components are carried across the conversion, then substituted")
  func missingComponents() throws {
    // A `none` takes the other color's value, so this lightness is 0.5 rather than
    // the 0.25 a "none means zero" reading would give.
    let substituted = try parse("color-mix(in oklch, oklch(none 0.2 30), oklch(0.5 0.1 60))")
    #expect(abs(substituted.components[0] - 0.5) < 1e-12)

    // M12's carry-forward is the mechanism, not a lookalike: HSL's missing hue has
    // to survive the conversion into OKLCH for this to be 200. Convert numerically
    // instead and it comes back as HSL's own hue, ~30° away in OKLCH.
    let carried = try parse("color-mix(in oklch, hsl(none 50% 50%), oklch(0.5 0.1 200))")
    let carriedHue = try #require(carried.hue)
    #expect(hueDistance(carriedHue, 200) < 1e-9)

    // Missing on *both* sides stays missing, which is what lets the result
    // serialize as `none` rather than inventing a number for it.
    let stillMissing = try parse("color-mix(in oklch, oklch(0.5 0.1 none), oklch(0.7 0.2 none))")
    #expect(stillMissing.missing.contains(.component(2)))
    #expect(!stillMissing.missing.contains(.component(0)))
  }

  @Test("The four arcs are two arcs, and which is which depends on the direction")
  func hueArcs() throws {
    // 20° and 340° are 40° apart across 0° and 320° apart the other way, so each
    // method picks one of two answers — 0° or 180° at the midpoint. The
    // discriminating part is that reversing the operands swaps which method gets
    // which: `increasing` follows the direction of travel, `shorter` the length.
    // `.nan` rather than a `#require`, so a hueless result fails the comparison
    // below instead of the unwrap — the claim is about the angle either way.
    func midpoint(_ css: String) throws -> Double {
      try parse(css).hue ?? .nan
    }

    let warmToCool = "oklch(0.6 0.15 20), oklch(0.6 0.15 340)"
    #expect(try hueDistance(midpoint("color-mix(in oklch shorter hue, \(warmToCool))"), 0) < 1e-9)
    #expect(try hueDistance(midpoint("color-mix(in oklch longer hue, \(warmToCool))"), 180) < 1e-9)
    #expect(try hueDistance(midpoint("color-mix(in oklch increasing hue, \(warmToCool))"), 180) < 1e-9)
    #expect(try hueDistance(midpoint("color-mix(in oklch decreasing hue, \(warmToCool))"), 0) < 1e-9)

    let coolToWarm = "oklch(0.6 0.15 340), oklch(0.6 0.15 20)"
    #expect(try hueDistance(midpoint("color-mix(in oklch shorter hue, \(coolToWarm))"), 0) < 1e-9)
    #expect(try hueDistance(midpoint("color-mix(in oklch longer hue, \(coolToWarm))"), 180) < 1e-9)
    #expect(try hueDistance(midpoint("color-mix(in oklch increasing hue, \(coolToWarm))"), 0) < 1e-9)
    #expect(try hueDistance(midpoint("color-mix(in oklch decreasing hue, \(coolToWarm))"), 180) < 1e-9)
  }

  @Test("The mix is never gamut mapped, even in a bounded space")
  func noGamutMapping() throws {
    // CSS Color 4 §12 has no mapping step, so mixing a Display P3 green in sRGB
    // lands outside sRGB and says so. **The reference disagrees here** — colorjs.io's
    // `range()` maps both endpoints in first, to avoid flat spots in gradients — so
    // this claim is asserted against the spec rather than against the oracle, and
    // the generator skips exactly these cases.
    let wide = try parse("color-mix(in srgb, color(display-p3 0 1 0), black)")
    #expect(wide.space == .srgb)
    #expect(wide.components[0] < 0, "a mapped result would have clamped this to 0")
    #expect(!wide.inGamut(of: .srgb))
  }

  @Test("Mixing in different spaces gives different colors")
  func theSpaceIsTheChoice() throws {
    // The reason CSS makes the space mandatory. Halfway between white and blue is
    // `rgb(50% 50% 100%)` in sRGB and a distinctly bluer color in OKLCH — 0.14 of a
    // green channel apart, where a 0.05 threshold would also pass on the red one.
    // If these agreed, the interpolation space would be decorative.
    let inSRGB = try parse("color-mix(in srgb, white, blue)")
    let inOKLCH = try parse("color-mix(in oklch, white, blue)").converted(to: .srgb)
    #expect(abs(inSRGB.components[1] - inOKLCH.components[1]) > 0.1)
  }
}

// MARK: - Reference vectors

@Suite("color-mix() — reference vectors")
struct ColorMixVectorTests {
  /// Looser than the 1e-9 the conversion fixtures use, and for a specific reason:
  /// un-premultiplying divides by the interpolated alpha, which is as low as 0.1 in
  /// these vectors, so any upstream difference is multiplied by up to ten on the way
  /// out. Still four orders of magnitude below anything a real defect would move.
  static let tolerance = 1e-8

  @Test("The fixture was generated premultiplied")
  func fixtureProvenance() {
    let generator = MixVectors.shared.generator
    #expect(generator.library == "colorjs.io")
    #expect(
      generator.premultiplied,
      "CSS premultiplies; a fixture generated without it records plausible wrong answers",
    )
    #expect(!MixVectors.shared.mixes.isEmpty)
  }

  @Test("Mixes match the reference", arguments: ColorSpace.allCases)
  func mixesMatchReference(space: ColorSpace) throws {
    var failures: [String] = []
    var checked = 0

    for testCase in MixVectors.shared.mixes where testCase.space == space {
      checked += 1
      let method = try #require(
        HueInterpolationMethod(rawValue: testCase.hue),
        "unknown hue method \(testCase.hue) in the fixture",
      )
      let actual = ColorInterpolation(space: space, hue: method).interpolated(
        from: MixVectors.color(testCase.from),
        to: MixVectors.color(testCase.to),
        at: testCase.progress,
      )

      var complaint: String?
      for index in 0 ..< 3 {
        let slot = ComponentMask.component(index)
        guard let expected = testCase.expected.components[index] else {
          // `null` means the reference considers the component missing, which
          // happens exactly when both endpoints were. That is a claim about the
          // mask, not about a number.
          if !actual.missing.contains(slot) {
            complaint = "component \(index) should be missing, got \(actual.components[index])"
          }
          continue
        }
        if actual.missing.contains(slot) {
          complaint = "component \(index) flagged missing, reference says \(expected)"
          continue
        }
        let difference = space.hueIndex == index
          ? hueDistance(actual.components[index], expected) / 360
          : abs(actual.components[index] - expected) / max(1, abs(expected))
        if difference > Self.tolerance {
          complaint = "component \(index): got \(actual.components[index]), want \(expected)"
        }
      }
      if abs(actual.alpha - testCase.expected.alpha) > Self.tolerance {
        complaint = "alpha: got \(actual.alpha), want \(testCase.expected.alpha)"
      }

      if let complaint {
        failures.append(
          """
          \(testCase.from.space.rawValue) → \(testCase.to.space.rawValue) \
          in \(space.rawValue) \(testCase.hue) @\(testCase.progress): \(complaint)
          """,
        )
      }
    }

    #expect(checked > 0, "No fixture cases interpolate in \(space.rawValue)")
    #expect(
      failures.isEmpty,
      """
      \(failures.count)/\(checked) mixes in \(space.rawValue) diverged:
      \(failures.prefix(5).joined(separator: "\n"))
      """,
    )
  }
}
