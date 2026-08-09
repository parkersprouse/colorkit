//
//  SchemaVersions.swift
//  ColorKit
//

import Foundation
import SwiftData

/// The store's schema, versioned, and the plan for moving between versions.
///
/// **Nothing here migrates anything yet, and that is the point.** SwiftData handles
/// additive changes — a new property, a new model — on its own, with or without a
/// `VersionedSchema`. What it cannot do on its own is a *destructive* change: a property
/// removed, or retyped, or split in two. The first of those needs a custom
/// ``MigrationStage``, and a stage needs a previous version to migrate *from*.
///
/// Introducing the machinery at the same moment as the first destructive change means
/// writing the version boundary and the data transformation together, against a store
/// whose old shape is no longer in the source tree to check against. Declaring V1 now,
/// while it is still exactly what shipped, costs one file and makes that future change a
/// matter of adding a case rather than reconstructing history.
///
/// So this is insurance, not a feature. Do not write a test that asserts the empty stage
/// list "works" — it would pass against a plan that migrates nothing, which is what it
/// already is.
///
/// ## Adding a version
///
/// 1. Copy the model types into a `ColorKitSchemaV2` enum, edited.
/// 2. Add it to ``ColorKitMigrationPlan/schemas``, newest last.
/// 3. Add a `MigrationStage` — `.lightweight` if the change is purely additive,
///    `.custom` if data has to be rewritten.
/// 4. Point ``PersistenceStack/schema`` at the new version.
enum ColorKitSchemaV1: VersionedSchema {
  nonisolated static let versionIdentifier = Schema.Version(1, 0, 0)

  nonisolated static var models: [any PersistentModel.Type] {
    [Project.self, Palette.self, SavedColor.self]
  }
}

/// The ordered list of schema versions, and how to get from each to the next.
///
/// `stages` is empty because `schemas` has one entry: there is nowhere to migrate from.
enum ColorKitMigrationPlan: SchemaMigrationPlan {
  nonisolated static var schemas: [any VersionedSchema.Type] {
    [ColorKitSchemaV1.self]
  }

  nonisolated static var stages: [MigrationStage] {
    []
  }
}
