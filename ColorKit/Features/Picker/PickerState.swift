//
//  PickerState.swift
//  ColorKit
//

import CoreGraphics
import Foundation

/// Which pair of axes the plane is showing.
///
/// - Note: `nonisolated`, like everything the renderer touches. The app builds with
///   `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so plain data in the UI layer has to
///   say otherwise or it cannot cross to the thread doing the drawing.
nonisolated enum PickerMode: String, CaseIterable, Identifiable, Sendable, Codable {
  /// Saturation across, value down, hue on the strip. What every design tool shows.
  case hsv
  /// Chroma across, lightness down, hue on the strip — with the sRGB edge drawn on
  /// top, which is the reason this mode exists.
  case oklch

  // MARK: Internal

  var id: String {
    rawValue
  }

  var title: String {
    switch self {
    case .hsv: "HSV"
    case .oklch: "OKLCH"
    }
  }

  /// How a pick in this mode gets written down.
  ///
  /// Not cosmetic. hex is 8-bit sRGB, so writing an OKLCH pick as hex would quantize
  /// it onto the 8-bit grid and re-parse it back as an sRGB color — the chroma
  /// slider would snap, sub-8-bit values would be unreachable, and a color authored
  /// in OKLCH would be stored in a space the user did not choose. `oklch()` is
  /// unbounded, so it also keeps picks made deliberately outside sRGB, which is half
  /// the point of drawing the boundary at all.
  var preferredFormat: CSSOutputFormat {
    switch self {
    case .hsv: .hex
    case .oklch: .oklch
    }
  }
}

