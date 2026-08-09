//
//  TransformSmokeTests.swift
//  ColorKitUITests
//

import XCTest

/// The transform panel, rendered and wired.
///
/// Every section of this panel emits *swatches*, and swatches say nothing at all to the
/// accessibility tree — the same problem the picker and CVD panels have. Two surfaces are
/// assertable instead, and between them they cover the whole chain:
///
/// 1. **The swatch buttons carry their own CSS as an accessibility label.** That is not a
///    testing affordance bolted on; an unlabelled color chip announces nothing to
///    VoiceOver either. It also means a harmony that silently produced the same color
///    four times could not pass.
/// 2. **Clicking one changes the input field.** The field is the app's source of truth, so
///    a changed field proves the entire path: harmony computed, button wired, `adopt`
///    called, text serialized losslessly and re-parsed.
final class TransformSmokeTests: XCTestCase {
  // MARK: Internal

  override func setUpWithError() throws {
    continueAfterFailure = false
    app = XCUIApplication()
    // See `ProjectsSmokeTests` for why this pairs with the AppKit opt-out even though
    // this suite has no persistence argument of its own to pair it with.
    app.launchArguments = ["-NSTreatUnknownArgumentsAsOpen", "NO", "UITestEphemeralPreferences"]
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

  // MARK: - Tests

  /// A triad really is three *different* colors, and clicking one adopts it.
  ///
  /// The default harmony is a triad, so the row is three swatches with the base marked
  /// at index 0. If the rotation were a no-op — or if the swatches were announcing an
  /// SF Symbol name instead of their color, which is the trap M6 fell into — the
  /// distinctness check would fail rather than quietly pass.
  func testTriadIsThreeDistinctColorsAndAdoptingOneChangesTheField() {
    setField("#3b82f6")
    click(radioButton: "Transform", "the tool switcher")
    capture("transform-panel")

    let base = swatchLabel("transformHarmony-0")
    let second = swatchLabel("transformHarmony-1")
    let third = swatchLabel("transformHarmony-2")

    XCTAssertFalse(base.isEmpty, "The base swatch has no accessibility label")
    XCTAssertNotEqual(base, second, "A triad produced the same color twice")
    XCTAssertNotEqual(second, third, "A triad produced the same color twice")

    click(button: "transformHarmony-1", "the second triad member")

    let adopted = fieldValue()
    XCTAssertNotEqual(
      adopted.lowercased(), "#3b82f6",
      "Clicking a harmony member did not change the input field",
    )
    // Transform results are written in OKLCH, losslessly — see `apply` in the panel.
    XCTAssertTrue(
      adopted.hasPrefix("oklch("),
      "Expected an oklch() spelling so nothing is quantized away, got \(adopted)",
    )
    capture("transform-after-adopting")
  }

  /// The adjust readout starts as the color itself, and the sliders are wired to it.
  ///
  /// Checked by moving a slider rather than by trusting the initial value: an identity
  /// adjustment showing the input color proves nothing on its own, since a panel that
  /// ignored the sliders entirely would show exactly the same thing.
  func testAdjustReadoutTracksTheSliders() {
    setField("#3b82f6")
    click(radioButton: "Transform", "the tool switcher")

    let unchanged = readout("transformAdjusted")
    XCTAssertFalse(unchanged.isEmpty, "The adjusted readout is empty")

    let lightness = app.sliders["Lightness"]
    guard lightness.waitForExistence(timeout: 15) else {
      XCTFail("No Lightness slider. Tree was:\n\(app.debugDescription)")
      return
    }
    lightness.adjust(toNormalizedSliderPosition: 0.85)

    let adjusted = readout("transformAdjusted")
    XCTAssertNotEqual(
      adjusted, unchanged,
      "Moving the lightness slider did not change the adjusted color",
    )

    // And Apply commits it, which is the only thing that touches the field.
    click(button: "transformApply", "the apply button")
    XCTAssertTrue(
      fieldValue().hasPrefix("oklch("),
      "Apply did not write the adjusted color to the field",
    )
  }

  /// The ramp is eleven stops by default and the middle one is the user's own color.
  func testRampMarksTheBaseInTheMiddle() {
    setField("#3b82f6")
    click(radioButton: "Transform", "the tool switcher")

    let middle = swatchLabel("transformRamp-5")
    let lightEnd = swatchLabel("transformRamp-0")
    let darkEnd = swatchLabel("transformRamp-10")

    XCTAssertFalse(middle.isEmpty, "The middle ramp stop has no accessibility label")
    XCTAssertNotEqual(lightEnd, middle, "The light end matches the base")
    XCTAssertNotEqual(darkEnd, middle, "The dark end matches the base")
    XCTAssertNotEqual(lightEnd, darkEnd, "The ramp's two ends are the same color")
    scrollDown(4)
    capture("transform-ramp")
  }

  /// The mix strip spans the pair, and adopting a stop writes it to the field.
  ///
  /// The default pair is `#3b82f6` on white, so the first stop is the color itself, the
  /// last is white, and the middle is neither. Distinctness is what carries the test: a
  /// strip that ignored the background, or ignored the amount, would render five
  /// swatches carrying the same label and still look like a gradient in a screenshot.
  func testMixStripSpansThePairAndAdoptingAStopChangesTheField() {
    setField("#3b82f6")
    click(radioButton: "Transform", "the tool switcher")

    let start = swatchLabel("transformMix-0")
    let middle = swatchLabel("transformMix-2")
    let end = swatchLabel("transformMix-4")

    XCTAssertFalse(middle.isEmpty, "The middle mix stop has no accessibility label")
    XCTAssertNotEqual(start, middle, "The mix strip never leaves the panel's own color")
    XCTAssertNotEqual(middle, end, "The mix strip never reaches the background")
    XCTAssertNotEqual(start, end, "Both ends of the mix strip are the same color")

    scrollDown(6)
    capture("transform-mix")

    click(button: "transformMix-2", "the middle mix stop")
    XCTAssertTrue(
      fieldValue().hasPrefix("oklch("),
      "Adopting a mix stop did not write it to the field, got \(fieldValue())",
    )
  }

  /// The solver reports the pair it was given and offers a way out of a failing one.
  ///
  /// `#3b82f6` on white is 3.68:1 — the pair the contrast panel's own screenshots use —
  /// so AA body text fails and there is exactly one direction to go, since nothing is
  /// lighter than white.
  func testSolverOffersAWayOutOfAFailingPair() {
    setField("#3b82f6")
    click(radioButton: "Transform", "the tool switcher")

    XCTAssertTrue(
      readout("transformCurrentRatio").contains("3.68"),
      "Expected the known 3.68:1 for #3b82f6 on white, got \(readout("transformCurrentRatio"))",
    )

    let darker = app.buttons["transformSolution-darker"]
    guard darker.waitForExistence(timeout: 15) else {
      XCTFail("No darker solution offered. Tree was:\n\(app.debugDescription)")
      return
    }
    XCTAssertFalse(
      app.buttons["transformSolution-lighter"].exists,
      "Nothing is lighter than a white background, so there should be no lighter solution",
    )
    scrollDown(8)
    capture("transform-solver")

    darker.click()
    XCTAssertTrue(
      fieldValue().hasPrefix("oklch("),
      "Adopting the solution did not write it to the field",
    )
  }

  /// The manual half of the contrast tool: drag, and the ratio moves.
  ///
  /// `#3b82f6` on white starts at 3.68:1 and the away direction is *darker*, so pushing
  /// right must raise the ratio. Checked by reading the live figure rather than by
  /// trusting the slider's sign — which is the whole point of the control, since the
  /// sign means opposite things in the two polarities.
  func testPushingRaisesTheLiveRatio() {
    setField("#3b82f6")
    click(radioButton: "Transform", "the tool switcher")

    XCTAssertTrue(
      readout("transformCurrentRatio").contains("3.68"),
      "Expected the known 3.68:1 starting point",
    )

    let push = app.sliders["Push"]
    guard push.waitForExistence(timeout: 15) else {
      XCTFail("No Push slider. Tree was:\n\(app.debugDescription)")
      return
    }
    // Reading an off-screen element is fine; *dragging* one is not, and this slider
    // sits well below the fold.
    scrollDown(8)
    guard waitUntilHittable(push) else {
      XCTFail("Push slider never became hittable. Tree was:\n\(app.debugDescription)")
      return
    }
    // The slider spans -0.4...0.4, so 0.9 of the way along is a firm shove apart.
    push.adjust(toNormalizedSliderPosition: 0.9)

    let pushed = readout("transformPushed")
    XCTAssertFalse(pushed.isEmpty, "Pushing produced no color")
    capture("transform-push")

    click(button: "transformUsePushed", "the push apply button")
    XCTAssertTrue(
      fieldValue().hasPrefix("oklch("),
      "Using the pushed color did not write it to the field",
    )
    // Pushing apart raises contrast, so the adopted color must beat where it started.
    // The readout reads "now 14.02:1", so strip both ends rather than just the ":1".
    let after = readout("transformCurrentRatio")
    let ratio = Double(
      after
        .replacingOccurrences(of: "now ", with: "")
        .replacingOccurrences(of: ":1", with: "")
        .trimmingCharacters(in: .whitespaces),
    ) ?? 0
    XCTAssertGreaterThan(
      ratio, 3.68,
      "Pushing apart did not raise the ratio — it reads \(after)",
    )
  }

  /// Both directions at once, on a background chosen to make that possible.
  ///
  /// `#757575` is not arbitrary. AA body text is reachable *upward* only while
  /// `(l + 0.05) × 4.5 ≤ 1.05` and *downward* only while `(l + 0.05) / 4.5 ≥ 0.05`, so
  /// the band where both hold is a sliver of luminance — `0.175` to `0.1833` — sitting
  /// right on the `√21` crossover where the contrast ceiling bottoms out. Gray 117
  /// lands at `0.1779`, inside it. Anywhere else and one of these two buttons is
  /// legitimately absent, which is what the white-background test above checks.
  func testAMidToneBackgroundOffersBothDirections() {
    setField("#3b82f6")

    click(radioButton: "Contrast", "the tool switcher")
    let background = app.textFields["backgroundInput"]
    guard background.waitForExistence(timeout: 15) else {
      XCTFail("No backgroundInput field. Tree was:\n\(app.debugDescription)")
      return
    }
    background.click()
    background.typeKey("a", modifierFlags: .command)
    background.typeText("#757575")

    click(radioButton: "Transform", "the tool switcher")

    let lighter = app.buttons["transformSolution-lighter"]
    let darker = app.buttons["transformSolution-darker"]
    XCTAssertTrue(
      lighter.waitForExistence(timeout: 15),
      "No lighter solution on a mid-tone background. Tree was:\n\(app.debugDescription)",
    )
    XCTAssertTrue(darker.exists, "No darker solution on a mid-tone background")
    scrollDown(8)
    capture("transform-solver-both-directions")
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
      XCTFail(
        "No radio button labelled \(label) (\(description)). Tree was:\n\(app.debugDescription)",
      )
      return
    }
    guard waitUntilHittable(button) else {
      XCTFail(
        "\(label) never became hittable (\(description)). Tree was:\n\(app.debugDescription)",
      )
      return
    }
    button.click()
  }

