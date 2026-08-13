//
//  Preferences.swift
//  ColorKit
//

import Foundation

/// The deliberate persisted subset of ``ColorStore``.
///
/// Everything here is a preference about *how you like to work*, the same category
/// ``ColorStore`` already documents `pickerMode`, `harmony` and the rest under. What is
/// missing is exactly as deliberate as what is here: `inputText`, `backgroundText`,
/// `exportOptions.name`, `recents`, `selectedProjectID` and `stagedPalette` are session
/// state, not preferences, and a toolkit that reopens on last week's half-typed color
/// and a stranger's saved project is worse than one that reopens clean.
///
/// **Explicit `CodingKeys`, not synthesis.** `Codable` derives its keys from property
/// names by default, so a future rename — `showsRecents` to `showRecents`, say — would
/// compile cleanly and then silently stop decoding that field, exactly the hazard
/// `.swiftformat`'s empty `--acronyms` exists to prevent for `Codable` structs
/// elsewhere. Dropping an entry here is required to fail ``PreferencesTests``'
/// round-trip test — that is the check this exists to make possible.
nonisolated struct Preferences: Codable, Equatable, Sendable {
  // MARK: Internal

  var formatOptions = CSSFormatOptions()
  var webFriendly = false
  var showsRecents = true
  var recentLimit = 12
  /// Whether M36's sidebar shows full rows or the icon-only rail. A preference like
  /// ``showsRecents``, not session state — the whole reason it collapses at all is to
  /// stay out of the way once you already know where the tools are, and losing that
  /// choice every launch would defeat the point.
  var sidebarCollapsed = false
  var pickerMode: PickerMode = .hsv
  var cvdDeficiency: ColorVisionDeficiency = .deuteranomaly
  var exportShape: ExportShape = .customProperties
  var exportTemplate: ExportTemplate = .color
  var exportFormat: CSSOutputFormat = .oklch
  /// The system-wide sampling chord (M27). Decodes to whatever was saved with no
  /// validation of its own — `GlobalShortcut`'s `Codable` synthesis has no notion of
  /// ``GlobalShortcut/isEligible`` — so a hand-edited or corrupted file can decode a
  /// chord that would swallow ordinary typing. `ColorStore.preferences`'s setter is
  /// where that gets caught, the same boundary that already clamps a negative
  /// `recentLimit`.
  var globalShortcut: GlobalShortcut = .sampleColor

  // MARK: Private

  private enum CodingKeys: String, CodingKey {
    case formatOptions
    case webFriendly
    case showsRecents
    case recentLimit
    case sidebarCollapsed
    case pickerMode
    case cvdDeficiency
    case exportShape
    case exportTemplate
    case exportFormat
    case globalShortcut
  }
}

/// Where ``Preferences`` lives between launches: one JSON blob in `UserDefaults`.
///
/// One key rather than one default per field, for the same reason `Preferences` is one
/// struct — a partial write cannot leave the stored preferences in a state no version of
/// the app ever produced.
///
/// `nonisolated`, like ``Preferences`` itself: nothing here touches AppKit, and pinning
/// it to the main actor would force every test that reads or writes preferences onto
/// one too, for no reason `UserDefaults` needs.
nonisolated enum PreferenceStore {
  /// Passed by `XCUIApplication` in the UI tests to get preferences that evaporate,
  /// exactly parallel to ``PersistenceStack/inMemoryLaunchArgument``.
  ///
  /// Without it, XCUITest launches the shipping app and inherits whatever the developer
  /// running it last set — legacy comma syntax, web-friendly mode, a raised precision —
  /// and a test's result would depend on who ran it. No leading hyphen, for the same
  /// reason `inMemoryLaunchArgument` has none: a bare argument is what this needs to be,
  /// and turning it into an `NSUserDefaults` key/value pair is a different bug.
  static let ephemeralLaunchArgument = "UITestEphemeralPreferences"

  /// Not `private` — ``PreferencesTests`` needs it to plant a corrupt value directly,
  /// which is the only way to exercise the "decoding garbage yields defaults" path
  /// without going through ``save(_:to:)`` first.
  static let defaultsKey = "me.parkersprouse.colorkit.preferences"

  /// Whether this process was launched by a UI test that asked for a clean slate.
  static var isEphemeral: Bool {
    ProcessInfo.processInfo.arguments.contains(ephemeralLaunchArgument)
  }

  /// Reads whatever was last saved, or the type's defaults if nothing was, the process
  /// asked for a clean slate, or the stored blob no longer decodes.
  ///
  /// A decode failure returns defaults silently rather than surfacing an error: a
  /// corrupt preference file is not worth a banner the way a corrupt project store is —
  /// nothing here is data anyone authored, only settings that reset to a sane default.
  static func load(from defaults: UserDefaults = .standard) -> Preferences {
    guard !isEphemeral, let data = defaults.data(forKey: defaultsKey) else {
      return Preferences()
    }
    return (try? JSONDecoder().decode(Preferences.self, from: data)) ?? Preferences()
  }

  /// Writes the given preferences, unless this process asked for a clean slate — in
  /// which case a UI test's changes must never reach the developer's real defaults.
  static func save(_ preferences: Preferences, to defaults: UserDefaults = .standard) {
    guard !isEphemeral else { return }
    guard let data = try? JSONEncoder().encode(preferences) else { return }
    defaults.set(data, forKey: defaultsKey)
  }
}
