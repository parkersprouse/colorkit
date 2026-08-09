//
//  CSSParsingTests.swift
//  ColorKitTests
//
//  Three separate concerns:
//
//  1. Parsing valid CSS, checked against a CURATED colorjs.io fixture. Curated
//     because the reference's parser is permissive in ways browsers are not, so it
//     is an oracle only for the subset where it and the spec agree.
//  2. Rejecting invalid CSS — hand-written, since the reference would accept much of
//     it. This is the part that decides whether the parser is actually useful.
//  3. Round-trip stability, asserted at the string level.
//

@testable import ColorKit
import Foundation
import Testing

// MARK: - Fixture

struct ParseFixture: Decodable {
  struct Case: Decodable {
    let input: String
    let space: ColorSpace
    let components: [Double?]
    let alpha: Double?
  }

  let cases: [Case]
}

enum ParseVectors {
  static let shared: ParseFixture = {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .appendingPathComponent("Fixtures/parse-vectors.json")
    guard let data = try? Data(contentsOf: url) else {
      fatalError("Missing fixture — run: node Tools/generate-parse-fixtures.mjs")
    }
    return try! JSONDecoder().decode(ParseFixture.self, from: data)
  }()
}

// MARK: - Valid input

@Suite("CSS parsing — valid input")
struct CSSParseValidTests {
  @Test("Every curated fixture parses to the reference value")
  func fixturesParse() throws {
    // Guards against the whole suite passing vacuously if the fixture ever loads
    // empty or shrinks unnoticed.
    #expect(
      ParseVectors.shared.cases.count >= 100,
      "fixture looks truncated — run: node Tools/generate-parse-fixtures.mjs",
    )

    var failures: [String] = []

    for testCase in ParseVectors.shared.cases {
      let result: ParseResult
      do {
        result = try CSSColorParser.parse(testCase.input)
      } catch {
        failures.append("\(testCase.input) → rejected: \(error.message)")
        continue
      }

      if result.color.space != testCase.space {
        failures.append(
          "\(testCase.input) → space \(result.color.space.rawValue), expected \(testCase.space.rawValue)",
        )
        continue
      }

      for i in 0 ..< 3 {
        if let expected = testCase.components[i] {
          let actual = result.color.components[i]
          if abs(actual - expected) > 1e-9 * max(1, abs(expected)) {
            failures.append(
              "\(testCase.input) → component \(i) = \(actual), expected \(expected)",
            )
          }
        } else if !result.color.missing.contains(.component(i)) {
          failures.append("\(testCase.input) → component \(i) should be `none`")
        }
      }

      if let expectedAlpha = testCase.alpha {
        if abs(result.color.alpha - expectedAlpha) > 1e-9 {
          failures.append(
            "\(testCase.input) → alpha \(result.color.alpha), expected \(expectedAlpha)",
          )
        }
      } else if !result.color.missing.contains(.alpha) {
        failures.append("\(testCase.input) → alpha should be `none`")
      }
    }

