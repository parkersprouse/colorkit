//
//  ColorStore.swift
//  ColorKit
//

import Foundation
import Observation

/// The result of parsing whatever is currently in the input field.
///
/// Three states rather than an optional, because "nothing typed yet" and "typed
/// something wrong" want opposite treatment in the UI: one is a hint, the other is an
/// error.
enum ParsedInput: Equatable {
  case empty
  case failed(ParseError)
  case parsed(ParseResult)

  // MARK: Lifecycle

  init(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      self = .empty
      return
    }
    do {
      self = try .parsed(CSSColorParser.parse(trimmed))
    } catch {
      self = .failed(error)
    }
  }

  // MARK: Internal

  var color: ColorValue? {
    if case let .parsed(result) = self {
      result.color
    } else {
      nil
    }
  }

  var error: ParseError? {
    if case let .failed(error) = self {
      error
    } else {
      nil
    }
  }

  var warnings: [ParseWarning] {
    if case let .parsed(result) = self {
      result.warnings
    } else {
      []
    }
  }
}

/// One editable color: the text, and whatever it currently parses to.
///
/// Extracted when contrast arrived, because the app went from editing one color to
/// editing a pair and will keep going — harmony bases, palette entries. A value type
/// rather than a class so that mutating it counts as mutating the store's own stored
/// property, which is what `@Observable` watches; a nested reference type would need
/// its own observation and would silently fail to notify anything.
struct ColorField {
  // MARK: Lifecycle

  init(text: String) {
    // Assignment during initialization does not fire `didSet`, so the first parse
    // is explicit.
    self.text = text
    reparse()
  }

  // MARK: Internal

  private(set) var parsed: ParsedInput = .empty

  /// The most recent text that parsed. Retained across invalid edits on purpose:
  /// without it everything downstream blanks out between `#3b82f` and `#3b82f6`,
  /// which reads as the app breaking rather than as feedback.
  private(set) var color: ColorValue?

  /// The source of truth while editing, never rewritten from the parsed value.
  /// Canonicalizing mid-edit would move the cursor out from under someone halfway
  /// through typing `oklch(`.
  var text: String {
    didSet {
      guard text != oldValue else { return }
      reparse()
    }
  }

  // MARK: Private

  private mutating func reparse() {
    parsed = ParsedInput(text)
    switch parsed {
    case let .parsed(result): color = result.color
    case .empty: color = nil
    case .failed: break // keep showing the last good color
    }
  }
}

/// Which panel the main window is showing.
///
/// The input field sits above this and belongs to no tool in particular — it is the
/// app's spine, and every tool is a different question asked about the same color.
enum Tool: String, CaseIterable, Identifiable, Sendable {
  case convert
  /// Between the other two deliberately: choosing a color comes before asking what
  /// it converts to or whether it is readable.
  case pick
  /// After picking, because it takes a color as its input rather than producing one
  /// from nothing, and before the two accessibility tools, because the colors it
  /// derives are the ones you then go and check.
  case transform
  case contrast
  /// After contrast, because both are accessibility questions about the same color —
  /// "can it be read" and "can it be told apart".
  case cvd
  /// Second to last, because it is the only tool that *keeps* anything. Every other one
  /// answers a question and forgets it the moment the field changes. Before export
  /// rather than after, because saving a set and then writing it out is the order those
  /// two happen in — and because a saved palette is one of the things export reads.
  case projects
  /// Last, because it is terminal: every other tool answers a question about the color,
  /// and this one writes the answer down. It is also the only tool that reads the
  /// *others'* output — the harmony, the ramp, and now a saved palette — rather than
  /// only the input field.
  case export

  // MARK: Internal

  var id: String {
    rawValue
  }

  /// Expanded rows show this text right beside their icon regardless.
  var title: String {
    switch self {
    case .convert: "Convert"
    case .pick: "Pick"
    case .transform: "Transform"
    case .contrast: "Contrast"
    case .cvd: "CVD"
    case .projects: "Projects"
    case .export: "Export"
    }
  }
  
  /// The accessibility label for a collapsed, icon-only sidebar row (M36) — see `ToolSidebar`.
  var tooltip: String {
    switch self {
    case .convert: "Convert"
    case .pick: "Pick"
    case .transform: "Transform"
    case .contrast: "Contrast"
    case .cvd: "Color Vision Deficiency"
    case .projects: "Projects"
    case .export: "Export"
    }
  }

  /// M36's sidebar row icon. Picked for recognizability over cleverness — a collapsed
  /// rail has nothing but this to go on, so an icon that requires the label to explain
  /// it has already failed the collapsed case it exists for.
  var systemImage: String {
    switch self {
    case .convert: "arrow.left.arrow.right"
    case .pick: "eyedropper"
    case .transform: "wand.and.stars"
    case .contrast: "circle.lefthalf.filled"
    case .cvd: "eye.trianglebadge.exclamationmark"
    case .projects: "folder"
    case .export: "square.and.arrow.up"
    }
  }
}

