//
//  RelativeColor.swift
//  ColorKit
//

import Foundation

/// What one channel keyword resolves to inside a relative color function.
///
/// Two cases rather than a `Double?` because the spec gives `none` two different
/// meanings depending on where the keyword is used, and a nil would flatten them:
/// written bare it produces a missing component, and inside a `calc()` it is
/// treated as zero. See ``ChannelBindings``.
nonisolated enum ChannelValue: Equatable, Sendable {
  case number(Double)
  case missing
}

/// The channel keywords an origin color makes available, per CSS Color 5's
/// relative color syntax.
///
/// Built once per relative function, from the origin **already converted into the
/// output function's space**. That conversion is the spec's "relative color
/// processing space" rule, and it uses
/// ``ColorValue/convertedForInterpolation(to:)`` rather than plain
/// ``ColorValue/converted(to:)`` — the spec points at CSS Color 4 §13.2 by name, so
/// M12's carry-forward is the mechanism and not merely a similar one.
nonisolated struct ChannelBindings: Equatable, Sendable {
  // MARK: Lifecycle

  /// - Parameters:
  ///   - origin: the color written after `from`, in whatever space it was authored.
  ///   - function: the output function, which decides the keywords' *scale*.
  ///   - space: the output function's space, which decides their *spelling* and is
  ///     what the origin converts into.
  ///
  /// Both are needed and neither implies the other. `rgb()` and `color(srgb …)`
  /// land on the same space and spell the channels the same way, but a keyword
  /// carries the written scale of its own function — so `r` is 255 in
  /// `rgb(from red r g b)` and 1 in `color(from red srgb r g b)`.
  init(origin: ColorValue, function: ColorFunction, space: ColorSpace) {
    let resolved = origin.convertedForInterpolation(to: space)
    let keywords = space.channelKeywords
    let grammars = ColorGrammar.components(for: function)

    var table: [String: ChannelValue] = [:]
    for (index, keyword) in [keywords.0, keywords.1, keywords.2].enumerated() {
      table[keyword] =
        resolved.missing.contains(.component(index))
          ? .missing
          // Keywords resolve to a `<number>` in the component's *written* scale,
          // never to a percentage — the spec is explicit. Storage and the written
          // form differ in exactly one place, `rgb()`, whose channels are stored
          // 0–1 and written 0–255, and `numberScale` is already the factor
          // between them.
          : .number(resolved.components[index] / grammars[index].numberScale)
    }
    // Alpha is spelled the same everywhere and is a plain 0–1 number.
    table["alpha"] = resolved.missing.contains(.alpha) ? .missing : .number(resolved.alpha)

    values = table
  }

  // MARK: Internal

  /// The value for `keyword`, or `nil` if it names no channel of this space.
  ///
  /// `nil` is what keeps an ordinary typo an error: `rgb(from red r g q)` has to
  /// fail rather than quietly resolving `q` to something.
  func value(for keyword: String) -> ChannelValue? {
    values[keyword]
  }

  // MARK: Private

  private let values: [String: ChannelValue]
}
