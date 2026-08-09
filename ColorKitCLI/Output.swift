import Foundation

/// The options every color-emitting command shares, and the rules about which of them
/// mean anything together.
struct OutputOptions {
  // MARK: Lifecycle

  /// Reads the shared options, rejecting any that the chosen shape would ignore.
  ///
  /// **An option a command would silently ignore is an error here, not a no-op.** The
  /// export panel *hides* the Format picker when `ExportShape.usesFormat` is false,
  /// because `p3WithFallback` fixes both its formats and honouring the picker would put
  /// an unbounded `oklch()` into the block a browser reaches when it *cannot* do wide
  /// gamut. A CLI has no control to hide, so the equivalent honesty is saying so: a
  /// `--format` that changed nothing would otherwise look like it had worked.
  init(_ arguments: Arguments) throws(CLIError) {
    if let text = arguments.value("shape") {
      guard let shape = Names.shape(named: text) else {
        throw .usage("“\(text)” is not an export shape. Try one of: \(Names.shapeList).")
      }
      self.shape = shape
    }

    if let text = arguments.value("format") {
      guard let format = Names.format(named: text) else {
        throw .usage("“\(text)” is not a color format. Try one of: \(Names.formatList).")
      }
      guard shape?.usesFormat != false else {
        throw .usage(
          "--shape \(Names.name(for: shape!)) writes its own two formats, so --format has nothing to set.",
        )
      }
      self.format = format
    }

    if let text = arguments.value("name") {
      guard shape?.usesName == true else {
        throw .usage(
          shape == nil
            ? "--name only applies with --shape."
            : "--shape \(Names.name(for: shape!)) has nowhere to put a family name.",
        )
      }
      guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
        throw .usage("--name is empty.")
      }
      name = text
    }

    if let text = arguments.value("template") {
      guard let template = Names.template(named: text) else {
        throw .usage("“\(text)” is not a declaration template. Try one of: \(Names.templateList).")
      }
      guard shape?.usesTemplate == true else {
        throw .usage(
          shape == nil
            ? "--template only applies with --shape."
            : "--shape \(Names.name(for: shape!)) writes whole declarations of its own.",
        )
      }
      self.template = template
    }

    if let precision = try arguments.integer("precision", in: 0 ... 10) {
      formatting.precision = precision
    }
  }

  // MARK: Internal

  // MARK: Static

  /// The options a command has to declare to accept an `OutputOptions`.
  static let spec = OptionSpec(valued: ["format", "precision", "shape", "name", "template"])

  /// The format a command writes when nothing says otherwise.
  ///
  /// `oklch()` for the reason `TransformPanel` adopts with `preferring: .oklch`: it is
  /// unbounded, so it can spell a result that left sRGB instead of quietly moving it,
  /// and a round trip through it does not quantize onto the 8-bit grid the way hex does.
  static let defaultFormat: CSSOutputFormat = .oklch

  var format: CSSOutputFormat = defaultFormat
  var formatting: CSSFormatOptions = .default

  /// The document to render, or `nil` for the two-column listing.
  var shape: ExportShape?
  var name = ExportOptions.defaultName
  var template: ExportTemplate = .color

  /// The format whose gamut the "mapped" warning is counted against.
  ///
  /// Deferred to `ExportOptions` in document mode rather than restated, because a shape
  /// writing two spellings has to say which one the count is about — for
  /// `p3WithFallback` that is the **hex fallback**, and counting against the P3 block
  /// instead reports nothing mapped while the hex line underneath has been rounded.
  var countedFormat: CSSOutputFormat {
    guard let shape else { return format }
    return exportOptions(shape).mappedCountFormat
  }

  func exportOptions(_ shape: ExportShape) -> ExportOptions {
    var options = ExportOptions.default
    options.shape = shape
    options.format = format
    options.name = name
    options.template = template
    return options
  }
}

/// Rendering a set of keyed colors — the shape shared by every command that answers
/// with more than one color.
enum PaletteOutput {
  /// A two-column listing, or a document when `--shape` asked for one.
  ///
  /// The listing puts nothing on stdout but keys and CSS, so `awk '{print $2}'` works;
  /// the mapped-value note goes to stderr for the same reason a parse warning does.
  static func render(_ entries: [PaletteEntry], _ options: OutputOptions) -> CommandOutcome {
    var outcome = CommandOutcome()

    if let shape = options.shape {
      outcome.output = options
        .exportOptions(shape)
        .render(entries, formatting: options.formatting)
    } else {
      let width = entries.map(\.key.count).max() ?? 0
      outcome.output = entries.map { entry in
        pad(entry.key, to: width) + "  " + css(entry.color, options)
      }.joined(separator: "\n")
    }

    if let note = mappedNote(entries, options) {
      outcome.diagnostic = note
    }
    return outcome
  }

  /// One color as CSS, falling back the way the export layer does.
  ///
  /// `cssStringOrHex` rather than `cssString` because the only format that can decline
  /// is `.keyword`, and no command reaches here with that: it is excluded from
  /// `CSSOutputFormat.exportable`, and `convert --format keyword` handles its own
  /// failure. The fallback is a belt, not a decision.
  static func css(_ color: ColorValue, _ options: OutputOptions) -> String {
    color.cssStringOrHex(as: options.format, options: options.formatting)
  }

  /// How many of `entries` had to move to be written, phrased for stderr.
  ///
  /// One predicate — `isGamutMapped` — decides this, the app's badge and the serialized
  /// string alike. A second rule here would let the warning disagree with the value
  /// printed beside it.
  static func mappedNote(
    _ entries: [PaletteEntry],
    _ options: OutputOptions,
  ) -> String? {
    let format = options.countedFormat
    let mapped = entries.count {
      $0.color.isGamutMapped(
        as: format,
        options: options.formatting,
        epsilon: ColorValue.gamutNoiseTolerance,
      )
    }
    guard mapped > 0 else { return nil }
    let subject = mapped == 1 ? "1 value was" : "\(mapped) values were"
    return "Note: \(subject) brought into gamut to be written as \(Names.name(for: format))."
  }

  static func pad(_ text: String, to width: Int) -> String {
    text + String(repeating: " ", count: max(0, width - text.count))
  }
}
