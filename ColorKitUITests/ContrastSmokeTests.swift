//
//  ContrastSmokeTests.swift
//  ColorKitUITests
//

import XCTest

/// Covers the contrast panel the only way it can be covered: by rendering it.
///
/// The M3 lesson this exists because of — a value can be computed perfectly and still
/// reach the user wrong. Unit tests prove `contrastRatio(with:)` returns 21; only this
/// proves anyone can see it.
final class ContrastSmokeTests: XCTestCase {
  // MARK: Internal

  override func setUpWithError() throws {
    continueAfterFailure = false
    app = XCUIApplication()
    // See `ProjectsSmokeTests` for why this pairs with the AppKit opt-out even though
    // this suite has no persistence argument of its own to pair it with.
    app.launchArguments = ["-NSTreatUnknownArgumentsAsOpen", "NO", "UITestEphemeralPreferences"]
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "App did not reach the foreground")
  }

  override func tearDownWithError() throws {
    app?.terminate()
    // Wait for the process to actually go. `terminate()` returns before it does,
    // and the next launch can race a bundle still shutting down.
    _ = app?.wait(for: .notRunning, timeout: 30)
    app = nil
  }

  /// Black on white is 21.00:1 — the anchor everyone knows, and the one number that
  /// proves the panel is wired to the real calculation rather than to a placeholder.
  func testPanelShowsTheCanonicalRatio() {
    let field = app.textFields["colorInput"]
    XCTAssertTrue(field.waitForExistence(timeout: 30))

    field.click()
    field.typeKey("a", modifierFlags: .command)
    field.typeText("#000000")

    showContrastPanel()

    let background = app.textFields["backgroundInput"]
    XCTAssertTrue(background.waitForExistence(timeout: 15), "The contrast panel never appeared")
    background.click()
    background.typeKey("a", modifierFlags: .command)
    background.typeText("#ffffff")

    XCTAssertTrue(
      app.staticTexts["21.00:1"].waitForExistence(timeout: 15),
      "Black on white did not render as 21.00:1",
    )
    // APCA's own anchor, and proof the two algorithms are not showing one number
    // twice: 106.0 is nothing like 21.
    XCTAssertTrue(app.staticTexts["Lc +106.0"].exists, "APCA did not render its Lc")
  }

  /// Swapping must change the APCA reading, because APCA is asymmetric. If both
  /// directions showed the same number, the panel would be quietly lying about the
  /// one thing that distinguishes APCA from a contrast ratio.
  func testSwappingChangesTheAPCAReading() {
    let field = app.textFields["colorInput"]
    XCTAssertTrue(field.waitForExistence(timeout: 30))
    field.click()
    field.typeKey("a", modifierFlags: .command)
    field.typeText("#000000")

    showContrastPanel()

    let background = app.textFields["backgroundInput"]
    XCTAssertTrue(background.waitForExistence(timeout: 15))
    background.click()
    background.typeKey("a", modifierFlags: .command)
    background.typeText("#ffffff")

    XCTAssertTrue(app.staticTexts["Lc +106.0"].waitForExistence(timeout: 15))

    app.buttons["swapColors"].click()

    XCTAssertTrue(
      app.staticTexts["Lc -107.9"].waitForExistence(timeout: 15),
      "Swapping did not change the Lc — APCA is being treated as symmetric",
    )
    // WCAG, by contrast, is symmetric and must not have moved.
    XCTAssertTrue(app.staticTexts["21.00:1"].exists, "The WCAG ratio should be unchanged by a swap")
  }

  // MARK: Private

  private var app: XCUIApplication!

  /// Switches to the contrast tool, failing with the accessibility tree rather than
  /// a bare "not found" — a wrong guess about how SwiftUI exposes a segmented
  /// picker should say what it exposes *instead*.
  private func showContrastPanel() {
    // A single named query rather than a fallback chain. A chain that quietly
    // succeeds on an index-based guess is a test that rots without ever going
    // red — if SwiftUI changes how it exposes a segmented picker, this should say
    // so, and the tree in the failure message is what says it.
    let contrast = app.radioButtons["Contrast"]
    guard contrast.waitForExistence(timeout: 15) else {
      XCTFail("No radio button labelled Contrast. Tree was:\n\(app.debugDescription)")
      return
    }
    contrast.click()
  }
}
