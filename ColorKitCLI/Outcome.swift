import Foundation

/// What a command produced: text for each stream and the process's exit status.
///
/// Every command returns one of these rather than printing, which is what makes the
/// whole front-end testable from a unit test — `main.swift` is the only code that
/// touches a file handle, and it does nothing but route these three fields.
struct CommandOutcome: Equatable {
  /// The three exit statuses the CLI distinguishes, and no others.
  ///
  /// A caller scripting this tool can tell "you asked wrong" from "the color you gave
  /// me is not a color", which is the difference between fixing a wrapper script and
  /// fixing its input.
  enum Status: Equatable {
    /// The command ran and its result is on stdout.
    case success
    /// The arguments themselves were wrong — unknown command, missing operand, bad option.
    case usage
    /// The arguments were well-formed and the work failed — a color that will not parse,
    /// a file that will not read.
    case failure

    // MARK: Internal

    var code: Int32 {
      switch self {
      case .success: 0
      case .failure: 1
      case .usage: 2
      }
    }
  }

  /// Goes to stdout. Results only — this is what a `$(…)` in a shell script captures.
  var output: String = ""

  /// Goes to stderr. Errors and usage text only, so a failed run never contaminates
  /// a pipeline with something that reads like a color.
  var diagnostic: String = ""

  var status: Status = .success

  // MARK: Constructors

  static func result(_ text: String) -> CommandOutcome {
    CommandOutcome(output: text, status: .success)
  }

  static func failed(_ message: String) -> CommandOutcome {
    CommandOutcome(diagnostic: message, status: .failure)
  }

  static func misused(_ message: String) -> CommandOutcome {
    CommandOutcome(diagnostic: message, status: .usage)
  }
}
