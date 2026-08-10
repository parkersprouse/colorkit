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

/// A pending import: the text to pre-fill ``ImportTextSheet`` with and a name to suggest.
///
/// Carried as one `Identifiable` value driving `.sheet(item:)` rather than a `Bool` plus
/// loose "pending text" state, so there is no window in which the sheet is up but its
/// contents are stale — the same shape `colorsSection`'s `.popover(item: $noteTarget)`
/// already uses. A fresh `id` each time re-presents the sheet even for a repeat import.
private struct ImportRequest: Identifiable {
  let id = UUID()

  /// Empty for "From Text…"; the file's bytes for "From File…".
  var text: String = ""

  /// A name suggested from the file's name, or `nil` for the paste path.
  var name: String?
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

  /// The shapes the open panel admits (M31), one per vocabulary "From Text…" can read.
  ///
  /// `css` and `tokens` are built from their extensions rather than named as statics: a
  /// bare `.tokens` file has no registered type, and admitting `css` the same way sidesteps
  /// whether the running system happens to declare one. `compactMap` drops either if the
  /// system cannot form it, leaving the file selectable by the other four types regardless.
  private static let importableFileTypes: [UTType] =
    [.json, .plainText, .javaScript]
      + ["css", "tokens"].compactMap { UTType(filenameExtension: $0) }

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

  /// Whether the file open panel is up, and what the last import came back with.
  ///
  /// The summary is separate from ``errorMessage`` rather than folded into it because an
  /// import routinely half-succeeds — eleven colors in, three skipped — and that is
  /// neither an error nor silence.
  @State private var isImporting = false
  @State private var importSummary: String?

  /// The pending import sheet — `nil` when closed, otherwise the text to pre-fill and a
  /// name to suggest. Both menu items (M31's "From Text…" and "From File…") set this;
  /// "From File…" fills it after reading the chosen file's bytes.
  @State private var importRequest: ImportRequest?

  /// Which saved color's name and notes are open for editing. A `@Model` is
  /// `Identifiable`, so this drives `.popover(item:)` directly.
  @State private var noteTarget: SavedColor?

  /// Which palette's name is open for editing (M32). A **label**, so it shares
  /// ``rename(_ palette:to:)``'s existing fallback rather than a door of its own.
  @State private var paletteEditTarget: Palette?

