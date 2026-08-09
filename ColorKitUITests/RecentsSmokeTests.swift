//
//  RecentsSmokeTests.swift
//  ColorKitUITests
//

import XCTest

/// The recents row (M23): a color submitted in the field reappears as a swatch above
/// the tool switcher, and clicking it restores what was typed rather than a
/// canonicalized form.
final class RecentsSmokeTests: XCTestCase {
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
    _ = app?.wait(for: .notRunning, timeout: 30)
    app = nil
  }

  // MARK: - Tests

  /// Submitting the field is one of the deliberate moments a color is remembered
  /// (``ColorInputField``'s `.onSubmit`), and the swatch that appears carries the
  /// *authored* text — `rebeccapurple`, not the `#663399` it resolves to — which is
  /// what the store-side ``ColorStoreTests/usingARecentRestoresItsText`` half already
  /// pins. This is the render-and-click half unit tests cannot reach.
  func testSubmittingAColorAddsItToTheRecentsRowAndClickingRestoresIt() {
    let field = app.textFields["colorInput"]
    XCTAssertTrue(field.waitForExistence(timeout: 30))
    field.click()
    field.typeKey("a", modifierFlags: .command)
    field.typeText("rebeccapurple\n")

    let recent = app.buttons["recentColor-rebeccapurple"]
    guard recent.waitForExistence(timeout: 15) else {
      XCTFail("No recent swatch for rebeccapurple. Tree was:\n\(app.debugDescription)")
      return
    }

    field.click()
    field.typeKey("a", modifierFlags: .command)
    field.typeText("red\n")
    XCTAssertEqual(field.value as? String, "red")

    guard waitUntilHittable(recent) else {
      XCTFail("Recent swatch never became hittable. Tree was:\n\(app.debugDescription)")
      return
    }
    recent.click()

    XCTAssertEqual(
      field.value as? String, "rebeccapurple",
      "clicking a recent should restore the authored text, not a re-derived one",
    )
  }

  /// The Clear affordance (matching `MenuBarPanel`'s), and proof the row only offers
  /// it once there is something to clear.
  func testClearRemovesEveryRecent() {
    XCTAssertFalse(
      app.buttons["clearRecents"].exists,
      "Clear should not appear before anything has been remembered",
    )

    let field = app.textFields["colorInput"]
    XCTAssertTrue(field.waitForExistence(timeout: 30))
    field.click()
    field.typeKey("a", modifierFlags: .command)
    field.typeText("red\n")

    let clear = app.buttons["clearRecents"]
    guard clear.waitForExistence(timeout: 15) else {
      XCTFail("No Clear button after remembering a color. Tree was:\n\(app.debugDescription)")
      return
    }
    clear.click()

    XCTAssertFalse(app.buttons["recentColor-red"].exists, "Clear did not remove the recent")
    XCTAssertFalse(app.buttons["clearRecents"].exists, "Clear should hide itself once the list is empty")
  }

  // MARK: Private

  private var app: XCUIApplication!

  /// Polls rather than using `waitForExpectations`, whose completion handler cannot
  /// cross into a non-`Sendable` `XCTestCase` under Swift 6.
  private func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval = 15) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if element.isHittable {
        return true
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    return element.isHittable
  }
}
