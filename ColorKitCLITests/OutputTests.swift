//
//  OutputTests.swift
//  ColorKitCLITests
//
//  The shared output options — which of them mean anything together, and what happens
//  to the ones that do not — plus the two commands whose input is not a color.
//

import Foundation
import Testing

@Suite("Shared output options")
struct OutputOptionTests {
  @Test("Every export shape renders, and every color in it parses back")
  func everyShapeSurvivesTheParser() {
    // Both cardinalities, because `json` and `tailwindConfig` fork on a lone color
    // versus a scale and a single-entry test happily passes a broken multi-entry branch.
    for shape in ExportShape.allCases {
      let name = Names.name(for: shape)
      for command in [["ramp", "#3b82f6"], ["harmony", "#3b82f6", "complementary"]] {
        let outcome = ColorKitCLI.run(command + ["--shape", name])
        #expect(outcome.status == .success, "\(name) via \(command[0])")

        // `designTokens` (M34) writes no CSS at all — a `$value` is a JSON object of
        // raw numbers, so `printedColors`/`CSSColorParser` would find nothing and
        // this loop would need to special-case an empty result rather than prove
        // anything. The oracle for this one shape is this app's own decoder instead,
        // the same substitution `ExportRoundTripTests` makes in the app-side suite.
        if shape == .designTokens {
          guard let data = outcome.output.data(using: .utf8),
                let document = try? DesignTokenImport.decode(data)
          else {
            Issue.record("\(name) via \(command[0]) did not decode as tokens: \(outcome.output)")
            continue
          }
          #expect(!document.colors.isEmpty, "\(name) via \(command[0]) wrote no tokens")
          continue
        }

        let values = printedColors(outcome.output)
        #expect(!values.isEmpty, "\(name) via \(command[0]) wrote no values")
        for value in values {
          #expect(CSSColorParser.color(value) != nil,
                  "\(name): “\(value)” did not parse back")
        }
      }
    }
  }

  @Test("An option the chosen shape would ignore is refused, not silently dropped")
  func inertOptionsAreRefused() {
    // The CLI's version of the export panel hiding its Format picker. `p3WithFallback`
    // fixes both its formats — honouring a picker there would put an unbounded `oklch()`
    // into the block a browser reaches precisely when it *cannot* do wide gamut — and a
    // `--format` that changed nothing would look like it had worked.
    #expect(ColorKitCLI.run(["ramp", "red", "--shape", "p3-with-fallback",
                             "--format", "hex"]).status == .usage)
    #expect(ColorKitCLI.run(["ramp", "red", "--shape", "p3-with-fallback"])
      .status == .success)

    // `usesName` and `usesTemplate` are complements: a bare declaration has nowhere to
    // put a family name, and a shape that writes its own properties has no template slot.
    #expect(ColorKitCLI.run(["ramp", "red", "--shape", "declaration",
                             "--name", "brand"]).status == .usage)
    #expect(ColorKitCLI.run(["ramp", "red", "--shape", "declaration",
                             "--template", "border"]).status == .success)
    #expect(ColorKitCLI.run(["ramp", "red", "--shape", "custom-properties",
                             "--template", "border"]).status == .usage)
    #expect(ColorKitCLI.run(["ramp", "red", "--shape", "custom-properties",
                             "--name", "brand"]).status == .success)

    // Without a shape there is no document at all, so both are inert.
    #expect(ColorKitCLI.run(["ramp", "red", "--name", "brand"]).status == .usage)
    #expect(ColorKitCLI.run(["ramp", "red", "--template", "border"]).status == .usage)
  }

  @Test("--name reaches the document it names")
  func nameReachesTheOutput() {
    let outcome = ColorKitCLI.run(["ramp", "#3b82f6", "--shape", "custom-properties",
                                   "--name", "accent"])
    #expect(outcome.output.contains("--accent-50:"))
    #expect(!outcome.output.contains("--brand-"))
    #expect(ColorKitCLI.run(["ramp", "red", "--shape", "json", "--name", " "])
      .status == .usage)
  }

  @Test("The mapped note counts against the format the values are written in")
  func theMappedNoteFollowsTheFormat() {
    // One predicate decides this and the value beside it, so the two cannot disagree.
    // hex cannot represent an out-of-gamut color at all; oklch is unbounded and never
    // moves one — which is why the same command says different things under each.
    let hex = ColorKitCLI.run(["harmony", "color(display-p3 0 1 0)", "triad",
                               "--format", "hex"])
    #expect(hex.diagnostic.contains("brought into gamut"))
    #expect(hex.diagnostic.contains("hex"))

    let oklch = ColorKitCLI.run(["harmony", "color(display-p3 0 1 0)", "triad",
                                 "--format", "oklch"])
    #expect(oklch.diagnostic.isEmpty)
  }

  @Test("A p3-with-fallback note counts against its hex fallback, not its wide block")
  func theP3NoteCountsTheFallback() {
    // The decision `ExportOptions.mappedCountFormat` exists for: counting against the
    // media block would report nothing mapped while the hex line right underneath has
    // been rounded. This is the CLI reading the same answer rather than a second rule.
    let outcome = ColorKitCLI.run(["harmony", "color(display-p3 0 1 0)", "triad",
                                   "--shape", "p3-with-fallback"])
    #expect(outcome.status == .success)
    #expect(outcome.diagnostic.contains("brought into gamut"))
    #expect(outcome.diagnostic.contains("hex"))
  }

  @Test("A listing puts nothing but keys and values on stdout")
  func listingsStayParseable() {
    // What makes `colorkit ramp red | awk '{print $2}'` work. The mapped note is the
    // thing most likely to end up here by accident, so it is the one checked for — and
    // a *harmony* is what produces one, because harmonies are never gamut-mapped where
    // every ramp stop already is. Asking a ramp for this would have tested nothing.
    let outcome = ColorKitCLI.run(["harmony", "color(display-p3 0 1 0)", "triad",
                                   "--format", "hex"])
    #expect(!outcome.diagnostic.isEmpty)
    for line in outcome.output.split(separator: "\n") {
      let fields = line.split(separator: " ").filter { !$0.isEmpty }
      #expect(fields.count == 2, "unexpected extra field in “\(line)”")
      #expect(CSSColorParser.color(String(fields[1])) != nil)
    }
  }
}

