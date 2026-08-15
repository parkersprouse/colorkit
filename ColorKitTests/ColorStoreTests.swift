//
//  ColorStoreTests.swift
//  ColorKitTests
//

import Carbon.HIToolbox
@testable import ColorKit
import Foundation
import Testing

/// - Note: Nothing here calls ``ColorStore/copy(_:)``. It writes to the real system
///   pasteboard, and a test suite has no business clobbering whatever the person
///   running it had copied.
@MainActor
@Suite("Color store")
struct ColorStoreTests {
  @Test("Starts on a parsed color")
  func initialState() throws {
    let store = ColorStore(initialInput: "rebeccapurple")
    let color = try #require(store.color)

    #expect(color == ColorValue.srgb8(102, 51, 153))
    #expect(store.parsed.error == nil)
    #expect(store.recents.isEmpty)
  }

  @Test("Empty input clears the color")
  func emptyInputClears() {
    let store = ColorStore(initialInput: "red")
    store.inputText = "   "

    #expect(store.color == nil)
    #expect(store.parsed == .empty)
  }

  /// The behavior that makes live parsing bearable. Every prefix of `#3b82f6` is
  /// typed on the way to it, and most of them are invalid; blanking the whole
  /// conversion panel on each one reads as the app breaking, not as feedback.
  @Test("An invalid edit keeps the last good color on screen")
  func invalidEditRetainsLastColor() throws {
    let store = ColorStore(initialInput: "#3b82f6")
    let before = try #require(store.color)

    store.inputText = "#3b82f"

    #expect(store.color == before)
    #expect(store.parsed.error != nil)
  }

  @Test("Warnings surface without failing the parse")
  func warningsAreReported() {
    let store = ColorStore(initialInput: "oklch(0.7, 0.15, 250)")

    #expect(store.color != nil)
    #expect(store.parsed.error == nil)
    #expect(store.parsed.warnings == [.commasInModernFunction("oklch")])
  }

  // MARK: - Recents

  @Test("Remembering keeps the authored text, not a canonical form")
  func recentsPreserveAuthoredText() throws {
    let store = ColorStore(initialInput: "rebeccapurple")
    store.remember()

    let recent = try #require(store.recents.first)
    #expect(recent.text == "rebeccapurple")
    #expect(recent.color == ColorValue.srgb8(102, 51, 153))
  }

  @Test("The same color moves to the front instead of piling up")
  func recentsDedupeByValue() {
    let store = ColorStore(initialInput: "red")
    store.remember()
    store.inputText = "blue"
    store.remember()
    // A different spelling of a color already in the list.
    store.inputText = "#ff0000"
    store.remember()

    #expect(store.recents.count == 2)
    #expect(store.recents.first?.text == "#ff0000")
  }

  /// Colors are deduplicated by value, and a value carries its space. `rgb()` and
  /// `hsl()` describe the same pixel but are not the same authored color — which
  /// space a color lives in is exactly what this app refuses to discard.
  @Test("The same pixel in two spaces stays two entries")
  func recentsKeepSpaceDistinction() {
    let store = ColorStore(initialInput: "rgb(255 0 0)")
    store.remember()
    store.inputText = "hsl(0 100% 50%)"
    store.remember()

    #expect(store.recents.count == 2)
  }

  @Test("Recents are capped")
  func recentsAreCapped() {
    let store = ColorStore(initialInput: "red")
    for value in 0 ..< 40 {
      store.inputText = "rgb(\(value) 0 0)"
      store.remember()
    }

    #expect(store.recents.count == 12)
    // Newest first.
    #expect(store.recents.first?.text == "rgb(39 0 0)")
  }

  /// M23: lowering the limit trims an already-full list immediately, rather than
  /// waiting for the next ``ColorStore/remember()`` to notice — the Settings
  /// Stepper's own label reads `store.recentLimit`, and it would otherwise say a
  /// number the list hasn't caught up to yet.
  @Test("Lowering recentLimit truncates an already-full list")
  func loweringRecentLimitTruncates() {
    let store = ColorStore(initialInput: "red")
    for value in 0 ..< 5 {
      store.inputText = "rgb(\(value) 0 0)"
      store.remember()
    }
    #expect(store.recents.count == 5)

    store.recentLimit = 3

    #expect(store.recents.count == 3)
    // Newest first, so trimming drops the oldest three, not the newest.
    #expect(store.recents.map(\.text) == ["rgb(4 0 0)", "rgb(3 0 0)", "rgb(2 0 0)"])
  }

