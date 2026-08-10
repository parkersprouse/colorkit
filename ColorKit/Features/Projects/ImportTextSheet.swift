//
//  ImportTextSheet.swift
//  ColorKit
//

import SwiftData
import SwiftUI

/// Pastes a document written in one of ``ExportShape``'s vocabularies — or a design
/// token file, or a bare list — back into a project.
///
/// A sheet rather than a fifth control folded into the save-controls row
/// (`ProjectsPanel.saveControls(_:)`): the preview, the shape picker, the storage-format
/// picker and the destination choice do not fit beside four buttons, and M26 is the
/// second half of the round trip `Export/` already makes — the same reason `Export
/// Project` is its own button rather than a cramped extra row.
///
/// **Nothing here builds a `ColorValue`.** Every color on screen came out of
/// ``PaletteImport``, and every save goes through
/// ``ProjectLibrary/savePalette(importing:named:to:)`` — the sheet's only job is turning
/// what got parsed into what that call needs: which project, what name, and whether the
/// stored text is the pasted value verbatim or re-spelled in a chosen format.
struct ImportTextSheet: View {
  // MARK: Internal

  /// Preselected — normally whatever project `ProjectsPanel` currently has open, so
  /// opening this sheet and importing does not silently change which project you were
  /// looking at.
  let initialProjectID: UUID?

  /// The document to pre-fill the paste box with. Empty for the "From Text…" path (the
  /// user pastes their own); the file's bytes for M31's "From File…" path, which reads a
  /// CSS/JSON/JavaScript/token/plain-text file and routes it through this same sheet
  /// rather than a second, silent decode path. `var` with a default so the memberwise
  /// initializer still admits the caller that passes neither this nor ``initialName``.
  var initialText: String = ""

  /// A name suggested from the imported file's name, or `nil` for the paste path. When
  /// present it wins over the parsed document's own ``ImportedPalette/detectedName`` in
  /// the single-group name field — the file is what the user named, so `accent.css` that
  /// happens to carry a `/* From "brand" */` header still suggests "accent".
  var initialName: String?

  /// M33: defaults the destination to "New Project" even when projects already exist —
  /// set by `ProjectsPanel`'s global Import entry points (`emptyState`'s actions, and
  /// its own row above `header`), which by design have not asked which project this
  /// import belongs to. `false` for the project-scoped `Menu("Import")` inside
  /// `saveControls(_:)`, which keeps defaulting to whatever project is already open —
  /// the memberwise default is what lets that call site go on omitting this entirely.
  var preferringNewProject = false

  /// Reports the project that ended up holding the import (so the panel can select it,
  /// even if this sheet created a new one) and a one-line summary — the same shape
  /// `ProjectsPanel.importSummary` already shows after an import.
  let onImported: (UUID, String) -> Void

