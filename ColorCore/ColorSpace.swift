//
//  ColorSpace.swift
//  ColorKit
//

import Foundation

/// A color space supported by CSS Color Module Level 4.
///
/// Named colors are deliberately *not* a case here. In the CSS spec a keyword is a
/// serialization *format* of sRGB, not a space of its own — modeling it that way
/// keeps `red` and `#f00` the same value, which is what users expect.
/// - Note: `nonisolated` throughout ColorCore. The app target builds with
///   `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which is right for UI code but
///   would strand the color engine on the main thread — blocking batch palette
///   generation, CVD image filtering, and any future CLI reuse.
nonisolated enum ColorSpace: String, Codable, Sendable, Hashable, CaseIterable {
  // sRGB family — alternate parameterizations of the same gamma-encoded values.
  case srgb
  case hsl
  case hwb
  case srgbLinear = "srgb-linear"

  // CIE Lab family. Note: D50-referenced, per CSS.
  case lab
  case lch

  // OKLab family. Note: D65-referenced, unlike lab/lch above.
  case oklab
  case oklch

  // Wide-gamut RGB spaces, reachable through `color()`.
  case displayP3 = "display-p3"
  case a98RGB = "a98-rgb"
  case proPhotoRGB = "prophoto-rgb"
  case rec2020

  // Connection spaces.
  case xyzD50 = "xyz-d50"
  case xyzD65 = "xyz-d65"
}

/// What a component *means*, independent of the space that holds it.
///
/// Two components are "analogous" — CSS Color 4 §13.2's word — when they share a
/// role, and that is the whole question interpolation needs answered: an `h` that
/// was authored `none` in `hsl()` is still absent after conversion to `oklch()`,
/// because both are hues, while a missing `b` in `lab()` says nothing about the
/// blue channel of sRGB.
///
/// Distinct from ``ColorSpace/componentLabels``, which is display copy and may be
/// reworded freely. This is a fact with behavior hanging off it.
///
/// ``whiteness`` and ``blackness`` are deliberately roles of their own: the spec
/// states outright that HWB's two have no analog in any other space. They still
/// take part in the *set* rule — see
/// ``ColorValue/carriedForwardMissing(to:)`` — which is a separate mechanism.
nonisolated enum ComponentRole: Sendable, Hashable, CaseIterable {
  case reds
  case greens
  case blues
  case lightness
  case colorfulness
  case hue
  case opponentA
  case opponentB
  case whiteness
  case blackness
}