  @Test("Nothing invalid reaches recents")
  func invalidInputIsNotRemembered() {
    let store = ColorStore(initialInput: "not-a-color")
    store.remember()

    #expect(store.recents.isEmpty)
  }

  @Test("Choosing a recent restores the text that made it")
  func usingARecentRestoresItsText() {
    let store = ColorStore(initialInput: "oklch(0.7 0.15 250)")
    store.remember()
    store.inputText = "red"

    store.use(store.recents[0])

    #expect(store.inputText == "oklch(0.7 0.15 250)")
    #expect(store.color?.space == .oklch)
  }

  @Test("Adopting a color writes it into the field")
  func adoptWritesInput() {
    let store = ColorStore(initialInput: "")
    store.adopt(.srgb8(59, 130, 246))

    #expect(store.inputText == "#3b82f6")
    #expect(store.color == ColorValue.srgb8(59, 130, 246))
  }

  /// The trap `adopt` has to dodge. This store keeps *text* as its source of truth,
  /// so an adopted color is serialized and immediately parsed back — and hex is
  /// 8-bit sRGB. Spelling a P3 sample as hex would gamut-map it on the way in and
  /// hand back a color the screen never showed, undoing the entire point of reading
  /// the pixel in a wide space to begin with.
  @Test("Adopting a wide-gamut color does not quietly flatten it into sRGB")
  func adoptPreservesWideGamut() throws {
    let store = ColorStore(initialInput: "")
    let p3Red = ColorValue(space: .displayP3, 1, 0, 0)
    store.adopt(p3Red)

    let readBack = try #require(store.color)
    #expect(readBack.exceedsSRGB, "the trip through text flattened the color")
    #expect(readBack.deltaEOK(to: p3Red) < 1e-9)

    // The obvious spelling, shown next to the working one. hex has to gamut-map to
    // exist at all, and what comes back is a color the display never showed.
    let asHex = try #require(p3Red.cssString(as: .hex))
    let viaHex = try CSSColorParser.parse(asHex).color
    #expect(!viaHex.exceedsSRGB)
    #expect(viaHex.deltaEOK(to: p3Red) > 0.01)
  }

  /// Display precision and storage precision are separate settings for a reason: a
  /// panel that rounds re-derives from the original next frame, while a stored
  /// string that rounds has destroyed it.
  @Test("Adoption ignores the display precision the user picked")
  func adoptIgnoresDisplayPrecision() throws {
    let store = ColorStore(initialInput: "")
    store.formatOptions.precision = 2 // "Minimum"

    // Deliberately outside sRGB, so adoption takes the `color(display-p3 …)`
    // branch where precision is actually expressible — a color hex could spell
    // would round-trip through 8-bit integers and prove nothing about digits.
    // colorjs.io 0.7.0 puts these coordinates out of sRGB, and confirms that
    // rounding them to two decimals costs ΔEOK 0.00124 — a difference this
    // assertion is six orders of magnitude tighter than.
    let sampled = ColorValue(space: .displayP3, 0.9876543210, 0.1234567891, 0.0246813579)
    store.adopt(sampled)

    let readBack = try #require(store.color)
    #expect(readBack.exceedsSRGB)
    #expect(readBack.deltaEOK(to: sampled) < 1e-9)
  }

  /// Alpha is the component most easily lost, because the default alpha policy omits
  /// it whenever a color is opaque.
  @Test("Adopting keeps partial alpha")
  func adoptKeepsAlpha() throws {
    let store = ColorStore(initialInput: "")
    store.adopt(ColorValue(space: .srgb, 1, 0, 0, alpha: 0.4))

    let readBack = try #require(store.color)
    #expect(abs(readBack.alpha - 0.4) < 1e-9)
  }

  // MARK: - Web-friendly mode (M22)

  /// The counterpart to ``adoptPreservesWideGamut`` above, with the flag on: now the
  /// mode's whole promise is that the field receives an sRGB spelling instead. hex
  /// alone would prove nothing here — hex `cannotRepresentOutOfGamut`, so it maps a
  /// wide sample regardless of the flag — so this checks the `.oklch` preferred
  /// format too, which is unbounded and would otherwise carry the wide value straight
  /// through untouched.
  @Test(
    "Under webFriendly, adopting a wide-gamut color writes an sRGB spelling",
    arguments: [CSSOutputFormat.hex, .oklch],
  )
  func adoptClampsWideGamutUnderWebFriendly(format: CSSOutputFormat) throws {
    let store = ColorStore(initialInput: "")
    store.webFriendly = true
    let p3Red = ColorValue(space: .displayP3, 1, 0, 0)
    store.adopt(p3Red, preferring: format)

    #expect(!store.inputText.contains("color("), "leaked the color() family: \(store.inputText)")
    let readBack = try #require(store.color)
    #expect(!readBack.exceedsSRGB, "the mode's whole promise: \(store.inputText)")
  }

