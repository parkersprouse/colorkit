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

  // MARK: Private

  private var app: XCUIApplication!
}
