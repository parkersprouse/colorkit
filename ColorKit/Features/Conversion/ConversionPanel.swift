//
//  ConversionPanel.swift
//  ColorKit
//

import SwiftUI

/// The current color written every way CSS allows, all at once.
///
/// Showing all of them simultaneously rather than behind a format picker is the whole
/// point: the question is usually "what is this in oklch?", and a picker turns that
/// into two interactions and hides the comparison that answers it.
struct ConversionPanel: View {
  // MARK: Internal

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 18) {
        // Filtered under M22's web-friendly mode, whose whole promise is that the
        // formats shown here stay hand-authorable sRGB.
        ForEach(FormatSection.sections(webFriendly: store.webFriendly)) { section in
          sectionView(section)
        }
      }
      .padding(16)
    }
  }

  // MARK: Private

  @Environment(ColorStore.self) private var store

  private func sectionView(_ section: FormatSection) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(section.title)
          .font(.headline)
        Text(section.subtitle)
          .font(.caption)
          .foregroundStyle(.tertiary)
      }

      VStack(spacing: 0) {
        let rows = rows(for: section)
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, formatted in
          if index > 0 {
            Divider().padding(.leading, 10)
          }
          FormatRow(formatted: formatted)
        }
      }
      .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
  }

  private func rows(for section: FormatSection) -> [FormattedColor] {
    guard let color = store.color else { return [] }
    // `compactMap` drops formats that cannot name this color — in practice only
    // `keyword`, which exists for 148 colors and no others.
    return section.formats.compactMap {
      color.formatted(as: $0, options: store.formatOptions)
    }
  }
}

/// One format, one value, one click to copy it.
struct FormatRow: View {
  // MARK: Internal

  let formatted: FormattedColor

  var body: some View {
    Button(action: copy) {
      // Centre-aligned, which is what the single-line rows every precision
      // below Maximum produce. Baseline alignment would read better on a
      // wrapped row but shifts the badge and copy icon on every other one.
      HStack(spacing: 10) {
        Text(formatted.format.title)
          .font(.callout)
          .foregroundStyle(.secondary)
          .frame(width: 132, alignment: .leading)

        // Wraps rather than truncates. At the highest precision a
        // `color(prophoto-rgb …)` value outgrows the row, and middle
        // truncation would elide exactly the digits someone raised the
        // precision to see — while the copy button silently delivered the
        // full string, so the display disagreed with the clipboard.
        Text(formatted.css)
          .font(.system(.callout, design: .monospaced))
          .frame(maxWidth: .infinity, alignment: .leading)
          .fixedSize(horizontal: false, vertical: true)

        if formatted.isGamutMapped {
          ColorBadge(text: "mapped")
            .help(
              "\(formatted.format.title) cannot express this color, so the value shown was brought into gamut by reducing chroma.",
            )
        }

        Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
          .font(.caption)
          .foregroundStyle(justCopied ? Color.green : Color.secondary)
          .opacity(justCopied || isHovering ? 1 : 0.35)
          .frame(width: 14)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      // Without this the row only responds where there is text, which makes the
      // whitespace between the label and the value feel dead.
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(isHovering ? Color.primary.opacity(0.06) : .clear)
    .onHover { isHovering = $0 }
    .help("Copy \(formatted.css)")
  }

  // MARK: Private

  @Environment(ColorStore.self) private var store

  @State private var justCopied = false
  @State private var isHovering = false
  @State private var resetTask: Task<Void, Never>?

  private func copy() {
    store.copy(formatted)
    justCopied = true
    // Cancel first, or copying twice in quick succession lets the earlier timer
    // clear the checkmark while the later copy is still fresh.
    resetTask?.cancel()
    resetTask = Task {
      try? await Task.sleep(for: .seconds(1.2))
      guard !Task.isCancelled else { return }
      justCopied = false
    }
  }
}