  /// `adoptBackground` is the same derivation aimed at a different field (M21), so
  /// it needs the identical guard — a wide "Use as background" swatch is just as
  /// real a leak as a wide foreground adopt.
  @Test("Under webFriendly, adoptBackground also writes an sRGB spelling")
  func adoptBackgroundClampsWideGamutUnderWebFriendly() throws {
    let store = ColorStore(initialInput: "", initialBackground: "")
    store.webFriendly = true
    store.adoptBackground(ColorValue(space: .displayP3, 1, 0, 0), preferring: .oklch)

    #expect(!store.backgroundText.contains("color("))
    let readBack = try #require(store.backgroundColor)
    #expect(!readBack.exceedsSRGB)
  }

  /// Off is the default, and off must stay exactly what ``adoptPreservesWideGamut``
  /// already pins — the flag changes nothing about ordinary adoption.
  @Test("webFriendly false leaves adopt exactly as before M22")
  func adoptUnaffectedWhenWebFriendlyIsOff() throws {
    let store = ColorStore(initialInput: "")
    store.webFriendly = false
    let p3Red = ColorValue(space: .displayP3, 1, 0, 0)
    store.adopt(p3Red)

    let readBack = try #require(store.color)
    #expect(readBack.exceedsSRGB)
  }

  // MARK: - Background

  /// The point of extracting `ColorField`: the background gets live parsing and the
  /// retained-last-good behavior for free rather than from a second implementation
  /// that could drift from the first.
  @Test("The background parses independently of the foreground")
  func backgroundParsesIndependently() {
    let store = ColorStore(initialInput: "#000000", initialBackground: "rebeccapurple")

    #expect(store.color == ColorValue.srgb8(0, 0, 0))
    #expect(store.backgroundColor == ColorValue.srgb8(102, 51, 153))

    store.backgroundText = "oklch(0.7 0.15 250)"
    #expect(store.backgroundColor?.space == .oklch)
    #expect(store.color == ColorValue.srgb8(0, 0, 0), "editing the background moved the foreground")
  }

  @Test("An invalid background edit keeps the last good background")
  func backgroundRetainsLastGoodColor() {
    let store = ColorStore(initialInput: "#000000", initialBackground: "#ffffff")
    store.backgroundText = "#fff"
    store.backgroundText = "#ff"

    #expect(store.backgroundParsed.error != nil)
    #expect(store.backgroundColor == ColorValue.srgb8(255, 255, 255))
  }

  /// Swapping matters because APCA is asymmetric — the two directions genuinely
  /// score differently, and this is how you see both without retyping either.
  @Test("Swapping exchanges both colors, text and all")
  func swapExchangesBothColors() {
    let store = ColorStore(initialInput: "rebeccapurple", initialBackground: "#ffffff")
    store.swapForegroundAndBackground()

    #expect(store.inputText == "#ffffff")
    #expect(store.backgroundText == "rebeccapurple")
    #expect(store.color == ColorValue.srgb8(255, 255, 255))
    #expect(store.backgroundColor == ColorValue.srgb8(102, 51, 153))
  }

  /// The background counterpart to ``adoptWritesInput`` — a `SwatchButton`'s "Use as
  /// background" menu item needs exactly this seam for a color with no authored text of
  /// its own, and it must not touch the foreground field.
  @Test("Adopting a color into the background writes it there and nowhere else")
  func adoptBackgroundWritesBackground() {
    let store = ColorStore(initialInput: "red")
    store.adoptBackground(.srgb8(59, 130, 246))

    #expect(store.backgroundText == "#3b82f6")
    #expect(store.backgroundColor == ColorValue.srgb8(59, 130, 246))
    #expect(store.inputText == "red", "adopting into the background moved the foreground")
  }

  @Test("Swapping twice is the identity")
  func swapIsItsOwnInverse() {
    let store = ColorStore(initialInput: "oklch(0.7 0.15 250)", initialBackground: "#fef08a")
    store.swapForegroundAndBackground()
    store.swapForegroundAndBackground()

    #expect(store.inputText == "oklch(0.7 0.15 250)")
    #expect(store.backgroundText == "#fef08a")
  }

