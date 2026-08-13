//
//  RecentsRow.swift
//  ColorKit
//

import SwiftUI

/// The colors you've already worked with, one tap to bring them back.
///
/// **M37 moved this from a horizontal strip above the tool switcher into
/// `ToolSidebar`, below the tool rows** — a sibling of the switcher rather than a
/// neighbor of the input field. That is a real change of argument, not just of pixels:
/// M23 put this beside `ColorInputField` on the reasoning that "a recent belongs to no
/// tool, so it lives with the other thing that doesn't either." M37 reads it the other
/// way — a recent is a *destination* you jump to, the same category the tool rows
/// above it already are, so it belongs with navigation rather than with the field. See
/// the M37 entry in PLAN.md for the fuller argument.
///
/// Gated on ``ColorStore/showsRecents`` alone, never on whether the list happens to be
/// empty — this app has already been bitten once (M23) by a section that only
/// materializes once something is in it, so an empty-state line still renders in its
/// place. What is new at M37: the header hides under ``ColorStore/sidebarCollapsed``
/// (there is no room to print "Recent Colors" on a 52pt rail) while the swatches
/// themselves keep rendering at whatever width the sidebar currently is — a collapsed
/// rail narrows the bars, it does not hide them, the same "icon rail, not fully
/// hidden" call M36 made for the tool rows.
struct RecentsRow: View {
  // MARK: Internal

  var body: some View {
    if store.showsRecents {
      VStack(alignment: .leading, spacing: 6) {
        if !store.sidebarCollapsed {
          header
        }

        if store.recents.isEmpty {
          if !store.sidebarCollapsed {
            Text("Colors you copy or submit collect here.")
              .font(.caption)
              .foregroundStyle(.tertiary)
          }
        } else {
          list
        }
      }
      // Fills whatever the tool rows above it left — the same "no fixed footprint
      // to jump under a click" discipline as M23's original fixed `height: 56`, just
      // expressed as "take the rest" instead of "take this much" now that this sits
      // below a variable-height sibling instead of above a fixed one.
      .frame(maxHeight: .infinity, alignment: .top)
    }
  }

  // MARK: Private

  @Environment(ColorStore.self) private var store

  private var header: some View {
    HStack {
      Text("Recent Colors")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      Spacer(minLength: 0)
      if !store.recents.isEmpty {
        Button("Clear") { store.clearRecents() }
          .buttonStyle(.plain)
          .font(.caption)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("clearRecents")
      }
    }
  }

  /// A vertical, full-width list rather than M23's horizontal scroller — the sidebar
  /// is a column, not a row, and "most recent on top" is `store.recents` order as-is:
  /// `ColorStore.remember()` inserts at index 0, so no reversal is needed here.
  ///
  /// Scrolls on its own rather than pushing the window taller, since
  /// ``ColorStore/recentLimit`` goes up to 50 and this section only ever has whatever
  /// height the tool rows above it left.
  private var list: some View {
    ScrollView(.vertical, showsIndicators: false) {
      VStack(spacing: 4) {
        ForEach(store.recents) { recent in
          // The authored-text initializer (M21), so a click returns *your* spelling
          // rather than a canonicalized one — the same contract `MenuBarPanel`'s own
          // recents grid makes, and deliberately not filtered by
          // ``ColorStore/webFriendly`` (M22): a recent's text is prior input, and the
          // mode hides output, it does not reject input.
          SwatchButton(
            color: recent.color,
            text: recent.text,
            cornerRadius: 5,
            checkerSize: 4,
            accessibilityIdentifier: "recentColor-\(recent.id)",
          )
          .frame(maxWidth: .infinity)
          .frame(height: 28)
          .help(recent.text)
        }
      }
    }
  }
}

#Preview {
  let store = ColorStore(initialInput: "#3b82f6")
  store.remember()
  store.inputText = "rebeccapurple"
  store.remember()
  return RecentsRow()
    .environment(store)
    .frame(width: 176, height: 300)
}
