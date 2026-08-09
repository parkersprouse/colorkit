//
//  ContrastPanel.swift
//  ColorKit
//

import SwiftUI

/// The current color read as text on a background, judged two ways.
///
/// Shows WCAG and APCA side by side rather than picking one, because they disagree by
/// design: WCAG's ratio is symmetric and normative, APCA's `Lc` is polarity-aware and
/// still a draft. A tool that showed only one would be either behind the research or
/// ahead of what an audit will actually check.
struct ContrastPanel: View {
  // MARK: Internal

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        backgroundField
        if let text = store.color, let background = store.backgroundColor {
          preview(text: text, background: background)
          wcag(text: text, background: background)
          apca(text: text, background: background)
        } else {
          ContentUnavailableView(
            "Two colors needed",
            systemImage: "circle.lefthalf.filled",
            description: Text("Contrast is a property of a pair, so both fields have to parse."),
          )
          .frame(maxWidth: .infinity)
        }
      }
      .padding(16)
    }
  }

  // MARK: Private

  @Environment(ColorStore.self) private var store

  // MARK: - Background

  private var backgroundField: some View {
    @Bindable var store = store

    return VStack(alignment: .leading, spacing: 6) {
      Text("Background")
        .font(.headline)

      HStack(spacing: 12) {
        if let background = store.backgroundColor {
          // The text initializer, not the value one: this swatch renders
          // `store.backgroundText` itself, so re-deriving through `adopt` would
          // canonicalize a typed `rebeccapurple` to `#663399` the moment "Use as
          // color" or "Copy" is reached for — the exact loss this app's text-is-truth
          // doctrine exists to prevent.
          SwatchButton(
            color: background,
            text: store.backgroundText,
            cornerRadius: 6,
            accessibilityIdentifier: "contrastBackgroundSwatch",
          )
          .frame(width: 34, height: 34)
        } else {
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(.separator, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            .frame(width: 34, height: 34)
        }

        VStack(alignment: .leading, spacing: 4) {
          TextField("#ffffff", text: $store.backgroundText)
            .textFieldStyle(.plain)
            .font(.system(.body, design: .monospaced))
            .accessibilityIdentifier("backgroundInput")
          Divider()
        }

        Button {
          store.swapForegroundAndBackground()
        } label: {
          Image(systemName: "arrow.up.arrow.down")
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("swapColors")
        // An icon-only `Button` otherwise announces its SF Symbol name — VoiceOver
        // would read this one as "arrow up arrow down", the same failure the tool
        // switcher's `Text`-not-`Label` note in `ContentView` exists to avoid. An
        // identifier is not a substitute: XCUITest reads it, VoiceOver does not, and
        // `.help` is a pointer tooltip rather than an accessibility label.
        .accessibilityLabel("Swap text and background")
        .help("Swap text and background. APCA scores the two directions differently.")
      }

      if case let .failed(error) = store.backgroundParsed {
        Label(error.message, systemImage: "exclamationmark.triangle.fill")
          .font(.callout)
          .foregroundStyle(.red)
      }
    }
  }

  // MARK: - Preview

  private func preview(text: ColorValue, background: ColorValue) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      // Three sizes because every threshold below is about type size. Numbers
      // alone do not tell you whether 4.5:1 is comfortable; a sentence does.
      Text("The quick brown fox").font(.system(size: 22, weight: .semibold))
      Text("The quick brown fox").font(.system(size: 15))
      Text("The quick brown fox").font(.system(size: 11))
    }
    .foregroundStyle(text.displayColor)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .background(background.displayColor, in: RoundedRectangle(cornerRadius: 8))
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .strokeBorder(.separator.opacity(0.5), lineWidth: 1),
    )
  }

  // MARK: - WCAG

  private func wcag(text: ColorValue, background: ColorValue) -> some View {
    let ratio = text.contrastRatio(with: background)
    let passed = text.passedRequirements(on: background)

    return VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text("WCAG 2.2")
          .font(.headline)
        // Two decimals, matching how audit tools report it — and how the
        // published thresholds are written.
        Text(String(format: "%.2f:1", ratio))
          .font(.system(.title3, design: .monospaced))
        Spacer()
      }

      VStack(spacing: 0) {
        ForEach(Array(RequirementPresentation.all.enumerated()), id: \.element.id) { index, item in
          if index > 0 {
            Divider()
          }
          requirementRow(item, passes: passed.contains(item.requirement))
        }
      }
      .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
  }

  private func requirementRow(_ item: RequirementPresentation, passes: Bool) -> some View {
    HStack(spacing: 10) {
      Image(systemName: passes ? "checkmark.circle.fill" : "xmark.circle")
        .foregroundStyle(passes ? Color.green : Color.secondary)
      Text(item.title)
      Text(item.requirement.criterion)
        .font(.caption)
        // See the note in `apca` — nothing in this panel is dimmer than
        // secondary, on principle.
        .foregroundStyle(.secondary)
      Spacer()
      Text(String(format: "%g:1", item.requirement.minimumRatio))
        .font(.system(.callout, design: .monospaced))
        .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
  }

  // MARK: - APCA

  private func apca(text: ColorValue, background: ColorValue) -> some View {
    let lc = text.apcaContrast(on: background)

    return VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text("APCA")
          .font(.headline)
        Text(String(format: "Lc %+.1f", lc))
          .font(.system(.title3, design: .monospaced))
        Spacer()
      }

      // No pass/fail. APCA's readability levels exist but could not be verified
      // against a pinned source the way the algorithm itself was, and a
      // threshold this app cannot stand behind has no business wearing a
      // checkmark next to WCAG's, which it can.
      // Comparative, not absolute. APCA measures a signed lightness *difference*,
      // so a mid-blue background is "darker" only relative to white text — and
      // calling #3b82f6 a dark background out loud reads as a bug.
      Text(
        lc == 0
          ? "Below the algorithm's reporting floor — too little contrast to score."
          : (lc > 0
            ? "Darker text on a lighter background."
            : "Lighter text on a darker background."),
      )
      .font(.callout)
      .foregroundStyle(.secondary)

      // `.secondary`, not `.tertiary`. Tertiary is dim enough to fail the very
      // check running six inches above it, and a contrast tool that ships
      // low-contrast text has undermined its own advice.
      Text(
        "Draft algorithm (0.0.98G), not part of WCAG. Unlike a ratio, Lc is direction-dependent — swap the colors and the number changes.",
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
  }
}

/// Wording for each requirement, kept out of ColorCore.
///
/// ``ContrastRequirement`` carries the ratio and the success-criterion number, which
/// are spec facts. "Body text" is a phrasing choice, and phrasing changes the first
/// time the layout does.
struct RequirementPresentation: Identifiable {
  /// Ordered by how much contrast they demand, so the row that fails first is the
  /// one nearest the bottom.
  static let all: [RequirementPresentation] = [
    .init(requirement: .nonText, title: "UI components & graphics"),
    .init(requirement: .aaLargeText, title: "AA · Large text"),
    .init(requirement: .aaNormalText, title: "AA · Body text"),
    .init(requirement: .aaaLargeText, title: "AAA · Large text"),
    .init(requirement: .aaaNormalText, title: "AAA · Body text"),
  ]

  let requirement: ContrastRequirement
  let title: String

  var id: ContrastRequirement {
    requirement
  }
}