@Suite("export")
struct ExportCommandTests {
  @Test("Bare colors are keyed by position and key=color names them")
  func keysComeFromTheCommandLine() {
    let positional = ColorKitCLI.run(["export", "red", "blue"])
    #expect(positional.output.contains("--brand-1:"))
    #expect(positional.output.contains("--brand-2:"))

    let named = ColorKitCLI.run(["export", "primary=red", "secondary=blue"])
    #expect(named.output.contains("--brand-primary:"))
    #expect(named.output.contains("--brand-secondary:"))
  }

  @Test("Two keys that sanitize to one are refused")
  func keysAreUniquedAfterSanitizing() {
    // Uniqued against the *sanitized* key, never the raw one. `.` is not a legal CSS
    // identifier character and `-` is, so `a.b` and `a-b` are two plausible keys that
    // become one property — and then a color vanishes from the document in silence.
    // The token importer guards the same collision; it renames, because those keys are
    // somebody else's. These were typed here, so saying so is more use.
    let collision = ColorKitCLI.run(["export", "a.b=red", "a-b=blue"])
    #expect(collision.status == .usage)
    #expect(collision.diagnostic.contains("a-b"))

    #expect(ColorKitCLI.run(["export", "a.b=red", "c=blue"]).status == .success)
    #expect(ColorKitCLI.run(["export", "red", "red"]).status == .success)
  }

  @Test("A bad color names the entry it came from")
  func failuresNameTheirEntry() {
    // Two colors on one line means "not a CSS color" on its own says nothing.
    let outcome = ColorKitCLI.run(["export", "ok=red", "bad=notacolor"])
    #expect(outcome.status == .failure)
    #expect(outcome.diagnostic.contains("bad"))
  }

