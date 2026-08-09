import Foundation

/// How a command failed, kept separate from *what* a command produced.
///
/// The two arms map onto the two non-zero exit codes and mean different things to
/// whoever is scripting this: `.usage` says the command line is wrong, `.failure` says
/// the command line was fine and the work did not succeed.
enum CLIError: Error, Equatable {
  case usage(String)
  case failure(String)

  // MARK: Internal

  var outcome: CommandOutcome {
    switch self {
    case let .usage(message): .misused(message)
    case let .failure(message): .failed(message)
    }
  }
}

/// Which options a command accepts, declared up front.
///
/// Without this split, scanning is ambiguous: `--all hex` could be a flag followed by a
/// positional or an option and its value, and nothing in the text says which. Declaring
/// the two sets is what lets the scanner reject an unknown option instead of guessing —
/// and an unknown option accepted silently is a typo that changes the answer.
struct OptionSpec {
  // MARK: Lifecycle

  init(flags: Set<String> = [], valued: Set<String> = []) {
    // `--help` is accepted everywhere, so no command has to remember to list it.
    self.flags = flags.union(["help"])
    self.valued = valued
  }

  // MARK: Internal

  let flags: Set<String>
  let valued: Set<String>

  /// This spec plus another's options, so a command that takes the shared output
  /// options declares them by reference rather than retyping five names.
  func adding(_ other: OptionSpec) -> OptionSpec {
    OptionSpec(flags: flags.union(other.flags), valued: valued.union(other.valued))
  }
}

/// A scanned command line: positionals in order, options by name.
struct Arguments {
  // MARK: Lifecycle

  /// Splits `raw` into positionals and options, rejecting anything `spec` does not list.
  ///
  /// `--` ends option scanning, so a positional beginning with a hyphen is still
  /// reachable. Nothing in CSS starts with one, but the convention costs one line and
  /// its absence is the kind of thing that only bites at 2am.
  init(_ raw: [String], spec: OptionSpec) throws(CLIError) {
    var index = 0
    var optionsEnded = false

    while index < raw.count {
      let argument = raw[index]
      index += 1

      if optionsEnded || !argument.hasPrefix("-") {
        positionals.append(argument)
        continue
      }

      if argument == "--" {
        optionsEnded = true
        continue
      }

      // The one short form. Everything else is spelled out, because a CLI nobody uses
      // daily is one whose abbreviations have to be looked up anyway.
      if argument == "-h" {
        flags.insert("help")
        continue
      }

      guard argument.hasPrefix("--"), argument.count > 2 else {
        throw .usage("Unknown option “\(argument)”.")
      }

      let body = String(argument.dropFirst(2))
      let name: String
      var inlineValue: String?
      if let separator = body.firstIndex(of: "=") {
        name = String(body[body.startIndex ..< separator])
        inlineValue = String(body[body.index(after: separator)...])
      } else {
        name = body
      }

      if spec.flags.contains(name) {
        guard inlineValue == nil else {
          throw .usage("--\(name) is a flag and takes no value.")
        }
        guard flags.insert(name).inserted else {
          throw .usage("--\(name) was given more than once.")
        }
        continue
      }

      guard spec.valued.contains(name) else {
        throw .usage("Unknown option “--\(name)”.")
      }
      guard values[name] == nil else {
        throw .usage("--\(name) was given more than once.")
      }

      if let inlineValue {
        values[name] = inlineValue
        continue
      }
      guard index < raw.count else {
        throw .usage("--\(name) needs a value.")
      }
      values[name] = raw[index]
      index += 1
    }
  }

  // MARK: Internal

  private(set) var positionals: [String] = []

  var wantsHelp: Bool {
    flags.contains("help")
  }

  func flag(_ name: String) -> Bool {
    flags.contains(name)
  }

  func value(_ name: String) -> String? {
    values[name]
  }

  /// The value of `name` as a number, or `nil` when it was not given.
  ///
  /// `range` is checked here rather than by each caller so the message says the bound
  /// once and says it the same way every time.
  func number(
    _ name: String,
    in range: ClosedRange<Double>? = nil,
  ) throws(CLIError) -> Double? {
    guard let text = values[name] else { return nil }
    guard let parsed = Double(text), parsed.isFinite else {
      throw .usage("--\(name) needs a number, got “\(text)”.")
    }
    if let range, !range.contains(parsed) {
      throw .usage("--\(name) must be between \(range.lowerBound) and \(range.upperBound).")
    }
    return parsed
  }

  func integer(
    _ name: String,
    in range: ClosedRange<Int>? = nil,
  ) throws(CLIError) -> Int? {
    guard let text = values[name] else { return nil }
    guard let parsed = Int(text) else {
      throw .usage("--\(name) needs a whole number, got “\(text)”.")
    }
    if let range, !range.contains(parsed) {
      throw .usage("--\(name) must be between \(range.lowerBound) and \(range.upperBound).")
    }
    return parsed
  }

  /// Requires exactly `count` positionals, naming them in the message when there are not.
  func expect(_ count: Int, named names: String) throws(CLIError) {
    guard positionals.count == count else {
      throw .usage(
        positionals.count < count
          ? "Missing \(names)."
          : "Too many arguments — expected \(names).",
      )
    }
  }

  // MARK: Private

  private var flags: Set<String> = []
  private var values: [String: String] = [:]
}
