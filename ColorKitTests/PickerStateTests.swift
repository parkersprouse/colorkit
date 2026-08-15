//
//  PickerStateTests.swift
//  ColorKitTests
//

@testable import ColorKit
import Foundation
import Testing

/// The picker's model, tested without a picker.
///
/// Everything here is a decision that produces no visible symptom until it produces a
/// maddening one — a hue that resets, a slider that stutters, a cursor that walks while
/// nobody is touching it.
@Suite("Picker state")
struct PickerStateTests {
  // MARK: Internal

  // MARK: - What gets written

  /// The heart of the OKLCH mode, and the assertion that fails the moment somebody
  /// simplifies the two formats into one.
  ///
  /// hex is 8-bit sRGB. Writing an OKLCH pick as hex would quantize it onto that grid
  /// and — because the store re-parses whatever it is handed — bring it back as an
  /// **sRGB** color. The mode's own axes would then be derived from a color in a
  /// different space on every frame, and chroma would snap to whatever the 8-bit grid
  /// allows.
  @Test("An OKLCH pick is written as oklch(), exactly")
  func oklchIsWrittenLosslessly() throws {
    var state = oklchState()
    let text = state.cssToWrite()
    let returned = try CSSColorParser.parse(text).color

    #expect(text.hasPrefix("oklch("), "wrote \(text)")
    #expect(returned.space == .oklch, "came back as \(returned.space.rawValue)")
    #expect(abs(returned.components.x - 0.6231) < 1e-9)
    #expect(abs(returned.components.y - 0.1885) < 1e-9)
    #expect(abs(returned.components.z - 259.81) < 1e-9)
  }

  /// A chroma step far below what 8 bits can resolve still produces a different
  /// string. Under hex both of these collapse to the same six digits, which is what
  /// makes a chroma slider feel like it is catching on something.
  @Test("Sub-8-bit chroma steps survive the round trip")
  func fineChromaStepsAreDistinct() {
    var coarse = oklchState(chroma: 0.1880)
    var fine = oklchState(chroma: 0.1881)

    #expect(coarse.cssToWrite() != fine.cssToWrite())
  }

  /// hex where hex is the right currency. An HSV pick is an sRGB color by
  /// construction, and 8 bits is the resolution the square is drawn at anyway.
  @Test("An HSV pick is written as hex")
  func hsvIsWrittenAsHex() throws {
    var state = PickerState()
    state.hsvHue = 217
    state.saturation = 76
    state.value = 96

    let text = state.cssToWrite()
    #expect(text.hasPrefix("#"), "wrote \(text)")
    #expect(try CSSColorParser.parse(text).color.space == .srgb)
  }

  /// A pick deliberately outside sRGB has to survive being written down, or drawing
  /// the gamut boundary would be pointless — you could see the edge but never cross
  /// it.
  @Test("A pick past the sRGB edge is stored intact")
  func wideChromaIsNotClampedAway() throws {
    var state = oklchState(lightness: 0.7, chroma: 0.35, hue: 140)
    let returned = try CSSColorParser.parse(state.cssToWrite()).color

    #expect(returned.exceedsSRGB)
    #expect(abs(returned.components.y - 0.35) < 1e-9)
  }

  /// The counterpart to ``wideChromaIsNotClampedAway`` — with wide gamut disallowed
  /// (M22's `store.webFriendly`), the same pick is pulled inside sRGB before it is
  /// written, rather than surviving intact.
  @Test("allowingWideGamut: false pulls the write inside sRGB")
  func wideChromaIsClampedWhenWideGamutIsDisallowed() throws {
    var state = oklchState(lightness: 0.7, chroma: 0.35, hue: 140)
    let text = state.cssToWrite(allowingWideGamut: false)
    let returned = try CSSColorParser.parse(text).color

    #expect(!returned.exceedsSRGB, "leaked past sRGB: \(text)")
    #expect(!text.contains("color("), "promoted to color() despite wide gamut being disallowed")
  }

  @Test("Alpha reaches the written value")
  func alphaIsWritten() throws {
    var state = oklchState()
    state.alpha = 0.4

    let returned = try CSSColorParser.parse(state.cssToWrite()).color
    #expect(abs(returned.alpha - 0.4) < 1e-9)
  }

  // MARK: - Reading back

  /// The guard that keeps the picker from arguing with itself: what it just wrote is
  /// not news.
  @Test("Its own write does not re-seed the axes")
  func ownWriteIsIgnored() throws {
    var state = oklchState()
    let text = state.cssToWrite()
    let color = try CSSColorParser.parse(text).color

    state.chroma = 0.25 // as if a drag moved on before the observation landed
    state.syncing(with: text, color: color)

    #expect(state.chroma == 0.25, "the picker re-seeded from its own write")
  }