/// A color the user has already worked with, plus the text that produced it.
///
/// The text is stored alongside the value so that clicking a recent returns you to
/// *your* spelling. Re-deriving it from the `ColorValue` would hand back a
/// canonicalized form, quietly rewriting `rebeccapurple` as `#663399`.
struct RecentColor: Identifiable, Hashable, Sendable {
  let color: ColorValue
  let text: String

  var id: String {
    text
  }
}

/// Shared state for the whole app: what is being edited, and what came before.
///
/// One instance, injected into both the window and the menu bar. Two instances would
/// compile perfectly and then silently diverge — recents added from the menu bar
/// would never appear in the window.
@MainActor
@Observable
final class ColorStore {
  // MARK: Lifecycle

  init(initialInput: String = "#3b82f6", initialBackground: String = "#ffffff") {
    foreground = ColorField(text: initialInput)
    background = ColorField(text: initialBackground)
  }

  // MARK: Internal

  /// How every format in the panel is serialized.
  var formatOptions = CSSFormatOptions()

  /// Which panel the main window is showing.
  var tool: Tool = .convert

  /// Which axes the picker is showing.
  ///
  /// Here rather than in the panel because leaving the tool and coming back tears the
  /// panel's own state down. Its *axes* should be rebuilt — the color may have moved
  /// while the tool was away — but the choice of axes is a preference about how you
  /// like to pick, and losing it every time is the kind of small rudeness that adds up.
  var pickerMode: PickerMode = .hsv

  /// Which deficiency the CVD panel is simulating, and how severely. On the store for
  /// the same reason as ``pickerMode``: leaving the tool tears the panel down, and the
  /// deficiency you were inspecting is a preference worth keeping across the trip. The
  /// default is deuteranomaly at full severity — the most common deficiency, shown at
  /// the endpoint where the effect is clearest.
  var cvdDeficiency: ColorVisionDeficiency = .deuteranomaly
  var cvdSeverity: Double = 1

  /// What the transform panel is deriving, and how.
  ///
  /// On the store for the same reason as ``pickerMode`` and ``cvdDeficiency``: these
  /// are preferences about how you like to work, and leaving the tool tears the panel
  /// down. The panel's *pending* adjustment deliberately does **not** live here — see
  /// the note in `TransformPanel`. A half-dialed slider is an unfinished edit, not a
  /// preference, and finding one still applied after a trip through another tool would
  /// mean the panel was showing a color the field does not contain.
  var harmony: Harmony = .triad
  var harmonyOptions = HarmonyOptions.default
  var shadeRamp = ShadeRamp.default

  /// Which space the transform panel's mix interpolates in, and which way round the
  /// wheel it goes where that space has a hue.
  ///
  /// Preferences, on the store for the same reason as the three above. The mix
  /// *amount* deliberately is not: a half-dialed slider is an unfinished edit, the same
  /// as the pending adjustment and the contrast push, and it stays in the panel.
  ///
  /// OKLCH by default because it is the space where a mix behaves the way people
  /// expect — mixing toward white keeps the hue and the chroma instead of washing out.
  var mixSpace: ColorSpace = .oklch
  var mixHueMethod: HueInterpolationMethod = .shorter

  /// Which bar the contrast solver aims at. AA body text is the one nearly every
  /// audit actually checks.
  var contrastTarget: ContrastRequirement = .aaNormalText

  /// What the export panel is writing, and in what shape. Preferences, on the store for
  /// the same reason as ``pickerMode`` — and more strongly here, because the family name
  /// is *typed*: losing `brand` on every trip to the contrast tool would mean retyping
  /// it, which is the difference between a preference and a chore.
  ///
  /// Note that these deliberately do **not** include precision or hex casing. Those are
  /// ``formatOptions``, shared with every other panel and with the toolbar menu, so the
  /// export panel's precision control is a second surface onto one setting rather than a
  /// second setting. Two knobs where one silently wins is the failure mode.
  var exportSource: ExportSource = .color
  var exportOptions = ExportOptions.default

  /// The export ``ExportShape`` the user was on before ``webFriendly`` restricted it,
  /// stashed so turning the mode back off (without meanwhile *using* the reassigned
  /// choice) restores it. `nil` when nothing is stashed — either the mode is off, or the
  /// stored shape was already web-friendly when it went on.
  ///
  /// Session-only, deliberately: there is no ``Preferences`` field, so quitting before
  /// the mode is toggled off or the choice is used simply loses the stash. See the M34
  /// follow-up entry in PLAN.md for why launch is treated as an ordinary transition.
  private(set) var restrictedExportShape: ExportShape?

  /// The export ``CSSOutputFormat`` counterpart to ``restrictedExportShape``, stashed and
  /// restored the same way and independently — restricting only one leaves the other `nil`.
  private(set) var restrictedExportFormat: CSSOutputFormat?

  /// Whether the recents row is shown. Off is a legitimate preference for someone who
  /// never uses it, not a way to clear the list — ``recents`` keeps filling either way.
  var showsRecents = true

  /// Whether ``ToolSidebar`` (M36) shows full rows or the icon-only rail. A plain
  /// stored `var`, unlike ``webFriendly`` — collapsing the sidebar has nothing
  /// downstream to reconcile, so there is no `didSet` to write.
  var sidebarCollapsed = false

