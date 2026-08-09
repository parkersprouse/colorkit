//
//  PersistenceStack.swift
//  ColorKit
//

import Foundation
import SwiftData

/// The app's SwiftData container, and the two decisions that come with building one.
///
/// **One container, attached to both scenes** — the same rule ``ColorStore`` follows.
/// Two containers over one store would compile and then fight: a project created from
/// the menu bar would be invisible to the window until something forced a refetch.
///
/// **A UI test must never write to the real store.** XCUITest launches the shipping app,
/// so a test that saves a project would deposit it in the user's own library and leave it
/// there — and the next run would find it. The launch argument is the only way in: the
/// app is a separate process, so nothing else a test does can reach this decision.
enum PersistenceStack {
  /// What kind of store the app ended up with.
  ///
  /// Three cases rather than an `isEphemeral` flag, because two of them are ephemeral for
  /// opposite reasons and only one is worth telling anyone about. The first draft
  /// conflated them, and the UI-test screenshots showed the app announcing that the store
  /// "could not be opened" during a run that had *asked* for a throwaway one — a banner
  /// stating something false, which is precisely what a warning must never do.
  enum Status: Sendable, Hashable {
    /// The real store, on disk.
    case persistent
    /// A throwaway store, because a UI test asked for one. Nothing to report: this is
    /// the store working as instructed.
    case ephemeralByRequest
    /// The on-disk store could not be opened, so saving will not outlive the session.
    /// The one case the panel warns about.
    case unavailable
  }

  /// Passed by ``XCUIApplication`` in the UI tests to get a store that evaporates.
  ///
  /// No leading hyphen, deliberately: `NSUserDefaults` claims the argument domain for
  /// anything starting with `-` and would read the next argument as its value.
  static let inMemoryLaunchArgument = "UITestInMemoryStore"

  /// Built from ``ColorKitSchemaV1`` rather than a bare model list, so the store
  /// records which version wrote it. See that type for why the migration plan is empty.
  static let schema = Schema(versionedSchema: ColorKitSchemaV1.self)

  /// Whether this process was launched by a UI test.
  static var wantsInMemoryStore: Bool {
    ProcessInfo.processInfo.arguments.contains(inMemoryLaunchArgument)
  }

  /// The container, and why it is the one it is.
  ///
  /// The fallback is deliberate and so is reporting it. A store that will not open —
  /// corrupt, or written by a version that knows a model this build does not — leaves
  /// two choices: refuse to launch, or run without persistence. For a tool opened dozens
  /// of times a day the second is far better, *provided it says so*: silently accepting
  /// saves that vanish at quit would be the worst of the three.
  static func make(inMemory: Bool = wantsInMemoryStore) -> (container: ModelContainer, status: Status) {
    if !inMemory {
      let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
      if let container = try? ModelContainer(for: schema, configurations: configuration) {
        return (container, .persistent)
      }
    }

    let ephemeral = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    guard let container = try? ModelContainer(for: schema, configurations: ephemeral) else {
      // An in-memory container failing means the schema itself is invalid — a
      // relationship SwiftData cannot resolve, say. That is a build-time mistake
      // wearing a runtime costume, and there is nothing sensible to run without.
      // `ProjectStoreTests` asserts the container builds precisely so this line is
      // unreachable in a shipped build.
      fatalError("The SwiftData schema is invalid; no container could be created.")
    }
    return (container, inMemory ? .ephemeralByRequest : .unavailable)
  }
}
