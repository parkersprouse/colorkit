//
//  ColorRecord.swift
//  ColorKit
//

import Foundation

/// A `ColorValue` flattened into the fields a store can query, plus the spelling that
/// produced it.
///
/// This is the whole bridge between ColorCore and SwiftData, and it is a plain value
/// type on purpose: the mapping is the part most likely to be wrong, and a value type
/// lets every claim about it be asserted without standing up a `ModelContainer`.
/// ``SavedColor`` stores these fields flat rather than holding a `ColorRecord`, because
/// flat columns are what makes a store *queryable* — "every oklch color in this project"
/// is a predicate over `spaceID`, and a blob is not.
///
/// **Why not `Codable` into a `Data` column.** `ColorValue` is `Codable`, so a one-line
/// blob is available and would be inspectable by nothing. That is the same reasoning
/// that made the export layer hand-write its JSON rather than encode the model.
///
/// **Why the text is stored too.** ``RecentColor`` already carries its authored text for
/// a reason that applies twice over here: re-deriving a spelling from a `ColorValue`
/// hands back a canonicalized one, so a saved `rebeccapurple` would come back
/// `#663399` — the app quietly rewriting something the user typed and then kept. The
/// components remain the *value*; the text is only how it was written. They are two
/// spellings of one claim, so ``ColorRecordTests`` requires that parsing the text
/// reproduces the components.
nonisolated struct ColorRecord: Hashable, Sendable {
  // MARK: Lifecycle

  init(_ color: ColorValue, text: String) {
    spaceID = color.space.rawValue
    c0 = color.components.x
    c1 = color.components.y
    c2 = color.components.z
    alpha = color.alpha
    missingMask = Int(color.missing.rawValue)
    self.text = text
  }

  init(
    spaceID: String,
    c0: Double,
    c1: Double,
    c2: Double,
    alpha: Double,
    missingMask: Int,
    text: String,
  ) {
    self.spaceID = spaceID
    self.c0 = c0
    self.c1 = c1
    self.c2 = c2
    self.alpha = alpha
    self.missingMask = missingMask
    self.text = text
  }

  // MARK: Internal

  /// ``ColorSpace``'s raw value — `oklch`, `display-p3`. The CSS name, so a store opened
  /// in any other tool reads as the spec rather than as this app's enum ordering.
  var spaceID: String

  var c0: Double
  var c1: Double
  var c2: Double
  var alpha: Double

  /// ``ComponentMask``'s raw value, widened to `Int` because that is what SwiftData
  /// stores natively. Dropping it would make a saved `oklch(0.7 0.2 none)` come back
  /// with a hue of zero, which is a different color and says so nowhere.
  var missingMask: Int

  /// The spelling this color was authored in. See the type's note.
  var text: String

  /// The color these fields describe, or `nil` if `spaceID` names no space this build
  /// knows.
  ///
  /// Optional rather than defaulted, because the alternative is inventing a color for a
  /// row whose meaning was lost — a store written by a later version, or hand-edited.
  /// Callers skip what they cannot read; nothing here force-unwraps data it did not
  /// create.
  var colorValue: ColorValue? {
    guard let space = ColorSpace(rawValue: spaceID) else { return nil }
    return ColorValue(
      space: space,
      c0,
      c1,
      c2,
      alpha: alpha,
      // Only four bits are defined, so a wider value is truncated rather than trusted.
      missing: ComponentMask(rawValue: UInt8(truncatingIfNeeded: missingMask) & 0b1111),
    )
  }

  /// A record for a color with no authored text of its own — a harmony member, a ramp
  /// stop, an eyedropper sample.
  ///
  /// Spelled with ``CSSFormatOptions/lossless`` and ``ColorValue/spelling(preferring:)``
  /// for the reason ``ColorStore/adopt(_:preferring:)`` gives: this string is what a
  /// recalled color is typed back as, so anything the spelling rounds away is gone. The
  /// user's display precision governs what panels *show* and must not reach storage.
  static func derived(_ color: ColorValue, preferring format: CSSOutputFormat = .hex) -> ColorRecord {
    ColorRecord(
      color,
      text: color.cssStringOrHex(as: color.spelling(preferring: format), options: .lossless),
    )
  }
}
