//
//  CalcTests.swift
//  ColorKitTests
//
//  M13. Every case here is hand-written, and that is forced rather than chosen:
//  colorjs.io cannot parse `calc()` at all — `rgb(calc(10 + 20) 0 0)` comes back
//  "Expected 3 coordinates … got 5" — so there is no oracle for any of it. The
//  standard of proof is instead the arithmetic itself, which is checkable by
//  inspection, plus the four rules that are *not* obvious from reading the code:
//  precedence, type checking, the slash consumed as a unit, and adjacent operands.
//

@testable import ColorKit
import Foundation
import Testing

@Suite("calc() — arithmetic")
struct CalcArithmeticTests {
  @Test("The four operators work in every component slot")
  func operators() throws {
    // rgb() numbers run 0–255 and store 0–1, so the expected values are scaled.
    #expect(try CSSColorParser.parse("rgb(calc(100 + 28) 0 0)").color.components[0] == 128 / 255)
    #expect(try CSSColorParser.parse("rgb(calc(200 - 72) 0 0)").color.components[0] == 128 / 255)
    #expect(try CSSColorParser.parse("rgb(calc(64 * 2) 0 0)").color.components[0] == 128 / 255)
    #expect(try CSSColorParser.parse("rgb(calc(256 / 2) 0 0)").color.components[0] == 128 / 255)
  }

  @Test("Percentages and angles carry their own type through the arithmetic")
  func percentagesAndAngles() throws {
    // 50% of oklch's lightness reference (1) after doubling 25%.
    let lightness = try CSSColorParser.parse("oklch(calc(25% * 2) 0.1 200)")
    #expect(lightness.color.components[0] == 0.5)

    // An angle slot, reached by arithmetic on degrees.
    let hue = try CSSColorParser.parse("oklch(0.5 0.1 calc(180deg + 20deg))")
    #expect(hue.color.components[2] == 200)

    // Mixed angle units resolve to degrees before the arithmetic runs.
    let turns = try CSSColorParser.parse("hsl(calc(0.5turn + 30deg) 50% 50%)")
    #expect(turns.color.components[0] == 210)
  }

  @Test("Multiplication and division bind tighter than addition")
  func precedence() throws {
    // 1 + 2 * 3 is 7, not 9. Left-to-right evaluation gets this wrong, which is
    // the mutation that proves the two-level grammar is load-bearing.
    #expect(try CSSColorParser.parse("rgb(calc(1 + 2 * 3) 0 0)").color.components[0] == 7 / 255)
    #expect(try CSSColorParser.parse("rgb(calc(2 * 3 + 1) 0 0)").color.components[0] == 7 / 255)
    #expect(try CSSColorParser.parse("rgb(calc(12 / 2 - 1) 0 0)").color.components[0] == 5 / 255)
    #expect(try CSSColorParser.parse("rgb(calc(1 - 12 / 2) 0 0)").color.components[0] == -5 / 255)
  }

  @Test("A calc() result is indistinguishable from a written value downstream")
  func resolvesToAnOrdinaryValue() throws {
    // Not merely an implementation note — it decides three separate behaviours,
    // so each is pinned rather than left to fall out of the bridge.

    // 1. The legacy same-type rule sees the computed type, so a computed
    //    percentage sits happily beside written ones.
    #expect(throws: Never.self) { try CSSColorParser.parse("rgb(calc(20% + 30%), 0%, 0%)") }
    //    …and a computed number beside a written percentage still fails it.
    #expect(throws: ParseError.mixedNumberAndPercentageInLegacy(function: "rgb")) {
      try CSSColorParser.parse("rgb(calc(100 + 28), 50%, 0%)")
    }

    // 2. Legacy hsl() requires percentages for saturation and lightness, and a
    //    calc() yielding a bare number does not satisfy that.
    #expect(throws: ParseError.percentageRequiredInLegacy(function: "hsl")) {
      try CSSColorParser.parse("hsl(120, calc(25 * 2), 50%)")
    }

    // 3. The angle-slot check applies to a computed angle too.
    #expect(throws: ParseError.self) { try CSSColorParser.parse("rgb(calc(60deg + 60deg) 0 0)") }
  }

  @Test("A calc() color is an ordinary color afterwards")
  func producesARealColor() throws {
    // End to end: the computed value survives into the same color a literal
    // would have produced, notation included.
    let computed = try CSSColorParser.parse("rgb(calc(510 / 2) calc(0 * 5) 0)")
    let literal = try CSSColorParser.parse("rgb(255 0 0)")
    #expect(computed.color == literal.color)
    #expect(computed.notation == literal.notation)
    #expect(computed.warnings.isEmpty)
  }
}

// MARK: - The slash

@Suite("calc() — the slash is two operators")
struct CalcSlashTests {
  // `/` is the alpha separator *and* calc's division. The body has to be consumed
  // as a unit before separator logic sees inside it, and these are the cases that
  // fail if it is not.

  @Test("Division inside calc() does not read as an alpha separator")
  func divisionIsNotAlpha() throws {
    // Three components and no alpha at all, despite a slash in the string.
    let result = try CSSColorParser.parse("rgb(calc(255 / 2) 0 0)")
    #expect(result.color.components[0] == 127.5 / 255)
    #expect(result.color.alpha == 1)
  }