  private func click(button identifier: String, _ description: String) {
    let button = app.buttons[identifier]
    guard button.waitForExistence(timeout: 15) else {
      XCTFail(
        "No button \(identifier) (\(description)). Tree was:\n\(app.debugDescription)",
      )
      return
    }
    guard waitUntilHittable(button) else {
      XCTFail(
        "\(identifier) never became hittable (\(description)). Tree was:\n\(app.debugDescription)",
      )
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

  /// A swatch button's label, which is the CSS of the color it stands for.
  private func swatchLabel(_ identifier: String) -> String {
    let button = app.buttons[identifier]
    guard button.waitForExistence(timeout: 15) else {
      XCTFail("No swatch \(identifier). Tree was:\n\(app.debugDescription)")
      return ""
    }
    return button.label
  }

  private func capture(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  /// Scrolls the panel so a lower section is actually in the frame.
  ///
  /// XCUITest reads off-screen elements happily, so the assertions above do not need
  /// this — but a screenshot of a section below the fold is a screenshot of the section
  /// above it, and these captures are the milestone's visual record.
  private func scrollDown(_ ticks: Int) {
    let scrollView = app.scrollViews.firstMatch
    guard scrollView.waitForExistence(timeout: 15) else {
      XCTFail("No scroll view to scroll. Tree was:\n\(app.debugDescription)")
      return
    }
    for _ in 0 ..< ticks {
      scrollView.scroll(byDeltaX: 0, deltaY: -120)
    }
  }
}
