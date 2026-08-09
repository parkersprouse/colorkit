//
//  ProjectsPanel.swift
//  ColorKit
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// What a dragged swatch carries: its position in the grid, and nothing else.
///
/// A position rather than an identity because ``ProjectLibrary/moveColors(fromOffsets:toOffset:in:)``
/// already speaks in offsets, and because `SavedColor` has no identifier that survives
/// leaving the process — `PersistentIdentifier` is not `Codable` in a form another app
/// could act on, which is the right outcome here anyway.
///
/// The app-owned content type is what keeps this drag *inside* the grid. With a plain-text
/// representation the tiles would happily accept any string dragged in from any app and
/// try to read a position out of it.
///
/// ``UTType/savedColorPosition`` is declared in `UTExportedTypeDeclarations` in the repo
/// root's `Info.plist`. `UTType(exportedAs:)` yields a working identifier without it — the
/// drag functions, since both ends compare the same string — but the system never
/// registers the type and every launch logs that it was expected to be declared. Deleting
/// the declaration brings that warning back rather than breaking anything, which is
/// exactly why it is easy to lose.
private nonisolated struct SavedColorDrag: Codable, Transferable {
  nonisolated static var transferRepresentation: some TransferRepresentation {
    CodableRepresentation(contentType: .savedColorPosition)
  }

  let position: Int
}

private nonisolated extension UTType {
  static let savedColorPosition = UTType(
    exportedAs: "me.parkersprouse.colorkit.saved-color-position",
  )
}

/// The colors you decided to keep.
///
/// Every other tool answers a question about the color in the field and forgets it the
/// moment the field changes; this one is the only place the app remembers anything on
/// purpose. So the two directions it runs in are the whole feature: **saving** what the
/// other tools produced, and **recalling** it into the field they all read from.
///
/// **The panel owns the only `@Query` and the only `modelContext` in the app.** Nothing
/// downstream of here knows SwiftData exists — a palette leaves as `[PaletteEntry]`,
/// which is the same value type a harmony produces, which is why exporting a saved
/// palette needed one enum case rather than a second path through the export layer. The
/// mutations themselves live in ``ProjectLibrary`` so their rules can be tested against
/// a container instead of through a rendered view.
struct ProjectsPanel: View {
  // MARK: Internal

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        if storeStatus == .unavailable {
          unavailableBanner
        }
        if let message = errorMessage {
          Label(message, systemImage: "exclamationmark.triangle")
            .font(.callout)
            .foregroundStyle(.secondary)
        }

        if projects.isEmpty {
          emptyState
        } else {
          header
          if let project = selectedProject {
            Divider()
            saveControls(project)
            colorsSection(project)
            palettesSection(project)
          }
        }
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  // MARK: Private

  /// The sets worth keeping. ``ExportSource/color`` is absent because Save Color already
  /// does that one, and ``ExportSource/saved`` because saving a saved palette back into
  /// the project it came from is a loop with nothing at the end of it.
  private static let savableSets: [ExportSource] = [.harmony, .ramp, .recents]

  @Environment(ColorStore.self) private var store
  @Environment(\.modelContext) private var context
  @Environment(\.projectStoreStatus) private var storeStatus

