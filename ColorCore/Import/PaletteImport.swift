//
//  PaletteImport.swift
//  ColorKit
//

import Foundation

/// The shape a pasted document was written in — ``ExportShape``'s vocabulary plus two
/// entries that shape has no use for.
///
/// **Deliberately not `ExportShape` itself.** The two vocabularies differ in both
/// directions: a design token file is importable and not something this app writes, and
/// a bare list of colors with no structure at all is importable and not a document shape
/// on the export side either. Reusing `ExportShape` would mean two cases meaning nothing
/// on one side or the other — the same argument that kept `color-mix()` out of
/// `ColorFunction`.
nonisolated enum ImportShape: String, CaseIterable, Sendable, Hashable, Identifiable, Codable {
  case customProperties = "custom-properties"
  case declaration
  case json
  case tailwindTheme = "tailwind-theme"
  case tailwindConfig = "tailwind-config"
  case p3WithFallback = "p3-with-fallback"
  /// A W3C design token document — the same format ``DesignTokenImport`` already reads
  /// from a file, reachable here from pasted text instead.
  case designTokens = "design-tokens"
  /// Colors with no surrounding structure at all: one per line, or comma-separated.
  case looseColors = "loose-colors"

  // MARK: Internal

  var id: String {
    rawValue
  }
}

/// One color read out of a pasted document.
///
/// ``text`` is the value exactly as it was written — not re-serialized — because the
/// storage-format control's default is "keep as pasted", and that promise only means
/// something if this is the literal substring the parser found rather than a round trip
/// through ``ColorValue`` and back. ``notes`` exists for the one shape that carries prose
/// of its own: a design token's `$description`.
nonisolated struct ImportedEntry: Sendable, Hashable, Identifiable {
  // MARK: Lifecycle

  init(key: String, color: ColorValue, text: String, notes: String = "") {
    self.key = key
    self.color = color
    self.text = text
    self.notes = notes
  }

  // MARK: Internal

  let key: String
  let color: ColorValue
  let text: String
  let notes: String

  var id: String {
    key + "\u{0}" + text
  }
}

/// A named set of imported entries — one palette-to-be, the same unit
/// ``ProjectLibrary/savePalette(importing:named:to:)`` saves in one call.
nonisolated struct ImportedGroup: Sendable, Hashable, Identifiable {
  let name: String
  let entries: [ImportedEntry]

  var id: String {
    name
  }

  /// The bridge to the export layer's own vocabulary. Nothing in this file calls it —
  /// it exists for the round-trip tests, which check an imported document against what
  /// ``ExportOptions/render(_:formatting:)`` would make of it, and for any future caller
  /// that wants to re-render an imported set without saving it first.
  var paletteGroup: PaletteGroup {
    PaletteGroup(name: name, entries: entries.map { PaletteEntry(key: $0.key, color: $0.color) })
  }
}

/// One value that looked like it belonged and did not parse.
///
/// A name and a message rather than a typed reason — unlike ``TokenSkipReason``, there is
/// only ever one way a pasted value fails here: ``CSSColorParser`` rejected it. The name
/// is whatever this app's own extraction called it (a property name, a JSON path, a
/// design-token path), so the panel can say which line was skipped.
nonisolated struct ImportSkip: Sendable, Hashable {
  let name: String
  let message: String
}

/// Everything one pasted document yielded.
///
/// ``detectedName`` is set only when there is exactly one group — a real name is
/// something to suggest, and with more than one group each already has its own name from
/// the document's own structure (a header comment, a JSON key, a Tailwind family). It is
/// still just a suggestion: the sheet's name field is editable, and renaming it before
/// import moves the one group along with it.
nonisolated struct ImportedPalette: Sendable, Hashable {
  let groups: [ImportedGroup]
  let detectedName: String?
  let skipped: [ImportSkip]
}

/// Why an entire paste could not be read at all, as distinct from one bad value inside an
/// otherwise good document — the same split ``DesignTokenError`` makes from
/// ``TokenSkipReason``, for the identical reason: an empty paste box and a design-token
/// file with one broken color are different things to tell a user.
nonisolated enum PaletteImportError: Error, Equatable, Sendable {
  case empty
  case malformed(String)

  // MARK: Internal

  var message: String {
    switch self {
    case .empty:
      "There is nothing to import."
    case let .malformed(text):
      text
    }
  }
}

