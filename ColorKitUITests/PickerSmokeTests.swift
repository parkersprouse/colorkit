//
//  PickerSmokeTests.swift
//  ColorKitUITests
//

import XCTest

/// The picker, rendered.
///
/// A plane is a `Canvas`, so there is nothing in the accessibility tree to assert
/// about pixels — which is exactly why the panel carries a numeric readout. The
/// readout is the assertable surface here, and it happens to be the thing a person
/// reads too.
final class PickerSmokeTests: XCTestCase {
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

  /// The panel reports where the current color actually is, in both sets of axes.
  ///
  /// These numbers come from colorjs.io, so this is the wiring check the whole panel
  /// rests on: the plane could be drawn perfectly and still be showing a color the
  /// field does not hold.
  func testPanelReportsTheCurrentColorInBothModes() {
    setField("#3b82f6")
    selectTool("Pick")

    XCTAssertEqual(readout("readoutFirst"), "217.2°", "HSV hue")
    XCTAssertEqual(readout("readoutSecond"), "76.0%", "HSV saturation")
    XCTAssertEqual(readout("readoutThird"), "96.5%", "HSV value")
    capture("picker-hsv")

    click(radioButton: "OKLCH", "the axis switcher")

    XCTAssertEqual(readout("readoutFirst"), "0.6231", "OKLCH lightness")
    XCTAssertEqual(readout("readoutSecond"), "0.1880", "OKLCH chroma")
    XCTAssertEqual(readout("readoutThird"), "259.8°", "OKLCH hue")
    capture("picker-oklch")
  }

  /// The panel's own claim about the gamut, rendered.
  ///
  /// `oklch(0.7 0.3 140)` is a green well outside sRGB — the same color PLAN.md uses
  /// to make the point that gamut containment cannot be reasoned about from space
  /// widths. Here it should land past the drawn edge and say so.
  func testAWideColorIsReportedAsOutsideSRGB() {
    setField("oklch(0.7 0.3 140)")
    selectTool("Pick")
    click(radioButton: "OKLCH", "the axis switcher")

    XCTAssertEqual(readout("readoutSecond"), "0.3000", "chroma was not preserved")
    XCTAssertTrue(
      app.staticTexts["Outside sRGB"].waitForExistence(timeout: 10),
      "A color past the boundary is not badged. Tree was:\n\(app.debugDescription)",
    )
    capture("picker-outside-srgb")
  }

  /// The write-back loop, end to end: dragging the plane has to reach the shared
  /// field, and in OKLCH mode it has to arrive as `oklch()` rather than as hex.
  ///
  /// Hex would still *look* right — the swatch and the plane would agree — while
  /// quietly quantizing every pick onto the 8-bit grid and storing it in a space the
  /// user did not choose.
  func testDraggingThePlaneWritesOKLCHToTheField() {
    setField("#3b82f6")
    selectTool("Pick")
    click(radioButton: "OKLCH", "the axis switcher")

    let plane = app.otherElements["pickerPlane"]
    guard plane.waitForExistence(timeout: 15) else {
      XCTFail("No picker plane. Tree was:\n\(app.debugDescription)")
      return
    }

    let before = app.textFields["colorInput"].value as? String
    plane.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.35))
      .press(forDuration: 0.1,
             thenDragTo: plane.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.4)))

    let after = app.textFields["colorInput"].value as? String
    XCTAssertNotEqual(after, before, "Dragging the plane did not reach the field")
    XCTAssertTrue(
      after?.hasPrefix("oklch(") == true,
      "An OKLCH pick was written as \(after ?? "nothing") — it should be oklch()",
    )
    capture("picker-after-drag")
  }

  /// Commit-on-release (M23): releasing the plane drag has to file a recent right
  /// away, not after the second-long debounce this gesture used to share with the
  /// hue and alpha strips. A short wait is what actually discriminates the two —
  /// the old debounce would still be asleep at this point, so nothing would have
  /// appeared yet, where a direct `store.remember()` shows up within one render
  /// pass. `RecentsRow` is the surface this is checked through; the store-side half
  /// (dedupe, the authored-text round trip) is `ColorStoreTests`'s job.
  func testReleasingTheDragFilesARecentWithoutTheOldDebounceDelay() {
    setField("#3b82f6")
    selectTool("Pick")

    let plane = app.otherElements["pickerPlane"]
    guard plane.waitForExistence(timeout: 15) else {
      XCTFail("No picker plane. Tree was:\n\(app.debugDescription)")
      return
    }

    plane.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.35))
      .press(forDuration: 0.1,
             thenDragTo: plane.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.7)))

    let recents = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'recentColor-'"))
    XCTAssertTrue(
      recents.firstMatch.waitForExistence(timeout: 0.6),
      "No recent appeared shortly after release — commit-on-release regressed to a delay. Tree was:\n\(app.debugDescription)",
    )
  }

  // MARK: Private

  private var app: XCUIApplication!

  // MARK: - Helpers

  /// One named query, and the tree on failure. A chain that falls back to an index is
  /// a test that cannot go red — the lesson the contrast switcher taught.
  ///
  /// Existence is not enough to click on: switching tools resizes the window, and a
  /// click dispatched while the layout is still settling lands where the button used
  /// to be. Waiting on hittability rather than on existence is the difference between
  /// a synchronization point and a race.
  private func click(radioButton label: String, _ description: String) {
    let button = app.radioButtons[label]
    guard button.waitForExistence(timeout: 15) else {
      XCTFail("No radio button labelled \(label) (\(description)). Tree was:\n\(app.debugDescription)")
      return
    }
    guard waitUntilHittable(button) else {
      XCTFail("\(label) never became hittable (\(description)). Tree was:\n\(app.debugDescription)")
      return
    }
    button.click()
  }

  /// M36: the tool switcher moved into a sidebar of real `Button`s, identified rather
  /// than labelled — see `ToolSidebar`'s doc comment for why a label query would not
  /// survive its collapsed, icon-only rail.
  private func selectTool(_ title: String) {
    let button = app.buttons["tool-\(title.lowercased())"]
    guard button.waitForExistence(timeout: 15) else {
      XCTFail("No sidebar button for \(title). Tree was:\n\(app.debugDescription)")
      return
    }
    guard waitUntilHittable(button) else {
      XCTFail("\(title) sidebar row never became hittable. Tree was:\n\(app.debugDescription)")
      return
    }
    button.click()
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

  private func setField(_ text: String) {
    let field = app.textFields["colorInput"]
    XCTAssertTrue(field.waitForExistence(timeout: 30))
    field.click()
    field.typeKey("a", modifierFlags: .command)
    field.typeText(text)
  }

  /// Reads a readout's `value`, not its `label`.
  ///
  /// Setting `.accessibilityIdentifier` on a SwiftUI `Text` publishes the string as
  /// the element's *value* and leaves the label empty — so the obvious `.label` here
  /// silently returns `""` and every comparison fails against nothing.
  private func readout(_ identifier: String) -> String {
    let element = app.staticTexts[identifier]
    guard element.waitForExistence(timeout: 15) else {
      XCTFail("No readout \(identifier). Tree was:\n\(app.debugDescription)")
      return ""
    }
    return element.value as? String ?? ""
  }

  private func capture(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