  /// Newest first, matching ``ProjectLibrary/projects()`` — the panel and the tests
  /// should not disagree about what "first" means.
  @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]

  /// The name a save will use. One field for both buttons, because naming the thing you
  /// are about to keep is the same act whether it is one color or eleven.
  @State private var entryName = ""
  @State private var errorMessage: String?
  @State private var confirmingProjectDeletion = false

  /// Whether the open panel is up, and what the last import came back with.
  ///
  /// The summary is separate from ``errorMessage`` rather than folded into it because an
  /// import routinely half-succeeds — eleven colors in, three tokens skipped — and that is
  /// neither an error nor silence.
  @State private var isImporting = false
  @State private var importSummary: String?

  /// Whether the M26 paste-a-document sheet is up. Shares ``importSummary`` with the
  /// token-file import above it — both are "the last thing Import did", and a user
  /// switching between the two menu items should not need two different places to look
  /// for what happened.
  @State private var isImportingText = false

  /// Which saved color's notes are open. A `@Model` is `Identifiable`, so this drives
  /// `.popover(item:)` directly.
  @State private var noteTarget: SavedColor?

  /// Which colors are ticked for "Save Selection".
  ///
  /// Held by `PersistentIdentifier` rather than by position, because a reorder or a delete
  /// renumbers positions underneath it and the selection would silently come to mean
  /// different colors. Stale identifiers are filtered at read time rather than pruned on
  /// every change — a deleted color simply stops matching.
  @State private var selection: Set<PersistentIdentifier> = []

  private var library: ProjectLibrary {
    ProjectLibrary(context)
  }

  /// The selected project, falling back to the newest.
  ///
  /// A fallback rather than a write, because this is read during `body`: correcting the
  /// stored selection here would mutate observed state mid-update. The selection is only
  /// ever written by the picker and by ``create()``.
  private var selectedProject: Project? {
    projects.first { $0.uuid == store.selectedProjectID } ?? projects.first
  }

  // MARK: - Chrome

  /// Shown only for ``PersistenceStack/Status/unavailable``, never for a store that is
  /// ephemeral because a test asked it to be. Silence in the failing case would be the
  /// worst option available — the panel would work perfectly and lose everything at
  /// quit — but a warning shown when nothing is wrong is a warning nobody reads.
  private var unavailableBanner: some View {
    Label(
      "Saving is not available — the projects store could not be opened, so anything "
        + "saved here lasts only until you quit.",
      systemImage: "exclamationmark.triangle.fill",
    )
    .font(.callout)
    .foregroundStyle(.secondary)
    .fixedSize(horizontal: false, vertical: true)
  }

  private var emptyState: some View {
    ContentUnavailableView {
      Label("No projects yet", systemImage: "folder")
    } description: {
      Text("A project is somewhere to keep the colors and palettes you want back later.")
    } actions: {
      Button("New Project") { create() }
        .accessibilityIdentifier("projectsNew")
    }
    .frame(maxWidth: .infinity)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 12) {
      LabeledContent("Project") {
        HStack(spacing: 8) {
          Picker(
            "Project",
            selection: Binding(
              get: { selectedProject?.uuid },
              set: { store.selectedProjectID = $0 },
            ),
          ) {
            ForEach(projects) { project in
              Text(project.name).tag(Optional(project.uuid))
            }
          }
          .labelsHidden()
          .accessibilityIdentifier("projectsPicker")

          Button("New") { create() }
            .accessibilityIdentifier("projectsNew")

          Button("Delete", role: .destructive) { confirmingProjectDeletion = true }
            .accessibilityIdentifier("projectsDelete")
            .disabled(selectedProject == nil)

          // The whole-project counterpart to each palette row's own Export button
          // below — M20. Disabled rather than hidden when there is nothing in the
          // project yet, matching every other save/export control here.
          Button("Export Project") { exportProject() }
            .accessibilityIdentifier("projectExport")
            .disabled(selectedProject.map { $0.colors.isEmpty && $0.palettes.isEmpty } ?? true)
        }
      }

      if let project = selectedProject {
        // Bound straight to the model, which SwiftData observes, so typing renames in
        // place. Committing on submit rather than per keystroke is what applies the
        // empty-name fallback and stamps `modifiedAt` once instead of thirty times.
        LabeledContent("Name") {
          @Bindable var project = project
          TextField("Name", text: $project.name)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 240)
            .accessibilityIdentifier("projectName")
            .onSubmit { perform { try library.rename(project, to: project.name) } }
        }
      }
    }
    .confirmationDialog(
      "Delete “\(selectedProject?.name ?? "")”?",
      isPresented: $confirmingProjectDeletion,
    ) {
      Button("Delete Project", role: .destructive) {
        guard let project = selectedProject else { return }
        perform {
          try library.delete(project)
          store.selectedProjectID = nil
        }
      }
    } message: {
      Text("Its colors and palettes go with it. This cannot be undone.")
    }
  }

  // MARK: - Saving

  private func saveControls(_ project: Project) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      LabeledContent("Save as") {
        TextField("Save as", text: $entryName, prompt: Text("Optional name"))
          .textFieldStyle(.roundedBorder)
          .frame(maxWidth: 240)
          .accessibilityIdentifier("saveName")
      }

      HStack(spacing: 8) {
        Button("Save Color") { saveColor(to: project) }
          .disabled(store.color == nil)
          .accessibilityIdentifier("saveColor")

        // The sets the other tools are producing right now, asked for by name rather
        // than read off `exportSource` — saving the harmony while the export panel is
        // set to something else is an ordinary thing to want.
        Menu("Save Set") {
          ForEach(Self.savableSets, id: \.self) { source in
            Button(source.title) { savePalette(store.entries(for: source), source, to: project) }
              .disabled(store.entries(for: source).isEmpty)
          }
        }
        .fixedSize()
        .accessibilityIdentifier("saveSet")

        // A set the user assembled by hand, rather than one a tool produced. Kept beside
        // the generated sets because it answers the same question — what is worth keeping
        // together — and disabled rather than hidden so the tick marks have a visible
        // destination before anything is ticked.
        Button("Save Selection") { saveSelection(to: project) }
          .disabled(selectedColors(in: project).isEmpty)
          .accessibilityIdentifier("saveSelection")

        // The one control here that brings colors in from outside the app rather than
        // from another of its tools. Beside the save buttons because it answers the same
        // question they do — what ends up in this project — and because an import lands
        // as a palette, which is what the two buttons to its left produce.
        //
        // A `Menu` rather than the plain `Button` this was before M26, because the row
        // stays at four controls that way — the tool switcher's own lesson: an eighth
        // segment there is what swept it into an overflow menu, not one more choice
        // behind an existing control. `Menu`'s own accessibility identifier is what a
        // test opens the menu through, matching every other `menuButton` query in
        // ``ProjectsSmokeTests``.
        Menu("Import") {
          Button("From Text…") { isImportingText = true }
            .accessibilityIdentifier("importFromText")
          Button("From Token File…") { isImporting = true }
            .accessibilityIdentifier("importTokens")
        }
        .fixedSize()
        .accessibilityIdentifier("importMenu")
      }

      if let summary = importSummary {
        Text(summary)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("importSummary")
      }

      Text(
        "Saved colors keep the spelling you typed, so a recalled color comes back as "
          + "you wrote it rather than canonicalized. Drag a swatch to reorder, or tick "
          + "several and save them as a palette.",
      )
      .font(.caption)
      .foregroundStyle(.tertiary)
      .fixedSize(horizontal: false, vertical: true)
    }
    // `.json` covers the conventional `name.tokens.json`; the bare `.tokens` spelling
    // exists too and has no registered type, so it is admitted by extension. A dynamic
    // type is the whole cost of that, and the alternative is a file the panel refuses to
    // show for no reason a user could work out.
    .fileImporter(
      isPresented: $isImporting,
      allowedContentTypes: [.json] + (UTType(filenameExtension: "tokens").map { [$0] } ?? []),
    ) { result in
      importTokens(result, into: project)
    }
    .sheet(isPresented: $isImportingText) {
      ImportTextSheet(initialProjectID: project.uuid) { importedProjectID, summary in
        store.selectedProjectID = importedProjectID
        importSummary = summary
      }
    }
  }

  // MARK: - Contents

  private func colorsSection(_ project: Project) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Colors").font(.headline)

      if project.colors.isEmpty {
        Text("No colors saved in this project yet.")
          .font(.callout)
          .foregroundStyle(.secondary)
      } else {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 66), spacing: 10)], spacing: 10) {
          ForEach(Array(project.orderedColors.enumerated()), id: \.element.persistentModelID) {
            index, saved in
            savedColorTile(saved, index: index)
          }
        }
        // One popover for the grid rather than one per tile: `item:` already carries
        // which color is being edited, and forty tiles each holding their own would be
        // forty pieces of state for a thing only ever open once.
        .popover(item: $noteTarget) { saved in
          notesEditor(saved)
        }
      }
    }
  }

  /// Why a color was kept, which the swatch cannot say and the name should not have to.
  ///
  /// A popover rather than a field in the grid: notes are the least-used thing here and
  /// giving every tile a permanent text box would bury the colors under them.
  private func notesEditor(_ saved: SavedColor) -> some View {
    @Bindable var saved = saved

    return VStack(alignment: .leading, spacing: 8) {
      Text(saved.name.isEmpty ? saved.text : saved.name)
        .font(.headline)
      TextField("Notes", text: $saved.notes, prompt: Text("What this is for"), axis: .vertical)
        .lineLimit(3 ... 6)
        .textFieldStyle(.roundedBorder)
        .frame(width: 260)
        .accessibilityIdentifier("savedColorNotes")
      Text("Saved as \(saved.text)")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(12)
    // Bound straight to the model, so edits are live; the save is stamped once on the
    // way out rather than on every keystroke.
    .onDisappear { perform { try library.touch(saved) } }
  }

  /// One saved color: click to put it back in the field.
  ///
  /// The button carries the color's CSS as its accessibility label, for the reason every
  /// swatch in this app does — a colored rectangle says nothing to VoiceOver, and it is
  /// the only handle a UI test has on a grid of them.
  private func savedColorTile(_ saved: SavedColor, index: Int) -> some View {
    VStack(spacing: 4) {
      // The tick is a *sibling* of the swatch, not an overlay on it. A SwiftUI `Button`
      // is a single accessibility element, so anything layered over one is swallowed:
      // the tick vanished from the tree entirely, and `savedColor-N` began matching two
      // elements at once and broke a test that had nothing to do with any of this.
      ZStack(alignment: .topTrailing) {
        if let color = saved.colorValue {
          // The selection ring is a sibling in this ZStack, not an overlay on the
          // button `SwatchButton` wraps — the trap noted just above this function.
          ZStack {
            SwatchButton(
              color: color,
              text: saved.text,
              cornerRadius: 6,
              accessibilityIdentifier: "savedColor-\(index)",
            ) {
              savedColorMenu(saved, index: index)
            }
            RoundedRectangle(cornerRadius: 6)
              .strokeBorder(.tint, lineWidth: 2)
              .opacity(selection.contains(saved.persistentModelID) ? 1 : 0)
              .allowsHitTesting(false)
          }
          .frame(width: 44, height: 44)
          .help(tooltip(saved))
        } else {
          // A row this build cannot read. Shown rather than hidden, because a color
          // silently missing from a project is worse than one that says it is — still
          // a plain `Button`, not a `SwatchButton`, since there is no `ColorValue` to
          // hand one; the stored text is still worth recalling, so the tap survives.
          Button {
            store.inputText = saved.text
            store.remember()
          } label: {
            ZStack {
              RoundedRectangle(cornerRadius: 6).fill(.quaternary)
              Image(systemName: "questionmark").foregroundStyle(.secondary)
            }
            .frame(width: 44, height: 44)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(saved.text)
          .accessibilityIdentifier("savedColor-\(index)")
          .help(tooltip(saved))
          .contextMenu { savedColorMenu(saved, index: index) }
        }

        selectionBadge(saved, index: index)
      }
      // On the tile, not on the button inside it. Recorded as a placement, not a rule:
      // whether a `Button` would consume the press a drag needs is *not* established.
      // Moving the modifier here changed nothing observable, and the test that would
      // have settled it cannot drive a drag either way — see the note on XCUITest and
      // dragging sessions in CLAUDE.md.
      //
      // Position in, position out. The drop lands on a *tile*, so the target index is
      // where the color should end up rather than an `onMove` slot — `move(from:to:)`
      // converts between the two.
      .draggable(SavedColorDrag(position: index))
      .dropDestination(for: SavedColorDrag.self) { items, _ in
        guard let dragged = items.first, let project = saved.project else { return false }
        move(from: dragged.position, to: index, in: project)
        return true
      }

      Text(saved.name.isEmpty ? saved.text : saved.name)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)
        .frame(maxWidth: 62)
    }
  }

  /// The saved-color-specific commands, shared by both branches of `savedColorTile` — the
  /// readable one, where they extend `SwatchButton`'s own menu, and the unreadable
  /// fallback, which has no `SwatchButton` to extend and attaches this directly.
  @ViewBuilder
  private func savedColorMenu(_ saved: SavedColor, index: Int) -> some View {
    Button(selection.contains(saved.persistentModelID) ? "Deselect" : "Select") {
      toggleSelection(saved)
    }

    // The same move the drag performs, reachable without one. A drag is the only
    // affordance a pointer wants and the only one a keyboard or VoiceOver user cannot
    // use at all, which would make reordering the one thing in this panel that some
    // people simply could not do. Both paths call `move(from:to:)`.
    Button("Move Left") { moveTile(saved, from: index, by: -1) }
      .disabled(index == 0)
    Button("Move Right") { moveTile(saved, from: index, by: 1) }
      .disabled(index == (saved.project?.colors.count ?? 0) - 1)

    Button("Notes…") { noteTarget = saved }
    Button("Delete", role: .destructive) {
      // Cleared first: the popover holds this object, and leaving it pointed at a
      // deleted model is a reference to a row that no longer exists.
      if noteTarget?.persistentModelID == saved.persistentModelID {
        noteTarget = nil
      }
      perform { try library.delete(saved) }
    }
  }

  /// The tick that puts a color into "Save Selection".
  ///
  /// Always drawn rather than revealed on hover, and that is a testability decision as
  /// much as a discoverability one: a control that only exists under the pointer is a
  /// control XCUITest cannot wait on for hittability. Unselected it is faint enough to
  /// read as chrome; the tinted ring on the swatch is what actually carries the state.
  private func selectionBadge(_ saved: SavedColor, index: Int) -> some View {
    let isSelected = selection.contains(saved.persistentModelID)

    return Button {
      toggleSelection(saved)
    } label: {
      Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
        .font(.system(size: 13))
        .symbolRenderingMode(.palette)
        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary),
                         isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear))
        .background(Circle().fill(.background).padding(1))
    }
    .buttonStyle(.plain)
    // Kept inside the tile's bounds rather than hung off the corner: a control that
    // straddles the edge of its container loses hittability at the overhang.
    .offset(x: -2, y: 2)
    .accessibilityLabel(isSelected ? "Deselect \(saved.text)" : "Select \(saved.text)")
    .accessibilityIdentifier("selectColor-\(index)")
  }

  private func palettesSection(_ project: Project) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Palettes").font(.headline)

      if project.palettes.isEmpty {
        Text("No palettes saved yet — build a harmony or a ramp, then Save Set.")
          .font(.callout)
          .foregroundStyle(.secondary)
      } else {
        ForEach(Array(project.orderedPalettes.enumerated()), id: \.element.persistentModelID) {
          index, palette in
          paletteRow(palette, index: index)
        }
      }
    }
  }

  private func paletteRow(_ palette: Palette, index: Int) -> some View {
    let entries = palette.paletteEntries

    return VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Text(palette.name).font(.callout.weight(.medium))
        ColorBadge(text: palette.kind.title, tint: .secondary)
        Spacer()
        Button("Export") { store.stage(entries, named: palette.name) }
          .disabled(entries.isEmpty)
          .accessibilityIdentifier("paletteExport-\(index)")
        Button("Delete", role: .destructive) { perform { try library.delete(palette) } }
          .accessibilityIdentifier("paletteDelete-\(index)")
      }

      HStack(alignment: .top, spacing: 4) {
        ForEach(Array(entries.enumerated()), id: \.offset) { entryIndex, entry in
          // The key moves to a caption underneath, matching `ExportPanel.swatches` —
          // `SwatchButton`'s accessibility label is always the color's own CSS, never
          // a caller-chosen name, which is what makes a row of these testable at all:
          // a ramp that silently repeated a stop would fail a distinctness check on
          // the label, and a label that instead read the key could not catch that.
          VStack(spacing: 2) {
            SwatchButton(
              color: entry.color,
              cornerRadius: 4,
              accessibilityIdentifier: "palette-\(index)-swatch-\(entryIndex)",
            )
            .frame(width: 24, height: 24)
            if !entry.key.isEmpty {
              Text(entry.key)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
            }
          }
        }
      }
    }
    .padding(10)
    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
  }

  /// What the imported palette is called: the file's name, minus the extensions that only
  /// say what kind of file it is.
  ///
  /// `brand.tokens.json` is the conventional spelling, and dropping one extension leaves
  /// `brand.tokens` — a palette named after a file format rather than after a brand.
  private static func paletteName(for url: URL) -> String {
    let stem = url.deletingPathExtension().lastPathComponent
    return stem.hasSuffix(".tokens") ? String(stem.dropLast(".tokens".count)) : stem
  }

  private static func summary(_ document: DesignTokenDocument, from url: URL) -> String {
    var parts = ["Imported \(counted(document.colors.count, "color")) from \(url.lastPathComponent)."]
    if document.otherTypeCount > 0 {
      parts.append("Ignored \(counted(document.otherTypeCount, "token")) of other types.")
    }
    if let note = skippedNote(document.skipped) {
      parts.append(note)
    }
    return parts.joined(separator: " ")
  }

  /// Why a file that read perfectly well produced nothing.
  ///
  /// Distinct from every message above it: the file was found, opened and understood. One
  /// of the two counts is necessarily non-zero here — a file with no tokens at all throws
  /// ``DesignTokenError/noTokens`` and never reaches this.
  private static func nothingImported(_ document: DesignTokenDocument) -> String {
    guard let note = skippedNote(document.skipped) else {
      return "No color tokens in that file — its \(counted(document.otherTypeCount, "token")) "
        + "have some other “$type”."
    }
    return "No colors imported. " + note
  }

  /// The first failure in full, and a count of the rest.
  ///
  /// One reason rather than all of them, because the reasons repeat: a file with a
  /// misspelled color space has that same complaint forty times, and forty lines of it
  /// would bury the count.
  ///
  /// "Token", not "color token", and the imprecision is the honest direction: a token
  /// whose reference does not resolve is reported before its `$type` can be known, so
  /// some of these may not have been colors at all.
  private static func skippedNote(_ skipped: [SkippedToken]) -> String? {
    guard let first = skipped.first else { return nil }
    let head = "Skipped \(counted(skipped.count, "token")) — “\(first.name)”: \(first.reason.message)"
    return skipped.count == 1 ? head : head + " (\(skipped.count - 1) more like it.)"
  }

  private static func counted(_ count: Int, _ noun: String) -> String {
    "\(count) \(noun)\(count == 1 ? "" : "s")"
  }

  /// Palettes first, then one single-entry group per loose color — a ramp is the thing
  /// you came for and a loose color is a note beside it.
  ///
  /// Each loose color's entry carries an **empty key**, the same rule
  /// ``PaletteEntry`` documents for a palette of one: it is what turns a project color
  /// named `text color` into a one-entry group that renders `--text-color` rather than
  /// a suffix nothing would reference. The group is named after the color's label —
  /// its own name if it has one, its authored text otherwise — matching how the tile
  /// below labels itself.
  private static func exportGroups(for project: Project) -> [PaletteGroup] {
    let palettes = project.orderedPalettes.map {
      PaletteGroup(name: $0.name, entries: $0.paletteEntries)
    }
    let colors = project.orderedColors.compactMap { saved -> PaletteGroup? in
      guard let color = saved.colorValue else { return nil }
      let label = saved.name.isEmpty ? saved.text : saved.name
      return PaletteGroup(name: label, entries: [PaletteEntry(color: color)])
    }
    return palettes + colors
  }

  /// Name, spelling and notes, in whatever combination exists.
  private func tooltip(_ saved: SavedColor) -> String {
    let heading = saved.name.isEmpty ? saved.text : "\(saved.name) — \(saved.text)"
    return saved.notes.isEmpty ? heading : "\(heading)\n\(saved.notes)"
  }

  private func create() {
    perform {
      let project = try library.createProject(named: entryName)
      store.selectedProjectID = project.uuid
      entryName = ""
    }
  }

  private func saveColor(to project: Project) {
    guard let color = store.color else { return }
    perform {
      // The field's own text, so the spelling survives — see `ColorRecord`.
      try library.saveColor(
        ColorRecord(color, text: store.inputText.trimmingCharacters(in: .whitespacesAndNewlines)),
        named: entryName,
        to: project,
      )
      entryName = ""
    }
  }

  private func savePalette(_ entries: [PaletteEntry], _ source: ExportSource, to project: Project) {
    guard !entries.isEmpty else { return }
    perform {
      try library.savePalette(entries, named: entryName, kind: source.paletteKind, to: project)
      entryName = ""
    }
  }

  // MARK: - Exporting the whole project

  /// Stages every palette and loose color in `project` as named groups and switches to
  /// the export panel. See M20 in PLAN.md.
  private func exportProject() {
    guard let project = selectedProject else { return }
    store.stage(project: Self.exportGroups(for: project), named: project.name)
  }

  // MARK: - Importing

  /// Reads a W3C design token file and saves its colors as a palette.
  ///
  /// **Every failure mode gets its own sentence, and that is not politeness.** This is the
  /// app's only file read, so it is the only place a *sandbox* denial can happen — and a
  /// denial that reported as "no color tokens in that file" would be undiagnosable, since
  /// the file plainly has them. So: the panel dismissal, the read, the decode, the
  /// "readable file with nothing importable in it", and the save are five outcomes with
  /// five messages.
  ///
  /// The security-scoped access is what makes the read legal at all. The app is sandboxed
  /// with `ENABLE_USER_SELECTED_FILES = readonly`, which grants a URL the user chose in an
  /// open panel — but the grant has to be *claimed*, and the failure without it is a
  /// permission error on a file the user just picked.
  private func importTokens(_ result: Result<URL, Error>, into project: Project) {
    importSummary = nil

    guard case let .success(url) = result else {
      if case let .failure(error) = result {
        errorMessage = "Could not open that file: \(error.localizedDescription)"
      }
      return
    }

    let scoped = url.startAccessingSecurityScopedResource()
    defer {
      if scoped {
        url.stopAccessingSecurityScopedResource()
      }
    }

    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch {
      errorMessage = "Could not read \(url.lastPathComponent): \(error.localizedDescription)"
      return
    }

    let document: DesignTokenDocument
    do {
      document = try DesignTokenImport.decode(data)
    } catch {
      errorMessage = error.message
      return
    }

    guard !document.colors.isEmpty else {
      errorMessage = Self.nothingImported(document)
      return
    }

    perform {
      try library.savePalette(
        importing: document.colors,
        named: Self.paletteName(for: url),
        to: project,
      )
      importSummary = Self.summary(document, from: url)
    }
  }

  /// The ticked colors, in the order they appear rather than the order they were ticked.
  ///
  /// Derived from `orderedColors` rather than stored, so a selection made before a
  /// reorder still exports in the order the grid is showing — and so identifiers left
  /// behind by a deleted color drop out instead of having to be swept up.
  private func selectedColors(in project: Project) -> [SavedColor] {
    project.orderedColors.filter { selection.contains($0.persistentModelID) }
  }

  private func toggleSelection(_ saved: SavedColor) {
    if selection.contains(saved.persistentModelID) {
      selection.remove(saved.persistentModelID)
    } else {
      selection.insert(saved.persistentModelID)
    }
  }

  private func saveSelection(to project: Project) {
    let colors = selectedColors(in: project)
    guard !colors.isEmpty else { return }
    perform {
      try library.savePalette(from: colors, named: entryName, to: project)
      entryName = ""
      selection = []
    }
  }

  /// One step left or right, for the menu commands that stand in for the drag.
  private func moveTile(_ saved: SavedColor, from index: Int, by step: Int) {
    guard let project = saved.project else { return }
    move(from: index, to: index + step, in: project)
  }

  /// Translates a drop *onto* a tile into the `onMove` offset the library expects.
  ///
  /// The two conventions differ by one in exactly one direction: dropping onto a tile
  /// further down the grid means landing after it, and `onMove`'s destination indexes the
  /// order before the dragged item is lifted out, so the target has to be stepped past.
  private func move(from source: Int, to target: Int, in project: Project) {
    guard source != target else { return }
    perform {
      try library.moveColors(
        fromOffsets: IndexSet(integer: source),
        toOffset: source < target ? target + 1 : target,
        in: project,
      )
    }
  }

  /// Runs a mutation and reports what went wrong instead of swallowing it.
  ///
  /// `try?` is the tempting one-liner and it means a save that failed looks exactly like
  /// a save that worked — the panel simply shows nothing new and the user tries again.
  private func perform(_ work: () throws -> Void) {
    do {
      try work()
      errorMessage = nil
    } catch {
      errorMessage = "Could not save: \(error.localizedDescription)"
    }
  }
}

nonisolated extension ExportSource {
  /// What a palette saved from this source is recorded as.
  ///
  /// ``ExportSource/color``, ``ExportSource/saved`` and ``ExportSource/project`` have no
  /// honest answer — one is not a set, and the other two already came from palettes
  /// whose kinds are known — so they fall to ``PaletteKind/custom`` rather than
  /// inventing provenance.
  var paletteKind: PaletteKind {
    switch self {
    case .harmony: .harmony
    case .ramp: .ramp
    case .recents: .recents
    case .color, .saved, .project: .custom
    }
  }
}

#Preview {
  ContentView()
    .environment({
      let store = ColorStore(initialInput: "#3b82f6")
      store.tool = .projects
      return store
    }())
    .modelContainer(PersistenceStack.make(inMemory: true).container)
}