/// Reads a palette back out of text this app — or something compatible with it — wrote.
///
/// **There is no multi-color entry point in `CSSColorParser`, and this does not add one.**
/// `CSSColorParser.parse` still reads exactly one color and still throws on anything past
/// it; the seam here is structural extraction first, one value parsed at a time after —
/// so a single malformed line costs that line and nothing else, and the 35 existing error
/// cases in `ParseError` keep meaning what they mean.
///
/// **The round trip is the oracle**, the same way it is for `Export/`: render a document
/// with ``ExportOptions/render(_:formatting:)`` and this should read the groups, keys and
/// colors back out of it. `PaletteImportTests` holds that claim for every export shape at
/// both cardinalities — a lone color and a scale.
nonisolated enum PaletteImport {
  // MARK: Internal

  // MARK: - Detection

  /// Structural sniffing, most specific first. Order is load-bearing: `@theme {` and
  /// `module.exports` both also satisfy a later, looser test (`:root {` and "parses as
  /// JSON" respectively do not overlap with them, but a document carrying stray text
  /// could), so the earlier, more specific reading has to win.
  static func detect(_ text: String) -> ImportShape {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.contains("@theme") {
      return .tailwindTheme
    }
    if trimmed.contains("module.exports") || trimmed.contains("@type {import('tailwindcss')") {
      return .tailwindConfig
    }
    if trimmed.contains("@media (color-gamut") {
      return .p3WithFallback
    }
    if trimmed.contains(":root {") {
      return .customProperties
    }
    if let data = trimmed.data(using: .utf8),
       let object = try? JSONSerialization.jsonObject(with: data)
    {
      if let dictionary = object as? [String: Any] {
        return containsValueKey(dictionary) ? .designTokens : .json
      }
    }
    return looksLikeDeclarations(trimmed) ? .declaration : .looseColors
  }

  // MARK: - Parsing

  /// Reads `text` as `shape`. Throws only when the whole paste cannot be read at all —
  /// see ``PaletteImportError``; a value that fails to parse inside an otherwise good
  /// document is reported in ``ImportedPalette/skipped`` instead.
  static func parse(_ text: String, as shape: ImportShape) throws(PaletteImportError) -> ImportedPalette {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw .empty }

    switch shape {
    case .customProperties:
      return parsePropertyBlock(trimmed, stripPrefix: "")
    case .tailwindTheme:
      return parsePropertyBlock(trimmed, stripPrefix: "color-")
    case .p3WithFallback:
      return parseP3WithFallback(trimmed)
    case .declaration:
      return parseDeclarations(trimmed)
    case .json:
      return parseJSON(trimmed)
    case .tailwindConfig:
      return parseTailwindConfig(trimmed)
    case .designTokens:
      return try parseDesignTokens(trimmed)
    case .looseColors:
      return parseLooseColors(trimmed)
    }
  }

  // MARK: Private

  // MARK: - Shared line extraction

  /// A `name: value;` pair as read off one line, with the trailing `/* key */` comment
  /// ``ColorExport/declarations(_:formatting:)`` writes, if there was one.
  private struct ParsedLine {
    let name: String
    let value: String
    let comment: String?
  }

  /// Everything one source line could be: a `/* From "…" */` group header, or a property
  /// line. Every other line — a selector, a brace, an `@media` prelude, a blank line — is
  /// simply not produced by this scan, so callers never see it.
  private enum SourceLine {
    case header(String)
    case property(ParsedLine)
  }

  // MARK: - Family / key inference

  /// Accumulates entries under a family name, preserving the order families were first
  /// seen — `JSONSerialization` and a hand-rolled JS scan both need this, since neither
  /// document format is guaranteed to preserve source order any more than
  /// `DesignTokenImport` could rely on `JSONSerialization` for one.
  private struct GroupBuilder {
    // MARK: Internal

    private(set) var order: [String] = []

    var groups: [ImportedGroup] {
      order.map { ImportedGroup(name: $0, entries: entries[$0] ?? []) }
    }

    mutating func add(_ entry: ImportedEntry, to family: String) {
      if entries[family] == nil {
        order.append(family)
      }
      entries[family, default: []].append(entry)
    }

    // MARK: Private

    private var entries: [String: [ImportedEntry]] = [:]
  }

  // MARK: - Detection helpers

  private static func containsValueKey(_ node: [String: Any]) -> Bool {
    if node["$value"] != nil {
      return true
    }
    for value in node.values {
      if let child = value as? [String: Any], containsValueKey(child) {
        return true
      }
    }
    return false
  }

  /// Strips a trailing `/* … */` comment, if there is one — the same comment
  /// ``ColorExport/declarations(_:formatting:)`` appends after the semicolon, which
  /// means a line testing for `;`-termination has to look past it too, or every
  /// declaration carrying a key comment fails the check that is supposed to recognize it.
  private static func strippingTrailingComment(_ line: String) -> String {
    guard line.hasSuffix("*/"), let start = line.range(of: "/*", options: .backwards) else {
      return line
    }
    return String(line[..<start.lowerBound]).trimmingCharacters(in: .whitespaces)
  }

  private static func looksLikeDeclarations(_ text: String) -> Bool {
    text.split(separator: "\n").contains { rawLine in
      let line = strippingTrailingComment(rawLine.trimmingCharacters(in: .whitespaces))
      guard line.hasSuffix(";"), let colon = line.firstIndex(of: ":") else { return false }
      return !line[line.startIndex ..< colon].trimmingCharacters(in: .whitespaces).isEmpty
    }
  }

  /// Line-based and `;`-terminated, not scanned across the whole document. **This is not
  /// interchangeable with a document-wide `:`…`;` scan**: `@media (color-gamut: p3) {`
  /// has a colon and no semicolon, and a scan spanning it would swallow the prelude as
  /// part of whatever value came next. A line whose trimmed form is `name: value;`
  /// already excludes `@media …{`, `:root {` and `}` for free, since none of them end in
  /// a semicolon.
  private static func sourceLines(in text: String) -> [SourceLine] {
    var out: [SourceLine] = []
    for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
      var line = rawLine.trimmingCharacters(in: .whitespaces)
      guard !line.isEmpty else { continue }

      if line.hasPrefix("/* From \""), line.hasSuffix("\" */") {
        let inner = line.dropFirst("/* From \"".count).dropLast("\" */".count)
        out.append(.header(String(inner)))
        continue
      }

      var comment: String?
      if line.hasSuffix("*/"), let start = line.range(of: "/*", options: .backwards) {
        comment = String(line[line.index(start.lowerBound, offsetBy: 2)...].dropLast(2))
          .trimmingCharacters(in: .whitespaces)
        line = String(line[..<start.lowerBound]).trimmingCharacters(in: .whitespaces)
      }
      guard line.hasSuffix(";"), let colon = line.firstIndex(of: ":") else { continue }
      let name = String(line[line.startIndex ..< colon]).trimmingCharacters(in: .whitespaces)
      guard !name.isEmpty, !name.hasPrefix("@") else { continue }
      let value = String(line[line.index(after: colon) ..< line.index(before: line.endIndex)])
        .trimmingCharacters(in: .whitespaces)
      out.append(.property(ParsedLine(name: name, value: value, comment: comment)))
    }
    return out
  }

  /// Splits a document's property lines into blocks at each `/* From "…" */` header,
  /// with everything before the first header (or the whole document, if there is none at
  /// all) forming one headerless block.
  private static func headeredBlocks(in text: String) -> [(header: String?, lines: [ParsedLine])] {
    var blocks: [(header: String?, lines: [ParsedLine])] = []
    var currentHeader: String?
    var currentLines: [ParsedLine] = []
    var sawAnything = false

    for source in sourceLines(in: text) {
      switch source {
      case let .header(identifier):
        if sawAnything {
          blocks.append((currentHeader, currentLines))
        }
        currentHeader = identifier
        currentLines = []
        sawAnything = true
      case let .property(line):
        currentLines.append(line)
        sawAnything = true
      }
    }
    if sawAnything {
      blocks.append((currentHeader, currentLines))
    }
    return blocks.filter { !$0.lines.isEmpty }
  }

  /// The longest common **hyphen-segment** prefix across `names`, and each name's
  /// remaining suffix once that prefix (and its separating hyphen) is removed.
  ///
  /// Segment-wise, never character-wise: `primary-100` and `primary-200` share the
  /// segment `primary`. `primary-100` and `primar-200` share seven raw *characters* and
  /// zero segments — collapsing them to `primar` would invent a family nothing in the
  /// document ever named. `nil` when there is no shared segment at all, which callers
  /// read as M20's loose-color rule in reverse: every name becomes a family of one.
  private static func commonFamily(_ names: [String]) -> (family: String, keys: [String: String])? {
    guard names.count > 1 else { return nil }
    let segmented = names.map { $0.split(separator: "-").map(String.init) }
    guard var shared = segmented.first else { return nil }
    for segments in segmented.dropFirst() {
      var count = 0
      while count < shared.count, count < segments.count, shared[count] == segments[count] {
        count += 1
      }
      shared = Array(shared.prefix(count))
      if shared.isEmpty {
        return nil
      }
    }
    let family = shared.joined(separator: "-")
    var keys: [String: String] = [:]
    for (name, segments) in zip(names, segmented) {
      keys[name] = segments.dropFirst(shared.count).joined(separator: "-")
    }
    return (family, keys)
  }

  /// Disambiguates keys that collided *within one group* — two properties that happened
  /// to strip to the same suffix. Same `-2` suffix loop as
  /// ``DesignTokenImport/keyed(_:)`` and ``ProjectLibrary/paletteKeys(for:)``, scoped per
  /// group rather than globally because that is the scope a palette's keys have to be
  /// unique in. A group of exactly one entry is left alone: its empty key is
  /// ``PaletteEntry``'s "no position to name" marker, not a collision waiting to happen.
  private static func uniquingKeys(_ groups: [ImportedGroup]) -> [ImportedGroup] {
    groups.map { group in
      guard group.entries.count > 1 else { return group }
      var used: Set<String> = []
      let entries = group.entries.map { entry -> ImportedEntry in
        var key = entry.key
        if used.contains(key) {
          var suffix = 2
          while used.contains("\(key)-\(suffix)") {
            suffix += 1
          }
          key = "\(key)-\(suffix)"
        }
        used.insert(key)
        return ImportedEntry(key: key, color: entry.color, text: entry.text, notes: entry.notes)
      }
      return ImportedGroup(name: group.name, entries: entries)
    }
  }

  private static func finished(_ builder: GroupBuilder, skipped: [ImportSkip]) -> ImportedPalette {
    let groups = uniquingKeys(builder.groups)
    return ImportedPalette(
      groups: groups,
      detectedName: groups.count == 1 ? groups.first?.name : nil,
      skipped: skipped,
    )
  }

  private static func parseAndAppend(
    key: String,
    rawValue: String,
    family: String,
    diagnosticName: String,
    notes: String = "",
    into builder: inout GroupBuilder,
    skipped: inout [ImportSkip],
  ) {
    guard let color = CSSColorParser.color(rawValue) else {
      skipped.append(ImportSkip(name: diagnosticName, message: "“\(rawValue)” is not a color this app can parse."))
      return
    }
    builder.add(ImportedEntry(key: key, color: color, text: rawValue, notes: notes), to: family)
  }

  // MARK: - CSS-shaped: customProperties, tailwindTheme, and p3WithFallback's wide block

  /// `:root { --a: …; }`-shaped text, one or more groups. `stripPrefix` additionally
  /// removes `color-`, the Tailwind theme namespace, before family inference runs.
  ///
  /// **A header, when there is one, is authoritative** — it is this app's own record of
  /// what the group was called, where segment-wise inference is a guess about a file this
  /// app never wrote. So a headered block strips exactly that name off every property
  /// rather than re-deriving it, and only a headerless block reaches for
  /// ``commonFamily(_:)``.
  private static func parsePropertyBlock(_ text: String, stripPrefix: String) -> ImportedPalette {
    var builder = GroupBuilder()
    var skipped: [ImportSkip] = []

    for block in headeredBlocks(in: text) {
      let stripped = block.lines.map { line -> (line: ParsedLine, name: String) in
        var name = line.name
        if name.hasPrefix("--") {
          name.removeFirst(2)
        }
        if !stripPrefix.isEmpty, name.hasPrefix(stripPrefix) {
          name.removeFirst(stripPrefix.count)
        }
        return (line, name)
      }

      if let header = block.header {
        for (line, name) in stripped {
          let key = name == header
            ? ""
            : (name.hasPrefix(header + "-") ? String(name.dropFirst(header.count + 1)) : name)
          parseAndAppend(
            key: key, rawValue: line.value, family: header, diagnosticName: line.name,
            into: &builder, skipped: &skipped,
          )
        }
      } else if stripped.count == 1 {
        let (line, name) = stripped[0]
        parseAndAppend(
          key: "", rawValue: line.value, family: name, diagnosticName: line.name,
          into: &builder, skipped: &skipped,
        )
      } else if let (family, keys) = commonFamily(stripped.map(\.name)) {
        for (line, name) in stripped {
          parseAndAppend(
            key: keys[name] ?? "", rawValue: line.value, family: family, diagnosticName: line.name,
            into: &builder, skipped: &skipped,
          )
        }
      } else {
        for (line, name) in stripped {
          parseAndAppend(
            key: "", rawValue: line.value, family: name, diagnosticName: line.name,
            into: &builder, skipped: &skipped,
          )
        }
      }
    }

    return finished(builder, skipped: skipped)
  }

  /// `p3WithFallback` writes the same properties twice — hex, then again in
  /// `color(display-p3 …)` behind `@media (color-gamut: p3)`. **Only the override block
  /// is read.** Hex `cannotRepresentOutOfGamut`, so any color that motivated choosing
  /// this shape in the first place would come back rounded if the fallback block were
  /// the one trusted — the media block is the one spelling that can actually carry it.
  private static func parseP3WithFallback(_ text: String) -> ImportedPalette {
    guard let range = text.range(of: "@media (color-gamut") else {
      return ImportedPalette(groups: [], detectedName: nil, skipped: [])
    }
    return parsePropertyBlock(String(text[range.lowerBound...]), stripPrefix: "")
  }

  // MARK: - declaration

  /// Bare declarations. **The family name is not always recoverable**: a single-group
  /// declaration export carries no header at all (only a multi-group one does — see
  /// `ExportOptions.declarations`), so a headerless block falls back to
  /// `ExportOptions.defaultName` as a neutral placeholder rather than inventing a name
  /// the document never stated. `detectedName` still surfaces it as an editable
  /// suggestion; nothing here treats it as a real detection.
  private static func parseDeclarations(_ text: String) -> ImportedPalette {
    var builder = GroupBuilder()
    var skipped: [ImportSkip] = []

    for block in headeredBlocks(in: text) {
      let family = block.header ?? ExportOptions.defaultName
      for line in block.lines {
        let key = line.comment.map { ExportOptions.cssIdentifier($0, fallback: "") } ?? ""
        parseAndAppend(
          key: key, rawValue: line.value, family: family, diagnosticName: line.name,
          into: &builder, skipped: &skipped,
        )
      }
    }

    return finished(builder, skipped: skipped)
  }

  // MARK: - json

  private static func jsonKeyOrder(_ lhs: String, _ rhs: String) -> Bool {
    if let left = Int(lhs), let right = Int(rhs) {
      return left < right
    }
    return lhs < rhs
  }

  /// This app's own `json` shape always nests one level — a lone color is a string, a
  /// scale is an object of them (``ColorExport/json(_:formatting:)``) — but a
  /// hand-authored file might not, so both readings are supported: nested when *any* top
  /// value is itself an object, flat (family inferred the same way the CSS shapes infer
  /// one) otherwise.
  private static func parseJSON(_ text: String) -> ImportedPalette {
    guard let data = text.data(using: .utf8),
          let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else {
      return ImportedPalette(groups: [], detectedName: nil, skipped: [])
    }

    var builder = GroupBuilder()
    var skipped: [ImportSkip] = []
    let topLevel = object.keys.sorted(by: jsonKeyOrder)
    let isNested = object.values.contains { $0 is [String: Any] }

    if isNested {
      for key in topLevel {
        switch object[key] {
        case let value as String:
          parseAndAppend(
            key: "", rawValue: value, family: key, diagnosticName: key,
            into: &builder, skipped: &skipped,
          )
        case let nested as [String: Any]:
          for subKey in nested.keys.sorted(by: jsonKeyOrder) {
            guard let value = nested[subKey] as? String else { continue }
            parseAndAppend(
              key: subKey, rawValue: value, family: key, diagnosticName: "\(key).\(subKey)",
              into: &builder, skipped: &skipped,
            )
          }
        default: continue
        }
      }
    } else if topLevel.count == 1, let key = topLevel.first, let value = object[key] as? String {
      parseAndAppend(
        key: "", rawValue: value, family: key, diagnosticName: key,
        into: &builder, skipped: &skipped,
      )
    } else if let (family, keys) = commonFamily(topLevel) {
      for key in topLevel {
        guard let value = object[key] as? String else { continue }
        parseAndAppend(
          key: keys[key] ?? "", rawValue: value, family: family, diagnosticName: key,
          into: &builder, skipped: &skipped,
        )
      }
    } else {
      for key in topLevel {
        guard let value = object[key] as? String else { continue }
        parseAndAppend(
          key: "", rawValue: value, family: key, diagnosticName: key,
          into: &builder, skipped: &skipped,
        )
      }
    }

    return finished(builder, skipped: skipped)
  }

  // MARK: - tailwindConfig

  /// Strips a JavaScript string literal's quotes (either kind) and a trailing comma.
  /// Not a general JS scanner — this app's own `tailwindConfig` shape never writes
  /// anything a value could contain that would need one (no escaped quotes, no nested
  /// commas outside the object braces already being tracked by depth).
  private static func stripJSQuotes(_ text: String) -> String {
    var value = text.trimmingCharacters(in: .whitespaces)
    if value.hasSuffix(",") {
      value.removeLast()
    }
    value = value.trimmingCharacters(in: .whitespaces)
    guard value.count >= 2 else { return value }
    if (value.hasPrefix("'") && value.hasSuffix("'"))
      || (value.hasPrefix("\"") && value.hasSuffix("\""))
    {
      return String(value.dropFirst().dropLast())
    }
    return value
  }

  /// A depth-tracked line scan over the `colors: { … }` object inside
  /// `module.exports = { theme: { extend: { colors: { … } } } }` —
  /// ``ColorExport/tailwindConfig(_:formatting:)``'s own shape read backwards. Not a
  /// general JavaScript parser: it tracks exactly the one level of nesting this app's own
  /// export produces (a family is either a bare string or one object of shade keys), which
  /// is what `tailwindConfig`'s own two cardinalities are — a lone color and a scale.
  private static func parseTailwindConfig(_ text: String) -> ImportedPalette {
    var builder = GroupBuilder()
    var skipped: [ImportSkip] = []

    guard let colorsKeyword = text.range(of: "colors:"),
          let openBrace = text[colorsKeyword.upperBound...].firstIndex(of: "{")
    else {
      return ImportedPalette(groups: [], detectedName: nil, skipped: [])
    }

    var depth = 0
    var family: String?
    let body = text[text.index(after: openBrace)...]

    lineLoop: for rawLine in body.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      if line == "}" || line == "}," {
        if depth > 0 {
          depth -= 1
          family = nil
          continue
        }
        break lineLoop
      }

      guard let colon = line.firstIndex(of: ":") else { continue }
      let key = stripJSQuotes(String(line[line.startIndex ..< colon]))
      let rest = stripJSQuotes(String(line[line.index(after: colon)...]))

      if depth == 0 {
        if String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces) == "{" {
          family = key
          depth = 1
        } else {
          parseAndAppend(
            key: "", rawValue: rest, family: key, diagnosticName: key,
            into: &builder, skipped: &skipped,
          )
        }
      } else if let currentFamily = family {
        parseAndAppend(
          key: key, rawValue: rest, family: currentFamily, diagnosticName: "\(currentFamily).\(key)",
          into: &builder, skipped: &skipped,
        )
      }
    }

    return finished(builder, skipped: skipped)
  }

  // MARK: - designTokens

  /// Delegates straight to ``DesignTokenImport``, the same decoder the file-picker import
  /// already uses — pasted text is just a token document that arrived a different way.
  ///
  /// Grouped by dotted path minus its last segment (`color.brand.500` → family
  /// `color-brand`, key `500`), which a token path can do exactly because it is already
  /// hierarchical — unlike the CSS shapes, nothing here has to *guess* a boundary in a
  /// flat hyphenated name. A single-segment path has no group above it and becomes its
  /// own one-entry group, matching every other shape's lone-color rule.
  private static func parseDesignTokens(_ text: String) throws(PaletteImportError) -> ImportedPalette {
    guard let data = text.data(using: .utf8) else {
      return ImportedPalette(groups: [], detectedName: nil, skipped: [])
    }
    let document: DesignTokenDocument
    do {
      document = try DesignTokenImport.decode(data)
    } catch {
      throw .malformed(error.message)
    }

    var builder = GroupBuilder()
    for token in document.colors {
      let family = token.path.count > 1 ? token.path.dropLast().joined(separator: "-") : token.key
      let key = token.path.count > 1
        ? ExportOptions.cssIdentifier(token.path.last ?? "", fallback: "")
        : ""
      let text = token.color.cssStringOrHex(as: .native(for: token.color.space), options: .lossless)
      builder.add(ImportedEntry(key: key, color: token.color, text: text, notes: token.description), to: family)
    }

    let skipped = document.skipped.map { ImportSkip(name: $0.name, message: $0.reason.message) }
    return finished(builder, skipped: skipped)
  }

  // MARK: - looseColors

  /// Splits on newlines, commas and semicolons **outside of parentheses** — so
  /// `oklch(0.7 0.2 140), red` is two candidates, not four, and a function call's own
  /// internal commas or spaces never get treated as a separator.
  private static func topLevelSegments(_ text: String) -> [String] {
    var segments: [String] = []
    var current = ""
    var depth = 0
    for character in text {
      switch character {
      case "(":
        depth += 1
        current.append(character)
      case ")":
        depth -= 1
        current.append(character)
      case ",", "\n", ";":
        // Swift gives each pattern in a comma-separated case list its own implicit
        // `where` when only the last one is written explicitly — `case ",", "\n", ";"
        // where depth == 0` guards only `;`, not the two ahead of it. That shipped
        // here once: it split `color-mix(in oklch, red, blue)` into four pieces at
        // every comma regardless of depth, two of which happened to parse as colors
        // on their own ("red", the trailing "#3b82f6") — enough to pass a test that
        // only checked `entries.count`. The explicit `if` below is what actually makes
        // the guard apply to all three separators.
        if depth == 0 {
          segments.append(current)
          current = ""
        } else {
          current.append(character)
        }
      default:
        current.append(character)
      }
    }
    segments.append(current)
    return segments.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
  }

  /// No structure at all: a flat list, one candidate per line or comma. Keys are 1-based
  /// positions — the same fallback ``PaletteNaming/rampKeys(count:)`` uses when nothing
  /// else names a position — except for the single-color case, which gets an empty key
  /// instead: a palette of one is a color, not a scale, matching ``PaletteEntry``'s own
  /// rule for a lone entry everywhere else in this app.
  private static func parseLooseColors(_ text: String) -> ImportedPalette {
    var builder = GroupBuilder()
    var skipped: [ImportSkip] = []
    let family = ExportOptions.defaultName

    for (index, segment) in topLevelSegments(text).enumerated() {
      parseAndAppend(
        key: String(index + 1), rawValue: segment, family: family, diagnosticName: segment,
        into: &builder, skipped: &skipped,
      )
    }

    let groups = builder.groups
    if groups.count == 1, groups[0].entries.count == 1, let entry = groups[0].entries.first {
      return ImportedPalette(
        groups: [ImportedGroup(
          name: family,
          entries: [ImportedEntry(key: "", color: entry.color, text: entry.text, notes: entry.notes)],
        )],
        detectedName: family,
        skipped: skipped,
      )
    }
    return finished(builder, skipped: skipped)
  }
}
