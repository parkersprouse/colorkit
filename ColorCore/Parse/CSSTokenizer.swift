//
//  CSSTokenizer.swift
//  ColorKit
//

import Foundation

/// A token from CSS color syntax.
///
/// A focused subset of the CSS token grammar — enough for the color functions and
/// nothing more. A general CSS tokenizer would be far more machinery than the job
/// needs.
///
/// There is no `divide` case: `/` is the alpha separator *and* `calc()`'s division
/// operator, and one token serves both because ``CSSColorParser`` consumes a
/// `calc()` body as a unit before separator logic ever sees the tokens inside it.
nonisolated enum CSSToken: Equatable, Sendable {
  case function(String) // ident immediately followed by "("
  case ident(String) // bare keyword: red, none, srgb, deg
  case number(Double) // 255, -0.5, 1e2
  case percentage(Double) // the value before "%", so 50% is 50
  case dimension(Double, String) // 120deg → (120, "deg")
  case hash(String) // #ff0000 → "ff0000"
  case comma
  case slash
  case plus
  case minus
  case asterisk
  case openParen
  case closeParen

  // MARK: Internal

  /// How this token is named back to the user in a parse error.
  ///
  /// Lives on the token rather than beside either parser, because both
  /// ``CSSColorParser`` and ``CalcExpression`` report unexpected tokens and a second
  /// copy of this switch is a copy that can fall out of step with the cases above.
  var description: String {
    switch self {
    case let .function(n): "\(n)("
    case let .ident(n): n
    case let .number(n): "\(n)"
    case let .percentage(p): "\(p)%"
    case let .dimension(v, u): "\(v)\(u)"
    case let .hash(h): "#\(h)"
    case .comma: ","
    case .slash: "/"
    case .plus: "+"
    case .minus: "-"
    case .asterisk: "*"
    case .openParen: "("
    case .closeParen: ")"
    }
  }
}

