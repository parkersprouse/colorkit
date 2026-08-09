import Foundation

/// `colorkit cvd` — a color as color vision deficiencies render it.
enum VisionCommand {
  static let spec = OptionSpec(valued: ["type", "severity"]).adding(OutputOptions.spec)

  static let usage = """
  Usage: colorkit cvd <color> [--type <name>] [--severity <s>]
                      [--shape <name>] [--format <name>] [--precision <n>]

    Simulates Machado's model in linear RGB — the matrices are applied to
    linearized channels and the result re-encoded, which is what makes the answer
    right rather than merely plausible.

    --type      One of: \(Names.deficiencyList)  (default: all three)
    --severity  0 to 1, where 1 is the strongest simulated (default 1)
    --shape     Render a document instead of a listing. One of: \(Names.shapeList)
  """

  static func run(_ arguments: Arguments) throws(CLIError) -> CommandOutcome {
    try arguments.expect(1, named: "a color")
    let parsed = try ColorArgument.parse(arguments.positionals[0], as: "color")

    var deficiencies = ColorVisionDeficiency.allCases
    if let text = arguments.value("type") {
      guard let deficiency = Names.deficiency(named: text) else {
        throw .usage("“\(text)” is not a deficiency. Try one of: \(Names.deficiencyList).")
      }
      deficiencies = [deficiency]
    }
    let severity = try arguments.number("severity", in: 0 ... 1) ?? 1

    let options = try OutputOptions(arguments)
    let entries = deficiencies.map { deficiency in
      PaletteEntry(
        key: deficiency.rawValue,
        color: parsed.color.simulating(deficiency, severity: severity),
      )
    }

    var outcome = PaletteOutput.render(entries, options)
    outcome.diagnostic = (ColorArgument.warnings(parsed, as: "color") + [outcome.diagnostic])
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
    return outcome
  }
}
