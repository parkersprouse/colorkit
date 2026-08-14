//
//  ToolSidebar.swift
//  ColorKit
//

import SwiftUI

/// M36's vertical tool switcher, replacing the segmented `Picker` that used to sit
/// above every panel. Modeled on the Claude Code desktop app's own sidebar: full rows
/// (icon + label) when expanded, an icon-only rail when collapsed, and a toggle at the
/// top rather than a drag handle — there is nothing here to resize, only to show or
/// hide.
///
/// Hand-rolled `HStack` in `ContentView`, not `NavigationSplitView` — a
/// `NavigationSplitView` wants to own the window's toolbar and renders a native
/// sidebar `List`, and this app already has one toolbar-shaped bug on file (the old
/// segmented picker's "more toolbar items" overflow, see `ContentView`'s history in
/// PLAN.md). A second, less-inspectable layout container is the wrong tool to risk
/// repeating it with.
///
/// Every row is a real `Button` queried by `.accessibilityIdentifier("tool-\(rawValue)")`
/// rather than by its label — the collapsed rail has no `Text` for XCUITest to match
/// against, and `Tool.title` is supplied separately as the accessibility label so
/// VoiceOver still announces "Convert" rather than an SF Symbol name (see the
/// `Tool.title` doc comment, and the segmented-picker bug it was written against).
///
/// **M37 added `RecentsRow` below the tool rows** — see its own doc comment for why
/// recents moved here from above the tool switcher, rather than adding a new
/// invariant to this one.
struct ToolSidebar: View {
  // MARK: Internal

  /// Not `private` — `ContentView` reads both widths to size the window's own
  /// `minWidth` against whichever one is currently showing, so the content column
  /// keeps the same effective width the sidebar's collapse state left it before.
  enum Metrics {
    static let collapsedWidth: CGFloat = 52
    static let expandedWidth: CGFloat = 176
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      collapseToggle
      
      Divider()
        .padding(.vertical, 8)

      ForEach(Tool.allCases) { tool in
        row(for: tool)
      }

      // M37: recents moved here from above the tool switcher — see `RecentsRow`'s
      // doc comment for the argument. `RecentsRow` renders nothing at all when
      // `showsRecents` is off, which is exactly when this sidebar still wants the
      // old `Spacer`-only behavior to hold the tool rows at the top.
      if store.showsRecents {
        Divider()
          .padding(.vertical, 8)
        RecentsRow()
      } else {
        Spacer(minLength: 0)
      }
    }
    .padding(.horizontal, store.sidebarCollapsed ? 8 : 10)
    .padding(.top, 14)
    .frame(width: store.sidebarCollapsed ? Metrics.collapsedWidth : Metrics.expandedWidth)
    .frame(maxHeight: .infinity, alignment: .top)
    // A real macOS sidebar material, not a guessed flat color — it is theme-aware by
    // construction, so there is no light/dark fork to get wrong, unlike a hand-picked
    // `Color`. Without it the sidebar and the content column were the same fill with
    // only a `Divider()` between them, which reads as one panel with a stray line in
    // it rather than as a sidebar.
    .background(.regularMaterial)
    .animation(.easeInOut(duration: 0.16), value: store.sidebarCollapsed)
  }

  // MARK: Private

  @Environment(ColorStore.self) private var store

  private var collapseToggle: some View {
    HStack(spacing: 10) {
      Button {
        store.sidebarCollapsed.toggle()
      } label: {
        Image(systemName: "sidebar.left")
          .frame(width: 20)
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)
      .accessibilityIdentifier("toggleSidebar")
      .accessibilityLabel(store.sidebarCollapsed ? "Expand Sidebar" : "Collapse Sidebar")
      .help(store.sidebarCollapsed ? "Expand Sidebar" : "Collapse Sidebar")
    }
    .padding(.horizontal, store.sidebarCollapsed ? 0 : 8)
    .frame(maxWidth: .infinity, alignment: store.sidebarCollapsed ? .center : .trailing)
    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
  }

  private func row(for tool: Tool) -> some View {
    let isSelected = store.tool == tool

    return Button {
      store.tool = tool
    } label: {
      HStack(spacing: 10) {
        Image(systemName: tool.systemImage)
          .frame(width: 20)
        if !store.sidebarCollapsed {
          Text(tool.title)
          Spacer(minLength: 0)
        }
      }
      .padding(.vertical, 7)
      .padding(.horizontal, store.sidebarCollapsed ? 0 : 8)
      .frame(maxWidth: .infinity, alignment: store.sidebarCollapsed ? .center : .leading)
      .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
    .buttonStyle(.plain)
    .background(
      isSelected ? Color.accentColor.opacity(0.16) : .clear,
      in: RoundedRectangle(cornerRadius: 7, style: .continuous),
    )
    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
    .accessibilityIdentifier("tool-\(tool.rawValue)")
    .accessibilityLabel(tool.tooltip)
    .help(tool.tooltip)
  }
}

#Preview {
  let store = ColorStore(initialInput: "#3b82f6")
  store.remember()
  store.inputText = "rebeccapurple"
  store.remember()
  return HStack(spacing: 0) {
    ToolSidebar()
    Divider()
    Color.clear
  }
  .frame(width: 500, height: 500)
  .environment(store)
}
