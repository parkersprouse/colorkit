import Foundation

/// The CLI's front door: argv in, an outcome out, and no I/O anywhere below it.
///
/// A second front end over `ColorCore`, and the last milestone on purpose — it exposes
/// a finished core rather than being revised by every feature added above it. Everything
/// the app's panels do with color is reachable here except the two things that are not
/// color: the eyedropper, which is `NSColorSampler`, and saved projects, which are
/// SwiftData. Neither lives in `ColorCore`, so neither could come along.
enum ColorKitCLI {
  // MARK: Internal

  /// Kept in step with the app's `MARKETING_VERSION` by hand. Reaching a build setting
  /// from a `.swift` file needs a generated header, which is a lot of machinery for a
  /// version banner.
  static let version = "1.0"

  static let commands: [(name: String, summary: String, usage: String)] = [
    ("convert", "Write a color in one format, or in all of them", ConvertCommand.usage),
    ("contrast", "Measure WCAG 2.2 and APCA contrast for a pair", ContrastCommand.usage),
    ("solve", "Find the nearest color that meets a contrast target", SolveCommand.usage),
    ("adjust", "Move a color along the OKLCH axes", AdjustCommand.usage),
    ("harmony", "Derive a color's relatives", HarmonyCommand.usage),
    ("ramp", "Build a shade scale around a color", RampCommand.usage),
    ("cvd", "Simulate color vision deficiencies", VisionCommand.usage),
    ("export", "Write named colors as a stylesheet or config", ExportCommand.usage),
    ("tokens", "Read a W3C design token file", TokensCommand.usage),
  ]

  static var help: String {
    let width = commands.map(\.name.count).max() ?? 0
    let list = commands.map { command in
      "  " + PaletteOutput.pad(command.name, to: width) + "  " + command.summary
    }.joined(separator: "\n")

    return """
    colorkit \(version) — CSS colors from the command line.

    Usage: colorkit <command> [arguments]

    \(list)

    Any command takes --help for its own arguments. Results go to stdout and
    everything else to stderr, so a value can be captured directly:

      colorkit convert "color-mix(in oklch, red, blue)" --format hex

    Exit codes: 0 success, 1 the command ran and failed, 2 the command line was wrong.
    """
  }

  static func run(_ arguments: [String]) -> CommandOutcome {
    guard let name = arguments.first else {
      // No arguments is a misuse, not a request for help — so the text goes to stderr
      // and the status is `.usage`. `colorkit --help` is the request, and that one
      // prints to stdout and succeeds.
      return .misused(help)
    }

    if name == "--help" || name == "-h" || name == "help" {
      return .result(help)
    }
    if name == "--version" {
      return .result("colorkit \(version)")
    }

    let rest = Array(arguments.dropFirst())
    do {
      switch name {
      case "convert": return try dispatch(rest, ConvertCommand.spec, ConvertCommand.usage,
                                          ConvertCommand.run)
      case "contrast": return try dispatch(rest, ContrastCommand.spec, ContrastCommand.usage,
                                           ContrastCommand.run)
      case "solve": return try dispatch(rest, SolveCommand.spec, SolveCommand.usage,
                                        SolveCommand.run)
      case "adjust": return try dispatch(rest, AdjustCommand.spec, AdjustCommand.usage,
                                         AdjustCommand.run)
      case "harmony": return try dispatch(rest, HarmonyCommand.spec, HarmonyCommand.usage,
                                          HarmonyCommand.run)
      case "ramp": return try dispatch(rest, RampCommand.spec, RampCommand.usage,
                                       RampCommand.run)
      case "cvd": return try dispatch(rest, VisionCommand.spec, VisionCommand.usage,
                                      VisionCommand.run)
      case "export": return try dispatch(rest, ExportCommand.spec, ExportCommand.usage,
                                         ExportCommand.run)
      case "tokens": return try dispatch(rest, TokensCommand.spec, TokensCommand.usage,
                                         TokensCommand.run)
      default:
        return .misused("“\(name)” is not a colorkit command.\n\n" + help)
      }
    } catch {
      return error.outcome
    }
  }

  // MARK: Private

  /// Scans a command's arguments and runs it, answering `--help` before either.
  ///
  /// Help is checked after scanning rather than before, so `colorkit ramp --stops --help`
  /// still reports the missing value — a `--help` that swallowed a broken command line
  /// would hide the thing it was asked about.
  private static func dispatch(
    _ raw: [String],
    _ spec: OptionSpec,
    _ usage: String,
    _ body: (Arguments) throws(CLIError) -> CommandOutcome,
  ) throws(CLIError) -> CommandOutcome {
    let arguments = try Arguments(raw, spec: spec)
    if arguments.wantsHelp {
      return .result(usage)
    }
    return try body(arguments)
  }
}