  @Test("An alpha separator still works with a division in the alpha itself")
  func bothSlashesAtOnce() throws {
    // The discriminating case: two slashes in one string meaning different
    // things, told apart only by which side of `calc(`…`)` they fall on.
    let result = try CSSColorParser.parse("rgb(0 0 0 / calc(1 / 2))")
    #expect(result.color.alpha == 0.5)
    #expect(result.color.components == SIMD3(0.0, 0.0, 0.0))
  }

  @Test("A calc() in the last component does not swallow the alpha")
  func calcBeforeAnAlpha() throws {
    let result = try CSSColorParser.parse("rgb(0 0 calc(128 + 127) / 0.25)")
    #expect(result.color.components[2] == 255 / 255)
    #expect(result.color.alpha == 0.25)
  }

  @Test("Commas around a calc() still select the legacy form")
  func legacyFormIsUnaffected() throws {
    let result = try CSSColorParser.parse("rgba(calc(200 + 55), 0, 0, calc(1 / 4))")
    #expect(result.color.components[0] == 1)
    #expect(result.color.alpha == 0.25)
    #expect(result.notation == .function(.rgba, legacy: true))
  }
}

// MARK: - Rejection

@Suite("calc() — rejection")
struct CalcRejectionTests {
  // MARK: Internal

  @Test("Two operands with no operator are rejected")
  func adjacentOperands() throws {
    // `calc(1 -2)` is the reason this rule exists. CSS requires whitespace on
    // both sides of `+` and `-` precisely because `-2` is otherwise a signed
    // number, and the number scanner claims it here for the same reason — so
    // the body is two adjacent values and there is no expression to evaluate.
    expectRejected("rgb(calc(1 -2) 0 0)")
    expectRejected("rgb(calc(1 2) 0 0)")
    expectRejected("rgb(calc(50% 2) 0 0)")

    // The spaced form is a subtraction and reaches a negative channel, which is
    // a legal out-of-gamut sRGB value rather than a parse failure.
    #expect(try CSSColorParser.parse("rgb(calc(1 - 2) 0 0)").color.components[0] == -1 / 255)
  }

  @Test("Types that cannot be combined are rejected")
  func typeMismatches() {
    // This parser's scope, not a claim about CSS: percentages resolve against a
    // reference in a color component, so CSS Values 4 is more permissive here
    // than these rules are. Widening later should not have to retract anything.
    expectRejected("rgb(calc(50% + 2) 0 0)", .calcTypeMismatch)
    expectRejected("oklch(0.5 0.1 calc(90deg + 10) 0)", .calcTypeMismatch)
    // Multiplying two non-numbers has no meaning in any reading.
    expectRejected("rgb(calc(50% * 50%) 0 0)", .calcTypeMismatch)
    expectRejected("oklch(0.5 0.1 calc(90deg * 2deg))", .calcTypeMismatch)
    // Dividing by anything but a plain number, likewise.
    expectRejected("rgb(calc(255 / 50%) 0 0)", .calcTypeMismatch)
  }

  @Test("Division by zero is rejected rather than producing an infinity")
  func divisionByZero() {
    // Left alone this is `.infinity`, which converts and gamut-maps into
    // plausible-looking garbage instead of an error.
    expectRejected("rgb(calc(255 / 0) 0 0)", .calcDivisionByZero)
  }

  @Test("Malformed bodies are rejected")
  func malformedBodies() {
    expectRejected("rgb(calc() 0 0)", .calcEmpty)
    expectRejected("rgb(calc(1 +) 0 0)", .calcDanglingOperator)

    // Unterminated needs *every* closing paren missing, which is what a field
    // parsing as you type actually sees. Drop only calc's own and it swallows
    // the outer function's instead, so the body — not the paren — is what is
    // malformed, and the error says so.
    expectRejected("rgb(calc(1 + 1", .calcUnterminated)
    expectRejected("rgb(calc(1 + 1 0 0)", .calcUnsupportedSyntax("0.0"))

    expectRejected("rgb(calc(none + 1) 0 0)")
    expectRejected("rgb(calc(#fff * 2) 0 0)")
  }

  @Test("Nesting and parentheses are outside the supported subset")
  func nestingIsRejected() {
    // Scoped out deliberately — see PLAN.md's M13. What matters is that each
    // says so, rather than failing with a raw tokenizer complaint about "(".
    expectRejected("rgb(calc((1 + 2) * 3) 0 0)", .calcUnsupportedSyntax("("))
    expectRejected("rgb(calc(1 + calc(2)) 0 0)", .calcUnsupportedSyntax("calc("))
  }

  @Test("Arithmetic outside a calc() is still invalid")
  func operatorsOutsideCalc() throws {
    // The tokenizer grew operator classes for calc's sake; that must not make
    // them legal in an ordinary argument list.
    expectRejected("rgb(1 + 1 0 0)")
    expectRejected("rgb(1 * 2 0 0)")
    expectRejected("rgb((1) 0 0)")
    // And a signed number is still a number, which is what `+` meant before.
    #expect(try CSSColorParser.parse("rgb(+128 0 0)").color.components[0] == 128 / 255)
  }

  @Test("calc() is not itself a color")
  func calcIsNotAColor() {
    #expect(throws: ParseError.unknownFunction("calc")) {
      try CSSColorParser.parse("calc(1 + 1)")
    }
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