  /// Somebody else typing in the field, on the other hand, is exactly what the panel
  /// has to follow.
  @Test("An outside edit does re-seed the axes")
  func outsideEditIsAdopted() throws {
    var state = oklchState()
    _ = state.cssToWrite()

    let typed = try CSSColorParser.parse("#ff0000").color
    state.syncing(with: "#ff0000", color: typed)

    #expect(abs(state.oklchHue - 29.2339) < 1e-3)
    #expect(abs(state.chroma - 0.2577) < 1e-3)
  }

  /// A field cleared to nothing leaves the cursor where it was rather than dropping
  /// it on black — the same choice ``ColorField`` makes about invalid input.
  @Test("An empty field leaves the axes alone")
  func emptyFieldKeepsTheCursor() {
    var state = oklchState()
    state.syncing(with: "", color: nil)

    #expect(state.chroma == 0.1885)
  }

  // MARK: - Hue that outlives its color

  /// Drag saturation to zero and the color is gray, which has no hue. Adopting the
  /// zero that falls out of the conversion would swing the strip to red and hand back
  /// a different color on the way out.
  @Test("A gray does not reset the hue")
  func achromaticColorsKeepTheChosenHue() throws {
    var state = PickerState()
    state.hsvHue = 217
    state.saturation = 80
    state.value = 90
    _ = state.cssToWrite()

    try state.syncing(with: "#808080", color: CSSColorParser.parse("#808080").color)

    #expect(state.hsvHue == 217, "hue jumped to \(state.hsvHue)")
    #expect(state.saturation == 0)
  }

  @Test("A gray does not reset the OKLCH hue either")
  func achromaticColorsKeepTheOKLCHHue() throws {
    var state = oklchState()
    _ = state.cssToWrite()

    try state.syncing(with: "#808080", color: CSSColorParser.parse("#808080").color)

    #expect(state.oklchHue == 259.81, "hue jumped to \(state.oklchHue)")
    #expect(state.chroma < 1e-6)
  }

  /// Black is the other case with no hue, and also no value to derive one from.
  @Test("Black does not reset the hue")
  func blackKeepsTheChosenHue() throws {
    var state = PickerState()
    state.hsvHue = 140
    state.saturation = 50
    state.value = 50
    try state.syncing(with: "#000000", color: CSSColorParser.parse("#000000").color)

    #expect(state.hsvHue == 140)
  }

  // MARK: - Switching axes

  /// The two modes describe one color, so switching may not move it. Deriving the new
  /// axes from whatever the other mode was last left at would.
  @Test("Switching axes carries the color across")
  func modeSwitchPreservesTheColor() {
    var state = PickerState()
    state.hsvHue = 217
    state.saturation = 76
    state.value = 96
    let before = state.color

    state.setMode(.oklch)

    #expect(state.mode == .oklch)
    #expect(state.color.deltaEOK(to: before) < 1e-9)
  }

  /// And back again, which is the direction that can lose something: OKLCH can hold
  /// colors HSV cannot.
  @Test("Switching to HSV from a wide color lands on the nearest sRGB one")
  func modeSwitchFromWideColorMapsIn() {
    var state = oklchState(lightness: 0.7, chroma: 0.35, hue: 140)
    let wide = state.color
    #expect(wide.exceedsSRGB)

    state.setMode(.hsv)

    #expect(state.color.inGamut(of: .srgb, epsilon: 1e-9))
    // Mapped, not clipped: chroma is given up, hue is kept.
    #expect(state.color.deltaEOK(to: wide.gamutMapped(to: .srgb)) < 1e-9)
  }

  /// The bug that only appears from the outside: the panel opens on HSV, so a wide
  /// color typed into the field has already been mapped into the cube by the time the
  /// user reaches for the OKLCH tab. Carrying *those* axes across would narrow
  /// `oklch(0.7 0.3 140)` to chroma 0.2366 for no reason the user could see.
  ///
  /// Passing the field's color instead keeps it, and HSV is left as what it is — a
  /// view of the color, not a stage it has to pass through.
  @Test("Switching to OKLCH restores a wide color rather than the mapped one")
  func modeSwitchCarriesTheFieldsColor() throws {
    let wide = try CSSColorParser.parse("oklch(0.7 0.3 140)").color

    var state = PickerState()
    state.seed(from: wide)
    #expect(state.color.exceedsSRGB == false, "HSV cannot hold this color, by construction")

    state.setMode(.oklch, carrying: wide)

    #expect(abs(state.chroma - 0.3) < 1e-9, "chroma narrowed to \(state.chroma)")
    #expect(abs(state.lightness - 0.7) < 1e-9)
    #expect(abs(state.oklchHue - 140) < 1e-9)
  }

