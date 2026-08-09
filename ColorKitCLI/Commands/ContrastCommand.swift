import Foundation

/// `colorkit contrast` — what a pair of colors measures, and optionally whether it passes.
enum ContrastCommand {
  static let spec = OptionSpec(valued: ["require"])

  static let usage = """
  Usage: colorkit contrast <foreground> <background> [--require <level>]

    Reports WCAG 2.2 and APCA contrast for the pair, then every requirement and
    whether it is met.

    --require  Exit non-zero unless this level passes. One of: \(Names.requirementList)
  """

  static func run(_ arguments: Arguments) throws(CLIError) -> CommandOutcome {
    try arguments.expect(2, named: "a foreground and a background color")
    let foreground = try ColorArgument.parse(arguments.positionals[0], as: "foreground color")
    let background = try ColorArgument.parse(arguments.positionals[1], as: "background color")

    var required: ContrastRequirement?
    if let text = arguments.value("require") {
      guard let requirement = Names.requirement(named: text) else {
        throw .usage("“\(text)” is not a contrast level. Try one of: \(Names.requirementList).")
      }
      required = requirement
    }

    let ratio = foreground.color.contrastRatio(with: background.color)
    let lc = foreground.color.apcaContrast(on: background.color)

    var lines = [
      "WCAG 2.2  \(Numbers.fixed(ratio, 2)):1",
      // APCA is signed: the polarity says which of the two is lighter, and dropping
      // the sign would throw away half of what the number means.
      "APCA      Lc \(Numbers.fixed(lc, 1))",
    ]

    let width = Names.requirements.map(\.label.count).max() ?? 0
    for entry in Names.requirements {
      let passes = foreground.color.meets(entry.requirement, on: background.color)
      lines.append(
        PaletteOutput.pad(entry.label, to: width)
          + "  " + (passes ? "pass" : "fail")
          + "  (\(entry.requirement.criterion), needs "
          + "\(Numbers.trimmed(entry.requirement.minimumRatio, 2)):1)",
      )
    }

    var outcome = CommandOutcome.result(lines.joined(separator: "\n"))
    outcome.diagnostic = (
      ColorArgument.warnings(foreground, as: "foreground color")
        + ColorArgument.warnings(background, as: "background color"),
    ).joined(separator: "\n")

    // **The exit code only carries a verdict when one was asked for.** Without
    // `--require` this command is a report, and making a report exit non-zero because
    // of what it found would merge two questions — "did the command run" and "do these
    // colors pass" — that a script needs to tell apart.
    if let required, !foreground.color.meets(required, on: background.color) {
      outcome.status = .failure
      let shortfall = "\(Names.label(for: required)) needs "
        + "\(Numbers.trimmed(required.minimumRatio, 2)):1, measured \(Numbers.fixed(ratio, 2)):1."
      outcome.diagnostic = outcome.diagnostic.isEmpty
        ? shortfall
        : outcome.diagnostic + "\n" + shortfall
    }
    return outcome
  }
}

/// `colorkit solve` — the nearest color that reaches a contrast target.
enum SolveCommand {
  static let spec = OptionSpec(
    flags: ["all"],
    valued: ["on", "level", "target", "format", "precision"],
  )

  static let usage = """
  Usage: colorkit solve <color> --on <background> [--level <level> | --target <ratio>]
                        [--all] [--format <name>] [--precision <n>]

    Moves the color's OKLCH lightness — and only its lightness, so the hue and
    chroma that make it that color survive — until it meets the target against
    the given background.

    --on       The background to solve against (required)
    --level    A WCAG level. One of: \(Names.requirementList)  (default aa)
    --target   A raw ratio, such as 4.5. Cannot be combined with --level
    --all      Print both the lighter and the darker answer, not just the nearest
    --format   One of: \(Names.formatList)
  """

  static func run(_ arguments: Arguments) throws(CLIError) -> CommandOutcome {
    try arguments.expect(1, named: "a color")
    let color = try ColorArgument.parse(arguments.positionals[0], as: "color")

    guard let backgroundText = arguments.value("on") else {
      throw .usage("solve needs a background — pass --on <color>.")
    }
    let background = try ColorArgument.parse(backgroundText, as: "background color")

    guard arguments.value("level") == nil || arguments.value("target") == nil else {
      throw .usage("--level and --target say the same thing two ways; pass one.")
    }

    let target: Double
    if let raw = try arguments.number("target", in: 1 ... 21) {
      target = raw
    } else if let text = arguments.value("level") {
      guard let requirement = Names.requirement(named: text) else {
        throw .usage("“\(text)” is not a contrast level. Try one of: \(Names.requirementList).")
      }
      target = requirement.minimumRatio
    } else {
      target = ContrastRequirement.aaNormalText.minimumRatio
    }

    let options = try OutputOptions(arguments)
    let solutions = ContrastSolver.solutions(
      for: color.color,
      on: background.color,
      target: target,
    )

    guard !solutions.isEmpty else {
      // The ceiling distinguishes the two ways this fails, and they want different
      // answers from whoever asked: no color at all can reach the target here, or
      // this color's chroma and hue cannot while its lightness alone moves.
      let ceiling = ContrastSolver.ceiling(against: background.color)
      throw .failure(
        ceiling < target
          ? "Nothing reaches \(Numbers.trimmed(target, 2)):1 on that background — "
          + "the best any color can do is \(Numbers.fixed(ceiling, 2)):1."
          : "No lightness of that color reaches \(Numbers.trimmed(target, 2)):1 on "
          + "that background, though some color does.",
      )
    }

    let chosen = arguments.flag("all")
      ? solutions
      : [solutions.min { abs($0.lightnessDelta) < abs($1.lightnessDelta) }!]

    let width = chosen.map(\.direction.rawValue.count).max() ?? 0
    let written = chosen.map { ($0, PaletteOutput.css($0.color, options)) }
    var outcome = CommandOutcome.result(written.map { solution, css in
      PaletteOutput.pad(solution.direction.rawValue, to: width)
        + "  " + css
        + "  " + Numbers.fixed(solution.ratio, 2) + ":1"
    }.joined(separator: "\n"))

    var notes = ColorArgument.warnings(color, as: "color")
      + ColorArgument.warnings(background, as: "background color")

    // **The solver's guarantee is about the color; this text is about the string.** The
    // search keeps its bracket's passing end, so the answer lands a hair *above* the
    // target — which is exactly the margin serializing at four decimals can round away.
    // Measured on one input, the printed value meets AA at precision 5, 7, 8 and 10 and
    // misses it at 4 and 6, so this is rounding luck rather than a threshold and there
    // is no default precision that fixes it. Biasing the rounding would make this
    // command's output disagree with every other one, so instead the value is read back
    // and checked with the same predicate the caller would use.
    let lost = written.filter { _, css in
      guard let readBack = CSSColorParser.color(css) else { return true }
      return readBack.contrastRatio(with: background.color) < target
    }
    if !lost.isEmpty {
      notes.append(
        "Note: written to \(options.formatting.precision) decimals, the "
          + lost.map(\.0.direction.rawValue).joined(separator: " and ")
          + " value reads back a hair under \(Numbers.trimmed(target, 2)):1. "
          + "The color meets the target; raise --precision to keep that true of the text.",
      )
    }

    outcome.diagnostic = notes.joined(separator: "\n")
    return outcome
  }
}