    #expect(
      failures.isEmpty,
      "\(failures.count)/\(ParseVectors.shared.cases.count) failed:\n\(failures.prefix(10).joined(separator: "\n"))",
    )
  }

  @Test("Percentage references follow CSS Color 4 per space")
  func percentageReferences() throws {
    // The single most error-prone table in the grammar: 100% means something
    // different for Lab's a/b (125) than OKLab's (0.4), and LCH chroma (150)
    // than OKLCH's (0.4).
    #expect(try CSSColorParser.parse("lab(100% 100% 100%)").color.components == SIMD3(100, 125, 125))
    #expect(try CSSColorParser.parse("oklab(100% 100% 100%)").color.components == SIMD3(1, 0.4, 0.4))
    #expect(try CSSColorParser.parse("lch(100% 100% 0)").color.components == SIMD3(100, 150, 0))
    #expect(try CSSColorParser.parse("oklch(100% 100% 0)").color.components == SIMD3(1, 0.4, 0))
    #expect(try CSSColorParser.parse("rgb(100% 100% 100%)").color.components == SIMD3(1, 1, 1))
    #expect(try CSSColorParser.parse("hsl(0 100% 100%)").color.components == SIMD3(0, 100, 100))
    #expect(try CSSColorParser.parse("color(display-p3 100% 100% 100%)").color.components == SIMD3(1, 1, 1))
  }

  @Test("All four hue units convert to degrees")
  func hueUnits() throws {
    #expect(try CSSColorParser.parse("hsl(120deg 50% 50%)").color.components.x == 120)
    #expect(try abs(CSSColorParser.parse("hsl(0.5turn 50% 50%)").color.components.x - 180) < 1e-9)
    #expect(try abs(CSSColorParser.parse("hsl(100grad 50% 50%)").color.components.x - 90) < 1e-9)
    #expect(try abs(CSSColorParser.parse("hsl(3.14159265358979rad 50% 50%)").color.components.x - 180) < 1e-9)
  }

  @Test("Hue is preserved as authored, not normalized")
  func hueNotNormalized() throws {
    // Normalizing at parse time would silently rewrite the user's input.
    #expect(try CSSColorParser.parse("hsl(-60 50% 50%)").color.components.x == -60)
    #expect(try CSSColorParser.parse("hsl(400 50% 50%)").color.components.x == 400)
  }

  @Test("Out-of-range rgb values survive parsing")
  func outOfRangePreserved() throws {
    // `rgb(300 -20 0)` is syntactically valid CSS. Clamping here would destroy
    // information before the user ever sees it.
    let color = try CSSColorParser.parse("rgb(300 -20 0)").color
    #expect(abs(color.components.x - 300.0 / 255.0) < 1e-12)
    #expect(color.components.y < 0)
  }

  @Test("Notation is reported so the UI can echo the authored form")
  func notationIsReported() throws {
    #expect(try CSSColorParser.parse("#f00").notation == .hex(digits: 3))
    #expect(try CSSColorParser.parse("#ff0000aa").notation == .hex(digits: 8))
    #expect(try CSSColorParser.parse("red").notation == .keyword("red"))
    #expect(try CSSColorParser.parse("rgb(255 0 0)").notation == .function(.rgb, legacy: false))
    #expect(try CSSColorParser.parse("rgb(255, 0, 0)").notation == .function(.rgb, legacy: true))
    #expect(try CSSColorParser.parse("rgba(255, 0, 0, 1)").notation == .function(.rgba, legacy: true))
    // Relative syntax is its own case, carrying no `legacy:` — the spec rules that
    // combination out, so the type has nowhere to express it.
    #expect(try CSSColorParser.parse("rgb(from red r g b)").notation == .relative(.rgb))
    #expect(try CSSColorParser.parse("color(from red srgb r g b)").notation == .relative(.color))
  }

  @Test("xyz is accepted as an alias for xyz-d65")
  func xyzAlias() throws {
    let aliased = try CSSColorParser.parse("color(xyz 0.4 0.2 0.6)").color
    let explicit = try CSSColorParser.parse("color(xyz-d65 0.4 0.2 0.6)").color
    #expect(aliased == explicit)
    #expect(aliased.space == .xyzD65)
  }

  @Test("Numeric edge forms tokenize correctly")
  func numericEdgeForms() throws {
    #expect(try CSSColorParser.parse("rgb(2.55e2 0 0)").color.components.x == 1)
    #expect(try CSSColorParser.parse("rgb(.5 0 0)").color.components.x == 0.5 / 255)
    #expect(try CSSColorParser.parse("rgb(+128 0 0)").color.components.x == 128.0 / 255.0)
    #expect(try CSSColorParser.parse("oklch(0.7 0.15 -200)").color.components.z == -200)
  }
}

// MARK: - Invalid input

@Suite("CSS parsing — rejection")
struct CSSParseRejectionTests {
  // MARK: Internal

  @Test("Non-numeric component tokens are rejected")
  func nonNumericTokens() {
    // The reference parses these as `rgb(none none none)`, turning a typo into a
    // valid color. That is precisely the behavior this tool must not have.
    expectRejected("rgb(a b c)")
    expectRejected("rgb(red green blue)")
    expectRejected("oklch(foo 0.1 200)")
    expectRejected("hsl(120 half full)")
  }

  @Test("Wrong component counts are rejected")
  func wrongArity() {
    expectRejected("rgb(255 0)")
    expectRejected("oklch(0.5 0.1)")
    expectRejected("rgb(1 2 3 4 5)")
    expectRejected("lab(50%)")
    expectRejected("rgb()")
  }

  @Test("A fourth component without a slash is rejected")
  func alphaNeedsSlash() {
    // CSS requires `/` before alpha in modern syntax; the reference accepts a
    // bare fourth value.
    expectRejected("rgb(255 0 0 0)")
    expectRejected("oklch(0.5 0.1 200 0.5)")
  }

  @Test("Mixed comma and slash syntax is rejected")
  func mixedSeparators() {
    expectRejected("rgb(255, 0, 0 / 0.5)")
    expectRejected("rgb(255 0 0, 0.5)")
    expectRejected("hsl(120, 50%, 50% / 0.5)")
  }

  @Test("A dangling slash is rejected")
  func danglingAlpha() {
    expectRejected("rgb(255 0 0 / )")
    expectRejected("rgb(255 0 0 /)")
  }

