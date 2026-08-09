//
//  CommandTests.swift
//  ColorKitCLITests
//
//  **The oracle is this app's own parser**, the same standard `Export/` is held to and
//  for the same reason: the CLI's output is text a machine will read back. So the
//  discriminating assertion is that a printed value survives `CSSColorParser`, not that
//  it matches a string somebody typed into a test. Exact strings are reserved for
//  *syntax* — a `:root` block either has its braces or is not one — and are wrong for
//  anything editorial.
//
//  The conversions, harmonies, ramps and contrast maths underneath are validated in
//  `ColorKitTests` against colorjs.io and against their own defining properties.
//  Nothing here re-tests them; what is tested here is the front end.
//

import Foundation
import Testing

// MARK: - Helpers

/// Requires that everything the command printed is a color this app can read back.
private func expectEveryValueParses(
  _ outcome: CommandOutcome,
  atLeast minimum: Int,
  _ comment: Comment,
  sourceLocation: SourceLocation = #_sourceLocation,
) {
  let values = printedColors(outcome.output)
  #expect(values.count >= minimum, comment, sourceLocation: sourceLocation)
  for value in values {
    #expect(
      CSSColorParser.color(value) != nil,
      "\(comment): “\(value)” did not parse back",
      sourceLocation: sourceLocation,
    )
  }
}

// MARK: - Dispatch

@Suite("Dispatch")
struct DispatchTests {
  @Test("Every listed command is reachable and answers --help on stdout")
  func everyCommandIsReachable() {
    // The listing in `ColorKitCLI.commands` is what `--help` prints, and a command
    // present there but missing from the switch would advertise something that does not
    // run. Driving the list rather than a hand-written one is what keeps the two in step.
    for command in ColorKitCLI.commands {
      let outcome = ColorKitCLI.run([command.name, "--help"])
      #expect(outcome.status == .success, "\(command.name) --help did not succeed")
      #expect(outcome.output == command.usage, "\(command.name) --help printed something else")
      #expect(outcome.diagnostic.isEmpty)
    }
  }

  @Test("Every command's usage text names the command it is for")
  func usageTextIsNotCopied() {
    // Cheap guard against the one mistake a table of nine near-identical entries invites:
    // wiring a command to its neighbour's help.
    for command in ColorKitCLI.commands {
      #expect(command.usage.contains("colorkit \(command.name)"), "\(command.name) usage")
    }
  }

  @Test("--help beats a valid command line but not a broken one")
  func helpDoesNotHideAUsageError() {
    // Checked *after* scanning on purpose. A `--help` that short-circuited first would
    // answer the question and swallow the report about the option that is missing a value.
    #expect(ColorKitCLI.run(["ramp", "red", "--help"]).status == .success)
    #expect(ColorKitCLI.run(["ramp", "--stops", "--help"]).status == .usage)
  }

  @Test("Too few and too many positionals are both usage errors")
  func operandCountIsChecked() {
    #expect(ColorKitCLI.run(["convert"]).status == .usage)
    #expect(ColorKitCLI.run(["convert", "red", "blue"]).status == .usage)
    #expect(ColorKitCLI.run(["contrast", "red"]).status == .usage)
    #expect(ColorKitCLI.run(["contrast", "red", "white", "blue"]).status == .usage)
  }
}

// MARK: - Names

