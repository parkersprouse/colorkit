//
//  WCAGContrast.swift
//  ColorKit
//

import Foundation

/// A contrast threshold from WCAG 2.2, as a fact rather than a sentence.
///
/// Carries the success-criterion number, which is spec vocabulary, but no human
/// wording — "Normal text" is a phrasing choice belonging to whatever draws the row.
nonisolated enum ContrastRequirement: Sendable, Hashable, CaseIterable {
  /// 1.4.3 Contrast (Minimum) — body text.
  case aaNormalText
  /// 1.4.3 Contrast (Minimum) — text at 18pt, or 14pt bold, and above.
  case aaLargeText
  /// 1.4.6 Contrast (Enhanced) — body text.
  case aaaNormalText
  /// 1.4.6 Contrast (Enhanced) — large text.
  case aaaLargeText
  /// 1.4.11 Non-text Contrast — UI components, focus indicators, meaningful graphics.
  case nonText

  // MARK: Internal

  /// The ratio a pair must reach. Note that AAA large text and AA normal text are
  /// the same number reached from opposite directions — 4.5:1 is both the floor for
  /// ordinary body copy and the enhanced bar once type gets big.
  var minimumRatio: Double {
    switch self {
    case .aaNormalText: 4.5
    case .aaLargeText: 3
    case .aaaNormalText: 7
    case .aaaLargeText: 4.5
    case .nonText: 3
    }
  }

  /// The success criterion this comes from, for anyone cross-checking an audit.
  var criterion: String {
    switch self {
    case .aaNormalText, .aaLargeText: "1.4.3"
    case .aaaNormalText, .aaaLargeText: "1.4.6"
    case .nonText: "1.4.11"
    }
  }

  /// A short paraphrase of the criterion's own requirement, for a tooltip. Paraphrased
  /// rather than the spec's normative text verbatim, both because a summary does not
  /// need updating every time the row's own wording changes and because it avoids
  /// reproducing the W3C's copyrighted text at length.
  var specSummary: String {
    switch self {
    case .aaNormalText:
      "Text and images of text need at least 4.5:1 contrast against their background."
    case .aaLargeText:
      "Large-scale text (18pt, or 14pt bold, and larger) needs at least 3:1 contrast against its background."
    case .aaaNormalText:
      "The enhanced level: text and images of text need at least 7:1 contrast against their background."
    case .aaaLargeText:
      "The enhanced level: large-scale text needs at least 4.5:1 contrast against its background."
    case .nonText:
      "Visual boundaries of user interface components, and graphics required to understand content, need at least 3:1 contrast against adjacent colors."
    }
  }

  /// This criterion's own page on the W3C's site — the anchor slug matches the
  /// criterion's name, not its number, so it is transcribed rather than derived.
  var specURL: URL {
    switch self {
    case .aaNormalText, .aaLargeText:
      URL(string: "https://www.w3.org/TR/WCAG22/#contrast-minimum")!
    case .aaaNormalText, .aaaLargeText:
      URL(string: "https://www.w3.org/TR/WCAG22/#contrast-enhanced")!
    case .nonText:
      URL(string: "https://www.w3.org/TR/WCAG22/#non-text-contrast")!
    }
  }
}

nonisolated extension ColorValue {
  /// Relative luminance as **WCAG** defines it, which is not quite as sRGB defines
  /// it and not what ``ColorSpace/srgbLinear`` uses.
  ///
  /// WCAG's formula linearizes at **0.03928**; the sRGB specification — and
  /// therefore `TransferFunctions` and every conversion ColorCore validates against
  /// colorjs.io — linearizes at **0.04045**. The two are otherwise identical, which
  /// is exactly what makes this dangerous: they look like the same function with a
  /// typo, and merging them would silently make every contrast result
  /// non-conformant. **Keep them separate.**
  ///
  /// In practice the difference is unobservable on hex colors — no `k/255` falls
  /// between the two thresholds, so any 8-bit color linearizes identically either
  /// way. It only shows up on continuous values, where it moves a ratio by at most
  /// 2.8e-4. Small, but conformance is defined by the text, not by the size of the
  /// discrepancy.
  ///
  /// Alpha is ignored: the contrast of a translucent color depends on whatever is
  /// behind it, so a caller who cares must composite first.
  var wcagRelativeLuminance: Double {
    // Gamut-mapped rather than clipped, and never raw: `pow` of a negative
    // component returns NaN, and an out-of-sRGB color has them. Mapping matches
    // what the swatch shows and what the serializer writes for bounded formats.
    let srgb = convertedAndMapped(to: .srgb)
    let r = Self.wcagLinearize(srgb.components.x)
    let g = Self.wcagLinearize(srgb.components.y)
    let b = Self.wcagLinearize(srgb.components.z)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
  }

  /// The WCAG contrast ratio between two colors, from 1:1 to 21:1.
  ///
  /// Symmetric — hence `with` rather than `against`. Which color is text and which
  /// is background makes no difference here, which is precisely the criticism APCA
  /// exists to answer; see ``apcaContrast(on:)``.
  func contrastRatio(with other: ColorValue) -> Double {
    let a = wcagRelativeLuminance
    let b = other.wcagRelativeLuminance
    let lighter = max(a, b)
    let darker = min(a, b)
    // The 0.05 is a fixed allowance for viewing flare — ambient light reflecting
    // off the screen — which is why pure black on pure white is 21:1 rather than
    // infinite.
    return (lighter + 0.05) / (darker + 0.05)
  }

  /// Whether this color on `background` satisfies `requirement`.
  func meets(_ requirement: ContrastRequirement, on background: ColorValue) -> Bool {
    // Compared at the precision the ratio is reported to. A pair landing at
    // 4.4999999 is 4.5 to every audit tool that prints one decimal, and failing it
    // on a floating-point artifact would be indefensible.
    contrastRatio(with: background) >= requirement.minimumRatio - 1e-9
  }

  /// Every requirement this pairing satisfies.
  func passedRequirements(on background: ColorValue) -> Set<ContrastRequirement> {
    Set(ContrastRequirement.allCases.filter { meets($0, on: background) })
  }

  private static func wcagLinearize(_ channel: Double) -> Double {
    // Clamped even though gamut mapping should already guarantee 0…1: mapping can
    // leave a component at -1e-17, and `pow` on that is NaN, which would propagate
    // silently through a ratio and out into the UI as "nan:1".
    let c = min(max(channel, 0), 1)
    return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
  }
}
