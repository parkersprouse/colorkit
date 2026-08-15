//
//  ColorInputField.swift
//  ColorKit
//

import SwiftUI

/// The field everything else hangs off: type any CSS color, see it parse as you go.
struct ColorInputField: View {
  // MARK: Internal

  var body: some View {
    @Bindable var store = store

    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .center, spacing: 14) {
        swatch

        VStack(alignment: .leading, spacing: 6) {
          TextField("#3b82f6", text: $store.inputText)
            .textFieldStyle(.plain)
            .font(.system(.title2, design: .monospaced))
            .accessibilityIdentifier("colorInput")
            // Submitting is one of the moments a color is worth keeping,
            // as opposed to the dozens of valid prefixes typed to reach it.
            .onSubmit { store.remember() }
          Divider()
        }

        eyedropper
      }

      status
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  // MARK: Private

  @Environment(ColorStore.self) private var store

  @State private var showsPicker = false
  /// Forces a fresh ``CompactPicker`` — and so a fresh ``PickerState`` — on every
  /// open, rather than leaning on `.popover`'s own behavior on dismiss.
  ///
  /// Measured rather than assumed:
  /// `testReopeningThePopoverSeedsFromWhateverIsInTheFieldNow` passes identically
  /// with `.id(pickerSession)` removed, because macOS already discards a popover's
  /// content view — `@State` included — the moment it closes, so
  /// `.task { seedFromStore() }` re-runs on every open with or without this. Kept
  /// anyway as deliberate insurance rather than reverted as dead code: `.popover`
  /// documents no such teardown guarantee, so this is what keeps the reseed correct
  /// if that stops being true on a future OS rather than relying on it silently.
  @State private var pickerSession = 0

  // MARK: - Eyedropper

  /// Samples a pixel into the field. Does **not** touch the clipboard — the field is
  /// right here, and the global shortcut is the variant that copies.
  private var eyedropper: some View {
    Button {
      Task { await store.sampleFromScreen() }
    } label: {
      Image(systemName: "eyedropper")
        .font(.title3)
        .frame(width: 26, height: 26)
        .contentShape(Rectangle())
    }
    .buttonStyle(.borderless)
    .accessibilityIdentifier("eyedropper")
    .accessibilityLabel("Pick a color from the screen")
    .help(
      store.globalShortcutIsActive
        ? "Pick a color from the screen. Works from any app with \(store.globalShortcut.displayString)."
        : "Pick a color from the screen.",
    )
  }

  // MARK: - Swatch