@Suite("The CLI's vocabulary")
struct NameTests {
  @Test("Every catalog format has a name, and the name resolves back to it")
  func formatNamesAreTotalAndInvertible() {
    // Totality is the claim that matters: `Names.name(for:)` is a transcribed table and
    // the catalog is not, so a format added to ColorCore is unreachable from the CLI
    // until someone names it. This fails the moment that happens rather than at the
    // shell, where the symptom is only "that is not a color format".
    for format in CSSOutputFormat.catalog {
      let name = Names.name(for: format)
      #expect(!name.isEmpty)
      #expect(Names.format(named: name) == format, "\(name) did not round-trip")
    }
    #expect(Set(CSSOutputFormat.catalog.map(Names.name(for:))).count
      == CSSOutputFormat.catalog.count)
  }

  @Test("rgb and srgb are different words for different formats")
  func rgbAndSrgbAreNotConflated() {
    // They differ in written scale — `rgb(255 0 0)` against `color(srgb 1 0 0)` — so a
    // table that collapsed them would hand back a near-black that still renders.
    #expect(Names.format(named: "rgb") == .rgb)
    #expect(Names.format(named: "srgb") == .color(.srgb))
  }

  @Test("Every requirement, harmony, shape, template and deficiency is named exactly once")
  func everyEnumeratedNameResolves() {
    for requirement in ContrastRequirement.allCases {
      let label = Names.label(for: requirement)
      #expect(!label.isEmpty, "no label for \(requirement)")
    }
    for entry in Names.requirements {
      #expect(Names.requirement(named: entry.name) == entry.requirement)
    }
    #expect(Set(Names.requirements.map(\.name)).count == ContrastRequirement.allCases.count)

    for harmony in Harmony.allCases {
      #expect(Names.harmony(named: harmony.rawValue) == harmony)
    }
    // Shapes are the one table here that is *not* derived from raw values, so totality
    // is a real claim rather than a tautology: `customProperties` is a SwiftUI
    // identifier, not something anyone should type after `--shape`.
    for shape in ExportShape.allCases {
      let name = Names.name(for: shape)
      let isIdentifier = name.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" }
      #expect(Names.shape(named: name) == shape, "\(name) did not round-trip")
      #expect(isIdentifier, "\(name) is not a CLI identifier")
    }
    #expect(Set(Names.shapes.map(\.name)).count == ExportShape.allCases.count)
    for template in ExportTemplate.allCases {
      #expect(Names.template(named: template.rawValue) == template)
    }
    for deficiency in ColorVisionDeficiency.allCases {
      #expect(Names.deficiency(named: deficiency.rawValue) == deficiency)
    }
    for space in ColorSpace.allCases {
      #expect(Names.space(named: space.rawValue) == space)
    }
  }
}

// MARK: - convert

@Suite("convert")
struct ConvertCommandTests {
  @Test("With --format the answer is one bare value and nothing else")
  func singleFormatOutputIsBare() {
    // The contract behind `$(colorkit convert … --format hex)`. A label, a trailing
    // note or a second line would each break the capture silently.
    let outcome = ColorKitCLI.run(["convert", "#3b82f6", "--format", "oklch"])
    #expect(outcome.status == .success)
    #expect(!outcome.output.contains("\n"))
    #expect(outcome.output.hasPrefix("oklch("))
    #expect(CSSColorParser.color(outcome.output) != nil)
  }

  @Test("Without --format every format that can name the color is listed and parses back")
  func everyListedFormatSurvivesTheParser() {
    let outcome = ColorKitCLI.run(["convert", "#3b82f6"])
    expectEveryValueParses(outcome, atLeast: CSSOutputFormat.catalog.count - 1,
                           "convert lists every catalog format")
  }

  @Test("A color with no keyword drops that row rather than inventing one")
  func keywordIsSkippedWhenThereIsNone() {
    // 148 fixed points cannot name an arbitrary color, and the nearest one would be a
    // lie. The table skips it; asking for it by name is an honest failure.
    let listed = ColorKitCLI.run(["convert", "#3b82f6"])
    #expect(!listed.output.contains("keyword"))

    let asked = ColorKitCLI.run(["convert", "#3b82f6", "--format", "keyword"])
    #expect(asked.status == .failure)
    #expect(asked.output.isEmpty)

    let exists = ColorKitCLI.run(["convert", "#663399", "--format", "keyword"])
    #expect(exists.output == "rebeccapurple")
  }

