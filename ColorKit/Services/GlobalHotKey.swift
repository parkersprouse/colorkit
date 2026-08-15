//
//  GlobalHotKey.swift
//  ColorKit
//

import AppKit
import Carbon.HIToolbox

/// A key combination the system delivers even when another app is frontmost.
///
/// Carbon's vocabulary, not AppKit's: virtual key codes and `cmdKey`-style masks,
/// which are what ``GlobalHotKeyCenter`` has to hand to `RegisterEventHotKey`.
/// Named `GlobalShortcut` rather than the obvious `KeyboardShortcut` because SwiftUI
/// already owns that name and means something different by it.
nonisolated struct GlobalShortcut: Sendable, Hashable, Codable {
  // MARK: Internal

  /// Pick a color from anywhere on screen.
  ///
  /// Three modifiers on purpose. ⇧⌘C is Digital Color Meter's own copy shortcut and
  /// is claimed by plenty of editors; ⌥⌘C is Finder's "Copy as Pathname". A global
  /// hot key wins over the frontmost app's, so a collision here would silently break
  /// something the user already relies on — a worse outcome than an awkward chord.
  ///
  /// Also the fallback ``Preferences``' ``globalShortcut`` field decodes to when the
  /// stored value fails ``isEligible`` — see that property's doc for why a *default*
  /// this safe is exactly what a corrupt preferences file needs to land on.
  static let sampleColor = GlobalShortcut(
    keyCode: UInt32(kVK_ANSI_C),
    modifiers: UInt32(controlKey | optionKey | cmdKey),
    keyLabel: "C",
  )

  /// A virtual key code — `kVK_ANSI_C`, not the character `"c"`. Key codes describe
  /// a physical key position, so this stays the same key on a Dvorak layout.
  let keyCode: UInt32
  /// A Carbon modifier mask (`cmdKey`, `optionKey`, …), unrelated in value to
  /// `NSEvent.ModifierFlags`.
  let modifiers: UInt32
  /// How the key prints. A key code cannot be turned back into a character without
  /// consulting the active keyboard layout, so the label is carried alongside it.
  let keyLabel: String

  /// Whether this chord is safe to claim system-wide.
  ///
  /// A chord that carries none of ⌃⌥⌘ can still type a character — ⇧ alone does not
  /// save it, since ⇧A still types a capital A — and registering one would swallow
  /// every keystroke of that character in every app on the machine. A bare function
  /// key is the one exception, since function keys are not text.
  ///
  /// This is what stands between a hand-edited or corrupted preferences file (a
  /// `"modifiers": 0` sitting next to any letter's key code decodes just fine — see
  /// ``GlobalShortcut``'s own `Codable` synthesis, which has no notion of this rule)
  /// and a global hot key that breaks typing app-wide. Two call sites share it rather
  /// than each inventing its own bar: ``ColorStore/preferences``'s setter falls back to
  /// ``sampleColor`` when a loaded value fails it, and
  /// ``ColorStore/updateGlobalShortcut(_:)`` refuses to even attempt registering a
  /// chord the Settings recorder captured that fails it.
  var isEligible: Bool {
    let requiresNoText = UInt32(controlKey | optionKey | cmdKey)
    if modifiers & requiresNoText != 0 {
      return true
    }
    return Self.functionKeyCodes.contains(keyCode)
  }

  /// The shortcut as a menu would show it, in the order Apple's HIG specifies.
  var displayString: String {
    var symbols = ""
    if modifiers & UInt32(controlKey) != 0 {
      symbols += "⌃ "
    }
    if modifiers & UInt32(optionKey) != 0 {
      symbols += "⌥ "
    }
    if modifiers & UInt32(shiftKey) != 0 {
      symbols += "⇧ "
    }
    if modifiers & UInt32(cmdKey) != 0 {
      symbols += "⌘ "
    }
    return symbols + keyLabel
  }

  // MARK: Private

  /// F1 through F20 — the full range Carbon names, and the only key codes
  /// ``isEligible`` accepts with no modifier at all.
  private static let functionKeyCodes: Set<UInt32> = [
    UInt32(kVK_F1), UInt32(kVK_F2), UInt32(kVK_F3), UInt32(kVK_F4), UInt32(kVK_F5),
    UInt32(kVK_F6), UInt32(kVK_F7), UInt32(kVK_F8), UInt32(kVK_F9), UInt32(kVK_F10),
    UInt32(kVK_F11), UInt32(kVK_F12), UInt32(kVK_F13), UInt32(kVK_F14), UInt32(kVK_F15),
    UInt32(kVK_F16), UInt32(kVK_F17), UInt32(kVK_F18), UInt32(kVK_F19), UInt32(kVK_F20),
  ]
}

