//
//  SidebarSmokeTests.swift
//  ColorKitUITests
//

import XCTest

/// M36's `ToolSidebar`, rendered — the one thing every other suite's `selectTool(_:)`
/// exercises only in the sidebar's default, expanded state. Every other test in this
/// target proves a row can be clicked; this file is the one that proves collapsing the
/// rail does not take that away, which is the whole reason the milestone chose an
/// icon-only rail over hiding the sidebar outright.
final class SidebarSmokeTests: XCTestCase {
  // MARK: Internal

  override func setUpWithError() throws {
    continueAfterFailure = false
    app = XCUIApplication()
    // See `ProjectsSmokeTests` for why the AppKit opt-out is required even though this
    // suite has no persistence argument of its own to pair it with.
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

  /// A collapsed row has no `Text` label left in the tree — only the icon and its
  /// identifier — and still has to switch tools. If collapsing merely hid the row
  /// instead of shrinking it, this would fail at the `waitForExistence` below; if it
  /// left the row present but not clickable, it would fail at hittability instead.
  func testACollapsedRowStillSwitchesTools() {
    toggleSidebar()

    let pick = app.buttons["tool-pick"]
    XCTAssertTrue(pick.waitForExistence(timeout: 15), "No collapsed sidebar row for Pick. Tree was:\n\(app.debugDescription)")
    XCTAssertTrue(waitUntilHittable(pick), "Collapsed Pick row never became hittable. Tree was:\n\(app.debugDescription)")
    pick.click()

    XCTAssertTrue(
      app.otherElements["pickerPlane"].waitForExistence(timeout: 15),
      "Clicking the collapsed Pick row did not open the picker panel. Tree was:\n\(app.debugDescription)",
    )
  }

  /// The label VoiceOver reads must not depend on whether the row is showing its own
  /// `Text` — a collapsed, icon-only row is exactly the shape that made the old
  /// segmented switcher announce an SF Symbol name instead of "Convert" (see `Tool
  /// .title`'s doc comment). `.label` is asserted, not `.value` — this is a `Button`,
  /// not a `Text` with a published `.accessibilityIdentifier`, so the ordinary
  /// accessibility surface is the one to check.
  func testACollapsedRowStillAnnouncesItsToolName() {
    toggleSidebar()

    let export = app.buttons["tool-export"]
    XCTAssertTrue(export.waitForExistence(timeout: 15))
    XCTAssertEqual(export.label, "Export", "A collapsed row's accessibility label should still be its tool name, not an SF Symbol name")
  }

  /// Expanding after collapsing restores the row exactly where every other suite
  /// expects to find it, so the round trip — not just one direction — is what is
  /// actually load-bearing for the rest of this target's `selectTool(_:)` helpers.
  func testExpandingAfterCollapsingRestoresTheRow() {
    toggleSidebar()
    toggleSidebar()

    let transform = app.buttons["tool-transform"]
    XCTAssertTrue(transform.waitForExistence(timeout: 15))
    XCTAssertTrue(waitUntilHittable(transform))
    transform.click()

    XCTAssertTrue(
      app.buttons["transformHarmony-0"].waitForExistence(timeout: 15),
      "Transform did not open after expanding the sidebar back out. Tree was:\n\(app.debugDescription)",
    )
  }

  // MARK: Private

  private var app: XCUIApplication!

  // MARK: - Helpers

  private func toggleSidebar() {
    let toggle = app.buttons["toggleSidebar"]
    guard toggle.waitForExistence(timeout: 15) else {
      XCTFail("No sidebar collapse toggle. Tree was:\n\(app.debugDescription)")
      return
    }
    guard waitUntilHittable(toggle) else {
      XCTFail("Sidebar collapse toggle never became hittable. Tree was:\n\(app.debugDescription)")
      return
    }
    toggle.click()
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