  /// Which project the Projects panel is showing.
  ///
  /// A `UUID` rather than SwiftData's own `PersistentIdentifier`, and that is the point:
  /// this type holds app state and knows nothing about persistence, exactly as ColorCore
  /// knows nothing about either. ``ProjectLibrary/project(uuid:)`` does the lookup. It is
  /// also the reason ``ExportStoreTests`` still needs no `ModelContainer`.
  ///
  /// On the store rather than in the panel for the reason ``pickerMode`` gives — leaving
  /// a tool tears its panel down, and which project you are working in is a preference
  /// that should survive the trip.
  var selectedProjectID: UUID?

  private(set) var recents: [RecentColor] = []

  // MARK: - Staged palette

  /// A saved palette handed to the export panel, as plain values.
  ///
  /// The whole reason the Projects tool can feed Export without SwiftData reaching this
  /// far: ``Palette/paletteEntries`` converts at the boundary and what arrives here is
  /// the same `[PaletteEntry]` a harmony or a ramp produces. Downstream, nothing can tell
  /// the difference — which is what makes ``ExportSource/saved`` one line rather than a
  /// second code path through the export layer.
  private(set) var stagedPalette: [PaletteEntry] = []

  /// A whole project handed to the export panel, as named groups.
  ///
  /// Parallel to ``stagedPalette``, and separate from it rather than folded in: a
  /// project export is more than one named set at once, which is what M20's grouped
  /// renderer exists for. `ProjectsPanel`'s Export Project button builds these from
  /// `project.orderedPalettes` and `project.orderedColors` — see ``stage(project:named:)``.
  private(set) var stagedProject: [PaletteGroup] = []

  // MARK: - Screen sampling

  /// True for a moment after a sample lands, so the menu bar can acknowledge a
  /// capture the user made while looking at some other app entirely.
  private(set) var justCaptured = false

  // MARK: - Global shortcut

  /// Whether the system accepted the sampling hot key. Shown in the menu bar panel,
  /// because a shortcut advertised but not registered is worse than none offered.
  private(set) var globalShortcutIsActive = false

  /// Hides exotic formats and keeps every value inside sRGB. See M22 in PLAN.md.
  ///
  /// A `didSet` (matching ``recentLimit``'s shape, not ``globalShortcut``'s
  /// computed-property-with-rollback one, since nothing here can fail and need reverting)
  /// so that toggling the mode reassigns any now-restricted export choice to a safe one
  /// *and stashes the original*, rather than leaving the stored value inert behind a
  /// picker that no longer offers it. See ``reconcileExportOptions()``.
  var webFriendly = false {
    didSet {
      guard webFriendly != oldValue else { return }
      reconcileExportOptions()
    }
  }

  /// The system-wide sampling chord (M27), read directly the same way ``recentLimit``
  /// and ``pickerMode`` are — ``preferences``'s own field mirrors this rather than
  /// being a second source of truth.
  ///
  /// A computed property over a private backing field, not a stored `var` with a
  /// `didSet`: the setter here re-registers immediately when the shortcut is already
  /// active, which is the right behavior for the two paths that assign through it — a
  /// hand-edited preferences file reaching `PreferenceStore.load()`, and the Settings
  /// "Reset to Defaults" button's `store.preferences = Preferences()` — and neither of
  /// those needs to tell a caller whether the system accepted the new chord, the same
  /// graceful-degradation ``activateGlobalShortcut()`` already practices. A user
  /// recording a chord in Settings deserves better than that silence, which is what
  /// ``updateGlobalShortcut(_:)`` is for: it validates first, rolls back on failure,
  /// and writes ``storedGlobalShortcut`` directly rather than through this setter, so a
  /// successful recording doesn't also pay for a second, redundant unregister/register
  /// round trip.
  var globalShortcut: GlobalShortcut {
    get { storedGlobalShortcut }
    set {
      guard globalShortcutIsActive, newValue != storedGlobalShortcut else {
        storedGlobalShortcut = newValue
        return
      }
      GlobalHotKeyCenter.shared.unregisterAll()
      storedGlobalShortcut = newValue
      globalShortcutIsActive = registerGlobalShortcut(newValue)
    }
  }

  /// How many colors ``recents`` keeps. Settable — was `private static let recentLimit
  /// = 12` — because M19 makes it a preference like the rest of this group rather than
  /// a constant. "Enough to be useful, few enough to stay scannable" no longer fixes the
  /// number at 12, only supplies the default.
  ///
  /// A `didSet` (M23) so lowering this in Settings trims an already-full list right
  /// away, rather than waiting for the next ``remember()`` to notice — the Stepper's
  /// label would otherwise keep reading a count the list hasn't caught up to yet.
  /// Skipped during `init` the same way ``ColorField/text`` skips its first `reparse`
  /// — ``recents`` is always empty then, so there is nothing to trim.
  var recentLimit = 12 {
    didSet { trimRecents() }
  }

