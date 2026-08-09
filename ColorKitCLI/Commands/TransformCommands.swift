import Foundation

/// `colorkit adjust` — one color moved along the three OKLCH axes.
enum AdjustCommand {
  static let spec = OptionSpec(valued: ["lightness", "chroma", "hue", "format", "precision"])

  static let usage = """
  Usage: colorkit adjust <color> [--lightness <delta>] [--chroma <scale>]
                         [--hue <degrees>] [--format <name>] [--precision <n>]

    Adjusts in OKLCH and answers in OKLCH — see --format's default. A result that
    left sRGB is written out as it is rather than pulled back in; the value is the
    honest answer and hex is one flag away if you want the mapped one.

    --lightness  Added to the lightness, -1 to 1
    --chroma     Multiplied into the chroma, 0 or more
    --hue        Added to the hue, in degrees
  """

  static func run(_ arguments: Arguments) throws(CLIError) -> CommandOutcome {
    try arguments.expect(1, named: "a color")
    let parsed = try ColorArgument.parse(arguments.positionals[0], as: "color")
    let options = try OutputOptions(arguments)

    var adjustment = OKLCHAdjustment.identity
    if let delta = try arguments.number("lightness", in: -1 ... 1) {
      adjustment.lightnessDelta = delta
    }
    if let scale = try arguments.number("chroma", in: 0 ... 100) {
      adjustment.chromaScale = scale
    }
    if let rotation = try arguments.number("hue", in: -360 ... 360) {
      adjustment.hueRotation = rotation
    }

    let result = adjustment.applied(to: parsed.color)
    var outcome = CommandOutcome.result(PaletteOutput.css(result, options))
    outcome.diagnostic = (
      ColorArgument.warnings(parsed, as: "color")
        + [PaletteOutput.mappedNote([PaletteEntry(key: "", color: result)], options)]
        .compactMap(\.self),
    ).joined(separator: "\n")
    return outcome
  }
}

/// `colorkit harmony` — a color's relatives, keyed by their role.
enum HarmonyCommand {
  static let spec = OptionSpec(valued: ["spread", "stops"]).adding(OutputOptions.spec)

  static let usage = """
  Usage: colorkit harmony <color> <kind> [--spread <degrees>] [--stops <n>]
                          [--shape <name>] [--format <name>] [--name <family>]
                          [--template <name>] [--precision <n>]

    Kinds: \(Names.harmonyList)

    Hue harmonies turn the hue and leave lightness and chroma alone, so the members
    read as a family — and they are never pulled back into gamut, because a
    "complement" moved to fit sRGB is not the complement. Monochromatic is the
    exception in both respects: it is a lightness family, so it defers to the same
    generator `ramp` uses and every stop is held inside the gamut.

    --spread   Degrees either side of the base (analogous only, default 30)
    --stops    How many shades (monochromatic only, default 5)
    --shape    Render a document instead of a listing. One of: \(Names.shapeList)
  """

  static func run(_ arguments: Arguments) throws(CLIError) -> CommandOutcome {
    try arguments.expect(2, named: "a color and a harmony kind")
    let parsed = try ColorArgument.parse(arguments.positionals[0], as: "color")

    let kindText = arguments.positionals[1]
    guard let harmony = Names.harmony(named: kindText) else {
      throw .usage("“\(kindText)” is not a harmony. Try one of: \(Names.harmonyList).")
    }

    var harmonyOptions = HarmonyOptions.default
    if let spread = try arguments.number("spread", in: 1 ... 180) {
      guard harmony == .analogous else {
        throw .usage("--spread only means something for the analogous harmony.")
      }
      harmonyOptions.analogousSpread = spread
    }
    if let stops = try arguments.integer("stops", in: 3 ... 21) {
      guard harmony == .monochromatic else {
        throw .usage("--stops only means something for the monochromatic harmony.")
      }
      harmonyOptions.monochromaticStops = stops
    }

    let options = try OutputOptions(arguments)
    let colors = parsed.color.harmony(harmony, options: harmonyOptions)
    let keys = PaletteNaming.harmonyKeys(harmony, options: harmonyOptions)
    var outcome = PaletteOutput.render(
      zip(keys, colors).map { PaletteEntry(key: $0, color: $1) },
      options,
    )

    var notes = ColorArgument.warnings(parsed, as: "color")
    if parsed.color.isAchromatic, harmony.hueOffsets(options: harmonyOptions) != nil {
      // Arithmetic being honest rather than a bug: there is no third color related to
      // a gray by 120°. Saying so beats printing the same gray three times in silence.
      notes.append("Note: that color has no hue, so every member of a hue harmony is the same.")
    }
    outcome.diagnostic = (notes + [outcome.diagnostic]).filter { !$0.isEmpty }
      .joined(separator: "\n")
    return outcome
  }
}

/// `colorkit ramp` — a shade scale built around a color.
enum RampCommand {
  static let spec = OptionSpec(valued: ["stops", "lightest", "darkest", "taper", "gamut"])
    .adding(OutputOptions.spec)

  static let usage = """
  Usage: colorkit ramp <color> [--stops <n>] [--lightest <l>] [--darkest <l>]
                       [--taper <t>] [--gamut <space>] [--shape <name>]
                       [--format <name>] [--name <family>] [--precision <n>]

    Eleven stops by default, keyed the way Tailwind numbers them, lightest first.
    Every stop is held inside the gamut — a ramp is a set built to be used together,
    so one member that cannot be displayed spoils it.

    --stops    3 to 21; an even count is rounded up so the base keeps the middle
    --lightest OKLCH lightness of the first stop (default 0.97)
    --darkest  OKLCH lightness of the last stop (default 0.18)
    --taper    How much chroma falls off toward the ends, 0 to 1 (default 0.5)
    --gamut    The gamut every stop is held inside. One of: \(Names.spaceList)
    --shape    Render a document instead of a listing. One of: \(Names.shapeList)
  """

  static func run(_ arguments: Arguments) throws(CLIError) -> CommandOutcome {
    try arguments.expect(1, named: "a color")
    let parsed = try ColorArgument.parse(arguments.positionals[0], as: "color")

    var ramp = ShadeRamp.default
    if let stops = try arguments.integer("stops", in: 3 ... 21) {
      ramp.stops = stops
    }
    if let lightest = try arguments.number("lightest", in: 0 ... 1) {
      ramp.lightest = lightest
    }
    if let darkest = try arguments.number("darkest", in: 0 ... 1) {
      ramp.darkest = darkest
    }
    guard ramp.darkest < ramp.lightest else {
      throw .usage("--darkest must be below --lightest.")
    }
    if let taper = try arguments.number("taper", in: 0 ... 1) {
      ramp.chromaTaper = taper
    }
    if let text = arguments.value("gamut") {
      guard let space = Names.space(named: text) else {
        throw .usage("“\(text)” is not a color space. Try one of: \(Names.spaceList).")
      }
      ramp.gamut = space
    }

    let options = try OutputOptions(arguments)
    let colors = ramp.generated(from: parsed.color)
    let keys = PaletteNaming.rampKeys(count: colors.count)
    var outcome = PaletteOutput.render(
      zip(keys, colors).map { PaletteEntry(key: $0, color: $1) },
      options,
    )
    outcome.diagnostic = (ColorArgument.warnings(parsed, as: "color") + [outcome.diagnostic])
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
    return outcome
  }
}
