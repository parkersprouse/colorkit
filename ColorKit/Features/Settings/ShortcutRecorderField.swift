//
//  ShortcutRecorderField.swift
//  ColorKit
//

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Records a new ``GlobalShortcut`` for the Settings scene (M27).
///
/// A local `NSEvent` monitor installed only while recording, not an
/// `NSViewRepresentable` wrapping a focus-taking `NSView` subclass — this needs no
/// focus ring and no custom hit testing, and returning `nil` from the monitor's handler
/// swallows the event outright, which is what stops a recorded ⌘W (or an unrelated
/// system shortcut) from also acting on the Settings window while a chord is being
/// captured.
///
/// No XCUITest: nothing today drives the Settings window (M22's own web-friendly
/// toggle is already a recorded gap for the same reason), and a unit test synthesizing
/// a key event to exercise this view would need Accessibility permission a test runner
/// has no business holding — the same limitation ``GlobalHotKeyTests`` documents for
/// the *firing* half of a registered chord. What ``ColorStore/updateGlobalShortcut(_:)``
/// does with a captured chord is unit-tested directly; this view's own job — turning an
/// `NSEvent` into a `GlobalShortcut` — is a recorded manual check.
struct ShortcutRecorderField: View {
  // MARK: Internal

  var body: some View {
    VStack(alignment: .trailing, spacing: 4) {
      HStack(spacing: 8) {
        Text(isRecording ? "Press a key combination…" : store.globalShortcut.displayString)
          .foregroundStyle(isRecording ? .secondary : .primary)
          .monospaced()
          .frame(minWidth: 120, alignment: .trailing)

        Button(isRecording ? "Cancel" : "Record Shortcut…") {
          if isRecording {
            stopRecording()
          } else {
            startRecording()
          }
        }

        if store.globalShortcut != .sampleColor {
          Button("Reset") {
            didFail = !store.updateGlobalShortcut(.sampleColor)
          }
        }
      }

      if didFail {
        Text("That combination couldn't be used. Try one with ⌃, ⌥, or ⌘.")
          .font(.caption)
          .foregroundStyle(.orange)
      }
    }
    .onDisappear { stopRecording() }
  }

  // MARK: Private

  private static let namedKeys: [UInt16: String] = [
    UInt16(kVK_Space): "Space",
    UInt16(kVK_Tab): "Tab",
    UInt16(kVK_Return): "Return",
    UInt16(kVK_Delete): "Delete",
    UInt16(kVK_ForwardDelete): "Forward Delete",
    UInt16(kVK_LeftArrow): "←",
    UInt16(kVK_RightArrow): "→",
    UInt16(kVK_UpArrow): "↑",
    UInt16(kVK_DownArrow): "↓",
    UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3", UInt16(kVK_F4): "F4",
    UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6", UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8",
    UInt16(kVK_F9): "F9", UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
    UInt16(kVK_F13): "F13", UInt16(kVK_F14): "F14", UInt16(kVK_F15): "F15",
    UInt16(kVK_F16): "F16", UInt16(kVK_F17): "F17", UInt16(kVK_F18): "F18",
    UInt16(kVK_F19): "F19", UInt16(kVK_F20): "F20",
  ]

  @Environment(ColorStore.self) private var store
  @State private var isRecording = false
  @State private var didFail = false
  @State private var monitor: Any?

  /// `charactersIgnoringModifiers` is empty or unhelpful for Space, Tab, the arrows,
  /// and every function key — the common ones get a name of their own, the same
  /// vocabulary ``GlobalHotKeyTests`` already asserts (`"Space"`, `"F13"`). Everything
  /// else falls back to whatever the key types, uppercased.
  private static func label(forKeyCode keyCode: UInt16, event: NSEvent) -> String {
    if let named = namedKeys[keyCode] {
      return named
    }
    if let typed = event.charactersIgnoringModifiers, !typed.isEmpty {
      return typed.uppercased()
    }
    return "Key \(keyCode)"
  }

  private func startRecording() {
    didFail = false
    isRecording = true
    // Returning `nil` swallows every key while recording — including the chord this
    // captures, which would otherwise also reach whatever it normally does (⌘W
    // closing the window mid-recording, say).
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      handle(event)
      return nil
    }
  }

  private func stopRecording() {
    isRecording = false
    if let monitor {
      NSEvent.removeMonitor(monitor)
    }
    monitor = nil
  }

  private func handle(_ event: NSEvent) {
    guard event.keyCode != UInt16(kVK_Escape) else {
      stopRecording()
      return
    }

    let candidate = GlobalShortcut(
      keyCode: UInt32(event.keyCode),
      modifiers: carbonModifiers(from: event.modifierFlags),
      keyLabel: Self.label(forKeyCode: event.keyCode, event: event),
    )
    didFail = !store.updateGlobalShortcut(candidate)
    stopRecording()
  }

  /// Carbon's modifier masks are different numeric values from
  /// `NSEvent.ModifierFlags`' — see ``GlobalShortcut/modifiers``' own doc — so this is
  /// a translation, not a cast.
  private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
    let relevant = flags.intersection(.deviceIndependentFlagsMask)
    var carbon: UInt32 = 0
    if relevant.contains(.command) {
      carbon |= UInt32(cmdKey)
    }
    if relevant.contains(.option) {
      carbon |= UInt32(optionKey)
    }
    if relevant.contains(.control) {
      carbon |= UInt32(controlKey)
    }
    if relevant.contains(.shift) {
      carbon |= UInt32(shiftKey)
    }
    return carbon
  }
}

#Preview {
  ShortcutRecorderField()
    .environment(ColorStore())
    .padding()
}
