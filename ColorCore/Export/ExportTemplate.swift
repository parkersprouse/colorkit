//
//  ExportTemplate.swift
//  ColorKit
//

import Foundation

/// One color in a palette, under the key it will be written out as.
///
/// The key is a *suffix*, not a full name: ``ExportOptions/name`` supplies the family
/// (`brand`) and this supplies the position within it (`500`), so the two compose into
/// `--brand-500` for CSS and `brand: { 500: … }` for Tailwind. An empty key means the
/// palette has one member and no position to name — a lone color is `--brand`, not
/// `--brand-1`.
///
/// Keys are CSS identifiers and JavaScript object keys by the time they are emitted, so
/// they are sanitized at the point of use rather than trusted here — see
/// ``ExportOptions/cssIdentifier(_:)``.
nonisolated struct PaletteEntry: Sendable, Hashable, Identifiable {
  // MARK: Lifecycle

  init(key: String = "", color: ColorValue) {
    self.key = key
    self.color = color
  }

  // MARK: Internal

  let key: String
  let color: ColorValue

  var id: String {
    key
  }
}

/// A named set of entries — one palette, or one loose color, inside a document that
/// writes more than one.
///
/// Rendering a single ``PaletteEntry`` array is the one-group special case of rendering
/// these: a project export writes one property set per saved palette (plus one per
/// loose color, as a group of one) rather than flattening everything under the single
/// family name ``ExportOptions/name`` supplies. See M20 in PLAN.md.
nonisolated struct PaletteGroup: Sendable, Hashable, Identifiable {
  let name: String
  let entries: [PaletteEntry]

  var id: String {
    name
  }
}

/// A CSS declaration with a color-valued slot in it.
///
/// These are *syntax*, which is why they live in ColorCore alongside the serializer
/// rather than beside the panel's wording: `border` takes a width and a style before its
/// color and `fill` takes neither, and getting that wrong emits CSS that does not parse.
///
/// **The non-color parts are conventional, not specified.** `1px solid`, `0 1px 3px` —
/// nothing about the language requires them, they are the values you would type before
/// changing them. This app is a color tool, so it declines to grow a shadow editor to
/// make them adjustable; the declaration is a starting point you paste and then edit,
/// and every template is one line so editing it is trivial.
nonisolated enum ExportTemplate: String, CaseIterable, Sendable, Hashable, Identifiable, Codable {
  case color
  case backgroundColor = "background-color"
  case border
  case outline
  case boxShadow = "box-shadow"
  case textShadow = "text-shadow"
  case fill
  case stroke

  // MARK: Internal

  var id: String {
    rawValue
  }

  /// The CSS property this template sets. Also its `rawValue` for every case where the
  /// property *is* the whole template, which is most of them.
  var property: String {
    rawValue
  }

  /// This declaration with `value` in its color slot, terminated and ready to paste
  /// inside a rule.
  func declaration(for value: String) -> String {
    switch self {
    case .color, .backgroundColor, .fill, .stroke:
      "\(property): \(value);"
    case .border:
      "border: 1px solid \(value);"
    case .outline:
      // 2px rather than 1px: an outline is usually a focus ring, and a focus ring
      // thinner than the border beside it is not one.
      "outline: 2px solid \(value);"
    case .boxShadow:
      "box-shadow: 0 1px 3px \(value);"
    case .textShadow:
      "text-shadow: 0 1px 2px \(value);"
    }
  }
}

/// Where a palette's keys come from.
///
/// Facts about the systems being exported to, not editorial choices — Tailwind's scale
/// is Tailwind's, and a harmony's members have fixed roles — so they belong here rather
/// than in the panel's presentation layer. They also have to be *unique*, because two
/// entries sharing a key silently collapse into one custom property.
nonisolated enum PaletteNaming {
  /// Tailwind's shade keys, lightest first.
  ///
  /// Eleven of them, `50` through `950`. Checked against the current documentation
  /// rather than recalled: the `950` step is a later addition than the rest, so a list
  /// ending at `900` is a plausible-looking and wrong answer.
  ///
  /// That there are exactly eleven and that ``ShadeRamp`` defaults to eleven stops is
  /// not a coincidence — the ramp's `lightest` was chosen to sit where Tailwind's `50`
  /// does — but it is also not a guarantee, which is what ``rampKeys(count:)`` is for.
  static let tailwindScale = [
    "50", "100", "200", "300", "400", "500", "600", "700", "800", "900", "950",
  ]

  /// Keys for a ramp of `count` stops, lightest first.
  ///
  /// Tailwind's scale when the count matches it exactly, and 1-based indices otherwise.
  /// The fallback is not hypothetical: ``Harmony/monochromatic`` asks ``ShadeRamp`` for
  /// five stops, and the panel's stepper runs from 3 to 21. Spreading eleven fixed names
  /// over five stops would have to invent a mapping, and every mapping is wrong for
  /// someone — `1…5` at least claims nothing.
  static func rampKeys(count: Int) -> [String] {
    guard count == tailwindScale.count else {
      return (1 ... max(count, 1)).map(String.init)
    }
    return tailwindScale
  }

  /// Keys for a harmony's members, in the order ``ColorValue/harmony(_:options:)``
  /// returns them.
  ///
  /// Named by role where a role exists, because `--brand-complement` is worth having
  /// over `--brand-2` in a stylesheet somebody has to read later. Monochromatic defers
  /// to ``rampKeys(count:)`` for the same reason the harmony itself defers to
  /// ``ShadeRamp``: it is a lightness family, not a hue one.
  static func harmonyKeys(_ harmony: Harmony, options: HarmonyOptions = .default) -> [String] {
    switch harmony {
    case .complementary:
      ["base", "complement"]
    case .splitComplementary:
      ["base", "split-1", "split-2"]
    case .triad:
      ["base", "triad-2", "triad-3"]
    case .tetrad:
      ["base", "tetrad-2", "tetrad-3", "tetrad-4"]
    case .analogous:
      // Analogous leads with the member *below* the base — see `hueOffsets` — so the
      // base is in the middle here, unlike every other hue harmony.
      ["analogous-1", "base", "analogous-3"]
    case .monochromatic:
      rampKeys(count: harmony.count(options: options))
    }
  }
}