  @Test("export needs at least one color and defaults to a document")
  func exportDefaultsToADocument() {
    #expect(ColorKitCLI.run(["export"]).status == .usage)
    // A listing of what you just typed is not worth a command, which is why this one
    // command defaults to a shape where every other defaults to a listing.
    #expect(ColorKitCLI.run(["export", "red"]).output.hasPrefix(":root {"))
  }

  /// The CLI's honesty rule (`OutputOptions.init`'s own doc comment) applied to the
  /// *second* shape that hides `--format`, for a different reason than the first.
  /// `p3WithFallback`'s message ("writes its own two formats") would be false here —
  /// `design-tokens` writes no format at all — and a copy-pasted message is exactly
  /// the kind of thing that looks like it works until somebody reads it.
  @Test("--shape design-tokens rejects --format with its own reason, not p3WithFallback's")
  func designTokensRejectsFormatForItsOwnReason() {
    let outcome = ColorKitCLI.run(["export", "red", "--shape", "design-tokens", "--format", "hex"])
    #expect(outcome.status == .usage)
    #expect(outcome.diagnostic.contains("its own space"))
    #expect(!outcome.diagnostic.contains("its own two formats"))
  }

  /// `colorkit export --shape design-tokens` is a genuine round trip through the
  /// tool (M34), not merely a shape that happens to produce valid JSON — every color
  /// typed on the command line comes back out of this app's own decoder.
  @Test("export --shape design-tokens writes a document the tool can read back")
  func designTokensRoundTripsThroughTheTool() throws {
    let outcome = ColorKitCLI.run([
      "export", "primary=red", "secondary=color(display-p3 0.1 0.2 0.5)",
      "--shape", "design-tokens",
    ])
    #expect(outcome.status == .success)
    let data = try #require(outcome.output.data(using: .utf8))
    let document = try DesignTokenImport.decode(data)
    #expect(document.colors.count == 2)
    #expect(document.colors.contains { $0.color.space == .displayP3 })
  }
}

@Suite("tokens")
struct TokensCommandTests {
  // MARK: Internal

  @Test("A token file reads off disk and every color in it comes back")
  func aTokenFileImports() {
    // **This is the only test in the project that reads a real file through this code
    // path**, and it can be: the CLI target is not sandboxed, where the app's importer
    // needed a powerbox URL and a security-scoped claim and so remains a manual check.
    Self.withFile(Self.document) { path in
      let outcome = ColorKitCLI.run(["tokens", path])
      #expect(outcome.status == .success)
      #expect(outcome.diagnostic.contains("Imported 4 color tokens."))
      #expect(outcome.diagnostic.contains("Ignored 1 token of other types."))

      for key in ["brand-50", "brand-500", "brand-wide", "semantic-primary"] {
        #expect(outcome.output.contains(key), "missing \(key)")
      }
      for value in printedColors(outcome.output) {
        #expect(CSSColorParser.color(value) != nil, "“\(value)” did not parse back")
      }
    }
  }

  @Test("The listing keeps the space each token named")
  func theListingKeepsTheAuthoredSpelling() {
    // A token's `colorSpace` is authored information, like a typed `rebeccapurple` —
    // which is why the app's importer saves in that space rather than canonicalizing.
    // Canonicalizing here would throw away the same thing.
    Self.withFile(Self.document) { path in
      let outcome = ColorKitCLI.run(["tokens", path])
      #expect(outcome.output.contains("color(srgb "))
      #expect(outcome.output.contains("color(display-p3 "))

      // A document has one format by construction, so asking for a shape is asking for
      // one spelling — and then the authored spaces are gone by design, not by accident.
      let shaped = ColorKitCLI.run(["tokens", path, "--shape",
                                    Names.name(for: .customProperties)])
      #expect(!shaped.output.contains("color(srgb "))
      #expect(shaped.status == .success)
    }
  }

