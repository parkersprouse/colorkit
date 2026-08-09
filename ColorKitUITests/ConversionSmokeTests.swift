//
//  ConversionSmokeTests.swift
//  ColorKitUITests
//

import XCTest

/// End-to-end coverage of the one path unit tests cannot reach: text in the field
/// becoming rendered rows on screen.
///
/// Replaces the Xcode template's UI tests, which launched the app three times —
/// including once inside a `measure` loop — and asserted nothing at all. Those
/// launches were pure cost: seconds on every run, and an app instance left behind
/// whenever one failed to terminate.
///
/// - Note: Rows are queried as **buttons**, not static texts. `FormatRow` wraps its
///   label and value in a `Button`, and SwiftUI merges a button's children into one
///   accessibility element whose label is the concatenation — so a row reads as
///   `"hsl(), hsl(217.22 91.22% 59.8%)"` and no `StaticText` for the value exists.
final class ConversionSmokeTests: XCTestCase {
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
    // Terminate explicitly rather than trusting the runner to clean up. This app
    // has a MenuBarExtra, so a surviving instance leaves an icon in the menu bar
    // that looks like a second copy of the app and cannot be clicked — the exact
    // symptom that prompted this file.
    app?.terminate()
    // …and wait for it to actually be gone. `terminate()` returns before the
    // process does, so the next test's `launch()` can race a bundle still shutting
    // down and fail with "does not have a process ID". Observed once in five runs
    // before this wait was added.
    _ = app?.wait(for: .notRunning, timeout: 30)
    app = nil
  }

  /// Precision is relative to each component's scale, and this is the only test
  /// that proves it survives the trip through the real view. A hue printed to four
  /// decimals — `hsl(217.2193 …)` — is the defect being guarded against.
  func testPanelRendersEveryFormatAtReadablePrecision() {
    XCTAssertTrue(
      row("Hex", "#3b82f6").waitForExistence(timeout: 30),
      "The conversion panel never rendered its default color",
    )

    for (title, css) in [
      ("rgb()", "rgb(59 130 246)"),
      ("hsl()", "hsl(217.22 91.22% 59.8%)"),
      ("hwb()", "hwb(217.22 23.14% 3.53%)"),
      ("oklch()", "oklch(0.6231 0.188 259.81)"),
      ("oklab()", "oklab(0.6231 -0.0332 -0.1851)"),
      ("lch()", "lch(54.62% 66.37 277.59)"),
      ("lab()", "lab(54.62% 8.76 -65.79)"),
      ("color(display-p3)", "color(display-p3 0.3047 0.5035 0.9338)"),
      ("color(xyz-d65)", "color(xyz-d65 0.2642 0.2355 0.9034)"),
    ] {
      XCTAssertTrue(row(title, css).exists, "Missing row: \(title) → \(css)")
    }
  }

  /// Typing a color no sRGB screen can show must reach the panel *and* be marked,
  /// so a value that was quietly moved never reads as an exact answer.
  func testOutOfGamutColorIsBadgedOnBoundedFormatsOnly() {
    let field = app.textFields["colorInput"]
    XCTAssertTrue(field.waitForExistence(timeout: 30))

    field.click()
    field.typeKey("a", modifierFlags: .command)
    field.typeText("oklch(0.9 0.3 140)")

    // OKLCH is unbounded, so it holds the color exactly and carries no badge.
    let exact = row("oklch()", "oklch(0.9 0.3 140)")
    XCTAssertTrue(exact.waitForExistence(timeout: 15), "The typed color never reached the panel")

    let badged = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "mapped"))
    XCTAssertGreaterThan(badged.count, 0, "An out-of-sRGB color produced no gamut badge")
    XCTAssertFalse(exact.label.contains("mapped"), "oklch() holds this color exactly")
  }

  /// M13 is core-only in code but a user reaches it by typing, so this is the one
  /// check that the whole path — field, parser, `CalcExpression`, every conversion —
  /// works in the running app rather than only under `#expect`.
  ///
  /// The expression is chosen so the arithmetic is checkable by eye and each
  /// operator appears once: `128 * 2 - 1` is 255, `0 * 5` is 0, `255 / 2` is 127.5,
  /// and that last one is also the case a slash-as-alpha-separator bug would turn
  /// into a three-component color with an alpha of 2.
  func testCalcExpressionReachesThePanel() {
    let field = app.textFields["colorInput"]
    XCTAssertTrue(field.waitForExistence(timeout: 30))

    field.click()
    field.typeKey("a", modifierFlags: .command)
    field.typeText("rgb(calc(128 * 2 - 1) calc(0 * 5) calc(255 / 2))")

    XCTAssertTrue(
      row("Hex", "#ff0080").waitForExistence(timeout: 15),
      "A calc() expression never reached the panel",
    )
  }

  /// M14, same reasoning as the calc() case above: core-only in code, but a user
  /// reaches it by typing, so the running app is where the whole path gets checked.
  ///
  /// `oklch(from #3b82f6 calc(l * 0.5) c h)` is the expression PLAN.md said the
  /// milestone's value lives in — halve a color's lightness while holding its chroma
  /// and hue. The panel's own oklch() row is the readout, and the untouched
  /// components are what prove the origin was converted rather than re-derived:
  /// the chroma and hue match `#3b82f6`'s to the digit.
  func testRelativeColorReachesThePanel() {
    let field = app.textFields["colorInput"]
    XCTAssertTrue(field.waitForExistence(timeout: 30))

    field.click()
    field.typeKey("a", modifierFlags: .command)
    field.typeText("oklch(from #3b82f6 calc(l * 0.5) c h)")

    XCTAssertTrue(
      row("oklch()", "oklch(0.3115 0.188 259.81)").waitForExistence(timeout: 15),
      "A relative color never reached the panel",
    )
  }

  // MARK: Private

  private var app: XCUIApplication!

  private func row(_ title: String, _ css: String) -> XCUIElement {
    app.buttons["\(title), \(css)"]
  }
}
