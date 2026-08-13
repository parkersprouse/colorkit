//
//  PreferencesTests.swift
//  ColorKitTests
//

import Carbon.HIToolbox
@testable import ColorKit
import Foundation
import Observation
import Testing

/// - Note: Every test here that touches ``PreferenceStore`` injects its own
///   `UserDefaults(suiteName:)`, never `.standard` — a test writing to the real
///   defaults would pollute whatever the developer running it has actually set, exactly
///   the hazard ``PreferenceStore/ephemeralLaunchArgument`` exists to prevent for
///   XCUITest. Each suite is removed in a `defer` so runs do not accumulate state.
@Suite("Preferences")
struct PreferencesTests {
  // MARK: Internal

  @Test("Every field survives an encode/decode round trip")
  func roundTrips() throws {
    let data = try JSONEncoder().encode(Self.nonDefault)
    let decoded = try JSONDecoder().decode(Preferences.self, from: data)

    #expect(decoded == Self.nonDefault)
    // And the default itself, so a field that happens to decode to *some* value
    // rather than the one encoded — the failure mode a dropped `CodingKeys` entry
    // produces — cannot pass by coincidence against only one fixture.
    #expect(decoded != Preferences())
  }

  @Test("Decoding garbage yields defaults, not a crash")
  func corruptStoreYieldsDefaults() throws {
    let defaults = try #require(UserDefaults(suiteName: "PreferencesTests.garbage"))
    defer { defaults.removePersistentDomain(forName: "PreferencesTests.garbage") }

    defaults.set(Data("not json".utf8), forKey: PreferenceStore.defaultsKey)

    #expect(PreferenceStore.load(from: defaults) == Preferences())
  }

  @Test("Nothing stored yields defaults")
  func emptyStoreYieldsDefaults() throws {
    let defaults = try #require(UserDefaults(suiteName: "PreferencesTests.empty"))
    defer { defaults.removePersistentDomain(forName: "PreferencesTests.empty") }

    #expect(PreferenceStore.load(from: defaults) == Preferences())
  }

  @Test("What is saved is what the next load reads back")
  func saveThenLoadRoundTrips() throws {
    let defaults = try #require(UserDefaults(suiteName: "PreferencesTests.roundtrip"))
    defer { defaults.removePersistentDomain(forName: "PreferencesTests.roundtrip") }

    PreferenceStore.save(Self.nonDefault, to: defaults)

    #expect(PreferenceStore.load(from: defaults) == Self.nonDefault)
  }

  /// ``nonDefault`` deliberately pairs `webFriendly: true` with a restricted
  /// `.color(.displayP3)` export format — a legal *serialized* combination (a hand-edited
  /// file, or one an app version before the M34 follow-up saved) that the store now
  /// **reconciles on load**: the format is reassigned to a web-friendly one and the
  /// original stashed, so a later toggle-off restores it. Every other field applies
  /// verbatim. This is the persistence-layer counterpart to
  /// ``WebFriendlyExportStoreTests/assigningPreferencesReconcilesARestrictedShape()``,
  /// which exercises the same setter fix against a restricted *shape*.
  @MainActor
  @Test("ColorStore applies a loaded Preferences, reconciling a restricted export choice")
  func colorStoreAppliesLoadedPreferences() {
    let store = ColorStore()

    store.preferences = Self.nonDefault

    // Whole-struct equality against the *reconciled* expectation — the on-load reassign of
    // the restricted format is the only field that differs from `nonDefault`. Asserted as
    // a struct (not only field-by-field) so a setter that forgets to assign a field is
    // still caught: a forgotten field keeps its default and the individual `#expect`s can
    // coincide with it, but the struct comparison cannot.
    var expected = Self.nonDefault
    expected.exportFormat = .oklch // reassigned from the restricted .color(.displayP3)
    #expect(store.preferences == expected)

    // And the specific reconcile facts the struct equality does not spell out: the
    // reassigned format is web-friendly, the original is stashed, the (already safe) shape
    // is not.
    #expect(CSSOutputFormat.webFriendly.contains(store.exportOptions.format))
    #expect(store.restrictedExportFormat == .color(.displayP3))
    #expect(store.restrictedExportShape == nil)

    // Turning the mode off (without meanwhile using the choice) brings displayP3 back.
    store.webFriendly = false
    #expect(store.exportOptions.format == .color(.displayP3))
  }

  /// The M27 counterpart to ``negativeRecentLimitIsClamped`` above: a chord with no
  /// modifier that could still type a character — the shape a hand-edited preferences
  /// file can carry, since `GlobalShortcut`'s `Codable` synthesis has no notion of
  /// ``GlobalShortcut/isEligible`` — must not reach `GlobalHotKeyCenter` at all. Falls
  /// back to ``GlobalShortcut/sampleColor`` rather than merely refusing, the same
  /// "still works, just with the default" recovery every other clamp in this file
  /// makes.
  @MainActor
  @Test("An ineligible globalShortcut is clamped to the default rather than registered as-is")
  func ineligibleGlobalShortcutIsClamped() {
    let store = ColorStore()
    var corrupt = Preferences()
    corrupt.globalShortcut = GlobalShortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: 0, keyLabel: "A")

    store.preferences = corrupt