/// Where the picker's cursors are, independent of what the field says.
///
/// The store keeps *text* as its source of truth, which is right for the app and
/// unusable as a picker's model: every drag tick would serialize and re-parse, and the
/// round trip loses exactly what a picker must not lose. Saturation dragged to zero
/// comes back as a gray with no hue, so the next frame would snap the strip to red;
/// hex quantization would make the cursor stutter on an 8-bit grid.
///
/// So the axes below lead and the store follows. The store is written on every change
/// and read only when something *else* changed it — see ``syncing(with:color:)``.
nonisolated struct PickerState: Sendable {
  // MARK: Lifecycle

  init(color: ColorValue? = nil) {
    if let color {
      seed(from: color)
    }
  }

  // MARK: Internal

  /// Where the chroma axis ends.
  ///
  /// sRGB reaches about `0.32` at its most saturated and most hues fall far short,
  /// so a tighter axis would clip the boundary curve it exists to show. `0.4` is
  /// OKLab's own reference range for `a` and `b`, leaves visible headroom past every
  /// sRGB hue, and keeps deliberately wide picks on the plane instead of off its
  /// edge.
  static let chromaAxisMaximum = 0.4

  private(set) var mode: PickerMode = .hsv

  var alpha: Double = 1

  // HSV axes.
  var hsvHue: Double = 0
  var saturation: Double = 0
  var value: Double = 100

  // OKLCH axes, held alongside rather than derived on demand, so that a drag moves
  // one number instead of round-tripping through a color and back.
  var lightness: Double = 1
  var chroma: Double = 0
  var oklchHue: Double = 0

  /// The last string this picker put into the store, used to tell its own writes
  /// apart from someone else's. Compared as text rather than as a color: exact
  /// equality, no epsilon to tune, and it answers precisely the question being
  /// asked — "is the field still showing what I put there?"
  private(set) var lastWritten: String?

  // MARK: - The color under the cursor

  /// What the active axes describe.
  var color: ColorValue {
    switch mode {
    case .hsv:
      ColorValue(
        hsv: HSVComponents(hue: hsvHue, saturation: saturation, value: value),
        alpha: alpha,
      )
    case .oklch:
      ColorValue(space: .oklch, lightness, chroma, oklchHue, alpha: alpha)
    }
  }

  /// A drag position as a fraction of its axis, clamped to `[0, 1]`.
  ///
  /// Shared by every picker gesture — the plane clamps two of these, the hue strip
  /// and alpha slider one each — so the boundary behavior (a drag that overshoots the
  /// control pins to the edge rather than wrapping or extrapolating) cannot drift
  /// between them.
  static func clampedFraction(_ position: CGFloat, over extent: CGFloat) -> Double {
    guard extent > 0 else { return 0 }
    return min(max(Double(position / extent), 0), 1)
  }

  // MARK: - Seeding

  /// Moves every axis to describe `color`.
  ///
  /// Both modes are seeded, not just the active one, so switching modes never shows
  /// a stale cursor. The exception is hue: a gray has none, and adopting the zero
  /// that falls out of the conversion is the oldest bug in color pickers — drag
  /// saturation to nothing, watch the strip jump to red, drag back up in a hue you
  /// never chose. The user's hue outlives colors that cannot carry one.
  mutating func seed(from color: ColorValue) {
    alpha = color.alpha

    let hsv = color.hsvComponents
    saturation = hsv.saturation
    value = hsv.value
    if hsv.saturation > 0, hsv.value > 0 {
      hsvHue = hsv.hue
    }

    let oklch = color.converted(to: .oklch)
    lightness = oklch.components.x
    chroma = oklch.components.y
    if !color.isAchromatic {
      oklchHue = oklch.components.z
    }
  }

  /// Switches axes, carrying a color across rather than reinterpreting whatever the
  /// other mode was last left at.
  ///
  /// - Parameter color: The authoritative color, normally the field's. Passing it
  ///   rather than reading ``color`` matters whenever HSV is the mode being left:
  ///   HSV describes the sRGB cube, so its axes have *already* mapped a wide color
  ///   in, and carrying that across would quietly narrow `oklch(0.7 0.3 140)` to
  ///   chroma 0.2366 merely because the panel happened to open on the other tab.
  ///   Falls back to the current axes when there is nothing to carry.
  mutating func setMode(_ newMode: PickerMode, carrying color: ColorValue? = nil) {
    guard newMode != mode else { return }
    let current = color ?? self.color
    mode = newMode
    seed(from: current)
  }

  // MARK: - Talking to the store

  /// The CSS to write, remembered so the write can be recognized coming back.
  ///
  /// - Parameter allowingWideGamut: `false` under ``ColorStore/webFriendly`` (M22).
  ///   Defensive rather than load-bearing on the usual path: every gesture already
  ///   clamps chroma to the sRGB edge under the flag (see ``committing(_:in:)``), so
  ///   `color` normally already fits. This is what still keeps the promise for the
  ///   one case that arrives unclamped — seeding from a typed, wide `oklch()` value,
  ///   since seeding carries input across rather than rejecting it.
  mutating func cssToWrite(allowingWideGamut: Bool = true) -> String {
    let color = allowingWideGamut ? color : color.pulledInto(.srgb)
    let text = color.cssStringOrHex(
      as: color.spelling(preferring: mode.preferredFormat, allowingWideGamut: allowingWideGamut),
      // Storage precision, not display precision. The field is re-parsed into
      // the color every other panel sees, so anything rounded here is rounded
      // permanently — the same reason the eyedropper does not use the user's
      // chosen digits either.
      options: .lossless,
    )
    lastWritten = text
    return text
  }

  /// Re-seeds from the field, unless the field is still showing this picker's own
  /// last write.
  ///
  /// The distinction matters more than it looks. Seeding unconditionally would feed
  /// every write straight back in — grays would lose their hue one frame after being
  /// dragged to, and hex quantization would drag the cursor a pixel at a time. A
  /// boolean "I am writing" flag is the tempting fix and the wrong one: the store
  /// re-parses synchronously but observation fires later, so the flag has usually
  /// been cleared by the time the callback lands.
  mutating func syncing(with text: String, color: ColorValue?) {
    guard text != lastWritten else { return }
    lastWritten = nil
    guard let color else { return }
    seed(from: color)
  }

  // MARK: - Committing a gesture

  /// The one seam every kind of drag — plane, hue strip, alpha — funnels through
  /// (M24): mutate the axes, clamp chroma to the sRGB edge under
  /// ``ColorStore/webFriendly`` (M22), and return the text to write.
  ///
  /// Extracted from what was `PickerPanel.apply(_:)` when the three gestures became
  /// their own views (``PickerPlaneView``, ``PickerHueStripView``,
  /// ``PickerAlphaSliderView``) shared by both `PickerPanel` and the popover
  /// `CompactPicker` — one shared implementation is what keeps the clamp from being
  /// reproduced across two hosts and three gestures. The clamp lives here rather than
  /// only in the plane's own drag handler, because a hue-strip drag can leave a
  /// chroma that fit the old hue past the new one's boundary, and every kind of
  /// change already reaches this one function.
  ///
  /// Returns the string rather than writing `store.inputText` itself, and that is
  /// not a style choice: `self` is reached through a `@Binding` in every caller, so
  /// writing the store *inside* this method would run before the binding's own
  /// write-back finishes — `lastWritten` would still be stale in the source of truth
  /// at the moment the store's observers fire. Returning the text and letting the
  /// caller assign `store.inputText = state.committing(…)` keeps the exact ordering
  /// `apply(_:)` had: this picker's own state is fully settled, `lastWritten`
  /// included, before the store — and therefore `syncing(with:color:)` — ever sees
  /// the write.
  ///
  /// Never called from `seed(from:)`: the mode hides output, it does not reject
  /// input, so a typed `oklch(0.9 0.3 140)` must still arrive on the panel unclamped.
  @MainActor
  mutating func committing(_ change: (inout PickerState) -> Void, in store: ColorStore) -> String {
    change(&self)
    if store.webFriendly, mode == .oklch {
      let limit = GamutBoundary.maxChroma(lightness: lightness, hue: oklchHue, in: .srgb)
      chroma = min(chroma, limit)
    }
    return cssToWrite(allowingWideGamut: !store.webFriendly)
  }
}
