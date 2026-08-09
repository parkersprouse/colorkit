//
//  ColorRecordTests.swift
//  ColorKitTests
//

@testable import ColorKit
import Foundation
import Testing

/// The bridge between a `ColorValue` and the fields a store can hold.
///
/// Tested without SwiftData on purpose: ``ColorRecord`` is a plain value type precisely
/// so the flattening — the part most likely to silently lose something — can be asserted
/// without a `ModelContainer` anywhere in sight. What persistence adds on top is checked
/// in ``ProjectStoreTests``.
@Suite("Color records")
struct ColorRecordTests {
  /// Every space, so a new `ColorSpace` case cannot be added without this noticing.
  /// Components are deliberately not round numbers: `0.5` survives a great many wrong
  /// implementations that `0.3178` does not.
  @Test("Every space round-trips exactly", arguments: ColorSpace.allCases)
  func everySpaceRoundTrips(space: ColorSpace) throws {
    let original = ColorValue(space: space, 0.3178, 0.4271, 0.5093, alpha: 0.8123)
    let record = ColorRecord(original, text: "authored")

    #expect(record.spaceID == space.rawValue)
    #expect(try #require(record.colorValue) == original)
  }

  /// `none` is a component that is *absent*, not one that is zero, and the mask is the
  /// only thing carrying that distinction. Drop it from the bridge and a saved
  /// `oklch(0.7 0.2 none)` comes back as a hue of exactly 0 — a different color, with
  /// nothing anywhere to say so.
  @Test("The missing-component mask survives storage")
  func missingMaskSurvives() throws {
    let original = ColorValue(space: .oklch, 0.7, 0.2, 0, missing: [.third])
    let restored = try #require(ColorRecord(original, text: "oklch(0.7 0.2 none)").colorValue)

    #expect(restored.missing == [.third])
    #expect(restored == original)
  }

  /// A row this build cannot read is skipped, not guessed at. The alternative is
  /// inventing a color for a space whose meaning was lost — a store written by a later
  /// version, or hand-edited — and showing it as though it were saved.
  @Test("An unknown space reads as nothing")
  func unknownSpaceIsNil() {
    let record = ColorRecord(
      spaceID: "cmyk",
      c0: 0,
      c1: 0,
      c2: 0,
      alpha: 1,
      missingMask: 0,
      text: "cmyk(0 0 0 0)",
    )

    #expect(record.colorValue == nil)
  }

  /// The authored spelling is kept verbatim, which is the entire reason it is stored:
  /// re-deriving it would canonicalize, and a saved `rebeccapurple` would come back
  /// `#663399` — the app rewriting something the user typed and then chose to keep.
  @Test(
    "The authored spelling is stored verbatim",
    arguments: ["rebeccapurple", "#3b82f6", "rgb(59 130 246)", "hsl(217.22 91.22% 59.8%)"],
  )
  func authoredTextIsVerbatim(css: String) throws {
    let color = try CSSColorParser.parse(css).color
    let record = ColorRecord(color, text: css)

    #expect(record.text == css)
  }

  /// The stored components and the stored text are two spellings of one claim, so they
  /// have to agree — the failure mode of storing both is that they quietly stop.
  ///
  /// Exact here, because for an authored color the text is what produced the components
  /// in the first place.
  @Test(
    "Stored components match the stored spelling",
    arguments: ["rebeccapurple", "#3b82f6", "rgb(59 130 246)", "oklch(0.7 0.15 250)"],
  )
  func componentsMatchSpelling(css: String) throws {
    let record = try ColorRecord(CSSColorParser.parse(css).color, text: css)

    let reparsed = try CSSColorParser.parse(record.text).color
    #expect(reparsed == record.colorValue)
  }

  /// A derived color — a ramp stop, a harmony member — has no authored text, so one is
  /// written for it at ``CSSFormatOptions/lossless``. That precision is the point: this
  /// string is what the color is typed back as when it is recalled, so anything the
  /// spelling rounds away is gone for good, exactly as in ``ColorStore/adopt(_:​preferring:)``.
  ///
  /// Measured with `deltaEOK` rather than per component, because even at `.lossless` the
  /// printed precision is *relative to each component's scale* — a hue on a 0–360 scale
  /// gets two fewer decimals than a lightness on a 0–1 one, so it lands within 5e-9 of
  /// itself while the lightness is exact. A flat per-component epsilon would be
  /// measuring the serializer's scaling rule rather than whether the color survived; the
  /// first draft of this test did exactly that and failed at 4.5e-9 on the hue. The
  /// perceptual distance it actually amounts to is ten orders of magnitude under a JND.
  @Test("A derived spelling survives the round trip it will be read back through")
  func derivedSpellingIsLossless() throws {
    let base = try CSSColorParser.parse("#3b82f6").color

    for stop in ShadeRamp.default.generated(from: base) {
      let record = ColorRecord.derived(stop, preferring: .oklch)
      let reparsed = try CSSColorParser.parse(record.text).color

      // `.oklch` is unbounded, so nothing was gamut-mapped on the way out and the
      // recalled color is in the space it was written in.
      #expect(reparsed.space == .oklch)
      #expect(try reparsed.deltaEOK(to: #require(record.colorValue)) < 1e-9)
    }
  }
}
