//
//  ExportStoreTests.swift
//  ColorKitTests
//

@testable import ColorKit
import Foundation
import Testing

/// The seam between the app's state and the export layer: which colors a source names,
/// and under which keys.
///
/// This lives on ``ColorStore`` rather than in the panel precisely so it can be asserted
/// here. Built into the view, "the ramp exports eleven entries keyed 50 to 950" would be
/// reachable only through XCUITest — a claim about a data structure, checked by reading
/// a rendered string.
///
/// - Note: Nothing here calls ``ColorStore/copyExport()``, for the reason
///   ``ColorStoreTests`` gives about ``ColorStore/copy(_:)``: it writes to the real
///   system pasteboard, and a test has no business clobbering it.
@MainActor
@Suite("Export sources")
struct ExportSourceTests {
  @Test("A lone color exports one unkeyed entry")
  func singleColorHasNoKey() throws {
    let store = ColorStore(initialInput: "#3b82f6")
    store.exportSource = .color

    let entries = store.exportEntries
    #expect(entries.count == 1)
    #expect(try #require(entries.first).key.isEmpty)
    #expect(try #require(entries.first).color == ColorValue.srgb8(0x3B, 0x82, 0xF6))
  }

  /// The default ramp is eleven stops, which is exactly Tailwind's scale — so this is
  /// also the check that the two stayed lined up.
  @Test("The default ramp exports Tailwind's eleven keys")
  func rampUsesTailwindKeys() {
    let store = ColorStore(initialInput: "#3b82f6")
    store.exportSource = .ramp

    #expect(store.exportEntries.map(\.key) == PaletteNaming.tailwindScale)
  }

  /// Moving the stepper off eleven has to change the keys too, or ten stops would be
  /// written under eleven names and one color would vanish.
  @Test("A resized ramp falls back to indices")
  func resizedRampUsesIndices() {
    let store = ColorStore(initialInput: "#3b82f6")
    store.exportSource = .ramp
    store.shadeRamp.stops = 5

    #expect(store.exportEntries.map(\.key) == ["1", "2", "3", "4", "5"])
  }

  /// Keys and colors stay in step across every harmony. `zip` truncates silently, so a
  /// naming table one entry short would drop a color with nothing to show for it.
  @Test("Harmony entries pair every member with a key", arguments: Harmony.allCases)
  func harmonyEntriesArePaired(harmony: Harmony) {
    let store = ColorStore(initialInput: "#3b82f6")
    store.exportSource = .harmony
    store.harmony = harmony

    let entries = store.exportEntries
    let members = try? #require(store.color).harmony(harmony, options: store.harmonyOptions)

    #expect(entries.count == members?.count)
    #expect(entries.map(\.color) == members)
    #expect(Set(entries.map(\.key)).count == entries.count)
  }

  /// Empty until something is filed, which is the one source that can legitimately have
  /// nothing in it — and the reason the panel has a message for that case.
  @Test("Recents export in the order they are shown")
  func recentsAreNewestFirst() {
    let store = ColorStore(initialInput: "#3b82f6")
    store.exportSource = .recents
    #expect(store.exportEntries.isEmpty)

    store.remember()
    store.inputText = "#ef4444"
    store.remember()

    let entries = store.exportEntries
    #expect(entries.map(\.key) == ["1", "2"])
    #expect(entries.first?.color == ColorValue.srgb8(0xEF, 0x44, 0x44))
  }

  /// No color in the field means nothing to export, from any source — the panel shows
  /// its unavailable state instead, and the document must not be a lone `:root {}`.
  @Test("An empty field exports nothing at all", arguments: ExportSource.allCases)
  func noColorExportsNothing(source: ExportSource) {
    let store = ColorStore(initialInput: "not a color")
    store.exportSource = source

    #expect(store.exportEntries.isEmpty)
    #expect(store.exportDocument.isEmpty)
  }

