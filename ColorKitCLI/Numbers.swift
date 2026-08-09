import Foundation

/// Printing numbers that are *reported* rather than serialized.
///
/// Nothing here touches a color component — those go through `CSSFormatOptions`, whose
/// precision is relative to each component's scale. These are the plain figures a
/// report carries: a contrast ratio, an APCA Lc, a severity.
///
/// `String(format:)` without a locale argument formats in the POSIX locale, which is
/// what a CLI wants: a decimal comma would be correct prose and a broken pipe.
enum Numbers {
  /// Fixed decimals — for figures where the trailing zero carries meaning, like a
  /// ratio printed as `4.50:1` beside `4.83:1`.
  static func fixed(_ value: Double, _ places: Int) -> String {
    String(format: "%.\(places)f", value)
  }

  /// Fixed decimals with trailing zeros removed — for thresholds, where WCAG writes
  /// `3` and `4.5` rather than `3.00` and `4.50`.
  static func trimmed(_ value: Double, _ places: Int = 4) -> String {
    var text = fixed(value, places)
    guard text.contains(".") else { return text }
    while text.hasSuffix("0") {
      text.removeLast()
    }
    if text.hasSuffix(".") {
      text.removeLast()
    }
    return text
  }
}