  // MARK: - Output

  @Test("Format options flow through to every row")
  func formatOptionsApply() throws {
    let store = ColorStore(initialInput: "#ffcc00")
    store.formatOptions.uppercaseHex = true
    store.formatOptions.collapseHex = true

    let hex = try #require(store.formats.first { $0.format == .hex })
    #expect(hex.css == "#FC0")
  }

  @Test("No color means no rows")
  func noColorMeansNoFormats() {
    let store = ColorStore(initialInput: "")
    #expect(store.formats.isEmpty)
  }

  // MARK: - Notation menu (M25)

  /// The headline claim: every format in the catalog can re-spell `rebeccapurple`
  /// exactly, so choosing any of them from the menu has to round-trip. In-gamut and
  /// keyword-nameable on purpose — the same reason `ExportRoundTripTests.base` picks
  /// an 8-bit sRGB color — so `.keyword` gets a meaningful case instead of the vacuous
  /// no-op it would be against an unnamed color.
  @Test("Choosing a format from the notation menu round-trips the color", arguments: CSSOutputFormat.catalog)
  func respellRoundTripsEveryFormat(format: CSSOutputFormat) throws {
    let store = ColorStore(initialInput: "rebeccapurple")
    let before = try #require(store.color)

    store.respell(as: format)

    let after = try #require(store.color)
    #expect(after.deltaEOK(to: before) < 1e-7, "\(format) round-tripped to \(store.inputText)")
  }

  /// The honest exception the round-trip test above doesn't exercise: a format that
  /// `cannotRepresentOutOfGamut` maps rather than losing the color, and it maps
  /// **as the format that was chosen** — this is the behavior that makes ``respell``
  /// a different method from ``adopt(_:preferring:)`` rather than a thin wrapper
  /// around it. `adopt`'s `spelling(preferring:)` would see that hex can't hold a
  /// Display P3 red and silently substitute `color(display-p3 …)` instead; a click on
  /// "hex" in the menu means hex.
  @Test("Re-spelling into a format that cannotRepresentOutOfGamut maps instead of substituting another format")
  func respellGamutMapsInsteadOfSubstitutingFormat() throws {
    let store = ColorStore(initialInput: "color(display-p3 1 0 0)")
    #expect(try #require(store.color).exceedsSRGB)

    store.respell(as: .hex)

    #expect(store.inputText.hasPrefix("#"), "got \(store.inputText) instead of a hex string")
    #expect(try !(#require(store.color).exceedsSRGB))
  }

