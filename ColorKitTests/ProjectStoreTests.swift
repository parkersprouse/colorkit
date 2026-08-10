//
//  ProjectStoreTests.swift
//  ColorKitTests
//

@testable import ColorKit
import Foundation
import SwiftData
import Testing

/// The persistence layer against a real, in-memory `ModelContainer`.
///
/// Everything here needs a container because everything here is about what SwiftData
/// does — relationships, cascades, what comes back from a fetch. The *mapping* is
/// asserted in ``ColorRecordTests``, which needs none of this.
@MainActor
@Suite("Project store")
struct ProjectStoreTests {
  // MARK: Internal

  /// The first assertion, and not a formality.
  ///
  /// ``SavedColor`` is the destination of two to-many relationships — a project's loose
  /// colors and a palette's entries — and SwiftData resolves inverses when the container
  /// is built, not when the code compiles. Get it wrong and every model still compiles,
  /// every property still type-checks, and the app throws on launch. This is the check
  /// that turns that into a test failure.
  @Test("The schema builds a container")
  func containerBuilds() throws {
    let container = try Self.makeContainer()

    #expect(container.schema.entities.count == 3)
  }

  /// The app's own factory, not just a hand-rolled container — the launch argument is
  /// the only thing standing between a UI test and the user's real library, so it is
  /// worth an assertion of its own.
  ///
  /// It reports ``PersistenceStack/Status/ephemeralByRequest`` rather than
  /// ``PersistenceStack/Status/unavailable``, which is the distinction that keeps the
  /// panel from warning about a failure that did not happen. The two were one flag until
  /// the UI-test screenshots showed the app announcing a store it "could not open"
  /// during a run that had asked for exactly that store.
  @Test("The launch argument produces a store that says why it is ephemeral")
  func launchArgumentIsEphemeralByRequest() {
    #expect(PersistenceStack.make(inMemory: true).status == .ephemeralByRequest)
  }

  @Test("A saved color comes back as the color that went in")
  func savedColorRoundTrips() throws {
    let library = try Self.makeLibrary()
    let project = try library.createProject(named: "Site")
    let blue = try CSSColorParser.parse("#3b82f6").color

    try library.saveColor(ColorRecord(blue, text: "#3b82f6"), named: "Brand", to: project)

    let reloaded = try #require(try library.projects().first)
    let color = try #require(reloaded.orderedColors.first)
    #expect(color.name == "Brand")
    #expect(color.colorValue == blue)
  }

  /// The reason the spelling is stored at all, asserted end to end rather than only at
  /// the bridge: recalling this color has to put `rebeccapurple` back in the field, not
  /// the `#663399` a serializer would hand back.
  @Test("A recalled color keeps the spelling it was saved with")
  func savedColorKeepsItsSpelling() throws {
    let library = try Self.makeLibrary()
    let project = try library.createProject(named: "Site")
    let purple = try CSSColorParser.parse("rebeccapurple").color

    try library.saveColor(ColorRecord(purple, text: "rebeccapurple"), to: project)

    let color = try #require(try library.projects().first?.orderedColors.first)
    #expect(color.text == "rebeccapurple")
  }

  /// A ramp's order *is* its meaning, and a to-many relationship does not promise one —
  /// hence ``SavedColor/sortIndex`` and the sort on read. Eleven stops shuffled is not a
  /// ramp, and the eleven keys would then name the wrong colors.
  @Test("A saved palette keeps its order and its keys")
  func savedPaletteKeepsOrderAndKeys() throws {
    let library = try Self.makeLibrary()
    let project = try library.createProject(named: "Site")
    let base = try CSSColorParser.parse("#3b82f6").color
    let stops = ShadeRamp.default.generated(from: base)
    let entries = zip(PaletteNaming.rampKeys(count: stops.count), stops)
      .map { PaletteEntry(key: $0, color: $1) }

    try library.savePalette(entries, named: "Brand", kind: .ramp, to: project)

    let palette = try #require(try library.projects().first?.orderedPalettes.first)
    #expect(palette.kind == .ramp)
    #expect(palette.paletteEntries.map(\.key) == PaletteNaming.tailwindScale)
    // Lightest first, all the way down — the property the ramp itself guarantees, now
    // asserted on the other side of a save.
    let lightnesses = palette.paletteEntries.map { $0.color.converted(to: .oklch).components.x }
    #expect(lightnesses == lightnesses.sorted(by: >))
  }

