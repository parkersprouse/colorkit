//
//  FormatCatalog.swift
//  ColorKit
//

import Foundation

/// One color written one way, with the facts a UI needs to present it honestly.
///
/// Deliberately carries no display copy — no titles, no icons, no section names.
/// Those are presentation choices belonging to whatever draws the row, and leaving
/// them out means these values can be asserted on in tests without pinning wording
/// that will change the first time the layout does.
nonisolated struct FormattedColor: Sendable, Hashable, Identifiable {
  let format: CSSOutputFormat
  let css: String
  /// The serialized value is not the authored color: it was moved into this
  /// format's gamut to become expressible at all.
  let isGamutMapped: Bool

  var id: CSSOutputFormat {
    format
  }
}

nonisolated extension CSSOutputFormat {
  /// Every format the conversion panel offers, in display order.
  ///
  /// Ordered by how often you reach for it writing CSS. `oklch()` leads the
  /// perceptual group because it is the one worth reaching for; the XYZ connection
  /// spaces come last because they are exact and occasionally indispensable but
  /// nobody ships them in a stylesheet.
  static let catalog: [CSSOutputFormat] = [
    // sRGB, in the spellings a browser has always understood.
    .hex, .keyword, .rgb, .hsl, .hwb,
    // Perceptually uniform.
    .oklch, .oklab, .lch, .lab,
    // Wider gamuts, reachable only through color().
    .color(.displayP3), .color(.rec2020), .color(.a98RGB), .color(.proPhotoRGB),
    // Exact, but rarely authored by hand.
    .color(.srgb), .color(.srgbLinear), .color(.xyzD65), .color(.xyzD50),
  ]

  /// The formats offered under ``ColorStore/webFriendly`` (M22) — every hand-authored
  /// sRGB spelling plus the four perceptual functions, none of which can express
  /// anything past sRGB's edge without an explicit clamp.
  ///
  /// A table, not a predicate derived from `catalog` — the same reason
  /// ``ColorSpace/componentRoles`` and ``ColorSpace/channelKeywords`` are transcribed
  /// rather than computed. The criterion is a judgment about authoring practice, not a
  /// fact the enum carries: `color(srgb …)` is fully inside sRGB, so any gamut-derived
  /// rule would include it, and it is excluded anyway because nobody hand-authors the
  /// `color()` family. A derived `if case .color` rule would agree by accident today and
  /// disagree the moment a bounded non-`color()` format is added.
  static let webFriendly: [CSSOutputFormat] = [
    .hex, .keyword, .rgb, .hsl, .hwb, .oklch, .oklab, .lch, .lab,
  ]

  /// The format that writes a color in the space it is already in.
  ///
  /// The inverse of ``space``, and useful wherever the space a color arrived in is
  /// *authored information* rather than an implementation detail. A design token names
  /// its `colorSpace` explicitly, so importing one and then storing it spelled `oklch()`
  /// would throw away something the author wrote down — the same objection this app makes
  /// to canonicalizing a typed `rebeccapurple`.
  ///
  /// An RGB-family space answers `color(srgb …)` rather than `rgb()`, and both XYZ spaces
  /// answer `color()` too, because that is the spelling those spaces have. Derived rather
  /// than transcribed — every arm is already stated by ``space``, which is what
  /// `nativeFormatRoundTripsThroughItsSpace` asserts.
  static func native(for space: ColorSpace) -> CSSOutputFormat {
    switch space {
    case .hsl: .hsl
    case .hwb: .hwb
    case .lab: .lab
    case .lch: .lch
    case .oklab: .oklab
    case .oklch: .oklch
    default: .color(space)
    }
  }
}

nonisolated extension ColorValue {
  /// This color written as `format`, or `nil` when the format cannot name it.
  ///
  /// Only `.keyword` ever returns `nil`: 148 fixed points cannot name an arbitrary
  /// color, and answering with the nearest one would be a lie in a tool whose whole
  /// job is being exact.
  func formatted(
    as format: CSSOutputFormat,
    options: CSSFormatOptions = .default,
  ) -> FormattedColor? {
    guard let css = cssString(as: format, options: options) else { return nil }
    return FormattedColor(
      format: format,
      css: css,
      isGamutMapped: isGamutMapped(
        as: format,
        options: options,
        epsilon: Self.gamutNoiseTolerance,
      ),
    )
  }

  /// This color in every catalog format, skipping any that cannot name it.
  func allFormats(options: CSSFormatOptions = .default) -> [FormattedColor] {
    CSSOutputFormat.catalog.compactMap { formatted(as: $0, options: options) }
  }

  /// A format that can write this color down without throwing part of it away —
  /// `format` itself when it suffices, and a wide-gamut fallback when it does not.
  ///
  /// Needed anywhere a color becomes text that will later be read back. hex is the
  /// natural preference and the right answer for almost everything, but it is 8-bit
  /// sRGB: asking it to spell a Display P3 sample forces a gamut map, and the color
  /// that comes back is not the color that went in.
  ///
  /// The decision comes from ``isGamutMapped(as:options:epsilon:)`` — the same
  /// predicate that decides whether a row wears a "mapped" badge — rather than a
  /// second rule of its own. One predicate means the badge and this can never
  /// disagree about whether a format is lossy for a given color.
  ///
  /// - Parameter allowingWideGamut: `false` under ``ColorStore/webFriendly`` (M22).
  ///   The promotion this function exists to make is itself a `color()` spelling, and
  ///   that family is exactly what the mode hides — so declining it and returning
  ///   `format` unchanged is not merely "no preference", it is required. This alone
  ///   does not pull an out-of-sRGB *value* in; callers under the flag additionally
  ///   move the color itself with ``pulledInto(_:)`` before asking for a spelling, and
  ///   this parameter is what stops that already-safe color from being promoted right
  ///   back out on the way to the field.
  func spelling(
    preferring format: CSSOutputFormat,
    allowingWideGamut: Bool = true,
  ) -> CSSOutputFormat {
    guard allowingWideGamut else { return format }
    return isGamutMapped(as: format, options: .lossless, epsilon: Self.gamutNoiseTolerance)
      // Display P3 rather than the sampler's own `srgb-linear`: it is what a web
      // author actually writes for wide colors, its components stay inside 0–1
      // for anything a P3 screen can show, and `preserve` keeps even the rare
      // beyond-P3 value intact instead of clamping it.
      ? .color(.displayP3)
      : format
  }
}