  /// The panel's precision control and the toolbar's are one setting, so writing through
  /// either has to move the document. If these ever became separate state this is the
  /// assertion that would fail.
  @Test("The document follows the app-wide precision")
  func documentFollowsFormatOptions() {
    let store = ColorStore(initialInput: "#3b82f6")
    store.exportSource = .color
    store.exportOptions.format = .oklch

    store.formatOptions.precision = 2
    let coarse = store.exportDocument
    store.formatOptions.precision = 10
    let fine = store.exportDocument

    #expect(coarse != fine)
    #expect(fine.count > coarse.count)
  }

  /// The badge counts what the serializer actually moved, because both ask the same
  /// predicate. A hex export of a wide color moves it; an OKLCH export of the same color
  /// does not, OKLCH being unbounded.
  @Test("The mapped count agrees with the format's reach")
  func mappedCountTracksTheFormat() {
    let store = ColorStore(initialInput: "oklch(0.72 0.28 142)")
    store.exportSource = .color

    store.exportOptions.format = .hex
    #expect(store.exportGamutMappedCount == 1)

    store.exportOptions.format = .oklch
    #expect(store.exportGamutMappedCount == 0)
  }

  /// The shape that writes two spellings counts against the **fallback**, and the badge
  /// would lie either way round if it did not.
  ///
  /// Measured against the P3 block, this color — outside sRGB, inside Display P3 — would
  /// report `0 mapped` while the hex line directly under the badge had been rounded. The
  /// selection is left at `oklch()`, unbounded and equally silent, which is what makes
  /// this a test of `mappedCountFormat` rather than of the format picker: reading
  /// `exportOptions.format` here gives 0.
  @Test("The P3 shape counts what its fallback moved, not what its selection would")
  func mappedCountFollowsTheShapesFallback() {
    let store = ColorStore(initialInput: "color(display-p3 0 1 0)")
    store.exportSource = .color
    store.exportOptions.format = .oklch

    #expect(store.exportGamutMappedCount == 0, "oklch() is unbounded; nothing is mapped")

    store.exportOptions.shape = .p3WithFallback
    #expect(store.exportGamutMappedCount == 1)
    #expect(store.exportOptions.mappedCountFormat == ExportOptions.fallbackFormat)
    // …and the selection really is still the one that reports nothing.
    #expect(store.exportOptions.format == .oklch)
  }
}

/// The seam M8 deferred: a palette saved in a project, exported.
///
/// Asserted on ``ColorStore`` with no `ModelContainer` in sight, which is the point of
/// staging plain ``PaletteEntry`` values rather than handing the export layer a
/// `Palette` — see ``ColorStore/stagedPalette``. What the persistence side of the same
/// journey does is in ``ProjectStoreTests``.
@MainActor
@Suite("Staged palettes")
struct StagedPaletteTests {
  /// Staging is four changes at once, and every one of them is load-bearing: the source
  /// switches, the family name follows the palette, the tool changes, and the entries
  /// arrive. Miss the name and a palette saved as `brand` exports under whatever the
  /// panel was last set to.
  @Test("Staging a palette carries its name into the export")
  func stagingCarriesTheName() {
    let store = ColorStore(initialInput: "#3b82f6")
    let entries = [
      PaletteEntry(key: "50", color: .srgb8(0xEF, 0xF6, 0xFF)),
      PaletteEntry(key: "500", color: .srgb8(0x3B, 0x82, 0xF6)),
    ]

    store.stage(entries, named: "brand")

    #expect(store.exportSource == .saved)
    #expect(store.exportOptions.name == "brand")
    #expect(store.tool == .export)
    #expect(store.exportEntries.map(\.key) == ["50", "500"])
    #expect(store.exportDocument.contains("--brand-500:"))
  }

  /// The one source that does not read the input field. A saved palette was chosen
  /// earlier and does not stop existing because the field was cleared — and the panel
  /// guards on this exact property, since hiding the controls would hide the Source
  /// picker that reaches the palette.
  @Test("A staged palette outlives the field it was not derived from")
  func stagedPaletteSurvivesAnEmptyField() {
    let store = ColorStore(initialInput: "#3b82f6")
    store.stage([PaletteEntry(key: "base", color: .srgb8(0x3B, 0x82, 0xF6))], named: "brand")

    store.inputText = ""

    #expect(store.color == nil)
    #expect(store.exportEntries.count == 1)
    #expect(!store.exportDocument.isEmpty)
  }

