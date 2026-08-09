//
//  RelativeColorTests.swift
//  ColorKitTests
//
//  M14. No oracle again, and for a third distinct reason: colorjs.io 0.7.0 has no
//  relative color syntax at all — every form here comes back "Expected 3 coordinates
//  … got 4". So the standard of proof is CSS Color 5's stated rules, asserted as
//  properties, plus the fact that the conversions underneath are already
//  oracle-validated. Per CLAUDE.md this file must not re-test those conversions; it
//  tests what relative syntax adds on top of them.
//

@testable import ColorKit
import Foundation
import Testing

@Suite("Relative color syntax — channel resolution")
struct RelativeColorChannelTests {
  @Test("A color rebuilt from its own channels is unchanged")
  func identity() throws {
    // The defining property: naming every channel in order reproduces the origin.
    // It holds within a space and across one, and the cross-space case is the
    // interesting half — it proves the origin really is converted into the output
    // function's space rather than read raw.
    let red = try #require(ColorValue.named("red"))
    #expect(try CSSColorParser.parse("rgb(from red r g b)").color == red)
    #expect(try CSSColorParser.parse("hsl(from red h s l)").color == red.converted(to: .hsl))
    #expect(try CSSColorParser.parse("oklch(from red l c h)").color == red.converted(to: .oklch))
    #expect(try CSSColorParser.parse("lab(from red l a b)").color == red.converted(to: .lab))
    #expect(try CSSColorParser.parse("hwb(from red h w b)").color == red.converted(to: .hwb))
    #expect(
      try CSSColorParser.parse("color(from red display-p3 r g b)").color
        == red.converted(to: .displayP3),
    )
  }

  @Test("Channel keywords carry the output function's written scale, not the space's")
  func writtenScale() throws {
    // The discriminating case, and the one a space-keyed lookup gets wrong:
    // `rgb()` and `color(srgb …)` are the same space and spell the channels the
    // same way, but a keyword is a number in *its own function's* scale. Red's
    // red channel is 255 in one and 1 in the other, so subtracting the right
    // constant lands on zero and subtracting the other does not.
    #expect(try CSSColorParser.parse("rgb(from red calc(r - 255) g b)").color.components[0] == 0)
    #expect(
      try CSSColorParser.parse("color(from red srgb calc(r - 1) g b)").color.components[0] == 0,
    )

    // The rest of the spec's table, each pinned by the same subtraction. These are
    // components whose stored range and written range agree, so the subtraction
    // lands on zero only if the keyword is on the spec's scale.
    #expect(try CSSColorParser.parse("hsl(from red h calc(s - 100) l)").color.components[1] == 0)
    #expect(try CSSColorParser.parse("lab(from white calc(l - 100) a b)").color.components[0] == 0)

    // OKLab's is a *discrimination*, not an exact assertion, and deliberately so:
    // white's OKLab lightness is 1.0000000000000002, not 1, because the transform
    // is a cube root and back. The competing hypothesis is that `l` is written
    // 0–100 like Lab's, which would land on −99, so a tolerance four orders of
    // magnitude larger than the error still tells the two apart cleanly. Asserting
    // `== 0` here would be demanding precision the conversion never promised.
    let oklabL = try CSSColorParser.parse("oklab(from white calc(l - 1) a b)").color.components[0]
    #expect(abs(oklabL) < 0.01, "oklab l should be written 0–1, got a residual of \(oklabL)")

    // HWB and LCH complete the spec's table. Both need a color the identity test
    // cannot stand in for: red's whiteness *and* blackness are 0, so a 0–1 scale
    // and a 0–100 one agree on it and the case proves nothing. A mid grey has
    // both nonzero.
    let grey = try #require(ColorValue.named("gray")).converted(to: .hwb)
    let hwbW = try CSSColorParser.parse("hwb(from gray h calc(w - 50) b)").color.components[1]
    #expect(abs(hwbW - (grey.components[1] - 50)) < 1e-12)
    #expect(grey.components[1] > 1, "a 0–100 whiteness is the whole point of this case")

    // lch chroma is written 0–150, which only a chromatic color distinguishes.
    let lch = try #require(CSSColorParser.color("#3b82f6")).converted(to: .lch)
    let lchC = try CSSColorParser.parse("lch(from #3b82f6 l calc(c - 150) h)").color.components[1]
    #expect(abs(lchC - (lch.components[1] - 150)) < 1e-12)
    #expect(lch.components[1] > 1, "a 0–150 chroma is the whole point of this case")
  }

  @Test("Alpha is clamped where components are not")
  func alphaIsClamped() throws {
    // The spec's asymmetry, and it is not an oversight in either direction.
    // Relative syntax makes the alpha half easy to reach.
    #expect(
      try CSSColorParser.parse("rgb(from rgb(255 0 0 / 0.5) r g b / calc(alpha * 3))")
        .color.alpha == 1,
    )
    #expect(try CSSColorParser.parse("rgb(from red r g b / -0.5)").color.alpha == 0)

    // Components stay unclamped: an out-of-gamut color has to be writable, which
    // is what the "Outside sRGB" badge reports on.
    #expect(try CSSColorParser.parse("rgb(from red calc(r * 2) g b)").color.components[0] == 2)
  }

  @Test("Arithmetic on a channel is the point of the feature")
  func arithmetic() throws {
    // `calc(l * 0.5)` is the case PLAN.md said the value lives in.
    let base = try #require(ColorValue.named("red")).converted(to: .oklch)
    let halved = try CSSColorParser.parse("oklch(from red calc(l * 0.5) c h)").color
    #expect(halved.components[0] == base.components[0] * 0.5)
    #expect(halved.components[1] == base.components[1])
    #expect(halved.components[2] == base.components[2])

    // A hue rotation, which is the other thing people reach for.
    let rotated = try CSSColorParser.parse("oklch(from red l c calc(h + 180))").color
    #expect(rotated.components[2] == base.components[2] + 180)
  }

  @Test("Channels can be reordered, and ordinary values still mix in")
  func reorderingAndLiterals() throws {
    // Keywords are values, not slots — nothing stops `c` landing in the lightness
    // position, and the spec does not either.
    let swapped = try CSSColorParser.parse("oklch(from red c l h)").color
    let base = try #require(ColorValue.named("red")).converted(to: .oklch)
    #expect(swapped.components[0] == base.components[1])
    #expect(swapped.components[1] == base.components[0])

    // Literals, percentages and keywords in one function.
    let mixed = try CSSColorParser.parse("oklch(from red 0.5 50% h)").color
    #expect(mixed.components[0] == 0.5)
    #expect(mixed.components[1] == 0.2) // 50% of oklch chroma's 0.4 reference
    #expect(mixed.components[2] == base.components[2])
  }

  @Test("alpha is a channel like any other")
  func alphaChannel() throws {
    let translucent = try CSSColorParser.parse("rgb(from rgb(255 0 0 / 0.4) r g b / alpha)").color
    #expect(translucent.alpha == 0.4)

    // Available even when the output writes no alpha of its own, and usable in
    // arithmetic like every other channel.
    let halved = try CSSColorParser.parse("rgb(from rgb(255 0 0 / 0.4) r g b / calc(alpha / 2))")
    #expect(halved.color.alpha == 0.2)

    // An origin with no alpha written still exposes one, at 1.
    #expect(try CSSColorParser.parse("rgb(from red r g b / alpha)").color.alpha == 1)
  }

  @Test("An origin can be any color, including a nested function or another relative")
  func nestedOrigins() throws {
    let p3 = try CSSColorParser.parse("rgb(from color(display-p3 1 0 0) r g b)").color
    #expect(p3 == CSSColorParser.color("color(display-p3 1 0 0)")?.converted(to: .srgb))

    #expect(try CSSColorParser.parse("rgb(from #ff0000 r g b)").color == ColorValue.named("red"))

    let doubled = try CSSColorParser.parse("rgb(from rgb(from red r g b) r g b)").color
    #expect(doubled == ColorValue.named("red"))
  }

  @Test("The origin ends at its own closing paren, found by depth")
  func originClosesByDepth() throws {
    // Its own test because the obvious nesting cases above do *not* discriminate:
    // in `rgb(from color(display-p3 1 0 0) r g b)` the first `)` after `color(`
    // already is the right one, and so is it in `rgb(from rgb(from red …) …)` —
    // `from red` opens nothing. Depth counting only earns its keep when the
    // origin's function contains another function, and replacing it with "first
    // close paren wins" passes every test above.
    //
    // A calc() inside the origin is the cheapest case that tells them apart, and
    // the likeliest to be written by hand. Cut at the first `)` and the origin
    // becomes `rgb(calc(255 / 2)` — a one-component rgb() rather than a color.
    let viaCalc = try CSSColorParser.parse("rgb(from rgb(calc(255 / 2) 0 0) r g b)").color
    #expect(viaCalc.components[0] == 127.5 / 255)
    #expect(viaCalc.components[1] == 0)

    // And two function levels inside the origin, for the same reason. The claim
    // here is structural — the right paren was found — so it is checked loosely:
    // the value round-trips sRGB → OKLCh → sRGB and comes back 1.0000000000000002,
    // and demanding exactness would be testing the conversion rather than the
    // parse. Cutting at the wrong paren is off by far more than any epsilon.
    let deep = try CSSColorParser.parse("rgb(from oklch(from color(srgb 1 0 0) l c h) r g b)")
    let red = try #require(ColorValue.named("red"))
    for index in 0 ..< 3 {
      #expect(abs(deep.color.components[index] - red.components[index]) < 1e-12)
    }
  }
}

