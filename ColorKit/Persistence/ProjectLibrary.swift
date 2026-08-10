//
//  ProjectLibrary.swift
//  ColorKit
//

import Foundation
import SwiftData

/// Every mutation the projects feature performs, in one testable place.
///
/// A thin wrapper over `ModelContext` rather than a store of its own: SwiftData already
/// owns the state, and a second copy of it in an `@Observable` class would be two
/// answers to "what is saved". What this adds is the *rules* — where a new entry's
/// position comes from, what counts as touching a project, which relationship a color
/// belongs to — and having them here rather than inline in the panel is what lets
/// ``ProjectStoreTests`` assert them against an in-memory container instead of through a
/// rendered view.
///
/// Mutations save explicitly rather than leaning on autosave. The main context autosaves
/// on its own schedule, which is fine for an app and useless for a test that wants to
/// fetch back what it just wrote.
@MainActor
struct ProjectLibrary {
  // MARK: Lifecycle

  init(_ context: ModelContext) {
    self.context = context
  }

  // MARK: Internal

  let context: ModelContext

  // MARK: - Reading

  /// Every project, newest first.
  func projects() throws -> [Project] {
    try context.fetch(
      FetchDescriptor<Project>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]),
    )
  }

  /// The project ``ColorStore/selectedProjectID`` names, if it still exists.
  ///
  /// Looked up by ``Project/uuid`` rather than by `PersistentIdentifier` so the selection
  /// can live on a store that does not import SwiftData — see the note on that property.
  func project(uuid: UUID) throws -> Project? {
    var descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.uuid == uuid })
    descriptor.fetchLimit = 1
    return try context.fetch(descriptor).first
  }

  // MARK: - Projects

  @discardableResult
  func createProject(named name: String) throws -> Project {
    let project = Project(name: Self.cleaned(name, fallback: Self.untitledProject))
    context.insert(project)
    try context.save()
    return project
  }

  func rename(_ project: Project, to name: String) throws {
    project.name = Self.cleaned(name, fallback: Self.untitledProject)
    project.touch()
    try context.save()
  }

  /// Deletes a project and, by cascade, everything inside it.
  ///
  /// The cascade is declared on the relationships rather than performed here, so this
  /// cannot fall out of step with a palette added later. ``ProjectStoreTests`` asserts
  /// that nothing survives, because an orphaned `SavedColor` is invisible — it belongs
  /// to no project, so no view would ever show it and no user would ever know.
  func delete(_ project: Project) throws {
    context.delete(project)
    try context.save()
  }

  // MARK: - Colors

  /// Saves one color into a project's loose colors.
  @discardableResult
  func saveColor(
    _ record: ColorRecord,
    named name: String = "",
    to project: Project,
  ) throws -> SavedColor {
    let color = SavedColor(
      record: record,
      name: name.trimmingCharacters(in: .whitespacesAndNewlines),
      sortIndex: Self.nextIndex(after: project.colors.map(\.sortIndex)),
    )
    context.insert(color)
    color.project = project
    project.touch()
    try context.save()
    return color
  }

  /// Saves one color read out of a pasted document (M30) as a loose color.
  ///
  /// **A fifth save door, deliberately — not a widened ``saveColor(_:named:to:)``.** It
  /// writes `ColorRecord(entry.color, text: entry.text)` **verbatim**, never
  /// `.derived(_:preferring:)`, which is the identical rule the fourth `savePalette`
  /// overload exists to protect: the storage-format control's default is "keep as
  /// pasted", and that promise is only real if the stored text is the literal substring
  /// ``PaletteImport`` found rather than a round trip through ``ColorValue`` and back. A
  /// new door into that room is exactly how the rule gets re-broken, so this is its own
  /// door with its own reason rather than a `record:` the caller had to build correctly.
  ///
  /// It also carries ``ImportedEntry/notes``, which ``saveColor(_:named:to:)`` has no
  /// parameter for and which a design token's `$description` rides in on — the second
  /// reason a shared door would not fit.
  ///
  /// The name is the caller's already-resolved choice: an imported color takes its
  /// group's name, *unless* that name is ``ExportOptions/defaultName`` (a placeholder the
  /// loose-color and headerless paths both reach for), in which case the caller passes
  /// empty and the tile falls back to displaying the CSS text. That decision lives at the
  /// call site, beside the same one it already makes for a palette's name.
  @discardableResult
  func saveColor(
    importing entry: ImportedEntry,
    named name: String = "",
    to project: Project,
  ) throws -> SavedColor {
    let color = SavedColor(
      record: ColorRecord(entry.color, text: entry.text),
      name: name.trimmingCharacters(in: .whitespacesAndNewlines),
      notes: entry.notes,
      sortIndex: Self.nextIndex(after: project.colors.map(\.sortIndex)),
    )
    context.insert(color)
    color.project = project
    project.touch()
    try context.save()
    return color
  }

  /// Commits an edit made by binding straight to the model — a renamed color, a note.
  ///
  /// Bindings write to the object the moment a key is pressed, so this is not what makes
  /// the change happen; it is what stamps `modifiedAt` once and flushes, rather than
  /// thirty times on the way through a sentence.
  func touch(_ color: SavedColor) throws {
    color.project?.touch()
    color.palette?.project?.touch()
    try context.save()
  }

  func delete(_ color: SavedColor) throws {
    color.project?.touch()
    color.palette?.project?.touch()
    context.delete(color)
    try context.save()
  }

  /// Moves loose colors within a project, in `onMove` terms: `source` indexes the current
  /// order, and `destination` is a position in that *same, pre-removal* order.
  ///
  /// Positions are renumbered densely from zero afterwards, which is the one place that
  /// happens. ``nextIndex(after:)`` leaves gaps on purpose so a new color lands last even
  /// after deletions, but a gap is only safe while positions are append-only: slotting a
  /// moved color *into* one means picking a value between two neighbours, and two moves
  /// into the same gap collide. Renumbering costs a write per color and removes the
  /// question. Appending still works off the maximum, so `newColorsLandLast` is unaffected.
  func moveColors(fromOffsets source: IndexSet, toOffset destination: Int, in project: Project) throws {
    var ordered = project.orderedColors
    guard let lowest = source.min(), lowest >= 0, let highest = source.max(),
          highest < ordered.count, (0 ... ordered.count).contains(destination)
    else { return }

    let moved = source.map { ordered[$0] }
    // Back to front, so the indices still ahead of the cursor stay valid.
    for index in source.sorted(by: >) {
      ordered.remove(at: index)
    }
    // `destination` counted the pre-removal order, so discount whatever was lifted out
    // from in front of it.
    let insertion = destination - source.filter { $0 < destination }.count
    ordered.insert(contentsOf: moved, at: insertion)

    for (index, color) in ordered.enumerated() {
      color.sortIndex = index
    }
    project.touch()
    try context.save()
  }

  // MARK: - Palettes

  /// Saves a set of colors as a palette, keeping their order and their keys.
  ///
  /// The entries arrive as ``PaletteEntry`` — the same value type the export layer
  /// consumes — so this is the one direction the boundary is crossed in: values in,
  /// models out. A ramp's keys become its entries' names, which is what lets a saved
  /// ramp export as `--brand-500` again months later.
  @discardableResult
  func savePalette(
    _ entries: [PaletteEntry],
    named name: String,
    kind: PaletteKind,
    to project: Project,
  ) throws -> Palette {
    let palette = newPalette(named: name, kind: kind, in: project)

    for (index, entry) in entries.enumerated() {
      let color = SavedColor(
        record: .derived(entry.color, preferring: .oklch),
        name: entry.key,
        sortIndex: index,
      )
      context.insert(color)
      color.palette = palette
    }

    project.touch()
    try context.save()
    return palette
  }

  /// Saves a hand-picked set of a project's loose colors as a palette.
  ///
  /// Separate from the ``PaletteEntry`` overload rather than converting into it, and the
  /// difference is the whole reason this exists. That one takes *derived* colors — a ramp
  /// stop, a harmony member — which have no authored spelling of their own, so it invents
  /// one with ``ColorRecord/derived(_:preferring:)``. These colors already have one, typed
  /// by the user; routing them through the same door would canonicalize `rebeccapurple`
  /// into `oklch(…)` and quietly contradict the panel's own promise that a saved color
  /// keeps the spelling it was saved with. Copying ``SavedColor/record`` carries the text,
  /// the components and the `missing` mask across intact.
  ///
  /// The colors are copied, not moved: a loose color put into a palette stays loose too.
  /// `SavedColor` belongs to a project *or* a palette, so the alternative is removing it
  /// from the grid it was just selected in.
  @discardableResult
  func savePalette(
    from colors: [SavedColor],
    named name: String,
    to project: Project,
  ) throws -> Palette {
    let palette = newPalette(named: name, kind: .custom, in: project)

    let keys = Self.paletteKeys(for: colors)
    for (index, color) in colors.enumerated() {
      let copy = SavedColor(record: color.record, name: keys[index], sortIndex: index)
      context.insert(copy)
      copy.palette = palette
    }

    project.touch()
    try context.save()
    return palette
  }

  /// Saves the color tokens read out of a design token file as a palette.
  ///
  /// **A third overload rather than a conversion into either of the two above**, for the
  /// reason that keeps those two apart: what differs is how a stored *spelling* is
  /// derived, and that is the one thing routing through a shared door destroys. The
  /// `PaletteEntry` overload spells everything `oklch()` because a ramp stop and a
  /// harmony member have no space of their own to keep. A design token does — its
  /// `colorSpace` is written down in the file — so each color is spelled in the space it
  /// arrived in, and a `display-p3` token comes back `color(display-p3 …)` rather than
  /// canonicalized. That is the same objection this app makes to rewriting a typed
  /// `rebeccapurple`, applied to somebody else's authoring instead of your own.
  ///
  /// Keys arrive already sanitized and already unique — see
  /// ``DesignTokenImport/keyed(_:)`` — so unlike the hand-picked overload this one does
  /// no deduplication of its own. Both facts are pinned by tests, because a key that
  /// collides costs a color silently.
  ///
  /// `$description` becomes the color's notes, which is the field it was already for.
  @discardableResult
  func savePalette(
    importing tokens: [DesignToken],
    named name: String,
    to project: Project,
  ) throws -> Palette {
    let palette = newPalette(named: name, kind: .imported, in: project)

    for (index, token) in tokens.enumerated() {
      let color = SavedColor(
        record: .derived(token.color, preferring: .native(for: token.color.space)),
        name: token.key,
        notes: token.description,
        sortIndex: index,
      )
      context.insert(color)
      color.palette = palette
    }

    project.touch()
    try context.save()
    return palette
  }

  /// Saves the colors read out of a pasted document (M26) as a palette.
  ///
  /// **A fourth overload rather than a conversion into any of the three above**, and the
  /// reason repeats: what differs between all four is how a stored *spelling* is
  /// derived, and that is exactly what routing through a shared door would destroy. This
  /// one writes ``ImportedEntry/text`` verbatim — never `.derived(_:preferring:)`, which
  /// re-spells — because the storage-format control's default is "keep as pasted", and
  /// that promise is only real if the stored text is the literal substring
  /// ``PaletteImport`` found rather than a round trip through ``ColorValue`` and back.
  /// When the sheet's control instead asks for a specific format, the *caller* rewrites
  /// each entry's `text` before this is reached — the same discipline
  /// `ColorStore.respell(as:)` (M25) uses to keep a clicked format from being
  /// second-guessed.
  ///
  /// Keys arrive already sanitized and already unique — see
  /// ``PaletteImport/uniquingKeys(_:)`` — so like the design-token overload this one does
  /// no deduplication of its own.
  ///
  /// `.imported` is shared with the design-token overload rather than given a case of its
  /// own: both mean the identical thing, "somebody else's names, read out of a file (or a
  /// paste box) rather than generated by a tool in this app."
  @discardableResult
  func savePalette(
    importing entries: [ImportedEntry],
    named name: String,
    to project: Project,
  ) throws -> Palette {
    let palette = newPalette(named: name, kind: .imported, in: project)

    for (index, entry) in entries.enumerated() {
      let color = SavedColor(
        record: ColorRecord(entry.color, text: entry.text),
        name: entry.key,
        notes: entry.notes,
        sortIndex: index,
      )
      context.insert(color)
      color.palette = palette
    }

    project.touch()
    try context.save()
    return palette
  }

  func rename(_ palette: Palette, to name: String) throws {
    palette.name = Self.cleaned(name, fallback: palette.kind.title)
    palette.project?.touch()
    try context.save()
  }

  func delete(_ palette: Palette) throws {
    palette.project?.touch()
    context.delete(palette)
    try context.save()
  }

  // MARK: - Renaming what you saved (M32)

  /// Renames a loose color — a **label**, never syntax.
  ///
  /// Both this and ``rekey(_:to:)`` write ``SavedColor/name``, and that is exactly why
  /// they must not share a door. This one has no fallback and must **not** route
  /// through ``cleaned(_:fallback:)``: `saved.name.isEmpty ? saved.text : saved.name`
  /// is the display rule everywhere a saved color is shown, so an empty name is not an
  /// error here, it is how a color that was never given a label falls back to the CSS
  /// it was saved with instead of a manufactured one. ``rekey(_:to:)`` exists because a
  /// palette entry's empty name means something different — it is the entry's *export
  /// key*, and leaving that blank is not "no label", it is "no property".
  func rename(_ color: SavedColor, to name: String) throws {
    color.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    color.project?.touch()
    color.palette?.project?.touch()
    try context.save()
  }

  /// Renames a palette entry's export key — **syntax**, not a label.
  ///
  /// ``SavedColor/name`` doubles as a palette entry's key (see that type's own doc
  /// comment): it becomes a CSS custom property and a bare JavaScript object key, so
  /// changing it is a different act from ``rename(_:to:)``, which only changes what a
  /// tile is called. An empty result therefore falls back to the entry's **position** —
  /// `1`, `2`, … — the same fallback ``paletteKeys(for:)`` already writes for an entry
  /// that arrives with no name of its own, rather than to nothing at all.
  ///
  /// The candidate is deduplicated against its siblings' **sanitized** keys, never
  /// their raw names — the same distinction ``DesignTokenImport/keyed(_:)`` draws for a
  /// token's path, and for the identical reason: `-` is a legal identifier character
  /// and `.` is not, so two visually distinct names can still collide once
  /// ``ExportOptions/cssIdentifier(_:fallback:)`` gets hold of them. Two entries
  /// sharing a key do not produce a duplicate property — they collapse into one, and a
  /// color silently disappears from the export with nothing in the document to say so.
  func rekey(_ entry: SavedColor, to name: String) throws {
    guard let palette = entry.palette else { return }
    let ordered = palette.orderedEntries
    guard let position = ordered.firstIndex(where: {
      $0.persistentModelID == entry.persistentModelID
    }) else { return }

    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let candidate = trimmed.isEmpty ? String(position + 1) : trimmed
    let siblingNames = ordered
      .filter { $0.persistentModelID != entry.persistentModelID }
      .map(\.name)

    entry.name = Self.dedupedKey(candidate, against: siblingNames)
    palette.project?.touch()
    try context.save()
  }

  // MARK: Private

  private static let untitledProject = "Untitled Project"

  /// Trimmed, and never empty. A blank name is a row you cannot click on in a list, so
  /// the fallback is applied at the point of storage rather than at the point of
  /// display — where every future view would have to remember it.
  private static func cleaned(_ name: String, fallback: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? fallback : trimmed
  }

  /// One past the highest position in use, so a new entry lands at the end even after
  /// deletions have left gaps. `count` would collide: delete the middle of three and the
  /// next insert would reuse position 2.
  private static func nextIndex(after existing: [Int]) -> Int {
    (existing.max() ?? -1) + 1
  }

  /// Export keys for a hand-picked set: the color's own name where it has one, its
  /// position where it does not.
  ///
  /// The deduplication is not defensive tidying. A key becomes a CSS custom property and a
  /// JavaScript object key, so two entries sharing one do not produce a duplicate — they
  /// produce a *single* property, and a color disappears from the export with nothing in
  /// the document to say so. Derived palettes never hit this because their keys are
  /// generated distinct; a set the user assembled by hand has no such guarantee, and two
  /// colors named "blue" is an ordinary thing to have.
  private static func paletteKeys(for colors: [SavedColor]) -> [String] {
    var used: Set<String> = []
    return colors.enumerated().map { index, color in
      let named = color.name.trimmingCharacters(in: .whitespacesAndNewlines)
      var key = named.isEmpty ? String(index + 1) : named
      if used.contains(key) {
        var suffix = 2
        while used.contains("\(key)-\(suffix)") {
          suffix += 1
        }
        key = "\(key)-\(suffix)"
      }
      used.insert(key)
      return key
    }
  }

  /// `candidate`, suffixed until its **sanitized** form no longer collides with any of
  /// `siblingNames`'s own sanitized forms. See ``rekey(_:to:)``.
  ///
  /// Comparing sanitized rather than raw is the whole point — two entries named
  /// `brand.500` and `brand-500` look distinct and are not once
  /// ``ExportOptions/cssIdentifier(_:fallback:)`` gets hold of them, so a raw-text
  /// comparison (what ``paletteKeys(for:)`` above does, for a set with no such hazard)
  /// would let the collision through.
  private static func dedupedKey(_ candidate: String, against siblingNames: [String]) -> String {
    let used = Set(siblingNames.map { ExportOptions.cssIdentifier($0, fallback: "") })
    guard used.contains(ExportOptions.cssIdentifier(candidate, fallback: "")) else { return candidate }

    var suffix = 2
    while used.contains(ExportOptions.cssIdentifier("\(candidate)-\(suffix)", fallback: "")) {
      suffix += 1
    }
    return "\(candidate)-\(suffix)"
  }

  /// The part of saving a palette that is genuinely the same for all three overloads:
  /// an empty palette, named, positioned and attached.
  ///
  /// Extracted *because* the three must not be merged. What differs between them is how
  /// each color's stored spelling is derived, and three identical copies of this
  /// boilerplate is precisely what invites somebody to unify the overloads and destroy
  /// that — see the notes on each. Sharing the part that carries no decision leaves the
  /// parts that do standing alone, where they read as choices rather than as duplication.
  private func newPalette(named name: String, kind: PaletteKind, in project: Project) -> Palette {
    let palette = Palette(
      name: Self.cleaned(name, fallback: kind.title),
      kind: kind,
      sortIndex: Self.nextIndex(after: project.palettes.map(\.sortIndex)),
    )
    context.insert(palette)
    palette.project = project
    return palette
  }
}
