//
//  ContentView.swift
//  ColorKit
//
//  Created by Parker Sprouse on 7/23/26.
//

// For the preview's `.modelContainer` only — this view has no persistence of its own,
// and `ProjectsPanel` still owns the app's only `@Query` and `modelContext`.
import SwiftData
import SwiftUI

struct ContentView: View {
  // MARK: Internal

  var body: some View {
    @Bindable var store = store

    return HStack(spacing: 0) {
      // M36's replacement for the old segmented `Picker` above — see `ToolSidebar`
      // for why it is a vertical, collapsible rail instead and for why it is a
      // hand-rolled `HStack` rather than `NavigationSplitView`.
      ToolSidebar()

      Divider()

      VStack(spacing: 0) {
        // M36: the settings that used to live only behind the toolbar's gear now
        // get a wider stage when the window has room to spare. See
        // `InlineSettingsBar` for why this sits in the body rather than back in
        // `.toolbar`.
        InlineSettingsBar()

        // Above every tool panel deliberately: the input field belongs to no tool.
        // Every tool is a different question asked about the same color, so moving
        // it inside a tab would imply each one has a color of its own.
        //
        // Recents used to sit right below this (M23–M36). M37 moved `RecentsRow`
        // into `ToolSidebar`, below the tool rows — see its doc comment for why.
        ColorInputField()
          .padding(.horizontal, 16)
          .padding(.vertical, 12)

        Divider()

        switch store.tool {
        case .convert:
          if store.color != nil {
            ConversionPanel()
          } else {
            ContentUnavailableView(
              "No color yet",
              systemImage: "eyedropper.halffull",
              description: Text("Type a CSS color above and every other format appears here."),
            )
          }
        case .pick:
          PickerPanel()
        case .transform:
          TransformPanel()
        case .contrast:
          ContrastPanel()
        case .cvd:
          CVDPanel()
        case .projects:
          ProjectsPanel()
        case .export:
          ExportPanel()
        }
      }
    }
    // The sidebar's own width varies with its collapse state, and the content
    // column was tuned against the pre-M36 520pt minimum — so the window's floor
    // has to track the sidebar rather than assume its widest (or narrowest) state.
    // Without this, collapsing the sidebar would let the window shrink well below
    // what the content column was ever designed to fit into.
    .frame(
      minWidth: sidebarWidth + 520,
      minHeight: 460,
    )
    // See `MenuBarLabel` — the shortcut is claimed from whichever scene appears
    // first, because neither scene is guaranteed to be on screen.
    .task { store.activateGlobalShortcut() }
  }

  // MARK: Private

  @Environment(ColorStore.self) private var store

  private var sidebarWidth: CGFloat {
    store.sidebarCollapsed ? ToolSidebar.Metrics.collapsedWidth : ToolSidebar.Metrics.expandedWidth
  }
}

/// Serialization settings, now reachable both from ``InlineSettingsBar`` (M36) and
/// from this gear — see that file for why it moved out of `.toolbar` rather than
/// picking up neighbors there.
///
/// These change every row in the panel at once, which is why they live here rather
/// than per-row: precision and legacy syntax are properties of how *you* write CSS,
/// not of any one color.
struct OutputOptionsMenu: View {
  // MARK: Internal

  var body: some View {
    @Bindable var store = store

    Menu {
      Toggle("Legacy comma syntax", isOn: $store.formatOptions.legacy)
        .help("Writes rgb(255, 0, 0) and hsl(). Other functions have no legacy form.")
      Toggle("rgb() as percentages", isOn: $store.formatOptions.rgbAsPercentage)

      Section("hex") {
        Toggle("Uppercase", isOn: $store.formatOptions.uppercaseHex)
        Toggle("Shorten when possible", isOn: $store.formatOptions.collapseHex)
      }

      // Named levels rather than decimal counts, because precision is
      // relative to each component's scale — "4 decimals" would be true of
      // an OKLCH lightness and a lie about a hue in the same row.
      Picker("Decimal Precision", selection: $store.formatOptions.precision) {
        Text("Minimum").tag(2)
        Text("Normal").tag(4)
        Text("Increased").tag(6)
        Text("Maximum").tag(10)
      }
      .pickerStyle(.inline)

      Picker("Out of gamut", selection: $store.formatOptions.gamut) {
        Text("Map into gamut").tag(CSSFormatOptions.GamutPolicy.map)
        Text("Keep original values").tag(CSSFormatOptions.GamutPolicy.preserve)
      }
      .pickerStyle(.inline)

      Picker("Alpha", selection: $store.formatOptions.alpha) {
        Text("Only when transparent").tag(CSSFormatOptions.AlphaPolicy.whenNotOpaque)
        Text("Always").tag(CSSFormatOptions.AlphaPolicy.always)
        Text("Never").tag(CSSFormatOptions.AlphaPolicy.never)
      }
      .pickerStyle(.inline)
    } label: {
      Label("Output options", systemImage: "slider.horizontal.3")
    }
  }

  // MARK: Private

  @Environment(ColorStore.self) private var store
}

#Preview {
  ContentView()
    .environment(ColorStore(initialInput: "oklch(0.7 0.15 250)"))
    // The switcher can reach Projects, whose `@Query` has no container to read
    // without this — a preview that crashes the moment a tab is clicked. In memory,
    // so a preview never writes into the real library, matching the two previews
    // that show `ProjectsPanel` directly.
    .modelContainer(PersistenceStack.make(inMemory: true).container)
}
