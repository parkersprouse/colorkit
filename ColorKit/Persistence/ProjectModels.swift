//
//  ProjectModels.swift
//  ColorKit
//

import Foundation
import SwiftData

/// Where a saved palette came from.
///
/// Stored as a raw string rather than an integer so the store stays readable, and kept
/// alongside the palette rather than re-derived, because provenance is a fact about the
/// moment it was saved. A ramp saved from an eleven-stop ramp is a ramp forever, even
/// after an entry is deleted and the count no longer looks like one.
///
/// ``custom`` is the case that makes the others honest: it is what a palette becomes
/// when it no longer matches how it was generated, and what a hand-assembled one starts
/// as.
nonisolated enum PaletteKind: String, CaseIterable, Sendable, Identifiable {
  case harmony
  case ramp
  case recents
  /// Read out of a W3C design token file. Provenance worth keeping for the reason the
  /// others are kept: an imported palette's keys are somebody else's names, and knowing
  /// they came from a file is what explains why they look nothing like a ramp's.
  case imported
  case custom

  // MARK: Internal

  var id: String {
    rawValue
  }

  var title: String {
    switch self {
    case .harmony: "Harmony"
    case .ramp: "Ramp"
    case .recents: "Recents"
    case .imported: "Imported"
    case .custom: "Custom"
    }
  }
}

/// A named collection of colors and palettes.
///
/// The top of the stored hierarchy, and the only thing the panel lists directly.
///
/// - Note: ``uuid`` exists alongside SwiftData's own `PersistentIdentifier` so that
///   ``ColorStore`` can remember which project you were in without importing SwiftData.
///   That is the whole reason: the store holds app state and stays free of the
///   persistence layer, exactly as ColorCore stays free of both.
@Model
final class Project {
  // MARK: Lifecycle

  init(name: String) {
    uuid = UUID()
    self.name = name
    let now = Date.now
    createdAt = now
    modifiedAt = now
    colors = []
    palettes = []
  }

  // MARK: Internal

  @Attribute(.unique) var uuid: UUID
  var name: String
  var createdAt: Date
  var modifiedAt: Date

  /// Loose colors — ones saved on their own rather than as part of a set.
  ///
  /// The cascade is what stops a deleted project leaving its colors behind as rows
  /// nothing references. The inverse is declared explicitly rather than inferred:
  /// ``SavedColor`` is the destination of *two* to-many relationships (this and
  /// ``Palette/entries``), and SwiftData cannot guess which one a bare `[SavedColor]`
  /// belongs to — it throws at container initialization, which is why the first thing
  /// ``ProjectStoreTests`` asserts is that the container builds at all.
  @Relationship(deleteRule: .cascade, inverse: \SavedColor.project)
  var colors: [SavedColor]

  @Relationship(deleteRule: .cascade, inverse: \Palette.project)
  var palettes: [Palette]

  /// ``colors`` in the order they were added, newest last.
  ///
  /// Sorted on read rather than trusted, for the reason ``SavedColor/sortIndex`` gives.
  var orderedColors: [SavedColor] {
    colors.sorted { $0.sortIndex < $1.sortIndex }
  }

  var orderedPalettes: [Palette] {
    palettes.sorted { $0.sortIndex < $1.sortIndex }
  }

  /// Records an edit. Called by every mutation the panel performs, so "modified" means
  /// what it says rather than "created, and then never touched again".
  func touch() {
    modifiedAt = .now
  }
}

/// One stored color: the flattened ``ColorRecord`` fields, plus what it is called.
///
/// **``name`` doubles as the export key.** A palette entry's key is its position in the
/// family — `500`, `triad-2` — and that is also the only sensible thing to *call* a ramp
/// stop, so a second field would be two names for one string and an invitation for them
/// to disagree. A loose color's name is a label and its key is unused.
@Model
final class SavedColor {
  // MARK: Lifecycle

  init(record: ColorRecord, name: String = "", notes: String = "", sortIndex: Int = 0) {
    spaceID = record.spaceID
    c0 = record.c0
    c1 = record.c1
    c2 = record.c2
    alpha = record.alpha
    missingMask = record.missingMask
    text = record.text
    self.name = name
    self.notes = notes
    self.sortIndex = sortIndex
    createdAt = .now
  }