  /// Without a color to carry it falls back to the current axes, which is the old
  /// behavior and still the right answer when there is nothing more authoritative.
  @Test("Switching with nothing to carry uses the current axes")
  func modeSwitchWithoutACarriedColor() {
    var state = PickerState()
    state.hsvHue = 217
    state.saturation = 76
    state.value = 96
    let before = state.color

    state.setMode(.oklch, carrying: nil)

    #expect(state.color.deltaEOK(to: before) < 1e-9)
  }

  @Test("Switching to the mode already showing changes nothing")
  func redundantModeSwitchIsANoOp() {
    var state = oklchState()
    state.setMode(.oklch)

    #expect(state.chroma == 0.1885)
    #expect(state.lightness == 0.6231)
  }

  // MARK: - Committing a gesture (M24)

  /// The web-friendly chroma clamp used to be private to `PickerPanel.apply(_:)` and
  /// reachable only through a running app. Extracting the three gestures into their
  /// own views for M24 moved the clamp onto `PickerState` itself, which is what makes
  /// this a unit test rather than a recorded manual check.
  @MainActor
  @Test("A drag past the sRGB edge is clamped under web-friendly mode")
  func committingClampsUnderWebFriendly() throws {
    let store = ColorStore(initialInput: "oklch(0.7 0.35 140)")
    store.webFriendly = true
    var state = oklchState(lightness: 0.7, chroma: 0.35, hue: 140)

    // No further change to make — the seed itself is already past the edge, the
    // same shape a hue-strip drag leaving a chroma the new hue cannot hold would
    // produce.
    let text = state.committing({ _ in }, in: store)

    #expect(state.chroma < 0.35, "chroma was not clamped: \(state.chroma)")
    let returned = try CSSColorParser.parse(text).color
    #expect(!returned.exceedsSRGB, "wrote a color outside sRGB despite web-friendly mode: \(text)")
  }

  /// The counterpart — with the flag off, the identical drag is left untouched, the
  /// same distinction ``wideChromaIsNotClampedAway`` draws for `cssToWrite` alone.
  @MainActor
  @Test("The same drag is untouched with web-friendly mode off")
  func committingLeavesWideChromaAloneByDefault() throws {
    let store = ColorStore(initialInput: "oklch(0.7 0.35 140)")
    var state = oklchState(lightness: 0.7, chroma: 0.35, hue: 140)

    let text = state.committing({ _ in }, in: store)

    #expect(abs(state.chroma - 0.35) < 1e-9)
    let returned = try CSSColorParser.parse(text).color
    #expect(returned.exceedsSRGB)
  }

  /// `committing`'s round trip: the text it hands back is exactly what
  /// ``syncing(with:color:)`` recognizes as this picker's own write, so calling the
  /// two back to back does not re-seed the axes and undo the change just made.
  ///
  /// This is *not* a test of `committing`'s calling convention — why it returns the
  /// text rather than assigning `store.inputText` from inside its own body. That
  /// choice matters only through the `@Binding` indirection every real caller
  /// (`PickerPlaneView` and its siblings) reaches `self` through: reading a binding's
  /// property, mutating it, and writing it back are three separate steps, and writing
  /// the store ahead of the last one would observe a stale `lastWritten`. A plain
  /// local `var`, as used here, has no such indirection — `self` mutates in place
  /// with no copy-back to race — so no ordering bug in `committing` could make this
  /// particular assertion fail either way. The claim below is real and worth pinning;
  /// the `@Binding` race is a reasoned justification for the calling convention, not
  /// something a unit test can observe.
  @MainActor
  @Test("A committed change round-trips through the store without misreading its own write")
  func committingRoundTripsThroughTheStoreWithoutMisreadingItsOwnWrite() {
    let store = ColorStore(initialInput: "#3b82f6")
    var state = oklchState()

    store.inputText = state.committing({ $0.chroma = 0.2 }, in: store)
    state.syncing(with: store.inputText, color: store.color)

    #expect(state.chroma == 0.2, "the picker mistook its own write for an outside edit")
  }

  // MARK: Private

  private func oklchState(
    lightness: Double = 0.6231,
    chroma: Double = 0.1885,
    hue: Double = 259.81,
  ) -> PickerState {
    var state = PickerState()
    state.setMode(.oklch)
    state.lightness = lightness
    state.chroma = chroma
    state.oklchHue = hue
    return state
  }
}
