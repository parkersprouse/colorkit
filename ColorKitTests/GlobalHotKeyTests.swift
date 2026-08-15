//
//  GlobalHotKeyTests.swift
//  ColorKitTests
//

import Carbon.HIToolbox
@testable import ColorKit
import Foundation
import Testing

/// The Carbon layer is deprecated API reached through a C callback, which is exactly
/// the combination that stops compiling one OS release without anyone noticing. These
/// tests exist to make that a red test rather than a feature that quietly does
/// nothing.
///
/// - Note: The firing path — key press → C callback → `@MainActor` → action — cannot
///   be tested here. Synthesizing a system-wide key event needs Accessibility
///   permission that a test runner has no business holding, so that half is verified
///   by pressing the key.
@MainActor
@Suite("Global hot key")
struct GlobalHotKeyTests {
  // MARK: Internal

  /// Proves both halves of the lifecycle: the system still accepts a Carbon hot key,
  /// and releasing one really does hand the chord back. The second registration
  /// would fail with `eventHotKeyExistsErr` if `unregisterAll` were a no-op.
  ///
  /// - Note: This clears the host app's own registration as collateral, since
  ///   `unregisterAll` is all or nothing. Harmless — the host exists only for the
  ///   duration of the run — but it is why no test here asserts on the app's state.
  @Test("A hot key can be claimed, released, and claimed again")
  func registrationLifecycle() {
    let center = GlobalHotKeyCenter.shared
    center.unregisterAll()
    defer { center.unregisterAll() }

    #expect(center.register(probe) {}, "the system refused a Carbon hot key")
    center.unregisterAll()
    #expect(center.register(probe) {}, "unregistering did not release the chord")
  }

  /// Modifier order is not cosmetic — ⌘⌥⌃C would read as a different shortcut to
  /// anyone who knows the convention.
  @Test("The shortcut prints modifiers in the order menus use")
  func displayStringFollowsConvention() {
    #expect(GlobalShortcut.sampleColor.displayString == "⌃ ⌥ ⌘ C")

    let everything = GlobalShortcut(
      keyCode: UInt32(kVK_Space),
      modifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey),
      keyLabel: "Space",
    )
    #expect(everything.displayString == "⌃ ⌥ ⇧ ⌘ Space")
  }

  @Test("A shortcut with no modifiers prints as just its key")
  func bareKeyPrintsAlone() {
    let bare = GlobalShortcut(keyCode: UInt32(kVK_F13), modifiers: 0, keyLabel: "F13")
    #expect(bare.displayString == "F13")
  }

  @Test("Survives an encode/decode round trip")
  func codableRoundTrips() throws {
    let data = try JSONEncoder().encode(GlobalShortcut.sampleColor)
    let decoded = try JSONDecoder().decode(GlobalShortcut.self, from: data)

    #expect(decoded == GlobalShortcut.sampleColor)
  }

  // MARK: - Eligibility

  /// The predicate that stands between a hand-edited preferences file and a global hot
  /// key that swallows ordinary typing — see ``GlobalShortcut/isEligible``'s own doc.
  /// Each of ⌃, ⌥, ⌘ alone is enough; ⇧ alone is the one modifier that is deliberately
  /// not, because ⇧A still types a capital A.
  @Test(
    "Any of ⌃⌥⌘ alone makes a chord eligible; ⇧ alone does not",
    arguments: [
      (UInt32(controlKey), true),
      (UInt32(optionKey), true),
      (UInt32(cmdKey), true),
      (UInt32(shiftKey), false),
      (UInt32(0), false),
    ],
  )
  func modifierEligibility(modifiers: UInt32, expected: Bool) {
    let shortcut = GlobalShortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: modifiers, keyLabel: "A")
    #expect(shortcut.isEligible == expected)
  }

  @Test("A bare function key is eligible with no modifier at all")
  func bareFunctionKeyIsEligible() {
    let bare = GlobalShortcut(keyCode: UInt32(kVK_F13), modifiers: 0, keyLabel: "F13")
    #expect(bare.isEligible)
  }

  @Test("⌃⌥⌘ combined with ⇧ is still eligible — ⇧ merely riding along is not the same as ⇧ alone")
  func shiftAlongsideARealModifierIsEligible() {
    let shortcut = GlobalShortcut(
      keyCode: UInt32(kVK_ANSI_A),
      modifiers: UInt32(cmdKey | shiftKey),
      keyLabel: "A",
    )
    #expect(shortcut.isEligible)
  }

  // MARK: Private

  /// Deliberately not ``GlobalShortcut/sampleColor``: the unit tests are hosted in
  /// the app, which claims that chord as soon as a scene appears, and racing it
  /// would make this flaky. Four modifiers and Q is a combination nothing owns.
  private var probe: GlobalShortcut {
    GlobalShortcut(
      keyCode: UInt32(kVK_ANSI_Q),
      modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey),
      keyLabel: "Q",
    )
  }
}