  /// A popover trigger (M24), not a ``SwatchButton``: this swatch doesn't adopt a
  /// color on click or carry the "use as background / copy" menu those do — it
  /// opens ``CompactPicker`` on the color already in the field. With no color yet,
  /// opening the picker is the single most useful thing this swatch can do, so the
  /// dashed empty state is a button too.
  private var swatch: some View {
    Button {
      pickerSession += 1
      showsPicker = true
    } label: {
      swatchContent
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("headerSwatch")
    .accessibilityLabel("Color picker")
    .popover(isPresented: $showsPicker, arrowEdge: .bottom) {
      CompactPicker()
        .id(pickerSession)
    }
  }

  @ViewBuilder
  private var swatchContent: some View {
    if let color = store.color {
      ColorSwatch(color: color)
        .frame(width: 58, height: 58)
    } else {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .strokeBorder(
          .separator,
          style: StrokeStyle(lineWidth: 1, dash: [4, 3]),
        )
        // A stroked-only shape hit-tests only its 1pt outline, leaving the
        // middle of the empty state dead to a click — this is the one case
        // where the swatch has nothing filled to catch it.
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .frame(width: 58, height: 58)
    }
  }

  // MARK: - Status

  @ViewBuilder
  private var status: some View {
    switch store.parsed {
    case .empty:
      Text("hex, rgb(), hsl(), hwb(), lab(), lch(), oklab(), oklch(), color(), or a keyword.")
        .foregroundStyle(.secondary)

    case let .failed(error):
      Label(error.message, systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(.red)

    case let .parsed(result):
      VStack(alignment: .leading, spacing: 4) {
        summary(for: result)
        // Warnings mean it parsed but is not valid CSS. Shown rather than
        // rejected, because both cases are unambiguous about intent — but
        // shown loudly, because pasting one into a stylesheet does nothing.
        ForEach(Array(result.warnings.enumerated()), id: \.offset) { _, warning in
          Label(warning.message, systemImage: "exclamationmark.circle.fill")
            .foregroundStyle(.orange)
        }
      }
    }
  }

  private func summary(for result: ParseResult) -> some View {
    HStack(spacing: 8) {
      notationMenu(for: result)

      if result.color.exceedsDisplayGamut {
        ColorBadge(text: "Beyond this display")
          .help(
            "This color is outside Display P3, so the swatch shows the closest color your screen can produce.",
          )
      } else if result.color.exceedsSRGB {
        ColorBadge(text: "Outside sRGB")
          .help(
            "Outside the sRGB gamut. Formats that cannot express it are gamut-mapped, not clipped.",
          )
      }

      if result.color.isAchromatic, result.color.space.hueIndex != nil {
        ColorBadge(text: "Hue is powerless", tint: .gray)
          .help(
            "The color is neutral, so its hue carries no information. CSS serializes such components as none.",
          )
      }
    }
  }

  /// A `Menu` (M25) over every format that can name the active color, grouped the same
  /// way ``MenuBarPanel/copyMenu`` groups its formats — sharing ``FormatSection`` rather
  /// than repeating its walk, and narrowed to ``FormatSection/webFriendly`` under the
  /// same flag. Unlike the copy menu, choosing an entry here doesn't just read the
  /// color — it rewrites `store.inputText`, so ``ColorStore/respell(as:)`` is the one
  /// place that decides what string actually gets written.
  private func notationMenu(for result: ParseResult) -> some View {
    Menu {
      ForEach(FormatSection.sections(webFriendly: store.webFriendly)) { section in
        let formats = nameableFormats(in: section, for: result.color)
        if !formats.isEmpty {
          Section(section.title) {
            ForEach(formats, id: \.self) { format in
              Button(format.title) { store.respell(as: format) }
            }
          }
        }
      }
    } label: {
      Text(describe(result.notation))
        .foregroundStyle(.secondary)
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
    .accessibilityIdentifier("notationMenu")
  }

  /// `section.formats`, narrowed to the ones that can actually name `color` —
  /// `.keyword` is the only format that ever answers `nil`, but the filter is written
  /// generally rather than special-cased to it, the same way
  /// ``ColorValue/allFormats(options:)`` does it. Options are ``CSSFormatOptions/lossless``
  /// only to decide *nameability*, not to spell what is shown — the menu items are
  /// labelled with the format's title (`format.title`), never with the resulting CSS, so
  /// no precision choice here reaches the screen.
  private func nameableFormats(in section: FormatSection, for color: ColorValue) -> [CSSOutputFormat] {
    section.formats.filter { color.formatted(as: $0, options: .lossless) != nil }
  }

  private func describe(_ notation: ColorNotation) -> String {
    switch notation {
    case let .hex(digits):
      "\(digits)-digit hex"
    case let .keyword(name):
      "Named color \(name.lowercased())"
    case let .function(function, legacy):
      legacy
        ? "\(function.rawValue)() · legacy comma syntax"
        : "\(function.rawValue)()"
    case let .relative(function):
      "\(function.rawValue)() · relative to an origin color"
    case let .mix(interpolation):
      // The space is the substance of the choice, so it is what the summary says —
      // the hue arc only exists for half of them and is noise on the rest.
      "color-mix() · interpolated in \(interpolation.space.rawValue)"
    }
  }
}
