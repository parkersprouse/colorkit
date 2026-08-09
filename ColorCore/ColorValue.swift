//
//  ColorValue.swift
//  ColorKit
//

import Foundation

/// Tracks which components were authored as CSS `none`.
///
/// Carried through conversions so a round trip can preserve the distinction
/// between "hue is zero" and "hue is absent" — the latter matters for
/// interpolation and for serializing achromatic colors honestly.
nonisolated struct ComponentMask: OptionSet, Sendable, Hashable, Codable {
  static let first = ComponentMask(rawValue: 1 << 0)
  static let second = ComponentMask(rawValue: 1 << 1)
  static let third = ComponentMask(rawValue: 1 << 2)
  static let alpha = ComponentMask(rawValue: 1 << 3)

  let rawValue: UInt8

  static func component(_ index: Int) -> ComponentMask {
    ComponentMask(rawValue: 1 << UInt8(index))
  }
}

/// A color, retained in the space it was authored in.
///
/// Deliberately *not* normalized to sRGB on construction: `oklch(70% 0.4 30)` sits
/// outside the sRGB gamut, and eagerly converting would clamp it into oblivion with
/// no way back. Conversion happens on demand, so the authored value stays exact.
nonisolated struct ColorValue: Sendable, Hashable, Codable {
  // MARK: Lifecycle

  init(
    space: ColorSpace,
    components: SIMD3<Double>,
    alpha: Double = 1,
    missing: ComponentMask = [],
  ) {
    self.space = space
    self.components = components
    self.alpha = alpha
    self.missing = missing
  }

  init(
    space: ColorSpace,
    _ c0: Double,
    _ c1: Double,
    _ c2: Double,
    alpha: Double = 1,
    missing: ComponentMask = [],
  ) {
    self.init(
      space: space,
      components: SIMD3(c0, c1, c2),
      alpha: alpha,
      missing: missing,
    )
  }

  // MARK: Internal

  var space: ColorSpace
  var components: SIMD3<Double>
  var alpha: Double
  var missing: ComponentMask

  /// The hue component, for spaces that have one.
  var hue: Double? {
    get { space.hueIndex.map { components[$0] } }
    set {
      guard let index = space.hueIndex, let newValue else { return }
      components[index] = newValue
    }
  }

  var isOpaque: Bool {
    alpha >= 1
  }

  subscript(index: Int) -> Double {
    get { components[index] }
    set { components[index] = newValue }
  }
}

// MARK: - Convenience constructors

nonisolated extension ColorValue {
  /// Builds an sRGB color from 8-bit channel values.
  static func srgb8(_ r: UInt8, _ g: UInt8, _ b: UInt8, alpha: Double = 1) -> ColorValue {
    ColorValue(
      space: .srgb,
      Double(r) / 255,
      Double(g) / 255,
      Double(b) / 255,
      alpha: alpha,
    )
  }

  /// Looks up a CSS named color. Also accepts `transparent`.
  static func named(_ keyword: String) -> ColorValue? {
    let key = keyword.lowercased()
    if key == "transparent" {
      return ColorValue(space: .srgb, 0, 0, 0, alpha: 0)
    }
    guard let (r, g, b) = NamedColors.table[key] else { return nil }
    return .srgb8(r, g, b)
  }

  /// The CSS keyword exactly matching this color, if one exists.
  ///
  /// Requires an opaque sRGB color that lands precisely on 8-bit channel values —
  /// anything else has no keyword spelling.
  var namedKeyword: String? {
    guard isOpaque else { return nil }
    let rgb = converted(to: .srgb)
    var channels = SIMD3<UInt8>()
    for i in 0 ..< 3 {
      let scaled = rgb.components[i] * 255
      let rounded = scaled.rounded()
      guard abs(scaled - rounded) < 1e-9, rounded >= 0, rounded <= 255 else { return nil }
      channels[i] = UInt8(rounded)
    }
    return NamedColors.byValue[channels]
  }
}
