//
//  SettingsView.swift
//  ColorKit
//

import SwiftUI

/// The app's `Settings` scene (⌘,).
///
/// Five sections: General, Shortcuts, Command Line Tool, Output, and a reset. **Output
/// duplicates `OutputOptionsMenu`'s seven controls rather than replacing them** — the
/// same precedent the export panel's own Decimal Precision picker already set, documented at
/// ``ColorStore/formatOptions``. Both are surfaces onto the one set of bindings, so
/// changing precision here and in the toolbar menu can never disagree.
///
/// **Command Line Tool (M29) never shows "Installed ✓."** `installOutcome` is plain
/// `@State` — an ephemeral, this-click-only confirmation, not a persisted preference —
/// because the sandbox gives the app no honest way to re-verify on a later launch that
/// a symlink it created earlier still exists. See ``CommandLineToolInstaller`` and the
/// M29 entry in PLAN.md.
struct SettingsView: View {
  // MARK: Internal

  var body: some View {
    @Bindable var store = store

    Form {
      Section("General") {
        Toggle("Web-friendly mode", isOn: $store.webFriendly)
          .help("Hides less common formats and keeps every value inside sRGB to maintain web compatibility.")
        Toggle("Show recents", isOn: $store.showsRecents)
        Stepper(
          "Recent colors kept: \(store.recentLimit)",
          value: $store.recentLimit,
          in: 1 ... 50,
        )
      }

      Section("Shortcuts") {
        ShortcutRecorderField()
      }

      Section("Output") {
        Toggle("Legacy comma syntax", isOn: $store.formatOptions.legacy)
          .help("Writes rgb(255, 0, 0) and hsl(). Other functions have no legacy form.")
        Toggle("rgb() as percentages", isOn: $store.formatOptions.rgbAsPercentage)
        Toggle("Uppercase hex", isOn: $store.formatOptions.uppercaseHex)
        Toggle("Shorten hex when possible", isOn: $store.formatOptions.collapseHex)

        // Named levels rather than decimal counts, same as the toolbar menu:
        // precision is relative to each component's scale, so "4 decimals" is not
        // one fact about every row.
        Picker("Decimal Precision", selection: $store.formatOptions.precision) {
          Text("Minimum").tag(2)
          Text("Normal").tag(4)
          Text("Increased").tag(6)
          Text("Maximum").tag(10)
        }

        Picker("Out of gamut", selection: $store.formatOptions.gamut) {
          Text("Map into gamut").tag(CSSFormatOptions.GamutPolicy.map)
          Text("Keep original values").tag(CSSFormatOptions.GamutPolicy.preserve)
        }

        Picker("Alpha", selection: $store.formatOptions.alpha) {
          Text("Only when transparent").tag(CSSFormatOptions.AlphaPolicy.whenNotOpaque)
          Text("Always").tag(CSSFormatOptions.AlphaPolicy.always)
          Text("Never").tag(CSSFormatOptions.AlphaPolicy.never)
        }
      }

      Section("Command Line Tool") {
        VStack(spacing: 8) {
          HStack(alignment: .center, spacing: 8) {
            Text("colorkit")
              .monospaced()
              .font(.system(size: 12))
            
            Spacer()
            
            Button("Install…") { runInstall() }
              .accessibilityIdentifier("installColorkit")
          }
          .help("Adds a colorkit command you can run from the command line.")
          
          if let installOutcome {
            HStack() {
              Text(installOutcome.message)
                .font(.caption)
                .foregroundStyle(installOutcome.isSuccess ? Color.init(hue: 0.37, saturation: 0.75, brightness: 0.75, opacity: 1) : Color.orange)
                .textSelection(.enabled)
                .accessibilityIdentifier("installOutcome")
              
              Spacer()
            }
          }
        }
      }
      
      Section {
        Button("Reset to Defaults", role: .destructive) {
          store.preferences = Preferences()
        }
      }
    }
    .formStyle(.grouped)
    .frame(width: 420)
    .padding(.vertical, 8)
  }

  // MARK: Private

  @Environment(ColorStore.self) private var store
  @State private var installOutcome: CommandLineToolInstaller.InstallOutcome?

  /// Defaults the picker to `/usr/local/bin` — settled with Parker rather than left to
  /// whatever `NSOpenPanel` would otherwise propose.
  private func runInstall() {
    // Cleared on every click, not just a successful one — a stale message from a
    // previous attempt is not "ongoing truth" this click has anything to do with.
    installOutcome = nil

    guard let chosen = CommandLineToolInstaller.presentDestinationPicker(
      startingAt: URL(fileURLWithPath: "/usr/local/bin"),
    ) else {
      return // Canceled: nothing to say.
    }

    installOutcome = CommandLineToolInstaller.install(
      embeddedBinary: CommandLineToolInstaller.embeddedBinaryURL(inBundleAt: Bundle.main.bundleURL),
      into: chosen,
    )
  }
}

#Preview {
  SettingsView()
    .environment(ColorStore())
}
