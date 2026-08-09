//
//  ExportPanel.swift
//  ColorKit
//

// For the preview's `.modelContainer` only — export itself touches no SwiftData, which
// is what keeps `ExportStoreTests` free of a `ModelContainer`.
import SwiftData
import SwiftUI

/// The colors you have, written out as something you can paste.
///
/// Two choices drive everything: **what** to export — this color, or one of the sets the
/// other tools produce — and **what shape** to write it in. Everything below the controls
/// is a live preview of exactly what the copy button puts on the clipboard, which is the
/// property worth protecting: an export panel whose preview and clipboard can disagree is
/// worse than no preview at all.
///
/// **The panel builds no strings.** Every character comes from ``ExportOptions/render``
/// in ColorCore, reached through ``ColorStore/exportDocument``. That is not tidiness for
/// its own sake — tests here must never write to the real pasteboard, so string
/// generation living in a view would be a feature with no assertable surface.
struct ExportPanel: View {
  // MARK: Internal

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        // A staged palette or project is exportable with an empty field — it is a set
        // that was saved earlier, not something derived from what is being edited.
        // Guarding on the color alone would hide the Source picker itself, leaving no
        // way to reach the palette (or project) that is sitting right there.
        if store.color == nil, store.stagedPalette.isEmpty, store.stagedProject.isEmpty {
          ContentUnavailableView(
            "No color yet",
            systemImage: "square.and.arrow.up",
            description: Text("Type a CSS color above and it can be exported from here."),
          )
          .frame(maxWidth: .infinity)
        } else {
          controls
          Divider()
          preview
        }
      }
      .padding(16)
    }
    // On the whole panel rather than on the button, so the exporter survives the layout
    // changing under it — a shape switch rebuilds the preview subtree, and a presentation
    // modifier torn down mid-panel takes the open save panel with it.
    .fileExporter(
      isPresented: $isSaving,
      document: ExportDocument(text: store.exportDocument),
      contentType: store.exportOptions.shape.contentType,
      defaultFilename: store.exportOptions.suggestedFilename,
    ) { result in
      save(result)
    }
  }

  // MARK: Private

  @Environment(ColorStore.self) private var store

  @State private var justCopied = false
  @State private var resetTask: Task<Void, Never>?

  @State private var isSaving = false
  @State private var saveError: String?

  // MARK: - Controls

  private var controls: some View {
    @Bindable var store = store

    return VStack(alignment: .leading, spacing: 14) {
      LabeledContent("Source") {
        Picker("Source", selection: $store.exportSource) {
          ForEach(ExportSource.allCases) { source in
            Text(source.title).tag(source)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityIdentifier("exportSource")
      }

      // A menu rather than a segmented control, unlike Source above. Six options
      // against five, and "Custom properties" is more than twice the length of the
      // longest source title — a segmented control divides its width evenly, so the
      // short options would pay for the long one. The tool switcher is the cautionary
      // tale: segments that stop fitting do not degrade gracefully. M16 is the reason
      // this reads as vindication rather than caution: a sixth shape cost nothing here,
      // where a sixth *tool* is what swept the switcher into an overflow menu.
      LabeledContent("Shape") {
        Picker("Shape", selection: $store.exportOptions.shape) {
          // `p3WithFallback` is wide-gamut by definition — its whole job is a
          // `@media` block in `color(display-p3 …)` — so it is hidden under
          // web-friendly mode (M22) rather than restricted. Hiding the control
          // does not touch the stored `shape`, which is why `store.exportDocument`
          // separately reads `ExportOptions.effective(webFriendly:)`.
          ForEach(ExportShape.allCases.filter { store.webFriendly ? $0.isWebFriendly : true }) { shape in
            Text(shape.title).tag(shape)
          }
        }
        .labelsHidden()
        .accessibilityIdentifier("exportShape")
      }

      Text(store.exportOptions.shape.summary)
        .font(.caption)
        .foregroundStyle(.tertiary)
        .fixedSize(horizontal: false, vertical: true)

      if store.exportOptions.shape.usesTemplate {
        LabeledContent("Declaration") {
          Picker("Declaration", selection: $store.exportOptions.template) {
            ForEach(ExportTemplate.allCases) { template in
              Text(template.title).tag(template)
            }
          }
          .labelsHidden()
          .accessibilityIdentifier("exportTemplate")
        }
      }

      if store.exportOptions.shape.usesName {
        LabeledContent("Name") {
          // The prompt is the *same constant* the empty field falls back to, so what
          // is shown greyed out is what you actually get. Hardcoding it here let the
          // two drift: the placeholder read `brand` while an empty name exported
          // `--color`, the default of `cssIdentifier`.
          TextField(
            "Name",
            text: $store.exportOptions.name,
            prompt: Text(ExportOptions.defaultName),
          )
          .textFieldStyle(.roundedBorder)
          .frame(maxWidth: 200)
          .accessibilityIdentifier("exportName")
        }
      }

      // Hidden for the one shape that fixes its own spellings, and hidden rather than
      // disabled for the reason the Declaration and Name controls are: a live picker
      // there could put `oklch()` — the default, and unbounded — into a block whose
      // entire job is being what a browser *without* wide-gamut support receives.
      if store.exportOptions.shape.usesFormat {
        LabeledContent("Format") {
          // `keyword` is absent, and structurally so — see `CSSOutputFormat.exportable`.
          // It names 148 colors, so a palette would come back part keywords and part
          // something else with nothing in the file to say so.
          Picker("Format", selection: $store.exportOptions.format) {
            ForEach(
              store.webFriendly ? CSSOutputFormat.webFriendlyExportable : CSSOutputFormat.exportable,
              id: \.self,
            ) { format in
              Text(format.title).tag(format)
            }
          }
          .labelsHidden()
          .accessibilityIdentifier("exportFormat")
        }
      }

      // The *same* setting the toolbar's output menu shows, not a copy of it. Surfaced
      // again here because precision is the one serialization choice you actually think
      // about while exporting, and sending someone to a toolbar menu mid-task to find it
      // is a worse answer than showing one knob in two places.
      LabeledContent("Precision") {
        Picker("Precision", selection: $store.formatOptions.precision) {
          Text("Compact").tag(2)
          Text("Normal").tag(4)
          Text("Fine").tag(6)
          Text("Maximum").tag(10)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityIdentifier("exportPrecision")
      }
    }
  }

  // MARK: - Preview

  private var preview: some View {
    let document = store.exportDocument
    let entries = store.exportEntries
    let mapped = store.exportGamutMappedCount

    return VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text("Output").font(.headline)
        Text(entries.count == 1 ? "1 color" : "\(entries.count) colors")
          .font(.caption)
          .foregroundStyle(.tertiary)
        Spacer()
        // Copy keeps the position it has always had. Saving is the occasional action —
        // this panel's output is usually pasted into a stylesheet already open.
        Button(justCopied ? "Copied" : "Copy") { copy() }
          .disabled(document.isEmpty)
          .accessibilityIdentifier("exportCopy")
        Button("Save…") { isSaving = true }
          .disabled(document.isEmpty)
          .accessibilityIdentifier("exportSave")
      }

      if let saveError {
        // Shown rather than thrown away, and shown here rather than in an alert: the
        // panel already reports the mapped-count warning inline a few points below, and
        // a modal for a failed write would be the only modal in the app.
        Label(saveError, systemImage: "exclamationmark.triangle.fill")
          .font(.callout)
          .foregroundStyle(.red)
          .accessibilityIdentifier("exportSaveError")
      }

      if entries.isEmpty {
        // Said plainly rather than shown as an empty code block, which reads as the
        // panel having broken. The wording belongs to the *source* — Recents and Saved
        // are empty for unrelated reasons, and one sentence cannot be true of both.
        Label(store.exportSource.emptyMessage, systemImage: "clock")
          .font(.callout)
          .foregroundStyle(.secondary)
      } else {
        if mapped > 0 {
          HStack(spacing: 8) {
            ColorBadge(text: mapped == 1 ? "1 mapped" : "\(mapped) mapped")
            // The format named is `mappedCountFormat`, which is what the count was
            // measured against — for the P3 shape that is the fallback, not the
            // selection, and naming the selection would name a format the document
            // does not contain.
            Text(
              store.exportOptions.shape.mappedNote(
                count: mapped,
                format: store.exportOptions.mappedCountFormat,
              ),
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          }
        }

        swatches(entries)

        // Horizontally scrollable rather than wrapping: this is code, and a soft-wrapped
        // Tailwind config is harder to read than one you scroll.
        ScrollView(.horizontal, showsIndicators: true) {
          Text(document)
            .font(.system(.callout, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("exportDocument")
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
      }
    }
  }

  /// What is about to be written, as colors rather than as text.
  ///
  /// Each carries its CSS as an accessibility label, for the reason the transform panel's
  /// swatches do: a colored rectangle announces nothing to VoiceOver, and it is the only
  /// handle a test has on a row of them.
  private func swatches(_ entries: [PaletteEntry]) -> some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 6) {
        ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
          VStack(spacing: 4) {
            // The label and identifier now live on the button itself — wrapping it in
            // an `.accessibilityElement(children: .ignore)` container the way the
            // pre-M21 version did would swallow the Button into a second element and
            // make `exportSwatch-N` match twice, the trap `ProjectsPanel` documents.
            SwatchButton(
              color: entry.color,
              cornerRadius: 6,
              accessibilityIdentifier: "exportSwatch-\(index)",
            )
            .frame(width: 38, height: 38)
            if !entry.key.isEmpty {
              Text(entry.key)
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
          }
        }
      }
      .padding(.vertical, 2)
    }
  }

  /// What `.fileExporter` came back with.
  ///
  /// The write itself is done by the time this runs — `FileDocument` hands the system a
  /// `FileWrapper` and the system writes it, which is what makes this the one export path
  /// with no string-building anywhere near it.
  ///
  /// Success files the color under recents for the reason ``ColorStore/copyExport()``
  /// does: reaching for a value is the clearest signal you intend to use it, and saving
  /// one to disk is a stronger signal than copying it. A cancellation is not a failure and
  /// must not raise anything — `.failure` here means the write was attempted and lost.
  private func save(_ result: Result<URL, Error>) {
    switch result {
    case .success:
      saveError = nil
      store.remember()
    case let .failure(error):
      saveError = "Could not save: \(error.localizedDescription)"
    }
  }

  private func copy() {
    store.copyExport()
    justCopied = true
    // Cancelled first for the reason `FormatRow` gives: two copies in quick succession
    // would otherwise let the earlier timer clear a label the later one just set.
    resetTask?.cancel()
    resetTask = Task {
      try? await Task.sleep(for: .seconds(1.2))
      guard !Task.isCancelled else { return }
      justCopied = false
    }
  }
}

#Preview {
  ContentView()
    .environment({
      let store = ColorStore(initialInput: "#3b82f6")
      store.tool = .export
      return store
    }())
    // Export itself touches no SwiftData, but this preview is the whole `ContentView`
    // and its switcher can reach Projects — see the note on `ContentView`'s own preview.
    .modelContainer(PersistenceStack.make(inMemory: true).container)
}
