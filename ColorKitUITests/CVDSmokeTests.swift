//
//  CVDSmokeTests.swift
//  ColorKitUITests
//

import XCTest

/// The CVD panel, rendered.
///
/// The swatches are the point, and swatches say nothing to the accessibility tree — so,
/// as with the picker, the assertable surface is the panel's text readout: the
/// simulated color's own spelling. If the filter were a no-op, or the controls were not
/// wired to it, this readout would not move.
final class CVDSmokeTests: XCTestCase {
  // MARK: Internal

  override func setUpWithError() throws {
    continueAfterFailure = false
    app = XCUIApplication()
    // Without this, the run inherits whatever `Preferences` a previous run — or the
    // developer's own use of the app — last saved to the real `UserDefaults`. See
    // `ProjectsSmokeTests` for why the pairing with the AppKit opt-out is required
    // even though this suite has no persistence argument of its own to pair it with.
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

  /// The filter is not a no-op, and the deficiency control is wired to it.
  ///
  /// Pure red is confused by every red-green deficiency, so its simulated spelling
  /// cannot still be `#ff0000`; and protanomaly and deuteranomaly render it
  /// differently, so switching between them must move the readout. A panel that showed
  /// the swatches but forgot to pass the selection through would pass neither check.
  func testSimulatingRedChangesItAndTracksTheDeficiency() {
    setField("#ff0000")
    click(radioButton: "CVD", "the tool switcher")

    XCTAssertTrue(readout("cvdSeverity").contains("100%"), "Severity should start at full")

    let deuteranomaly = readout("cvdSimulated")
    XCTAssertTrue(deuteranomaly.hasPrefix("#"), "Simulated color should be a hex string")
    XCTAssertNotEqual(
      deuteranomaly.lowercased(), "#ff0000",
      "Deuteranomaly leaves pure red unchanged — the filter is not running",
    )
    capture("cvd-deuteranomaly")

    click(radioButton: "Protanomaly", "the deficiency picker")
    let protanomaly = readout("cvdSimulated")
    XCTAssertNotEqual(
      protanomaly, deuteranomaly,
      "Switching deficiency did not change the simulated color",
    )
    capture("cvd-protanomaly")
  }

  /// M21: every swatch here is a live handle, and the simulated one is the swatch a
  /// person actually wants to adopt — the color everything else on the panel exists to
  /// show them. Pure red simulated at full severity is never `#ff0000` again (the same
  /// fact the test above pins), so a changed field proves the click actually reached
  /// `SwatchButton`'s adopt path rather than doing nothing.
  func testClickingTheSimulatedSwatchAdoptsIt() {
    setField("#ff0000")
    click(radioButton: "CVD", "the tool switcher")

    click(button: "cvdSimulatedSwatch", "the simulated swatch")

    let adopted = fieldValue()
    XCTAssertNotEqual(
      adopted.lowercased(), "#ff0000",
      "Clicking the simulated swatch did not change the input field",
    )
  }

  // MARK: Private

  private var app: XCUIApplication!

  // MARK: - Helpers

  /// One named query, and the tree on failure — never a fallback chain. Hittability
  /// rather than existence, because switching tools resizes the window under a click
  /// already in flight.
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

  private func click(button identifier: String, _ description: String) {
    let button = app.buttons[identifier]
    guard button.waitForExistence(timeout: 15) else {
      XCTFail("No button \(identifier) (\(description)). Tree was:\n\(app.debugDescription)")
      return
    }
    guard waitUntilHittable(button) else {
      XCTFail("\(identifier) never became hittable (\(description)). Tree was:\n\(app.debugDescription)")
      return
    }
    button.click()
  }

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

  private func fieldValue() -> String {
    let field = app.textFields["colorInput"]
    guard field.waitForExistence(timeout: 15) else {
      XCTFail("No colorInput field. Tree was:\n\(app.debugDescription)")
      return ""
    }
    return field.value as? String ?? ""
  }

  /// Reads a readout's `value`, not its `label` — `.accessibilityIdentifier` on a
  /// SwiftUI `Text` publishes the string as the element's value and leaves the label
  /// empty.
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
