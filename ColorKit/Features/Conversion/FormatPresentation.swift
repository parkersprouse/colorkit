//
//  FormatPresentation.swift
//  ColorKit
//

import SwiftUI

/// - Note: The two types below are `nonisolated` even though they live in the UI
///   layer. They are plain data — a label and a grouping — and the app target's
///   `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` would otherwise pin them to the main
///   thread, where a test could not read them without hopping actors to look at a
///   string constant. Views in this file stay main-actor, as they must.
nonisolated extension CSSOutputFormat {
  /// How this format is labeled on screen.
  ///
  /// Function formats are written with their parentheses so the label doubles as a
  /// reminder of the syntax you are about to paste.
  var title: String {
    switch self {
    case .hex: "hex"
    case .keyword: "Keyword"
    case .rgb: "rgb()"
    case .hsl: "hsl()"
    case .hwb: "hwb()"
    case .lab: "lab()"
    case .lch: "lch()"
    case .oklab: "oklab()"
    case .oklch: "oklch()"
    // `ColorSpace`'s raw values are already the CSS identifiers, so this stays
    // correct for free when a space is added.
    case let .color(space): "color(\(space.rawValue))"
    }
  }
}

/// How the conversion panel groups formats.
///
/// Presentation only. ColorCore owns which formats exist and in what order; what to
/// *call* a cluster of them is an editorial judgement, and keeping it here means core
/// tests assert behavior instead of pinning wording.
///
/// The sections partition ``CSSOutputFormat/catalog`` exactly — a test enforces that,
/// so adding a format to core without placing it in a section fails loudly rather
/// than making the format quietly unreachable in the UI.
nonisolated struct FormatSection: Identifiable, Sendable {
  static let all: [FormatSection] = [
    FormatSection(
      title: "Web",
      subtitle: "Understood everywhere",
      formats: [.hex, .keyword, .rgb, .hsl, .hwb],
    ),
    FormatSection(
      title: "Perceptual",
      subtitle: "Even lightness and hue steps",
      formats: [.oklch, .oklab, .lch, .lab],
    ),
    FormatSection(
      title: "Wide gamut",
      subtitle: "Reaches past sRGB",
      formats: [
        .color(.displayP3), .color(.rec2020),
        .color(.a98RGB), .color(.proPhotoRGB),
      ],
    ),
    FormatSection(
      title: "Exact",
      subtitle: "Lossless, rarely authored",
      formats: [
        .color(.srgb), .color(.srgbLinear),
        .color(.xyzD65), .color(.xyzD50),
      ],
    ),
  ]

  /// ``all``, narrowed to ``CSSOutputFormat/webFriendly`` and dropping any section the
  /// filter leaves empty — Wide gamut and Exact lose every entry under M22, and an
  /// empty section header would be exactly the negative feedback the mode exists to
  /// avoid. Web and Perceptual pass through whole: `CSSOutputFormat.webFriendly` is
  /// precisely their union.
  static let webFriendly: [FormatSection] = all.compactMap { section in
    let formats = section.formats.filter { CSSOutputFormat.webFriendly.contains($0) }
    guard !formats.isEmpty else { return nil }
    return FormatSection(title: section.title, subtitle: section.subtitle, formats: formats)
  }

  let title: String
  let subtitle: String
  let formats: [CSSOutputFormat]

  var id: String {
    title
  }

  /// ``all`` or ``webFriendly``, chosen the one way every caller needs to choose it.
  ///
  /// Three call sites walk `FormatSection` under this exact condition — the
  /// conversion panel's rows, `MenuBarPanel`'s copy menu, and `ColorInputField`'s
  /// notation menu (M25) — and before this they each spelled the ternary out
  /// independently. Consolidated here rather than left as three copies that could
  /// drift the day a fourth condition joins `webFriendly`.
  static func sections(webFriendly: Bool) -> [FormatSection] {
    webFriendly ? Self.webFriendly : all
  }
}

/// A small pill for facts about a color that are easy to miss and expensive to get
/// wrong — chiefly that the value shown is not quite the value asked for.
struct ColorBadge: View {
  let text: String
  var tint: Color = .orange

  var body: some View {
    Text(text)
      .font(.caption2.weight(.semibold))
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .foregroundStyle(tint)
      .background(tint.opacity(0.15), in: Capsule())
  }
}