  /// ``harmonyOptions``, with ``HarmonyOptions/gamut`` forced to `.srgb` under
  /// ``webFriendly``.
  ///
  /// Read by both ``TransformPanel``'s preview and ``entries(for:)``'s export path, so
  /// a harmony's swatches and its exported values can never disagree about whether
  /// they left the gamut — the same reason ``ExportOptions/mappedCountFormat`` exists,
  /// one seam rather than two copies of the same decision.
  var effectiveHarmonyOptions: HarmonyOptions {
    var options = harmonyOptions
    if webFriendly {
      options.gamut = .srgb
    }
    return options
  }

  /// The subset of the properties above (and ``formatOptions``, ``pickerMode``,
  /// ``cvdDeficiency``) that persists across a launch. See ``Preferences`` for which
  /// fields are missing and why.
  ///
  /// A computed property rather than a stored one so there is exactly one copy of each
  /// value — a mirrored `Preferences` field would need its own synchronization and could
  /// drift from the property it duplicates. Reading it registers `@Observable` access to
  /// every field the getter touches, which is what lets a view depend on "the persisted
  /// preferences changed" without listing eight properties itself.
  var preferences: Preferences {
    get {
      Preferences(
        formatOptions: formatOptions,
        webFriendly: webFriendly,
        showsRecents: showsRecents,
        recentLimit: recentLimit,
        sidebarCollapsed: sidebarCollapsed,
        pickerMode: pickerMode,
        cvdDeficiency: cvdDeficiency,
        exportShape: exportOptions.shape,
        exportTemplate: exportOptions.template,
        exportFormat: exportOptions.format,
        globalShortcut: globalShortcut,
      )
    }
    set {
      formatOptions = newValue.formatOptions
      webFriendly = newValue.webFriendly
      showsRecents = newValue.showsRecents
      // Clamped, not trusted as-is: `newValue` can come from `PreferenceStore.load()`,
      // and `Preferences`' decode succeeds for any `Int` — a corrupt or hand-edited
      // preferences file with `"recentLimit": -5` would otherwise reach `remember()`'s
      // `recents.removeLast(recents.count - recentLimit)` and crash the first time it
      // ran, since the count subtracted would exceed the array's size. The Settings
      // panel's own Stepper already restricts to `1...50`; this is the boundary where
      // a value that did *not* come from that Stepper becomes trusted.
      recentLimit = max(1, newValue.recentLimit)
      sidebarCollapsed = newValue.sidebarCollapsed
      pickerMode = newValue.pickerMode
      cvdDeficiency = newValue.cvdDeficiency
      exportOptions.shape = newValue.exportShape
      exportOptions.template = newValue.exportTemplate
      exportOptions.format = newValue.exportFormat
      // Same boundary as `recentLimit`'s clamp above, for the same reason: a value
      // that did *not* come through the Settings recorder — `newValue` can come
      // straight from `PreferenceStore.load()` — is not trusted as-is. `isEligible`
      // rejects a chord with no modifier that could still type a character.
      globalShortcut = newValue.globalShortcut.isEligible ? newValue.globalShortcut : .sampleColor
      // `webFriendly = newValue.webFriendly` above fires the `didSet` *before*
      // `exportOptions.shape`/`.format` receive their final values a few lines up, so
      // that reconcile ran against `init` defaults and found nothing restricted. Redo it
      // now that the real, possibly-restricted values are in place — and clear any stash
      // first, because a "Reset to Defaults" (`store.preferences = Preferences()`) takes
      // the `false` branch, which would otherwise write a stale stash back over the
      // freshly-assigned defaults. Safe to call unconditionally because it is diff-driven.
      restrictedExportShape = nil
      restrictedExportFormat = nil
      reconcileExportOptions()
    }
  }

  // MARK: - Editing

  /// What the user typed. Forwarded to ``ColorField`` so the two fields cannot drift
  /// apart in behavior — the background gets live parsing, retained-last-good, and
  /// no mid-edit canonicalization for free rather than by a second implementation.
  var inputText: String {
    get { foreground.text }
    set { foreground.text = newValue }
  }

  var parsed: ParsedInput {
    foreground.parsed
  }

  var color: ColorValue? {
    foreground.color
  }

  var backgroundText: String {
    get { background.text }
    set { background.text = newValue }
  }

  var backgroundParsed: ParsedInput {
    background.parsed
  }

  var backgroundColor: ColorValue? {
    background.color
  }

  // MARK: - Output

  /// Every format for the current color, or nothing if the field has no valid color.
  var formats: [FormattedColor] {
    color?.allFormats(options: formatOptions) ?? []
  }

  /// The colors ``exportSource`` currently names, each under the key it will be written
  /// out as.
  ///
  /// Here rather than in the panel so that "the ramp exports eleven entries keyed 50 to
  /// 950" is a claim a unit test can make. A panel-side version would be reachable only
  /// through XCUITest, which would mean asserting it against a rendered string.
  ///
  /// A lone color gets an **empty key** on purpose — see ``PaletteEntry`` — so it is
  /// written `--brand` rather than `--brand-1`, a suffix nothing would reference.
  var exportEntries: [PaletteEntry] {
    entries(for: exportSource)
  }

