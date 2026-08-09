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

  /// Reports the project that ended up holding the import (so the panel can select it,
  /// even if this sheet created a new one) and a one-line summary — the same shape
  /// `ProjectsPanel.importSummary` already shows after a token-file import.
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
            destinationControl
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
      creatingNewProject = projects.isEmpty
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
  @State private var destinationProjectID: UUID?
  @State private var creatingNewProject = false
  @State private var newProjectName = ""
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
      Text("Paste a stylesheet, a Tailwind config, JSON, a design token file, or a bare list of colors.")
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
      Picker("Storage format", selection: $storageFormat) {
        Text("Keep as pasted").tag(CSSOutputFormat?.none)
        ForEach(availableFormats, id: \.self) { format in
          Text(format.title).tag(CSSOutputFormat?.some(format))
        }
      }
      .labelsHidden()
      .accessibilityIdentifier("importSheetFormat")
    }
  }

  private var destinationControl: some View {
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
        TextField("New project name", text: $newProjectName, prompt: Text("Untitled Project"))
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
    VStack(alignment: .leading, spacing: 10) {
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
        .onChange(of: palette.detectedName, initial: true) { _, detected in
          guard !nameEdited else { return }
          name = detected ?? ""
        }
      } else {
        Text("\(palette.groups.count) palettes will be created: "
          + palette.groups.map(\.name).joined(separator: ", "))
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

  /// Takes the already-parsed outcome rather than reading ``outcome`` itself — see the
  /// note at the top of `body` for why re-reading it is not free.
  private func canImport(_ outcome: Result<ImportedPalette, PaletteImportError>?) -> Bool {
    guard case let .success(palette) = outcome, !palette.groups.isEmpty else { return false }
    guard !palette.groups.flatMap(\.entries).isEmpty else { return false }
    if creatingNewProject {
      return !newProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    return destinationProjectID != nil
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

      var savedCount = 0
      for group in palette.groups {
        let entries = resolvedEntries(group.entries)
        guard !entries.isEmpty else { continue }
        let groupName = palette.groups.count == 1 && !name.isEmpty ? name : group.name
        try library.savePalette(importing: entries, named: groupName, to: project)
        savedCount += entries.count
      }

      var summary = "Imported \(savedCount) color\(savedCount == 1 ? "" : "s")"
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
    case .designTokens: "Design tokens"
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