  @Test("A gamut-mapped value is marked in the table and noted on stderr when asked alone")
  func gamutMappingIsReportedTwoWays() {
    // Two mechanisms and the reason they differ: in the table, *which* formats had to
    // move is the whole information, so each row says so; with `--format` there is only
    // one answer, so stdout stays a bare value and the caveat goes to stderr.
    let wide = "color(display-p3 0 1 0)"

    let table = ColorKitCLI.run(["convert", wide])
    #expect(table.output.contains("(gamut-mapped)"))
    // Not every row: the point is that some formats hold this color and some do not.
    #expect(!table.output.split(separator: "\n").allSatisfy { $0.contains("(gamut-mapped)") })

    let single = ColorKitCLI.run(["convert", wide, "--format", "hex"])
    #expect(!single.output.contains("gamut"))
    #expect(single.diagnostic.contains("brought into gamut"))

    let unbounded = ColorKitCLI.run(["convert", wide, "--format", "oklch"])
    #expect(unbounded.diagnostic.isEmpty)
  }

  @Test("color-mix() and rgb(from …) arrive through convert, which is why neither has a command")
  func theParserIsTheMixCommand() {
    // The decision recorded in `ConvertCommand`: `CSSColorParser` already accepts these
    // as input, so a `mix` subcommand would be a second door into one room. If this ever
    // stops working, that argument stops holding and the CLI is missing a feature.
    let mixed = ColorKitCLI.run(["convert", "color-mix(in oklch, red, blue)",
                                     "--format", "oklch"])
    #expect(mixed.status == .success)
    #expect(CSSColorParser.color(mixed.output) != nil)

    let relative = ColorKitCLI.run(["convert", "rgb(from red calc(r / 2) g b)",
                                        "--format", "rgb"])
    #expect(relative.status == .success)
    #expect(relative.output == "rgb(127.5 0 0)")
  }

  @Test("--precision changes the value's decimals and 11 is refused")
  func precisionIsHonouredAndBounded() {
    let coarse = ColorKitCLI.run(["convert", "#3b82f6", "--format", "oklch",
                                      "--precision", "2"])
    let fine = ColorKitCLI.run(["convert", "#3b82f6", "--format", "oklch",
                                    "--precision", "8"])
    #expect(coarse.output != fine.output)
    #expect(coarse.output.count < fine.output.count)
    #expect(ColorKitCLI.run(["convert", "red", "--precision", "11"]).status == .usage)
  }
}

// MARK: - contrast and solve

@Suite("contrast and solve")
struct ContrastCommandTests {
  @Test("The report names every requirement with its criterion and threshold")
  func theReportIsComplete() {
    let outcome = ColorKitCLI.run(["contrast", "#333333", "#ffffff"])
    #expect(outcome.status == .success)
    #expect(outcome.output.contains("WCAG 2.2"))
    #expect(outcome.output.contains("APCA"))
    for entry in Names.requirements {
      #expect(outcome.output.contains(entry.label))
      #expect(outcome.output.contains(entry.requirement.criterion))
    }
  }

  @Test("Without --require the exit code says nothing about the verdict")
  func aReportIsNotAVerdict() {
    // The two questions a script has to tell apart: did the command run, and do these
    // colors pass. Failing colors reported successfully is the point.
    let failing = ColorKitCLI.run(["contrast", "#777777", "#888888"])
    #expect(failing.status == .success)
    #expect(failing.output.contains("fail"))
  }

  @Test("--require turns the verdict into the exit code, in both directions")
  func requireDecidesTheExitCode() {
    let fails = ColorKitCLI.run(["contrast", "#777777", "#888888", "--require", "aa"])
    #expect(fails.status == .failure)
    #expect(fails.diagnostic.contains("needs 4.5:1"))
    // The report is still on stdout: a check that fails should still show its working.
    #expect(fails.output.contains("WCAG 2.2"))

    let passes = ColorKitCLI.run(["contrast", "#333333", "#ffffff", "--require", "aaa"])
    #expect(passes.status == .success)

    #expect(ColorKitCLI.run(["contrast", "red", "white", "--require", "AA"]).status == .usage)
  }