  /// The export document as it currently stands.
  ///
  /// Generated in ColorCore and merely *displayed* here, which is what lets the panel be
  /// a preview and a copy button with no string-building of its own — and what lets the
  /// tests assert the output without ever touching the real pasteboard.
  ///
  /// A project routes through the grouped renderer rather than through ``exportEntries``:
  /// that property flattens ``stagedProject`` into one list for callers that only need
  /// colors (the badge, the swatch strip), and flattening loses the per-palette family
  /// names the grouped document is the whole point of keeping.
  ///
  /// Reads ``ExportOptions/effective(webFriendly:)`` rather than ``exportOptions``
  /// directly (M22). Since the M34 follow-up, ``reconcileExportOptions()`` keeps the
  /// stored shape/format valid under ``webFriendly``, so in normal operation this
  /// substitution is a no-op — but it stays as the last line of defense, the one place
  /// that cannot emit a wide-gamut document even if a restricted value reaches
  /// ``exportOptions`` some other way (a raw write in a test, a future code path that
  /// skips the `select`/reconcile seam). Removing it is caught by
  /// ``WebFriendlyExportStoreTests/exportDocumentClampsARawRestrictedShape()``.
  var exportDocument: String {
    let options = exportOptions.effective(webFriendly: webFriendly)
    if exportSource == .project {
      return options.render(stagedProject, formatting: formatOptions)
    } else {
      return options.render(exportEntries, formatting: formatOptions)
    }
  }

  /// How many entries the chosen format cannot express without moving them.
  ///
  /// Uses ``ColorValue/isGamutMapped(as:options:epsilon:)`` — the same predicate behind
  /// the conversion panel's "mapped" badge and behind the serializer's own decision — so
  /// the warning above the preview cannot disagree with the document below it.
  ///
  /// Measured against ``ExportOptions/mappedCountFormat`` rather than
  /// ``ExportOptions/format``, which is the same value for every shape that writes one
  /// spelling and the *fallback* for the one that writes two. See that property for why
  /// the fallback is the honest half to count.
  var exportGamutMappedCount: Int {
    let options = exportOptions.effective(webFriendly: webFriendly)
    // `nil` (M34, `ExportShape.designTokens`) means this shape has no such badge at
    // all — a token file never gamut-maps — not "count zero for some other reason."
    guard let mappedFormat = options.mappedCountFormat else { return 0 }
    return exportEntries.count {
      $0.color.isGamutMapped(
        as: mappedFormat,
        options: formatOptions,
        epsilon: ColorValue.gamutNoiseTolerance,
      )
    }
  }

  /// The colors any source names, whether or not it is the one being exported.
  ///
  /// Split out from ``exportEntries`` when the Projects panel arrived: saving "the
  /// current harmony" as a palette needs the harmony's entries while the export source
  /// is something else entirely. One function, so a saved ramp and an exported ramp
  /// cannot be keyed differently.
  func entries(for source: ExportSource) -> [PaletteEntry] {
    // Independent of the input field, because a staged palette (or a staged project) is
    // a set that was saved earlier — it does not stop existing because the field was
    // cleared. `.project` flattens ``stagedProject`` for callers that only want colors
    // — the badge count, the swatch strip — never for the document itself, which needs
    // the per-group names and reaches ``stagedProject`` directly through
    // ``exportDocument``.
    if source == .saved {
      return stagedPalette
    }
    if source == .project {
      return stagedProject.flatMap(\.entries)
    }
    guard let color else { return [] }
    switch source {
    case .color:
      return [PaletteEntry(color: color)]
    case .harmony:
      let options = effectiveHarmonyOptions
      let members = color.harmony(harmony, options: options)
      let keys = PaletteNaming.harmonyKeys(harmony, options: options)
      return zip(keys, members).map { PaletteEntry(key: $0, color: $1) }
    case .ramp:
      let stops = shadeRamp.generated(from: color)
      let keys = PaletteNaming.rampKeys(count: stops.count)
      return zip(keys, stops).map { PaletteEntry(key: $0, color: $1) }
    case .recents:
      // Positional keys, because a recent's own text is the thing that makes it
      // recognizable and `--brand-rebeccapurple` is not a name anyone wants in a
      // stylesheet. Newest first, matching the order they are shown in.
      return recents.enumerated().map {
        PaletteEntry(key: String($0.offset + 1), color: $0.element.color)
      }
    case .saved:
      return stagedPalette
    case .project:
      return stagedProject.flatMap(\.entries)
    }
  }

  /// Hands a saved palette to the export panel and switches to it.
  ///
  /// The name travels with the colors and becomes ``ExportOptions/name``, so a palette
  /// saved as `brand` exports as `--brand-500` rather than under whatever family name
  /// the panel was last set to. That is the payoff M8 deferred: the set you saved months
  /// ago comes back spelled the way you saved it.
  func stage(_ palette: [PaletteEntry], named name: String) {
    stagedPalette = palette
    exportSource = .saved
    exportOptions.name = name
    tool = .export
  }