// MARK: - Missing components

@Suite("Relative color syntax — missing components")
struct RelativeColorMissingTests {
  // The M12 dependency, and the spec names §13.2 outright rather than describing
  // something similar. What makes these tests worth writing is that `none` means
  // two different things depending on where the keyword appears.

  @Test("A missing origin channel carries forward through the conversion")
  func carriesForward() throws {
    // hsl's hue is missing and oklch has a hue, so it pairs off individually.
    let result = try CSSColorParser.parse("oklch(from hsl(none 50% 50%) l c h)")
    #expect(result.color.missing.contains(.component(2)))
    #expect(!result.color.missing.contains(.component(0)))

    // Same space, so nothing to carry — the mask arrives intact.
    let sameSpace = try CSSColorParser.parse("rgb(from rgb(none 0 0) r g b)")
    #expect(sameSpace.color.missing.contains(.first))

    // The set rule, which individual pairing alone would lose: sRGB and OKLab
    // share no role at all, so all three travel together or not at all.
    let asSet = try CSSColorParser.parse("oklab(from rgb(none none none) l a b)")
    #expect(asSet.color.missing.contains(.component(0)))
    #expect(asSet.color.missing.contains(.component(1)))
    #expect(asSet.color.missing.contains(.component(2)))
  }

  @Test("A missing channel is none when written bare and zero inside a calc()")
  func noneMeansTwoThings() throws {
    // The rule that would be lost by modelling a channel as `Double?`: written on
    // its own it stays missing, but arithmetic reads it as zero. Same keyword,
    // same origin, two answers.
    let bare = try CSSColorParser.parse("oklch(from hsl(none 50% 50%) l c h)")
    #expect(bare.color.missing.contains(.component(2)))

    let computed = try CSSColorParser.parse("oklch(from hsl(none 50% 50%) l c calc(h + 10))")
    #expect(!computed.color.missing.contains(.component(2)))
    #expect(computed.color.components[2] == 10)
  }