  /// Which palette entry's export key is open for editing (M32) — **syntax**, not a
  /// label, hence its own popover rather than reusing ``noteTarget``'s. See
  /// ``ProjectLibrary/rekey(_:to:)``.
  @State private var entryEditTarget: SavedColor?

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
          Button("From Text…") { importRequest = ImportRequest() }
            .accessibilityIdentifier("importFromText")
          // "From File…" (M31), a superset of the old "From Token File…" rather than a
          // swap: it raises the open panel, reads the chosen file's bytes, and hands them
          // to the same sheet the paste path uses — so token files keep working, and CSS,
          // JSON, JavaScript and plain-text exports start working, all through one path
          // that inherits the shape override, storage-format control, destination picker
          // and preview instead of a second silent decode.
          Button("From File…") { isImporting = true }
            .accessibilityIdentifier("importFile")
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
    // Every shape "From Text…" reads, as a file: `.css`, `.json`, `.javaScript` (a
    // Tailwind config), plain text (a bare color list), and the conventional
    // `name.tokens.json` design-token file. `css` and `tokens` are built from their
    // extensions — `tokens` has no registered type at all, and `css` is admitted the same
    // way so a file the panel would otherwise refuse to show, for no reason a user could
    // work out, stays selectable whether or not the system happens to declare it.
    .fileImporter(
      isPresented: $isImporting,
      allowedContentTypes: Self.importableFileTypes,
    ) { result in
      importFile(result)
    }
    .sheet(item: $importRequest) { request in
      ImportTextSheet(
        initialProjectID: project.uuid,
        initialText: request.text,
        initialName: request.name,
      ) { importedProjectID, summary in
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

  /// What a color is called and why it was kept — the swatch can say neither.
  ///
  /// A popover rather than fields in the grid: a label and a note are the
  /// least-used things here, and giving every tile a permanent text box would bury the
  /// colors under them. **M32 folded the name in** — previously notes-only, retitled
  /// Edit… on the menu that opens it — rather than a separate door, because both
  /// fields are edited the identical way: bound straight to the model, live, and
  /// committed once on the way out.
  ///
  /// The name field has no fallback, unlike everything else this panel lets you rename.
  /// `saved.name.isEmpty ? saved.text : saved.name` is the display rule everywhere a
  /// saved color is shown, so clearing this is how you tell the tile to show the CSS
  /// again rather than a label nobody typed. That rule lives in
  /// ``ProjectLibrary/rename(_:to:)`` — called on the way out below, trimming rather
  /// than merely flushing, so the door M32 wrote is not a second, unreachable claim
  /// about the same behavior this field's live binding already produces on its own.
  private func notesEditor(_ saved: SavedColor) -> some View {
    @Bindable var saved = saved

    return VStack(alignment: .leading, spacing: 8) {
      Text(saved.name.isEmpty ? saved.text : saved.name)
        .font(.headline)
      TextField("Name", text: $saved.name, prompt: Text("Optional label"))
        .textFieldStyle(.roundedBorder)
        .frame(width: 260)
        .accessibilityIdentifier("savedColorName")
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
    // Bound straight to the model, so edits are live; the commit happens once on the
    // way out rather than on every keystroke. `rename` (M32) rather than the plainer
    // `touch` — it does everything `touch` did (both relationships' `touch()`, one
    // `save()`, which flushes the notes field's already-live edit for free) plus
    // trims the name, so this is a strict superset and not a second code path.
    .onDisappear { perform { try library.rename(saved, to: saved.name) } }
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

    Button("Edit…") { noteTarget = saved }
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
        VStack(alignment: .leading, spacing: 10) {
          ForEach(Array(project.orderedPalettes.enumerated()), id: \.element.persistentModelID) {
            index, palette in
            paletteRow(palette, index: index)
          }
        }
        // Two popovers for the whole section rather than one per row or per swatch,
        // matching `colorsSection`'s own reasoning: `item:` already carries which
        // palette or which entry is being edited, so a dozen rows each holding their
        // own would be a dozen pieces of state for something only ever open once.
        .popover(item: $paletteEditTarget) { palette in
          paletteNameEditor(palette)
        }
        .popover(item: $entryEditTarget) { entry in
          entryKeyEditor(entry)
        }
      }
    }
  }

  private func paletteRow(_ palette: Palette, index: Int) -> some View {
    let orderedEntries = palette.orderedEntries

    return VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Text(palette.name).font(.callout.weight(.medium))
        ColorBadge(text: palette.kind.title, tint: .secondary)
        Spacer()
        Button("Export") { store.stage(palette.paletteEntries, named: palette.name) }
          .disabled(palette.paletteEntries.isEmpty)
          .accessibilityIdentifier("paletteExport-\(index)")
        // M32: opens `paletteNameEditor`, wiring `ProjectLibrary.rename(_ palette:to:)`
        // — the library's only unwired mutation since M9.
        Button("Edit") { paletteEditTarget = palette }
          .accessibilityIdentifier("paletteEdit-\(index)")
        Button("Delete", role: .destructive) {
          // Cleared first, the same reason `savedColorMenu`'s own Delete does: a
          // popover left pointed at a deleted model is a reference to a row that no
          // longer exists.
          if paletteEditTarget?.persistentModelID == palette.persistentModelID {
            paletteEditTarget = nil
          }
          if entryEditTarget?.palette?.persistentModelID == palette.persistentModelID {
            entryEditTarget = nil
          }
          perform { try library.delete(palette) }
        }
        .accessibilityIdentifier("paletteDelete-\(index)")
      }

      HStack(alignment: .top, spacing: 4) {
        // Walked as `SavedColor` models, not `palette.paletteEntries`, so each swatch's
        // menu has something to hand `entryEditTarget` — a `PaletteEntry` is a plain
        // value with no model behind it to rekey. A row with no readable `colorValue`
        // renders nothing, the same silent skip `paletteEntries` already performs via
        // `compactMap` — but note `entryIndex` here counts *all* stored entries,
        // including that skipped one, where it used to number only the renderable
        // ones. Nothing keys off that number except this identifier string, which is
        // untested and does not claim to be stable across a build that can't read a
        // color it used to.
        ForEach(Array(orderedEntries.enumerated()), id: \.element.persistentModelID) {
          entryIndex, entry in
          if let color = entry.colorValue {
            // The key moves to a caption underneath, matching `ExportPanel.swatches` —
            // `SwatchButton`'s accessibility label is always the color's own CSS, never
            // a caller-chosen name, which is what makes a row of these testable at all:
            // a ramp that silently repeated a stop would fail a distinctness check on
            // the label, and a label that instead read the key could not catch that.
            VStack(spacing: 2) {
              SwatchButton(
                color: color,
                cornerRadius: 4,
                accessibilityIdentifier: "palette-\(index)-swatch-\(entryIndex)",
              ) {
                Button("Rename Key…") { entryEditTarget = entry }
              }
              .frame(width: 24, height: 24)
              if !entry.name.isEmpty {
                Text(entry.name)
                  .font(.system(size: 8))
                  .foregroundStyle(.secondary)
              }
            }
          }
        }
      }
    }
    .padding(10)
    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
  }

  /// A palette's name — a **label**, sharing ``rename(_ palette:to:)``'s existing
  /// fallback (its `kind.title`) rather than a new rule. Bound straight to the model
  /// and committed on submit and on close, the same pattern the project name field
  /// (`header`) already uses for a plain, non-popover text field.
  private func paletteNameEditor(_ palette: Palette) -> some View {
    @Bindable var palette = palette

    return VStack(alignment: .leading, spacing: 8) {
      Text("Rename Palette").font(.headline)
      TextField("Name", text: $palette.name, prompt: Text(palette.kind.title))
        .textFieldStyle(.roundedBorder)
        .frame(width: 220)
        .accessibilityIdentifier("paletteName")
        .onSubmit { perform { try library.rename(palette, to: palette.name) } }
    }
    .padding(12)
    .onDisappear { perform { try library.rename(palette, to: palette.name) } }
  }

  /// A palette entry's export key — **syntax**, not a label. Shows the sanitized
  /// identifier live underneath the field, because ``ExportOptions/cssIdentifier(_:fallback:)``
  /// is lossy and has no inverse: typing "Triad 2" writes `--brand-triad-2`, and that
  /// belongs in front of the user before they commit rather than in an export they
  /// read later — the same honesty M17 recorded when a name leaving through export
  /// turned out not to return through import unchanged. The preview shows the
  /// **sanitized** candidate, not the fully deduplicated one — a collision can only be
  /// found by comparing against every sibling's current name, which `library.rekey`
  /// does at the point of commit rather than on every keystroke.
  ///
  /// `onSubmit` and `onDisappear` can both fire ``ProjectLibrary/rekey(_:to:)`` for one
  /// edit — pressing Return, then closing the popover. That runs the dedupe loop twice
  /// rather than double-suffixing anything: the second call reads `entry.name` *after*
  /// the first already wrote the deduplicated key, and siblings are compared by
  /// `persistentModelID`, so an entry never collides with its own already-committed name.
  private func entryKeyEditor(_ entry: SavedColor) -> some View {
    @Bindable var entry = entry
    let position = (entry.palette?.orderedEntries.firstIndex {
      $0.persistentModelID == entry.persistentModelID
    } ?? 0) + 1
    let sanitized = ExportOptions.cssIdentifier(entry.name, fallback: "")

    return VStack(alignment: .leading, spacing: 8) {
      Text("Rename Key").font(.headline)
      TextField("Key", text: $entry.name, prompt: Text("Position \(position)"))
        .textFieldStyle(.roundedBorder)
        .frame(width: 180)
        .accessibilityIdentifier("paletteEntryKey")
        .onSubmit { perform { try library.rekey(entry, to: entry.name) } }
      Text(
        sanitized.isEmpty
          ? "Blank falls back to its position, “\(position)”."
          : "Exports as “\(sanitized)”.",
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .accessibilityIdentifier("paletteEntryKeyPreview")
    }
    .padding(12)
    .onDisappear { perform { try library.rekey(entry, to: entry.name) } }
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

  /// Reads a chosen file (M31) and opens ``ImportTextSheet`` pre-filled with its bytes and
  /// a name from its filename — every shape then decodes through the one path a paste takes,
  /// so a single color imports as a color (M30's fix), and the app's own JSON export, which
  /// has no `$value`, routes to `.json` and imports rather than being refused as a token file.
  ///
  /// **Only the file read happens here; nothing is decoded or saved.** So the outcomes are
  /// the three a read can have — the panel was cancelled (say nothing), the file could not be
  /// opened or read (report it), or the bytes are not UTF-8 text (report that) — and the
  /// fourth, success, hands the text to the sheet. Decode and save diagnostics belong to the
  /// sheet, which is where the shape, format and destination are actually chosen.
  ///
  /// This is the app's only place a *sandbox* denial can surface, which is why a read
  /// failure gets its own sentence rather than a generic "nothing imported". The
  /// security-scoped access is what makes the read legal at all: the app is sandboxed with
  /// `ENABLE_USER_SELECTED_FILES = readwrite`, which grants a URL the user chose in an open
  /// panel — but the grant has to be *claimed*, and the failure without it is a permission
  /// error on a file the user just picked.
  private func importFile(_ result: Result<URL, Error>) {
    guard case let .success(url) = result else {
      if case let .failure(error) = result {
        errorMessage = "Could not open that file: \(error.localizedDescription)"
      }
      return
    }

    // A file was actually chosen, so this attempt supersedes whatever the last import
    // left on screen — clear *both* the previous error and summary here, once, rather
    // than at the top. Clearing at the top would wipe a prior success summary even when
    // the panel was dismissed without a file, and would leave a stale summary sitting
    // beside a fresh read error below; this point is past the `.success` guard, so it is
    // reached only when there is a new outcome to report.
    errorMessage = nil
    importSummary = nil

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

    guard let text = String(data: data, encoding: .utf8) else {
      errorMessage = "Could not read \(url.lastPathComponent) as text."
      return
    }

    importRequest = ImportRequest(text: text, name: Self.paletteName(for: url))
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