  /// The Projects panel saves "the harmony" while the export panel is set to something
  /// else entirely, so the lookup has to be independent of ``ColorStore/exportSource``.
  /// Sharing one function is also what stops a saved ramp and an exported ramp being
  /// keyed differently.
  @Test("Any source can be asked for its colors, whichever one is selected")
  func entriesAreIndependentOfSelection() {
    let store = ColorStore(initialInput: "#3b82f6")
    store.exportSource = .color

    #expect(store.entries(for: .ramp).map(\.key) == PaletteNaming.tailwindScale)
    #expect(
      store.entries(for: .harmony).map(\.key)
        == PaletteNaming.harmonyKeys(store.harmony, options: store.harmonyOptions),
    )
    // …and the selected source is untouched by having asked.
    #expect(store.exportSource == .color)
    #expect(store.exportEntries.count == 1)
  }

  /// A palette records where it came from, so the kinds have to line up with the sources
  /// that can produce one. The two that cannot are `custom` rather than a guess.
  @Test("Every savable source names a palette kind", arguments: ExportSource.allCases)
  func sourcesMapToKinds(source: ExportSource) {
    switch source {
    case .harmony: #expect(source.paletteKind == .harmony)
    case .ramp: #expect(source.paletteKind == .ramp)
    case .recents: #expect(source.paletteKind == .recents)
    case .color, .saved, .project: #expect(source.paletteKind == .custom)
    }
  }
}

/// The M20 sibling of ``StagedPaletteTests``: a whole project, staged as groups rather
/// than a single flat list.
///
/// - Note: ``ExportSourceTests/noColorExportsNothing(source:)`` already runs over
///   ``ExportSource/project`` by way of `ExportSource.allCases`, but it asserts nothing
///   meaningful about it — nothing is ever staged there, so it only proves an *unused*
///   `.project` source is empty. The coverage for what staging actually does is here.
@MainActor
@Suite("Staged projects")
struct StagedProjectTests {
  /// Staging a project is the same four changes ``stagingCarriesTheName`` pins for a
  /// single palette, plus the one M20 adds: the document comes from the grouped
  /// renderer, so a second group's family name shows up in it too.
  @Test("Staging a project carries its name and every group's")
  func stagingCarriesEveryGroupsName() {
    let store = ColorStore(initialInput: "#3b82f6")
    let groups = [
      PaletteGroup(name: "primary", entries: [
        PaletteEntry(key: "500", color: .srgb8(0x3B, 0x82, 0xF6)),
      ]),
      PaletteGroup(name: "secondary", entries: [
        PaletteEntry(key: "500", color: .srgb8(0xEF, 0x44, 0x44)),
      ]),
    ]

    store.stage(project: groups, named: "my-project")

    #expect(store.exportSource == .project)
    #expect(store.exportOptions.name == "my-project")
    #expect(store.tool == .export)
    #expect(store.exportDocument.contains("--primary-500:"))
    #expect(store.exportDocument.contains("--secondary-500:"))
  }

  /// A staged project does not read the input field, matching
  /// ``StagedPaletteTests/stagedPaletteSurvivesAnEmptyField()`` — a project export is a
  /// set assembled earlier, and `ExportPanel`'s own guard checks exactly this property
  /// to decide whether the Source picker itself is worth showing.
  @Test("A staged project outlives the field it was not derived from")
  func stagedProjectSurvivesAnEmptyField() {
    let store = ColorStore(initialInput: "#3b82f6")
    store.stage(
      project: [PaletteGroup(name: "brand", entries: [PaletteEntry(color: .srgb8(0x3B, 0x82, 0xF6))])],
      named: "brand",
    )

    store.inputText = ""

    #expect(store.color == nil)
    #expect(store.exportEntries.count == 1, "The flattened entries should survive too")
    #expect(!store.exportDocument.isEmpty)
  }