  /// The same trap ``adoptIgnoresDisplayPrecision`` pins for `adopt`: this string
  /// becomes the field's new source of truth and is immediately re-parsed, so
  /// rounding it to the panel's display precision would be a permanent loss, not a
  /// cosmetic one.
  @Test("Re-spelling ignores the display precision the user picked")
  func respellIgnoresDisplayPrecision() throws {
    let precise = ColorValue(space: .displayP3, 0.9876543210, 0.1234567891, 0.0246813579)
    let text = try #require(precise.cssString(as: .color(.displayP3), options: .lossless))
    let store = ColorStore(initialInput: text)
    store.formatOptions.precision = 2 // "Minimum"
    let before = try #require(store.color)

    store.respell(as: .oklch)

    let after = try #require(store.color)
    #expect(
      after.deltaEOK(to: before) < 1e-7,
      "display precision (\(store.formatOptions.precision)) leaked into \(store.inputText)",
    )
  }

  /// `.keyword` is the only format ``ColorValue/formatted(as:options:)`` ever answers
  /// `nil` for, and the menu is built by filtering those out — but ``respell(as:)``
  /// guards the same way independently, so a caller that reached it anyway (or a
  /// future menu that forgot to filter) fails safely instead of blanking the field.
  /// `rgb()`, not hex, and that choice is load-bearing: a mutation that falls back to
  /// hex instead of no-opping would be invisible against `#3b82f6` as the starting
  /// text, since that color's hex spelling and its typed spelling are the same
  /// string. `rgb(59 130 246)` names the identical color but not identically, so a
  /// fallback-to-hex mutation changes `store.inputText` and this test catches it.
  @Test("Re-spelling into a format that can't name the color leaves the field untouched")
  func respellNoOpsWhenTheColorCannotBeNamed() {
    let store = ColorStore(initialInput: "rgb(59 130 246)") // not one of the 148 keywords
    let before = store.inputText

    store.respell(as: .keyword)

    #expect(store.inputText == before)
  }

  /// The counterpart to ``adoptClampsWideGamutUnderWebFriendly``: `oklch()` is
  /// unbounded and `.lossless` does not gamut-map it, so without pulling the color
  /// into sRGB first, re-spelling a wide-gamut color that was typed in before the
  /// mode was switched on would leave it spelled outside sRGB despite the mode being
  /// on.
  @Test("Under webFriendly, re-spelling into a perceptual format still clamps to sRGB")
  func respellClampsUnderWebFriendly() throws {
    let store = ColorStore(initialInput: "color(display-p3 1 0 0)")
    store.webFriendly = true

    store.respell(as: .oklch)

    let after = try #require(store.color)
    #expect(!after.exceedsSRGB, "the mode's whole promise: \(store.inputText)")
  }

  /// Off is the default, and off must leave `respell` exactly as
  /// ``respellRoundTripsEveryFormat`` already pins for a chosen wide format — the flag
  /// changes nothing about ordinary re-spelling.
  @Test("webFriendly false leaves re-spelling unclamped")
  func respellUnaffectedWhenWebFriendlyIsOff() throws {
    let store = ColorStore(initialInput: "color(display-p3 1 0 0)")
    store.webFriendly = false

    store.respell(as: .oklch)

    let after = try #require(store.color)
    #expect(after.exceedsSRGB)
  }

  // MARK: - Global shortcut (M27)

  /// A fresh `ColorStore` never calls `activateGlobalShortcut()` — every other test in
  /// this suite relies on that to avoid claiming a real system-wide chord — so
  /// `globalShortcutIsActive` is `false` here, which routes `updateGlobalShortcut`
  /// through its cheapest branch: write the value, touch no Carbon API at all. That is
  /// exactly what makes this deterministic and safe to run in parallel with every
  /// other test in the suite.
  @Test("Recording an eligible chord while inactive commits it directly")
  func updateGlobalShortcutCommitsWhenInactive() {
    let store = ColorStore()
    let candidate = GlobalShortcut(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(cmdKey), keyLabel: "D")

    #expect(store.updateGlobalShortcut(candidate))
    #expect(store.globalShortcut == candidate)
  }

  /// The predicate itself is pinned in `GlobalHotKeyTests`; this is the boundary that
  /// actually matters — a caller cannot end up with an ineligible chord committed by
  /// going through the store.
  @Test("Recording an ineligible chord is refused and leaves the shortcut unchanged")
  func updateGlobalShortcutRejectsIneligibleChord() {
    let store = ColorStore()
    let before = store.globalShortcut
    let ineligible = GlobalShortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: 0, keyLabel: "A")

    #expect(!store.updateGlobalShortcut(ineligible))
    #expect(store.globalShortcut == before)
  }

  @Test("Recording the chord already in effect is a no-op success")
  func updateGlobalShortcutNoOpsOnTheSameChord() {
    let store = ColorStore()

    #expect(store.updateGlobalShortcut(store.globalShortcut))
    #expect(store.globalShortcut == .sampleColor)
  }

  /// The one test in this suite that claims a real system-wide chord, which is why it
  /// is deliberately the four-modifier probe `GlobalHotKeyTests` uses rather than
  /// ``GlobalShortcut/sampleColor`` — the running host claims that one the moment its
  /// own scenes appear, and racing it would make this flaky. Proves the *active*
  /// branch of `updateGlobalShortcut`: rebinding while already registered both claims
  /// the new chord and genuinely releases the old one, checked by re-claiming the old
  /// chord afterward — `GlobalHotKeyCenter.register` would fail with
  /// `eventHotKeyExistsErr` if it were still held.
  @Test("Rebinding while active releases the previous chord and claims the new one")
  func updateGlobalShortcutRebindsWhileActive() {
    let center = GlobalHotKeyCenter.shared
    center.unregisterAll()
    defer { center.unregisterAll() }

    let store = ColorStore()
    let first = GlobalShortcut(keyCode: UInt32(kVK_ANSI_Q), modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey), keyLabel: "Q")
    let second = GlobalShortcut(keyCode: UInt32(kVK_ANSI_W), modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey), keyLabel: "W")

    store.globalShortcut = first
    store.activateGlobalShortcut()
    #expect(store.globalShortcutIsActive)

    #expect(store.updateGlobalShortcut(second))
    #expect(store.globalShortcut == second)
    #expect(store.globalShortcutIsActive)

    // `first` must be free again — held, this fails with `eventHotKeyExistsErr`.
    #expect(center.register(first) {}, "the previous chord was not released")
  }
}
