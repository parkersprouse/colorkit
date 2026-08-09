//
//  ArgumentTests.swift
//  ColorKitCLITests
//
//  The scanner and the exit-code contract. Neither has an oracle and neither needs
//  one — both are decisions this CLI makes, so what the tests pin is that each
//  decision is *reachable* and that the ones meant to differ actually do.
//

import Foundation
import Testing

@Suite("Argument scanning")
struct ArgumentScanningTests {
  // MARK: Internal

  @Test("Positionals keep their order and options are lifted out from between them")
  func positionalsKeepOrder() throws {
    let arguments = try Self.scan(["red", "--format", "hex", "blue", "--all"])
    #expect(arguments.positionals == ["red", "blue"])
    #expect(arguments.value("format") == "hex")
    #expect(arguments.flag("all"))
  }

  @Test("--name=value and --name value are the same thing")
  func inlineValuesMatchSeparatedOnes() throws {
    #expect(try Self.scan(["--format=hex"]).value("format") == "hex")
    #expect(try Self.scan(["--format", "hex"]).value("format") == "hex")
  }

  @Test("An unknown option is a usage error, never a positional")
  func unknownOptionIsRejected() {
    // The whole reason `OptionSpec` exists. Accepting `--formt hex` silently would
    // leave a typo looking like a working command whose answer is in the wrong format.
    #expect(throws: CLIError.usage("Unknown option “--formt”.")) {
      try Self.scan(["red", "--formt", "hex"])
    }
  }

  @Test("An option at the end of the line with nothing after it is a usage error")
  func missingValueIsRejected() {
    #expect(throws: CLIError.usage("--format needs a value.")) {
      try Self.scan(["red", "--format"])
    }
  }

  @Test("A flag given a value, and a value given twice, are both usage errors")
  func malformedOptionsAreRejected() {
    #expect(throws: CLIError.usage("--all is a flag and takes no value.")) {
      try Self.scan(["--all=yes"])
    }
    #expect(throws: CLIError.usage("--format was given more than once.")) {
      try Self.scan(["--format", "hex", "--format", "rgb"])
    }
    #expect(throws: CLIError.usage("--all was given more than once.")) {
      try Self.scan(["--all", "--all"])
    }
  }

  @Test("-- ends option scanning")
  func doubleHyphenEndsOptions() throws {
    let arguments = try Self.scan(["--", "--format"])
    #expect(arguments.positionals == ["--format"])
    #expect(arguments.value("format") == nil)
  }

  @Test("--help and -h are accepted without any command listing them")
  func helpIsUniversal() throws {
    #expect(try Self.scan(["--help"]).wantsHelp)
    #expect(try Self.scan(["-h"]).wantsHelp)
    #expect(try !Self.scan([]).wantsHelp)
  }

  @Test("A number outside its range names the range rather than failing to convert")
  func numbersAreRangeChecked() throws {
    let spec = OptionSpec(valued: ["severity", "stops"])
    #expect(try Arguments(["--severity", "0.5"], spec: spec).number("severity", in: 0 ... 1) == 0.5)
    #expect(throws: (any Error).self) {
      try Arguments(["--severity", "2"], spec: spec).number("severity", in: 0 ... 1)
    }
    #expect(throws: (any Error).self) {
      try Arguments(["--severity", "loud"], spec: spec).number("severity")
    }
    #expect(throws: (any Error).self) {
      try Arguments(["--stops", "2.5"], spec: spec).integer("stops")
    }
  }

  // MARK: Private

  private static let spec = OptionSpec(flags: ["all"], valued: ["format", "name"])

  private static func scan(_ raw: [String]) throws -> Arguments {
    try Arguments(raw, spec: spec)
  }
}

@Suite("Exit codes and streams")
struct ExitCodeTests {
  @Test("The three statuses are three different codes")
  func statusesAreDistinct() {
    // Stated as the numbers rather than as inequalities, because these are a contract
    // with whatever shell script calls this and changing one silently is the failure.
    #expect(CommandOutcome.Status.success.code == 0)
    #expect(CommandOutcome.Status.failure.code == 1)
    #expect(CommandOutcome.Status.usage.code == 2)
  }

  @Test("A wrong command line and a failed command are told apart")
  func usageAndFailureAreSeparate() {
    // The distinction that would vanish if the two arms of `CLIError` were merged:
    // both of these "fail", and only one of them is fixed by editing the command line.
    #expect(ColorKitCLI.run(["convert", "red", "--nope"]).status == .usage)
    #expect(ColorKitCLI.run(["convert", "notacolor"]).status == .failure)
    #expect(ColorKitCLI.run(["convert", "red", "--format", "hex"]).status == .success)
  }

  @Test("Results go to stdout and everything else to stderr")
  func streamsAreSeparate() {
    // The claim that makes `$(colorkit convert red --format hex)` usable: a run that
    // fails must put *nothing* on stdout, or the capture succeeds with garbage in it.
    let failed = ColorKitCLI.run(["convert", "notacolor"])
    #expect(failed.output.isEmpty)
    #expect(!failed.diagnostic.isEmpty)

    let misused = ColorKitCLI.run(["convert"])
    #expect(misused.output.isEmpty)
    #expect(!misused.diagnostic.isEmpty)
  }

  @Test("A warning reaches stderr without touching the exit code or stdout")
  func warningsDoNotContaminateTheResult() {
    // `rgb()` accepts commas, `oklch()` does not — the parser takes it anyway and says
    // so. That "said so" has to land on stderr: a warning is not a failure, and a
    // pipeline that received it on stdout would be reading prose as a color.
    let outcome = ColorKitCLI.run(["convert", "oklch(0.7, 0.1, 250)", "--format", "hex"])
    #expect(outcome.status == .success)
    #expect(outcome.diagnostic.contains("does not accept commas"))
    // One line, and that line is the color: the warning did not leak across.
    #expect(!outcome.output.contains("\n"))
    #expect(CSSColorParser.color(outcome.output) != nil)
  }

  @Test("No arguments is a misuse; --help is a request")
  func helpAndEmptinessDiffer() {
    // Same text, opposite streams and opposite codes. `colorkit | head` should not
    // look like a success, and `colorkit --help > x` should not write an empty file.
    let empty = ColorKitCLI.run([])
    #expect(empty.status == .usage)
    #expect(empty.output.isEmpty)

    let help = ColorKitCLI.run(["--help"])
    #expect(help.status == .success)
    #expect(help.diagnostic.isEmpty)
    #expect(help.output == empty.diagnostic)
  }

  @Test("An unknown command is a usage error and prints the list of real ones")
  func unknownCommandIsRejected() {
    let outcome = ColorKitCLI.run(["bogus"])
    #expect(outcome.status == .usage)
    for command in ColorKitCLI.commands {
      #expect(outcome.diagnostic.contains(command.name))
    }
  }
}
