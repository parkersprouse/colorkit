import Foundation

/// `colorkit export` — a set of named colors written as a document.
enum ExportCommand {
  static let spec = OptionSpec().adding(OutputOptions.spec)

  static let usage = """
  Usage: colorkit export <entry>... [--shape <name>] [--format <name>]
                         [--name <family>] [--template <name>] [--precision <n>]

    Each entry is either a color or key=color. Bare colors are keyed by position,
    starting at 1.

    --shape     One of: \(Names.shapeList)  (default \(Names.name(for: ExportOptions.default.shape)))
    --format    One of: \(Names.formatList)
    --name      The family name a document groups the colors under
    --template  The declaration written per color, for --shape declaration.
                One of: \(Names.templateList)
  """

  static func run(_ arguments: Arguments) throws(CLIError) -> CommandOutcome {
    guard !arguments.positionals.isEmpty else {
      throw .usage("Missing at least one color.")
    }

    var options = try OutputOptions(arguments)
    // Unlike every other command here, export's default *is* a document: a bare
    // listing of what you just typed is not worth a command.
    options.shape = options.shape ?? ExportOptions.default.shape

    var entries: [PaletteEntry] = []
    var seen: Set<String> = []
    for (position, argument) in arguments.positionals.enumerated() {
      let key: String
      let colorText: String
      if let separator = argument.firstIndex(of: "="), separator != argument.startIndex {
        key = String(argument[argument.startIndex ..< separator])
        colorText = String(argument[argument.index(after: separator)...])
      } else {
        key = String(position + 1)
        colorText = argument
      }

      // **Uniqued against the sanitized key, never the raw one.** Two keys that differ
      // only where `cssIdentifier` does not — `brand.500` and `brand-500` — become one
      // CSS property, and then one of the colors vanishes from the document with
      // nothing said. The design token importer guards the same collision the same way;
      // the difference is what happens next. There it renames, because a token file is
      // somebody else's and the colors have to survive. Here the keys were typed on
      // this command line, so saying so is more use than silently renaming.
      let sanitized = ExportOptions.cssIdentifier(key, fallback: "")
      guard seen.insert(sanitized).inserted else {
        throw .usage("Two entries share the key “\(sanitized)”; every key has to be distinct.")
      }

      let parsed = try ColorArgument.parse(colorText, as: "color for “\(key)”")
      entries.append(PaletteEntry(key: key, color: parsed.color))
    }

    return PaletteOutput.render(entries, options)
  }
}

/// `colorkit tokens` — a W3C design token file, read and written out as CSS.
enum TokensCommand {
  // MARK: Internal

  static let spec = OptionSpec().adding(OutputOptions.spec)

  static let usage = """
  Usage: colorkit tokens <file> [--shape <name>] [--format <name>]
                         [--name <family>] [--template <name>] [--precision <n>]

    Reads a W3C design token file, keeps every color token — including one that
    aliases another and inherits its type — and writes them out. What was skipped
    and why goes to stderr, so the document on stdout stays a document.

    Each color is listed in the space its token named — a token's colorSpace is
    something its author wrote down. Passing --shape or --format asks for one
    spelling across the whole set instead.

    --shape  Render a document instead of a listing. One of: \(Names.shapeList)
  """

  static func run(_ arguments: Arguments) throws(CLIError) -> CommandOutcome {
    try arguments.expect(1, named: "a token file")
    let path = arguments.positionals[0]

    // The CLI target is not sandboxed — that setting is on the app target alone — so
    // this is a plain read where the app needed a powerbox URL and a security-scoped
    // claim. Same file, none of the machinery.
    let data: Data
    do {
      data = try Data(contentsOf: URL(fileURLWithPath: path))
    } catch {
      throw .failure("Could not read “\(path)”: \(error.localizedDescription)")
    }

    let document: DesignTokenDocument
    do {
      document = try DesignTokenImport.decode(data)
    } catch {
      throw .failure("Could not read “\(path)”: \(error.message)")
    }

    let options = try OutputOptions(arguments)
    let entries = document.colors.map { PaletteEntry(key: $0.key, color: $0.color) }

    // **The listing spells each color in the space its token named; a document cannot.**
    // `savePalette(importing:)` is a third overload rather than a call into either other
    // one for exactly this reason — a token's `colorSpace` is authored information, like
    // a typed `rebeccapurple`, and canonicalizing it throws that away. But
    // `ExportOptions.render` writes one format across the whole document by
    // construction, so asking for `--shape` *is* asking for one spelling. The default
    // stays the listing so the authored spelling is what you get without asking.
    var outcome: CommandOutcome
    if options.shape != nil || arguments.value("format") != nil {
      outcome = PaletteOutput.render(entries, options)
    } else {
      let width = entries.map(\.key.count).max() ?? 0
      outcome = .result(entries.map { entry in
        var native = options
        native.format = CSSOutputFormat.native(for: entry.color.space)
        return PaletteOutput.pad(entry.key, to: width)
          + "  " + PaletteOutput.css(entry.color, native)
      }.joined(separator: "\n"))
    }

    outcome.diagnostic = (report(document) + [outcome.diagnostic])
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
    return outcome
  }

  // MARK: Private

  /// What the file contained, phrased for stderr.
  ///
  /// Every skipped token is named with its reason rather than counted, because a
  /// token that quietly did not arrive is the failure this report exists to prevent.
  private static func report(_ document: DesignTokenDocument) -> [String] {
    var lines = ["Imported \(count(document.colors.count, "color token"))."]
    if document.otherTypeCount > 0 {
      lines.append("Ignored \(count(document.otherTypeCount, "token")) of other types.")
    }
    for skipped in document.skipped {
      lines.append("Skipped “\(skipped.name)”: \(skipped.reason.message)")
    }
    return lines
  }

  private static func count(_ n: Int, _ noun: String) -> String {
    "\(n) \(noun)\(n == 1 ? "" : "s")"
  }
}
