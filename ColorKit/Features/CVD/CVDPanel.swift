//
//  CVDPanel.swift
//  ColorKit
//

import SwiftUI

/// The current color as it looks to someone with a colour-vision deficiency.
///
/// A live filter rather than a verdict: it simulates protan/deutan/tritan vision at any
/// severity using the Machado et al. (2009) matrices, so an author can *see* whether two
/// colors they chose stay distinguishable. It sits beside the contrast panel because it
/// answers the other half of the same accessibility question — contrast asks "can this
/// be read", this asks "can these be told apart".
struct CVDPanel: View {
  // MARK: Internal

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        controls

        if let color = store.color {
          comparison(of: color)
          everyDeficiency(of: color)
          if let background = store.backgroundColor {
            pairing(text: color, background: background)
          }
          if !store.recents.isEmpty {
            palette
          }
        } else {
          ContentUnavailableView(
            "No color yet",
            systemImage: "eye.trianglebadge.exclamationmark",
            description: Text("Type a CSS color above to see it through colour-blind eyes."),
          )
          .frame(maxWidth: .infinity)
        }
      }
      .padding(16)
    }
  }

  // MARK: Private

  @Environment(ColorStore.self) private var store

  private var presentation: CVDPresentation {
    CVDPresentation.of(store.cvdDeficiency)
  }

  private var severityCaption: String {
    let percent = Int((store.cvdSeverity * 100).rounded())
    let endpoint: String = if store.cvdSeverity <= 0.0001 {
      "normal vision"
    } else if store.cvdSeverity >= 0.9999 {
      presentation.dichromacy
    } else {
      presentation.title.lowercased()
    }
    return "\(percent)% · \(endpoint)"
  }

  // MARK: - Controls

  private var controls: some View {
    @Bindable var store = store

    return VStack(alignment: .leading, spacing: 12) {
      Picker("Deficiency", selection: $store.cvdDeficiency) {
        ForEach(ColorVisionDeficiency.allCases, id: \.self) { deficiency in
          Text(CVDPresentation.of(deficiency).title).tag(deficiency)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()

      Text(presentation.summary)
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text("Severity").font(.headline)
          Spacer()
          // Read via `value`, not `label` — see the note in PickerSmokeTests.
          Text(severityCaption)
            .font(.system(.callout, design: .monospaced))
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("cvdSeverity")
        }
        // No label closure: macOS renders it as visible text, and the
        // headline above already names this control.
        Slider(value: $store.cvdSeverity, in: 0 ... 1)
          .labelsHidden()
          .accessibilityLabel("Severity")
          .accessibilityIdentifier("cvdSeveritySlider")
      }
    }
  }

  // MARK: - Recents as a palette

  private var palette: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Recent colors")
        .font(.headline)
      // The whole point of a filter is that it applies to more than one swatch;
      // the recents are the palette already at hand. Original on top, simulated
      // below, so a pair that collapses is obvious.
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(store.recents) { recent in
            let simulated = recent.color.simulating(
              store.cvdDeficiency, severity: store.cvdSeverity,
            )
            VStack(spacing: 3) {
              SwatchButton(
                color: recent.color,
                text: recent.text,
                cornerRadius: 6,
                accessibilityIdentifier: "cvdRecent-\(recent.id)",
              )
              .frame(width: 34, height: 22)
              // The simulated color, not the recent's own — it has no authored text
              // of its own, so it adopts through the value initializer instead.
              SwatchButton(
                color: simulated,
                cornerRadius: 6,
                accessibilityIdentifier: "cvdRecentSimulated-\(recent.id)",
              )
              .frame(width: 34, height: 22)
            }
          }
        }
        .padding(.bottom, 4)
      }
    }
  }

  // MARK: - Original vs simulated

  private func comparison(of color: ColorValue) -> some View {
    let simulated = color.simulating(store.cvdDeficiency, severity: store.cvdSeverity)

    return VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .center, spacing: 14) {
        labeledSwatch(color, caption: "Normal vision", identifier: "cvdOriginal")
        Image(systemName: "arrow.right")
          .foregroundStyle(.secondary)
        labeledSwatch(simulated, caption: presentation.title, identifier: "cvdSimulatedSwatch")
        Spacer()
      }

      // The simulated color's own spelling: the panel's assertable payload, and a
      // value worth copying when you want the confusable to hand.
      Text(simulated.cssStringOrHex(as: .hex, options: store.formatOptions))
        .font(.system(.callout, design: .monospaced))
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .accessibilityIdentifier("cvdSimulated")
    }
  }

  private func labeledSwatch(_ color: ColorValue, caption: String, identifier: String) -> some View {
    VStack(spacing: 6) {
      SwatchButton(color: color, cornerRadius: 10, accessibilityIdentifier: identifier)
        .frame(width: 88, height: 66)
      Text(caption)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  // MARK: - All three at a glance

  private func everyDeficiency(of color: ColorValue) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("At \(Int((store.cvdSeverity * 100).rounded()))% severity")
        .font(.headline)
      HStack(spacing: 12) {
        ForEach(ColorVisionDeficiency.allCases, id: \.self) { deficiency in
          let simulated = color.simulating(deficiency, severity: store.cvdSeverity)
          VStack(spacing: 6) {
            SwatchButton(
              color: simulated,
              cornerRadius: 8,
              accessibilityIdentifier: "cvdEvery-\(deficiency.rawValue)",
            )
            .frame(height: 44)
            Text(CVDPresentation.of(deficiency).title)
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
  }

  // MARK: - The pair, as a CVD viewer sees it

  private func pairing(text: ColorValue, background: ColorValue) -> some View {
    let simText = text.simulating(store.cvdDeficiency, severity: store.cvdSeverity)
    let simBackground = background.simulating(store.cvdDeficiency, severity: store.cvdSeverity)

    return VStack(alignment: .leading, spacing: 8) {
      Text("Text on background")
        .font(.headline)
      HStack(spacing: 12) {
        sample(text: text, background: background, caption: "Normal vision")
        sample(text: simText, background: simBackground, caption: presentation.title)
      }
    }
  }

  private func sample(text: ColorValue, background: ColorValue, caption: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("The quick brown fox")
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(text.displayColor)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(background.displayColor, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .strokeBorder(.separator.opacity(0.5), lineWidth: 1),
        )
      Text(caption)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }
}

/// Wording for each deficiency, kept out of ColorCore.
///
/// ``ColorVisionDeficiency`` carries the cone and the matrices, which are facts. The
/// display name, the plain-language summary and the honest caveat about tritanomaly are
/// editorial — the same split ``RequirementPresentation`` keeps for WCAG.
struct CVDPresentation {
  let deficiency: ColorVisionDeficiency
  /// Title-cased name, e.g. "Deuteranomaly".
  let title: String
  /// The severity-1.0 dichromacy this deficiency approaches.
  let dichromacy: String
  /// One line of plain language, shown under the picker.
  let summary: String

  static func of(_ deficiency: ColorVisionDeficiency) -> CVDPresentation {
    switch deficiency {
    case .protanomaly:
      CVDPresentation(
        deficiency: deficiency,
        title: "Protanomaly",
        dichromacy: "protanopia",
        summary: "Reduced sensitivity to red light. Reds darken and can be "
          + "confused with greens; protanopia — no working red cones — is the "
          + "full-severity endpoint.",
      )
    case .deuteranomaly:
      CVDPresentation(
        deficiency: deficiency,
        title: "Deuteranomaly",
        dichromacy: "deuteranopia",
        summary: "Reduced sensitivity to green light — the most common form of "
          + "colour blindness, affecting roughly 6% of men. Red and green grow "
          + "hard to tell apart.",
      )
    case .tritanomaly:
      CVDPresentation(
        deficiency: deficiency,
        title: "Tritanomaly",
        dichromacy: "tritanopia",
        // Honest about the model's weak spot, in the spirit of the APCA
        // no-badge decision: the paper's authors note tritanomaly is an
        // approximation via the shift paradigm rather than a fit to data.
        summary: "Reduced sensitivity to blue light, confusing blues with greens "
          + "and yellows with violet. Rare, and the case Machado's model "
          + "approximates rather than measures — read it as indicative.",
      )
    }
  }
}
