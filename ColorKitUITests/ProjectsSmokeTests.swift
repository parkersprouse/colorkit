//
//  ProjectsSmokeTests.swift
//  ColorKitUITests
//

import XCTest

/// The projects panel, against a store that evaporates.
///
/// **Every launch here passes `UITestInMemoryStore`.** XCUITest drives the shipping app,
/// so without it a test that saves a project would deposit it in the person's own
/// library and leave it there — and the next run would find it and assert against it.
/// The launch argument is the only way to reach that decision, the app being a separate
/// process.
///
/// What is worth testing here and nowhere else is the *round trip through the store*:
/// ``ProjectStoreTests`` proves a saved color comes back out of a `ModelContext`, but
/// only a running app can show that clicking a saved swatch puts the spelling back in
/// the field, and that a palette saved in one tool exports under its own name in
/// another.
final class ProjectsSmokeTests: XCTestCase {
  // MARK: Internal

  override func setUpWithError() throws {
    continueAfterFailure = false
    app = XCUIApplication()
    // The opt-out is not decoration. AppKit's `NSTreatUnknownArgumentsAsOpen` defaults
    // to on, so it reads a bare launch argument as a *file to open* — and an app asked
    // to open a document does not create its default window. The app still launches and
    // still reaches `.runningForeground`; it simply has a menu bar and nothing else, so
    // every query here fails against a tree with no window in it and the symptom reads
    // as a broken panel rather than a broken launch. Measured, not guessed: adding any
    // meaningless argument to a passing suite reproduced it exactly, and this pair fixed
    // it. The store argument itself keeps its bare spelling — a leading hyphen would be
    // claimed by `NSUserDefaults` instead, which is the opposite trap.
    // `UITestEphemeralPreferences` joins it for the same reason: without it this run
    // would inherit whatever `Preferences` a previous run — or the developer's own use
    // of the app — last saved to the real `UserDefaults`.
    app.launchArguments = [
      "-NSTreatUnknownArgumentsAsOpen", "NO", "UITestInMemoryStore", "UITestEphemeralPreferences",
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

  // MARK: - Tests

  /// The whole reason a saved color stores its text: recalling it returns *your*
  /// spelling. A store keeping only components would come back `#663399`, which is the
  /// same color and not the same answer.
  func testARecalledColorKeepsTheSpellingItWasSavedWith() {
    setField("rebeccapurple")
    click(radioButton: "Projects", "the tool switcher")
    createProject()

    clickButton("saveColor", "the save-color button")

    let swatch = app.buttons["savedColor-0"]
    XCTAssertTrue(
      swatch.waitForExistence(timeout: 15),
      "Nothing was saved. Tree was:\n\(app.debugDescription)",
    )
    XCTAssertEqual(
      swatch.label,
      "rebeccapurple",
      "A saved swatch carries its CSS as its accessibility label",
    )
    capture("projects-saved-color")

    // Move the field somewhere else, then click the saved color to bring it back.
    setField("#ff0000")
    XCTAssertTrue(waitUntilHittable(swatch), "The saved swatch never became clickable")
    swatch.click()

    XCTAssertEqual(
      fieldValue(),
      "rebeccapurple",
      "Recalling a saved color must return the spelling, not a canonicalized form",
    )
  }

  /// The seam M8 deferred, end to end: save a ramp in one tool, export it from another.
  ///
  /// Both halves matter. Eleven swatches prove the order and count survived the store —
  /// the entries come back out of an *unordered* SwiftData relationship, sorted by an
  /// explicit index. `--brand-500` proves the palette's own name reached
  /// `ExportOptions`, rather than the export panel keeping whatever it was last set to.
  func testASavedRampExportsUnderItsOwnName() {
    setField("#3b82f6")
    click(radioButton: "Projects", "the tool switcher")
    createProject()

    typeInto("saveName", "brand")
    select(menuItem: "Ramp", fromMenu: "saveSet", "the save-set menu")

    XCTAssertTrue(
      app.buttons["palette-0-swatch-10"].waitForExistence(timeout: 15),
      "Expected eleven saved ramp stops. Tree was:\n\(app.debugDescription)",
    )
    capture("projects-saved-ramp")

    clickButton("paletteExport-0", "the palette export button")

    let document = readout("exportDocument")
    XCTAssertTrue(
      document.contains("--brand-500:"),
      "A staged palette should export under its own name, got:\n\(document)",
    )
    XCTAssertTrue(
      document.contains("--brand-950:"),
      "The dark end of the saved ramp is missing from:\n\(document)",
    )
    capture("projects-exported-palette")
  }

  /// M20, end to end: a palette and a loose color, exported together as one document.
  ///
  /// The unit tests in `GroupedExportTests` and `StagedProjectTests` prove the renderer
  /// and the store side; what only a running app can show is that the panel's own
  /// button actually builds the groups from a real project and reaches the export
  /// panel, the same handoff `testASavedRampExportsUnderItsOwnName` proves for a single
  /// staged palette.
  func testExportProjectCombinesEveryPaletteAndLooseColor() {
    setField("#3b82f6")
    click(radioButton: "Projects", "the tool switcher")
    createProject()

    typeInto("saveName", "brand")
    select(menuItem: "Ramp", fromMenu: "saveSet", "the save-set menu")
    XCTAssertTrue(
      app.buttons["palette-0-swatch-10"].waitForExistence(timeout: 15),
      "Expected eleven saved ramp stops. Tree was:\n\(app.debugDescription)",
    )

    // A loose color, saved with no name — its group is named after its own text, the
    // same fallback the tile beneath it already shows.
    saveColors(["#ff0000"])

    clickButton("projectExport", "the export-project button")

    // The Source picker's sixth segment, actually reached rather than assumed — a
    // segment that gets swept into an overflow menu the way an eighth *tool* is known
    // to (see CLAUDE.md) would still leave `store.exportSource == .project` and a
    // correct document; only this checks the control itself renders as a usable
    // segment.
    let projectSegment = app.radioButtons["Project"]
    XCTAssertTrue(
      projectSegment.waitForExistence(timeout: 15),
      "No \"Project\" segment in the Source picker. Tree was:\n\(app.debugDescription)",
    )
    XCTAssertTrue(
      waitUntilHittable(projectSegment),
      "The \"Project\" segment never became hittable. Tree was:\n\(app.debugDescription)",
    )

    let document = readout("exportDocument")
    XCTAssertTrue(
      document.contains("--brand-500:"),
      "The palette's own name should reach the document, got:\n\(document)",
    )
    XCTAssertTrue(
      document.contains("--ff0000:"),
      "The loose color should export as its own single-entry group, got:\n\(document)",
    )
    capture("projects-exported-project")
  }

  /// Deleting a project takes its contents with it, and the panel returns to the state
  /// it started in. The cascade is asserted against a context in ``ProjectStoreTests``;
  /// what this adds is that the view stops showing what was deleted.
  func testDeletingAProjectClearsItsContents() {
    setField("#3b82f6")
    click(radioButton: "Projects", "the tool switcher")
    createProject()
    clickButton("saveColor", "the save-color button")
    XCTAssertTrue(app.buttons["savedColor-0"].waitForExistence(timeout: 15))

    clickButton("projectsDelete", "the delete-project button")
    // Scoped to the sheet. An app-wide `buttons["Delete Project"]` matches more than one
    // element — a confirmation dialog appears in the tree under both the app and its
    // window — and an ambiguous query fails at the click with no tree to read.
    let confirm = app.sheets.buttons["Delete Project"]
    XCTAssertTrue(
      confirm.waitForExistence(timeout: 15),
      "No confirmation sheet. Tree was:\n\(app.debugDescription)",
    )
    confirm.click()

    XCTAssertTrue(
      app.staticTexts["No projects yet"].waitForExistence(timeout: 15),
      "The panel should return to its empty state. Tree was:\n\(app.debugDescription)",
    )
    XCTAssertFalse(app.buttons["savedColor-0"].exists, "A deleted project's colors survived")
  }

  /// Reordering is proved against a container in `ProjectStoreTests`; what only a running
  /// app can show is that a command in the panel reaches it, and that the grid redraws in
  /// the new order rather than keeping a stale one.
  ///
  /// **This drives the menu commands, not the drag, and that is not a workaround.**
  /// XCUITest cannot start an AppKit dragging session — its synthesized events move the
  /// pointer without the drag ever beginning, so a drag-based test here would fail
  /// whether the feature worked or not. The menu commands exist because a drag-only
  /// reorder is unusable from the keyboard or VoiceOver in the first place; they share
  /// `move(from:to:)` with the drop handler, so this covers the path both use and leaves
  /// only the gesture that opens it uncovered.
  func testMoveCommandsReorderTheGrid() {
    click(radioButton: "Projects", "the tool switcher")
    createProject()
    saveColors(["#ff0000", "#00ff00", "#0000ff"])

    XCTAssertEqual(swatchLabels(count: 3), ["#ff0000", "#00ff00", "#0000ff"])

    // Right twice, so a handler that ignored its step or moved by a fixed amount fails.
    contextMenu("savedColor-0", item: "Move Right")
    XCTAssertTrue(
      waitForSwatchLabels(["#00ff00", "#ff0000", "#0000ff"]),
      "After one Move Right: \(swatchLabels(count: 3)). Tree was:\n\(app.debugDescription)",
    )

    contextMenu("savedColor-1", item: "Move Right")
    XCTAssertTrue(
      waitForSwatchLabels(["#00ff00", "#0000ff", "#ff0000"]),
      "After two: \(swatchLabels(count: 3)). Tree was:\n\(app.debugDescription)",
    )

    contextMenu("savedColor-0", item: "Move Right")
    contextMenu("savedColor-1", item: "Move Left")
    XCTAssertTrue(
      waitForSwatchLabels(["#00ff00", "#0000ff", "#ff0000"]),
      "Left must undo Right: \(swatchLabels(count: 3)). Tree was:\n\(app.debugDescription)",
    )
  }

  /// The reorder has to outlive the panel, not just the frame it happened in — the grid
  /// reads `orderedColors`, so a move that never reached `sortIndex` would still look
  /// right until something forced a refetch.
  func testAReorderSurvivesLeavingThePanel() {
    click(radioButton: "Projects", "the tool switcher")
    createProject()
    saveColors(["#ff0000", "#00ff00", "#0000ff"])

    contextMenu("savedColor-2", item: "Move Left")
    XCTAssertTrue(waitForSwatchLabels(["#ff0000", "#0000ff", "#00ff00"]))

    click(radioButton: "Convert", "the tool switcher")
    click(radioButton: "Projects", "the tool switcher")

    XCTAssertTrue(
      waitForSwatchLabels(["#ff0000", "#0000ff", "#00ff00"]),
      "Order after returning: \(swatchLabels(count: 3)). Tree was:\n\(app.debugDescription)",
    )
  }

  /// The other half of the loose-set feature: ticking colors the user chose by hand and
  /// keeping them together. `ProjectStoreTests` covers what gets stored; this covers that
  /// the tick marks and the button are wired to it at all.
  func testSavingASelectionMakesAPalette() {
    click(radioButton: "Projects", "the tool switcher")
    createProject()
    saveColors(["rebeccapurple": "brand", "#00ff00": "leaf", "#0000ff": "sky"],
               order: ["rebeccapurple", "#00ff00", "#0000ff"])

    // The first and the third, so a palette of everything would also fail this.
    clickButton("selectColor-0", "the first color's tick")
    clickButton("selectColor-2", "the third color's tick")
    clickButton("saveSelection", "the save-selection button")

    // `buttons`, not `otherElements` — M21 makes a palette swatch a `SwatchButton`, the
    // same live handle a saved color already is. Its accessibility label is always the
    // color's own CSS now (never the key, which would let two identical colors pass a
    // distinctness check they should fail), so this checks slot order by color instead.
    let firstEntry = app.buttons["palette-0-swatch-0"]
    XCTAssertTrue(
      firstEntry.waitForExistence(timeout: 15),
      "No palette was saved. Tree was:\n\(app.debugDescription)",
    )
    XCTAssertEqual(
      firstEntry.label.lowercased(), "#663399",
      "The first slot should be rebeccapurple, ticked first",
    )
    XCTAssertEqual(
      app.buttons["palette-0-swatch-1"].label.lowercased(), "#0000ff",
      "The second slot should be the third color ticked (#0000ff), skipping the untitled #00ff00",
    )
    XCTAssertFalse(
      app.buttons["palette-0-swatch-2"].exists,
      "Only the two ticked colors belong in the palette. Tree was:\n\(app.debugDescription)",
    )

    // The keys survive too, as the caption under each swatch now rather than as the
    // swatch's own label — see `ProjectsPanel.paletteRow`.
    XCTAssertTrue(
      app.staticTexts["brand"].exists,
      "The first entry's key should still be shown as a caption",
    )
    XCTAssertTrue(
      app.staticTexts["sky"].exists,
      "The second entry's key should still be shown as a caption",
    )

    // M21: a palette swatch is a live handle too, not just a labeled rectangle. Moving
    // the field elsewhere first is what makes the click provably the cause of the change,
    // the same shape ``testARecalledColorKeepsTheSpellingItWasSavedWith`` uses.
    setField("#111111")
    XCTAssertTrue(waitUntilHittable(firstEntry), "The palette swatch never became clickable")
    firstEntry.click()
    XCTAssertEqual(
      fieldValue().lowercased(), "#663399",
      "Clicking the palette swatch did not adopt rebeccapurple into the field",
    )
  }

  /// **The file path's affordance, and deliberately not the import.**
  ///
  /// M26 moved the old plain `Button` behind `Menu("Import")` — the tool switcher's own
  /// lesson, so the save-controls row stays at four controls rather than growing a fifth.
  /// Clicking "From File…" raises `NSOpenPanel`, which XCUITest cannot drive — the same
  /// shape as the drag-and-drop this suite declines to test, and for the same reason: a
  /// test that tried would fail whether the feature worked or not. So the assertion stops
  /// at what a running app can honestly be asked: the menu opens and both items are there,
  /// and neither is clicked.
  ///
  /// What M31 leaves uncovered here is the *file read* — the open panel, the sandbox, the
  /// security-scoped URL, and whether the sheet then presents pre-filled with the file's
  /// bytes. That last step is the milestone's one silently-fatal risk (a dead feature with
  /// a green suite) and is a **recorded manual check**, the same boundary as M17's read and
  /// M8b's write. The decode after the bytes reach the sheet is covered by
  /// ``PaletteImportTests``/``DesignTokenImportTests`` and the save by ``ProjectStoreTests``.
  /// "From Text…" is drivable and gets its own test below, since it opens a sheet rather
  /// than a system panel.
  func testTheImportMenuOffersBothImportPaths() {
    click(radioButton: "Projects", "the tool switcher")
    createProject()

    let menu = app.menuButtons["importMenu"]
    XCTAssertTrue(
      menu.waitForExistence(timeout: 15),
      "No import menu in the projects panel. Tree was:\n\(app.debugDescription)",
    )
    XCTAssertTrue(
      waitUntilHittable(menu),
      "The import menu never became hittable. Tree was:\n\(app.debugDescription)",
    )
    menu.click()

    XCTAssertTrue(
      app.menuItems["From Text…"].waitForExistence(timeout: 15),
      "No “From Text…” item. Tree was:\n\(app.debugDescription)",
    )
    XCTAssertTrue(
      app.menuItems["From File…"].waitForExistence(timeout: 15),
      "No “From File…” item. Tree was:\n\(app.debugDescription)",
    )
    app.typeKey(.escape, modifierFlags: [])
  }

  /// The end-to-end path a system panel can never give this suite: paste, confirm, and a
  /// palette exists. `:root` with two properties sharing the `brand-` prefix exercises
  /// the same segment-wise family inference `PaletteImportTests` checks in isolation —
  /// this is the one place it is checked reaching an actual saved `Palette`.
  func testImportingPastedCustomPropertiesCreatesAPalette() {
    click(radioButton: "Projects", "the tool switcher")
    createProject()

    select(menuItem: "From Text…", fromMenu: "importMenu", "the import menu")

    let sheet = app.sheets.firstMatch
    XCTAssertTrue(
      sheet.waitForExistence(timeout: 15),
      "No import sheet appeared. Tree was:\n\(app.debugDescription)",
    )

    let textBox = sheet.textViews["importSheetText"]
    XCTAssertTrue(
      textBox.waitForExistence(timeout: 15),
      "No paste box in the import sheet. Tree was:\n\(app.debugDescription)",
    )
    textBox.click()
    textBox.typeText(":root {\n  --brand-500: #3b82f6;\n  --brand-600: #ef4444;\n}")

    // The name field has to actually pick up the detected family — `onChange` needs
    // `initial: true` for this, since the field's container does not exist until the
    // first successful parse and the modifier would otherwise miss that first change.
    let nameField = sheet.textFields["importSheetName"]
    XCTAssertTrue(
      nameField.waitForExistence(timeout: 15),
      "No name field in the import sheet. Tree was:\n\(app.debugDescription)",
    )
    XCTAssertEqual(nameField.value as? String, "brand")

    let confirm = sheet.buttons["importSheetConfirm"]
    XCTAssertTrue(
      waitUntilHittable(confirm),
      "The Import button never became hittable. Tree was:\n\(app.debugDescription)",
    )
    confirm.click()

    XCTAssertTrue(
      app.buttons["paletteExport-0"].waitForExistence(timeout: 15),
      "No palette row appeared after import. Tree was:\n\(app.debugDescription)",
    )
    // `--brand-500` and `--brand-600` share the `brand` family, so this is one palette
    // of two — and M30's summary counts *kinds of group*, not entries. Pre-M30 this read
    // "Imported 2 colors", counting entries; that is exactly the preview/confirmation
    // disagreement M30 removed (the preview above counts groups too).
    XCTAssertTrue(
      readout("importSummary").hasPrefix("Imported 1 palette"),
      "Summary was: \(readout("importSummary"))",
    )
  }

  // MARK: Private

  private var app: XCUIApplication!

  // MARK: - Helpers

  /// One named query, and the tree on failure — never a fallback chain, which is a test
  /// that cannot fail. Hittability rather than existence, because switching tools
  /// resizes the window under a click already in flight.
  private func click(radioButton label: String, _ description: String) {
    let button = app.radioButtons[label]
    guard button.waitForExistence(timeout: 15) else {
      XCTFail(
        "No radio button labelled \(label) (\(description)). Tree was:\n\(app.debugDescription)",
      )
      return
    }
    guard waitUntilHittable(button) else {
      XCTFail("\(label) never became hittable (\(description)). Tree:\n\(app.debugDescription)")
      return
    }
    button.click()
  }

  private func clickButton(_ identifier: String, _ description: String) {
    let button = app.buttons[identifier]
    guard button.waitForExistence(timeout: 15) else {
      XCTFail("No button \(identifier) (\(description)). Tree was:\n\(app.debugDescription)")
      return
    }
    guard waitUntilHittable(button) else {
      XCTFail("\(identifier) never became hittable. Tree was:\n\(app.debugDescription)")
      return
    }
    button.click()
  }

  private func select(menuItem title: String, fromMenu identifier: String, _ description: String) {
    // `menuButtons`, not `popUpButtons`: a SwiftUI `Menu` renders as an AppKit
    // MenuButton, where a `Picker` renders as a pop-up. They are different queries and
    // the wrong one simply never matches.
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

  /// The panel opens on its empty state, so the first project is made through the button
  /// that sits there.
  private func createProject() {
    clickButton("projectsNew", "the new-project button")
    XCTAssertTrue(
      app.textFields["projectName"].waitForExistence(timeout: 15),
      "No project was created. Tree was:\n\(app.debugDescription)",
    )
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

  private func typeInto(_ identifier: String, _ text: String) {
    let field = app.textFields[identifier]
    guard field.waitForExistence(timeout: 15) else {
      XCTFail("No text field \(identifier). Tree was:\n\(app.debugDescription)")
      return
    }
    field.click()
    field.typeKey("a", modifierFlags: .command)
    field.typeText(text)
  }

  private func setField(_ text: String) {
    typeInto("colorInput", text)
  }

  private func fieldValue() -> String {
    app.textFields["colorInput"].value as? String ?? ""
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

  /// Types each CSS string into the field and saves it, leaving the grid in that order.
  private func saveColors(_ css: [String]) {
    saveColors([:], order: css)
  }

  /// The same, optionally naming each color as it is saved.
  private func saveColors(_ names: [String: String], order css: [String]) {
    for (index, text) in css.enumerated() {
      setField(text)
      if let name = names[text] {
        typeInto("saveName", name)
      }
      clickButton("saveColor", "the save-color button")
      XCTAssertTrue(
        app.buttons["savedColor-\(index)"].waitForExistence(timeout: 15),
        "\(text) was not saved. Tree was:\n\(app.debugDescription)",
      )
    }
  }

  /// Right-clicks a tile and picks one of its commands.
  private func contextMenu(_ identifier: String, item title: String) {
    let element = app.buttons[identifier]
    guard element.waitForExistence(timeout: 15), waitUntilHittable(element) else {
      XCTFail("No hittable \(identifier). Tree was:\n\(app.debugDescription)")
      return
    }
    element.rightClick()

    let item = app.menuItems[title]
    guard item.waitForExistence(timeout: 15) else {
      XCTFail("No item \(title) on \(identifier). Tree was:\n\(app.debugDescription)")
      return
    }
    item.click()
  }

  /// The grid's swatches in order. Each carries its CSS as its accessibility label, which
  /// is the only handle a test has on a row of colored rectangles.
  private func swatchLabels(count: Int) -> [String] {
    (0 ..< count).map { app.buttons["savedColor-\($0)"].label }
  }

  private func waitForSwatchLabels(_ expected: [String], timeout: TimeInterval = 15) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if swatchLabels(count: expected.count) == expected {
        return true
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    return swatchLabels(count: expected.count) == expected
  }

  private func capture(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
