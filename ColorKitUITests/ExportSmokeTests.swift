//
//  ExportSmokeTests.swift
//  ColorKitUITests
//

import XCTest

/// The export panel, rendered and wired.
///
/// The document itself is generated in ColorCore and asserted exhaustively by
/// ``ExportTests``, so nothing here re-checks its syntax. What only a running app can
/// show is that the *controls reach it*: that picking a source swaps which colors are
/// written, that the shape menu swaps the wrapper, and that the name field renames every
/// property in the block. Each of those is a binding that compiles perfectly while doing
/// nothing.
///
/// **Nothing here clicks Copy.** It writes to the real system pasteboard, and a test has
/// no business clobbering whatever the person running it had copied — the same rule
/// ``ColorStoreTests`` follows. The button is asserted present and enabled instead, which
/// is the part that can regress; `Clipboard.copy` itself is one line with its own
/// coverage.
final class ExportSmokeTests: XCTestCase {
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

  /// The panel opens on a `:root` block for the color in the field.
  ///
  /// Also the check that a lone color is written `--brand` rather than `--brand-1`: an
  /// index suffix on a palette of one is a name nothing would reference, and it is the
  /// kind of detail that looks fine until you paste it.
  func testDefaultExportIsARootBlockForTheCurrentColor() {
    setField("#3b82f6")
    click(radioButton: "Export", "the tool switcher")
    capture("export-panel")

    let document = readout("exportDocument")
    XCTAssertTrue(document.contains(":root {"), "Expected a :root block, got:\n\(document)")
    XCTAssertTrue(
      document.contains("--brand:"),
      "A lone color should be --brand with no index suffix, got:\n\(document)",
    )
    XCTAssertTrue(
      document.contains("oklch("),
      "The default export format is oklch(), got:\n\(document)",
    )

    let copy = app.buttons["exportCopy"]
    XCTAssertTrue(copy.waitForExistence(timeout: 15), "No copy button. Tree:\n\(app.debugDescription)")
    XCTAssertTrue(copy.isEnabled, "The copy button is disabled with a document to copy")
  }

  /// The Save control is there to be used — and that is as far as a test can go.
  ///
  /// **Nothing here clicks it.** `.fileExporter` presents `NSSavePanel`, which is a
  /// separate process XCUITest cannot reach, so a test that clicked would hang on a panel
  /// it can neither fill in nor dismiss and would fail whether the feature worked or not.
  /// That is the same rule ``ProjectsSmokeTests`` follows for `fileImporter`, and it is
  /// not a gap that better test code would close: driving that panel from outside needs
  /// assistive access, which `osascript` does not have here.
  ///
  /// So the split is deliberate. The filename and content type are decided *before* the
  /// panel opens and are pinned by `ExportFileNamingTests`; the write itself is a recorded
  /// manual check in PLAN.md. What is left for a running app to show is that the button
  /// exists, is enabled with a document to save, and is actually reachable — which is
  /// exactly what a binding that compiled and did nothing would still pass, so the
  /// hittability assertion is the one carrying weight here.
  func testTheSaveControlIsThereToBeUsed() {
    setField("#3b82f6")
    click(radioButton: "Export", "the tool switcher")

    let save = app.buttons["exportSave"]
    XCTAssertTrue(
      save.waitForExistence(timeout: 15),
      "No save button. Tree:\n\(app.debugDescription)",
    )
    XCTAssertTrue(save.isEnabled, "The save button is disabled with a document to save")
    XCTAssertTrue(
      waitUntilHittable(save),
      "The save button never became hittable. Tree:\n\(app.debugDescription)",
    )

    // Saving has not been attempted, so the failure label must not be on screen. It is
    // the only thing that would tell us the panel had reported a problem it never had —
    // the mistake M9 shipped once already, with a banner announcing a failure that had
    // not happened.
    XCTAssertFalse(
      app.staticTexts["exportSaveError"].exists,
      "A save error is showing before anything was saved. Tree:\n\(app.debugDescription)",
    )
  }

  /// Switching the source rewrites the document from a different set of colors.
  ///
  /// The ramp is eleven stops and Tailwind's scale is eleven keys, so both ends of that
  /// alignment are checked here: `--brand-50` at the light end and `--brand-950` at the
  /// dark one. A naming table that had drifted to stopping at `900` would still produce
  /// a plausible-looking block, and this is where it fails.
  func testRampSourceWritesTheWholeTailwindScale() {
    setField("#3b82f6")
    click(radioButton: "Export", "the tool switcher")
    click(radioButton: "Ramp", "the export source picker")

    let document = readout("exportDocument")
    XCTAssertTrue(document.contains("--brand-50:"), "No light end in:\n\(document)")
    XCTAssertTrue(document.contains("--brand-500:"), "No middle in:\n\(document)")
    XCTAssertTrue(document.contains("--brand-950:"), "No dark end in:\n\(document)")

    // Eleven swatches, and the eleventh proves the row is the ramp rather than the
    // single color it was showing a moment ago.
    XCTAssertTrue(
      app.buttons["exportSwatch-10"].waitForExistence(timeout: 15),
      "Expected eleven ramp swatches. Tree:\n\(app.debugDescription)",
    )
    capture("export-ramp")
  }

