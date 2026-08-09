//
//  RecentsRow.swift
//  ColorKit
//

import SwiftUI

/// The colors you've already worked with, one tap from the input field above it.
///
/// Sits between ``ColorInputField`` and the tool switcher — the same argument that
/// puts the field itself above the switcher: a recent belongs to no tool, so it lives
/// with the other thing that doesn't either. Gated on ``ColorStore/showsRecents``
/// (M19) alone, never on whether the list happens to be empty — always rendering,
/// with an empty-state line in place of swatches, is what `MenuBarPanel`'s own
/// recents section already does, and for the same reason: a row that materializes
/// the moment the first color is remembered would push the tool switcher and every
/// panel below it down a frame after the click that triggered it, and this app has
/// already been bitten once by a resize landing under a click already in flight (see
/// the `GeometryReader` note in PLAN.md).
struct RecentsRow: View {
  // MARK: Internal

  var body: some View {
    if store.showsRecents {
      VStack(alignment: .leading, spacing: 6) {
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
              .accessibilityIdentifier("clearRecents")
          }
        }

        if store.recents.isEmpty {
          Text("Colors you copy or submit collect here.")
            .font(.caption)
            .foregroundStyle(.tertiary)
        } else {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
              ForEach(store.recents) { recent in
                // The authored-text initializer (M21), so a click returns *your*
                // spelling rather than a canonicalized one — the same contract
                // `MenuBarPanel`'s own recents grid makes, and deliberately not
                // filtered by ``ColorStore/webFriendly`` (M22): a recent's text is
                // prior input, and the mode hides output, it does not reject input.
                SwatchButton(
                  color: recent.color,
                  text: recent.text,
                  cornerRadius: 6,
                  checkerSize: 4,
                  accessibilityIdentifier: "recentColor-\(recent.id)",
                )
                .frame(width: 30, height: 30)
                .help(recent.text)
              }
            }
          }
        }
      }
      .frame(height: 56)
      .padding(.horizontal, 16)
      .padding(.top, 12)
    }
  }

  // MARK: Private

  @Environment(ColorStore.self) private var store
}

#Preview {
  let store = ColorStore(initialInput: "#3b82f6")
  store.remember()
  store.inputText = "rebeccapurple"
  store.remember()
  return RecentsRow()
    .environment(store)
    .frame(width: 520)
}