  /// Every stop of a saved ramp has to survive the trip, not just the ends. The stored
  /// spelling is `oklch()` at lossless precision, so agreement here is tight.
  @Test("Every palette entry survives the round trip")
  func paletteEntriesSurvive() throws {
    let library = try Self.makeLibrary()
    let project = try library.createProject(named: "Site")
    let base = try CSSColorParser.parse("#3b82f6").color
    let original = ShadeRamp.default.generated(from: base)
    let entries = zip(PaletteNaming.rampKeys(count: original.count), original)
      .map { PaletteEntry(key: $0, color: $1) }

    try library.savePalette(entries, named: "Brand", kind: .ramp, to: project)

    let restored = try #require(try library.projects().first?.orderedPalettes.first)
      .paletteEntries.map(\.color)
    #expect(restored.count == original.count)
    for (saved, source) in zip(restored, original) {
      #expect(saved.deltaEOK(to: source) < 1e-9)
    }
  }

  // MARK: - Imported palettes

  /// The whole import path against a container: decoded tokens in, a palette out, with
  /// the keys, the order and the provenance the file gave them.
  @Test("An imported token file becomes a palette that keeps its keys and order")
  func importedTokensBecomeAPalette() throws {
    let library = try Self.makeLibrary()
    let project = try library.createProject(named: "Site")
    let document = try DesignTokenImport.decode(Data(Self.rampTokens.utf8))

    try library.savePalette(importing: document.colors, named: "Brand", to: project)

    let palette = try #require(try library.projects().first?.orderedPalettes.first)
    #expect(palette.name == "Brand")
    // Provenance, kept for the reason every other kind is: an imported palette's keys are
    // somebody else's names, and that is what explains why they look nothing like a ramp's.
    #expect(palette.kind == .imported)
    #expect(palette.paletteEntries.map(\.key) == ["brand-50", "brand-100", "brand-900"])
  }

