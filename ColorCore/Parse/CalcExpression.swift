//
//  CalcExpression.swift
//  ColorKit
//

import Foundation

/// One value inside a `calc()` body, tagged with the CSS type it carries.
///
/// The tag is the whole point: `calc()` is type-checked arithmetic, not arithmetic
/// on doubles. `calc(50% * 2)` is 100% and `calc(50% * 50%)` is nothing at all, and
/// the only thing separating them is which side is a plain number.
///
/// Angles arrive already normalized to degrees, the same way ``CSSToken/dimension``
/// values are elsewhere, so `calc(0.5turn + 30deg)` needs no unit bookkeeping here.
nonisolated enum CalcTerm: Equatable, Sendable {
  case number(Double)
  case percentage(Double) // the value before "%", so 50% is 50
  case angle(Double) // degrees
}

/// Evaluates the scoped subset of `calc()` this parser supports: `+ - * /` over
/// numbers, percentages and angles, flat.
///
/// Deliberately not a general CSS math evaluator. There is no nesting, no
/// parenthesized sub-expression, and no `var()` — see PLAN.md's M13 for why the line
/// is drawn there. What is here is *correct* rather than merely present: precedence
/// is real (`calc(1 + 2 * 3)` is 7, not 9) and the type rules are enforced.
nonisolated enum CalcExpression {
  // MARK: Internal

  /// Evaluates the tokens of one `calc()` body — everything between the `calc(`
  /// that opened it and its closing `)`, neither included.
  ///
  /// - Parameter channels: the origin color's channel keywords, when this `calc()`
  ///   sits inside a relative color function. `nil` outside one, which is what
  ///   keeps `rgb(calc(r * 2) 0 0)` an error rather than a silent zero.
  static func evaluate(
    _ body: [CSSToken],
    channels: ChannelBindings? = nil,
  ) throws(ParseError) -> CalcTerm {
    guard !body.isEmpty else { throw ParseError.calcEmpty }

    var index = 0
    let result = try sum(body, &index, channels)
    guard index == body.count else {
      // Two operands with no operator between them. The realistic way to get
      // here is `calc(1 -2)`, which CSS rejects for the same reason: without
      // the space, `-2` is a signed number rather than a subtraction.
      throw ParseError.calcUnsupportedSyntax(body[index].description)
    }
    return result
  }

  // MARK: Private

  // MARK: - Grammar

  /// `sum := product (('+' | '-') product)*`
  private static func sum(
    _ body: [CSSToken],
    _ index: inout Int,
    _ channels: ChannelBindings?,
  ) throws(ParseError) -> CalcTerm {
    var left = try product(body, &index, channels)

    while index < body.count, body[index] == .plus || body[index] == .minus {
      let adding = body[index] == .plus
      index += 1
      guard index < body.count else { throw ParseError.calcDanglingOperator }
      let right = try product(body, &index, channels)
      left = try add(left, right, adding: adding)
    }

    return left
  }

  /// `product := term (('*' | '/') term)*`
  private static func product(
    _ body: [CSSToken],
    _ index: inout Int,
    _ channels: ChannelBindings?,
  ) throws(ParseError) -> CalcTerm {
    var left = try term(body, &index, channels)

    while index < body.count, body[index] == .asterisk || body[index] == .slash {
      let multiplying = body[index] == .asterisk
      index += 1
      guard index < body.count else { throw ParseError.calcDanglingOperator }
      let right = try term(body, &index, channels)
      left = try multiplying ? multiply(left, right) : divide(left, by: right)
    }

    return left
  }

  /// `term := number | percentage | dimension | channel-keyword`
  private static func term(
    _ body: [CSSToken],
    _ index: inout Int,
    _ channels: ChannelBindings?,
  ) throws(ParseError) -> CalcTerm {
    guard index < body.count else { throw ParseError.calcDanglingOperator }
    let token = body[index]
    index += 1

    switch token {
    case let .number(n):
      return .number(n)
    case let .percentage(p):
      return .percentage(p)
    case let .dimension(value, unit):
      guard let degrees = ColorGrammar.degrees(value, unit: unit) else {
        throw ParseError.calcUnsupportedSyntax("\(value)\(unit)")
      }
      return .angle(degrees)
    case let .ident(name):
      // A channel keyword, and only inside a relative color function — `channels`
      // is nil everywhere else, so the throw below still catches `calc(r * 2)`
      // written outside one.
      guard let value = channels?.value(for: name) else {
        throw ParseError.calcUnsupportedSyntax(name)
      }
      switch value {
      case let .number(n):
        return .number(n)
      case .missing:
        // The spec's rule, and it is *not* the same as the bare-keyword rule
        // one level up: written on its own a missing channel stays missing,
        // but arithmetic on `none` reads it as zero.
        return .number(0)
      }
    default:
      throw ParseError.calcUnsupportedSyntax(token.description)
    }
  }

  // MARK: - Type rules

  /// Addition and subtraction need both sides to carry the same type.
  private static func add(
    _ left: CalcTerm,
    _ right: CalcTerm,
    adding: Bool,
  ) throws(ParseError) -> CalcTerm {
    let sign = adding ? 1.0 : -1.0
    switch (left, right) {
    case let (.number(a), .number(b)):
      return .number(a + sign * b)
    case let (.percentage(a), .percentage(b)):
      return .percentage(a + sign * b)
    case let (.angle(a), .angle(b)):
      return .angle(a + sign * b)
    default:
      throw ParseError.calcTypeMismatch
    }
  }

  /// Multiplication needs at least one plain number; the other side sets the type.
  private static func multiply(_ left: CalcTerm, _ right: CalcTerm) throws(ParseError) -> CalcTerm {
    switch (left, right) {
    case let (.number(a), .number(b)):
      return .number(a * b)
    case let (.percentage(p), .number(n)), let (.number(n), .percentage(p)):
      return .percentage(p * n)
    case let (.angle(d), .number(n)), let (.number(n), .angle(d)):
      return .angle(d * n)
    default:
      throw ParseError.calcTypeMismatch
    }
  }

  /// Division needs a plain number on the right; the left side keeps its type.
  private static func divide(_ left: CalcTerm, by right: CalcTerm) throws(ParseError) -> CalcTerm {
    guard case let .number(divisor) = right else { throw ParseError.calcTypeMismatch }
    guard divisor != 0 else { throw ParseError.calcDivisionByZero }

    switch left {
    case let .number(n): return .number(n / divisor)
    case let .percentage(p): return .percentage(p / divisor)
    case let .angle(d): return .angle(d / divisor)
    }
  }
}