  /// The shape menu swaps the wrapper, not just the label above it.
  ///
  /// Tailwind v3 is the shape furthest from the default — a JavaScript module rather than
  /// a CSS block — so it is the one where a binding that changed nothing would be most
  /// obvious.
  func testShapeMenuSwitchesToATailwindConfig() {
    setField("#3b82f6")
    click(radioButton: "Export", "the tool switcher")
    select(menuItem: "Tailwind v3", fromPopUp: "exportShape", "the shape picker")

    let document = readout("exportDocument")
    XCTAssertTrue(
      document.contains("module.exports"),
      "Expected a JavaScript config, got:\n\(document)",
    )
    XCTAssertTrue(
      document.contains("extend:"),
      "The config must extend the palette rather than replace it, got:\n\(document)",
    )
    capture("export-tailwind-config")
  }

  /// The name field reaches every property in the block.
  ///
  /// Typed on the ramp rather than on a single color so the assertion covers the suffix
  /// path too — a rename that only worked for the unkeyed case would pass on `--brand`
  /// and leave eleven `--brand-500`s behind.
  func testRenamingTheFamilyRewritesEveryProperty() {
    setField("#3b82f6")
    click(radioButton: "Export", "the tool switcher")
    click(radioButton: "Ramp", "the export source picker")

    let name = app.textFields["exportName"]
    guard name.waitForExistence(timeout: 15) else {
      XCTFail("No exportName field. Tree was:\n\(app.debugDescription)")
      return
    }
    name.click()
    name.typeKey("a", modifierFlags: .command)
    name.typeText("accent")

    let document = readout("exportDocument")
    XCTAssertTrue(document.contains("--accent-500:"), "Rename did not reach:\n\(document)")
    XCTAssertFalse(document.contains("--brand"), "The old name survives in:\n\(document)")
    capture("export-renamed")
  }

  /// A declaration is bare — no wrapper, no family name — and the name field goes away
  /// with it, because a `border` shorthand has nowhere to put one.
  func testDeclarationShapeDropsTheWrapperAndTheNameField() {
    setField("#3b82f6")
    click(radioButton: "Export", "the tool switcher")
    select(menuItem: "Declarations", fromPopUp: "exportShape", "the shape picker")

    let document = readout("exportDocument")
    XCTAssertFalse(document.contains(":root"), "A declaration needs no wrapper:\n\(document)")
    XCTAssertTrue(document.hasPrefix("color:"), "Expected a bare declaration, got:\n\(document)")
    XCTAssertFalse(
      app.textFields["exportName"].exists,
      "A bare declaration has nowhere to put a family name, so the field should be hidden",
    )
    capture("export-declaration")
  }

  /// The P3 shape writes two blocks and fixes both their spellings, so the Format picker
  /// goes away with the choice — the same claim the declaration test makes about the name
  /// field, and a sharper one: a live picker here could put `oklch()`, the panel's own
  /// default and unbounded, into the block a browser reaches when it *cannot* do wide
  /// gamut.
  ///
  /// The input is deliberately outside sRGB, which is the only case where the two blocks
  /// carry different values and so the only one where a document that ignored the media
  /// block would still look right.
  func testP3ShapeWritesBothBlocksAndHidesTheFormatPicker() {
    setField("color(display-p3 0 1 0)")
    click(radioButton: "Export", "the tool switcher")
    select(menuItem: "P3 with fallback", fromPopUp: "exportShape", "the shape picker")

    let document = readout("exportDocument")
    XCTAssertTrue(
      document.contains("@media (color-gamut: p3)"),
      "No media block in:\n\(document)",
    )
    XCTAssertTrue(document.contains("--brand: #"), "The fallback is not hex:\n\(document)")
    XCTAssertTrue(
      document.contains("--brand: color(display-p3"),
      "The override is not in P3:\n\(document)",
    )
    XCTAssertFalse(
      app.popUpButtons["exportFormat"].exists,
      "The shape fixes its own formats, so the picker should be hidden",
    )
    capture("export-p3-fallback")
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

  private func select(menuItem title: String, fromPopUp identifier: String, _ description: String) {
    let popUp = app.popUpButtons[identifier]
    guard popUp.waitForExistence(timeout: 15) else {
      XCTFail("No pop-up \(identifier) (\(description)). Tree was:\n\(app.debugDescription)")
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