  /// **A design token's `colorSpace` is authored information, so it survives storage.**
  ///
  /// The `PaletteEntry` overload spells everything `oklch()`, which is right for a ramp
  /// stop that never had a space of its own. Route an import through it and a
  /// `display-p3` token comes back spelled `oklch(…)` — the same color, and not the same
  /// answer, exactly as re-deriving `rebeccapurple` as `#663399` would be.
  @Test("An imported color keeps the space its token named")
  func importedColorsKeepTheirOwnSpelling() throws {
    let library = try Self.makeLibrary()
    let project = try library.createProject(named: "Site")
    let document = try DesignTokenImport.decode(Data(#"""
    { "t": { "$type": "color", "wide": { "$value": {
      "colorSpace": "display-p3", "components": [0.9, 0.2, 0.15] } } } }
    """#.utf8))

    try library.savePalette(importing: document.colors, named: "Wide", to: project)

    let saved = try #require(
      try library.projects().first?.orderedPalettes.first?.orderedEntries.first,
    )
    #expect(saved.text.hasPrefix("color(display-p3"), "Stored as “\(saved.text)”")
    #expect(saved.colorValue?.space == .displayP3)
  }

  /// **The payoff path, and the one claim in M17's docs that nothing else holds.**
  ///
  /// Somebody imports a token file in order to emit CSS from it, and "export came free"
  /// is only true if an imported palette reaches the export layer as any other does. It
  /// does, because `Palette.paletteEntries` is the boundary and nothing downstream can
  /// tell where a `PaletteEntry` came from.
  ///
  /// The double prefix in `--brand-brand-50` is **expected, and is what a token file
  /// actually produces**. The family name comes from the file (`brand.tokens.json`) and
  /// the key comes from the token's full path (`brand.50`), and those two sources overlap
  /// whenever a file's top-level group is named after the file — which is the conventional
  /// shape. It is left alone rather than stripped: the family name is a free-text field in
  /// the export panel and one edit away, where any automatic stripping would make the keys
  /// depend on how many top-level groups a file happened to have. Full paths are the right
  /// keys for the reason `DesignTokenImport.keyed` gives — `brand.500` and `accent.500`
  /// collapsing to `500` and `500-2` is a worse answer than a long name.
  @Test("An imported palette exports like any other")
  func importedPalettesExport() throws {
    let library = try Self.makeLibrary()
    let project = try library.createProject(named: "Site")
    let document = try DesignTokenImport.decode(Data(Self.rampTokens.utf8))

    try library.savePalette(importing: document.colors, named: "brand", to: project)

    let palette = try #require(try library.projects().first?.orderedPalettes.first)
    var options = ExportOptions.default
    options.shape = .customProperties
    options.name = palette.name
    let rendered = options.render(palette.paletteEntries)

    // The names carry this test's claim, so they are pinned exactly. The *values* are
    // pulled back out and parsed instead — this app's own parser is the export layer's
    // oracle, and re-typing hex digits here would only test whether they were copied
    // correctly.
    let names = rendered.split(separator: "\n").compactMap { line in
      line.trimmingCharacters(in: CharacterSet.whitespaces).split(separator: ":").first.map(String.init)
    }
    .filter { $0.hasPrefix("--") }
    #expect(names == ["--brand-brand-50", "--brand-brand-100", "--brand-brand-900"])

    let values = ExportRoundTripTests.propertyValues(in: rendered)
    #expect(values.count == 3, "Expected one value per token:\n\(rendered)")
    for (value, entry) in zip(values, palette.paletteEntries) {
      let parsed = try CSSColorParser.parse(value).color
      // Not the 1e-9 that `paletteEntriesSurvive` uses, and the difference is the point:
      // that test round-trips through *storage*, which is lossless, where this one goes
      // through a rendered document at the panel's display precision of four decimals.
      // Measured agreement is ~5e-5. The competing hypothesis is a pairing error — values
      // emitted in a different order from their names — and these three shades run from
      // near-white to navy, so a mismatched pair differs by more than 0.3. Three hundred
      // times the tolerance, rather than a tolerance chosen to fit.
      #expect(parsed.deltaEOK(to: entry.color) < 1e-3)
    }
  }

  /// `$description` is the field a design system says *why* in, exactly once. Notes are
  /// where this app already keeps that, so nothing is invented to hold it.
  @Test("A token's description is stored as the color's notes")
  func importedDescriptionsBecomeNotes() throws {
    let library = try Self.makeLibrary()
    let project = try library.createProject(named: "Site")
    let document = try DesignTokenImport.decode(Data(#"""
    { "t": { "$type": "color", "c": {
      "$description": "The one on the buttons",
      "$value": { "colorSpace": "srgb", "components": [0, 0, 1] } } } }
    """#.utf8))

    try library.savePalette(importing: document.colors, named: "Tokens", to: project)

    let saved = try #require(
      try library.projects().first?.orderedPalettes.first?.orderedEntries.first,
    )
    #expect(saved.notes == "The one on the buttons")
  }

  // MARK: - Imported palettes (M26, pasted text)

  /// **The fourth overload writes `ImportedEntry/text` verbatim, never a re-derived
  /// spelling.** The discriminating input is a color whose *stored components* would
  /// re-serialize differently at `.lossless` than the exact substring pasted in — an
  /// out-of-gamut `oklch()` value, since `.lossless` preserves rather than clamps but
  /// still reformats to its own decimal precision. Routing this through
  /// `.derived(_:preferring:)` would rewrite it; this overload must not.
  @Test("An imported entry's text is stored exactly as pasted, not re-derived")
  func importedEntryTextIsStoredVerbatim() throws {
    let library = try Self.makeLibrary()
    let project = try library.createProject(named: "Site")
    let pasted = "oklch(0.7 0.5 140.123456789)"
    let color = try CSSColorParser.parse(pasted).color
    let entry = ImportedEntry(key: "500", color: color, text: pasted)

    try library.savePalette(importing: [entry], named: "Brand", to: project)

    let saved = try #require(try library.projects().first?.orderedPalettes.first?.orderedEntries.first)
    #expect(saved.text == pasted)
  }

  /// The same check every stored spelling is held to: parsing the stored text has to
  /// reproduce the stored components, or the two are two claims that can drift apart.
  @Test("An imported entry's stored text reproduces its stored components")
  func importedEntryTextReproducesComponents() throws {
    let library = try Self.makeLibrary()
    let project = try library.createProject(named: "Site")
    let text = """
    :root {
      --brand-500: #3b82f6;
      --brand-600: #ef4444;
    }
    """
    let imported = try PaletteImport.parse(text, as: .customProperties)
    let group = try #require(imported.groups.first)

    try library.savePalette(importing: group.entries, named: group.name, to: project)

    let palette = try #require(try library.projects().first?.orderedPalettes.first)
    #expect(palette.kind == .imported)
    for saved in palette.orderedEntries {
      let reparsed = try CSSColorParser.parse(saved.text).color
      #expect(reparsed == saved.colorValue)
    }
  }

  /// M30's fifth save door. `saveColor(importing:)` is the loose-color sibling of the
  /// fourth `savePalette` overload and carries the same verbatim promise: the stored text
  /// is the literal pasted substring, never a `.derived(_:preferring:)` round trip that
  /// would re-spell it. Same out-of-gamut `oklch()` as `importedEntryTextIsStoredVerbatim`,
  /// which `.lossless` preserves but reformats to its own precision — so a regression that
  /// routed through `.derived` changes the string and fails here. `notes` is the *other*
  /// reason this door exists (a design token's `$description` rides in on it) and is
  /// otherwise untested for a loose color, so it is asserted too.
  @Test("An imported loose color stores its text verbatim and keeps its notes")
  func importedLooseColorIsStoredVerbatim() throws {
    let library = try Self.makeLibrary()
    let project = try library.createProject(named: "Site")
    let pasted = "oklch(0.7 0.5 140.123456789)"
    let color = try CSSColorParser.parse(pasted).color
    let entry = ImportedEntry(key: "", color: color, text: pasted, notes: "Primary brand color")

    try library.saveColor(importing: entry, named: "Brand base", to: project)

    let saved = try #require(try library.projects().first?.orderedColors.first)
    #expect(saved.text == pasted)
    #expect(saved.notes == "Primary brand color")
    #expect(saved.name == "Brand base")
  }

  /// An orphaned `SavedColor` belongs to no project, so no view would ever show it and
  /// nobody would ever know it was there. The cascade is declared on the relationships;
  /// this is what proves it reaches both of them — the loose colors *and* the ones two
  /// levels down inside a palette.
  @Test("Deleting a project takes its colors and palettes with it")
  func deletingAProjectCascades() throws {
    let library = try Self.makeLibrary()
    let project = try library.createProject(named: "Site")
    let blue = try CSSColorParser.parse("#3b82f6").color
    try library.saveColor(ColorRecord(blue, text: "#3b82f6"), to: project)
    try library.savePalette(
      [PaletteEntry(key: "base", color: blue), PaletteEntry(key: "alt", color: blue)],
      named: "Brand",
      kind: .harmony,
      to: project,
    )
    #expect(try library.context.fetch(FetchDescriptor<SavedColor>()).count == 3)

    try library.delete(project)

    #expect(try library.projects().isEmpty)
    #expect(try library.context.fetch(FetchDescriptor<Palette>()).isEmpty)
    #expect(try library.context.fetch(FetchDescriptor<SavedColor>()).isEmpty)
  }

  /// Deleting a palette must not reach the project's loose colors, which is the other
  /// half of the cascade being right: one shared inverse would take both.
  @Test("Deleting a palette leaves the project's own colors alone")
  func deletingAPaletteSparesLooseColors() throws {
    let library = try Self.makeLibrary()
    let project = try library.createProject(named: "Site")
    let blue = try CSSColorParser.parse("#3b82f6").color
    try library.saveColor(ColorRecord(blue, text: "#3b82f6"), to: project)
    let palette = try library.savePalette(
      [PaletteEntry(key: "base", color: blue)],
      named: "Brand",
      kind: .harmony,
      to: project,
    )

    try library.delete(palette)

    let reloaded = try #require(try library.projects().first)
    #expect(reloaded.orderedColors.count == 1)
    #expect(reloaded.orderedPalettes.isEmpty)
    #expect(try library.context.fetch(FetchDescriptor<SavedColor>()).count == 1)
  }

  /// Positions come from one past the highest in use, not from the count. Delete the
  /// middle of three and a count-based index would reuse position 2, putting the new
  /// color *before* the one already sitting there.
  @Test("A new color lands last even after a deletion")
  func newColorsLandLast() throws {
    let library = try Self.makeLibrary()
    let project = try library.createProject(named: "Site")
    let colors = ["#ff0000", "#00ff00", "#0000ff"]
    for css in colors {
      let color = try CSSColorParser.parse(css).color
      try library.saveColor(ColorRecord(color, text: css), named: css, to: project)
    }

    let middle = try #require(project.orderedColors.dropFirst().first)
    try library.delete(middle)
    let added = try CSSColorParser.parse("#ffff00").color
    try library.saveColor(ColorRecord(added, text: "#ffff00"), named: "#ffff00", to: project)

    #expect(project.orderedColors.map(\.name) == ["#ff0000", "#0000ff", "#ffff00"])
  }

  /// A blank name is a row nothing in a list can show, so the fallback is applied where
  /// the value is stored rather than in every view that will ever display one.
  @Test("An empty project name falls back rather than storing nothing")
  func emptyNamesFallBack() throws {
    let library = try Self.makeLibrary()

    let project = try library.createProject(named: "   ")
    let palette = try library.savePalette(
      [PaletteEntry(color: ColorValue.srgb8(0, 0, 0))],
      named: "",
      kind: .ramp,
      to: project,
    )

    #expect(!project.name.isEmpty)
    #expect(palette.name == PaletteKind.ramp.title)
  }

  /// The selection on ``ColorStore`` is a `UUID` so the store need not import SwiftData;
  /// this is the lookup that makes that indirection work, including the case that
  /// matters — a project deleted while it was the selected one.
  @Test("A project is findable by the id the store remembers")
  func projectsAreFindableByUUID() throws {
    let library = try Self.makeLibrary()
    let project = try library.createProject(named: "Site")
    let id = project.uuid

    #expect(try library.project(uuid: id)?.name == "Site")

    try library.delete(project)
    #expect(try library.project(uuid: id) == nil)
  }

  /// Notes are edited by binding a `TextField` straight to the model, so the write has
  /// already happened by the time anything is called — what ``ProjectLibrary/touch(_:)``
  /// adds is the flush and the timestamp. This is the assertion that the note survives a
  /// fetch rather than living only in the object the panel happens to be holding.
  @Test("A note on a saved color persists")
  func notesPersist() throws {
    let library = try Self.makeLibrary()
    let project = try library.createProject(named: "Site")
    let blue = try CSSColorParser.parse("#3b82f6").color
    let color = try library.saveColor(ColorRecord(blue, text: "#3b82f6"), named: "Brand", to: project)

    color.notes = "Primary call to action only"
    try library.touch(color)

    let reloaded = try #require(try library.projects().first?.orderedColors.first)
    #expect(reloaded.notes == "Primary call to action only")
  }

  /// `modifiedAt` should mean what it says. Saving into a project is a modification of
  /// it, even though nothing about the `Project` row itself changed.
  @Test("Saving into a project marks it modified")
  func savingTouchesTheProject() throws {
    let library = try Self.makeLibrary()
    let project = try library.createProject(named: "Site")
    let before = project.modifiedAt
    let blue = try CSSColorParser.parse("#3b82f6").color

    try library.saveColor(ColorRecord(blue, text: "#3b82f6"), to: project)

    #expect(project.modifiedAt > before)
  }

  /// The claim the whole milestone rests on, and the only test here that leaves memory.
  ///
  /// Every other test in this file uses `isStoredInMemoryOnly`, which proves round
  /// tripping *within* a context and structurally cannot prove that anything survives the
  /// app being quit — the thing "saved projects" actually means. So this one writes to a
  /// real SQLite store, drops the container entirely, opens a second one over the same
  /// file and reads it back.
  ///
  /// Both halves of the store's meaning are checked: `rebeccapurple` for the spelling,
  /// and the ramp for order, since ``SavedColor/sortIndex`` is doing its work across a
  /// genuine reopen here rather than across one in-memory fetch.
  ///
  /// The temp path is a *directory*, not a bare file. SQLite writes `-wal` and `-shm`
  /// sidecars beside the store, and removing only the `.store` would leave state behind
  /// that could make a later run pass for the wrong reason.
  @Test("A saved project survives the store closing and reopening")
  func dataSurvivesAReopen() throws {
    let directory = URL.temporaryDirectory
      .appending(path: "m9-reopen-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "projects.store")

    let purple = try CSSColorParser.parse("rebeccapurple").color
    let base = try CSSColorParser.parse("#3b82f6").color
    let stops = ShadeRamp.default.generated(from: base)

    // Scoped so the container is released before the second one opens the same file.
    do {
      let library = try ProjectLibrary(ModelContext(Self.makeContainer(at: url)))
      let project = try library.createProject(named: "Site")
      try library.saveColor(ColorRecord(purple, text: "rebeccapurple"), named: "Brand", to: project)
      try library.savePalette(
        zip(PaletteNaming.rampKeys(count: stops.count), stops)
          .map { PaletteEntry(key: $0, color: $1) },
        named: "Brand",
        kind: .ramp,
        to: project,
      )
    }

    let library = try ProjectLibrary(ModelContext(Self.makeContainer(at: url)))
    let project = try #require(try library.projects().first)
    #expect(project.name == "Site")

    let color = try #require(project.orderedColors.first)
    #expect(color.text == "rebeccapurple")
    #expect(color.colorValue == purple)
    #expect(color.name == "Brand")

    let palette = try #require(project.orderedPalettes.first)
    #expect(palette.kind == .ramp)
    #expect(palette.paletteEntries.map(\.key) == PaletteNaming.tailwindScale)
    for (saved, source) in zip(palette.paletteEntries.map(\.color), stops) {
      #expect(saved.deltaEOK(to: source) < 1e-9)
    }
  }

  // MARK: - Reordering

  /// `onMove` semantics: `destination` is a slot in the order as it stands *before*
  /// anything is lifted out, so moving the first color to position 3 of 3 puts it last
  /// rather than one short of it. Getting this wrong is invisible at the ends and wrong
  /// by one everywhere else.
  @Test("Moving a color rewrites the order")
  func reorderingMovesAColor() throws {
    let library = try Self.makeLibrary()
    let project = try Self.projectWithColors(["#ff0000", "#00ff00", "#0000ff"], in: library)

    try library.moveColors(fromOffsets: IndexSet(integer: 0), toOffset: 3, in: project)
    #expect(project.orderedColors.map(\.name) == ["#00ff00", "#0000ff", "#ff0000"])

    try library.moveColors(fromOffsets: IndexSet(integer: 2), toOffset: 0, in: project)
    #expect(project.orderedColors.map(\.name) == ["#ff0000", "#00ff00", "#0000ff"])
  }

  /// Two colors dragged together stay together and stay in their own order.
  @Test("A multiple selection moves as one block")
  func reorderingMovesASelection() throws {
    let library = try Self.makeLibrary()
    let project = try Self.projectWithColors(["#ff0000", "#00ff00", "#0000ff"], in: library)

    try library.moveColors(fromOffsets: IndexSet([0, 1]), toOffset: 3, in: project)

    #expect(project.orderedColors.map(\.name) == ["#0000ff", "#ff0000", "#00ff00"])
  }

  /// The rule that makes a move safe. ``ProjectLibrary/nextIndex(after:)`` leaves gaps so
  /// appends land last after a deletion, and a gap cannot hold an arbitrary insertion —
  /// so a move renumbers everything densely. This asserts both halves: the positions
  /// really are `0...n-1` afterwards, and appending still lands at the end, because
  /// renumbering must not break what the gaps were protecting.
  @Test("A move renumbers positions densely without breaking appends")
  func reorderingRenumbersDensely() throws {
    let library = try Self.makeLibrary()
    let project = try Self.projectWithColors(["#ff0000", "#00ff00", "#0000ff"], in: library)

    let middle = try #require(project.orderedColors.dropFirst().first)
    try library.delete(middle)
    #expect(project.orderedColors.map(\.sortIndex) == [0, 2])

    try library.moveColors(fromOffsets: IndexSet(integer: 1), toOffset: 0, in: project)
    #expect(project.orderedColors.map(\.sortIndex) == [0, 1])
    #expect(project.orderedColors.map(\.name) == ["#0000ff", "#ff0000"])

    let added = try CSSColorParser.parse("#ffff00").color
    try library.saveColor(ColorRecord(added, text: "#ffff00"), named: "#ffff00", to: project)
    #expect(project.orderedColors.map(\.name) == ["#0000ff", "#ff0000", "#ffff00"])
  }

  /// An out-of-range request is ignored rather than trapped. The offsets come from a drag,
  /// and a drop that lands as the grid is re-laying out can name an index that no longer
  /// exists; crashing on it would be a poor trade for a gesture the user can simply repeat.
  @Test("An out-of-range move changes nothing")
  func reorderingIgnoresBadOffsets() throws {
    let library = try Self.makeLibrary()
    let project = try Self.projectWithColors(["#ff0000", "#00ff00"], in: library)

    try library.moveColors(fromOffsets: IndexSet(integer: 7), toOffset: 0, in: project)
    try library.moveColors(fromOffsets: IndexSet(integer: 0), toOffset: 9, in: project)

    #expect(project.orderedColors.map(\.name) == ["#ff0000", "#00ff00"])
  }

  /// Reordering is a persistence claim, not a view-state one, so it has to be checked the
  /// way ``dataSurvivesAReopen`` checks the rest: a real store, dropped and reopened. An
  /// in-memory container would prove only that the objects in hand were mutated.
  @Test("A reordering survives the store closing and reopening")
  func reorderingSurvivesAReopen() throws {
    let directory = URL.temporaryDirectory
      .appending(path: "m11-reorder-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "projects.store")

    // Scoped so the container is released before the second one opens the same file.
    do {
      let library = try ProjectLibrary(ModelContext(Self.makeContainer(at: url)))
      let project = try Self.projectWithColors(["#ff0000", "#00ff00", "#0000ff"], in: library)
      try library.moveColors(fromOffsets: IndexSet(integer: 2), toOffset: 0, in: project)
    }

    let library = try ProjectLibrary(ModelContext(Self.makeContainer(at: url)))
    let project = try #require(library.projects().first)
    #expect(project.orderedColors.map(\.name) == ["#0000ff", "#ff0000", "#00ff00"])
  }

  // MARK: - Loose sets

  /// The reason this overload exists at all. These colors were typed by the user, so they
  /// have a spelling worth keeping; the ``PaletteEntry`` overload re-derives one because
  /// its colors — ramp stops, harmony members — never had one. Routing a loose set through
  /// that door would turn `rebeccapurple` into `oklch(…)` on the way in.
  @Test("A loose set keeps each color's authored spelling")
  func looseSetKeepsItsSpelling() throws {
    let library = try Self.makeLibrary()
    let project = try Self.projectWithColors(["rebeccapurple", "#ff0000"], in: library)

    try library.savePalette(from: project.orderedColors, named: "Picked", to: project)

    let palette = try #require(project.orderedPalettes.first)
    #expect(palette.kind == .custom)
    #expect(palette.orderedEntries.map(\.text) == ["rebeccapurple", "#ff0000"])
  }

  /// A key becomes a CSS custom property and a JavaScript object key, so two entries
  /// sharing one collapse into a single property and a color vanishes from the export with
  /// nothing to mark its absence. Derived palettes generate distinct keys and never meet
  /// this; a hand-picked set has no such guarantee.
  @Test("Duplicate names still produce distinct palette keys")
  func looseSetKeysAreUnique() throws {
    let library = try Self.makeLibrary()
    let project = try library.createProject(named: "Site")
    for css in ["#ff0000", "#00ff00", "#0000ff"] {
      let color = try CSSColorParser.parse(css).color
      try library.saveColor(ColorRecord(color, text: css), named: "blue", to: project)
    }

    try library.savePalette(from: project.orderedColors, named: "Picked", to: project)

    let palette = try #require(project.orderedPalettes.first)
    let keys = palette.paletteEntries.map(\.key)
    #expect(keys == ["blue", "blue-2", "blue-3"])
    #expect(Set(keys).count == keys.count)
  }

  /// An unnamed color falls back to its position, so a set of blank names still exports as
  /// distinct properties rather than one.
  @Test("Unnamed colors fall back to positional keys")
  func looseSetNamesFallBackToPositions() throws {
    let library = try Self.makeLibrary()
    let project = try library.createProject(named: "Site")
    for css in ["#ff0000", "#00ff00"] {
      let color = try CSSColorParser.parse(css).color
      try library.saveColor(ColorRecord(color, text: css), to: project)
    }

    try library.savePalette(from: project.orderedColors, named: "Picked", to: project)

    let palette = try #require(project.orderedPalettes.first)
    #expect(palette.paletteEntries.map(\.key) == ["1", "2"])
  }

  /// The colors are copied into the palette, not moved into it. `SavedColor` belongs to a
  /// project *or* a palette, so reassigning would empty the grid the user just selected in.
  @Test("Saving a loose set leaves the loose colors where they were")
  func looseSetLeavesTheColorsInPlace() throws {
    let library = try Self.makeLibrary()
    let project = try Self.projectWithColors(["#ff0000", "#00ff00"], in: library)

    try library.savePalette(from: project.orderedColors, named: "Picked", to: project)

    #expect(project.orderedColors.map(\.name) == ["#ff0000", "#00ff00"])
    #expect(project.orderedPalettes.first?.entries.count == 2)
  }

  // MARK: - Renaming what you saved (M32)

  /// The asymmetry the milestone exists to state: a loose color's name is a label, not
  /// syntax, so clearing it is legal — unlike a project or a palette, which both fall
  /// back to a title rather than store nothing.
  @Test("A saved color's name can be cleared, unlike a project's or a palette's")
  func colorRenameHasNoFallback() throws {
    let library = try Self.makeLibrary()
    let project = try library.createProject(named: "Site")
    let color = try CSSColorParser.parse("#ff0000").color
    let saved = try library.saveColor(ColorRecord(color, text: "#ff0000"), named: "Brand Red", to: project)

    try library.rename(saved, to: "   ")

    #expect(saved.name.isEmpty)
  }

  /// `rekey`'s empty answer is different from `rename`'s: a blank key is not "no
  /// label", it is "no property", so it falls back to the entry's position rather than
  /// to nothing — the same fallback `paletteKeys(for:)` already writes for an entry
  /// that arrives with no name of its own.
  @Test("An emptied palette-entry key falls back to its position, not to nothing")
  func rekeyFallsBackToPosition() throws {
    let library = try Self.makeLibrary()
    let project = try library.createProject(named: "Site")
    let entries = try [
      PaletteEntry(key: "500", color: CSSColorParser.parse("#ff0000").color),
      PaletteEntry(key: "600", color: CSSColorParser.parse("#00ff00").color),
    ]
    try library.savePalette(entries, named: "Brand", kind: .ramp, to: project)
    let palette = try #require(project.orderedPalettes.first)
    let second = palette.orderedEntries[1]

    try library.rekey(second, to: "   ")

    #expect(second.name == "2")
  }

  /// The collision worth a mutation, per the milestone: two entries renamed onto keys
  /// that only *look* distinct do not collapse into one property. `brand.500` and
  /// `brand-500` are two legal, different-looking names that
  /// `ExportOptions.cssIdentifier(_:fallback:)` maps onto the identical identifier —
  /// the same hazard `DesignTokenImport.keyed(_:)` guards against on the way in.
  @Test("Two palette-entry keys that sanitize alike do not collapse into one")
  func rekeyDedupesAgainstSanitizedSiblings() throws {
    let library = try Self.makeLibrary()
    let project = try library.createProject(named: "Site")
    let entries = try [
      PaletteEntry(key: "brand.500", color: CSSColorParser.parse("#ff0000").color),
      PaletteEntry(key: "600", color: CSSColorParser.parse("#00ff00").color),
    ]
    try library.savePalette(entries, named: "Brand", kind: .ramp, to: project)
    let palette = try #require(project.orderedPalettes.first)
    let second = palette.orderedEntries[1]

    try library.rekey(second, to: "brand-500")

    let keys = palette.paletteEntries.map(\.key)
    #expect(second.name == "brand-500-2")
    #expect(Set(keys).count == keys.count, "A color must not silently vanish behind a colliding key:\n\(keys)")
  }

  /// The round trip the field's live preview promises: a rekeyed entry is not merely
  /// renamed in the store, it exports under the new name.
  @Test("A rekeyed entry exports under its new key")
  func rekeyedEntryExportsUnderNewKey() throws {
    let library = try Self.makeLibrary()
    let project = try library.createProject(named: "Site")
    let entries = try [PaletteEntry(key: "500", color: CSSColorParser.parse("#ff0000").color)]
    try library.savePalette(entries, named: "Brand", kind: .ramp, to: project)
    let palette = try #require(project.orderedPalettes.first)
    let entry = try #require(palette.orderedEntries.first)

    try library.rekey(entry, to: "primary")

    var options = ExportOptions.default
    options.shape = .customProperties
    options.name = palette.name
    let rendered = options.render(palette.paletteEntries)

    #expect(rendered.contains("--Brand-primary"))
    #expect(!rendered.contains("--Brand-500"))
  }

  // MARK: Private

  /// A store on disk, for the one test that has to leave memory.
  /// Three shades out of numeric order in the file, so the palette's order is a claim
  /// about the importer rather than about how the JSON happened to be typed.
  private static let rampTokens = #"""
  { "brand": { "$type": "color",
    "900": { "$value": { "colorSpace": "srgb", "components": [0.05, 0.1, 0.4] } },
    "50":  { "$value": { "colorSpace": "srgb", "components": [0.9, 0.94, 1] } },
    "100": { "$value": { "colorSpace": "srgb", "components": [0.8, 0.88, 1] } } } }
  """#

  /// A project holding one loose color per CSS string, named after it, in order.
  private static func projectWithColors(
    _ css: [String],
    in library: ProjectLibrary,
  ) throws -> Project {
    let project = try library.createProject(named: "Site")
    for text in css {
      let color = try CSSColorParser.parse(text).color
      try library.saveColor(ColorRecord(color, text: text), named: text, to: project)
    }
    return project
  }

  private static func makeContainer(at url: URL) throws -> ModelContainer {
    try ModelContainer(
      for: PersistenceStack.schema,
      configurations: ModelConfiguration(schema: PersistenceStack.schema, url: url),
    )
  }

  /// A container that exists only for the duration of one test. Nothing here may touch
  /// the store the app itself writes to.
  private static func makeContainer() throws -> ModelContainer {
    try ModelContainer(
      for: PersistenceStack.schema,
      configurations: ModelConfiguration(
        schema: PersistenceStack.schema,
        isStoredInMemoryOnly: true,
      ),
    )
  }

  private static func makeLibrary() throws -> ProjectLibrary {
    try ProjectLibrary(ModelContext(makeContainer()))
  }
}