nonisolated enum CSSTokenizer {
  // MARK: Internal

  /// Splits CSS color syntax into tokens, discarding whitespace.
  ///
  /// Whitespace is dropped, and that is *almost* free: legacy versus modern form is
  /// decided by whether commas are present, which survives tokenization. The one
  /// place CSS makes whitespace load-bearing is `calc()`'s `+` and `-`, which the
  /// spec requires to be surrounded by it precisely because `-2` is otherwise a
  /// signed number.
  ///
  /// Half of that rule survives anyway and it is the half that matters: `scanNumber`
  /// claims `-2` before the operator rules run, so `calc(1 -2)` tokenizes as two
  /// adjacent numbers and the parser rejects it, exactly as CSS does. The other half
  /// does not: `calc(1- 2)` is invalid CSS and parses here as a subtraction, because
  /// nothing downstream can tell it from `calc(1 - 2)`. Documented leniency, in the
  /// safe direction — it accepts a typo rather than misreading a valid expression.
  static func tokenize(_ input: String) throws(ParseError) -> [CSSToken] {
    var tokens: [CSSToken] = []
    let scalars = Array(input.unicodeScalars)
    var i = 0

    while i < scalars.count {
      let c = scalars[i]

      if isWhitespace(c) {
        i += 1
        continue
      }

      switch c {
      case ",":
        tokens.append(.comma)
        i += 1
      case "/":
        tokens.append(.slash)
        i += 1
      case ")":
        tokens.append(.closeParen)
        i += 1
      case "(":
        // A "(" not directly attached to an identifier. Always an error, but the
        // parser throws it so the message can name what was actually attempted —
        // a parenthesized calc() sub-expression is the realistic way to get here.
        tokens.append(.openParen)
        i += 1
      case "*":
        tokens.append(.asterisk)
        i += 1
      case "#":
        i += 1
        var digits = ""
        while i < scalars.count, isHexDigit(scalars[i]) {
          digits.unicodeScalars.append(scalars[i])
          i += 1
        }
        guard !digits.isEmpty else {
          throw ParseError.unexpectedCharacter("#", at: i - 1)
        }
        tokens.append(.hash(digits))
      default:
        if isNumberStart(scalars, at: i) {
          let (value, next) = try scanNumber(scalars, from: i)
          i = next

          if i < scalars.count, scalars[i] == "%" {
            i += 1
            tokens.append(.percentage(value))
          } else if i < scalars.count, isIdentStart(scalars[i]) {
            let (unit, afterUnit) = scanIdent(scalars, from: i)
            i = afterUnit
            tokens.append(.dimension(value, unit.lowercased()))
          } else {
            tokens.append(.number(value))
          }
        } else if c == "+" {
          // No digit follows, so this is not a sign — it is calc()'s addition.
          tokens.append(.plus)
          i += 1
        } else if c == "-", !(i + 1 < scalars.count && isIdentChar(scalars[i + 1])) {
          // "-" means three things and the checks have to run in this order,
          // each earlier one being the more specific: a number's sign (-0.5),
          // an identifier's first character (--custom), and subtraction.
          tokens.append(.minus)
          i += 1
        } else if isIdentStart(c) {
          let (name, next) = scanIdent(scalars, from: i)
          i = next
          if i < scalars.count, scalars[i] == "(" {
            i += 1
            tokens.append(.function(name.lowercased()))
          } else {
            tokens.append(.ident(name.lowercased()))
          }
        } else {
          throw ParseError.unexpectedCharacter(Character(c), at: i)
        }
      }
    }

    return tokens
  }

  // MARK: Private

  // MARK: - Scanners

  /// Scans a CSS number.
  ///
  /// Boundaries are found here rather than handed to `Double(_:)`, which would
  /// happily swallow trailing characters that belong to the next token — the
  /// classic hand-rolled-tokenizer bug where `1e2deg` or `5px` parse as numbers.
  private static func scanNumber(
    _ s: [Unicode.Scalar],
    from start: Int,
  ) throws(ParseError) -> (Double, Int) {
    var i = start
    var text = ""

    if i < s.count, s[i] == "+" || s[i] == "-" {
      text.unicodeScalars.append(s[i])
      i += 1
    }

    var sawDigit = false
    while i < s.count, isDigit(s[i]) {
      text.unicodeScalars.append(s[i])
      i += 1
      sawDigit = true
    }

    if i < s.count, s[i] == "." {
      // Only consume the dot if a digit follows; otherwise it belongs elsewhere.
      if i + 1 < s.count, isDigit(s[i + 1]) {
        text.unicodeScalars.append(s[i])
        i += 1
        while i < s.count, isDigit(s[i]) {
          text.unicodeScalars.append(s[i])
          i += 1
          sawDigit = true
        }
      }
    }

    guard sawDigit else {
      throw ParseError.unexpectedCharacter(Character(s[start]), at: start)
    }

    // Exponent, but only when it is well-formed — `1e2` is a number while the
    // `e` in `1em` starts a unit.
    if i < s.count, s[i] == "e" || s[i] == "E" {
      var j = i + 1
      var exponent = "e"
      if j < s.count, s[j] == "+" || s[j] == "-" {
        exponent.unicodeScalars.append(s[j])
        j += 1
      }
      if j < s.count, isDigit(s[j]) {
        while j < s.count, isDigit(s[j]) {
          exponent.unicodeScalars.append(s[j])
          j += 1
        }
        text += exponent
        i = j
      }
    }

    guard let value = Double(text) else {
      throw ParseError.invalidNumber(text)
    }
    return (value, i)
  }

  private static func scanIdent(_ s: [Unicode.Scalar], from start: Int) -> (String, Int) {
    var i = start
    var text = ""
    while i < s.count, isIdentChar(s[i]) {
      text.unicodeScalars.append(s[i])
      i += 1
    }
    return (text, i)
  }

  // MARK: - Character classes

  private static func isWhitespace(_ c: Unicode.Scalar) -> Bool {
    c == " " || c == "\t" || c == "\n" || c == "\r" || c == "\u{0C}"
  }

  private static func isDigit(_ c: Unicode.Scalar) -> Bool {
    c >= "0" && c <= "9"
  }

  private static func isHexDigit(_ c: Unicode.Scalar) -> Bool {
    isDigit(c) || (c >= "a" && c <= "f") || (c >= "A" && c <= "F")
  }

  private static func isIdentStart(_ c: Unicode.Scalar) -> Bool {
    (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || c == "-" || c == "_"
  }

  private static func isIdentChar(_ c: Unicode.Scalar) -> Bool {
    isIdentStart(c) || isDigit(c)
  }

  private static func isNumberStart(_ s: [Unicode.Scalar], at i: Int) -> Bool {
    let c = s[i]
    if isDigit(c) {
      return true
    }
    if c == "." {
      return i + 1 < s.count && isDigit(s[i + 1])
    }
    if c == "+" || c == "-" {
      guard i + 1 < s.count else { return false }
      if isDigit(s[i + 1]) {
        return true
      }
      // "-" also begins a dashed-ident (`--custom`), so only treat it as a
      // number when a digit actually follows the decimal point.
      return s[i + 1] == "." && i + 2 < s.count && isDigit(s[i + 2])
    }
    return false
  }
}