  /// `--shape design-tokens` is the one document shape that does not throw the
  /// authored spaces away — asserted against the same fixture and the same count
  /// ``aTokenFileImports`` already pins, so the two cannot disagree about how many
  /// colors the file holds.
  @Test("--shape design-tokens keeps every token in its own space, unlike every other shape")
  func designTokensShapeKeepsAuthoredSpaces() throws {
    try Self.withFile(Self.document) { path in
      let shaped = ColorKitCLI.run(["tokens", path, "--shape", Names.name(for: .designTokens)])
      #expect(shaped.status == .success)

      let data = try #require(shaped.output.data(using: .utf8))
      let redecoded = try DesignTokenImport.decode(data)
      #expect(redecoded.colors.count == 4)
      #expect(redecoded.colors.contains { $0.color.space == .displayP3 })
    }
  }

  @Test("An alias resolves to the color it points at")
  func aliasesResolve() {
    // A token with no `$type` of its own that aliases a color token *is* a color token —
    // the format's precedence is explicit type, then the resolved reference's, then the
    // group's. Filtering before resolving makes exactly these disappear in silence.
    Self.withFile(Self.document) { path in
      let outcome = ColorKitCLI.run(["tokens", path])
      let values = printedColors(outcome.output)
      let byKey = Dictionary(
        uniqueKeysWithValues: zip(
          outcome.output.split(separator: "\n").map { $0.split(separator: " ")[0] },
          values,
        ),
      )
      #expect(byKey["semantic-primary"] == byKey["brand-500"])
    }
  }

  @Test("A skipped token is named with its reason rather than counted")
  func skippedTokensAreNamed() {
    let broken = """
    {
      "c": {
        "$type": "color",
        "good": { "$value": { "colorSpace": "srgb", "components": [1, 0, 0] } },
        "alien": { "$value": { "colorSpace": "cmyk", "components": [0, 1, 1, 0] } },
        "dangling": { "$value": "{nowhere.at.all}" }
      }
    }
    """
    Self.withFile(broken) { path in
      let outcome = ColorKitCLI.run(["tokens", path])
      #expect(outcome.status == .success)
      #expect(outcome.diagnostic.contains("c.alien"))
      #expect(outcome.diagnostic.contains("c.dangling"))
      #expect(printedColors(outcome.output).count == 1)
    }
  }

  @Test("A missing file and an unreadable one fail differently from a broken command line")
  func fileFailuresAreFailuresNotMisuse() {
    // The five outcomes the app's panel gives five sentences: an unreadable file and a
    // file with nothing importable in it are not the same problem, and neither is a
    // command line that named no file at all.
    let missing = ColorKitCLI.run(["tokens", "/nowhere/at/all.json"])
    #expect(missing.status == .failure)
    #expect(missing.diagnostic.contains("Could not read"))

    Self.withFile("not json at all") { path in
      let outcome = ColorKitCLI.run(["tokens", path])
      #expect(outcome.status == .failure)
      #expect(outcome.output.isEmpty)
    }

    #expect(ColorKitCLI.run(["tokens"]).status == .usage)
  }

  // MARK: Private

  /// A file exercising the four rules the importer's precedence chain rests on: an
  /// explicit `$type`, a group's inherited one, an alias that takes its *resolved*
  /// reference's type, and a token of another type entirely.
  private static let document = """
  {
    "brand": {
      "$type": "color",
      "50":  { "$value": { "colorSpace": "srgb", "components": [0.94, 0.96, 1] } },
      "500": { "$value": { "colorSpace": "srgb", "components": [0.23, 0.51, 0.96] } },
      "wide": { "$value": { "colorSpace": "display-p3", "components": [0.1, 0.2, 0.5] } }
    },
    "semantic": {
      "primary": { "$value": "{brand.500}" }
    },
    "spacing": {
      "$type": "dimension",
      "sm": { "$value": { "value": 4, "unit": "px" } }
    }
  }
  """

  private static func withFile<T>(
    _ contents: String,
    named name: String = "cli.tokens.json",
    _ body: (String) throws -> T,
  ) rethrows -> T {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    let file = url.appendingPathComponent(name)
    try? Data(contents.utf8).write(to: file)
    defer { try? FileManager.default.removeItem(at: url) }
    return try body(file.path)
  }
}