  @Test("A missing alpha carries too")
  func missingAlpha() throws {
    let result = try CSSColorParser.parse("rgb(from rgb(255 0 0 / none) r g b / alpha)")
    #expect(result.color.missing.contains(.alpha))
  }
}

// MARK: - Rejection

@Suite("Relative color syntax — rejection")
struct RelativeColorRejectionTests {
  // MARK: Internal

  @Test("Channel keywords are rejected without an origin")
  func keywordsNeedAnOrigin() {
    // The gate has to stay shut by default, or every typo becomes a color.
    expectRejected("rgb(r g b)")
    expectRejected("oklch(l c h)")
    expectRejected("rgb(calc(r * 2) 0 0)")
  }

  @Test("Only this space's own keywords are accepted")
  func keywordsArePerSpace() {
    // srgb spells its channels r/g/b, so lab's letters are not in scope — which
    // is what stops a keyword being read against the wrong component.
    expectRejected("rgb(from red l a b)")
    expectRejected("oklch(from red r g b)")
    expectRejected("rgb(from red r g q)")
    // xyz spells them x/y/z despite sharing sRGB's roles. A role-derived table
    // would have accepted r/g/b here and rejected the spec's spelling.
    expectRejected("color(from red xyz r g b)")
    #expect(throws: Never.self) { try CSSColorParser.parse("color(from red xyz x y z)") }
  }

  @Test("Relative syntax cannot use the legacy comma form")
  func legacyIsRejected() {
    // A hard error, not a warning. The other comma leniencies in this parser
    // exist because the intent is unambiguous; the spec rules this one out.
    expectRejected(
      "rgb(from red r, g, b)",
      .relativeSyntaxRequiresModernForm(function: "rgb"),
    )
  }

  @Test("A malformed origin is reported as such")
  func malformedOrigins() {
    expectRejected("rgb(from)", .missingOriginColor)
    expectRejected("rgb(from notacolor r g b)", .unknownKeyword("notacolor"))
    expectRejected("rgb(from / r g b)")

    // M13's paren-stealing finding, in a second place: an unterminated origin
    // needs *every* closing paren missing, because depth counting otherwise hands
    // it the outer function's. Dropping only the inner one makes the origin
    // swallow `r g b)` and fail as a malformed rgb() — which is the honest
    // reading, since the tokens genuinely do not say which `)` was meant.
    expectRejected("rgb(from rgb(255 0 0 r g b", .unterminatedFunction("rgb"))
    expectRejected("rgb(from rgb(255 0 0 r g b)", .unexpectedToken("r"))
  }

  @Test("from is only a keyword in the first position")
  func fromIsPositional() {
    // Elsewhere it is an ordinary identifier, and there is no color named `from`.
    expectRejected("rgb(255 from 0 0)")
    expectRejected("rgb(from red r g from)")
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