    #expect(store.globalShortcut == .sampleColor)
  }

  /// A regression test for a real crash, not a hypothetical one: `remember()` computes
  /// `recents.removeLast(recents.count - recentLimit)`, and a negative `recentLimit`
  /// makes that argument exceed the array's size the first time a color is
  /// remembered. `Preferences.recentLimit` decodes successfully for any `Int` — the
  /// Settings panel's Stepper is the only thing that keeps it in `1...50` in the
  /// ordinary path, and a hand-edited or corrupted preferences file bypasses it
  /// entirely.
  @MainActor
  @Test("A corrupt negative recentLimit is clamped rather than crashing remember()")
  func negativeRecentLimitIsClamped() {
    let store = ColorStore(initialInput: "red")
    var corrupt = Preferences()
    corrupt.recentLimit = -5

    store.preferences = corrupt
    store.remember()

    #expect(store.recentLimit >= 1)
    #expect(store.recents.count == 1)
  }

  @MainActor
  @Test("Assigning preferences leaves session state untouched")
  func preferencesDoNotTouchSessionState() {
    let store = ColorStore(initialInput: "rebeccapurple")
    let inputBefore = store.inputText
    store.exportOptions.name = "brand"

    store.preferences = Self.nonDefault

    // `exportOptions.name` is session state, deliberately absent from `Preferences` —
    // assigning `preferences` must not reset it to `ExportOptions.defaultName` as a
    // side effect of touching the rest of `exportOptions`.
    #expect(store.exportOptions.name == "brand")
    #expect(store.inputText == inputBefore)
  }

  /// Pins the claim `ColorStore.preferences`'s doc comment makes: reading the computed
  /// getter registers `@Observable` access to every field it touches, which is what
  /// lets `ColorKitApp`'s `.onChange(of: store.preferences)` fire on *any*
  /// persisted change without listing nine properties itself. That claim is exactly
  /// the "compiles perfectly and does nothing" shape this codebase has been burned by
  /// before, so it is checked directly rather than left as reasoning in a comment.
  ///
  /// Three mutation sites, not one: a field directly on the store, one nested inside
  /// `formatOptions`, and one nested inside `exportOptions` — the two nested cases are
  /// what a getter that only tracked its own top-level properties would miss.
  @MainActor
  @Test("Mutating any persisted field invalidates a read of preferences")
  func preferencesObservesEveryPersistedField() {
    let mutations: [(String, (ColorStore) -> Void)] = [
      ("webFriendly", { $0.webFriendly = true }),
      ("formatOptions.legacy", { $0.formatOptions.legacy = true }),
      ("exportOptions.shape", { $0.exportOptions.shape = .json }),
      // `recentLimit` gained a `didSet` in M23 (to trim `recents` immediately on a
      // lowered limit) — property observers on an `@Observable` stored property are
      // exactly the kind of thing that can compile clean and silently stop being
      // observed, so this is the same "does it actually fire" check the other three
      // fields already get.
      ("recentLimit", { $0.recentLimit = 3 }),
      // `globalShortcut` (M27) is a computed property over a private backing field,
      // not a stored `var` — a different shape than `recentLimit`'s `didSet`, but the
      // same "does @Observable actually see through this" question, and the same
      // reason it needs its own check rather than trusting `recentLimit`'s to stand in
      // for it.
      ("globalShortcut", { $0.globalShortcut = .init(keyCode: 1, modifiers: UInt32(cmdKey), keyLabel: "S") }),
    ]

    for (name, mutate) in mutations {
      let store = ColorStore()
      // `onChange` is `@Sendable`, and this is a same-thread, synchronous test — the
      // mutation happens right after registering the observation and nothing else
      // touches `fired` — so the unchecked opt-out is safe here.
      nonisolated(unsafe) var fired = false
      withObservationTracking {
        _ = store.preferences
      } onChange: {
        fired = true
      }

      mutate(store)

      #expect(fired, "reading `preferences` did not observe a change to \(name)")
    }
  }

  // MARK: Private

  /// Every field changed from its default, so a mistakenly-omitted `CodingKeys` entry
  /// — or one that maps the wrong property — has something to disagree about. `.color`
  /// is deliberately not the chosen ``CSSOutputFormat``: that is the default, and
  /// `.color(.displayP3)` is what exercises `CSSOutputFormat`'s associated-value
  /// encoding path rather than one of its plain cases.
  private static let nonDefault = Preferences(
    formatOptions: CSSFormatOptions(
      precision: 6,
      legacy: true,
      rgbAsPercentage: true,
      collapseHex: true,
      uppercaseHex: true,
      alpha: .always,
      gamut: .preserve,
      noneForPowerlessComponents: true,
    ),
    webFriendly: true,
    showsRecents: false,
    recentLimit: 25,
    sidebarCollapsed: true,
    pickerMode: .oklch,
    cvdDeficiency: .protanomaly,
    exportShape: .tailwindConfig,
    exportTemplate: .border,
    exportFormat: .color(.displayP3),
    globalShortcut: GlobalShortcut(
      keyCode: UInt32(kVK_ANSI_D),
      modifiers: UInt32(cmdKey | shiftKey),
      keyLabel: "D",
    ),
  )
}
