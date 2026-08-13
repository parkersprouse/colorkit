//
//  InlineSettingsBar.swift
//  ColorKit
//

import SwiftUI

/// M36's inline settings strip — the handful of ``ColorStore/formatOptions`` and
/// ``ColorStore/webFriendly`` controls that are common enough to earn a seat outside
/// ``OutputOptionsMenu``'s gear, when the window is wide enough to spare the room.
///
/// Sits in the window body, above ``ColorInputField``, **not** in `.toolbar`. That is
/// not a style choice: the old tool switcher lived in the toolbar until a sixth tab
/// made macOS sweep it whole into a "more toolbar items" overflow menu at a window
/// width well inside what looked like plenty of room (see `ContentView`'s history in
/// PLAN.md) — a `ToolbarItem(placement: .principal)`'s width budget is
/// `windowWidth − 2 × max(leading, trailing)`, not "whatever the toolbar has spare."
/// Three more controls beside ``OutputOptionsMenu`` would risk the identical failure,
/// and worse here: an overflowed gear menu would hide the *only* way to reach every
/// other output setting, not just a convenience duplicate of it.
///
/// `ViewThatFits` picks the widest tier that fits without needing a measured
/// threshold — the same reason it is preferred over a `GeometryReader` elsewhere in
/// this app. Each control also appears in ``OutputOptionsMenu``, which is not new
/// duplication: `SettingsView`'s own doc comment already establishes that precedent
/// for ``ColorStore/formatOptions``, and this is a third surface onto the identical
/// bindings, not a second setting.
struct InlineSettingsBar: View {
  // MARK: Internal

  var body: some View {
    @Bindable var store = store

    ViewThatFits(in: .horizontal) {
      full(store: store)
      medium(store: store)
      minimal
    }
    // No fixed height: a `Picker(.menu)` measures 26pt, taller than the toggle beside
    // it, and a `.frame(height:)` here once clipped the pickers against a guessed
    // number instead of letting the row size itself to its tallest control.
    .padding(.horizontal, 16)
    .padding(.top, 12)
  }

  // MARK: Private

  @Environment(ColorStore.self) private var store

  private var minimal: some View {
    HStack {
      Spacer(minLength: 0)
      OutputOptionsMenu()
    }
  }

  private func medium(store: ColorStore) -> some View {
    HStack(spacing: 12) {
      webFriendlyToggle(store: store)
      Spacer(minLength: 8)
      OutputOptionsMenu()
    }
  }

  private func full(store: ColorStore) -> some View {
    HStack(spacing: 14) {
      webFriendlyToggle(store: store)

      Divider().frame(height: 14)

      precisionPicker(store: store)
      gamutPicker(store: store)

      Spacer(minLength: 8)

      OutputOptionsMenu()
    }
  }

  private func webFriendlyToggle(store: ColorStore) -> some View {
    @Bindable var store = store

    return Toggle(isOn: $store.webFriendly) {
      Label("Web-friendly", systemImage: "network")
        .font(.callout)
    }
    .toggleStyle(.switch)
    .controlSize(.small)
    .help("Hides exotic formats and keeps every value inside sRGB.")
    .accessibilityIdentifier("inlineWebFriendlyToggle")
  }

  /// Same three-level naming as ``OutputOptionsMenu`` and `SettingsView` — precision
  /// is relative to each component's scale, not a flat decimal count, so a named
  /// level is the one wording that stays true at every component's own precision.
  private func precisionPicker(store: ColorStore) -> some View {
    @Bindable var store = store

    return Picker("Precision", selection: $store.formatOptions.precision) {
      Text("Compact").tag(2)
      Text("Normal").tag(4)
      Text("Fine").tag(6)
      Text("Maximum").tag(10)
    }
    .pickerStyle(.menu)
    .labelsHidden()
    .fixedSize()
    .help("Precision")
    .accessibilityIdentifier("inlinePrecisionPicker")
  }

  private func gamutPicker(store: ColorStore) -> some View {
    @Bindable var store = store

    return Picker("Out of gamut", selection: $store.formatOptions.gamut) {
      Text("Map into gamut").tag(CSSFormatOptions.GamutPolicy.map)
      Text("Keep original values").tag(CSSFormatOptions.GamutPolicy.preserve)
    }
    .pickerStyle(.menu)
    .labelsHidden()
    .fixedSize()
    .help("Out of gamut")
    .accessibilityIdentifier("inlineGamutPicker")
  }
}

#Preview {
  InlineSettingsBar()
    .environment(ColorStore())
    .frame(width: 700)
}

#Preview("Narrow") {
  InlineSettingsBar()
    .environment(ColorStore())
    .frame(width: 260)
}
