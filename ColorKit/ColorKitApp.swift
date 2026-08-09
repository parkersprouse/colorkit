//
//  ColorKitApp.swift
//  ColorKit
//
//  Created by Parker Sprouse on 7/23/26.
//

import SwiftData
import SwiftUI

enum WindowID {
  static let main = "main"
}

/// What kind of projects store the app opened. See ``PersistenceStack/Status``.
///
/// An environment value rather than a property on ``ColorStore``, because it is a fact
/// about how the *app* was launched rather than app state — nothing can change it, and
/// only one view ever reads it.
extension EnvironmentValues {
  @Entry var projectStoreStatus = PersistenceStack.Status.persistent
}

@main
struct ColorKitApp: App {
  // MARK: Internal

  var body: some Scene {
    // `Window` rather than `WindowGroup`: this is one workspace, not a document
    // type, so several independent copies of it would only fragment the recents
    // list and the current color.
    Window("ColorKit", id: WindowID.main) {
      ContentView()
        .environment(store)
        .environment(\.projectStoreStatus, persistence.status)
        // The window is the scene most likely to be open, so it is the primary place
        // a settings change gets written back — but not the only one. See the same
        // modifier on `MenuBarLabel`.
        .onChange(of: store.preferences) { _, updated in
          PreferenceStore.save(updated)
        }
    }
    .defaultSize(width: 620, height: 700)
    .modelContainer(persistence.container)

    MenuBarExtra {
      MenuBarPanel()
        .environment(store)
    } label: {
      MenuBarLabel()
        .environment(store)
    }
    .menuBarExtraStyle(.window)
    // The same container, for the same reason both scenes share one `ColorStore`: two
    // containers over one store would compile and then disagree, and a project created
    // in one would be invisible to the other until something forced a refetch.
    .modelContainer(persistence.container)

    Settings {
      SettingsView()
        .environment(store)
    }
  }

  // MARK: Private

  /// One store, shared by both scenes.
  ///
  /// Constructing it separately per scene would compile cleanly and then silently
  /// diverge: colors filed from the menu bar would never reach the window, and the
  /// two would disagree about what the current color even is.
  ///
  /// Loaded with whatever ``PreferenceStore`` last saved, rather than plain
  /// `ColorStore()`. That happens here and not inside `ColorStore.init` on purpose: the
  /// plain initializer is what every unit test constructs, and loading real
  /// `UserDefaults` into it would make a fresh `ColorStore()`'s `pickerMode` depend on
  /// whichever preferences happen to be sitting on the machine running the test.
  @State private var store: ColorStore = {
    let store = ColorStore()
    store.preferences = PreferenceStore.load()
    // A bare launch argument, like `UITestEphemeralPreferences` beside it — a UI test
    // has no way to reach the Settings scene's Toggle (M22, and no test drives that
    // window yet), so this is the seam that lets a suite start with web-friendly mode
    // already on without going through it.
    if ProcessInfo.processInfo.arguments.contains("UITestWebFriendly") {
      store.webFriendly = true
    }
    return store
  }()

  /// Built once, here, rather than by `.modelContainer(for:)` on each scene — that
  /// modifier makes a container per call site.
  @State private var persistence = PersistenceStack.make()
}

/// The menu bar icon, which doubles as the only feedback a global capture gets.
///
/// Pressing the shortcut from another app shows the loupe, takes a click, and then —
/// without this — nothing visible happens, because the app that captured the color is
/// not the one the user is looking at. A brief checkmark on the icon says the color
/// landed, needs no notification permission, and costs no window.
struct MenuBarLabel: View {
  // MARK: Internal

  var body: some View {
    Image(systemName: store.justCaptured ? "checkmark.circle.fill" : "eyedropper.halffull")
      // One of two places the shortcut is claimed. Both are needed and neither is
      // redundant: this view exists unless the user hides the menu bar item, the
      // window's exists unless the window is closed, and `activateGlobalShortcut`
      // is idempotent so whichever appears first wins.
      .task { store.activateGlobalShortcut() }
      // The other of two places preferences are saved — see the same modifier on the
      // window's content. This one is what covers a settings change made while the
      // main window is closed, since this label exists as long as the menu bar item
      // does. Saving twice for one change is harmless: `PreferenceStore.save` just
      // overwrites the same key with an equal value.
      .onChange(of: store.preferences) { _, updated in
        PreferenceStore.save(updated)
      }
  }

  // MARK: Private

  @Environment(ColorStore.self) private var store
}