  // MARK: Internal

  var name: String
  var notes: String
  var createdAt: Date

  /// Position within its project or palette.
  ///
  /// **A SwiftData to-many relationship is unordered, and not merely in theory.** Read
  /// the entries straight off `palette.entries` and an eleven-stop ramp comes back
  /// `600, 400, 100, 200, 900, 300, 800, 950, 500, 50, 700` — measured, in the same
  /// context, immediately after the save that inserted them in order. A ramp's order
  /// *is* its meaning: shuffled, every one of Tailwind's eleven keys names the wrong
  /// color, and the export still looks perfectly well-formed. So order is written down
  /// and sorted on read, never inferred from the array.
  var sortIndex: Int

  // The `ColorRecord` fields, flat so they can be queried. See that type.
  var spaceID: String
  var c0: Double
  var c1: Double
  var c2: Double
  var alpha: Double
  var missingMask: Int
  var text: String

  var project: Project?
  var palette: Palette?

  /// The stored fields as the value type that owns their meaning.
  ///
  /// Every read and write of the color goes through here, so the flattening exists in
  /// exactly one place and the panel never touches `c0` by hand.
  var record: ColorRecord {
    get {
      ColorRecord(
        spaceID: spaceID,
        c0: c0,
        c1: c1,
        c2: c2,
        alpha: alpha,
        missingMask: missingMask,
        text: text,
      )
    }
    set {
      spaceID = newValue.spaceID
      c0 = newValue.c0
      c1 = newValue.c1
      c2 = newValue.c2
      alpha = newValue.alpha
      missingMask = newValue.missingMask
      text = newValue.text
    }
  }

  /// The color itself, or `nil` if the stored space is unknown to this build.
  var colorValue: ColorValue? {
    record.colorValue
  }

  /// This color as the export layer sees it. `nil` for a row that cannot be read, so a
  /// palette exports what it has rather than substituting something for what it lost.
  var paletteEntry: PaletteEntry? {
    colorValue.map { PaletteEntry(key: name, color: $0) }
  }
}

/// A saved set of colors, kept together because they are used together.
///
/// Distinct from a project's loose ``Project/colors`` in exactly the way ``ShadeRamp``
/// is distinct from a bag of colors: the order is load-bearing and the members mean
/// something as a group. That is also why this is what the export panel consumes.
@Model
final class Palette {
  // MARK: Lifecycle

  init(name: String, kind: PaletteKind = .custom, sortIndex: Int = 0) {
    self.name = name
    kindID = kind.rawValue
    self.sortIndex = sortIndex
    createdAt = .now
    entries = []
  }

  // MARK: Internal

  var name: String
  var createdAt: Date
  var sortIndex: Int

  /// ``PaletteKind``'s raw value. Stored as a string rather than the enum so that a
  /// value written by a later version — a kind this build has never heard of — reads
  /// back as ``PaletteKind/custom`` instead of failing to decode the row.
  var kindID: String

  @Relationship(deleteRule: .cascade, inverse: \SavedColor.palette)
  var entries: [SavedColor]

  var project: Project?

  var kind: PaletteKind {
    get { PaletteKind(rawValue: kindID) ?? .custom }
    set { kindID = newValue.rawValue }
  }

  /// The entries in the order they were saved. See ``SavedColor/sortIndex``.
  var orderedEntries: [SavedColor] {
    entries.sorted { $0.sortIndex < $1.sortIndex }
  }

  /// The palette as the export layer consumes it: plain values, no SwiftData.
  ///
  /// This is the boundary. Everything downstream of it — ``ColorStore/stagedPalette``,
  /// ``ExportOptions/render(_:formatting:)`` — deals in `PaletteEntry` and has no idea a
  /// database exists, which is what keeps the export tests free of a `ModelContainer`.
  var paletteEntries: [PaletteEntry] {
    orderedEntries.compactMap(\.paletteEntry)
  }
}