/// Owns the app's system-wide hot keys.
///
/// Uses Carbon's `RegisterEventHotKey` rather than
/// `NSEvent.addGlobalMonitorForEvents`, which would work identically *and* demand the
/// user grant Input Monitoring in System Settings. Carbon needs no permission and no
/// prompt, even sandboxed. It has been deprecated for over a decade and remains the
/// only way to do this; the deprecation is why it is quarantined in one file.
@MainActor
final class GlobalHotKeyCenter {
  // MARK: Lifecycle

  private init() {}

  // MARK: Internal

  static let shared = GlobalHotKeyCenter()

  /// `'CLRT'`. Carbon tags every hot key with a four-character app signature, so the
  /// handler can tell ours apart from any other registered on the same target.
  nonisolated static let signature: OSType = 0x434C_5254

  /// Claims `shortcut` system-wide, reporting whether the system accepted it.
  ///
  /// Returns `false` rather than throwing because there is nothing to recover from:
  /// the app works fine without a hot key, and the caller's only real option is to
  /// stop advertising one. Note that macOS does **not** reliably report a collision
  /// with another application, so `true` means "registered", not "unique".
  @discardableResult
  func register(_ shortcut: GlobalShortcut, action: @escaping () -> Void) -> Bool {
    guard installHandlerIfNeeded() else { return false }

    let id = nextID
    var ref: EventHotKeyRef?
    let status = RegisterEventHotKey(
      shortcut.keyCode,
      shortcut.modifiers,
      EventHotKeyID(signature: Self.signature, id: id),
      GetApplicationEventTarget(),
      0,
      &ref,
    )
    guard status == noErr, let ref else { return false }

    nextID += 1
    registrations[id] = ref
    actions[id] = action
    return true
  }

  /// Releases every hot key. Registrations outlive the objects that made them, so
  /// tests must call this or they leak a system-wide chord for the session.
  func unregisterAll() {
    for ref in registrations.values {
      UnregisterEventHotKey(ref)
    }
    registrations.removeAll()
    actions.removeAll()
  }

  // MARK: Fileprivate

  fileprivate func fire(_ id: UInt32) {
    actions[id]?()
  }

  // MARK: Private

  private var actions: [UInt32: () -> Void] = [:]
  private var registrations: [UInt32: EventHotKeyRef] = [:]
  private var handler: EventHandlerRef?
  private var nextID: UInt32 = 1

  private func installHandlerIfNeeded() -> Bool {
    guard handler == nil else { return true }
    var spec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed),
    )
    return InstallEventHandler(
      GetApplicationEventTarget(),
      hotKeyEventHandler,
      1,
      &spec,
      nil,
      &handler,
    ) == noErr
  }
}

/// Carbon's half of the bridge, and the one place Swift 6 concurrency actually costs
/// something in this codebase.
///
/// `EventHandlerUPP` is a C function pointer, so this closure can capture nothing —
/// not `self`, not the store, nothing. Carbon offers a `userData` pointer for exactly
/// that, but round-tripping a Swift object through `UnsafeMutableRawPointer` means
/// hand-managing its lifetime against a registration that outlives normal ARC scope.
/// Reaching a `shared` singleton by name is the same indirection with none of the
/// unsafety.
private let hotKeyEventHandler: EventHandlerUPP = { _, event, _ in
  guard let event else { return OSStatus(eventNotHandledErr) }

  var id = EventHotKeyID()
  let status = GetEventParameter(
    event,
    EventParamName(kEventParamDirectObject),
    EventParamType(typeEventHotKeyID),
    nil,
    MemoryLayout<EventHotKeyID>.size,
    nil,
    &id,
  )
  guard status == noErr, id.signature == GlobalHotKeyCenter.signature else {
    return OSStatus(eventNotHandledErr)
  }

  // Carbon dispatches application-target events from the main run loop, which is the
  // main thread — the same guarantee AppKit leans on for every event it delivers.
  // Asserting it beats hopping: `Task { @MainActor in }` would defer the loupe to a
  // later runloop turn *and* silently absorb the day the guarantee stopped holding.
  MainActor.assumeIsolated {
    GlobalHotKeyCenter.shared.fire(id.id)
  }
  return noErr
}
