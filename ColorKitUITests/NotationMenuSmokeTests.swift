//
//  NotationMenuSmokeTests.swift
//  ColorKitUITests
//

import XCTest

/// The notation menu (M25): the "6-digit hex" / "oklch()" line under the header
/// swatch's summary is a `Menu` listing every format that can name the active color,
/// and choosing one rewrites `colorInput` — the one path a unit test cannot reach,
/// since it is rendering and a real click that prove the `Menu` exists and works.
final class NotationMenuSmokeTests: XCTestCase {
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

  /// A SwiftUI `Menu` is a `menuButton` to XCUITest, not a `popUpButton` — the wrong
  /// query never matches, so this pins the query itself rather than assuming it.
  func testTheNotationControlExistsAsAMenuButton() {
    XCTAssertTrue(
      app.menuButtons["notationMenu"].waitForExistence(timeout: 30),
      "The notation control never appeared as a menuButton. Tree was:\n\(app.debugDescription)",
    )
  }

  /// Choosing a format from the menu rewrites `colorInput` — the entire reason M25
  /// turns the plain label into a `Menu` rather than leaving it as `Text`.
  /// `rebeccapurple` re-spelled as `rgb()` is `rgb(102 51 153)`, confirmed against
  /// `colorkit convert rebeccapurple --format rgb` before pinning it here.
  func testChoosingAFormatRewritesTheField() {
    let field = app.textFields["colorInput"]
    XCTAssertTrue(field.waitForExistence(timeout: 30))
    field.click()
    field.typeKey("a", modifierFlags: .command)
    field.typeText("rebeccapurple\n")

    select(menuItem: "rgb()", fromMenu: "notationMenu", "notation menu")

    XCTAssertEqual(field.value as? String, "rgb(102 51 153)")
  }

  // MARK: Private

  private var app: XCUIApplication!

  private func select(menuItem title: String, fromMenu identifier: String, _ description: String) {
    let popUp = app.menuButtons[identifier]
    guard popUp.waitForExistence(timeout: 15) else {
      XCTFail("No menu \(identifier) (\(description)). Tree was:\n\(app.debugDescription)")
      return
    }
    guard waitUntilHittable(popUp) else {
      XCTFail("\(identifier) never became hittable. Tree was:\n\(app.debugDescription)")
      return
    }
    popUp.click()

    let item = app.menuItems[title]
    guard item.waitForExistence(timeout: 15) else {
      XCTFail("No menu item \(title) in \(identifier). Tree was:\n\(app.debugDescription)")
      return
    }
    item.click()
  }

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
