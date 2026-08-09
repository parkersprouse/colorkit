//
//  PickerPanel.swift
//  ColorKit
//

import SwiftUI

/// Choosing a color by eye instead of by typing one.
///
/// Two sets of axes over the same plane. **HSV** is the square every design tool
/// shows, and it is here because muscle memory is worth more than novelty. **OKLCH**
/// is the one this app exists to offer: perceptually even, and with the sRGB edge
/// drawn on the plane so the moment a color stops being expressible on the web is
/// visible rather than inferred from a badge after the fact.
///
/// The panel writes to the shared field on every change and reads back only when
/// something else has written there — see ``PickerState/syncing(with:color:)`` for why
/// the two directions cannot be the same code path.
///
/// The plane, hue strip and alpha strip are ``PickerPlaneView``, ``PickerHueStripView``
/// and ``PickerAlphaSliderView`` (M24) — extracted so the popover picker on the header
/// swatch, ``CompactPicker``, composes the identical controls instead of a second,
/// inevitably drifting copy.
struct PickerPanel: View {
  // MARK: Internal

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        modeSwitcher
        planeAndStrip
        PickerAlphaSliderView(state: $state)
        readout
      }
      .padding(16)
      .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
        planeSide = squareSide(forPanelWidth: width)
      }
    }
    .task { seedFromStore() }
    .onChange(of: store.inputText) { state.syncing(with: store.inputText, color: store.color) }
    // The popover's own mode switcher (M24, `CompactPicker`) can change
    // `store.pickerMode` while this panel is already mounted — the header swatch
    // sits above the tool switcher, so nothing stops opening the popover while on
    // the Pick tab. Without this, this panel's local `state.mode` would only ever
    // follow *its own* switcher, and the two would silently disagree about which
    // axes are showing until the tool was left and re-entered. `setMode` no-ops
    // when the mode already matches, so this is also safe to fire on the write
    // this panel's own switcher just made.
    .onChange(of: store.pickerMode) { state.setMode(store.pickerMode, carrying: store.color) }
  }

  // MARK: Private

  @Environment(ColorStore.self) private var store

  @State private var state = PickerState()
  @State private var planeSide: CGFloat = 320

  // MARK: - Mode

  private var modeSwitcher: some View {
    Picker(
      "Axes",
      selection: Binding(
        get: { state.mode },
        // The field's color, not the panel's: see ``PickerState/setMode(_:carrying:)``.
        // Switching tabs deliberately does not *write* — looking at a color in
        // other axes is not editing it, and rewriting `#3b82f6` as `oklch(…)`
        // for having glanced at the OKLCH tab would be presumptuous.
        set: { newMode in
          state.setMode(newMode, carrying: store.color)
          store.pickerMode = newMode
        },
      ),
    ) {
      ForEach(PickerMode.allCases) { mode in
        Text(mode.title).tag(mode)
      }
    }
    .pickerStyle(.segmented)
    .labelsHidden()
    .fixedSize()
    .accessibilityIdentifier("pickerMode")
  }

  private var planeAndStrip: some View {
    HStack(alignment: .top, spacing: 12) {
      // `fillsAvailableWidth: true` — this panel's plane stretches to the row's
      // full width rather than sitting in a fixed square; see
      // `PickerPlaneView.fillsAvailableWidth`.
      PickerPlaneView(state: $state, side: planeSide, fillsAvailableWidth: true)
      PickerHueStripView(state: $state, height: planeSide)
    }
    .frame(height: planeSide)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: - Readout

  /// The numbers behind the cursor.
  ///
  /// Not redundant with the field above, which shows one CSS string: HSV has no CSS
  /// spelling at all, and in OKLCH mode the chroma still available at this lightness
  /// and hue is the panel's actual payload — it is what turns "this looks vivid" into
  /// "this is 0.19 of a possible 0.21".
  @ViewBuilder
  private var readout: some View {
    switch state.mode {
    case .hsv:
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 18) {
          figure("H", String(format: "%.1f°", state.hsvHue), id: "readoutFirst")
          figure("S", String(format: "%.1f%%", state.saturation), id: "readoutSecond")
          figure("V", String(format: "%.1f%%", state.value), id: "readoutThird")
          figure("A", String(format: "%.2f", state.alpha), id: "readoutAlpha")
          Spacer()
        }

        // Keyed off the *field's* color rather than the panel's, because in
        // this mode they can differ: HSV has no way to hold a wide color, so
        // the square shows the nearest one it can. Saying so is the same move
        // the conversion panel makes when it badges a mapped row — show the
        // closest honest thing, and admit the compromise beside it.
        if store.color?.exceedsSRGB == true {
          HStack(spacing: 10) {
            ColorBadge(text: "Outside sRGB")
            Text("HSV describes the sRGB cube, so the square is showing the nearest color it can hold. Switch to OKLCH to keep the original.")
              .font(.callout)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
            Spacer()
          }
        }
      }
    case .oklch:
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 18) {
          figure("L", String(format: "%.4f", state.lightness), id: "readoutFirst")
          figure("C", String(format: "%.4f", state.chroma), id: "readoutSecond")
          figure("H", String(format: "%.1f°", state.oklchHue), id: "readoutThird")
          figure("A", String(format: "%.2f", state.alpha), id: "readoutAlpha")
          Spacer()
        }
        // Unreachable rather than wrong under web-friendly (M22): the cursor's
        // chroma is clamped to the sRGB edge on every drag (see
        // ``PickerState/committing(_:in:)``), so this line would only ever
        // report "no headroom used" — hidden, the same way every other exotic
        // control in this mode is.
        if !store.webFriendly {
          gamutLine
        }
      }
    }
  }

  private var gamutLine: some View {
    let available = GamutBoundary.maxChroma(
      lightness: state.lightness,
      hue: state.oklchHue,
      in: .srgb,
    )

    return HStack(spacing: 10) {
      Text(String(format: "sRGB allows %.4f here", available))
        .font(.callout)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("readoutLimit")

      if state.color.exceedsSRGB {
        ColorBadge(text: "Outside sRGB")
      }

      Spacer()
    }
  }

  private func figure(_ label: String, _ value: String, id: String) -> some View {
    HStack(spacing: 5) {
      Text(label)
        .font(.caption.weight(.semibold))
        // Nothing in this app is dimmer than secondary — the rule the contrast
        // panel set, applied everywhere since.
        .foregroundStyle(.secondary)
      Text(value)
        .font(.system(.callout, design: .monospaced))
        .accessibilityIdentifier(id)
    }
  }

  // MARK: - Plumbing

  /// The row's height is set from the panel's **width**, never inferred from the
  /// space available.
  ///
  /// The plane is a `GeometryReader` inside a `ScrollView`, which proposes unbounded
  /// height — so a square asked to fit that proposal takes all of it, and the window
  /// opens nearly a thousand points tall. Worse, the resize that follows moves
  /// controls out from under a click that was already on its way. Width is bounded,
  /// measuring it cannot feed back into itself, and a square is as wide as it is
  /// tall — so width is the one dimension worth asking about.
  ///
  /// This still governs only the plane's **height**. M24's extraction briefly gave
  /// the plane an explicit `.frame(width:)` too, making it a true square that stopped
  /// growing past 460pt in either dimension — reasoned at the time as closing a gap
  /// left by the pre-M24 layout, where the plane had no `.frame(width:)` of its own
  /// and simply took whatever the row's `HStack` had left over after the 28pt strip.
  /// That reasoning was correct about the *edge case* (above roughly 532pt of panel
  /// width the old layout was a rectangle, not a square) and wrong about which shape
  /// was wanted: a `PickerPanel` wider than that reads better filling the width it
  /// has, not sitting in a fixed square beside empty space. Reverted for this panel
  /// (`fillsAvailableWidth: true` on the `PickerPlaneView` this feeds) once that
  /// became clear; `CompactPicker`'s popover has no such container to fill and keeps
  /// the fixed square.
  private func squareSide(forPanelWidth width: CGFloat) -> CGFloat {
    // Panel padding, the strip, and the gap between them.
    min(max(width - 72, 240), 460)
  }

  /// Re-entering the tool rebuilds this panel's `@State` from scratch, which is right
  /// for the axes — the field's color may have moved while the tool was away — and
  /// wrong for the mode, which is a preference rather than a view of anything. So the
  /// axes come from the color and the mode comes from the store.
  private func seedFromStore() {
    if let color = store.color {
      state.seed(from: color)
    }
    state.setMode(store.pickerMode, carrying: store.color)
  }
}

#Preview {
  PickerPanel()
    .environment(ColorStore(initialInput: "oklch(0.62 0.19 260)"))
    .frame(width: 520, height: 520)
}