  @Test("Malformed hex is rejected")
  func badHex() {
    expectRejected("#fff0000") // 7 digits
    expectRejected("#12345") // 5 digits
    expectRejected("#f") // 1 digit
    expectRejected("#ff") // 2 digits
    expectRejected("#")
    expectRejected("#gg0000")
    expectRejected("#ff00gg")
  }

  @Test("Legacy syntax rules are enforced")
  func legacyRules() {
    // Legacy hsl() requires percentages for saturation and lightness.
    expectRejected("hsl(120, 50, 50)")
    expectRejected("hsla(120, 50, 50, 0.5)")
    // Legacy rgb() cannot mix numbers with percentages.
    expectRejected("rgb(255, 50%, 0)")
    expectRejected("rgb(50%, 0, 0)")
  }

  @Test("Unknown identifiers are rejected")
  func unknownIdentifiers() {
    expectRejected("notacolor")
    expectRejected("foo(1 2 3)")
    expectRejected("color(bogus 1 0 0)")
    expectRejected("color(--custom 1 0 0)")
    // Context-dependent, not a color value.
    expectRejected("currentColor")
  }

  @Test("Unsupported CSS functions get a useful error, not a tokenizer complaint")
  func unsupportedFunctions() {
    // The naming matters: these bodies contain syntax the color tokenizer has no
    // rules for, so without an early check the user would see a complaint from
    // somewhere inside the argument list instead of what is actually wrong.
    #expect(throws: ParseError.unsupportedFunction("clamp")) {
      try CSSColorParser.parse("oklch(clamp(0, 0.5, 1) 0.1 200)")
    }
    // var() is the common real-world case — worth naming explicitly.
    #expect(throws: ParseError.unsupportedFunction("var")) {
      try CSSColorParser.parse("rgb(var(--r) 0 0)")
    }
    expectRejected("rgb(min(255, 300) 0 0)")

    // calc() was on this list until M13 and is now evaluated. The check still
    // has to fire for anything unevaluatable nested inside one — and it has to
    // fire *first*, because a `min(` reaching `CalcExpression` would come back
    // as "outside the supported subset" rather than naming the function. Both a
    // first-listed name and a later one, since `firstCalled` scans the list
    // rather than the input and only the ordering of the list decides which of
    // two unsupported functions gets named.
    #expect(throws: Never.self) { try CSSColorParser.parse("rgb(calc(1 + 1) 0 0)") }
    #expect(throws: ParseError.unsupportedFunction("var")) {
      try CSSColorParser.parse("rgb(calc(var(--r) * 2) 0 0)")
    }
    #expect(throws: ParseError.unsupportedFunction("min")) {
      try CSSColorParser.parse("rgb(calc(min(1, 2) * 2) 0 0)")
    }

    // And the check must not fire on legitimate functions that merely contain
    // the letters — `color(` must never be mistaken for a math function.
    #expect(throws: Never.self) { try CSSColorParser.parse("color(srgb 1 0 0)") }
  }

  @Test("Empty and trailing content are rejected")
  func emptyAndTrailing() {
    expectRejected("")
    expectRejected("   ")
    expectRejected("red blue")
    expectRejected("#f00 extra")
    expectRejected("rgb(255 0 0) rgb(0 0 0)")
  }

  @Test("An angle in a non-angle slot is rejected")
  func angleInWrongSlot() {
    expectRejected("rgb(120deg 0 0)")
    expectRejected("oklch(0.5deg 0.1 200)")
  }

  // MARK: Private

  private func expectRejected(_ input: String, _ note: Comment? = nil) {
    #expect(throws: ParseError.self, note ?? "\(input) should be rejected") {
      try CSSColorParser.parse(input)
    }
  }
}

// MARK: - Documented leniency

@Suite("CSS parsing — leniency")
struct CSSParseLeniencyTests {
  @Test("Commas in modern-only functions parse, with a warning")
  func commasInModernFunctions() throws {
    // Unambiguous about intent, so rejecting would be unhelpful — but it is not
    // valid CSS, and the warning is what stops it reaching a stylesheet.
    let result = try CSSColorParser.parse("lab(50%, 20, 30)")
    #expect(result.color.components == SIMD3(50, 20, 30))
    #expect(result.warnings.contains(.commasInModernFunction("lab")))
  }

  @Test("none in legacy syntax parses, with a warning")
  func noneInLegacySyntax() throws {
    let result = try CSSColorParser.parse("rgb(none, 0, 0)")
    #expect(result.color.missing.contains(.first))
    #expect(result.warnings.contains(.noneInLegacySyntax))
  }

  @Test("Valid CSS produces no warnings")
  func validInputIsQuiet() throws {
    for input in ["rgb(255 0 0)", "rgb(255, 0, 0)", "oklch(0.7 0.15 200)", "#f00", "red"] {
      #expect(try CSSColorParser.parse(input).warnings.isEmpty, "\(input) should be quiet")
    }
  }
}
