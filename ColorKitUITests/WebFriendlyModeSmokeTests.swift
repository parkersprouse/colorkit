//
//  WebFriendlyModeSmokeTests.swift
//  ColorKitUITests
//

import XCTest

/// M22's mix section, hidden rather than restricted.
///
/// `TransformSmokeTests.testMixStripSpansThePairAndAdoptingAStopChangesTheField`
/// already proves the section renders with the flag off — a plain launch, no argument
/// added for it. This suite is the other half: launched with `UITestWebFriendly` (see
/// `ColorKitApp`), it should be gone.
///
/// No test here drives the Settings scene's Toggle — nothing in the app wires an
/// accessibility identifier to it yet, and no UI test anywhere drives that window, so
/// this launches straight into the mode instead of reaching it through the UI. The live
/// round trip (turn the Toggle on and off from Settings and watch the section react) is
/// a recorded manual check, the same way the file panels are.
final class WebFriendlyModeSmokeTests: XCTestCase {
  // MARK: Internal

  override func setUpWithError() throws {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchArguments = [
      "-NSTreatUnknownArgumentsAsOpen", "NO",
      "UITestEphemeralPreferences", "UITestWebFriendly",
    ]
    app.launch()
    XCTAssertTrue(
      app.wait(for: .runningForeground, timeout: 30),
      "App did not reach the foreground",
    )
  }

  override func tearDownWithError() throws {
    app?.terminate()
    _ = app?.wait(for: .notRunning, timeout: 30)
    app = nil
  }

  /// The section that has to go: its space picker, its background swatch, its result
  /// swatch. Absence rather than a disabled state — the "hide rather than disable"
  /// rule this mode follows throughout.
  func testMixSectionIsAbsentUnderWebFriendlyMode() {
    let field = app.textFields["colorInput"]
    XCTAssertTrue(field.waitForExistence(timeout: 30))
    field.click()
    field.typeKey("a", modifierFlags: .command)
    field.typeText("oklch(0.65 0.2 30)")

    let transform = app.radioButtons["Transform"]
    XCTAssertTrue(transform.waitForExistence(timeout: 15))
    transform.click()

    // Present neighbours, so this is "the mix section specifically" rather than
    // "the panel rendered nothing" — the harmony row right above it still shows.
    XCTAssertTrue(
      app.buttons["transformHarmony-0"].waitForExistence(timeout: 15),
      "the harmony section should still be here",
    )

    // A `Picker` without `.segmented` is a `popUpButton`, not a `menuButton` — the
    // same distinction `MenuBarPanel.copyMenu` documents for `Menu`.
    XCTAssertFalse(
      app.popUpButtons["transformMixSpace"].exists,
      "the mix space picker is still present under web-friendly mode.\n\(app.debugDescription)",
    )
    XCTAssertFalse(app.buttons["transformMixBackground"].exists)
  }

  /// The Chroma slider's left end really does reach fully gray, driven through the
  /// running app rather than through `OKLCHAdjustment` directly.
  ///
  /// `AdjustSliderRangeTests` already pins the arithmetic, so this is here for the one
  /// thing a unit test structurally cannot reach: that the slider's *track* is bound to
  /// that arithmetic, at the range the panel actually hands it. The bug it regresses
  /// against was exactly a binding-level one — the values were computed correctly and
  /// the slider's `in:` range strand them, reporting `×0.917 ... ×1.083` for this very
  /// color, so its far-left position produced a chroma of `0.172` where the base was
  /// `0.188`. Visually that is *the same blue*; the assertion below wants a gray, so
  /// the two answers are not near each other and this cannot pass against the old
  /// range.
  ///
  /// Web-friendly mode matters and is not incidental: with it off the ceiling is
  /// unbounded, the track is the plain `×0 ... ×2` it has always been, and the stranding
  /// this pins never happened in the first place.
  func testTheChromaSliderReachesFullyGrayUnderWebFriendlyMode() {
    let field = app.textFields["colorInput"]
    XCTAssertTrue(field.waitForExistence(timeout: 30))
    field.click()
    field.typeKey("a", modifierFlags: .command)
    field.typeText("#3b82f6\n")

    let transform = app.radioButtons["Transform"]
    XCTAssertTrue(transform.waitForExistence(timeout: 15))
    transform.click()

    // Hittability rather than existence: the tool switch resizes the window, and a
    // click already in flight lands where the control used to be.
    let chroma = app.sliders["Chroma"]
    XCTAssertTrue(
      chroma.waitForExistence(timeout: 15),
      "no Chroma slider.\n\(app.debugDescription)",
    )

    // An identifier on a `Text` publishes the string as `value`, never `label`.
    let readout = app.staticTexts["transformAdjusted"]
    XCTAssertTrue(readout.waitForExistence(timeout: 15))
    XCTAssertEqual(
      readout.value as? String, "#3b82f6",
      "the panel should open on the untouched color",
    )

    chroma.adjust(toNormalizedSliderPosition: 0)
    let desaturated = readout.value as? String ?? ""
    XCTAssertTrue(
      Self.isNeutral(desaturated),
      "the slider's left end gave \(desaturated), which is not a gray — the old "
        + "mirrored range stopped at ×0.917 and would answer a blue here",
    )

    // And the identity is still at the track's centre. Within one 8-bit step rather
    // than exactly, and the tolerance is the *input method's*, not the arithmetic's:
    // `adjust(toNormalizedSliderPosition:)` puts the thumb on a pixel, so "the centre"
    // is only ever within half a pixel of a true `0`, which lands a channel or two off
    // — measured, `#3c82f5` against `#3b82f6`. Asserting equality here fails for a
    // reason that has nothing to do with the slider. Note this half does **not**
    // discriminate against the old mirrored range, which centred the identity too; it
    // guards a future change that moves it off centre.
    chroma.adjust(toNormalizedSliderPosition: 0.5)
    let centred = readout.value as? String ?? ""
    XCTAssertTrue(
      Self.isWithinOneStep(centred, of: "#3b82f6"),
      "the centre gave \(centred), further than a rounding step from the identity",
    )
  }

  // MARK: Private

  private var app: XCUIApplication!

  /// A `#rrggbb` string's three channels, or `nil` if it is not one.
  private static func channels(_ hex: String) -> [Int]? {
    guard hex.count == 7, hex.hasPrefix("#") else { return nil }
    return stride(from: 1, to: 7, by: 2).compactMap { offset -> Int? in
      let start = hex.index(hex.startIndex, offsetBy: offset)
      return Int(hex[start ..< hex.index(start, offsetBy: 2)], radix: 16)
    }
  }

  /// Whether a `#rrggbb` string has three equal channels, i.e. no hue survives.
  ///
  /// Parsed rather than compared against a specific gray on purpose: which gray a
  /// fully-desaturated `#3b82f6` lands on is a fact about OKLCH's lightness, not about
  /// the slider, and pinning it here would make this test fail for a reason it has
  /// nothing to say about.
  private static func isNeutral(_ hex: String) -> Bool {
    guard let channels = channels(hex), channels.count == 3 else { return false }
    return Set(channels).count == 1
  }

  /// Whether two `#rrggbb` strings agree to within one 8-bit step on every channel —
  /// the precision an XCUITest slider drag can actually deliver.
  private static func isWithinOneStep(_ hex: String, of other: String) -> Bool {
    guard let a = channels(hex), let b = channels(other), a.count == 3, b.count == 3 else {
      return false
    }
    return zip(a, b).allSatisfy { abs($0 - $1) <= 1 }
  }
}