  @Test("A solved color really meets the target it was solved for")
  func solvedColorsMeetTheirTarget() throws {
    // Asserted as the property rather than as a recorded string, the same standard
    // `Transform/` is held to: the arithmetic can be rewritten and this stays true.
    //
    // **The property is a disjunction, and that is the finding rather than a hedge.**
    // The solver keeps its bracket's passing end, so the answer sits a hair above the
    // target — a margin four decimals can round away. It does, for AA on this input,
    // and at precision 5 it does not, which is what shows this is rounding luck with no
    // default that fixes it. So the claim the CLI can actually keep is: the printed
    // value meets the target, *or* stderr says it no longer does.
    let background = try #require(CSSColorParser.color("#ffffff"))
    for level in ["aa", "aa-large", "aaa"] {
      let outcome = ColorKitCLI.run(["solve", "#3b82f6", "--on", "#ffffff",
                                         "--level", level])
      #expect(outcome.status == .success)
      let value = try #require(printedColors(outcome.output).first)
      let solved = try #require(CSSColorParser.color(value))
      let requirement = try #require(Names.requirement(named: level))
      #expect(solved.meets(requirement, on: background)
        || outcome.diagnostic.contains("reads back a hair under"),
        "\(level): \(value) missed the target and nothing said so")
    }
  }

  @Test("A rounded solution that misses the target says so, and more decimals fix it")
  func roundingAwayTheMarginIsReported() throws {
    // Both halves matter. Without the first, a value that quietly missed would look
    // like an answer; without the second, the note could be unconditional and this
    // whole mechanism would be saying nothing.
    let background = try #require(CSSColorParser.color("#ffffff"))
    let requirement = ContrastRequirement.aaNormalText

    let coarse = ColorKitCLI.run(["solve", "#3b82f6", "--on", "#ffffff",
                                      "--level", "aa", "--precision", "4"])
    let coarseText = try #require(printedColors(coarse.output).first)
    let coarseValue = try #require(CSSColorParser.color(coarseText))
    #expect(!coarseValue.meets(requirement, on: background))
    #expect(coarse.diagnostic.contains("reads back a hair under"))
    #expect(coarse.status == .success, "the color is fine; only its spelling is short")

    let fine = ColorKitCLI.run(["solve", "#3b82f6", "--on", "#ffffff",
                                    "--level", "aa", "--precision", "10"])
    let fineText = try #require(printedColors(fine.output).first)
    let fineValue = try #require(CSSColorParser.color(fineText))
    #expect(fineValue.meets(requirement, on: background))
    #expect(fine.diagnostic.isEmpty)
  }

  @Test("--all reports both directions when both exist and one when only one does")
  func allShowsEveryDirection() {
    // Against a mid-tone background contrast rises in both directions, so there are two
    // answers; against white there is nowhere lighter to go. That the count differs is
    // the cheapest statement that `--all` reports the search rather than a fixed pair.
    let both = ColorKitCLI.run(["solve", "#808080", "--on", "#808080",
                                    "--target", "3", "--all"])
    #expect(both.output.split(separator: "\n").count == 2)
    #expect(both.output.contains("lighter"))
    #expect(both.output.contains("darker"))

    let one = ColorKitCLI.run(["solve", "#3b82f6", "--on", "#ffffff",
                                   "--level", "aaa", "--all"])
    #expect(one.output.split(separator: "\n").count == 1)
  }

  @Test("An unreachable target fails with the ceiling rather than a wrong answer")
  func unreachableTargetsAreExplained() {
    // AAA against a mid-tone is genuinely impossible — the ceiling's own floor is
    // √21 ≈ 4.58 — so this is the failure that has to be reported rather than
    // approximated. AA body text, at 4.5, is always reachable.
    let outcome = ColorKitCLI.run(["solve", "#3b82f6", "--on", "#767676",
                                       "--level", "aaa"])
    #expect(outcome.status == .failure)
    #expect(outcome.output.isEmpty)
    #expect(outcome.diagnostic.contains("the best any color can do"))
  }

  @Test("solve needs a background, and takes only one way of naming its target")
  func solveRejectsAmbiguousArguments() {
    #expect(ColorKitCLI.run(["solve", "red"]).status == .usage)
    #expect(ColorKitCLI.run(["solve", "red", "--on", "white",
                                 "--level", "aa", "--target", "4.5"]).status == .usage)
  }
}