nonisolated extension ColorSpace {
  /// Groups spaces that are alternate encodings of the same underlying values.
  ///
  /// Conversions *within* a family go directly rather than detouring through XYZ:
  /// the round trip would add floating-point error and, worse, destroy hue on
  /// achromatic colors.
  enum Family: Sendable, Hashable {
    case srgbEncoded // srgb, hsl, hwb — all describe gamma-encoded sRGB
    case lab // lab, lch
    case oklab // oklab, oklch
    case independent // everything else
  }

  var family: Family {
    switch self {
    case .srgb, .hsl, .hwb: .srgbEncoded
    case .lab, .lch: .lab
    case .oklab, .oklch: .oklab
    default: .independent
    }
  }

  /// Spaces with no inherent gamut limit. Gamut mapping is a no-op for these.
  var isUnbounded: Bool {
    switch self {
    case .lab, .lch, .oklab, .oklch, .xyzD50, .xyzD65: true
    default: false
    }
  }

  /// The RGB space whose `[0, 1]` cube defines this space's gamut, if bounded.
  ///
  /// HSL and HWB have no gamut of their own — they describe sRGB, so they borrow
  /// its cube.
  var rgbBasis: ColorSpace? {
    switch self {
    case .srgb, .hsl, .hwb: .srgb
    case .srgbLinear: .srgbLinear
    case .displayP3: .displayP3
    case .a98RGB: .a98RGB
    case .proPhotoRGB: .proPhotoRGB
    case .rec2020: .rec2020
    default: nil
    }
  }

  /// Index of the hue component, for spaces that have one.
  ///
  /// Derived from ``componentRoles`` rather than listed separately, so the two
  /// cannot drift: a space that gained a hue in one table and not the other would
  /// interpolate one way and display another.
  var hueIndex: Int? {
    componentIndex(of: .hue)
  }

  /// What each component *is*, for deciding which components correspond across
  /// spaces. See ``ComponentRole``.
  ///
  /// Transcribed from CSS Color 4 §13.2's table, not read off ``componentLabels``.
  /// Three of its groupings are not guessable from the letters: XYZ counts as a
  /// super-saturated RGB space, so `x`/`y`/`z` share `r`/`g`/`b`'s categories;
  /// Saturation shares Chroma's despite being lightness-dependent; and `b` names
  /// two unrelated things — Blue in an RGB space, Opponent b in Lab — which is
  /// exactly why roles are per-space and never inferred from a label.
  var componentRoles: (ComponentRole, ComponentRole, ComponentRole) {
    switch self {
    case .srgb, .srgbLinear, .displayP3, .a98RGB, .proPhotoRGB, .rec2020,
         .xyzD50, .xyzD65:
      (.reds, .greens, .blues)
    case .hsl: (.hue, .colorfulness, .lightness)
    case .hwb: (.hue, .whiteness, .blackness)
    case .lab, .oklab: (.lightness, .opponentA, .opponentB)
    case .lch, .oklch: (.lightness, .colorfulness, .hue)
    }
  }

  /// The role table in index order — the same three facts as ``componentRoles``,
  /// shaped for walking rather than destructuring.
  var orderedComponentRoles: [ComponentRole] {
    let roles = componentRoles
    return [roles.0, roles.1, roles.2]
  }

  /// Where this space keeps a given role, if it has one at all.
  ///
  /// A role appears at most once per space, so this is a lookup rather than a
  /// search — which is what lets ``ComponentRole`` decide analogy by equality.
  func componentIndex(of role: ComponentRole) -> Int? {
    let roles = componentRoles
    if roles.0 == role {
      return 0
    }
    if roles.1 == role {
      return 1
    }
    if roles.2 == role {
      return 2
    }
    return nil
  }

  /// Whether this space can appear inside the CSS `color()` function.
  var isColorFunctionSpace: Bool {
    switch self {
    case .srgb, .srgbLinear, .displayP3, .a98RGB, .proPhotoRGB, .rec2020,
         .xyzD50, .xyzD65:
      true
    default:
      false
    }
  }

  /// The channel keywords CSS Color 5 relative color syntax exposes for this space,
  /// in index order — the `r`, `g`, `b` of `rgb(from red r g b)`.
  ///
  /// Transcribed from the spec, and **never derived** — not from
  /// ``componentLabels`` and not from ``componentRoles``. Both look like they would
  /// work and both are wrong for different reasons:
  ///
  /// - `componentLabels` is display copy the UI layer owns and may reword freely.
  ///   Today every label's first letter happens to be the right keyword, which makes
  ///   the derivation tempting and the failure silent: rewording "Chroma" would make
  ///   the parser accept `oklch(from red l o h)` and reject the spec's spelling.
  ///   Syntax cannot hang off editorial copy.
  /// - `componentRoles` genuinely disagrees. XYZ counts as a super-saturated RGB
  ///   space there, so it shares `(.reds, .greens, .blues)` — but its keywords are
  ///   `x`, `y`, `z`. A role-derived table would name them `r`, `g`, `b`.
  ///
  /// Keying on the *space* rather than the function is what makes one table enough:
  /// `rgb()` and `color(srgb …)` both land on ``srgb`` and both spell it `r g b`.
  var channelKeywords: (String, String, String) {
    switch self {
    case .srgb, .srgbLinear, .displayP3, .a98RGB, .proPhotoRGB, .rec2020:
      ("r", "g", "b")
    case .xyzD50, .xyzD65: ("x", "y", "z")
    case .hsl: ("h", "s", "l")
    case .hwb: ("h", "w", "b")
    case .lab, .oklab: ("l", "a", "b")
    case .lch, .oklch: ("l", "c", "h")
    }
  }

  /// Human-facing component labels, in order.
  var componentLabels: (String, String, String) {
    switch self {
    case .srgb, .srgbLinear, .displayP3, .a98RGB, .proPhotoRGB, .rec2020:
      ("Red", "Green", "Blue")
    case .hsl: ("Hue", "Saturation", "Lightness")
    case .hwb: ("Hue", "Whiteness", "Blackness")
    case .lab, .oklab: ("Lightness", "a", "b")
    case .lch, .oklch: ("Lightness", "Chroma", "Hue")
    case .xyzD50, .xyzD65: ("X", "Y", "Z")
    }
  }

  /// Achromatic threshold used when converting a rectangular space to its polar
  /// form. Derived from the base space's `a` reference range divided by 100000,
  /// matching the reference implementation.
  var polarEpsilon: Double? {
    switch self {
    case .lch: 250.0 / 100_000.0 // Lab `a` spans [-125, 125]
    case .oklch: 0.8 / 100_000.0 // OKLab `a` spans [-0.4, 0.4]
    default: nil
    }
  }
}