  /// ``ColorStore/exportEntries`` flattens every group into one list for callers that
  /// only want colors — the mapped-count badge, the swatch strip — which have no notion
  /// of a group at all.
  @Test("The flattened entries cover every group, in order")
  func exportEntriesFlattenEveryGroup() {
    let store = ColorStore(initialInput: "#3b82f6")
    let groups = [
      PaletteGroup(name: "primary", entries: [PaletteEntry(key: "500", color: .srgb8(0x3B, 0x82, 0xF6))]),
      PaletteGroup(name: "secondary", entries: [PaletteEntry(key: "600", color: .srgb8(0xEF, 0x44, 0x44))]),
    ]

    store.stage(project: groups, named: "brand")

    #expect(store.exportEntries.map(\.key) == ["500", "600"])
    #expect(store.exportEntries.map(\.color) == [.srgb8(0x3B, 0x82, 0xF6), .srgb8(0xEF, 0x44, 0x44)])
  }
}

/// The export panel's own wording and controls.
///
/// Unlike ``FormatSection``, the presentation here is written as exhaustive `switch`es,
/// so "every case has a title" is already a compile error rather than a test. What the
/// compiler cannot check is that the titles are *usable* — a picker with two identical
/// rows compiles perfectly and is unusable.
///
/// - Note: `@MainActor` for ``Tool`` alone. ``ExportShape`` and ``ExportTemplate`` are
///   `nonisolated`, but `Tool` is shell state that only views ever read, so under
///   `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` its `title` is main-actor isolated. The
///   suite hops rather than the type being loosened, since nothing outside the UI has
///   any business reading it.
@MainActor
@Suite("Export presentation")
struct ExportPresentationTests {
  @Test("Shape titles are distinct and non-empty")
  func shapeTitlesAreUsable() {
    let titles = ExportShape.allCases.map(\.title)
    #expect(titles.allSatisfy { !$0.isEmpty })
    #expect(Set(titles).count == titles.count)
    #expect(ExportShape.allCases.allSatisfy { !$0.summary.isEmpty })
  }

  @Test("Template titles are distinct and name their property")
  func templateTitlesAreUsable() {
    let titles = ExportTemplate.allCases.map(\.title)
    #expect(Set(titles).count == titles.count)
    #expect(ExportTemplate.allCases.allSatisfy { $0.title.hasPrefix($0.property) })
  }

  /// Exactly one shape takes a declaration template, and it is the one that takes no
  /// family name. The panel hides whichever control does not apply, so a shape answering
  /// `true` to both would show a name field that changes nothing.
  @Test("Template and name apply to opposite shapes", arguments: ExportShape.allCases)
  func templateAndNameAreComplementary(shape: ExportShape) {
    #expect(shape.usesTemplate != shape.usesName)
  }

  /// The mapped warning is per shape now, because the generic sentence is false of the
  /// one that writes two blocks: "the values below were brought into gamut" is true of
  /// its fallback and wrong about the `@media` block underneath, which carries those
  /// colors exactly. A shape with no sentence would show a bare badge and no reason.
  @Test("Every shape can explain a mapped count", arguments: ExportShape.allCases)
  func mappedNotesAreWritten(shape: ExportShape) {
    for count in [1, 4] {
      let note = shape.mappedNote(count: count, format: .hex)
      #expect(!note.isEmpty)
      // Singular and plural are written out rather than suffixed with "(s)", so the two
      // must actually differ — a shape wording only one of them reads as a bug.
      #expect(note != shape.mappedNote(count: count == 1 ? 4 : 1, format: .hex))
    }
  }

  /// The P3 shape names both of its blocks, and names neither the user's format selection
  /// (which it ignores) nor a gamut it does not write.
  ///
  /// **It also promises nothing about exactness, which is the assertion that matters.**
  /// An earlier draft said the media block "carries them exactly" — true of the colors
  /// inside P3 that motivate the shape, false of every color outside it, and this badge
  /// counts both because the count is measured against hex. A substring check cannot
  /// catch a false claim, so the *fact* is pinned by an input in
  /// ``ExportShapeTests/p3OverrideIsNotAnExactnessPromise()``; what is checked here is
  /// that the copy has not drifted back to making the claim.
  @Test("The P3 warning names both blocks and claims no more than it can")
  func p3MappedNoteNamesTheBlocks() {
    let note = ExportShape.p3WithFallback.mappedNote(
      count: 2,
      format: ExportOptions.fallbackFormat,
    )
    #expect(note.contains("fallback"))
    #expect(note.contains("@media"))
    #expect(!note.contains("brought into gamut"), "The generic sentence leaked through")
    #expect(!note.contains("exactly"), "The override cannot promise this for every color")
  }