// MARK: - Transforms

@Suite("adjust, harmony, ramp and cvd")
struct TransformCommandTests {
  @Test("adjust answers in OKLCH by default and moves the axis it was given")
  func adjustMovesOneAxis() throws {
    // OKLCH by default for the reason `TransformPanel` adopts with `preferring: .oklch`:
    // a round trip through hex quantizes onto the 8-bit grid, so a small nudge would
    // come back as the color it started from.
    let base = try #require(CSSColorParser.color(
      ColorKitCLI.run(["adjust", "#3b82f6"]).output,
    ))
    let lighter = try #require(CSSColorParser.color(
      ColorKitCLI.run(["adjust", "#3b82f6", "--lightness", "0.1"]).output,
    ))
    #expect(lighter.oklchComponents.lightness > base.oklchComponents.lightness)

    let turned = try #require(CSSColorParser.color(
      ColorKitCLI.run(["adjust", "#3b82f6", "--hue", "180"]).output,
    ))
    let separation = abs(turned.oklchComponents.hue - base.oklchComponents.hue)
    #expect(abs(separation - 180) < 1e-6)
  }

  @Test("Every harmony prints its own keys and every member parses back")
  func harmoniesAreCompleteAndReadable() {
    for harmony in Harmony.allCases {
      let outcome = ColorKitCLI.run(["harmony", "#3b82f6", harmony.rawValue])
      #expect(outcome.status == .success, "\(harmony.rawValue)")
      let lines = outcome.output.split(separator: "\n")
      #expect(lines.count == harmony.count(), "\(harmony.rawValue) member count")
      for key in PaletteNaming.harmonyKeys(harmony) {
        #expect(outcome.output.contains(key), "\(harmony.rawValue) is missing \(key)")
      }
      expectEveryValueParses(outcome, atLeast: harmony.count(), "\(harmony.rawValue)")
    }
  }

  @Test("A hue harmony of a gray says so instead of repeating the gray in silence")
  func achromaticHarmoniesAreExplained() {
    let gray = ColorKitCLI.run(["harmony", "#808080", "triad"])
    #expect(gray.status == .success)
    #expect(gray.diagnostic.contains("no hue"))
    // Monochromatic is a lightness family, so a gray is a perfectly good base for it.
    #expect(ColorKitCLI.run(["harmony", "#808080", "monochromatic"]).diagnostic.isEmpty)
  }

  @Test("An option that only applies to one harmony is refused for the others")
  func inapplicableHarmonyOptionsAreRefused() {
    #expect(ColorKitCLI.run(["harmony", "red", "analogous", "--spread", "40"])
      .status == .success)
    #expect(ColorKitCLI.run(["harmony", "red", "triad", "--spread", "40"])
      .status == .usage)
    #expect(ColorKitCLI.run(["harmony", "red", "monochromatic", "--stops", "7"])
      .status == .success)
    #expect(ColorKitCLI.run(["harmony", "red", "triad", "--stops", "7"])
      .status == .usage)
  }

  @Test("A ramp is eleven Tailwind-keyed stops, all of them inside the gamut")
  func rampStopsAreInGamut() throws {
    // The ramp's whole promise, and the one thing that distinguishes it from a harmony:
    // a set built to be used together cannot contain a member that will not display.
    let outcome = ColorKitCLI.run(["ramp", "#3b82f6"])
    #expect(outcome.status == .success)
    let lines = outcome.output.split(separator: "\n").map(String.init)
    #expect(lines.count == PaletteNaming.tailwindScale.count)
    for (line, key) in zip(lines, PaletteNaming.tailwindScale) {
      #expect(line.hasPrefix(key), "expected \(key), got \(line)")
    }
    // **Read at full precision, because the printed value is not the color.** A stop
    // sitting exactly on the gamut boundary can round *outward* at four decimals —
    // `oklch(0.97 0.0142 259.81)` is 2.3e-5 of chroma past a boundary at 0.014177 — so
    // this assertion at display precision would be measuring the serializer's rounding,
    // not the ramp's clamp, and it fails. At ten decimals what comes back is the
    // `ColorValue` the ramp produced, and *that* is what has to be in gamut.
    for value in printedColors(ColorKitCLI.run(["ramp", "#3b82f6",
                                                    "--precision", "10"]).output)
    {
      let color = try #require(CSSColorParser.color(value))
      #expect(color.inGamut(of: .srgb, epsilon: ColorValue.gamutNoiseTolerance),
              "\(value) left sRGB")
    }

    // And the printed excursion stays inside the recorded worst case — 1.7e-3 of a
    // channel across hues at four decimals, 0.43 of an 8-bit step. Stated as its own
    // assertion rather than as a loosened tolerance on the one above, because the two
    // are different claims and only this one is about display precision.
    for value in printedColors(outcome.output) {
      let color = try #require(CSSColorParser.color(value))
      #expect(color.inGamut(of: .srgb, epsilon: 2e-3), "\(value) left sRGB by more than rounding")
    }
  }

  @Test("An even stop count is rounded up so the base keeps the middle")
  func evenStopCountsAreRoundedUp() {
    #expect(ColorKitCLI.run(["ramp", "red", "--stops", "10"])
      .output.split(separator: "\n").count == 11)
    #expect(ColorKitCLI.run(["ramp", "red", "--stops", "2"]).status == .usage)
    #expect(ColorKitCLI.run(["ramp", "red", "--lightest", "0.2", "--darkest", "0.9"])
      .status == .usage)
  }

  @Test("A wider --gamut lets the ramp keep more chroma")
  func gamutWidensTheRamp() throws {
    // Queried rather than reasoned about: the claim is only that rec2020 holds *this*
    // ramp's chroma where sRGB clamps it, which is what the two outputs differing shows.
    let narrow = ColorKitCLI.run(["ramp", "#3b82f6", "--gamut", "srgb"])
    let wide = ColorKitCLI.run(["ramp", "#3b82f6", "--gamut", "rec2020"])
    #expect(narrow.output != wide.output)
    #expect(ColorKitCLI.run(["ramp", "red", "--gamut", "cmyk"]).status == .usage)

    for value in printedColors(wide.output) {
      let color = try #require(CSSColorParser.color(value))
      #expect(color.inGamut(of: .rec2020, epsilon: ColorValue.gamutNoiseTolerance))
    }
  }

  @Test("cvd simulates all three deficiencies by default, one when named")
  func cvdCoversEveryDeficiency() {
    let all = ColorKitCLI.run(["cvd", "#e11d48"])
    #expect(all.status == .success)
    for deficiency in ColorVisionDeficiency.allCases {
      #expect(all.output.contains(deficiency.rawValue))
    }
    expectEveryValueParses(all, atLeast: ColorVisionDeficiency.allCases.count, "cvd")

    let one = ColorKitCLI.run(["cvd", "#e11d48", "--type", "protanomaly"])
    #expect(one.output.split(separator: "\n").count == 1)
    #expect(ColorKitCLI.run(["cvd", "red", "--type", "monochromacy"]).status == .usage)
  }

  @Test("Severity 0 leaves the color alone and 1 does not")
  func severityIsHonoured() {
    // The cheapest statement that `--severity` reaches the matrix interpolation at all:
    // at zero the simulation is the identity, and a flag that was being dropped would
    // make these two agree.
    let none = ColorKitCLI.run(["cvd", "#e11d48", "--type", "deuteranomaly",
                                    "--severity", "0"])
    let full = ColorKitCLI.run(["cvd", "#e11d48", "--type", "deuteranomaly",
                                    "--severity", "1"])
    #expect(none.output != full.output)
    #expect(ColorKitCLI.run(["cvd", "red", "--severity", "2"]).status == .usage)
  }
}
