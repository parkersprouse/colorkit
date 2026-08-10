//
//  ExportPresentation.swift
//  ColorKit
//

import SwiftUI

/// Which of the app's colors an export is written from.
///
/// Lives here rather than in ColorCore because it is a question about *this app's
/// state* — what the store happens to be holding — not about CSS. ColorCore takes a
/// `[PaletteEntry]` and neither knows nor cares whether it came from a ramp or from
/// the recents list.
///
/// ``saved`` arrived with M9 and is the case M8 declined to invent early. It is also the
/// only source that does not read the input field: the other four are derived from
/// whatever is being edited right now, and a palette pulled out of a project is a set
/// that was chosen earlier and stands on its own.
nonisolated enum ExportSource: String, CaseIterable, Identifiable, Sendable {
  case color
  case harmony
  case ramp
  case recents
  case saved
  /// A whole project's palettes and loose colors, staged by `ProjectsPanel`'s Export
  /// Project button as ``PaletteGroup``s rather than a single flat list — see M20 in
  /// PLAN.md. Otherwise parallel to ``saved``: it does not read the input field either,
  /// since a project export is a set assembled earlier.
  case project

  // MARK: Internal

  var id: String {
    rawValue
  }

  /// Short, and shorter than it wants to be. These are the segments of a segmented
  /// control, which divides its width evenly — so "Saved palette" would make every other
  /// option pay for it, and a fifth segment is already the point where that starts to
  /// bite.
  var title: String {
    switch self {
    case .color: "This color"
    case .harmony: "Harmony"
    case .ramp: "Ramp"
    case .recents: "Recents"
    case .saved: "Saved"
    case .project: "Project"
    }
  }

  /// What to say when this source names no colors.
  ///
  /// Per source, because two of them can now be empty for entirely different reasons and
  /// a single line cannot be true of both — telling somebody that "recents fill up as
  /// you copy colors" when what they are missing is a staged palette is the same defect
  /// as M8's placeholder that disagreed with its own fallback.
  var emptyMessage: String {
    switch self {
    case .color, .harmony, .ramp:
      "Type a CSS color above and it can be exported from here."
    case .recents:
      "Nothing to export yet — recents fill up as you copy and sample colors."
    case .saved:
      "No palette staged. Open Projects and choose Export on a saved palette."
    case .project:
      "No project staged. Open Projects and choose Export Project."
    }
  }
}

/// - Note: `nonisolated` for the reason ``FormatSection`` gives — these are plain data,
///   and the app target's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` would otherwise
///   put a string constant behind an actor hop.
nonisolated extension ExportShape {
  var title: String {
    switch self {
    case .declaration: "Declarations"
    case .customProperties: "Custom properties"
    case .json: "JSON"
    case .tailwindTheme: "Tailwind v4"
    case .tailwindConfig: "Tailwind v3"
    case .p3WithFallback: "P3 with fallback"
    case .designTokens: "Design tokens (DTCG)"
    }
  }

  /// What the shape is for, in one line. The Tailwind pair need it most: which one you
  /// want is decided by your project's major version and by nothing else, and "v4" alone
  /// does not say that v4 configures colors in CSS rather than JavaScript.
  var summary: String {
    switch self {
    case .declaration:
      "Bare declarations to paste inside a rule."
    case .customProperties:
      "A :root block. The portable answer, and what var() reads."
    case .json:
      "CSS strings under their keys, for anything that is not a stylesheet."
    case .tailwindTheme:
      "@theme in your CSS entry point. Tailwind v4 configures colors here."
    case .tailwindConfig:
      "tailwind.config.js, under theme.extend so the stock palette survives."
    case .p3WithFallback:
      "Hex for everyone, then the same properties in Display P3 behind "
        + "@media (color-gamut: p3). Fixed formats — the fallback has to be hex."
    case .designTokens:
      "$value objects, one per color, each in the space it was authored in — what "
        + "Figma and Style Dictionary consume."
    }
  }

  /// What to say above a preview whose values the chosen format could not carry as
  /// written.
  ///
  /// Editorial copy, so it lives here rather than in ColorCore — but the *count* comes
  /// from ``ExportOptions/mappedCountFormat``, and the two have to be decided together.
  /// ``p3WithFallback`` needs its own sentence because the generic one is false of it:
  /// "the values below were brought into gamut" is true of the fallback block and wrong
  /// about the `@media` block sitting underneath it, which is written in a wider gamut.
  ///
  /// **The wording stops at which block writes what, and deliberately promises nothing
  /// about exactness.** The count is measured against hex, so it includes colors outside
  /// *P3* as well — and those are mapped in **both** blocks under the app's default gamut
  /// policy. An earlier draft said the `@media` block "carries them exactly", which is a
  /// claim this shape cannot make about every color it counts, and false three lines above
  /// the value it describes. Saying only that the override is written in Display P3 is
  /// true either way. ``ExportShapeTests`` pins the fact the stronger claim denied.
  ///
  /// - Parameter format: ``ExportOptions/mappedCountFormat``, not
  ///   ``ExportOptions/format`` — for this shape they differ, and naming the user's
  ///   selection would name a format the document does not contain.
  func mappedNote(count: Int, format: CSSOutputFormat) -> String {
    let colors = count == 1 ? "one of these colors" : "\(count) of these colors"
    switch self {
    case .p3WithFallback:
      let them = count == 1 ? "it" : "them"
      return "Hex cannot express \(colors), so the fallback block rounds \(them); the "
        + "@media block writes \(them) in Display P3."
    case .declaration, .customProperties, .json, .tailwindTheme, .tailwindConfig:
      return "\(format.title) cannot express \(colors), so the values below were "
        + "brought into gamut."
    case .designTokens:
      // Unreachable in practice — `ExportPanel` only calls this once `mapped > 0`,
      // and `ExportOptions.mappedCountFormat` is `nil` for this shape, so
      // `exportGamutMappedCount` is always `0` here. Written as a real sentence
      // that still varies with `count` (`colors` already does) rather than a
      // placeholder, on the chance something upstream ever calls this without that
      // guard — and so it reads like every other shape's note beside it rather than
      // standing out as the one that does not bother.
      return "Design tokens keep \(colors) in the space each was authored in, "
        + "never brought into gamut."
    }
  }
}

nonisolated extension ExportTemplate {
  /// The property name, which is already the clearest possible label for it. Written
  /// with its colon so the picker reads as the CSS it produces.
  var title: String {
    "\(property):"
  }
}
