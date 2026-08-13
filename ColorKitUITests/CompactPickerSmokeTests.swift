//
//  CompactPickerSmokeTests.swift
//  ColorKitUITests
//

import XCTest

/// The header swatch's popover picker (M24): opening it from whatever tool is
/// showing, not only the Pick tab, and a drag inside it reaching the shared field.
///
/// See ``PickerSmokeTests`` for the Pick tab's own coverage of the three controls
/// this popover reuses (``PickerPlaneView``, ``PickerHueStripView``,
/// ``PickerAlphaSliderView``) — this file is only the popover-specific surface:
/// the trigger, the identifier collision the plane's `identifier` parameter exists
/// to avoid, and the empty-state hit target.
final class CompactPickerSmokeTests: XCTestCase {
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

  /// The write-back loop, end to end, reachable from a tool that has nothing to do
  /// with picking — Convert is the default tab, and the popover works from there.
  func testHeaderSwatchOpensAPopoverAndDraggingItWritesToTheField() {
    setField("#3b82f6")

    let swatch = app.buttons["headerSwatch"]
    guard swatch.waitForExistence(timeout: 15) else {
      XCTFail("No header swatch. Tree was:\n\(app.debugDescription)")
      return
    }
    guard waitUntilHittable(swatch) else {
      XCTFail("Header swatch never became hittable. Tree was:\n\(app.debugDescription)")
      return
    }
    swatch.click()

    let plane = app.otherElements["compactPickerPlane"]
    guard plane.waitForExistence(timeout: 15) else {
      XCTFail("Header swatch did not open the popover. Tree was:\n\(app.debugDescription)")
      return
    }

    let field = app.textFields["colorInput"]
    let before = field.value as? String
    plane.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.35))
      .press(forDuration: 0.1,
             thenDragTo: plane.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.7)))

    let after = field.value as? String
    XCTAssertNotEqual(after, before, "Dragging inside the popover did not reach the field")
  }

  /// The reason ``PickerPlaneView/identifier`` and its siblings take a distinct
  /// identifier per host: the header swatch sits above the tool switcher, so nothing
  /// stops opening the popover while already on the Pick tab, and the two planes
  /// have to resolve as two separate elements rather than one ambiguous query — the
  /// exact hazard CLAUDE.md's "never write a fallback chain of XCUITest queries"
  /// note exists to keep out.
  func testThePlaneAndItsPopoverCopyCanBothBeOnScreenAtOnce() {
    setField("#3b82f6")
    selectTool("Pick")

    XCTAssertTrue(
      app.otherElements["pickerPlane"].waitForExistence(timeout: 15),
      "the Pick tab's own plane should already be showing",
    )

    let swatch = app.buttons["headerSwatch"]
    guard waitUntilHittable(swatch) else {
      XCTFail("Header swatch never became hittable. Tree was:\n\(app.debugDescription)")
      return
    }
    swatch.click()

    guard app.otherElements["compactPickerPlane"].waitForExistence(timeout: 15) else {
      XCTFail("Popover plane never appeared beside the Pick tab's own. Tree was:\n\(app.debugDescription)")
      return
    }

    // Both present, and querying either identifier alone resolves to exactly one
    // element — the claim a shared identifier could not make.
    XCTAssertEqual(app.otherElements.matching(identifier: "pickerPlane").count, 1)
    XCTAssertEqual(app.otherElements.matching(identifier: "compactPickerPlane").count, 1)
  }

  /// The dashed empty state is a button too (M24), and specifically a button whose
  /// label — a stroked-only rectangle — has nothing filled to catch a click in the
  /// middle unless it claims its own content shape. Clicking dead center with no
  /// color typed is exactly the case that would silently do nothing without it.
  func testTheEmptyStateSwatchOpensThePopoverToo() {
    let field = app.textFields["colorInput"]
    XCTAssertTrue(field.waitForExistence(timeout: 30))
    field.click()
    field.typeKey("a", modifierFlags: .command)
    field.typeText("\u{8}") // backspace, clearing the selection to nothing
    XCTAssertEqual(field.value as? String, "")

    let swatch = app.buttons["headerSwatch"]
    guard waitUntilHittable(swatch) else {
      XCTFail("Header swatch never became hittable. Tree was:\n\(app.debugDescription)")
      return
    }
    swatch.click()

    XCTAssertTrue(
      app.otherElements["compactPickerPlane"].waitForExistence(timeout: 15),
      "Clicking the empty-state swatch did not open the popover. Tree was:\n\(app.debugDescription)",
    )
  }

  /// The claim `CompactPicker`'s own doc comment makes: "seeded from the store on
  /// appear." Open on blue, close by clicking the field (which is outside the
  /// popover), retype red, reopen, and a fresh alpha-only drag – which touches
  /// nothing but alpha – has to come back red, not the stale blue.
  ///
  /// Passes with `ColorInputField`'s `.id(pickerSession)` removed too – measured,
  /// not assumed away: macOS already discards a popover's content view, `@State`
  /// included, the moment it closes, so `.task { seedFromStore() }` re-runs on
  /// every open regardless. `.id(pickerSession)` is kept anyway as insurance
  /// against a future OS where that stops being true, not because this test
  /// discriminates it – nothing here can, since the behavior it would guard
  /// against isn't reproducible on this platform to begin with.
  func testReopeningThePopoverSeedsFromWhateverIsInTheFieldNow() {
    setField("#3b82f6")

    let swatch = app.buttons["headerSwatch"]
    guard waitUntilHittable(swatch) else {
      XCTFail("Header swatch never became hittable. Tree was:\n\(app.debugDescription)")
      return
    }
    swatch.click()
    guard app.otherElements["compactPickerPlane"].waitForExistence(timeout: 15) else {
      XCTFail("Popover never opened. Tree was:\n\(app.debugDescription)")
      return
    }

    // Clicking the field is a click outside the popover, which dismisses it – then
    // types the color the *next* open has to seed from.
    setField("#ff0000")
    XCTAssertFalse(
      app.otherElements["compactPickerPlane"].exists,
      "the popover should have closed when the field was clicked",
    )

    guard waitUntilHittable(swatch) else {
      XCTFail("Header swatch never became hittable a second time. Tree was:\n\(app.debugDescription)")
      return
    }
    swatch.click()

    let alpha = app.otherElements["compactPickerAlpha"]
    guard alpha.waitForExistence(timeout: 15) else {
      XCTFail("Popover did not reopen. Tree was:\n\(app.debugDescription)")
      return
    }

    // Alpha alone, so hue/saturation/value come through untouched from whatever
    // this open actually seeded from.
    alpha.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
      .press(forDuration: 0.1,
             thenDragTo: alpha.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))

    let field = app.textFields["colorInput"]
    let after = (field.value as? String ?? "").lowercased()
    XCTAssertTrue(
      after.hasPrefix("#ff0000"),
      "the reopened popover seeded from the stale blue instead of the retyped red: \(after)",
    )
  }

  /// The Pick tab and the popover are two independent hosts sharing one preference,
  /// `store.pickerMode` – and, before this test, only in one direction. Each panel's
  /// own switcher wrote the preference *and* its own local `PickerState.mode`
  /// together, so the two agreed as long as only one of them ever changed it. The
  /// header swatch sitting above the tool switcher means that stopped being true the
  /// moment the popover could open while the Pick tab is already showing: switching
  /// axes in the popover changed `store.pickerMode` but left `PickerPanel`'s own
  /// `state.mode` – and so its switcher, its plane, its readout – frozen on whatever
  /// it showed before, until the tool was left and re-entered.
  ///
  /// Both `RadioGroup`s are labelled "Axes" with "HSV"/"OKLCH" children, so this
  /// scopes through each group's own identifier (`app.radioGroups["pickerMode"]` /
  /// `["compactPickerMode"]`) rather than querying `app.radioButtons["OKLCH"]`
  /// directly – with both hosts open at once that query is ambiguous, the same
  /// hazard the plane's per-host `identifier` exists to keep out of *that* query.
  func testSwitchingAxesInThePopoverKeepsThePickTabInSync() {
    setField("#3b82f6")
    selectTool("Pick")

    let panelOKLCH = app.radioGroups["pickerMode"].radioButtons["OKLCH"]
    guard panelOKLCH.waitForExistence(timeout: 15) else {
      XCTFail("No OKLCH segment on the Pick tab's own switcher. Tree was:\n\(app.debugDescription)")
      return
    }
    XCTAssertEqual("\(panelOKLCH.value ?? "")", "0", "the Pick tab should start on HSV")

    let swatch = app.buttons["headerSwatch"]
    guard waitUntilHittable(swatch) else {
      XCTFail("Header swatch never became hittable. Tree was:\n\(app.debugDescription)")
      return
    }
    swatch.click()

    let popoverOKLCH = app.radioGroups["compactPickerMode"].radioButtons["OKLCH"]
    guard waitUntilHittable(popoverOKLCH) else {
      XCTFail("Popover's OKLCH segment never became hittable. Tree was:\n\(app.debugDescription)")
      return
    }
    popoverOKLCH.click()

    XCTAssertEqual(
      "\(panelOKLCH.value ?? "")", "1",
      "switching axes in the popover should update the Pick tab's own switcher too. Tree was:\n\(app.debugDescription)",
    )
  }

  // No UI test drives the mirror image of the one above — switching axes on the Pick
  // tab while the popover stays open. `CompactPicker` carries the symmetric
  // `.onChange(of: store.pickerMode)` for it anyway (`CompactPicker.swift`), but
  // measured directly: once the popover is open, every element in the main window
  // behind it reports `isHittable == false` and the whole `Application`/`Window`
  // subtree reads `Disabled` in `app.debugDescription` — reproducibly, confirmed
  // against an otherwise-identical test that opens the popover and interacts *inside*
  // it, which passes every time in the same run. That is the same shape of platform
  // limitation as XCUITest's inability to drive `NSOpenPanel` or a drag session: a
  // transient `NSPopover` takes key-window status while shown, so the window behind
  // it is not interactable from outside — not by a synthesized click and, as far as
  // this signature suggests, not by a real one either. A test built on clicking a
  // background control while the popover stays open would fail whether the feature
  // works or not, so none is written, per the standing rule against exactly that
  // shape of test. The forward direction above is the reachable half and is covered.

  // MARK: Private

  private var app: XCUIApplication!

  // MARK: - Helpers

  /// One named query, and the tree on failure. A chain that falls back to an index is
  /// a test that cannot go red — the lesson the contrast switcher taught.
  ///
  /// M36: the tool switcher moved into a sidebar of real `Button`s, identified rather
  /// than labelled — see `ToolSidebar`'s doc comment for why a label query would not
  /// survive its collapsed, icon-only rail. This file's other radio-button queries
  /// (`pickerMode`/`compactPickerMode`) go straight through `app.radioGroups[…]`
  /// rather than this helper, which is why there is no `click(radioButton:)` left to
  /// keep beside it.
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
}