  /// Source titles share a segmented control, and its empty-state copy has to be true of
  /// the source it is shown for. Recents and Saved are both legitimately empty and empty
  /// for unrelated reasons — one fills up as you work, the other waits on a palette being
  /// staged — so one sentence cannot serve both. That is M8's placeholder defect exactly:
  /// wording that belongs to one case, reused where it is false.
  @Test("Every source has usable copy, and the two empty cases differ")
  func sourceCopyIsUsable() {
    let titles = ExportSource.allCases.map(\.title)
    #expect(Set(titles).count == titles.count)
    #expect(ExportSource.allCases.allSatisfy { !$0.emptyMessage.isEmpty })
    #expect(ExportSource.recents.emptyMessage != ExportSource.saved.emptyMessage)
  }

  /// Every tool the switcher offers has a panel behind it. `ContentView`'s `switch` is
  /// exhaustive so a missing branch will not compile, but a `Tool` case added without a
  /// title would render a blank segment.
  @Test("Every tool is labelled")
  func everyToolHasATitle() {
    #expect(Tool.allCases.allSatisfy { !$0.title.isEmpty })
    #expect(Set(Tool.allCases.map(\.title)).count == Tool.allCases.count)
    #expect(Tool.allCases.last == .export, "Export is terminal and belongs last")
  }
}

@MainActor
@Suite("Web-friendly export (M22)")
struct WebFriendlyExportStoreTests {
  /// A vivid enough base that its complement provably leaves sRGB by default — the
  /// same premise ``HarmonyTests/harmoniesAreNotGamutMapped`` establishes.
  static let vivid = "oklch(0.65 0.2 30)"

  /// A harmony's exported entries and its `TransformPanel` preview read the same
  /// `effectiveHarmonyOptions`, so this is really pinning that seam rather than
  /// re-testing ``ColorValue/harmony(_:options:)`` itself.
  @Test("Under webFriendly, exported harmony entries stay inside sRGB")
  func harmonyEntriesStayInGamutUnderWebFriendly() {
    let store = ColorStore(initialInput: Self.vivid)
    store.exportSource = .harmony
    store.harmony = .complementary
    store.webFriendly = true

    #expect(store.exportEntries.allSatisfy { $0.color.inGamut(of: .srgb) })
  }

  /// Off is the default and must leave the escaping member exactly as
  /// ``HarmonyTests/harmoniesAreNotGamutMapped`` pins it — the flag is what makes the
  /// difference, not merely calling through `effectiveHarmonyOptions`.
  @Test("Off, the same harmony still escapes sRGB")
  func harmonyEntriesEscapeWhenWebFriendlyIsOff() {
    let store = ColorStore(initialInput: Self.vivid)
    store.exportSource = .harmony
    store.harmony = .complementary
    store.webFriendly = false

    #expect(!store.exportEntries.allSatisfy { $0.color.inGamut(of: .srgb) })
  }

  /// The integration version of ``WebFriendlyExportTests/renderedDocumentNeverEscapes``:
  /// a *stored* `p3WithFallback` preference (M19 persists it) plus the flag turned on
  /// must not reach the clipboard as a wide-gamut document, even though nothing here
  /// touches `store.exportOptions.shape` to work around it.
  @Test("exportDocument never writes @media or color() while webFriendly is on")
  func exportDocumentNeverEscapesUnderWebFriendly() {
    let store = ColorStore(initialInput: "#3b82f6")
    store.exportSource = .color
    store.exportOptions.shape = .p3WithFallback
    store.webFriendly = true

    let document = store.exportDocument
    #expect(!document.contains("@media"))
    #expect(!document.contains("color("))
    // The stored preference itself is untouched — turning the flag back off
    // restores the shape the panel showed before.
    #expect(store.exportOptions.shape == .p3WithFallback)
  }
}
