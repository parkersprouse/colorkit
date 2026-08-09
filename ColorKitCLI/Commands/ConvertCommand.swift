import Foundation

/// `colorkit convert` — one color, written in one format or in all of them.
///
/// **There is no `mix` command and no `relative` command, and that is not an omission.**
/// `CSSColorParser` already accepts `color-mix(in oklch, red, blue)` and
/// `rgb(from red r g b)` as *input*, so those syntaxes arrive here for free. A
/// subcommand would be a second door into a room that already has one, and it would
/// have to reimplement the grammar to build its arguments back into the string the
/// parser wants anyway.
enum ConvertCommand {
  static let spec = OptionSpec(valued: ["format", "precision"])

  static let usage = """
  Usage: colorkit convert <color> [--format <name>] [--precision <n>]

    Reads any CSS color — including color-mix(), rgb(from …) and calc() — and
    writes it out. With --format the value is printed bare and nothing else, so
    it can be captured directly; without it, every format that can name the color
    is listed.

    --format     One of: \(Names.formatList)
    --precision  Significant decimals, 0–10 (default 4)
  """

  static func run(_ arguments: Arguments) throws(CLIError) -> CommandOutcome {
    try arguments.expect(1, named: "a color")
    let parsed = try ColorArgument.parse(arguments.positionals[0], as: "color")
    let options = try OutputOptions(arguments)

    var outcome = CommandOutcome()
    var notes = ColorArgument.warnings(parsed, as: "color")

    if arguments.value("format") != nil {
      guard let written = parsed.color.formatted(
        as: options.format,
        options: options.formatting,
      ) else {
        // Only `.keyword` can decline, and only because 148 fixed points cannot name
        // an arbitrary color. Answering with the nearest one would be a lie in a tool
        // whose whole job is being exact.
        throw .failure("That color has no CSS keyword.")
      }
      outcome.output = written.css
      if written.isGamutMapped {
        notes.append(
          "Note: the value was brought into gamut to be written as "
            + "\(Names.name(for: options.format)).",
        )
      }
    } else {
      // The table marks each mapped row rather than counting them, because here
      // *which* formats had to move is the information — a count would flatten
      // "hex rounded it, display-p3 did not" into a number.
      let all = parsed.color.allFormats(options: options.formatting)
      let width = all.map { Names.name(for: $0.format).count }.max() ?? 0
      outcome.output = all.map { written in
        PaletteOutput.pad(Names.name(for: written.format), to: width)
          + "  " + written.css
          + (written.isGamutMapped ? "  (gamut-mapped)" : "")
      }.joined(separator: "\n")
    }

    outcome.diagnostic = notes.joined(separator: "\n")
    return outcome
  }
}