  var body: some View {
    // Parsed **once** per body pass and handed to everything that needs it, rather
    // than read from ``outcome`` at each use site. That property re-parses the whole
    // paste box every time it is touched, and the footer's Import button needs the
    // same answer this switch does — so reading it in both places parsed twice per
    // keystroke, on the main actor, while somebody was typing. Measured on a 20×11
    // custom-properties export (11 KB, 220 colors): 5.1 ms per detect-and-parse, so
    // the pair came to ~10.2 ms — most of a 60 Hz frame — where one is about a third
    // of it. Halved, not eliminated: the remaining parse is still per keystroke, and
    // getting rid of it needs debouncing or an off-main parse rather than a seam.
    let outcome = outcome

    return VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          pasteBox
          switch outcome {
          case let .success(palette) where !palette.groups.isEmpty:
            shapeAndNameControls(palette)
            storageFormatControl
            destinationControl(palette)
            preview(palette)
          case .success:
            Text("Nothing recognizable in that text yet.")
              .font(.callout)
              .foregroundStyle(.secondary)
          case let .failure(error):
            Text(error.message)
              .font(.callout)
              .foregroundStyle(.secondary)
          case nil:
            EmptyView()
          }
          if let saveError {
            Label(saveError, systemImage: "exclamationmark.triangle")
              .font(.callout)
              .foregroundStyle(.secondary)
          }
        }
        .padding(16)
      }
      Divider()
      footer(canImport: canImport(outcome))
    }
    .frame(width: 480, height: 580)
    .onAppear {
      destinationProjectID = initialProjectID ?? projects.first?.uuid
      // M33: `preferringNewProject` is what makes the global entry points default here
      // even with projects already on hand. `projects.isEmpty` alone is what this sheet
      // relied on before M33 — sufficient then only because the sheet could not open at
      // all while `projects.isEmpty`, since it hung entirely off `saveControls(_:)`,
      // which needs a selected project to render; M33 moved the sheet to `body` level
      // precisely so that stops being true.
      creatingNewProject = preferringNewProject || projects.isEmpty
      // Seeding here rather than in an `init` keeps the memberwise defaults above; it
      // mirrors the `destinationProjectID` line and runs before the first body pass
      // renders `shapeAndNameControls`, so the `initial: true` reseed below fires on the
      // parse this line triggers. Empty for the paste path, so it is a no-op there.
      pastedText = initialText
    }
    // The `storageFormat` counterpart to `ColorStore`'s export reconciliation (M34
    // follow-up): if the mode is toggled on (in Settings, a *different* `Scene` sharing
    // this `ColorStore`) while a non-web-friendly format is selected, reassign it to a
    // safe one and stash the original; toggling back off restores the stash unless the
    // control was used meanwhile. On the sheet's *root* view, not on `storageFormatControl`
    // — that only renders once a parse succeeds, so scoping the observer there would miss
    // a toggle made before anything is pasted and then surface a stale value the instant a
    // parse does succeed. No `initial:`: `storageFormat` starts `nil` (never restricted)
    // every time the sheet opens, so there is nothing to reconcile on appear.
    .onChange(of: store.webFriendly) { _, isOn in
      reconcileStorageFormat(webFriendly: isOn)
    }
  }

  // MARK: Private

  @Environment(\.dismiss) private var dismiss
  @Environment(ColorStore.self) private var store
  @Environment(\.modelContext) private var context

  @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]

  @State private var pastedText = ""
  @State private var shapeOverride: ImportShape?
  @State private var name = ""
  @State private var nameEdited = false
  @State private var storageFormat: CSSOutputFormat?
  /// The `storageFormat` the user was on before web-friendly mode restricted it, stashed
  /// so toggling the mode back off restores it. A single optional, not a pair: the stash
  /// is always a specific restricted format, never `nil`/"Keep as pasted", which is never
  /// itself restricted. Sheet-local `@State`, so — like the rest of this mechanism — none
  /// of it is unit-testable and XCUITest cannot drive the cross-scene Settings toggle; see
  /// the M34 follow-up entry in PLAN.md for this recorded gap.
  @State private var restrictedStorageFormat: CSSOutputFormat?
  @State private var destinationProjectID: UUID?
  @State private var creatingNewProject = false
  @State private var newProjectName = ""
  @State private var newProjectNameEdited = false
  @State private var saveError: String?

  private var library: ProjectLibrary {
    ProjectLibrary(context)
  }

  private var effectiveShape: ImportShape {
    shapeOverride ?? PaletteImport.detect(pastedText)
  }

  /// `nil` before anything is pasted, so the empty state can read as an empty state
  /// rather than "nothing recognizable" — those are different things to tell somebody
  /// who has not typed anything yet.
  private var outcome: Result<ImportedPalette, PaletteImportError>? {
    guard !pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    do {
      return try .success(PaletteImport.parse(pastedText, as: effectiveShape))
    } catch {
      return .failure(error)
    }
  }

  private var availableFormats: [CSSOutputFormat] {
    store.webFriendly ? CSSOutputFormat.webFriendlyExportable : CSSOutputFormat.exportable
  }

  // MARK: - Chrome

  private var header: some View {
    HStack {
      Text("Import Colors")
        .font(.headline)
      Spacer()
    }
    .padding(16)
  }

  // MARK: - Controls

  /// A plain, editable text view bound straight to state — never a "Paste" button
  /// reading `NSPasteboard` directly, which nothing outside a running app (and no
  /// XCUITest) could ever type into.
  private var pasteBox: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Paste a stylesheet, a Tailwind config, JSON, a Design tokens (DTCG) file, or a bare list of colors.")
        .font(.caption)
        .foregroundStyle(.secondary)
      TextEditor(text: $pastedText)
        .font(.system(.body, design: .monospaced))
        .frame(height: 140)
        .overlay {
          RoundedRectangle(cornerRadius: 6).strokeBorder(.separator, lineWidth: 1)
        }
        .accessibilityIdentifier("importSheetText")
    }
  }

  private var storageFormatControl: some View {
    LabeledContent("Storage format") {
      // Routed through a `Binding` that clears the stash on an explicit pick (M34
      // follow-up), the sheet-local counterpart to `ColorStore.selectExportFormat(_:)`:
      // picking any value — including re-picking the reassigned one — confirms it and
      // discards the pending revert to the restricted format.
      let selection = Binding(
        get: { storageFormat },
        set: {
          storageFormat = $0
          restrictedStorageFormat = nil
        },
      )
      Picker("Storage format", selection: selection) {
        Text("Keep as pasted").tag(CSSOutputFormat?.none)
        ForEach(availableFormats, id: \.self) { format in
          Text(format.title).tag(CSSOutputFormat?.some(format))
        }
      }
      .labelsHidden()
      .accessibilityIdentifier("importSheetFormat")
    }
  }

  /// Takes the parsed palette (unlike its M31-and-earlier self) so it can seed
  /// ``newProjectName`` — needed since M33, when the global entry points can open here
  /// with ``creatingNewProject`` already `true` even though projects exist, leaving Import
  /// disabled behind an empty required field with nothing on screen saying why.
  private func destinationControl(_ palette: ImportedPalette) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Picker("Destination", selection: $creatingNewProject) {
        Text("Existing Project").tag(false)
        Text("New Project").tag(true)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .disabled(projects.isEmpty)
      .accessibilityIdentifier("importSheetDestinationKind")

      if creatingNewProject {
        TextField(
          "New project name",
          text: Binding(get: { newProjectName }, set: { newProjectName = $0; newProjectNameEdited = true }),
          prompt: Text("Untitled Project"),
        )
        .textFieldStyle(.roundedBorder)
        .accessibilityIdentifier("importSheetNewProjectName")
      } else {
        Picker("Project", selection: $destinationProjectID) {
          ForEach(projects) { project in
            Text(project.name).tag(Optional(project.uuid))
          }
        }
        .labelsHidden()
        .accessibilityIdentifier("importSheetProjectPicker")
      }
    }
    // The same "reseed until touched" discipline `shapeAndNameControls`' name field
    // uses, and for the identical reason `initial: true` is load-bearing there: this
    // `VStack` does not exist until the first successful parse (see the switch in
    // `body`), so without `initial: true` the very first paste would create this
    // modifier with `detectedName` already at its post-parse value and nothing would
    // fire — the field would sit empty behind its placeholder and Import would stay
    // disabled with nothing on screen explaining why. `initialName` (a filename from
    // "From File…") wins over the parsed name, matching `shapeAndNameControls`. Seeded
    // regardless of `creatingNewProject`, since the reachable-once-and-stay-cached shape
    // (`onChange` fires whether or not the branch above is currently showing) is simpler
    // than gating it — and cheaper than it looks, since `newProjectNameEdited` still
    // stops it from clobbering anything typed.
    .onChange(of: palette.detectedName, initial: true) { _, detected in
      guard !newProjectNameEdited else { return }
      newProjectName = initialName ?? detected ?? ""
    }
  }

  private func footer(canImport: Bool) -> some View {
    HStack {
      Spacer()
      Button("Cancel") { dismiss() }
        .accessibilityIdentifier("importSheetCancel")
      Button("Import") { performImport() }
        .keyboardShortcut(.defaultAction)
        .disabled(!canImport)
        .accessibilityIdentifier("importSheetConfirm")
    }
    .padding(16)
  }

  private func shapeAndNameControls(_ palette: ImportedPalette) -> some View {
    let colors = palette.groups.count(where: { $0.soleColor != nil })
    let palettes = palette.groups.count - colors

    return VStack(alignment: .leading, spacing: 10) {
      LabeledContent("Shape") {
        Picker(
          "Shape",
          selection: Binding(get: { effectiveShape }, set: { shapeOverride = $0 }),
        ) {
          ForEach(ImportShape.allCases) { shape in
            Text(shape.title).tag(shape)
          }
        }
        .labelsHidden()
        .accessibilityIdentifier("importSheetShape")
      }

      // The split is named before the save, not discovered after it — a single unkeyed
      // color imports as a loose color and a scale as a palette, and this line is where
      // "which is which" becomes visible. It reads the same ``ImportedGroup/soleColor``
      // predicate `performImport` routes on, so the preview and the confirmation cannot
      // disagree about what just happened.
      Text("Imports as \(Self.splitPhrase(colors: colors, palettes: palettes)).")
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("importSheetSplit")

      if palette.groups.count == 1 {
        LabeledContent("Name") {
          TextField(
            "Name",
            text: Binding(get: { name }, set: { name = $0; nameEdited = true }),
            prompt: Text(ExportOptions.defaultName),
          )
          .textFieldStyle(.roundedBorder)
          .frame(maxWidth: 200)
          .accessibilityIdentifier("importSheetName")
        }
        // The suggestion tracks the parsed document until the user actually edits the
        // field — the same "reseed until touched" shape `PickerState` uses, so a
        // keystroke here is never clobbered by the next character typed into the paste
        // box above it.
        //
        // `initial: true` is load-bearing, not decoration. This `VStack` — and the
        // `onChange` on it — does not exist until the first successful parse, so
        // without it the very first paste creates this modifier with `detectedName`
        // already at its post-parse value and nothing fires: the field would show the
        // placeholder while `name` silently stays empty, and `performImport` would
        // fall back to the group's own name without the field ever having offered it.
        //
        // `defaultName` ("brand") is filtered out at the seed **only when the sole group
        // is a loose color**, not for any group that happens to be named "brand". It is a
        // placeholder `parseLooseColors` and headerless `parseDeclarations` reach for a
        // *single color*, so seeding a lone color's field to it would render "brand" as
        // real text while the saved color ends up nameless — a preview contradicting its
        // own outcome, the same defect M8 had. A genuine palette whose `commonFamily` is
        // literally "brand" (`--brand-500`, `--brand-600`) is a real name and keeps it:
        // the field shows "brand" and the palette saves as "brand". `performImport`'s own
        // `== defaultName` filter, gated on `soleColor` the same way, covers the
        // multi-group documents where this field never renders.
        .onChange(of: palette.detectedName, initial: true) { _, detected in
          guard !nameEdited else { return }
          // A filename from the "From File…" path (M31) wins over the document's own
          // detected name — the file is what the user named it. `initialName` is a
          // constant, so watching `detectedName` still fires this on the first parse and
          // on every re-parse; the paste path passes `nil` and is unchanged.
          let suggestion = initialName ?? detected
          let soleColor = palette.groups.first?.soleColor != nil
          // The `defaultName` blanking is unchanged and now also catches a file literally
          // named `brand` holding a lone color — consistent with the rule's intent, which
          // is that "brand" is a placeholder, not a name a color should wear as real text.
          name = soleColor && suggestion == ExportOptions.defaultName ? "" : (suggestion ?? "")
        }
      } else {
        // The names only — the counts are on the "Imports as …" line above, and calling
        // these all "palettes" would be wrong the moment one of them is a loose color.
        Text("From: " + palette.groups.map(\.name).joined(separator: ", "))
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  // MARK: - Preview

  private func preview(_ palette: ImportedPalette) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(palette.groups) { group in
        VStack(alignment: .leading, spacing: 4) {
          Text(group.name).font(.caption.weight(.medium))
          HStack(alignment: .top, spacing: 4) {
            ForEach(group.entries) { entry in
              VStack(spacing: 2) {
                ColorSwatch(color: entry.color, cornerRadius: 4)
                  .frame(width: 22, height: 22)
                if !entry.key.isEmpty {
                  Text(entry.key).font(.system(size: 8)).foregroundStyle(.secondary)
                }
              }
            }
          }
        }
      }
      if !palette.skipped.isEmpty {
        Text("\(palette.skipped.count) value\(palette.skipped.count == 1 ? "" : "s") could not "
          + "be read — \(palette.skipped[0].message)")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("importSheetSkipped")
      }
    }
  }

  /// Phrases a colors/palettes split for both the preview caption and the confirmation
  /// summary, so the two are one string built one way and cannot drift — the anti-drift
  /// property ``ImportedGroup/soleColor`` exists to give the *counts*, extended to the
  /// copy. Editorial wording lives here in the UI layer; the predicate stays in ColorCore.
  private static func splitPhrase(colors: Int, palettes: Int) -> String {
    func plural(_ count: Int, _ noun: String) -> String {
      "\(count) \(noun)\(count == 1 ? "" : "s")"
    }
    switch (colors, palettes) {
    case (0, 0): return "nothing"
    case (_, 0): return plural(colors, "color")
    case (0, _): return plural(palettes, "palette")
    default: return "\(plural(colors, "color")) and \(plural(palettes, "palette"))"
    }
  }

  /// Reassigns a now-restricted `storageFormat` to a safe one and stashes the original on
  /// a true transition; restores the stash on a false transition. The `storageFormat`
  /// analogue of ``ColorStore/reconcileExportOptions()`` — see the `.onChange` in `body`.
  private func reconcileStorageFormat(webFriendly: Bool) {
    if webFriendly {
      // `newValue`-derived rather than reading `store.webFriendly`/`availableFormats`,
      // which would depend on observation having settled before this runs. `nil` ("Keep
      // as pasted") is never restricted, so only a concrete out-of-list format reassigns.
      guard let current = storageFormat,
            !CSSOutputFormat.webFriendlyExportable.contains(current)
      else { return }
      restrictedStorageFormat = current
      // The fallback reuses `ExportOptions.effective(webFriendly:)` (→ `.oklch`) rather
      // than hardcoding it a second time. Falling back to `nil`/"Keep as pasted" was
      // rejected: that preserves the *pasted text* verbatim, which can itself be spelled
      // in a non-web-friendly notation — the worse outcome under a mode whose whole point
      // is staying web-friendly.
      var probe = ExportOptions.default
      probe.format = current
      storageFormat = probe.effective(webFriendly: true).format
    } else if let stashed = restrictedStorageFormat {
      storageFormat = stashed
      restrictedStorageFormat = nil
    }
  }

  /// Takes the already-parsed outcome rather than reading ``outcome`` itself — see the
  /// note at the top of `body` for why re-reading it is not free.
  /// M33: no longer requires a non-empty ``newProjectName`` when creating. It used to,
  /// on the reasoning that ``newProjectName``'s seed (below) would always have filled it
  /// in by the time there was anything to import — true for a single-group document,
  /// where the seed reads ``ImportedPalette/detectedName``, but false for a multi-group
  /// one, where `detectedName` is `nil` by construction (set only when `groups.count ==
  /// 1`). A whole-project export — plausibly the single most likely thing to reach the
  /// global entry point for — is multi-group, so the old rule would have opened Import
  /// disabled behind an empty required field with nothing on screen saying why: the
  /// exact defect this milestone exists to fix, just moved one field over.
  /// `ProjectLibrary.createProject(named:)` already falls back to "Untitled Project" for
  /// an empty name — the same fallback the plain New Project button already relies on
  /// unconditionally — so there was never a real requirement here to enforce.
  private func canImport(_ outcome: Result<ImportedPalette, PaletteImportError>?) -> Bool {
    guard case let .success(palette) = outcome, !palette.groups.isEmpty else { return false }
    guard !palette.groups.flatMap(\.entries).isEmpty else { return false }
    return creatingNewProject || destinationProjectID != nil
  }

  // MARK: - Importing

  /// Re-spells every entry's stored text when a specific format is chosen; leaves it
  /// exactly as pasted when the control is at its default. `formatted` returns `nil`
  /// only for `.keyword`, which never appears in ``availableFormats`` — see
  /// `CSSOutputFormat.exportable` — so the fallback to the pasted text is unreachable in
  /// practice and exists only so a future format that *can* fail does not crash a save
  /// over a string.
  private func resolvedEntries(_ entries: [ImportedEntry]) -> [ImportedEntry] {
    guard let format = storageFormat else { return entries }
    return entries.map { entry in
      let text = entry.color.formatted(as: format, options: .lossless)?.css ?? entry.text
      return ImportedEntry(key: entry.key, color: entry.color, text: text, notes: entry.notes)
    }
  }

  private func performImport() {
    guard case let .success(palette) = outcome else { return }
    saveError = nil

    do {
      let project: Project = if creatingNewProject {
        try library.createProject(named: newProjectName)
      } else if let uuid = destinationProjectID, let existing = projects.first(where: { $0.uuid == uuid }) {
        existing
      } else {
        try library.createProject(named: newProjectName)
      }

      var savedColors = 0
      var savedPalettes = 0
      for group in palette.groups {
        let entries = resolvedEntries(group.entries)
        guard !entries.isEmpty else { continue }
        // The name a single group takes from the editable field; a group in a
        // multi-group document takes its own header/JSON/family name.
        let resolvedName = palette.groups.count == 1 && !name.isEmpty ? name : group.name

        // The route is `soleColor`, the same predicate the preview counted with —
        // computed on the original group because `resolvedEntries` touches only the text,
        // never the key or the count. A single unkeyed color goes through the fifth door
        // as a loose color; anything with a real key stays a palette.
        if group.soleColor != nil, let entry = entries.first {
          // The group name unless it is the `defaultName` placeholder, in which case the
          // tile falls back to the CSS text rather than being labelled "brand".
          let colorName = resolvedName == ExportOptions.defaultName ? "" : resolvedName
          try library.saveColor(importing: entry, named: colorName, to: project)
          savedColors += 1
        } else {
          try library.savePalette(importing: entries, named: resolvedName, to: project)
          savedPalettes += 1
        }
      }

      // A completed import confirms the storage-format choice, discarding the pending
      // revert — the success-path counterpart to `ColorStore.confirmExportChoices()`. Not
      // unconditional: a failed or aborted import (the `catch` below) used nothing.
      restrictedStorageFormat = nil

      var summary = "Imported \(Self.splitPhrase(colors: savedColors, palettes: savedPalettes))"
      summary += palette.skipped.isEmpty ? "." : ", skipped \(palette.skipped.count)."
      onImported(project.uuid, summary)
      dismiss()
    } catch {
      saveError = "Could not save: \(error.localizedDescription)"
    }
  }
}

/// - Note: `nonisolated` for the reason `ExportShape.title` gives — plain data that
///   should not cost an actor hop under this target's default isolation.
nonisolated extension ImportShape {
  var title: String {
    switch self {
    case .customProperties: "Custom properties"
    case .declaration: "Declarations"
    case .json: "JSON"
    case .tailwindTheme: "Tailwind v4"
    case .tailwindConfig: "Tailwind v3"
    case .p3WithFallback: "P3 with fallback"
    case .designTokens: "Design tokens (DTCG)"
    case .looseColors: "Loose colors"
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
