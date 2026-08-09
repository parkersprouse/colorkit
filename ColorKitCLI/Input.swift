import Foundation

/// Turning a command-line word into a color.
enum ColorArgument {
  /// Parses `text` as a CSS color, or throws with the parser's own message.
  ///
  /// This is the CLI's reimplementation of `ParsedInput`, which lives in `ColorStore`
  /// and cannot come along: that type is `@MainActor` and AppKit-bound. The difference
  /// is not only isolation, though — `ParsedInput` keeps the last color that parsed so
  /// the panel does not blank out halfway through typing `oklch(`, and a CLI gets one
  /// shot at one string. So the app's third state, "invalid but carry on", has no
  /// meaning here and is deliberately absent.
  ///
  /// `label` names the operand in the error, because `contrast` takes two colors and
  /// "not a CSS color" twice over says nothing about which one.
  static func parse(_ text: String, as label: String) throws(CLIError) -> ParseResult {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw .usage("The \(label) is empty.")
    }
    do {
      return try CSSColorParser.parse(trimmed)
    } catch {
      throw .failure("Could not read the \(label) “\(trimmed)”: \(error.message)")
    }
  }

  /// The parser's warnings, phrased for stderr.
  ///
  /// A warning means the input was accepted, so these never change the exit code — they
  /// go to stderr precisely so a `$(…)` capturing stdout is unaffected by them.
  static func warnings(_ result: ParseResult, as label: String) -> [String] {
    result.warnings.map { "Warning: the \(label) — \($0.message)" }
  }
}