  /// Hands a whole project's palettes and loose colors to the export panel and switches
  /// to it, as ``PaletteGroup``s rather than a single flat list.
  ///
  /// Parallel to ``stage(_:named:)`` above — same four changes at once — but for M20's
  /// grouped renderer: a project export writes one property set per palette (plus one
  /// per loose color) rather than flattening everything under one family name. The
  /// `name` here becomes the project's own name, which is what ``ExportOptions/name``
  /// still governs even in the grouped case — the suggested filename, not any property
  /// inside the document, since every group there is named for itself.
  func stage(project groups: [PaletteGroup], named name: String) {
    stagedProject = groups
    exportSource = .project
    exportOptions.name = name
    tool = .export
  }

  /// Copies the export document and files the color, since reaching for a value is the
  /// clearest signal you intend to use it — the same rule ``copy(_:)`` follows.
  func copyExport() {
    guard !exportDocument.isEmpty else { return }
    Clipboard.copy(exportDocument)
    remember()
    // Producing a real export "confirms" whatever is on screen as the intended
    // configuration, so any pending revert to a restricted choice is discarded. After
    // the empty-document guard: a no-op copy of nothing is not using the configuration.
    confirmExportChoices()
  }

  // MARK: - Web-friendly export reconciliation (M34 follow-up)

  /// Keeps ``exportOptions``'s shape and format valid under ``webFriendly`` by reassigning
  /// any restricted choice to a safe one and stashing the original, and restoring the
  /// stash on the way back out.
  ///
  /// Called from ``webFriendly``'s `didSet` on every real transition, and once more at the
  /// end of the ``preferences`` setter (see there for why). It is **diff-driven** — it
  /// reuses ``ExportOptions/effective(webFriendly:)`` and reassigns only a field whose
  /// current value actually differs from the safe one — so calling it twice in a row is a
  /// no-op the second time and it never overwrites a stash it already set.
  ///
  /// This is what lets ``ExportPanel``'s pickers bind to the *raw* stored value again: the
  /// stored shape/format is now always a value the web-friendly picker still offers. That
  /// invariant is held here, not by the type — the only writers of `exportOptions.shape`/
  /// `.format` are this method, the ``preferences`` setter (which calls this afterward),
  /// and the pickers' setters (which route through ``selectExportShape(_:)`` /
  /// ``selectExportFormat(_:)``). A new writer that skips those can reintroduce the blank
  /// picker; it must reconcile after, or route through a `select` method.
  func reconcileExportOptions() {
    if webFriendly {
      let safe = exportOptions.effective(webFriendly: true)
      if exportOptions.shape != safe.shape {
        restrictedExportShape = exportOptions.shape
        exportOptions.shape = safe.shape
      }
      if exportOptions.format != safe.format {
        restrictedExportFormat = exportOptions.format
        exportOptions.format = safe.format
      }
    } else {
      if let shape = restrictedExportShape {
        exportOptions.shape = shape
        restrictedExportShape = nil
      }
      if let format = restrictedExportFormat {
        exportOptions.format = format
        restrictedExportFormat = nil
      }
    }
  }

  /// Sets the export shape from an explicit user pick and clears *only* the shape's own
  /// stash — an explicit pick "confirms" that field's current value as intended (even
  /// re-picking the value already shown), discarding the ability to revert it. It says
  /// nothing about whether the Format control was consciously chosen, so that stash is
  /// left alone. The picker's `Binding` setter routes here.
  func selectExportShape(_ shape: ExportShape) {
    exportOptions.shape = shape
    restrictedExportShape = nil
  }

  /// The ``selectExportShape(_:)`` counterpart for the Format picker.
  func selectExportFormat(_ format: CSSOutputFormat) {
    exportOptions.format = format
    restrictedExportFormat = nil
  }

  /// Clears both stashes at once, "confirming" the whole configuration on screen.
  ///
  /// Called from ``copyExport()`` and ``ExportPanel``'s save-success branch: producing a
  /// real export is evidence about the entire configuration at once, not one control in
  /// isolation. (``ExportShape/usesFormat`` and ``ExportShape/isWebFriendly`` are the same
  /// predicate today, so whenever Shape's narrowed list is in play, Format is relevant too
  /// — but that is why confirming both together is *correct* now, not why it was designed
  /// this way; the two predicates could diverge later.)
  func confirmExportChoices() {
    restrictedExportShape = nil
    restrictedExportFormat = nil
  }

  /// Exchanges foreground and background, text and all.
  ///
  /// Worth a button because APCA is asymmetric: dark-on-light and light-on-dark are
  /// different results, and swapping is how you see both without retyping either.
  func swapForegroundAndBackground() {
    let outgoing = foreground.text
    foreground.text = background.text
    background.text = outgoing
  }

  /// Replaces the input with a color chosen elsewhere — a recent, the eyedropper,
  /// or the picker.
  func use(_ recent: RecentColor) {
    inputText = recent.text
  }

