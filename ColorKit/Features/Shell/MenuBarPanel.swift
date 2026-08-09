//
//  MenuBarPanel.swift
//  ColorKit
//

import AppKit
import SwiftUI

/// What drops down from the menu bar icon.
///
/// Uses the `.window` `MenuBarExtra` style rather than `.menu`, because `.menu`
/// renders a real `NSMenu` and cannot draw arbitrary SwiftUI — which would reduce
/// recent colors to a list of hex strings. For a color tool the swatches *are* the
/// content, so the trade is worth the loss of native menu behavior.
struct MenuBarPanel: View {
  // MARK: Internal

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      current
      Divider()
      recents
      Divider()
      actions
    }
    .frame(width: 272)
  }

  // MARK: Private

  @Environment(ColorStore.self) private var store
  @Environment(\.openWindow) private var openWindow

  private var resolvedHex: String? {
    store.color?.cssStringOrHex(as: .hex, options: store.formatOptions)
  }

  /// What was typed — unless it says the same thing as the line above it.
  ///
  /// The subtitle earns its place when the two disagree: `rebeccapurple` or an
  /// `oklch()` stays visible next to the hex it resolves to. Type hex in the first
  /// place and there is nothing left to show, and a value printed twice reads as a
  /// rendering bug rather than as detail.
  ///
  /// Compared case-insensitively, so `#3B82F6` counts as a match — but not
  /// otherwise normalized, because `#ffcc00` against a collapsed `#fc0` genuinely
  /// is two different strings and worth seeing both of.
  private var authoredText: String? {
    let typed = store.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !typed.isEmpty, typed.lowercased() != resolvedHex?.lowercased() else { return nil }
    return typed
  }

  // MARK: - Current color

  private var current: some View {
    HStack(spacing: 10) {
      if let color = store.color {
        // The default tap is inherently a no-op here — the color already *is* the
        // field — so this swatch earns its place through the menu instead: "Use as
        // background" and "Copy" are real actions even when "Use as color" is not.
        // `store.inputText` rather than the resolved hex, so a typed `rebeccapurple`
        // stays `rebeccapurple` if the menu's Copy is used.
        SwatchButton(
          color: color,
          text: store.inputText,
          cornerRadius: 6,
          accessibilityIdentifier: "menuBarCurrent",
        )
        .frame(width: 40, height: 40)
      } else {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .strokeBorder(.separator, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
          .frame(width: 40, height: 40)
      }

      VStack(alignment: .leading, spacing: 2) {
        Text(resolvedHex ?? "No color")
          .font(.system(.body, design: .monospaced))
        if let authoredText {
          Text(authoredText)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }

      Spacer(minLength: 0)

      copyMenu
    }
    .padding(12)
  }

  private var copyMenu: some View {
    Menu {
      ForEach(FormatSection.sections(webFriendly: store.webFriendly)) { section in
        Section(section.title) {
          ForEach(formats(in: section)) { formatted in
            Button(formatted.format.title) { store.copy(formatted) }
          }
        }
      }
    } label: {
      Label("Copy as", systemImage: "doc.on.doc")
        .labelStyle(.iconOnly)
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
    .disabled(store.color == nil)
    .help("Copy as…")
  }

  // MARK: - Recents

  private var recents: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Recent")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        Spacer()
        if !store.recents.isEmpty {
          Button("Clear") { store.clearRecents() }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      if store.recents.isEmpty {
        Text("Colors you copy or submit collect here.")
          .font(.caption)
          .foregroundStyle(.tertiary)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        LazyVGrid(
          columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6),
          spacing: 6,
        ) {
          ForEach(store.recents) { recent in
            SwatchButton(
              color: recent.color,
              text: recent.text,
              cornerRadius: 5,
              checkerSize: 4,
              accessibilityIdentifier: "menuBarRecent-\(recent.id)",
            )
            .frame(height: 30)
            .help(recent.text)
          }
        }
      }
    }
    .padding(12)
  }

  private var actions: some View {
    VStack(spacing: 1) {
      // The shortcut is shown only once the system has actually accepted it.
      // Advertising a chord that was never registered is worse than offering
      // none: the user presses it, nothing happens, and the app looks broken.
      MenuBarRow(
        title: "Pick Color from Screen",
        systemImage: "eyedropper",
        shortcut: store.globalShortcutIsActive
          ? store.globalShortcut.displayString
          : nil,
      ) {
        Task { await store.sampleFromScreen(alsoCopy: true) }
      }
      MenuBarRow(title: "Open ColorKit", systemImage: "macwindow") {
        // A `.window`-style MenuBarExtra does not front the app on its own, so
        // without this the window opens behind whatever you were looking at.
        NSApp.activate()
        openWindow(id: WindowID.main)
      }
      MenuBarRow(title: "Quit", systemImage: "power") {
        NSApp.terminate(nil)
      }
    }
    .padding(6)
  }

  private func formats(in section: FormatSection) -> [FormattedColor] {
    guard let color = store.color else { return [] }
    return section.formats.compactMap {
      color.formatted(as: $0, options: store.formatOptions)
    }
  }
}

/// A menu-bar-panel row that highlights on hover, the way a real menu item would.
struct MenuBarRow: View {
  // MARK: Internal

  let title: String
  let systemImage: String
  /// Shown right-aligned, the way a real menu item shows its equivalent. `nil` when
  /// the row has no shortcut, or when the one it would name is not actually live.
  var shortcut: String?
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Label(title, systemImage: systemImage)
        Spacer(minLength: 12)
        if let shortcut {
          Text(shortcut)
            // Not `.secondary`: the row inverts to white on hover, and a
            // hierarchical style would keep this grey against the accent
            // colour. Opacity dims it relative to whatever it inherits.
            .opacity(0.65)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(
      isHovering ? Color.accentColor : .clear,
      in: RoundedRectangle(cornerRadius: 5, style: .continuous),
    )
    .foregroundStyle(isHovering ? Color.white : Color.primary)
    .onHover { isHovering = $0 }
  }

  // MARK: Private

  @State private var isHovering = false
}