  /// Adopts a color that has no authored text of its own — an eyedropper sample, a
  /// picker result — writing it in `format` where `format` can carry it.
  ///
  /// The subtlety is that this store keeps *text* as its source of truth, so the
  /// string written here is immediately parsed back into a new `ColorValue`. Any
  /// rounding or gamut mapping in the spelling is therefore permanent: naively
  /// writing a Display P3 sample as hex would map it into sRGB on the way in, and
  /// the color the rest of the app sees would be one the screen never showed. Hence
  /// ``ColorValue/spelling(preferring:)`` to choose the format and
  /// ``CSSFormatOptions/lossless`` to choose the digits — neither of which is the
  /// user's display precision, which governs only what panels show.
  func adopt(_ newColor: ColorValue, preferring format: CSSOutputFormat = .hex) {
    inputText = Self.spelled(newColor, preferring: format, webFriendly: webFriendly)
  }

  /// The same derivation ``adopt(_:preferring:)`` makes, aimed at the background field
  /// instead of the input — a `SwatchButton`'s "Use as background" menu item needs a
  /// value-only color spelled the same lossless way an eyedropper sample is.
  func adoptBackground(_ newColor: ColorValue, preferring format: CSSOutputFormat = .hex) {
    backgroundText = Self.spelled(newColor, preferring: format, webFriendly: webFriendly)
  }

  /// Rewrites the input in `format`, keeping the color the field already holds — the
  /// notation menu under the header swatch's summary line (M25).
  ///
  /// Deliberately does **not** go through ``adopt(_:preferring:)``. That helper picks
  /// a format itself when the one it prefers can't hold the value losslessly, silently
  /// substituting `color(display-p3 …)` for whatever was asked — the right behavior for
  /// an eyedropper sample, which arrives with no notation opinion of its own, and the
  /// wrong one here, where the format *is* the opinion: a click on "hex" means hex, gamut
  /// mapping and all, not a quiet swap to a format the click never named. So this writes
  /// exactly what ``ColorValue/formatted(as:options:)`` returns for the chosen format, or
  /// nothing if the color can't be named in it — only `.keyword` ever answers that way.
  /// Written at ``CSSFormatOptions/lossless``, never at display precision, for the same
  /// reason `adopt` is: this string becomes the field's new source of truth and is
  /// immediately re-parsed, so rounding it to four decimals would be permanent.
  ///
  /// Under ``webFriendly`` the color is pulled into sRGB first, the same recalibration
  /// `adopt` performs — a perceptual function like `oklch()` is unbounded and
  /// `.lossless` does not gamut-map on its own, so without this a wide-gamut color typed
  /// in before the mode was switched on could still leave the field spelled outside sRGB.
  func respell(as format: CSSOutputFormat) {
    guard let color else { return }
    let target = webFriendly ? color.pulledInto(.srgb) : color
    guard let formatted = target.formatted(as: format, options: .lossless) else { return }
    inputText = formatted.css
  }

  // MARK: - Recents

  /// Files the current color under recents.
  ///
  /// Called at deliberate moments — submitting the field, copying a value, sampling
  /// the screen — rather than on every keystroke. Live-parsing means every prefix of
  /// what you type parses too, so an eager version would fill the list with the
  /// accidental colors between `#f` and `#f0a`.
  func remember() {
    guard let color else { return }
    let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }

    // Exact-value dedupe, so `red` and `#f00` collapse but `rgb(255 0 0)` and
    // `hsl(0 100% 50%)` stay separate — they are the same pixel but different
    // authored colors, and which space a color lives in is the thing this app
    // refuses to throw away.
    recents.removeAll { $0.color == color }
    recents.insert(RecentColor(color: color, text: text), at: 0)
    trimRecents()
  }

  func clearRecents() {
    recents.removeAll()
  }

  /// Copies one serialization and files the color under recents, since reaching for
  /// a value is the clearest signal that you intend to use it.
  func copy(_ formatted: FormattedColor) {
    Clipboard.copy(formatted.css)
    remember()
  }

  /// Shows the loupe and adopts whatever pixel the user clicks.
  ///
  /// - Parameter alsoCopy: Put the result on the clipboard too. True for the global
  ///   hot key, whose entire point is capturing a color while another app is
  ///   frontmost — filling a text field nobody can see would accomplish nothing.
  ///   False for the in-app button, where the field is right there and clobbering
  ///   the clipboard would be presumptuous.
  /// - Returns: Whether a color was captured; `false` if the user cancelled.
  @discardableResult
  func sampleFromScreen(alsoCopy: Bool = false) async -> Bool {
    guard let sampled = await ScreenSampler.sample() else { return false }

    adopt(sampled)
    remember()

    if alsoCopy, let color {
      // The user's precision, not `.lossless`: this string is going somewhere
      // else to be read by a person, so it should look like the values the rest
      // of the app shows. Only the stored text has to survive a round trip.
      Clipboard.copy(
        color.cssStringOrHex(
          as: color.spelling(preferring: .hex),
          options: formatOptions,
        ),
      )
    }

    acknowledgeCapture()
    return true
  }

  /// Claims the system-wide sampling shortcut, once.
  ///
  /// Idempotent because it is called from both scenes: neither is guaranteed to
  /// exist — the window can be closed, and the menu bar item can be hidden — so
  /// whichever appears first registers and the other no-ops. Deliberately *not*
  /// called from `init`, so tests can build a store without claiming a chord
  /// system-wide.
  func activateGlobalShortcut() {
    guard !globalShortcutIsActive else { return }
    globalShortcutIsActive = registerGlobalShortcut(globalShortcut)
  }

  /// Rebinds the sampling chord to `shortcut`, tried before it is committed.
  ///
  /// This is what the Settings recorder calls, and it is deliberately stricter than
  /// assigning through ``globalShortcut``: a user recording a chord is watching, so
  /// silently ending up with none registered — the fallback every other failure path
  /// in this file accepts — would read as the app breaking rather than as a rejected
  /// shortcut. Returns `false` and changes nothing else when `shortcut` fails
  /// ``GlobalShortcut/isEligible`` or the system refuses to register it; in the second
  /// case the chord that was already working is re-claimed before returning, so a
  /// rejected recording never leaves the app with no shortcut at all.
  ///
  /// - Note: The rejection branch — the system refusing `shortcut` — has no test that
  ///   forces it. `GlobalHotKeyCenter`'s own doc notes macOS does not reliably report a
  ///   collision with another application, and the one collision this process *can*
  ///   force (registering the same chord twice without unregistering) is exactly what
  ///   this method's own `unregisterAll()` call clears before the retry — so there is
  ///   no way to make `RegisterEventHotKey` fail deterministically in-process. Reasoned
  ///   about rather than pinned, the same honesty this file already extends to
  ///   `NSOpenPanel`/`NSSavePanel`.
  @discardableResult
  func updateGlobalShortcut(_ shortcut: GlobalShortcut) -> Bool {
    guard shortcut.isEligible else { return false }
    guard shortcut != storedGlobalShortcut else { return true }
    guard globalShortcutIsActive else {
      storedGlobalShortcut = shortcut
      return true
    }

    let previous = storedGlobalShortcut
    GlobalHotKeyCenter.shared.unregisterAll()
    if registerGlobalShortcut(shortcut) {
      storedGlobalShortcut = shortcut
      return true
    }
    globalShortcutIsActive = registerGlobalShortcut(previous)
    return false
  }

  // MARK: Private

  /// The system-wide sampling chord's backing storage. See ``globalShortcut`` for why
  /// this is a computed property over a private field rather than a plain stored `var`.
  private var storedGlobalShortcut: GlobalShortcut = .sampleColor

  /// The color everything is about: the one being converted, sampled, and copied.
  private var foreground: ColorField

  /// The color contrast is measured against. Separate from `foreground` because
  /// contrast is the first question this app asks that needs two colors at once.
  private var background: ColorField

  private var captureResetTask: Task<Void, Never>?

  /// The lossless string ``adopt(_:preferring:)`` and ``adoptBackground(_:preferring:)``
  /// write, shared so the two cannot spell the same color two different ways.
  ///
  /// Under ``webFriendly`` (M22) this does more than decline the `color(display-p3 …)`
  /// promotion. Declining alone is not enough: `oklch()` is unbounded and `.lossless`
  /// does not gamut-map, so a color merely spelled in its *preferred* format — the
  /// `.oklch` path `TransformPanel` and the OKLCH picker mode both adopt through —
  /// would still carry values past sRGB's edge even with the promotion turned off. So
  /// the color itself is pulled inside sRGB **before** it is asked for a spelling; once
  /// it already fits, nothing needs promoting and ``allowingWideGamut`` is there mainly
  /// as the belt to that suspenders. This is the mode's whole promise for adopted
  /// colors, and it is lossy on purpose — see M22 in PLAN.md.
  private static func spelled(
    _ color: ColorValue,
    preferring format: CSSOutputFormat,
    webFriendly: Bool,
  ) -> String {
    let color = webFriendly ? color.pulledInto(.srgb) : color
    return color.cssStringOrHex(
      as: color.spelling(preferring: format, allowingWideGamut: !webFriendly),
      options: .lossless,
    )
  }

  private func registerGlobalShortcut(_ shortcut: GlobalShortcut) -> Bool {
    GlobalHotKeyCenter.shared.register(shortcut) { [weak self] in
      guard let self else { return }
      Task { await self.sampleFromScreen(alsoCopy: true) }
    }
  }

  /// The one place ``recents`` is trimmed to ``recentLimit`` — called after a new
  /// entry is filed and from ``recentLimit``'s `didSet`, so a lowered limit and a
  /// freshly-remembered color can never disagree about how the list is cut down.
  ///
  /// `max(recentLimit, 0)` rather than trusting the property outright: this runs from
  /// a `didSet`, which fires for *any* assignment, including one that reaches
  /// `recentLimit` directly rather than through ``preferences``'s own clamp. Without
  /// it a negative limit would ask `removeLast` for more elements than the array
  /// holds and crash at the point of assignment instead of at the next `remember()`.
  private func trimRecents() {
    let limit = max(recentLimit, 0)
    guard recents.count > limit else { return }
    recents.removeLast(recents.count - limit)
  }

  private func acknowledgeCapture() {
    justCaptured = true
    captureResetTask?.cancel()
    captureResetTask = Task {
      try? await Task.sleep(for: .seconds(1.5))
      guard !Task.isCancelled else { return }
      justCaptured = false
    }
  }
}
