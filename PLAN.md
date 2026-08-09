# ColorKit – Implementation Plan

> **Status (2026-08-05): M0–M18 and M5b (CVD) complete – the numbered plan is done.**
> The suite is **405 Swift Testing functions across 46 suites in `ColorKitTests`,
> 59 more across 10 suites in `ColorKitCLITests`, plus 30
> XCUITests**, read off a run rather than counted by hand. ColorCore is validated against
> **colorjs.io 0.7.0** (pinned exact) – 6,384 conversions, 1,368 gamut mappings, 108
> contrast pairs and **1,760 mix vectors** – plus independent definitional anchors, and
> **405 CVD vectors** over Machado's Table 1.
> 
> **M15's first commit was written in a Linux container with no Swift toolchain**, so it
> shipped uncompiled with a JavaScript port of the interpolation algorithm as its only
> proof. On a Mac the app target built clean on the first attempt – and the suite still
> found a real bug the JavaScript could not have, because the port reproduced the same
> reading of the spec. `premultiplied(_:leaving:)` keyed its alpha exemption off one
> color's own `missing` mask instead of what was missing on *both* sides, which made an
> even mix depend on the order of its operands and returned 200% red for
> `color-mix(in srgb, rgb(255 0 0 / none), rgb(0 0 255 / 0.25))`. Fixed, with a test that
> fails against the unfixed code. A follow-up mutation survey then killed all eleven
> mutations, two of them only after tests were added for exemptions nothing was holding –
> see M15's milestone note.
> 
> **One XCUITest failed mid-session for a host reason and then passed on retry**, and the
> diagnosis is worth keeping. `ProjectsSmokeTests.testASavedRampExportsUnderItsOwnName`
> reported its Export button as never hittable, with the whole `Application`, `Window` and
> `Toolbar` reading `Disabled` – the button was right there with real coordinates. Three
> things placed it: it had passed earlier in the same session, it failed *identically* at
> unmodified `ed68e20` in a clean worktree, and `ColorInterpolation` is reachable only
> from the parser's mix branch and `TransformPanel`, so no M15 code runs in that test at
> all. XCUITest cannot click into a macOS app it cannot bring frontmost, and the Mac was
> in use. It passes on an idle Mac, and the whole suite was **392 of 392 in one run at
> M15's HEAD** – read off a single `** TEST SUCCEEDED **`, after the formatting commit
> rather than before it, since the formatter moved a declaration in `TransformPanel.swift`
> and `TransformSmokeTests` is what covers that file. (That figure is M15's and is left
> as recorded; the current total is in the status line above. A count written as "at HEAD"
> stops being true the moment a milestone lands, so treat every number in these historical
> paragraphs as a reading taken then.)
> 
> M0–M9 were each reviewed on the running app. **Three later things were not, and should
> not be read as if they were:** M10 changed no behavior and has no UI to look at, M11's
> *drag* gesture is untestable by XCUITest and unconfirmed by hand – its Move Left/Right
> commands, which share the same handler, are covered end to end – and M12 is core-only,
> reachable from no panel. M13 and M14 are core-only in code but a user reaches both by
> typing, so each is driven against the running app by an XCUITest rather than eyeballed.
> 
> **M16 was checked against the reference from the panel's own screenshot**, and the
> check is discriminating rather than merely agreeing. Exporting `color(display-p3 0 1 0)`
> writes `--brand: #00fb29;` in the fallback and `--brand: color(display-p3 0 1 0);`
> unmoved in the `@media` block. colorjs.io's CSS gamut mapping gives `#00fb29` exactly –
> and a *naive clip* of the same color gives `#00ff00`, so the agreement proves the
> fallback goes through §13's mapper rather than clamping, which a matching value alone
> would not have shown. The screenshot also confirms the Format picker is gone while Name
> and Precision remain, and the badge reads `1 mapped` beside the shape's own sentence.
> 
> **M16 shipped with a decision the milestone note had not anticipated.** The plan
> specified the shape and the `usesFormat` flag correctly, and both went in as written.
> What it did not see is that the *badge* has to be decided with its own sentence: neither
> candidate reading is true as worded. Counting against the P3 block reports `0 mapped` for
> a color outside sRGB while the hex line directly beneath the badge has been rounded;
> counting against hex is right, but the existing copy – "the values below were brought
> into gamut" – is false of the media block, which carries those same colors exactly. So
> `mappedCountFormat` names the fallback, keeping one predicate, and the warning became per
> shape. Four mutations, all four killed.
> 
> **M10–M18 take up what the deferred list had been holding**: three CSS syntaxes the
> parser used to reject, the missing-component semantics all three rest on, a
> `@media (color-gamut)` export shape, design-token import, and a CLI over `ColorCore`.
> **All three now parse** – `calc()` (M13), `rgb(from …)` (M14) and `color-mix()` (M15).
> M10 (relocating `ColorCore`) and M11 (the three items M9 deferred)
> are done, plus the two housekeeping commits recorded after M11 – the exported `UTType`
> declaration M11's drag was missing, and Xcode's recommended build settings. **M12, the
> spine, is done**: `ComponentRole` and carry-forward exist, so every "depends on M12" is
> discharged – M14 was the first milestone to consume it, which is what turned that claim
> into a tested one, and M15 is the one it was written for. **M13 and M14 closed the
> plan's last dependency chain**, and M15 waited on nothing. **M16, M17 and M18 are all
> done, so the numbered plan is finished.** **M8b is done too**, so the deferred list no
> longer holds anything from the original plan – saving an export to a file cost one build
> setting, a `FileDocument` and a button, and its mutation run caught a tautological test
> that had been passing the exact bug it was written for. **M19–M26 are the next series**,
> planned together and fully detailed under *Planned: M19–M26* in Milestones below: a
> settings scene with the app's first persistence, whole-project export, interactive
> swatches everywhere, a web-friendly mode, a recents row, a popover picker, a re-spell
> menu, and import from the shapes the app already exports.
> 
> **M17's own plan note was wrong about one thing, and reading the spec is what caught it.**
> It said to reuse `ComponentGrammar.fullScale` as the token format's range table. The Color
> module leaves `lab`'s and `oklab`'s a/b and both chromas **unbounded**, where `fullScale`
> reports 125, 0.4 and 0.4 – it is a precision hint, not a bound, and validating against it
> would have rejected legal tokens. The salvageable half is sharper than the original: the
> mapping needs no arithmetic *at all*, because the format's ranges are CSS's own number
> forms and this app stores number forms. The one trap is `rgb()`, whose number form runs
> 0–255 while the format's `srgb` runs 0–1 – so a `[1, 0, 0]` scaled by it imports a
> near-black that still renders and still round-trips. Ten mutations, all ten killed.
> 
> **M12 is the first milestone with no oracle *and* nothing to look at**, so its standard
> of proof is the spec's own worked examples plus five mutations. Two of its findings are
> worth carrying: analogous *sets* are a second mechanism that an implementation doing only
> individual matching loses entirely and still passes every same-family test, and a
> spec-printed value should be asserted as a rounding rather than with a tolerance.
> 
> M9 closes the loop M8 left open, and its screenshots prove it end to end: a shade ramp
> saved into a project as `brand` and exported from the other tool comes back as a
> `:root` block reading `--brand-500: oklch(0.6231 0.188 259.81)` – the same value, to
> the last digit, that M8 recorded against colorjs.io. Nothing was lost crossing the
> store. Its screenshots also caught a banner announcing a failure that had not happened;
> see the milestone.
> 
> M8's exports were checked against the reference from the panel's own screenshots:
> exporting `#3b82f6` as a shade ramp writes `--brand-500: oklch(0.6231 0.188 259.81)`,
> and colorjs.io agrees to six decimals. Its **tool switcher moved out of the toolbar**
> in the process – a sixth segment made macOS sweep the whole switcher into an overflow
> menu, taking every tool with it. See the milestone below.
> 
> M7's harmonies were checked against the reference from the panel's own screenshots:
> adopting the triad member of `#3b82f6` writes
> `oklch(0.6230830326 0.1880147345 19.81452853)`, and colorjs.io agrees to ten decimals
> – lightness and chroma preserved exactly, hue rotated 120° and wrapped past 360. Its
> hex, `#e24956`, matches the panel's own readout. The transforms themselves have **no
> oracle** (colorjs.io has no notion of a harmony, a ramp or a solver), so they are
> tested definitionally, the way the gamut boundary is.
> 
> M5b's matrices were confirmed against three independent copies of Machado's Table 1
> (see the finding below), and the panel was reviewed on the running app: pure red
> simulates to olive under protanomaly and green to yellow under deuteranomaly – the
> signature of a correct linear-RGB pipeline, which a gamma-space application would miss
> by ~0.26.
> 
> M6's boundary readouts were checked against the reference from the panel's own
> screenshots: at `L 0.7 h 140` the panel says sRGB allows `0.2253` and the oracle
> agrees exactly; at `L 0.6231 h 259.8` it says `0.2037` against the oracle's `0.2038`
> – one search step, and deliberately on the inside, since the search returns a chroma
> that *is* in gamut rather than one merely near it.
> 
> The contrast panel was checked against the reference from its own screenshots:
> `#ffffff` on `#3b82f6` renders 3.68:1 / Lc −69.4, and swapped, 3.68:1 / Lc +63.9 –
> all four exact. That pair is also the clearest demonstration of why both algorithms
> are shown at once. WCAG returns the *same* ratio and the *same* five pass/fail
> verdicts for both directions; APCA separates them by 5.5 points, because white on
> blue genuinely reads better than blue on white.
> 
> **M4's three untestable links are confirmed by hand**, each verified separately
> because they fail independently: the menu bar shows ⌃⌥⌘C beside "Pick Color from
> Screen" (so the OS accepted the registration and a scene's `.task` fired), the chord
> raises the loupe from another app (so the key is captured and the C callback reaches
> the main actor), and the picked color lands in both the field and the clipboard (so
> the sandbox permits the sampler and the bridge works end to end). No permission
> prompt appeared at any point – `NSColorSampler` and Carbon hot keys are both
> confirmed sandbox-safe on macOS 26.5.
> 
> Three things came out of looking at the running app: precision is now relative to
> each component's scale, long values wrap instead of truncating mid-number, and the
> note on orphaned instances under **Running the app** below.
> 
> M2 note: colorjs.io is the oracle for *conversions* but **not** for *parsing* – its
> parser accepts `rgb(a b c)` as `rgb(none none none)` and tolerates commas in
> modern-only functions. The parser targets the CSS grammar itself; the parse fixture
> is a hand-curated valid-CSS-only list, and rejection cases are asserted in Swift.
> 
> Findings worth carrying forward:
> 
> - Matrices and the named-color table are **generated**, not transcribed
>   (`node Tools/generate-constants.mjs`). A recalled Bradford D50→D65 matrix diverged
>   from the real one at the 7th decimal – generation eliminated that class of bug.
> - `gamut_mapping` defaults to `"css"` in both 0.6.0 and 0.7.0, but the fixture
>   generator passes it explicitly anyway, so a version bump can't silently change it.
> - The 0.6.0 → 0.7.0 upgrade produced **byte-identical** generated Swift and
>   **zero** differences across all 7,752 fixture values; `toGamutCSS` is unchanged.
>   0.7.0 exports each space's matrices as `M`, so the generator now imports them
>   instead of scraping source – it requires >= 0.7 as a result.
> - The app target builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so every
>   ColorCore file needs an explicit `nonisolated` or it gets stranded on the main
>   thread. Plain data in the UI layer needs it too, or non-`@MainActor` tests can't
>   read it.
> - Rec.2020 does **not** contain Display P3 – gamut checks must be per-color, never a
>   ranking of space "widths". Confirmed again in M3: `oklch(0.9 0.3 140)` is outside
>   sRGB, P3, Rec.2020 *and* A98, but inside ProPhoto; P3 green is outside A98 yet
>   inside Rec.2020. Verify every containment claim against the reference.
> - The gamut badge and the serialized string come from **one** predicate
>   (`ColorValue.isGamutMapped(as:options:epsilon:)`), differing only in tolerance.
>   Computing them separately would let the badge lie about the value beside it.
> - Hex is 8-bit quantized, so round-trip tests need a per-format tolerance: exact for
>   decimal formats, ~0.005 ΔEOK for hex, one JND for anything gamut-mapped.
> - **Precision is relative to each component's scale, not a flat decimal count.**
>   Four decimals is right for an OKLCH lightness of `0.6231` and absurd for a hue of
>   `217.2193`. `CSSFormatOptions.decimals(forFullScale:)` drops one decimal per power
>   of ten above unit scale, so every component carries about the same number of
>   meaningful digits.
> - SwiftUI merges a `Button`'s children into one accessibility element, so conversion
>   rows are reachable in XCUITest as **buttons** labeled `"hsl(), hsl(217.22 …)"` –
>   there is no `StaticText` for the value.
> - Each commit must build and test **standalone**, verified in a `git worktree` – a
>   green run at HEAD does not prove the intermediate commits are bisectable.
> - **`NSColor.usingColorSpace(.sRGB)` clips, silently.** Handed Display P3 red it
>   returns `1, 0, 0` – identical to plain sRGB red, no error, no signal. That one call
>   is why most Mac eyedroppers lie about vivid colors. Sampled colors are read into
>   **linear extended sRGB** instead (sRGB primaries, no transfer function, components
>   free to leave 0–1), which lands directly on `ColorSpace.srgbLinear`.
> - **ColorSync is not the CSS spec, and falls short in two different ways.** Measured
>   against colorjs.io 0.7.0: same-primaries (sRGB → linear sRGB) agrees to ΔEOK
>   **3.3e-8**, cross-primaries (P3 → sRGB) only to **3.4e-5** – a thousandfold gap.
>   The small one is just ColorSync's **float32** pipeline (components differ by 1.1e-7
>   at a value of 0.92, exactly one `Float` ulp); the large one is the display's ICC
>   primaries genuinely differing from CSS Color 4's idealized matrices. Both sit far
>   under a 0.02 JND, but a sampled color is only ever as exact as the system's color
>   management – assert a tolerance, never equality.
> - **Storage precision and display precision are different settings.** `ColorStore`
>   keeps *text* as its source of truth, so an adopted color is serialized and
>   immediately re-parsed; anything the spelling rounds or gamut-maps is gone for good.
>   `adopt` therefore uses `CSSFormatOptions.lossless` and
>   `ColorValue.spelling(preferring:)` – never the user's chosen precision, which
>   governs only what panels show. Writing a P3 sample as hex would have re-introduced
>   the clipping bug one layer below the bridge that just prevented it.
> - Carbon `RegisterEventHotKey` / `InstallEventHandler` still compile, link, and
>   return `noErr` on macOS 26.5 under `-swift-version 6`. The C callback reaches
>   `@MainActor` via `MainActor.assumeIsolated` and needs no `userData` round trip,
>   because a `shared` singleton is the same indirection without the unsafety.
> - **colorjs.io is an oracle for APCA but only a cross-check for WCAG.** It does not
>   implement WCAG's definition: luminance comes from XYZ-D65 Y, which uses the
>   full-precision matrix row where WCAG's text specifies rounded coefficients, and it
>   linearizes at 0.04045 where WCAG says 0.03928. Measured divergence is up to
>   **1.97e-4 relative** over 20,000 random 8-bit pairs. WCAG correctness therefore
>   rests on published anchors (21:1, 1:1) that hold under either definition, plus one
>   discriminating pair that asserts the WCAG answer *and* asserts a mismatch with
>   colorjs's – so silently adopting the reference's definition fails rather than passes.
> - Two near-identical linearizations that must **never** be merged:
>   `TransferFunctions` uses **0.04045** (sRGB, and what every conversion is validated
>   against), `wcagRelativeLuminance` uses **0.03928**. They look like the same function
>   with a typo. Note the famous discrepancy is *unobservable* on hex colors – no
>   `k/255` lands between the thresholds – while the coefficient rounding nobody talks
>   about affects every color including hex.
> - Contrast maths gamut-maps before measuring. Not cosmetic: an out-of-sRGB color has
>   negative components and `pow` of a negative is NaN, which propagates silently and
>   surfaces as "nan:1". colorjs.io leaves this case explicitly unspecified.
> - **A forgiving XCUITest selector is a test that cannot fail.** The first contrast UI
>   test tried three queries and clicked whichever existed; it passed via an
>   index-based fallback while the named query never matched. Replacing the chain with
>   one named query plus a tree dump on failure exposed a real defect: a segmented
>   `Picker` renders a `Label` icon-only and hands VoiceOver the **SF Symbol name**, so
>   the switcher announced "arrow.left.arrow.right" instead of "Convert".
> - **The sRGB gamut is not star-shaped about the neutral axis in OKLCH, and blue is
>   the counterexample.** Walking chroma outward at blue's own lightness and hue, sRGB
>   red goes negative at `0.2656`, bottoms out at **−0.009** near `0.29` – three orders
>   of magnitude past float noise, so this is the shape of the gamut and not rounding –
>   and returns to zero only as the ray grazes the blue vertex at `0.3132`. The in-gamut
>   set is genuinely two pieces. Bisection reports the first exit and misses the far
>   sliver, which is what to want: the band between is outside sRGB, and drawing the
>   second island would present a stripe of unreachable colors as reachable. 3,420
>   lightness/hue pairs found no other disconnected ray.
> - **"Where does the gamut end" and "where does gamut mapping land" are different
>   questions.** §13 takes a clipped result whenever clipping costs under a JND, and at
>   a cube corner it costs nothing – so it maps blue's coordinates to `#0000ff` at full
>   chroma `0.3132` while the boundary sits at `0.2656`. Deriving the picker's curve
>   from the mapper would put the cursor inside the line for colors the badge calls out
>   of gamut. The curve must agree with the **badge**, and does.
> - **A channel tolerance is not a chroma tolerance.** `gamutNoiseTolerance` is 7.5e-5
>   *of a channel*; OKLab's cube root turns that into **0.041 of chroma at `L = 0`**, so
>   handing the badge's constant to the boundary search looks like consistency and is a
>   unit error – the curve bulges to a visible width at pure black, which has no chroma
>   at all. The curve is strict, the badge stays forgiving, and they differ only over
>   colors indistinguishable from black.
> - **A picker cannot read its own writes.** The store keeps text as its source of
>   truth, so every drag tick would serialize and re-parse – and the round trip loses
>   exactly what a picker must not: a gray comes back with no hue, so the strip snaps to
>   red one frame after saturation reaches zero. The axes lead and the store follows,
>   guarded by comparing the returned text against the last text written. A boolean "I
>   am writing" flag is the tempting version and the wrong one: the store reparses
>   synchronously but observation fires later, so the flag is already clear by the time
>   the callback lands.
> - **`.task(id:)` restarting does not stop a `Task.detached` it started.** Detached is
>   exactly what it says: no parent, so no inherited cancellation. Discarding the stale
>   *result* afterwards still looks correct and still burns a full plane of conversions
>   per frame of a drag – a throttle that isn't one. The render task is held and
>   cancelled explicitly, and the loops check `Task.isCancelled` so the cancel has
>   somewhere to land.
> - **A `GeometryReader` square inside a `ScrollView` takes the whole unbounded height
>   proposal.** The window opened 948pt tall, and the resize moved the mode switcher out
>   from under a click already in flight – surfacing as "Not hittable", which reads like
>   an accessibility problem and is a layout one. Size such a thing from *width*, which
>   is bounded and cannot feed back into itself.
> - **`.accessibilityIdentifier` on a SwiftUI `Text` publishes the string as the
>   element's `value`, leaving `label` empty.** XCUITest assertions on `.label` then
>   compare against `""` and report a mismatch with nothing, which points at the panel
>   rather than at the query. Only `app.debugDescription` says so.
> - A test that passes is not necessarily a test that tests anything. Both new `adopt`
>   assertions were confirmed by **mutating `adopt` back to the old implementation and
>   watching them fail** – which caught that the first draft of the precision test used
>   a P3 color that happened to be exactly `#3b82f6`, so hex round-tripped it perfectly
>   and the test proved nothing.
> - **Machado's Table 1 is not 33 numbers to recall – it is 33 numbers to pin.** The
>   matrices are generated (`python3 Tools/generate-cvd-matrices.py`) from a vendored
>   copy of colour-science 0.4.7's `CVD_MATRICES_MACHADO2010`, the same table the
>   reference `daltonlens` library uses. Before generating, all 33 were confirmed to
>   agree **exactly** (0.0 diff) with three independent copies: `daltonlens` 0.1.5, the
>   severity-1.0 rows in `opticquiz-cvd` 1.1.0, and the paper's own Table 1 from a
>   screenshot. The generator vendors the dataset rather than installing the 200 MB
>   colour+scipy stack, and re-asserts the identity-at-0.0 and the three published
>   endpoints as guards so a wrong swap fails loudly – the Bradford failure mode, headed
>   off the same way.
> - **The CVD matrices are linear-RGB → linear-RGB, and applying them to gamma-encoded
>   sRGB is the trap.** Confirmed three ways: `daltonlens` runs them in
>   `_simulate_cvd_linear_rgb` (decode sRGB → matrix → re-encode), and both npm
>   implementations linearize first. The difference is not subtle – on `#cc00ff` seen as
>   a protanope the linear pipeline gives `[0, 0.447, 1]` while a gamma-space application
>   lands ~0.26 away – so a discriminating test asserts the linear answer *and* asserts a
>   mismatch with the gamma-space one, exactly the shape of the WCAG-coefficient test.
> - **PLAN said "LMS matrices"; Table 1 is RGB.** Machado derives the transform through
>   LMS cone fundamentals, but tabulates it as a 3×3 that maps linear RGB to linear RGB.
>   The app never touches an LMS space for CVD – colorjs.io exposes none that is the
>   Hunt-Pointer-Estevez basis anyway, which is what made this look hard. Resolving the
>   source resolved the difficulty with it.
> - **Rows of every Table 1 matrix sum to ~1 (to 1e-6), so grays are invariant.** A
>   neutral confuses no cones, and the matrices encode that – a useful free invariant
>   the tests pin, and a quick check that the right numbers loaded.
> - **Contrast is not monotonic in lightness – it is a V – so a solver must not bisect
>   it.** Walking OKLCH lightness upward against a mid-tone background, the ratio *falls*
>   to 1:1 as the color passes through the background's own luminance and rises again
>   beyond it. Every target therefore has **two** crossings, and a bisection on the ratio
>   converges on whichever branch its initial bracket happened to straddle – silently
>   returning the further answer half the time. Measured over 215,000 samples: every one
>   of the 216 multi-crossing cases had a mid-tone background, and none had white or
>   black. Relative *luminance* is monotonic in lightness (the only backwards steps were
>   5e-5 of gamut-mapper jitter), so the solver inverts the target ratio into the two
>   luminances that produce it and bisects each. The inversion is algebraically exact, so
>   keeping the bracket's passing end returns a color that provably satisfies `meets`.
> - **The contrast ceiling has a floor, and it is exactly `√21 ≈ 4.5826`.** Against any
>   background the best available ratio is the better of black and white – `(l+0.05)/0.05`
>   rising, `1.05/(l+0.05)` falling – and they cross where `(l+0.05)² = 0.0525`, at
>   luminance `0.1791`. So **AA body text (4.5:1) is reachable against every background
>   that exists**, by a margin of 0.08, and only AAA's 7:1 can be genuinely impossible.
>   Against a mid-gray `#808080` nothing beats 5.32:1. The worst-case background sits at
>   channel `0.4604`, between the 8-bit grays 117 and 118 – so a sweep over hex colors
>   cannot land on it, and the test constructs it instead. A corollary the UI uses: the
>   band where AA is solvable in *both* directions is the sliver of luminance `0.175`
>   to `0.1833` either side of that crossover.
> - **Harmonies must not be gamut-mapped; ramps must be.** They look like the same
>   decision and are opposite ones. Rotating a vivid hue routinely leaves sRGB – the
>   gamut is nothing like a cylinder, so a chroma that fits at one hue may not fit at
>   another – and pulling the result in hands back a "complement" that is not the
>   complement, so harmonies stay exact and the badge does its job. A ramp is the other
>   case: it is a set built to be *used together*, and a constant-chroma one leaves the
>   gamut at both ends (asserted, so the premise cannot rot), gets clipped on the way to
>   the screen, and clipping shifts hue.
> - **Clamping a ramp stop only when it needs it is not an optimization.** Clamping
>   unconditionally moves the chosen color off itself by up to one search step – so it
>   would no longer come out of its own ramp bit-for-bit – and in an unbounded gamut,
>   where `maxChroma` correctly answers `.infinity`, it would set every chroma to
>   infinity. Both failure modes were confirmed by mutation.
> - **A SwiftData to-many relationship is unordered, and observably so.** Not a caveat
>   from the documentation – a measurement. Read an eleven-stop ramp back off
>   `palette.entries` instead of sorting it and the stops arrive `600, 400, 100, 200,
>   900, 300, 800, 950, 500, 50, 700`, in the same context, immediately after the save
>   that inserted them in order. Order that carries meaning gets an explicit `sortIndex`
>   and a sort on read; otherwise Tailwind's eleven keys name eleven wrong colors and the
>   exported block still looks perfectly well-formed.
> - **SwiftData resolves relationship inverses when the *container* is built, not when
>   the code compiles.** `SavedColor` is the destination of two to-many relationships (a
>   project's loose colors and a palette's entries), and with the inverses left to
>   inference every model still type-checks and the app throws on launch. Hence
>   `@Relationship(inverse:)` on both sides and "the container initializes" as the first
>   assertion in `ProjectStoreTests`.
> - **`@Model` needs no `nonisolated` gymnastics under
>   `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.** The macro's generated `PersistentModel`
>   conformance compiles unannotated, which was the one thing worth spiking before
>   designing a schema around it – every other layer in this project needed the
>   annotation.
> - **One flag cannot describe two opposite situations.** The projects store is ephemeral
>   both when the on-disk one fails to open and when a UI test asks for a throwaway, and
>   an `isEphemeral` boolean made the app announce "the store could not be opened" during
>   a run that had requested exactly that store. Three cases, and the banner fires for the
>   failure alone: a warning shown when nothing is wrong is a warning nobody reads.
> - **A component's letter is not its meaning, and CSS Color 4 §13.2's table says so
>   twice.** `b` is Blue in an RGB space and Opponent b in Lab – unrelated quantities
>   sharing a letter – while `r` and `x` are the *same* category, because the spec counts
>   XYZ as a super-saturated RGB space. Deriving analogy from `componentLabels` gets both
>   backwards, which is why the role table is transcribed like a matrix rather than
>   computed. Confirmed by mutation: collapsing Opponent b into Blues carries a missing
>   `lab()` b into sRGB's blue channel, and one test catches it.

## Context

The goal is a native macOS app that serves as a personal, one-stop color toolkit for daily web development: parse and convert every CSS Color 4 format, check accessibility, transform colors, generate harmonies and ramps, export as CSS, and save collections into projects. Scope is expected to grow over time, so this plan optimizes for a **trustworthy core with a stable API** that features can be layered onto indefinitely, rather than a one-shot build.

The single thing that determines whether this tool is worth relying on is **conversion accuracy**. Most color tools are approximately correct – they use blog-post matrices, ignore the D50/D65 distinction between `lab()` and `oklab()`, and clip out-of-gamut colors instead of gamut-mapping them. The plan therefore front-loads a pure, dependency-free color core validated against reference test vectors before any UI is written.

### Current state

M0–M12 are built. The stock SwiftData template (`Item.swift`, the `NavigationSplitView` list) is gone – M9 brought SwiftData back on its own terms rather than the template's, and M11 versioned that schema. `ColorCore/` now sits at the repo root as its own synchronized group rather than inside the app's, which is what makes a second target possible. What stands now is:

| Layer         | Files                                                                                                                                                                                                                                                                                                                                                                        |
| ------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Core model    | [ColorValue.swift](ColorCore/ColorValue.swift), [ColorSpace.swift](ColorCore/ColorSpace.swift)                                                                                                                                                                                                                                                                               |
| Spaces        | [Matrices.swift](ColorCore/Spaces/Matrices.swift) and [NamedColors.swift](ColorCore/Spaces/NamedColors.swift) (**generated**), [TransferFunctions.swift](ColorCore/Spaces/TransferFunctions.swift), [ColorMatrix.swift](ColorCore/Spaces/ColorMatrix.swift)                                                                                                                  |
| Convert       | [Conversion.swift](ColorCore/Convert/Conversion.swift), [GamutMapping.swift](ColorCore/Convert/GamutMapping.swift), [GamutBoundary.swift](ColorCore/Convert/GamutBoundary.swift), [HSV.swift](ColorCore/Convert/HSV.swift), [MissingComponents.swift](ColorCore/Convert/MissingComponents.swift)                                                                             |
| Parse         | [CSSTokenizer.swift](ColorCore/Parse/CSSTokenizer.swift), [ColorSyntax.swift](ColorCore/Parse/ColorSyntax.swift), [CSSColorParser.swift](ColorCore/Parse/CSSColorParser.swift)                                                                                                                                                                                               |
| Format        | [CSSFormatter.swift](ColorCore/Format/CSSFormatter.swift), [FormatCatalog.swift](ColorCore/Format/FormatCatalog.swift)                                                                                                                                                                                                                                                       |
| Shell         | [ColorStore.swift](ColorKit/Features/Shell/ColorStore.swift), [MenuBarPanel.swift](ColorKit/Features/Shell/MenuBarPanel.swift), [ContentView.swift](ColorKit/ContentView.swift)                                                                                                                                                                         |
| Analysis      | [WCAGContrast.swift](ColorCore/Analysis/WCAGContrast.swift), [APCAContrast.swift](ColorCore/Analysis/APCAContrast.swift), [CVDSimulation.swift](ColorCore/Analysis/CVDSimulation.swift), [CVDMatrices.swift](ColorCore/Analysis/CVDMatrices.swift) (**generated**)                                                                                                           |
| Transform     | [Adjustment.swift](ColorCore/Transform/Adjustment.swift), [LightnessCurve.swift](ColorCore/Transform/LightnessCurve.swift), [Harmony.swift](ColorCore/Transform/Harmony.swift), [ShadeRamp.swift](ColorCore/Transform/ShadeRamp.swift), [ContrastSolver.swift](ColorCore/Transform/ContrastSolver.swift)                                                                     |
| Export        | [ExportTemplate.swift](ColorCore/Export/ExportTemplate.swift), [ColorExport.swift](ColorCore/Export/ColorExport.swift)                                                                                                                                                                                                                                                       |
| Conversion UI | [ColorInputField.swift](ColorKit/Features/Conversion/ColorInputField.swift), [ConversionPanel.swift](ColorKit/Features/Conversion/ConversionPanel.swift), [FormatPresentation.swift](ColorKit/Features/Conversion/FormatPresentation.swift)                                                                                                             |
| Contrast UI   | [ContrastPanel.swift](ColorKit/Features/Contrast/ContrastPanel.swift)                                                                                                                                                                                                                                                                                                 |
| Picker UI     | [PickerState.swift](ColorKit/Features/Picker/PickerState.swift), [PickerPlane.swift](ColorKit/Features/Picker/PickerPlane.swift), [PickerPanel.swift](ColorKit/Features/Picker/PickerPanel.swift), [PickerPlaneView.swift](ColorKit/Features/Picker/PickerPlaneView.swift), [PickerHueStripView.swift](ColorKit/Features/Picker/PickerHueStripView.swift), [PickerAlphaSliderView.swift](ColorKit/Features/Picker/PickerAlphaSliderView.swift), [CompactPicker.swift](ColorKit/Features/Picker/CompactPicker.swift)                                                                                                                                                       |
| CVD UI        | [CVDPanel.swift](ColorKit/Features/CVD/CVDPanel.swift)                                                                                                                                                                                                                                                                                                                |
| Transform UI  | [TransformPanel.swift](ColorKit/Features/Transform/TransformPanel.swift)                                                                                                                                                                                                                                                                                              |
| Export UI     | [ExportPanel.swift](ColorKit/Features/Export/ExportPanel.swift), [ExportPresentation.swift](ColorKit/Features/Export/ExportPresentation.swift)                                                                                                                                                                                                                 |
| Persistence   | [ColorRecord.swift](ColorKit/Persistence/ColorRecord.swift), [ProjectModels.swift](ColorKit/Persistence/ProjectModels.swift), [ProjectLibrary.swift](ColorKit/Persistence/ProjectLibrary.swift), [PersistenceStack.swift](ColorKit/Persistence/PersistenceStack.swift), [SchemaVersions.swift](ColorKit/Persistence/SchemaVersions.swift) |
| Projects UI   | [ProjectsPanel.swift](ColorKit/Features/Projects/ProjectsPanel.swift)                                                                                                                                                                                                                                                                                                 |
| Design system | [ColorSwatch.swift](ColorKit/DesignSystem/ColorSwatch.swift), [ColorValue+SwiftUI.swift](ColorKit/DesignSystem/ColorValue+SwiftUI.swift)                                                                                                                                                                                                                       |
| Services      | [Clipboard.swift](ColorKit/Services/Clipboard.swift), [ScreenSampler.swift](ColorKit/Services/ScreenSampler.swift), [GlobalHotKey.swift](ColorKit/Services/GlobalHotKey.swift)                                                                                                                                                                          |

`Persistence/` exists as of M9 and holds five files, listed above – M11 added
`SchemaVersions.swift`. An earlier revision of this file claimed one existed and was empty
long before that was true; git does not track empty directories, so it never survived a
clone and the claim held only on the machine that made it.

Key facts about the project, established during exploration and still current:

| Fact                            | Value                                                     | Why it matters                                                                                                                                                                                                             |
| ------------------------------- | --------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `objectVersion`                 | `77`, with **two** `PBXFileSystemSynchronizedRootGroup`s  | **New `.swift` files are picked up automatically.** No `project.pbxproj` edits needed – write into `ColorCore/` or `ColorKit/`, subfolders included. Editing the project file is for adding a *target*, nothing else. |
| `SDKROOT` / target              | `macosx`, deploy `26.5`                                   | macOS-only. Every modern API is available; no availability guards needed.                                                                                                                                                  |
| `ENABLE_APP_SANDBOX`            | `YES` (no `.entitlements` file yet; Xcode auto-generates) | Constrains the eyedropper and global-hotkey design.                                                                                                                                                                        |
| `SWIFT_VERSION`                 | `6.0` (raised in M0)                                      | Strict concurrency throughout.                                                                                                                                                                                             |
| `SWIFT_DEFAULT_ACTOR_ISOLATION` | `MainActor`                                               | Everything is main-actor unless marked `nonisolated`. See the ColorCore note above.                                                                                                                                        |
| `NSColorSampler`                | Present in SDK, `sample()` async                          | Confirmed available. Runs **out-of-process**, so the eyedropper needs **no Screen Recording permission**.                                                                                                                  |

### Decisions confirmed with the user

1. **Contrast tools** – build *both*, as separate controls: a paired-color solver (with auto-fix to a target ratio) and a standalone S-curve around mid-gray.
2. **App shape** – `MenuBarExtra` + main window, with a global hotkey for instant screen-sampling.
3. **Persistence** – SwiftData library (keeps the bootstrapped stack) plus JSON / CSS / Tailwind export.
4. **Accessibility** – WCAG 2.2 **and** APCA **and** color-vision-deficiency simulation.

---

## Architecture

Four layers, strictly one-directional. **`ColorCore` imports nothing but `Foundation`** – no SwiftUI, no AppKit, no SwiftData. Every one of its 31 files, measured rather than assumed (the figure stood at 27 for three milestones without being recounted, which is what measuring is for). That constraint is what keeps it exhaustively testable and reusable, and M10 turned "reusable in principle" into "addressable by a second target": it now sits beside the app rather than inside it.

```
ColorKit/                    ← repo root
├── ColorCore/                    ← its own synchronized root group (M10)
│   ├── ColorValue.swift          canonical model
│   ├── ColorSpace.swift          space enum + component metadata
│   ├── Spaces/                   matrices, transfer functions, white points
│   ├── Convert/                  conversion hub + gamut mapping
│   ├── Parse/                    CSS tokenizer + parser
│   ├── Format/                   CSS serializer + format catalog
│   ├── Analysis/                 WCAG, APCA, CVD, deltaE
│   ├── Transform/                lightness/sat/hue, harmonies, ramps
│   ├── Export/                   declaration templates + document shapes
│   └── Import/                   W3C design token decoding (M17)
├── ColorKitCLI/              ← the CLI's logic, in the tool *and* its test bundle
├── ColorKitCLIMain/          ← `main.swift` alone, in the tool only (M18)
├── ColorKitCLITests/         ← ColorCore + the CLI + tests, its own module
├── ColorKit/                ← the app target's own group
│   ├── Services/                 eyedropper, global hotkey, clipboard
│   ├── Persistence/              SwiftData @Models + Codable bridge
│   ├── Features/                 one folder per feature area (SwiftUI)
│   └── DesignSystem/             shared swatch/slider components
├── ColorKitTests/
├── ColorKitUITests/
└── Tools/                        Node + Python generators (not in any target)
```

Both `ColorCore/` and `ColorKit/` are `PBXFileSystemSynchronizedRootGroup`s listed by the app target, so a `.swift` file dropped in either compiles with no project edit. The sources still build **into the app module**, which is why everything in `ColorCore` stays `internal` and the tests reach it with `@testable import`. The CLI target lists `ColorCore` too – a synchronized root group can be
listed by any number of targets, which is what M10 bought and what M18 spent.

The boundary runs in one direction only: **ColorCore knows facts, the UI layer owns editorial copy.** `CSSOutputFormat.catalog` lives in core; the section names ("Web", "Perceptual") and the per-format labels live in `Features/`. A core test that reaches into the UI for a display string is the smell that the layering has slipped – and in M3 it also broke a commit's ability to build standalone.

### The core model

Storing everything as RGB is the mistake to avoid – `oklch(70% 0.4 30)` is outside sRGB, and normalizing to RGB on input destroys it permanently. `ColorValue` therefore **retains the color in its authored space**:

```swift
struct ColorValue: Hashable, Sendable, Codable {
    var space: ColorSpace
    var components: SIMD3<Double>
    var alpha: Double
    var missing: ComponentMask   // CSS `none`, set by the parser and honoured by the serializer
}
```

### The conversion hub

Rather than N² conversions, everything pivots through a connection space: **XYZ D65**. Each space implements `toXYZD65` / `fromXYZD65`, so adding a space later is one file and one enum case.

Two refinements matter for correctness:

- **Intra-family conversions stay direct.** `rgb`/`hsl`/`hwb`/named are alternate parameterizations of the *same* sRGB values; `lab`↔`lch` and `oklab`↔`oklch` are rectangular↔polar of the same space. Routing these through XYZ would add float error and destroy hue on achromatic colors. Convert them directly.
- **The D50/D65 split is the #1 accuracy trap.** CSS `lab()`/`lch()` are **D50**-referenced; `oklab()`/`oklch()` are **D65**. Converting sRGB → `lab()` requires sRGB → linear → XYZ D65 → **Bradford adaptation to D50** → Lab. Getting this wrong yields values that look plausible but are visibly off, and it is why many web tools disagree with browsers.

### Sourcing the matrices – do not derive or recall these

Matrices are **generated** by [generate-constants.mjs](Tools/generate-constants.mjs) from a pinned colorjs.io, never transcribed by hand. The original guidance below still explains *why*, and remains the rule for anything the generator does not cover:

| Matrix                             | Source                                                |
| ---------------------------------- | ----------------------------------------------------- |
| linear-sRGB ↔ XYZ D65              | CSS Color 4 §17 sample code / `spaces/srgb-linear.js` |
| Bradford D65 ↔ D50                 | CSS Color 4 §17 / `adapt.js`                          |
| XYZ D65 ↔ LMS, LMS ↔ OKLab         | `spaces/oklab.js`                                     |
| Display P3, A98, ProPhoto, Rec2020 | corresponding `spaces/*.js`                           |

**Do not copy the OKLab matrices from Ottosson's original blog post** – CSS Color 4 and colorjs.io use values computed at higher precision. Mixing sources produces small deltas against the reference tests and sends you chasing phantom bugs.

### Gamut mapping is a first-class core function

`oklch()` and `lab()` colors land outside sRGB constantly, so how they're mapped is user-visible and must not be an afterthought. Implement **CSS Color 4 §13**: binary-search OKLCH chroma downward, comparing each candidate against its clipped version with `deltaEOK`, stopping at JND `0.02`. The UI should always show *both* the mapped value and an "out of sRGB gamut" badge rather than silently clipping.

---

## Milestones

Sequenced so the app becomes genuinely useful at M4, then grows. Each milestone is independently shippable. **✅** marks a milestone that is built and tested; **⬜** marks one that is planned in full below but not yet started.

### ✅ M0 – Project hygiene

- Delete `Item.swift`; strip the template body from [ContentView.swift](ColorKit/ContentView.swift) and the `Item` schema from [ColorKitApp.swift](ColorKit/ColorKitApp.swift).
- Raise `SWIFT_VERSION` to `6.0`. Do this **now**, while the codebase is tiny, and migrating later is far more expensive. Strict concurrency is genuinely free across the value-type core; the one place it costs real work is the Carbon hot-key bridge in M4 – expect it there and nowhere else.
- Create the folder skeleton above.
- Add a `.gitignore` and `git init` (the directory is not yet a repo).

### ✅ M1 – ColorCore: model + conversions ⭐ *the foundation*

- `ColorValue`, `ColorSpace`, per-space metadata (component ranges, units, whether hue is present).
- All spaces: sRGB, linear sRGB, HSL, HWB, Lab/LCH (D50), OKLab/OKLCH (D65), Display P3, A98 RGB, ProPhoto RGB, Rec2020, XYZ D50/D65 – plus the full CSS named-color table (~148 entries incl. `rebeccapurple`) and `transparent`.
- Conversion hub, Bradford adaptation, `deltaEOK`, CSS Color 4 §13 gamut mapping.

**Validation gate – this is what makes the tool trustworthy.** Write a small Node script using `colorjs.io` that emits a JSON fixture of a few thousand conversions across a grid of colors and every space pair. Check the fixture into the repo and drive **parameterized Swift Testing** tests from it. Nothing proceeds to UI until conversions match the reference within tolerance and round-trips are stable.

Two things to get right in the fixture, or you will chase phantom bugs:

- **Pin the colorjs.io version** in the generator script, and check the version into the repo alongside the fixture.
- **Match the gamut-mapping *method*, and use two tolerances.** colorjs.io's `toGamut()` default has changed across versions and is not always the CSS Color 4 §13 algorithm being implemented here. Generate the fixture explicitly using its CSS-algorithm gamut method, and split tolerances: **tight** for ordinary in-gamut conversions, **looser and method-matched** for gamut-mapped ones. A mismatch here produces disagreements that look exactly like bugs but aren't – the same trap as mixing matrix sources.

### ✅ M2 – Parser + serializer

Hand-written recursive-descent tokenizer, no dependencies. Must handle:

- Hex `#rgb` / `#rgba` / `#rrggbb` / `#rrggbbaa`
- Legacy comma syntax (`rgb(255, 0, 0)`, `rgba(...)`, `hsl(120, 50%, 50%)`) **and** modern space syntax with `/` alpha (`rgb(255 0 0 / 50%)`)
- Percentage-vs-number forms per component, per space
- Hue units: bare, `deg`, `rad`, `grad`, `turn`
- `color(display-p3 1 0 0 / 50%)` and all predefined spaces
- Named colors, case-insensitive

Serializer needs configurable precision and legacy-vs-modern output. **Deferred at the time:** `calc()`, and relative color syntax (`rgb(from …)`) – a strong later addition, now planned as M13 and M14. `none` *is* parsed and round-trips (`nonePreserved()` pins it); what M2 left undone is the interpolation semantics in §13.2, which is M12.

Round-trip tests: parse → serialize → parse must be idempotent.

### ✅ M3 – App shell

`MenuBarExtra` + main window. Text input that live-parses any supported format, and a conversion panel rendering the color in **all** formats simultaneously with per-format copy buttons and out-of-gamut badges. Menu bar shows recent colors and a "copy as ▸" submenu.

*Done and visually reviewed at every precision level.*

### ✅ M4 – Eyedropper + global hotkey

- **Eyedropper:** [ScreenSampler](ColorKit/Services/ScreenSampler.swift) wraps `NSColorSampler`. Colors are read in **linear extended sRGB**, never `.sRGB` – see the finding above; the bridge is pure and `nonisolated` so it can be tested without the loupe.
- **Global hotkey:** [GlobalHotKey](ColorKit/Services/GlobalHotKey.swift) – Carbon `RegisterEventHotKey`, ⌃⌥⌘C. Three modifiers deliberately: ⇧⌘C and ⌥⌘C are already claimed (Digital Color Meter, Finder's "Copy as Pathname"), and a global hot key *wins* over the frontmost app's, so a collision silently breaks something the user relies on.
- **The two entry points do different things.** The in-app button fills the field and leaves the clipboard alone. The hot key also **copies**, because its whole point is capturing a color while another app is frontmost – filling an invisible text field would accomplish nothing. The menu bar icon flashes a checkmark, which is the only feedback a global capture can get without a notification permission.
- The shortcut is claimed from whichever scene appears first (`activateGlobalShortcut` is idempotent). Neither scene is guaranteed: the window can be closed, the menu bar item can be hidden.

*Done, and confirmed on the running app.* The app is sandboxed (`com.apple.security.app-sandbox`) with **no** screen-recording entitlement, and the loupe works anyway with no permission prompt – confirming `NSColorSampler` runs out of process rather than capturing the screen itself. Carbon hot keys likewise prompt for nothing.

### ✅ M5 – Accessibility (contrast)

- **WCAG 2.2** – [WCAGContrast.swift](ColorCore/Analysis/WCAGContrast.swift). Spec-literal `0.03928`, AA/AAA × normal/large, plus 1.4.11's 3:1 non-text threshold.
- **APCA** – [APCAContrast.swift](ColorCore/Analysis/APCAContrast.swift). Transcribed from colorjs.io 0.7.0's implementation of **0.0.98G**, matching to 1e-9 across 108 pairs in both polarities.
- **UI** – [ContrastPanel.swift](ColorKit/Features/Contrast/ContrastPanel.swift), reached by the tool switcher (which sat in the toolbar until M8 moved it into the window body – see that milestone). The store now holds a *pair* of colors via `ColorField`, so the background gets the foreground's editing behavior rather than a second implementation of it.

**No APCA pass/fail badges.** Its readability levels (Lc 90/75/60/45/30) could not be verified against a pinned source the way the algorithm was, and a threshold this app cannot stand behind has no business wearing a checkmark next to WCAG's, which it can. The panel shows the signed `Lc` and its polarity, nothing more.

Two things came out of reviewing the screenshots. Nothing in this panel is dimmer than `.secondary` – `.tertiary` explanatory text is dim enough to fail the very check running inches above it, and a contrast tool that ships low-contrast text has undermined its own advice. And APCA's polarity is described comparatively ("lighter text on a darker background") rather than absolutely, because calling `#3b82f6` a dark background out loud reads as a bug even though the sign is right.

### ✅ M5b – Accessibility (CVD simulation)

Machado et al. (2009) severity-parameterized simulation matrices for protan / deutan /
tritan, as a live preview filter over any swatch or palette: the current color shown
original-vs-simulated, all three deficiencies at the chosen severity side by side, the
foreground/background pair as a CVD viewer sees it (the other half of the contrast
question), and the recents strip filtered. Deficiency and severity live on `ColorStore`
so they outlast the panel, exactly like `pickerMode`.

- **[CVDMatrices.swift](ColorCore/Analysis/CVDMatrices.swift)** –
  **generated** (`python3 Tools/generate-cvd-matrices.py`) from a vendored, pinned copy
  of Machado's Table 1; never hand-edited, same rule as `Matrices.swift`. The generator
  is Python because the oracle that carries the table (colour-science, and `daltonlens`
  after it) is Python; it needs only the standard library.
- **[CVDSimulation.swift](ColorCore/Analysis/CVDSimulation.swift)** –
  `ColorValue.simulating(_:severity:)`. Gamut-maps into sRGB, decodes to **linear**
  light, applies the severity-interpolated matrix, clamps, re-encodes. Exact 0.1 steps
  are Table 1 verbatim; between them the two nearest matrices are blended, matching the
  reference libraries.
- **The block was always provenance, and it is now pinned** – see the two findings
  above on the source and the linear-RGB trap. It turned out to be a short milestone
  once the numbers were trustworthy, exactly as predicted.

**What is deliberately absent: no pass/fail verdict.** Like the APCA panel, this shows
rather than judges – there is no threshold for "distinguishable enough", and inventing
one would be the same overreach the contrast panel refuses. Tritanomaly additionally
carries an honest caveat in its blurb, because the paper's authors flag it as an
approximation via the shift paradigm rather than a fit to data.

### ✅ M6 – Full-spectrum picker

Canvas-rendered, with **two modes**: a familiar HSV square + hue strip, and an **OKLCH
mode** (L/C/h) that draws the sRGB gamut boundary so it's visible when chroma is being
clipped. Alpha slider over a checkerboard. The display's own edge is drawn dashed
beside sRGB's – nested, and verified nested: 20,000 random sRGB colors all fall inside
Display P3 while 9,626 of 20,000 P3 colors fall outside sRGB.

- **[GamutBoundary.swift](ColorCore/Convert/GamutBoundary.swift)** –
  `maxChroma(lightness:hue:in:)` and the sampled curve, in ColorCore because it is a
  numeric fact. Bisects the same `inGamut` predicate the badge uses, so the drawn line
  and the badge are one claim. See the blue counterexample and the tolerance note above
  – both are pinned by tests precisely so they are not "fixed".
- **HSV is deliberately not a `ColorSpace` case.** CSS has no `hsv()`, so a case would
  need excluding by hand from the parser, serializer, catalog and every `allCases` loop,
  and the first one missed would offer a format no browser accepts. It is a coordinate
  on the side ([HSV.swift](ColorCore/Convert/HSV.swift)) wrapping the
  sRGB↔HSV conversions that already existed to route HWB.
- **[PickerState.swift](ColorKit/Features/Picker/PickerState.swift)** holds the
  axes as a plain value type, testable without SwiftUI – which is what let the write
  loop, the hue-preservation rule and the format choice all be asserted directly.
- **Each mode writes in a format that can hold what it produced**: `oklch()` at
  `.lossless` for OKLCH, hex for HSV. Mutating the format to hex fails seven
  assertions, including two chroma values `1e-4` apart collapsing to the same
  `#3b82f6`.
- **Switching modes does not write.** Looking at a color in other axes is not editing
  it; rewriting `#3b82f6` as `oklch(…)` for having glanced at the other tab would be
  presumptuous. It does *carry* the field's color across, which is what stops HSV from
  narrowing a wide color merely by having been the tab the panel opened on.

**Recents are filed on a debounce, not on release.** Plane, strip and alpha are three
controls that dialing in one color touches in turn, so remembering on each gesture end
deposits three different way-points – the same noise the store already avoids by not
remembering on every keystroke. A second of stillness is the signal that a color was
chosen rather than passed through.

**The mode outlives the panel** (it lives on `ColorStore`), because re-entering the
tool tears the panel's state down. The axes *should* be rebuilt from the field, which
may have moved; the choice of which axes to use should not be.

**No numeric entry fields.** The shared input field above already accepts any CSS
color, so L/C/h boxes would be a second way to type the same thing. The readout is
read-only and earns its place differently: HSV has no CSS spelling anywhere else in the
app, and the sRGB chroma still available at this lightness and hue is the panel's
actual payload – it turns "this looks vivid" into "this is 0.19 of a possible 0.21".
It is also the only assertable surface a `Canvas` can offer a UI test.

*Done, and reviewed on the running app from its own screenshots.*

### ✅ M7 – Transform + harmony tools

All computed in **OKLCH** for perceptual evenness. One panel rather than five entries in
the tool switcher, four sections, and the pattern the plan predicted: *view → operates on
a `ColorValue` → emits a `ColorValue` or `[ColorValue]`.* Every emitted swatch is a button
that adopts it, so the sections compose – adopt a triad's red and its own triad contains
the original blue.

The export sheet is deferred to M8 as planned; until then the output is adopt-into-the-
field plus the Convert panel's existing copy rows, which is the same destination reached
one click later.

- **[Adjustment.swift](ColorCore/Transform/Adjustment.swift)** –
  `OKLCHComponents` (the coordinate every transform works in, mirroring `HSVComponents`)
  and `OKLCHAdjustment`. **Relative, not absolute**, which is what stops it being the M6
  picker twice: the picker already sets L, C and h outright, and what it cannot do is
  *transform* – a little lighter, a little less saturated, thirty degrees round. Each
  axis gets the operator it deserves, and they are not interchangeable: lightness **adds**
  (it is perceptually uniform on a fixed `0…1` scale), chroma **multiplies** (no upper
  bound, and its useful range depends on both lightness and hue, so `+0.05` would be
  noise on a vivid color and a doubling on a muted one), hue **adds and wraps** (it is an
  angle).
- **Results stay in OKLCH rather than returning to the input's space.** A round trip back
  to `#3b82f6` would quantize onto the 8-bit grid – a nudge finer than 1/255 would return
  the color you started with – and half of these transforms leave sRGB anyway, where a
  bounded format has no honest spelling. The picker learned the same lesson in M6, and
  the panel writes at `.lossless` for the same reason the eyedropper does.
- **[LightnessCurve.swift](ColorCore/Transform/LightnessCurve.swift)** –
  the S-curve: contrast with no second color in it. The pivot is **fixed at `L = 0.5`**
  rather than configurable, and that is what buys the good behavior: exact symmetry,
  fixed points at black/mid-gray/white, and an exact inverse. Opposite strengths cancel
  to 1e-12 because the strength maps *exponentially* onto the exponent (`3^s`), so `+0.5`
  and `−0.5` are reciprocal gammas; a linear mapping would fail to cancel. Its real use
  is on a **set** – it widens a ramp's ends while holding its order and its midpoint,
  which a lightness offset cannot do, because an offset slides a ramp where a curve
  stretches it.
- **[Harmony.swift](ColorCore/Transform/Harmony.swift)** – the six, at
  the classic angles but turned on OKLCH's wheel. That choice is the whole point:
  rotate 180° in HSL and a saturated blue's "complement" comes back a dim mustard,
  because HSL's hue is a raw RGB angle in which equal degrees are wildly unequal steps.
  Monochromatic is the odd one out – one hue, many lightnesses – so it delegates to
  `ShadeRamp` rather than reimplementing a lightness family worse.
- **A gray has no relatives, and the arithmetic says so.** Every hue harmony of
  `#808080` returns the same gray repeated, which is correct – there is no third color
  related to a neutral by 120° – so the panel says it in words rather than showing five
  identical swatches with no explanation.
- **[ShadeRamp.swift](ColorCore/Transform/ShadeRamp.swift)** – the two
  rules do different jobs and both are needed. Tapering chroma toward the ends is the
  *aesthetic* rule (light stops read as tints rather than as the same ink at a higher
  lightness); holding every stop at or inside the `GamutBoundary` edge is the
  *correctness* rule. Because the edge comes from the same predicate the badge uses,
  every stop is in gamut **by construction** rather than by a mapping applied afterwards.
- **[ContrastSolver.swift](ColorCore/Transform/ContrastSolver.swift)** –
  both halves the plan asked for, sharing one set of machinery. The **auto-fix** is "the
  nearest color hitting 4.5:1"; the **manual push** is a slider that moves the color and
  reports the ratio live. Both move **lightness alone**: hue and chroma are what make a
  color that color, and a solver free to move them turns "nearest" into a
  two-dimensional search with no obvious metric. See the two findings above – the V-shape
  that rules out bisecting the ratio, and the `√21` floor that decides when to say
  "impossible" instead of searching.
- **"Push apart" has to decide its own sign**, or it means opposite things in the two
  polarities. `awayFromBackground(for:on:)` reads the direction off the pair – a color
  already lighter than its background gets more legible by getting lighter still – so
  dragging right raises the ratio whether the text is dark on light or light on dark. On
  an exact luminance tie there is no side, and the direction with more headroom wins.
  Those headrooms are wildly asymmetric away from mid-luminance and are their own
  question: against `#1a1a2e`, going lighter reaches 16:1 while going darker manages
  1.3:1, hence a per-direction `ceiling(against:going:)` alongside the overall one.
- **The S-curve is a slider in the Adjust section rather than a fifth tool.** The plan
  framed it as one of "two separate contrast tools", which was right about the *maths* –
  it takes no second color – and wrong about the *furniture*: as its own panel it would
  be one slider on an empty page, and it composes with the other three adjustments, which
  is where its value actually shows. The separation the plan cared about is preserved
  where it matters: it is its own type, with no reference to a background anywhere.

**Testing has no oracle here, and that is an advantage.** colorjs.io converts and maps
but has no notion of a harmony, a ramp or a solver, so – exactly as with
`GamutBoundary` – the tests assert the *properties* the results must have rather than
recorded output: a hue exactly 180° away, a chroma preserved to the last bit, every ramp
stop in gamut, and, for the solver, that the answer passes `meets` **and** that stepping
back toward the original fails. Every load-bearing claim was confirmed by mutation:
removing the ramp's clamp fails three tests, dropping its exact fast path fails two,
gamut-mapping harmonies fails four, and keeping the solver's failing bracket end fails
five.

*Done, and reviewed on the running app from its own screenshots – see the status note
above for the colorjs.io cross-check of an adopted triad member.*

### ✅ M8 – Export

Template-driven, as planned: `color`, `background-color`, `border`, `outline`,
`box-shadow`, `text-shadow`, `fill`/`stroke`, plus custom-property blocks, JSON and
Tailwind – applied to a single color or to a whole palette, with a format picker and a
precision control.

**The plan's one word for two different things was "template".** Splitting them is the
decision the rest of the milestone hangs off. A *template* is per color – how one value
is spelled inside a declaration. A *shape* is per document – what wraps the set. They
look like one control and are not: `background-color:` repeated eleven times is not a
stylesheet, and a `:root` block holding a single `border` shorthand is not a custom
property. So `ExportTemplate` has the eight declarations and `ExportShape` has the five
documents, and exactly one shape consumes a template. The panel hides the control that
does not apply rather than leaving it there doing nothing – `usesTemplate` and `usesName`
are complements, and a test pins that.

*Superseded in one detail by M16, which added a **sixth** shape and a **third** capability
flag.* `usesFormat` is not part of the complement – it answers a different question, and
it is the first of the three that hides a control which would be actively harmful rather
than merely inert. The complement test still holds over all six cases.

Decisions worth recording:

- **"A whole palette" means the sets the app already has**: the harmony, the ramp, and
  recents. There was no `Palette` type at this point, deliberately – it belonged to M9,
  and inventing one here to have something to point at would have been building the next
  milestone early and worse. M9 added it, and adding the saved-palette source afterwards
  cost exactly one enum case, which is the evidence the seam was drawn in the right place.
- **Keys are a correctness problem, not a naming one.** A palette entry's key becomes a
  CSS identifier *and* a JavaScript object key, and the two have different rules:
  Tailwind writes shade keys bare because `50:` is a legal numeric key, but a bare
  `triad-2:` parses as a subtraction and the config fails to load. Keys must also be
  unique, since two entries sharing one silently collapse into a single property and a
  color disappears with nothing to show for it.
- **Tailwind's scale was checked, not recalled.** Eleven keys, `50` through `950`; the
  `950` step is a later addition than the rest, so a list ending at `900` looks right and
  is a version out of date. That `ShadeRamp` defaults to eleven stops is not a
  coincidence – its `lightest` was chosen to sit where Tailwind's `50` does – but it is
  not a guarantee either, so `PaletteNaming.rampKeys(count:)` falls back to indices.
  `Harmony.monochromatic` asks for five, so that path is live, not hypothetical.
- **Both Tailwind versions ship.** v4 configures colors in CSS (`@theme`, with the
  load-bearing `--color-` namespace prefix – `--brand-500` generates no utility at all)
  and v3 in JavaScript. Which you want is decided by your project's major version and by
  nothing else, so picking one and being wrong for half of them is not a simplification.
- **`.keyword` is excluded from the format picker structurally**, not by a fallback. It
  names 148 colors, so a palette of eleven shades would come back with two spelled as
  keywords and nine as something else, and nothing in the file would say a substitution
  happened. That is fine in the conversion panel, where a format that cannot name the
  color simply has no row. Every remaining format is *total*, which is what makes
  `cssStringOrHex`'s fallback unreachable rather than merely unused.
- **JSON is hand-shaped.** `ColorValue` is `Codable`, so `JSONEncoder` is one line away –
  and it would emit a `space` string, a `components` array and a `missing` bitmask. That
  is a serialization of the program, not of the color, and it is the same reasoning that
  made M9 reject an opaque blob. What a consumer wants is the CSS string they would have
  pasted.
- **Precision is one setting shown twice**, not two settings. The toolbar's output menu
  already owns `formatOptions`, and the panel writes through to the same property – so
  raising precision in either place moves the export. Two knobs where one silently wins
  was the alternative.

**The tool switcher moved out of the toolbar**, which was not planned and was not
optional. A sixth segment made macOS sweep the entire switcher into a *"more toolbar
items"* overflow menu – taking every tool with it, not just Export – at a window 745pt
wide, well above the 520pt minimum. `ToolbarItem(placement: .principal)` is *centered*,
so its width budget is not the toolbar's spare room but `width − 2 × max(leading,
trailing)`, and the window title alone spends that twice over. Raising the minimum would
only have deferred it – M9 added the seventh tool, and all seven fit in the body. **Seven
is the tested ceiling, though, not a headroom claim**, which is why M15 and M17 fold their
UI into existing panels rather than each taking a `Tool` case. It also makes the
hierarchy `ContentView` already described in its comment literal rather than implied:
field, then switcher, then panel. Every existing UI test kept passing unchanged, because
they query `radioButtons` by label and never cared where it lived.

**A measured characteristic, not a defect:** a ramp stop sitting exactly on the gamut
boundary can round *outward* at display precision. `--brand-50` for `#3b82f6` prints
`oklch(0.97 0.0142 259.81)`, and the true boundary at that lightness and hue is
`0.014177` – so the printed value is 2.3e-5 of chroma past it and colorjs.io calls the
string out of gamut, while the `ColorValue` it came from is inside. Swept across hues at
four decimals the worst excursion is **1.7e-3 of a channel, 0.43 of an 8-bit step**, so a
browser clamping it lands on the same pixel or one adjacent. It is not worth engineering
around: biasing export rounding inward would make the clipboard disagree with the
preview, which is a worse property than the one it fixes, and `Fine` or `Maximum`
precision removes it entirely.

**Testing has an oracle here for the first time since M5 – this app's own parser.**
`Transform/` had none, because colorjs.io has no notion of a harmony or a ramp. An
exported declaration is different: it is CSS, and CSS is what `CSSColorParser` reads. So
the discriminating test pulls the value back out of the document, parses it, and requires
the color that comes back to be the color that went in, for every exportable format. The
syntax assertions are exact strings, which is the right standard here and the wrong one
in `HarmonyPresentation` – a `:root` block either has its braces or is not one.

Three mutations confirm the tests bite: a shape ignoring its `formatting` argument,
unquoted JavaScript keys, and a ramp claiming Tailwind's scale at every stop count. **The
first initially passed**, and that is the useful part – the plumbing test rendered only a
single entry, while `json` and `tailwindConfig` fork on cardinality, so the broken
multi-entry branch was never reached. It now asserts at both.

**One defect survived into a commit and was caught in review**: the Name field prompted
`brand` while an emptied field exported `--color`. The placeholder was a literal in the
panel and the fallback came from `cssIdentifier`'s own default, so nothing tied them
together and clearing the field produced a property the user had never been shown.
`ExportOptions.defaultName` is now the starting value, the fallback *and* the
placeholder, and `json` reaches it through `identifier` like every other shape rather
than calling `cssIdentifier` itself – which is how CSS and JSON could have disagreed
about the same emptied name. The regression test fails three ways against the old code.
The general lesson is the one this file keeps relearning: a constant duplicated across a
layer boundary is a claim nothing checks.

*Done, and reviewed on the running app from its own screenshots – see the status note
above for the colorjs.io cross-check of an exported ramp stop.*

### ✅ M8b – Saving an export to a file

Built, and smaller than its long deferral suggested. A `Save…` button beside `Copy`, a
`FileDocument` over the string ColorCore already generates, and one build setting.

**`.fileExporter`, not the `NSSavePanel` wrapper this section used to plan for.**
`Services/` wraps AppKit only where SwiftUI has no equivalent – the pasteboard, the
sampler, Carbon hot keys – and a save panel is not one of those. `ExportDocument` is a
`FileDocument` over a `String` and nothing else, so the file, the preview and the
clipboard are one string with three destinations rather than three renderings that can
disagree. It is `nonisolated`, like all plain data here, or the conformance does not
compile under the app's default actor isolation.

**`ENABLE_USER_SELECTED_FILES` went `readonly` → `readwrite`, in both the Debug and
Release blocks.** Same shape as M17's read grant and the same trap: the type is only
consulted at runtime, so a Release-only omission is invisible from a Debug build. Verified
in the built binary – `codesign -d --entitlements -` now reports
`com.apple.security.files.user-selected.read-write`. Still no `.entitlements` file
anywhere; the build setting is the whole mechanism.

Decisions worth recording:

- **`ExportShape.fileExtension` is a fact about the shape, so it lives in ColorCore** beside
  the three capability flags. What `tailwindConfig` writes *is* a JavaScript module
  whatever a panel calls it. Four of the six answer `css`, including `p3WithFallback` – a
  `@media` block is still a stylesheet – so it is transcribed, not derived. The `UTType`
  mapping stays in the UI layer, where AppKit's vocabulary belongs, and is derived from
  that one table so a shape cannot propose `brand.css` and tag the file as JSON.
- **The proposed filename comes from the sanitized `identifier`, not from `name`.** So the
  file is called the same thing the properties inside it are: `My Brand!` writes
  `--My-Brand` and saves as `My-Brand.css`, and an emptied name proposes `brand.css`
  rather than `.css`. One function decides both, which is the same fix the
  `defaultName` constant was for.
- **`readableContentTypes` is empty on purpose.** Reading a stylesheet back is M26's job
  and goes through the pasteboard, not a document type. Declaring it readable would put
  this app in Finder's "Open With" for every `.css` on the disk.
- **A cancelled save is not a failure.** `.failure` means the write was attempted and lost,
  and only that raises the inline label – the M9 lesson about a banner announcing a failure
  that had not happened. A successful save calls `remember()`, since saving a value to disk
  is at least as strong a signal of intent as copying it.

**The mutation run found a tautology, which is the whole reason it is worth doing.** The
first version of "every shape's content type is writable" compared `writableContentTypes`
against `contentType` – but the list is *derived* from `contentType`, so the claim was true
by construction and survived a mutation collapsing all six shapes onto `css`, which is
exactly the bug it existed to catch. Replaced with a distinctness assertion, which is not
derivable that way and also catches `UTType(filenameExtension:)` silently falling back to
`.plainText` for everything. Two mutations, both killed by precise failure sets afterwards;
the second is killed by five tests where it previously escaped two.

**M8b's first real export found a conversion bug that had been shipping since M1.** Parker
saved a greyscale ramp in two formats and handed the files over; the `oklch()` one was
clean and the `hsl()` one read `--Greyscale-50: hsl(336 0% 96.06%)`,
`--Greyscale-100: hsl(350 0% 87.86%)`, `--Greyscale-200: hsl(345 0% 79.79%)` – a hue
wandering between 320 and 350 across eleven colors that have no hue at all.

- **Cause.** `srgbToHSL` and `srgbToHSV` guarded the hue with `delta != 0`, an *exact*
  comparison, where `rectangularToPolar` had used an epsilon since M1 and says why in its
  own comment: "rather than fabricating whatever `atan2` returns for numerical dust". A
  grey arriving in sRGB *through a conversion* has channels equal to ten decimal places and
  differing in the last ULP, so `delta` is ~1e-16 and the hue is a ratio of two pieces of
  noise. `lch()` and `oklch()` were always right; only the RGB-based polar forms were not.
- **Why nothing caught it.** A grey *typed* in sRGB has bit-identical channels, so
  `delta` is exactly `0` and the old guard worked. Every hand-written grey in the suite was
  of that kind, and colorjs.io agrees with us on the *color* – the rendered pixel is
  identical, since a browser ignores hue at zero saturation. It was only ever wrong in the
  text, which is exactly the thing an export feature puts in front of you.
- **Fix.** One `hueFromRGB` shared by HSL and HSV – the two had the same six lines and the
  same missing guard, which is how they drifted from the polar path – with the guard at
  `achromaticChannelEpsilon`, `1/100000` of a channel, derived the same way
  `ColorSpace.polarEpsilon` is. Saturation keeps the exact test on purpose: a near-grey has
  a real if minute saturation, and keeping it is what holds the round trip.
- **Proof.** The regression test converts from `oklch()` rather than typing a grey, and
  asserts the hue is **exactly** `0` rather than within a tolerance – the competing
  hypothesis is not "slightly off" but "any angle", and no tolerance separates 336 from 0
  without admitting every other wrong answer. Against the unfixed guard it fails 14 times
  across seven lightnesses with the fabricated hues named; the two tests asserting that
  faint *real* hues survive keep passing, so the failure set is precise. `#010203` is the
  sharpest surviving case – adjacent 8-bit channels at the darkest end, delta 780× the
  threshold, hue 210° and saturation 50% intact.

**A 32-file sweep afterwards found nothing else.** Parker exported a greyscale ramp and a
purple ramp as custom properties in all sixteen formats – 352 values – and they were
checked three ways: mutual consistency (every format against the `oklch()` spelling of the
same stop), against colorjs.io (feed it the app's `srgb` spelling, ask for every other
space), and re-parsed through the app's own parser. All 352 re-parse. Worst perceptual
disagreement is **6.1e-4 deltaEOK, about 1/33 of a JND**, and the ranking is itself the
proof that what remains is display rounding rather than error: `xyz-d65`, `xyz-d50` and
`srgb-linear` are worst *because four decimals on a value like `0.0055` is two significant
figures*, and `hex` is the only outlier above that at 2.2e-3, which is 8-bit quantization
at the darkest greys. Three things that look wrong in that set and are not:

- **CIE LCH hue is not constant across a constant-OKLCH-hue ramp, and dips at the dark
  end** – `primary` runs 307.68 → 314.73 and then drops to 311.66 at `-950`. colorjs.io
  produces the identical 311.66. It is genuine Lab-versus-OKLab hue-line divergence,
  largest where lightness is lowest and the stop has been clamped.
- **`color(a98-rgb …)` shows a green of `0.0025` where sRGB shows `0`.** a98's transfer
  function is near-vertical at zero, so a linear green of ~2.5e-5 encodes to 0.0025. Ask
  colorjs.io with the *rounded* sRGB string and it answers 0.0000; ask with the truer
  `rgb()` string and it answers 0.0031. Ours sits between them.
- **`rgb(244.95 244.95 244.95)` is not an integer**, and CSS Color 4 permits `<number>`
  channels. Worth knowing it surprises people; it is not wrong.

The sweep also confirmed something that is *not* a bug and *is* a gap: **the wide-gamut
exports do not reach past sRGB.** `ShadeRamp.gamut` defaults to `.srgb` and has no UI
control – it exists in the core and is reachable from the CLI's `--gamut`, and nothing in
the app binds it – so exporting a ramp as `color(display-p3 …)` re-spells sRGB colors
rather than widening them, and four `primary` stops sit exactly on the sRGB boundary where
the clamp fired. See the deferred list.

The general lesson is one this file keeps relearning in new clothes: **two functions
solving the same problem, where only one got the guard.** It is the same shape as the two
sRGB linearizations and the three `savePalette` overloads – and the reason the fix was to
merge the duplicated six lines rather than to patch the guard into both.

**The write itself is a recorded manual check, and no test will ever cover it.**
`.fileExporter` presents `NSSavePanel`, a separate process XCUITest cannot drive – the same
wall `fileImporter` hit in M17, and not one better test code can climb: driving that panel
from outside needs assistive access, which `osascript` does not have here. So
`ExportFileNamingTests` pins everything decided *before* the panel opens (the filename, the
extension, the content type, the document text) and `testTheSaveControlIsThereToBeUsed`
stops at the control being present, enabled and hittable. **An agent cannot verify the
write and should say so rather than infer it from a green suite.**

***The check is done, and it was not one save but thirty-four.*** Every `.css` file in both
batches Parker supplied – the first pair, then the sixteen-format sweep of both ramps – was
produced by the `Save…` action. So the write is confirmed across 34 saves, and the 352
values inside those files re-parse without a single rejection, which is a good deal more
than "a file lands": the bytes are right too. The `readwrite` entitlement therefore works
in the shipping app and not only in `codesign` output.

**The proposed filename is confirmed too.** The `.d50`/`.a98` infixes in the file names are
Parker's, added after the fact to tell the sixteen exports apart – the panel itself opened
proposing `greyscale.css`, which is exactly `cssIdentifier(name) + "." + shape.fileExtension`
for a palette saved as `greyscale`. So `suggestedFilename`, `ExportShape.fileExtension` and
`ExportDocument.contentType` are all confirmed on the running app as well as in
`ExportFileNamingTests`, and **nothing in M8b is left standing on a unit test alone.**

### ✅ M9 – Projects (SwiftData)

Built as planned: three `@Model` classes holding space ID plus raw components rather than
a serialized string or a `Data` blob, so saved values stay lossless *and* queryable, with
a small value-type bridge to and from `ColorValue`. `ColorCore` never learns SwiftData
exists – and neither, it turns out, does `ColorStore`.

```swift
@Model final class Project    { uuid, name, colors, palettes, createdAt, modifiedAt }
@Model final class SavedColor { name, notes, sortIndex, spaceID, c0/c1/c2, alpha, missingMask, text }
@Model final class Palette    { name, kindID, sortIndex, entries }
```

**The sketch above was missing two fields, and both are load-bearing.**

- **`missingMask`.** The parser sets `ComponentMask` for CSS `none`, so without it a saved
  `oklch(0.7 0.2 none)` comes back with a hue of exactly zero – a different color, with
  nothing anywhere to say so.
- **`text`, the authored spelling.** `RecentColor` already carries its text because
  re-deriving one canonicalizes, and the same argument applies twice over to something
  saved deliberately: a stored `rebeccapurple` recalled as `#663399` is the app rewriting
  a choice the user made and then kept. Components remain the *value* and text is only how
  it was written, so they are two spellings of one claim – and a test therefore requires
  that parsing the text reproduces the components, which is the check that stops them
  drifting.

Decisions worth recording:

- **`ColorStore` does not import SwiftData, and that is the load-bearing boundary.**
  `ProjectsPanel` owns the app's only `@Query` and only `modelContext`; a palette leaves
  it as `[PaletteEntry]`, the same value type a harmony produces. So `ExportSource.saved`
  is one enum case rather than a second path through the export layer, `ExportStoreTests`
  still needs no `ModelContainer`, and the selected project is remembered as a plain
  `UUID` – which is why `Project` carries one alongside SwiftData's `PersistentIdentifier`.

- **Staging carries the palette's *name*, not just its colors.** A set saved as `brand`
  exports as `--brand-500` however the export panel was last configured. That is the whole
  payoff M8 deferred, and forgetting the name would have made it half a feature.

- **`SavedColor.name` doubles as the export key.** A ramp stop's key *is* the only sensible
  thing to call it – `500` – so a second field would be two names for one string and an
  invitation for them to disagree.

- **`notes` got a UI rather than a deferral.** The sketch listed the field and the first
  draft stored it with nothing anywhere to write it – a column that exists and does
  nothing, which is the sort of thing this file exists to catch. It is a popover off the
  swatch's context menu, because notes are the least-used thing in the panel and a
  permanent text box under every tile would bury the colors it is describing.

- **Mutations live in `ProjectLibrary`, not in the panel.** A thin wrapper over
  `ModelContext` that owns the *rules* – where a position comes from, what counts as
  touching a project, which relationship a color belongs to – so they can be asserted
  against an in-memory container instead of through a rendered view. It saves explicitly
  rather than leaning on autosave, which is fine for an app and useless for a test that
  wants to fetch back what it just wrote.

- **A store that will not open falls back to memory and says so.** Refusing to launch over
  a corrupt file is the wrong trade for a tool opened dozens of times a day; accepting
  saves that silently evaporate is worse than both. Hence a banner – and hence the
  three-case `Status`, after the first version fired it during a UI test that had *asked*
  for a throwaway store. See the finding above.

- **UI tests launch with `UITestInMemoryStore`.** XCUITest drives the shipping app, so
  without it a test that saves would deposit a project in the real library and the next run
  would find it. The launch argument is the only way to reach that decision from outside
  the process, and it carries no leading hyphen because `NSUserDefaults` claims the
  argument domain for anything that starts with one.
  
  That turned out to be half the story, discovered later: a *bare* argument is claimed
  too, by AppKit, whose `NSTreatUnknownArgumentsAsOpen` defaults to on and reads it as a
  file to open – and an app launched to open a document never creates its default window.
  So the launch is three strings, `["-NSTreatUnknownArgumentsAsOpen", "NO",
  "UITestInMemoryStore"]`. The failure it causes is worth naming because it is unreadable
  from the outside: the app launches, reaches `.runningForeground`, publishes a full menu
  bar, and has no window, so all six tests fail on element queries and look like a broken
  panel. It is not specific to this suite – adding any meaningless argument to
  `ConversionSmokeTests` reproduced it, which is what identified the cause. Nor is it a
  regression: the same six fail at pre-M11 commits, so this is macOS drift and the green
  runs recorded in the M9 and M11 commit messages no longer reproduce on a current host.

- **Schema versioning is deferred, deliberately.** Additive changes migrate on their own
  and this is a personal-scope v1; a `VersionedSchema` would be ceremony around a
  migration that has not happened yet. Worth adding the first time a field is *removed*
  or retyped.

**The seventh tool went in before Export rather than after.** Export is documented as
terminal – every other tool answers a question about the color and this one writes the
answer down – and Projects is the tool that *keeps* things, which happens before you
write them out and is itself one of the things Export now reads. Seven segments still fit
the switcher in the window body, which is the layout M8 moved it there to survive.

**Testing splits along the boundary.** The mapping is a value type, so `ColorRecordTests`
asserts every space's round trip, the `none` mask and the two spellings agreeing, with no
container anywhere. `ProjectStoreTests` takes the things only SwiftData can answer –
inverses, cascades, what comes back from a fetch. `ProjectsSmokeTests` covers what only a
running app can show: clicking a saved swatch returns *your* spelling to the field, and a
ramp saved in one tool exports under its own name in another.

**An in-memory store cannot prove persistence, which is the entire feature.** Every test
above ran on `isStoredInMemoryOnly`, and a container that never touches a disk proves
round tripping *within a context* and nothing whatever about surviving a quit. So one
test leaves memory: it writes to a real SQLite store in a temp **directory** (SQLite puts
`-wal` and `-shm` sidecars beside the file, and cleaning up only the `.store` would leave
state that could make a later run pass for the wrong reason), releases the container,
opens a second one over the same file, and requires both the spelling and the ramp's
order to come back. Separately, launching with no arguments was confirmed to open
`default.store` under
`~/Library/Containers/me.parkersprouse.colorkit/Data/Library/Application Support/` –
so the sandbox permits the default location, `.persistent` is the arm actually taken, and
the fallback banner is not quietly the normal case.

Four mutations confirm the tests bite: dropping the `missing` mask fails two, nullifying
the palette cascade fails two, canonicalizing the stored text fails six, and removing the
sort fails thirteen. **The last one is the interesting one** – it did not merely risk
disorder, it produced it on the first run, which is what turned an assumption about
SwiftData into the measurement recorded above.

*Done, and reviewed on the running app from its own screenshots – see the status note for
the ramp that survived a round trip through the store unchanged.*

### ✅ M10 – `ColorCore` to its own group

Preparation, not a feature, and sequenced first for one reason: `ColorCore` sat *inside*
the app target's synchronized group, so no second target could address it, and relocating
26 files only gets more expensive as the milestones below add to them.

It is now a repo-root sibling with its own `PBXFileSystemSynchronizedRootGroup`, listed by
the app target. The sources still compile **into the app module**, so `internal` access is
untouched and no `public` sweep was needed – the alternative, extracting a real SPM
package, would have meant `public` on every type, member and `init` across 26 files and
`import ColorCore` throughout the app. Unit tests were unaffected because they reach the
core through `@testable import ColorKit`, never by listing its sources.

**The path references outside the project file are the part worth remembering.** Three
pointed at the old location and would have written to a stale path in silence: the two
generators' output directories and `.swiftformat`'s exclusion list. The proof they were
updated is that re-running every generator reproduces all three generated Swift files
byte-for-byte.

**A measured host dependency, found on the way and left alone:** regenerating
`cvd-vectors.json` returns 26 of 405 values differing in the last ULP. The generator is
idempotent on a given machine, so this is not nondeterminism – `**` on Python floats calls
libm `pow`, which IEEE-754 does not require to be correctly rounded, so it varies by
platform and libm version. Differences of 1e-16 are far inside every tolerance the CVD
tests use. Do not "fix" it by committing a regenerated fixture; that just moves the churn
to whoever regenerates next.

### ✅ M11 – Projects: schema versioning, reordering, loose sets

The three items M9 deferred, done together because they are all the projects panel.

**The `VersionedSchema` is insurance and is documented as such.** `ColorKitSchemaV1`
wraps the three existing models with an empty migration plan. Nothing migrates, and
nothing here asserts that it does – a test over an empty stage list would pass against a
plan that does nothing, which is exactly what it is. The value is having a version to
migrate *from* when the first destructive change lands, rather than writing the version
boundary and the data transformation at the same moment, against a shape no longer in the
source tree. `VersionedSchema` conformance needs `nonisolated` on its statics, per the
project's default actor isolation.

**Reordering renumbers, and that is a correctness rule.** `nextIndex(after:)` leaves gaps
on purpose so an append lands last after a deletion – but a gap is only safe while
positions are append-only. Slotting a moved color *into* one means inventing a value
between two neighbours, and two moves into the same gap collide. So `moveColors` renumbers
densely from zero, which is the one place that happens; appends still read the maximum, so
`newColorsLandLast` is untouched. **No new model field, and therefore no migration** – the
drag lives entirely inside `ProjectsPanel`, which owns the `modelContext`, so the rule that
forced `Project.uuid` (keeping `ColorStore` free of SwiftData) is simply not in play.

**Loose sets needed a second `savePalette`, not a conversion into the first.** The
`PaletteEntry` overload re-derives a spelling because its colors – ramp stops, harmony
members – never had one. A hand-picked set's colors were typed by the user, and sending
them through that door returns `rebeccapurple` as `oklch(…)`, contradicting the panel's own
caption. Copying `SavedColor.record` carries text, components and the `missing` mask
across. Keys come from each color's name, **deduplicated** – not tidiness: two entries
sharing a key collapse into one CSS property and a color leaves the export with nothing
marking its absence. Generated palettes never meet this; two colors named "blue" is an
ordinary thing for a person to have.

**Three UI facts cost real time and each looked like a bug somewhere else:**

- **A SwiftUI `Button` is a single accessibility element.** The selection tick, layered
  over the swatch as an overlay, was swallowed whole – absent from the tree entirely – and
  `savedColor-N` began matching *two* elements, breaking an existing recall test that had
  nothing to do with the change. It is a `ZStack` sibling now.
- **XCUITest cannot start an AppKit dragging session.** Its synthesized events move the
  pointer without the drag beginning, so a drag-driven test fails whether the feature works
  or not – including with `press(forDuration:thenDragTo:withVelocity:thenHoldForDuration:)`.
- `.draggable` ended up on the tile rather than on the swatch Button, on the theory that a
  Button consumes the press a drag needs. **That theory is unverified and should not be
  repeated as fact:** the test failed identically before and after the move, because of the
  point above. It is recorded as a placement, not a finding.

That last one forced a question worth more than the test: **a drag-only reorder is
unusable from the keyboard and from VoiceOver**, which would have made this the one thing
in the panel some people could not do at all. Move Left and Move Right now sit in the
tile's context menu and share `move(from:to:)` with the drop handler. The UI tests drive
those, so the shared path is covered end to end through the store and across a panel
switch; the gesture that opens it is not covered by any automated test and wants a human
to try it once.

Nine store tests, each confirmed against a mutation of the rule it covers – dropping the
offset discount, skipping the renumber, disabling dedup, re-deriving text, and moving
colors instead of copying them all fail the suite. The reorder is checked across a real
store close and reopen, since an in-memory container proves only that the objects in hand
were mutated.

### ✅ Housekeeping after M11

Two commits that belong to no milestone, recorded because both changed something outside
the source tree and neither is visible from a Debug build.

**The drag needed an `Info.plist`, and the app did not have one.** `UTType(exportedAs:)`
returns a working identifier whether or not the type is declared, so M11's reorder drag
functioned – both ends compare the same string – while every launch logged that
`me.parkersprouse.colorkit.saved-color-position` "was expected to be declared and
exported in the Info.plist … but it was not found". `GENERATE_INFOPLIST_FILE` covers every
scalar through `INFOPLIST_KEY_*`, and `UTExportedTypeDeclarations` is an array of
dictionaries with no such spelling, so a file is the only way to say it. Setting
`INFOPLIST_FILE` alongside the generator **merges** rather than replaces – measured by
diffing the built plist against a build without it, 24 keys in and the same 24 plus the
declaration out – and it is set in *both* configurations, because the declaration is read
only at runtime and a Release-only omission is invisible from a Debug build. The file sits
at the **repo root**: `ColorKit/` is a synchronized root group, so a plist dropped
there becomes the target's `Info.plist` *and* a bundled resource, which builds, warns, and
ships a duplicate in `Contents/Resources`. Confirmed by building it that way first.
`lsregister -dump` now finds the type; before, it did not.

**This registered the type. It did not test the gesture** – that still wants a human to
try it once, exactly as M11 recorded. The commit also corrected the comment above
`.draggable`, which had restated the Button-consumes-the-press theory as fact after
PLAN.md and CLAUDE.md had already walked it back.

**Xcode's recommended build settings, accepted with one real consequence.**
`DEAD_CODE_STRIPPING` was absent from every container and therefore resolved to `NO`, not
the `YES` the templates imply, so the Release link now runs `-dead_strip`. It is written to
the project and all three targets in both configurations, because the validator checks for
the key's *presence* per container rather than its resolved value. Test discovery is
runtime reflection with no static call site, so the check that stripping is safe is the
**count**, not the verdict: 316 cases (291 Swift Testing + 25 XCUITests), unchanged, and
Release links clean. `STRING_CATALOG_GENERATE_SYMBOLS` is inert today – no `.xcstrings`
files exist and all three targets already override it – and is set at the project level
only, to seed the default for M18's CLI target.

### ✅ M12 – Missing-component semantics ⭐ *the spine*

Not user-visible on its own, and three later milestones are wrong without it.

`ColorValue.converted(to:)` drops all three component `missing` flags and carries only
`.alpha`. When two colors are *interpolated*, CSS requires missingness to survive into a
space with **analogous** components – an `h` that is `none` in `hsl` is still `none` in
`oklch` – and nothing in the codebase can express "analogous" today. `componentLabels` is
the closest thing and is display copy, not a fact.

**Two things this milestone was originally scoped to do are wrong, and reading CSS Color 4
§4.4.1 and §13.2 rather than reasoning from the enum is what caught them.** Both are
recorded here because the mistaken version is the intuitive one.

**Carry-forward is an *interpolation* rule, not a conversion rule.** The plan said to carry
missing flags at all three conversion sites. The spec scopes carrying to interpolation, and
says something different about plain conversion: *"if a color is automatically produced by
color space conversion, then any powerless components in the result must instead be set to
missing"* – the result's own powerless components, not the source's missing ones. So
`converted(to:)` stays a pure numeric conversion, and carry-forward becomes an explicit
operation that interpolation asks for. Whether the serializer marks powerless components
stays where it is, behind `noneForPowerlessComponents`, because that is a presentation
choice and printing `none` at people unasked is not an improvement.

**The powerless rules are hue-only, and the existing implementation already covers them.**
The plan invented "HSL saturation at `l == 0` or `100`"; the spec has no such rule – it says
only that such a color *displays* as black or white "due to gamut mapping to the display".
The complete list is HSL hue at `s == 0`, HWB hue when achromatic (`w + b >= 100%`), and
LCH/OKLCH hue at zero chroma, plus a UA rule to treat hue as powerless below an epsilon of
colorfulness. `markingPowerlessComponents()` already decides this with one OKLab-based
`isAchromatic` test, which lands on the correct answer for all four spaces by a different
route – and the epsilon rule is explicitly blessed. **Nothing to add here. Do not
"complete" it.**

What was owed, and what was built:

- **[`ComponentRole`](ColorCore/ColorSpace.swift)**, with `ColorSpace.componentRoles`
  beside `componentLabels` but categorically different from it – copy that may be reworded
  freely versus a fact with behavior hanging off it. `hueIndex` is now *derived* from the
  table (`componentIndex(of: .hue)`) so the two cannot drift, and a test pins the
  derivation against the four answers it gave as a hand-written list, because a mistyped
  role would otherwise move the picker's hue axis with nothing to say so.
  **The table is transcribed from the spec, not derived from the labels** – three of its
  groupings are not guessable. `r` and `x` are the *same* category, because XYZ counts as
  a "super-saturated RGB space" (likewise `g`/`y` and `b`/`z`). Chroma and Saturation are
  one category, "despite Saturation being Lightness-dependent". Whiteness and Blackness
  have **no** analog in any space. And `b` means different things in different spaces –
  Blues in RGB, Opponent b in Lab – so roles are per-space and never read off a letter.
- **Analogous *sets*, which are a second mechanism and easy to miss entirely.** After
  removing individually-analogous components, whatever remains on each side forms a set,
  and if *every* member of the source's set is missing, the whole destination set is
  missing. This is what makes `lab(50% none none)` → `lch(50% none none)` rather than
  `lch(50% 0 0)`, and `rgb(none none none)` → `oklab(none none none)` even though sRGB and
  OKLab share no individual component. Alpha is analogous to alpha.
  **A set travels whole or not at all**, which is the half that is easy to get backwards:
  `lab(50% 0 none)` → `lch` carries *nothing*, because one of the two set members is
  present. Both halves are tested, and swapping the `allSatisfy` for a `contains` fails
  three of them.
- **[`MissingComponents.swift`](ColorCore/Convert/MissingComponents.swift)** –
  `carriedForwardMissing(to:)` returns the mask, `convertedForInterpolation(to:)` is the
  operation M15 calls (and does, unchanged). `converted(to:)` is untouched, so the blast radius is nil and
  no existing test needed revising – `referenceSaysAchromatic` was never approached.
- **`ParseError.noneNotAllowedInLegacy` is gone**, which is the honest resolution rather
  than making it throwable. The parser deliberately *warns* here
  (`ParseWarning.noneInLegacySyntax`) because the intent is unambiguous, so the error case
  was a second, unreachable answer to a question already answered. A note where the warning
  is declared says so, since the tempting fix is to start throwing it.

**The ordering the spec demands is recorded at the API, because M15 will not have the spec
in front of it.** (It did not, and the note did its job – see M15, which adds the step
this one does not mention: powerless marking has to *happen*, after the carry-forward.) Carry-forward runs *before* powerless marking, never after: a
carried-forward missing component takes the **other** color's value when interpolated,
where a powerless one is zero, so marking first would convert a value the spec wants
preserved into a zero. Two tests hold the line – a carried hue keeps the value the
conversion produced, and a plain gray carries *nothing* even though its hue is powerless in
every polar space. Folding the two operations together would pass one and fail the other.

The spec's own worked examples are the tests: the two set cases above, plus
`lch(50% 0.02 none)` and `color(display-p3 0.7 0.5 none)` in OKLCH, where the missing hue
carries and the missing blue does not. The spec also prints what that pair converts to, so
those numbers are asserted too – **as roundings rather than with a tolerance**, because a
printed `0.0001` is a bucket and the true chroma is `5.9e-5`. Asserting `|x − 0.0001| <
5e-5` would have passed by 9e-6 and looked like agreement to four decimals, which it is
not.

**No oracle, and that is measured rather than assumed:** colorjs.io resolves `none` on
conversion (`hsl(none 50% 50%).to('oklch')` returns a real hue), so this is spec-derived
and property-tested like `Transform/`.

**Five mutations confirm the tests bite**, each failing exactly the tests that encode the
rule it breaks: collapsing Opponent b into Blues fails one, deleting the set rule fails
three, reordering HSL's roles fails four (including the `hueIndex` pin), turning the set
rule's `allSatisfy` into `contains` fails three, and dropping alpha's carry fails one.

Storage was safe as predicted: `ColorRecord.missingMask` is an `Int` and the `& 0b1111`
truncation is only on the read path, so this sets existing bits and forces no schema change.

### ✅ M13 – `calc()`, scoped

All three predicted layers moved, and each blocked for the predicted reason.
`UnsupportedFunctions` loses `calc` and keeps the rest – `min`/`max`/`clamp`/`round`
because they are the other math functions and none is evaluated, `var`/`env`/`attr` for
the permanent reason that they cannot be resolved from the string at all. The pre-tokenize
check therefore keeps its job and needed only a different worked example; it still fires
for a `var()` nested inside a `calc()`. `CSSTokenizer` gained `.plus`, `.minus`,
`.asterisk` and `.openParen`. And the slash was the real one: `calc()` is consumed **as a
unit** in `scanArguments`, so `rgb(0 0 0 / calc(1 / 2))` has two slashes meaning different
things with only the parens to separate them.

Scope held as drawn – `+ - * /` over numbers, percentages and angles, flat. Two things
inside that scope are more than they look. **Precedence is real**: `calc(1 + 2 * 3)` is 7,
which a left-to-right fold gets wrong, so the grammar is two levels rather than one. And
**the type rules are enforced** – matching types for `±`, a plain number on one side of
`*` and on the right of `/` – but they are phrased as *this parser's scope*, never as CSS
invalidity. Percentages resolve against a reference in a color component, so CSS Values
4's type algebra is more permissive here than these rules are; saying otherwise would be a
claim wider than the evidence, and widening the rules later should not have to retract one.

**A resolved `calc()` becomes an ordinary written `Value`, and that is a decision.**
Everything downstream – the per-component grammar, the legacy same-type rules, the
angle-slot check – then runs unchanged and cannot tell a computed value from a typed one,
which is why the milestone cost so little. It is also why `rgb(calc(50%), 0, 0)` satisfies
legacy rgb's same-type rule and `hsl(120, calc(25 * 2), 50%)` fails its
percentage-required one. Both are pinned rather than left to fall out.

Two findings worth carrying:

- **`calc(1 -2)` is rejected for free, and the reason is the same as CSS's.** The spec
  demands whitespace around `+` and `-` precisely because `-2` is otherwise a signed
  number – and `scanNumber` claims it here before the operator rules run, so the body is
  two adjacent values with no expression in it. The converse does not hold: `calc(1- 2)`
  is invalid CSS and parses here as a subtraction, because whitespace is discarded and
  nothing downstream can tell it from `calc(1 - 2)`. Documented leniency, in the safe
  direction – it accepts a typo rather than misreading a valid expression.
- **`calcUnterminated` needs *every* closing paren missing.** Drop only calc's own and it
  swallows the outer function's, so `rgb(calc(1 + 1 0 0)` fails as a malformed *body*
  rather than an unterminated call. The genuinely unterminated case is `rgb(calc(1 + 1`,
  which is what a field parsing as you type actually sees. Both are pinned; the test was
  written expecting the first to be the unterminated one, and the failure is what taught
  the distinction.

### ✅ M14 – Relative color syntax

Both predicted hook points were exactly where the plan said, and both were the dead ends
it described. `ParsedInput` needed no change after all – it wraps `ParseResult` opaquely
and never inspects the notation, so `ColorInputField.describe` and `notationIsReported()`
were the only consumers.

Four rules carry the milestone, and every one came from the spec rather than from reading
the existing code:

- **Channel keywords are a transcribed table on `ColorSpace`, never derived.** Not from
  `componentLabels`, which is display copy the UI layer may reword freely – today every
  label's first letter *is* the right keyword, which makes the derivation tempting and its
  failure silent, because rewording "Chroma" would make the parser accept
  `oklch(from red l o h)` and reject the spec's spelling. And not from `componentRoles`,
  which genuinely disagrees: XYZ counts as a super-saturated RGB space there and shares
  `(.reds, .greens, .blues)`, but its keywords are `x y z`. This is M12's lesson arriving
  a second time, at a different table.
- **A keyword's value is a `<number>` in its own *function's* written scale.** Which is
  `stored / numberScale`, and the two diverge in exactly one place – `rgb()`, stored 0–1
  and written 0–255. So `rgb()` and `color(srgb …)` disagree on the same space: red's `r`
  is 255 in one and 1 in the other. `ChannelBindings` therefore takes the function *and*
  the space, because neither implies the other – the function fixes the scale, the space
  fixes the spelling and is what the origin converts into.
- **The origin converts with M12's carry-forward.** The spec names CSS Color 4 §13.2
  outright, so this is `convertedForInterpolation(to:)` and not the similar-looking
  `converted(to:)`. Substituting the latter fails exactly the two missing-component tests.
- **`none` means two different things, and both are load-bearing.** Written bare a missing
  channel stays missing; inside a `calc()` the spec reads it as zero. Modelling a channel
  as `Double?` flattens them, which is why `ChannelValue` has two cases. Mutating either
  half fails tests the other does not.

Legacy commas with an origin are a **hard error**, unlike this parser's other comma
leniencies – those parse because the intent is unambiguous, and this one the spec rules
out. `ColorNotation.relative` accordingly carries no `legacy:` flag: there is no such
combination, so the type has nowhere to express it.

An origin is a nested color, so `consumeColor` reads one from the token stream and finds
its closing paren **by depth** – the opposite of `consumeCalc`, whose body cannot nest and
whose first `)` is therefore its own.

**Alpha clamping came out of this milestone and is not part of it.** The spec's relative
section states that alpha is clamped while components are not; measuring showed this
parser clamped neither, and had not since M2. Fixed in `assemble` for *every* syntax
rather than only the relative one, in its own commit – clamping just the relative path
would have made `rgb(0 0 0 / 2)` and `rgb(from black r g b / 2)` disagree for no
reconstructible reason. The asymmetry is the part worth keeping: components must stay
unclamped or an out-of-gamut color could not be written at all, and the "Outside sRGB"
badge exists to report exactly those; alpha has no equivalent story.

**Out of scope, deliberately:** the spec's `alpha()` function, which has its own grammar
row and its own processing-space rule (the *origin's* space, not the output's). Recorded
in the deferred list rather than left implied by a ✅.

### ✅ M15 – `color-mix()`

The milestone M12 was written for, and it consumed it exactly as planned: each side goes
through `convertedForInterpolation(to:)` rather than `converted(to:)`. Nothing else was
reusable – `ShadeRamp` interpolates one scalar from one color, `Harmony` rotates a hue,
and `CVDSimulation`'s `lerp` is over matrix coefficients – so
[`Convert/Interpolation.swift`](ColorCore/Convert/Interpolation.swift) is new: the four
hue arcs, the percentage rules, and premultiplied interpolation.

**Both predicted oracle traps were real, and a third rule was not predicted at all.**

1. **`premultiplied: true`**, as planned. colorjs.io's default is not premultiplied and
   CSS is; the default returns `rgb(50% 0% 50%)` where the answer is
   `rgb(33.333% 0% 66.667%)` – a plausible wrong color rather than an error, which is
   what makes it the same class of trap as the WCAG `0.03928`/`0.04045` split.
2. **colorjs.io gamut-maps both endpoints before interpolating** – `range()` calls
   `toGamut()` on each, "to avoid areas of flat color". CSS Color 4 §12 has no such step.
   So for endpoints outside the interpolation space's gamut the oracle is answering a
   *different question*, and the generator skips those combinations (26 of them) rather
   than recording them. ColorCore's answer is pinned from the other side, by a test
   asserting that `color-mix(in srgb, color(display-p3 0 1 0), black)` keeps its negative
   red channel. **This was found by reading the reference's source, not by a failing
   test** – the fixture would simply have encoded the wrong behavior and passed.
3. **Powerless components must be marked missing before interpolating, and that step was
   not in the plan.** It is also the one with the most visible failure: white's OKLCH hue
   is 0° by convention, so `color-mix(in oklch, white, blue)` without it averages 0° and
   264° into 132° and returns a **green**. Marking it gives the light blue anyone expects.
   The ordering M12 recorded still holds – carry-forward first, marking second – and the
   reason it matters is now sharper: *inside* interpolation both kinds of missing behave
   identically (each takes the other color's value), so the order is about not blanking a
   value carry-forward is supposed to preserve.

**Percentages are their own small specification**, and are handled in `MixWeights` rather
than in the parser, so they are testable without a string. Both omitted is 50/50; one
omitted is the complement of the other; both given re-normalize – and if they sum to
*under* 100% the result's alpha is multiplied by the shortfall, so `red 20%, blue 20%` is
an even mix at 0.4 alpha. Over 100% only re-normalizes, because scaling up would hand back
a color more opaque than either input. Both at 0% is invalid, which is the one input with
no answer and hence the failable initializer. A percentage outside `[0, 100]` is
**rejected rather than clamped**, which is the opposite of alpha's rule two milestones
back and deliberately so: an out-of-range alpha has an obvious intention to read, where
`red 150%` has none.

**`color-mix()` is not a `ColorFunction` case**, and that is the shape decision worth
recording. Every member of that enum takes *components*: each has a per-component grammar,
a legacy-comma question and a fixed space. A mix has none of the three, so a case there
would have meant four tables gaining an entry that means nothing. It is a branch at the
top of `parseFunction` – which is what makes nesting free in both directions, since
`consumeColor` routes through the same function – plus a `ColorNotation.mix` case carrying
the interpolation method.

**The space table is *derived*, and that is not a contradiction of M12's and M14's
transcription rule.** Those tables carry facts the identifiers do not: a component's role,
its channel keyword, and which eight of the fourteen spaces `color()` accepts. Every space
is a legal interpolation space and the raw values are the CSS identifiers, so there is
nothing for a derivation to lose. The discriminating question is not "is this a table" but
"can a derivation drop a fact".

**Written without a compiler, then compiled – and the gap between those two states is
the most useful thing this milestone recorded.** The first commit was built in a Linux
container with no Swift toolchain, so its proof was a line-for-line JavaScript port of
the interpolation algorithm run against all 1,760 vectors with zero divergences, plus
the powerless verdicts (`isAchromatic` against colorjs.io's `null` hue) confirmed against
every endpoint and space in the fixture. On a Mac the app target built clean on the first
attempt and all four suites passed, 1,760 vectors included.

**And one of them was wrong anyway, which is the point.** `premultiplied(_:leaving:)`
exempted a color whose *own* `missing` mask held alpha, rather than one where alpha was
missing on **both** sides. §12.2's substitution runs before §12.3 premultiplies, so a
one-sided `none` alpha already carries the other color's value by then; skipping it
scales one end and not the other, and the divide on the way out lands
`color-mix(in srgb, rgb(255 0 0 / none), rgb(0 0 255 / 0.25))` on 200% red. The
JavaScript mirror could not have caught it – it was a port of the same reading, so it
reproduced the same rule – and neither could the fixture, because `MixFixture.Endpoint`
types alpha as a plain `Double` and no recorded endpoint can be missing one. What caught
it was reading the code against the spec's *order of operations* and then asking the
oracle a question the generator had never asked it. The cheap statement of the bug is
that the rule was not symmetric: it made an even mix depend on the order of its operands.

**Mutation survey: eleven mutations, all eleven killed – but two of them only after the
survey.** Removing the both-sides-missing exemption and removing the alpha-0 guard both
survived the suite as committed. The first is observable only in the value stored beneath
a `none` flag, which never reaches CSS output; it takes `lab(none none none)` mixed with
`hwb(none none none)`, whose §13.2 set rule carries *different* values across into sRGB,
to see it at all. The second is plainer and worse: mixing two fully transparent colors
divided 0 by 0 and returned a NaN color. Both now have tests, and both tests were
confirmed to fail against the mutation they own.

UI folded into `TransformPanel` as a fifth section. **No eighth `Tool` case** – see the
note in `ContentView`. The second color is the *background*, not a third field of the
panel's own, because the app already edits a pair and a mix needs two colors; the section
says so and points at the contrast tool when there is no background, exactly as the
legibility section below it does. The five-stop strip is the live preview and the amount
slider is the pending edit – the same split as the contrast push, and reset by `apply` for
the same reason, since repeated application converges on the background. The
`color-mix()` expression is printed under the result, which is now something you can paste
back into the field.

### ✅ M16 – `@media (color-gamut)` export shape

One `ExportShape` case, `p3WithFallback`, and one private generator at
`ExportOptions.render`: a hex fallback block, then `@media (color-gamut: p3)` re-declaring
the same properties in `color(display-p3 …)`.

**The shape needs two spellings where `ExportOptions.format` is one value.** Leaving the
panel's format picker live would let a user choose `.oklch` – the default, and unbounded –
filling the "fallback" block with out-of-sRGB values and defeating the point. So
`usesFormat` joins `usesTemplate` and `usesName` as a shape-capability flag and returns
`false` here. It is the first of the three that exists to stop a control being *harmful*
rather than merely inert, which is why the panel hides it rather than disabling it. The
fallback is hex on principle rather than laziness: that block's job is to be what a browser
without P3 support gets, hex is the most broadly compatible spelling there is, and it is
the only choice that `cannotRepresentOutOfGamut` – so the fallback provably falls back. The
override is emitted for every entry, including colors already inside sRGB – a per-entry
conditional would make the media block's contents depend on the palette's contents, so
editing one color would silently change which properties exist.

**What the plan did not anticipate: the mapped badge and its sentence have to be decided
together, because neither reading is true as worded.** The invariant is that one predicate
decides both the badge and the serialized string, and a shape writing two spellings is the
first thing to strain it. Measure against the P3 block and a color outside sRGB reports
`0 mapped` while the hex line directly beneath the badge has been rounded – the badge
silent about a value that changed. Measure against hex and the count is right, but the
existing copy is not: *"the values below were brought into gamut"* is true of the fallback
and false of the media block underneath it, which carries those same colors exactly. That
is the whole reason the shape exists, so a warning that did not say so would read as a
defect. The resolution is `ExportOptions.mappedCountFormat` – `format` for every
single-spelling shape, the **fallback** for this one – plus a per-shape `mappedNote` in the
UI layer, where editorial copy belongs. One predicate still, no second rule.

**The residual is recorded rather than answered:** a color outside *P3* is gamut-mapped in
both blocks and the badge does not distinguish it. A two-count badge is a different feature
from the one this milestone asked for, and this is the same accepted-limitation move as
`cssIdentifier` being lossy and ramp stops rounding outward at display precision.

**But the residual's effect on the *wording* was not a limitation, it was a defect, and it
shipped in the first commit.** The note read "the @media block carries them exactly" – true
of the P3-reachable colors that motivate the shape, and false of every color outside P3,
which this same badge counts because the count is measured against hex. So the panel made
an affirmative false statement about a value three lines beneath it: a user could ship a
stylesheet believing a Rec.2020 color had survived into the P3 block. The fix is wording
only – the note now stops at *which block writes what*, which is true either way, and the
two-count deferral above stays honest instead of understated. **The tests did not catch it
because they checked substrings**, and a substring cannot catch a false claim; the fact is
now pinned by an *input*, a Rec.2020 primary.

The sharper version of the rule surfaced only when that test was written, and it is worth
stating on its own: **the override is not hex, so it has no fixed answer.**
`color(display-p3 …)` is not `cannotRepresentOutOfGamut`, which means it follows the
app-wide gamut policy exactly as it does in every other shape – `.map` in the panel, and
`.preserve` under `CSSFormatOptions.lossless`. So whether the media block is exact depends
on a setting elsewhere in the app, which is a second and independent reason the note cannot
promise it. Both policies are asserted.

`propertyLines` is shared with `customProperties` so the two blocks cannot come to name
different properties. An override that misses its base is a `@media` block with no effect,
and nothing about the document looks wrong – which is why the two name *lists* are asserted
equal rather than spot-checked.

*Done, and reviewed on the running app from its own screenshot – see the status note above
for the colorjs.io cross-check of the fallback's gamut mapping, which discriminates against
a naive clip rather than merely agreeing.*

### ✅ M17 – W3C Design Tokens import

> **The four paragraphs below were written before the work, and two of their claims did not
> survive it.** They are kept rather than rewritten, because what a plan got wrong is worth
> as much as what it got right – but read them with the corrections, which are flagged in
> place and argued under **Done** at the end of this section. The `fullScale` instruction is
> the one that would actively mislead: following it rejects legal tokens.

Depended on M12, which is done: DTCG `components` accept `"none"`, and a decoded token now
has somewhere honest to put one.

**Checked against the Color Module rather than assumed, and the first assumption was
wrong.** `$value` is an **object** – `{colorSpace, components, alpha?, hex?}`, the first
two required – not a CSS string, so `CSSColorParser` is the wrong entry point and this is
component-based construction. But the payoff is large: the **14 `colorSpace` identifiers
are byte-identical to `ColorSpace`'s raw values**, because both follow CSS Color 4 naming –
the same reason `ColorRecord.spaceID` stores CSS names rather than enum ordering. There is
no mapping table to write; `ColorSpace(rawValue:)` is the decoder, and an unknown space is
skipped exactly as `ColorRecord.colorValue` already skips one. ~~Component ranges are
per-space, so reuse `ColorGrammar.components(for:)`'s `fullScale` rather than writing a
second table.~~ – **wrong, and the correction is the interesting part: the mapping needs no
range table and no arithmetic at all.** `fullScale` is a precision hint, not a bound, and
the Color Module leaves both chromas and both a/b pairs unbounded, so validating against it
rejects legal tokens. See **Done** below. `hex` is a fallback, not the value.

The sandbox already permits it – `ENABLE_USER_SELECTED_FILES = readonly` is set, so
`fileImporter` needs no project change. This would be the app's first file-reading
affordance of any kind, and still is the only one. ~~Note that `ColorStore.stage(_:named:)`
flips `tool = .export` while an import should land in **Projects**, so it needs a sibling
path rather than a changed one~~ – **the second claim that did not survive: no sibling was
needed and `ColorStore` was not touched at all.** An import lands as a `Palette`, and the
Export button already on `paletteRow` stages it – so `stagingCarriesTheName` pins behavior
that never had to change. And record the honest limitation:
`ExportOptions.cssIdentifier` is lossy, so a name that leaves through export does not
return through import unchanged.

UI lives in `ProjectsPanel`. No eighth `Tool` case.

**Done, and confirmed on the running app** – see the M17 entries under *Verification*, where
the one check no test could make is recorded along with the three rules its screenshot
happens to discriminate. `ColorCore/Import/DesignTokens.swift` decodes a token file; `ProjectsPanel` owns
the `fileImporter`; `ProjectLibrary.savePalette(importing:named:to:)` is the mutation, so
the whole path is assertable against a container. `PaletteKind.imported` records the
provenance – schema-safe, since `kindID` is a string with a `?? .custom` fallback and no
property changed. What the note above got right held up: the fourteen `colorSpace`
identifiers *are* `ColorSpace`'s raw values, and `ColorSpace(rawValue:)` is the whole
decoder. Note it is **not** `ColorGrammar.colorFunctionSpaces`, which additionally accepts
CSS's `xyz` alias that this format does not have.

Five decisions worth keeping, three of which came out of the design review rather than the
build:

- **Aliases resolve *before* the type filter, not after.** The format's precedence is
  explicit `$type` → **the resolved reference's** type → the nearest group's. So a token
  with no type of its own that aliases a color token is a color token, and filtering first
  drops exactly those – silently, which is the same class of defect as a colliding key.
  Both alias spellings are supported (`{group.token}` and the draft's `$ref` JSON Pointer),
  because they are one lookup with two spellings and declining the second means a file
  using it imports as empty. Cycle detection is not defensive tidying: without it a
  self-referential file – legal JSON, plausible hand-editing mistake – takes the process
  down, which is exactly what the mutation showed.
- **Paths are unique; the keys they sanitize to are not.** `-` is a legal name character
  and `.` is not, so `brand.500` and `brand-500` are two legal tokens that
  `ExportOptions.cssIdentifier` maps onto one identifier. Two entries sharing a key do not
  produce a duplicate property – they produce a *single* one, and a color disappears from
  the export with nothing in the document to say so. So the uniquing runs against the
  **sanitized** key, not the raw path.
- **A deterministic order had to be chosen, because there is none to preserve.**
  `JSONSerialization` returns an unordered dictionary, so the document's own ordering is
  not available at any price – and a palette's order is load-bearing. All-digit names
  compare numerically and everything else compares as text, so a shade ramp lands
  `50, 100, 950` rather than the alphabetical `100, 1000, 50`.
- **An imported color is stored spelled in the space its token named.** A third
  `savePalette` overload rather than a conversion into either existing one, for the reason
  that keeps those two apart: what differs is how the stored *spelling* is derived. The
  `PaletteEntry` overload writes `oklch()`, which is right for a ramp stop that never had a
  space of its own; a design token's `colorSpace` is authored information, so a
  `display-p3` token comes back `color(display-p3 …)`. Same objection as rewriting a typed
  `rebeccapurple`, applied to somebody else's authoring. `$description` becomes the color's
  notes, the field it was already for.
- **`hex` is a fallback for an unknown *space*, and nothing else.** A known space with
  unreadable components is a broken token and is reported as one, even when a perfectly
  good `hex` sits beside it – taking it would substitute a 6-digit sRGB approximation for
  whatever the components meant and say so nowhere. The unknown-space path mirrors how
  `ColorRecord.colorValue` already treats a stored space it does not recognize.

**No `ColorStore` change, which retires this milestone's own concern about `stage`.** The
note above worried that `stage(_:named:)` flips `tool = .export` and wanted a sibling path.
None is needed: once an import lands as a `Palette`, the existing `Export` button on
`paletteRow` stages it exactly as a saved harmony is staged. `stagingCarriesTheName` is
untouched, and export came free – a claim that is now *tested* rather than asserted, since
it is the feature's whole payoff and was for a while the only sentence here with nothing
behind it.

**The double prefix in `--brand-brand-50` is expected, and is what the conventional file
shape produces.** The family name comes from the file (`brand.tokens.json`) and the key
from the token's full path (`brand.50`), and those two sources overlap whenever a file's
top-level group is named after the file. Left alone rather than stripped: the family name
is free text in the export panel and one edit away, where automatic stripping would make
the keys depend on how many top-level groups a file happened to have. The exported string
is pinned by a test so the shape is a decision on record rather than a surprise.

The honest limitation the note asked for is recorded and unchanged: `cssIdentifier` is
lossy, so a name that leaves through export does not return through import unchanged.
Composite token types that *contain* colors – `shadow`, `border`, `gradient` – are counted
as other types rather than descended into; that is a second feature, not this one.

### ✅ M18 – CLI front-end

Last, so it exposes a finished `ColorCore` rather than being revised by every milestone
above – and the plan's three predictions about the target all held. A
`com.apple.product-type.tool` target lists the `ColorCore` root group alongside the CLI's
own, so `internal` still works; `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is set
per-target on the app and a fresh target correctly defaults to `nonisolated`; and every
ColorCore file imports `Foundation` and nothing else, so nothing had to move. `ParsedInput`
is reimplemented as `ColorArgument.parse` – and the difference is more than isolation.
`ParsedInput` keeps the last color that *did* parse so the panel does not blank out halfway
through typing `oklch(`; a CLI gets one shot at one string, so that third state has no
meaning here and is deliberately absent.

**`colorkit` is nine commands, and one of them is missing on purpose.** `convert`,
`contrast`, `solve`, `adjust`, `harmony`, `ramp`, `cvd`, `export`, `tokens` – everything the
app's panels do with color except the two things that are not color: the eyedropper is
`NSColorSampler` and saved projects are SwiftData, so neither is in `ColorCore` and neither
could come. **There is no `mix` command**, because `CSSColorParser` already accepts
`color-mix(in oklch, red, blue)` and `rgb(from red r g b)` as *input* – a subcommand would
be a second door into a room that already has one, and it would have to reimplement the
grammar to build its arguments back into the string the parser wants. A test pins that,
so the argument stops holding out loud rather than quietly.

**Two root groups for one executable, and the second is what avoids an exclusion list.**
`ColorKitCLI/` holds the logic and is compiled by the tool *and* by its test bundle;
`ColorKitCLIMain/` holds `main.swift` alone and is compiled by the tool only, because
top-level code is legal only in an executable module. The alternative was a
`PBXFileSystemSynchronizedBuildFileExceptionSet` naming one file – a list to keep in step
with the file system, which is precisely what M10 moved `ColorCore` to a root group to
avoid. A folder costs nothing and cannot drift.

**A third target compiles `ColorCore` a third time, and the two cheaper options are both
wrong.** The CLI cannot be tested from `ColorKitTests`: its sources reach ColorCore
through their own module, so compiling them into a target that reaches ColorCore through
`@testable import ColorKit` does not build – and listing `ColorCore` in that target as
well would *shadow* the import rather than merely duplicate it. Black-boxing the built
binary from the test host is worse: the host is the sandboxed app, so a sandbox denial
would be indistinguishable from a real failure. `ColorKitCLITests` therefore lists
`ColorCore`, the CLI and its own sources and imports nothing.

**Three rules the CLI adds, each an answer to a question the GUI answers by drawing.**

- **Results to stdout, everything else to stderr, and three exit codes** – 0, 1 for a
  command that ran and failed, 2 for a command line that was wrong. That split is what
  makes `$(colorkit convert red --format hex)` safe and what makes "a Raycast wrapper is a
  shell call rather than code" true. A failing run puts *nothing* on stdout; a parse
  warning goes to stderr and leaves the exit code alone.
- **An option the chosen shape would ignore is an error, not a no-op.** The export panel
  *hides* the Format picker when `ExportShape.usesFormat` is false, because
  `p3WithFallback` fixes both its formats. A CLI has no control to hide, so the equivalent
  honesty is refusing `--format` there – a flag that changed nothing would look like it
  had worked. Same for `--name` and `--template` against `usesName`/`usesTemplate`, and for
  `--spread` on a harmony that is not analogous.
- **`ExportShape`'s raw values are not CLI identifiers.** They exist for `Identifiable`
  and are not uniform: three carry an explicit hyphenated string, three fall back to their
  case names, and one of those – `customProperties`, sitting beside `tailwind-theme` – is
  camelCase. So shapes get a hand-written name table like
  `ContrastRequirement` does, while `Harmony`, `ExportTemplate`, `ColorVisionDeficiency` and
  `ColorSpace` stay derived – their raw values *are* the CSS identifiers, which is the same
  test `ColorGrammar.interpolationSpace(named:)` passes. A test requires every shape name
  to round-trip and to contain no uppercase, so the distinction fails loudly.

**The one thing the CLI found that the app had not had to face: a solved color and its
printed spelling can disagree.** `ContrastSolver` keeps its bracket's passing end, so the
answer sits a hair *above* the target – which is exactly the margin four decimals can round
away. Measured on one input, the printed value meets AA at precision 5, 7, 8 and 10 and
misses it at 4 and 6, so this is rounding luck and **no default precision fixes it**.
Biasing the rounding was rejected for the reason CLAUDE.md already gives about ramp stops:
it would make this command's output disagree with every other one. So `solve` reads its own
printed value back and says on stderr when the text no longer clears the bar, naming
`--precision` as the fix. The claim the CLI can actually keep is a disjunction – the printed
value meets the target, *or* stderr says it does not – and that is what the test asserts.

---

## Planned: M19–M26 – round out the toolkit

The numbered plan (M0–M18) is complete and M8b closed the last deferred item, so the
next series is eight new milestones rather than more of the old list. They close the
app's biggest remaining workflow gaps:

- **Export is one-directional.** The app writes six document shapes and reads only W3C
  design tokens. Pasting a stylesheet's `:root` block back in is not possible.
- **Export is one-palette-at-a-time.** A project with eight saved sets takes eight trips
  through Projects → Export → configure → Copy. `ExportOptions.render` takes a single
  `[PaletteEntry]` and one family name, so no shape in the core can carry a whole project.
- **Colors are inert.** `ColorSwatch` (`DesignSystem/ColorSwatch.swift`) carries no
  gesture; of fifteen call sites only three are clickable.
- **Nothing persists and there is no settings home.** No `Settings` scene, no
  `@AppStorage`, no `UserDefaults` – `formatOptions`, `pickerMode` and the rest die at
  quit.
- **The header is read-only.** The active swatch and the notation text under it
  (`ColorInputField.status`) are not interactive, so changing or re-spelling the active
  color always means leaving where you are.
- **Recents exist but are hidden.** `ColorStore.recents` is populated and capped at 12,
  and the only surface is the menu-bar panel – the main window never shows them.

Four decisions were settled with Parker before planning, each overriding a more obvious
reading, and are not to be re-litigated when implementing:

1. **"Web-friendly" means sRGB-safe**, not "browser-supported" – every format in the
   catalog is in fact supported by current browsers, so the honest filter is about gamut
   and exoticism. `color(srgb …)` is hidden too, despite being in-gamut, because the
   `color()` family is not a hand-written style.
2. **A tool that cannot stay in sRGB is hidden, not half-restricted.** `color-mix()` is
   the only one that qualifies – see M22.
3. **The importer's "format" control chooses the storage spelling**, not an input hint.
   The parser already reads all 17 formats from each value's own syntax; default is
   preserve-as-pasted.
4. **A real `Settings` scene with `@AppStorage`-backed persistence**, migrating the
   existing output options into it – nothing in the app persists today.

Ordered by dependency, executed top to bottom:

| #   | Milestone                                | Depends on                      |
| --- | ---------------------------------------- | ------------------------------- |
| M19 | Settings scene + persisted preferences   | –                               |
| M20 | Grouped export (whole-project export)    | –                               |
| M21 | Interactive swatches                     | –                               |
| M22 | Web-friendly mode                        | M19                             |
| M23 | Recents row + picker commit-on-release   | M19, M21                        |
| M24 | Popover picker on the header swatch      | M21 (M22 for the plane's gamut) |
| M25 | Click the notation to re-spell the color | M22 (for filtering)             |
| M26 | Import from the export shapes            | M19, M20                        |

Each milestone is its own commit (or small stack), each of which must build and test
standalone – verify in a throwaway worktree before stacking the next, per this file's
commit discipline below. Formatting is always a separate follow-up commit, per CLAUDE.md.

### ✅ M19 – Settings scene and persisted preferences

The foundation M22 and M23 will need, and the first persistence the app has outside
SwiftData. Built as planned, with one addition the plan note had not spelled out: a
manual Codable conformance for `CSSOutputFormat`.

**Where preferences live did not change.** `ColorStore` already documented itself as the
home for "preferences about how you like to work" (`pickerMode`, `cvdDeficiency`,
`harmony`, `mixSpace`, `exportOptions`). Two new ones joined them, `webFriendly` (for
M22) and `showsRecents` (for M23), and `recentLimit` moved from
`private static let recentLimit = 12` to a settable instance property, defaulting to the
same 12.

**One new seam, not a second store.** `ColorKit/Services/Preferences.swift`:

- `struct Preferences: Codable, Equatable, Sendable` with **explicit `CodingKeys`**,
  holding the deliberate persisted subset – `formatOptions`, `webFriendly`,
  `showsRecents`, `recentLimit`, `pickerMode`, `cvdDeficiency`, `exportShape`,
  `exportTemplate`, `exportFormat`. Explicit keys because `Codable` derives its keys
  from property names and a future rename would break decoding with a green build – the
  same hazard `.swiftformat`'s empty `--acronyms` exists to prevent. *Not* persisted:
  `inputText`, `backgroundText`, `exportOptions.name`, `recents`, `selectedProjectID`,
  `stagedPalette` – session state, not preferences, and a toolkit that reopens on last
  week's half-typed color is worse than one that reopens clean. A regression test pins
  this directly: assigning a full `Preferences` to `ColorStore` must not touch
  `exportOptions.name` or `inputText`.
- `enum PreferenceStore` – one `UserDefaults` key, JSON-encoded, with `load(from:)` and
  `save(_:to:)` both defaulting to `.standard` but accepting an injected `UserDefaults`,
  which is what lets `PreferencesTests` write and read without touching the real
  defaults. A decode failure returns defaults silently; a corrupt preference file is not
  worth a banner the way a corrupt project store is. `defaultsKey` stays non-`private`
  on purpose – it is what lets a test plant a corrupt value directly, the only way to
  exercise that path without going through `save` first.
- **`UITestEphemeralPreferences` launch argument**, exactly parallel to
  `PersistenceStack.inMemoryLaunchArgument`. Without it XCUITest would inherit the
  developer's settings and a run's result would depend on who ran it. **This cost three
  launch strings, not one** – `["-NSTreatUnknownArgumentsAsOpen", "NO",
  "UITestEphemeralPreferences"]` – for the reason CLAUDE.md records: a bare argument goes
  to AppKit as a file to open and the app launches with a menu bar and no window. All
  seven existing UI test files gained the string, not only `ProjectsSmokeTests` – six of
  the seven previously launched with no arguments at all, so this is also the first time
  those six needed the AppKit opt-out paired with it.

**`CSSFormatOptions` becomes `Codable`**, and so do `GamutPolicy` and `AlphaPolicy`,
given `String` raw values so `Codable` synthesis has something to key off. Compiler-
checked, and it keeps one source of truth rather than a mirrored copy that can drift.
**`CSSOutputFormat` needed a hand-written conformance instead** – the plan note did not
anticipate this. It is not `RawRepresentable` (`.color` carries a `ColorSpace`), so there
is no raw value for synthesis to use. The chosen spelling mirrors
`ColorKitCLI/Names.swift`'s `--format` vocabulary exactly – the `color()` cases named
by their space's own raw value – not because the two share code (they cannot; see the
CLI/app module split) but because it is one fact transcribed twice rather than two
decisions. `CSSFormattingTests.formatCodableRoundTrips()` walks the whole catalog through
encode/decode so a copy-paste slip in either switch has somewhere to surface.

**The scene.** `Settings { SettingsView().environment(store) }` in
`ColorKitApp.swift`. New `ColorKit/Features/Settings/SettingsView.swift` with
three sections: General (web-friendly, recents row, recents count), Output (the existing
seven controls from `OutputOptionsMenu`, bound to the same store properties), and a Reset
button that assigns `Preferences()` wholesale.

**`OutputOptionsMenu` stays** (`ContentView.swift`). It is a second surface onto the same
values, which is the precedent the export panel's Precision picker already set and
documented – not a second setting.

**Load-at-launch and save-on-change live in `ColorKitApp`, not in `ColorStore`.**
`ColorStore.preferences` is a plain computed property – no I/O – so every unit test's
`ColorStore()` stays deterministic regardless of what the machine running it has saved to
its real `UserDefaults`. The app loads once, in the `@State private var store` initial-
value closure (`store.preferences = PreferenceStore.load()`), and saves via
`.onChange(of: store.preferences)` registered in **two** places – the window's
`ContentView` and `MenuBarLabel` – for the same reason the global shortcut is claimed
from both scenes: neither is guaranteed to be on screen, and a change made while the
window is closed still needs to reach disk. Saving twice for one change is harmless,
since it overwrites the same key with an equal value.

**A negative `recentLimit` is a real crash, not a hypothetical one, and the fix is a
clamp at the one place an untrusted value becomes trusted state.** `remember()` computes
`recents.removeLast(recents.count - recentLimit)`, and `Preferences.recentLimit` decodes
successfully for *any* `Int` – the Settings panel's Stepper is the only thing keeping it
in `1...50` along the ordinary path, and a hand-edited or corrupted preferences file
bypasses it entirely. `ColorStore.preferences`'s setter now clamps to `max(1, …)`.
**Confirmed empirically, not assumed**: with the clamp removed, assigning
`recentLimit: -5` and calling `remember()` crashed with
`Fatal error: Can't remove more items from a collection than it contains` – exactly the
trap – before the clamp was restored.

**Testing.** [PreferencesTests](ColorKitTests/PreferencesTests.swift): every field
round-trips through encode/decode changed from its default in one fixture (including
`exportFormat: .color(.displayP3)`, the one case that exercises `CSSOutputFormat`'s
associated-value branch rather than a plain one); decoding garbage yields defaults;
`save` then `load` round-trips through an injected `UserDefaults` suite;
`ColorStore.preferences` re-emits what was assigned to it; session state survives an
assignment untouched; and the negative-`recentLimit` crash above is pinned as a
regression. **Confirmed the mutation directly**: dropping `webFriendly` from
`CodingKeys` was built, run, and failed exactly `roundTrips()` and
`saveThenLoadRoundTrips()` – the two tests that could tell – before being reverted. Two
more tests exercise `CSSFormatOptions`'s own synthesized conformance and
`CSSOutputFormat`'s hand-written one directly, in `CSSFormattingTests.swift`, since
`Preferences`'s round trip alone would only prove the composition and not each type on
its own. **A ninth test pins the claim the `preferences` doc comment makes rather than
leaving it as reasoning in a comment**: `withObservationTracking` around a read of
`store.preferences`, mutated at three sites – a field on the store directly, one nested
in `formatOptions`, one nested in `exportOptions` – confirms the getter's `@Observable`
access really does reach through both levels of nesting, which is what lets
`ColorKitApp`'s `.onChange` fire on any persisted change without listing nine
properties itself.

**Manual check, recorded for when this ships and not yet run.** Quit and relaunch,
confirm preferences survive; confirm a UI-test launch does *not* inherit them; look at
`SettingsView` on screen for the first time, since M0–M9's precedent of reviewing every
new panel on the running app was not followed here. Unlike M8b's file write and M17's
file read, `SettingsView` is an ordinary in-process window and XCUITest *could* reach
it – this is not the file-panel class of check – but writing that coverage was judged
out of scope for the milestone that introduces the scene, matching the plan note's
original call that this check stays manual. When run: locate the container with
`ls ~/Library/Containers/*olor-*oolkit/Data/Library/Preferences/` (the container's
bundle-id casing does not match `PRODUCT_BUNDLE_IDENTIFIER` exactly) and read the key
back with `plutil -p`, and quit with ⌘Q or `osascript -e 'quit app "ColorKit"'`
rather than `kill -9` – `UserDefaults` writes go through `cfprefsd` asynchronously, so a
hard kill can lose an unflushed write and look like a bug that is not one.

### ✅ M20 – Grouped export: write a whole project at once

Built as planned – one generalization, not a second renderer – with one correction the
advisor caught before it shipped and one compile-time trap the two-overload design
introduces that the plan note did not anticipate.

**`PaletteGroup` landed exactly as sketched**, beside `PaletteEntry` in
`ExportTemplate.swift`, and `render(_ entries:formatting:)` is now the one-line special
case of `render(_ groups:formatting:)`. Single-group output is byte-identical to before –
proved by leaving every exact string in the pre-M20 `ExportShapeTests` and
`ExportRoundTripTests` untouched rather than re-asserting the claim, since a wrapper that
calls the general case is trivially equal to itself and a new test saying so would pass
under any bug in the grouped renderer.

**That proof turned out to be uneven across shapes, and an advisor pass is what caught
it.** `declaration` and the three shapes sharing `groupedPropertyLines`
(`customProperties`, `tailwindTheme`, both of `p3WithFallback`'s blocks) each guard their
own `/* From "…" */` header independently, so "always emit the header" was really four
separate mutations, not one. Forcing it on in `groupedPropertyLines` fails
`customProperties` and `p3WithFallback`'s pre-existing exact-string tests – three
failures, the byte-identity claim made concrete for those two – but **`tailwindTheme`'s
own pre-existing test passed anyway**: `tailwindThemeBlock` only checks
`.contains`/`.hasPrefix`/`.hasSuffix`, none of which notices an extra comment appearing.
A single-group exact-string test had to be added for `tailwindTheme` specifically
(`tailwindThemeSingleGroupHasNoHeader`) before the mutation had anywhere to fail.
`declaration`'s own header guard was already covered – its pre-existing single- and
two-entry tests are both exact strings – but had no *two-group* test at all, so
`declarationGroupsGetHeaders` was added alongside it. Both additions were confirmed
against the mutation they close before being trusted, the same as the four below.

The four things the plan flagged all held:

- **The loose-color case needed no new rule.** `PaletteEntry`'s existing empty-key
  convention does the work; a project color's group is one entry with an empty key, and
  `propertyName`/`soleEntry` already treat that as `--text-color` rather than inventing
  a suffix.
- **Group names are uniqued against the sanitized name**, with the same `-2`/`-3` suffix
  loop `DesignTokenImport.keyed` and `ProjectLibrary.paletteKeys` use. **One limitation is
  recorded rather than fixed**: uniquing is group-versus-group only, so a palette
  `brand` with a `500` entry and a loose color literally named `brand 500` both resolve
  to `--brand-500` – the entry's own key was never in scope for this rule, and widening
  it would be a different feature than the one asked for.
- **`p3WithFallback` walks groups after branching on shape**, through a `groupedPropertyLines`
  helper shared by `customProperties`, `tailwindTheme` and both of `p3WithFallback`'s
  blocks – so no two of them can name a group's properties differently.
- **Group comments are `/* From "…" */`, in the four CSS shapes only**, sanitized through
  `cssIdentifier` for the reason the per-entry comment already was. The plan's example
  text said `/* From a ramp named "primary" */`; the shipped wording drops "a ramp
  named" because `PaletteGroup` carries no provenance – it is a name and a list, and a
  loose color's group is not a ramp. Inventing a "kind" just to fill in that phrase would
  have been a second table for no reader-facing gain.

**The one correction:** the plan's `entries(for:)` sketch put `.project` in the `switch`
below the `guard let color else { return [] }`, mirroring `.saved`'s original position –
but `.saved` had already been *hoisted above* that guard for exactly the reason a staged
palette must survive an empty field, and copying the switch-arm position instead of the
hoist would have made a staged project disappear the moment the input field was cleared.
Caught before writing any test, by an advisor pass; `stagedProjectSurvivesAnEmptyField`
now pins it, mirroring `stagedPaletteSurvivesAnEmptyField`.

**The compile-time trap:** two `render` overloads differing only in `[PaletteEntry]` vs.
`[PaletteGroup]` make a bare `options.render([])` ambiguous – Swift has no context to
pick an element type for an empty array literal. One call site in the pre-existing
`ExportTests.swift` had exactly this shape (`emptyPaletteIsEmpty`) and needed
`options.render([PaletteEntry]())` instead; every other call site was already typed by
an initializer inside the literal (`[PaletteEntry(color: …)]`) and needed nothing.

**App wiring landed as planned**: `ExportSource.project` with its own `title` and
`emptyMessage`; `ColorStore.stagedProject: [PaletteGroup]` and `stage(project:named:)`
beside their single-palette counterparts; `ExportPanel`'s top guard extended to
`store.stagedProject.isEmpty`. `entries(for: .project)` flattens every group into one
list – for the badge count and the swatch strip, which have no notion of a group – while
`exportDocument` reaches `stagedProject` directly for the real document, since flattening
would lose exactly the per-group names the shape exists to keep.

**Projects panel**: `Export Project` in `header`, next to New and Delete, disabled when
the project has neither colors nor palettes. It builds `project.orderedPalettes` (each
under `palette.name`) followed by one single-entry group per `project.orderedColors`,
named after the color's own label (its `name` if set, its authored `text` otherwise) –
palettes first, matching the plan's reasoning that a ramp is the thing you came for.

**One decision recorded rather than resolved either way:** `ExportOptions.name` never
reaches a grouped document – every family comes from the group's own name – so
`ExportPanel`'s Name field, still shown because `shape.usesName` has no notion of groups,
does not move a character of the preview once a project is staged. It is not inert,
though: it still drives `suggestedFilename`, which is what `stage(project:named:)`
intends by seeding it with the project's own name. That is the same shape of thing
`usesFormat`'s doc comment warns about – "a flag that changed nothing looks like it
worked" – so it is pinned rather than left implicit:
`nameDoesNotReachAGroupedDocument` asserts both halves, that changing `name` leaves a
two-group document identical and still changes the filename. Gating the control was
considered and rejected – it is genuinely doing something, just not the thing a glance at
the preview would suggest.

**Testing.** Both parameterized `ExportSource.allCases` suites in `ExportStoreTests`
picked `.project` up automatically, and one of them – `sourcesMapToKinds` – is itself an
exhaustive switch that needed a line added or the build breaks, which is the point of
writing it that way. New coverage: `GroupedExportTests` in `ExportTests.swift` pins
two-group documents exactly for `declaration`, `customProperties`, `tailwindTheme`, `json`
and `tailwindConfig` (the JSON/Tailwind cases at both per-group cardinalities in one
document – a lone-color group beside a scale), a single-group `tailwindTheme` document
with no header, the multi-group round trip through `CSSColorParser`, `p3WithFallback`
covering every group in both blocks, and the Name-field claim above; `StagedProjectTests`
in `ExportStoreTests.swift` covers the store side, including the empty-field survival
above. **Six mutations, all six caught by the intended test and no other**: uniquing
against the raw name instead of `cssIdentifier(name)` fails `collidingGroupNamesStaySeparate`;
deleting the suffix loop's `while` (always appending a bare `-2`) fails only
`thirdCollisionSkipsTakenSuffix`, not the simpler two-way collision test – proof the loop
itself is exercised, not just the branch that enters it; truncating `p3WithFallback`'s
wide block to the first group fails `p3WithFallbackCoversEveryGroup`; forcing
`groupedPropertyLines`'s header unconditionally fails three tests in the pre-existing
suite (`customProperties` and `p3WithFallback`) and none in the new one, and needed a
dedicated single-group `tailwindTheme` test before it had anywhere to fail for that
shape; and both directions of `declaration`'s own separate header guard were checked –
always off fails only the new two-group test, always on fails both pre-existing
single-group ones. `ProjectsSmokeTests` adds an end-to-end run – a ramp and a loose
color, saved separately, exported together under the project's own groups – **and
asserts the Source picker's "Project" segment itself is hittable**, not merely that the
right document ended up in the field. That distinction mattered: the existing
`ExportSmokeTests` only ever click "Export" and "Ramp", so they would pass identically
whether or not a sixth segment rendered usably, and the new test's own first pass reached
the document through `store.stage(project:)` programmatically without ever touching the
control it was meant to prove.

### ✅ M21 – Every swatch is a live handle

`ColorSwatch` (`DesignSystem/ColorSwatch.swift`) stays exactly what it is: a dumb
rectangle with no gesture and no accessibility of its own. Add a sibling in the same
file:

```swift
struct SwatchButton: View   // ColorSwatch wrapped in a Button, plus a11y and a menu
```

- Two initializers, because there are two kinds of color on screen and merging them
  destroys a spelling – the same doctrine as the three `savePalette` overloads. One takes
  a `ColorValue` and adopts it via `store.adopt(_:preferring:)` (a derived color: a
  harmony member, a CVD simulation, a mix). The other takes a color **and its authored
  text** and assigns that text directly (a recent, a saved color) so a stored
  `rebeccapurple` does not come back `#663399`.
- `.accessibilityLabel` carrying the CSS string, and an `.accessibilityIdentifier` the
  caller supplies. A colored rectangle says nothing to VoiceOver *or* to XCUITest, and a
  panel that emitted one color three times would otherwise pass.
- A context menu: **Use as color** (the default tap), **Use as background** (writes
  `store.backgroundText` – the contrast panel needs this and a click alone cannot express
  it), **Copy**.
- Calls `store.remember()`, matching `TransformPanel.apply(_:)` (`:717`).

**The accessibility trap this must not walk into:** a SwiftUI `Button` is one
accessibility element, so anything layered over it disappears from the tree *and* makes
the Button's identifier match twice – which is what broke unrelated tests when
`ProjectsPanel`'s selection badge was an overlay (see the note at
`ProjectsPanel.swift:358`). `SwatchButton` therefore documents that decorative chrome
goes **inside** the label and interactive siblings go in a `ZStack`, never in
`.overlay` – the same rule M21 restates that CLAUDE.md already carries generally.

**Call sites to convert** (from the survey; `MenuBarPanel:134`, `TransformPanel:642` and
`ProjectsPanel:370` are already buttons and fold into the new component):

| File                                      | Site                                    | Adopts                                                 |
| ----------------------------------------- | --------------------------------------- | ------------------------------------------------------ |
| `Features/Shell/MenuBarPanel.swift`       | `:59` current, `:134` recents           | text                                                   |
| `Features/Contrast/ContrastPanel.swift`   | `:53` preview                           | value; menu's "Use as background" earns its place here |
| `Features/CVD/CVDPanel.swift`             | `:117`, `:119`, `:160`, `:178`          | value – the **simulated** color for simulated swatches |
| `Features/Transform/TransformPanel.swift` | `:322`, `:413`, `:642`, `:675`          | value, `preferring: .oklch` (transforms return OKLCH)  |
| `Features/Export/ExportPanel.swift`       | `:232`                                  | value                                                  |
| `Features/Projects/ProjectsPanel.swift`   | `:370` saved color, `:503` palette tile | text / value                                           |

Two deliberate exclusions, both worth stating rather than leaving as gaps:
`ColorInputField`'s header swatch (`:71`) becomes the popover trigger in M24 instead, and
**`ConversionPanel` has no swatches at all** – its rows are text, already clickable, and
already copy. Adding a swatch per row is a visual change M25 subsumes.

**Testing.** `TransformSmokeTests` already asserts swatch accessibility labels and is the
pattern. Add UI coverage that clicking a CVD simulated swatch and a palette tile changes
the field. Unit-test the "authored text survives" claim on the store side, since that is
the half a rendered test cannot see.

Built as planned – `SwatchButton` in `DesignSystem/ColorSwatch.swift`, two initializers,
one adopt path, one context menu – with two things measured against the running app that
the plan had no way to anticipate from reading the source, and one deliberate deviation
from the call-site table.

**A `.contextMenu` on a `Button`'s ancestor is shadowed, not merged, by one on the
`Button` itself – measured, not guessed.** The first cut of `ProjectsPanel.savedColorTile`
left its existing five-item menu (Select/Deselect, Move Left/Right, Notes…, Delete) on the
outer `ZStack`, one level above the `Button` `SwatchButton` now owns, on the theory that an
ancestor's `.contextMenu` would still fire the way it had before the button inside it grew
one of its own. `testMoveCommandsReorderTheGrid` and `testAReorderSurvivesLeavingThePanel`
both failed against the real app with "No item Move Left on savedColor-0" – the ancestor's
menu never appeared at all. `SwatchButton` therefore takes a `menuExtras` builder appended
after its own three items, and `savedColorTile`'s five move there as a `@ViewBuilder`
helper shared by its readable and unreadable-row branches.

**`menuExtras` had to become a generic parameter, not an `AnyView`-erased closure – also
measured.** The first attempt at the hook above type-erased the extras with `AnyView` so
`SwatchButton` itself could stay a plain, non-generic `View`. It compiled cleanly and
still failed the same two tests, with the menu now showing exactly the built-in three
items and none of the five extras – `.contextMenu` walks the literal `@ViewBuilder` result
to build native `NSMenuItem`s, and erasing that result to `AnyView` defeats the walk.
`SwatchButton<MenuExtras: View>` fixed it; a `where MenuExtras == EmptyView` extension
supplies the two three-parameter initializers every other call site uses unchanged, so
nothing about the fourteen non-`ProjectsPanel` sites had to know the type ever changed.

**One deliberate deviation from the call-site table:** `ContrastPanel`'s background swatch
and `TransformPanel`'s two background chips (mix and solver) are wired to the *text*
initializer, not `value` as sketched. All three render `store.backgroundText`, which has
an authored spelling of its own sitting right there – wiring them to `adopt` instead would
have meant "Use as color" or "Copy" on the background's own swatch silently canonicalizing
a typed `rebeccapurple` to `#663399`, on the same field, from a menu whose other two items
do nothing to it. That is exactly the loss the text-is-truth doctrine exists to prevent
everywhere else in this app; the table's "value" reads as shorthand for "adopts a color"
rather than a considered choice between the two initializers on these three sites
specifically, the same way `:53`'s "preview" turned out to name the background swatch
rather than the text-sample box beside it.

**The `onAdopt` hook exists because of a correctness question the plan's table did not
raise.** `TransformPanel.labeledSwatch` backs three swatches – Adjust's "Now" and
"Adjusted", and Mix's "Mixed" – and two of those three show a *pending, relative* result
that `apply(_:)`'s own reset exists to stop from compounding. Wiring them to
`SwatchButton`'s bare adopt-and-remember would let two clicks on "Adjusted" apply the same
lightness delta twice, since nothing would clear `adjustment`/`curve` between them – the
exact bug the reset in `apply(_:)` was written to prevent, reachable through a second
control that does not call it. `onAdopt` runs the same clearing closure `apply(_:)` uses,
scoped to what each section actually holds pending (`adjustment`/`curve` for Adjust,
`mixAmount` for Mix); `TransformPanel.swatchRow`'s harmony/ramp/mix-strip swatches pass no
closure at all, since nothing pending is theirs to clear.

**The palette-row swatch conversion is a real behavior change the plan called for and
CLAUDE.md's pre-M21 testing notes had to catch up to.** `ProjectsPanel.paletteRow` used to
be the one swatch in the app that was not a button and was not labelled by its color –
`app.otherElements[…]`, label = the entry's key – documented as a deliberate distinction
from a saved color's `app.buttons[…]`/CSS pairing. `SwatchButton`'s accessibility label is
always CSS, with no per-call override, for the same reason `TransformPanel.swatchRow`
already relied on: a palette that silently repeated a color needs to fail a distinctness
check, and a label reading the key could not do that. The key did not just disappear –
it moved to a caption underneath each swatch, the same shape `ExportPanel.swatches` and
`savedColorTile` already use – but the three tests built around the old convention
(`testASavedRampExportsUnderItsOwnName`, `testExportProjectCombinesEveryPaletteAndLooseColor`,
`testSavingASelectionMakesAPalette`) needed updating to `app.buttons[…]` and, for the last
one, to assert CSS in slot order instead of keys – which is strictly stronger, since it now
also proves the colors themselves are right rather than only their names. The CLAUDE.md
paragraph documenting the old convention is rewritten alongside this entry.

**Testing.** `SwatchButtonTests` were not needed as a separate unit suite – nothing in the
component is reachable without a rendered `Button`, and `ColorStoreTests` already covers
the store-side seams it calls: `usingARecentRestoresItsText` is the "authored text
survives" claim the plan asked for (`store.use(_:)`, unchanged by this milestone), and the
new `adoptBackgroundWritesBackground` covers `ColorStore.adoptBackground(_:preferring:)`,
added for "Use as background" on a derived color. New UI coverage:
`CVDSmokeTests.testClickingTheSimulatedSwatchAdoptsIt` and an extension to
`ProjectsSmokeTests.testSavingASelectionMakesAPalette` that moves the field away and clicks
a palette swatch back, both against the specific claim the plan named. 443 unit tests, 59
CLI tests, and all 33 XCUITests (two panel-menu regressions caught and fixed against the
running app before either shipped, as recorded above) pass.

### ✅ M22 – Web-friendly mode

A single `store.webFriendly` flag (M19) with two halves: **hide formats**, and
**recalibrate values into sRGB**. No errors, no disabled controls, no negative feedback –
the "hide rather than disable" precedent is already established and documented twice
(`ExportShape.usesFormat`, `ExportPanel.swift:122`).

**The format table is transcribed, not derived.** Add to
`ColorCore/Format/FormatCatalog.swift`, beside `catalog`:

```swift
static let webFriendly: [CSSOutputFormat] = [
  .hex, .keyword, .rgb, .hsl, .hwb, .oklch, .oklab, .lch, .lab,
]
```

A table rather than a predicate, for the reason `componentRoles` and `channelKeywords`
are tables: the criterion is a judgment about gamut and authoring practice that the enum
does not carry. **`color(srgb …)` is the discriminating case** – it is fully inside
sRGB, so any gamut-derived rule would include it, and it is excluded anyway because the
mode hides the `color()` family and nobody hand-authors that spelling. A derived
`if case .color` rule would give the same answer today by accident and the wrong answer
the moment a bounded non-`color()` format is added.

**Three enumeration paths need the filter.** The survey found exactly three, and each
must be handled or the mode leaks:

1. **`FormatSection.all`** (`Features/Conversion/FormatPresentation.swift:46`) – feeds
   both `ConversionPanel` and `MenuBarPanel`'s copy menu. Needs a filtered variant that
   **drops sections left empty**, since Wide gamut loses all four entries and Exact loses
   all four. An empty section header is exactly the "negative feedback" the mode is meant
   to avoid.
2. **`CSSOutputFormat.exportable`** (`ColorCore/Export/ColorExport.swift:77`) – the export
   panel's Format picker.
3. **`ColorSpace.allCases`** (`Features/Transform/TransformPanel.swift:277`) – the mix
   interpolation-space picker.

Also hide **`ExportShape.p3WithFallback`** from the shape picker: it is a wide-gamut
shape by definition. Its `wideFormat` is `.color(.displayP3)`, so leaving it live would
put a wide-gamut block in a document the mode promised would not contain one.

**A tool that cannot stay in sRGB is hidden, not half-restricted.** The rule that
decides every case below: if a tool's output can be pulled into sRGB honestly, it is
recalibrated; if it cannot, the tool is **hidden**, exactly as an unreachable format is.
Half-restricting a tool that can still emit a wide value would leave mixed formats in the
output and defeat the mode.

Checked against every color-producing tool, **mixing is the only one that has to go**:

| Tool                         | Under web-friendly                                                 |
| ---------------------------- | ------------------------------------------------------------------ |
| Harmony                      | Recalibrated – `HarmonyOptions.gamut = .srgb`                      |
| Shade ramp                   | Already `.srgb` by default; nothing to do                          |
| Adjustment / lightness curve | Recalibrated – same optional gamut                                 |
| Contrast solver              | Recalibrated – clamp on the returned color                         |
| Picker                       | Recalibrated – plane and cursor clamped to the sRGB edge           |
| CVD simulation               | Already `convertedAndMapped(to: .srgb)` (`CVDSimulation.swift:80`) |
| **`color-mix()`**            | **Hidden**                                                         |

**Why mixing cannot be recalibrated**, in the order the reasons bite:

1. CSS Color 4 §12 has **no gamut-mapping step**, so clamping a mix would make this app
   disagree with browsers about `color-mix()` – the explicit reason the mix fixture
   generator skips out-of-gamut endpoints in the first place.
2. Restricting the *interpolation space* to the sRGB family does not rescue it either.
   That would guarantee an in-gamut result only for in-gamut endpoints, and under
   web-friendly the field must still **accept** a typed `oklch(0.9 0.3 140)` – the mode
   hides things, it does not reject input. So an endpoint can be outside sRGB and no
   choice of space contains it.

**Concretely:** M15 folded mixing into `TransformPanel` as a fifth section, not a
separate tool, so hiding it means hiding that section – the interpolation-space picker
(`TransformPanel.swift:277`), the hue-method picker, the amount slider, the result
swatch (`:322`) and its "Use it" button. `store.mixSpace` and `mixHueMethod` stay on the
store untouched, so turning the mode off restores exactly the setup you left.

**The parser is unaffected, and deliberately so.** `color-mix(…)` typed or pasted into
the field still parses, because the mode disables non-web-friendly *output* while still
allowing import from those formats. Same for `rgb(from …)` and `calc()`. The CLI needs
no change: it has no web-friendly mode, and `theParserIsTheMixCommand` already pins that
it has no `mix` command to hide.

`FormatSectionTests` (44 lines) currently asserts the four sections partition the
catalog exactly. **Keep that assertion on the unfiltered list** and add a counterpart
requiring that the filtered sections partition `webFriendly` and contain no empty
section.

**Recalibrating values – where, and where deliberately not.** Do not touch
`ColorValue.derivedOKLCH(_:)` (`Transform/Adjustment.swift:70`). It is the narrowest
seam – Adjustment, Harmony, ShadeRamp, ContrastSolver and LightnessCurve all funnel
through it – which is exactly why changing it would silently break the rule "harmonies
are never gamut-mapped", a rule with tests pinning it in both directions. Constrain at
the option structs instead, defaulting to today's behaviour:

- **Extract one clamp.** `ShadeRamp` already pulls a stop in with
  `GamutBoundary.maxChroma` under an `inGamut` guard (`ShadeRamp.swift:120`), and that
  guard is a correctness rule, not an optimization – clamping unconditionally moves the
  base off itself, and an unbounded gamut returns `.infinity`. Lift it into one
  `ColorValue.pulledInto(_ gamut: ColorSpace)` in `Convert/GamutBoundary.swift` and have
  `ShadeRamp` call it too, so there is one implementation.
- **`HarmonyOptions` gains `gamut: ColorSpace?`**, nil by default. Set to `.srgb` under
  web-friendly. Existing tests, which assert a rotated hue leaves sRGB, keep passing on
  the default.
- **`ContrastSolver`** gains the same optional clamp on its returned color. Its search is
  already on sRGB relative luminance, so this only constrains the answer, not the maths.
  The `solve` self-check still applies – the solver keeps its bracket's passing end.
- **`ColorInterpolation` is not touched at all**, because the mix section is hidden
  rather than restricted – see the table above. The arithmetic stays exactly as CSS
  Color 4 §12 has it, which is what keeps this app agreeing with browsers about
  `color-mix()`.
- **The picker.** `PickerPlane` already computes `srgbEdge` alongside `displayEdge`
  (`:167-170`) and `PickerPanel` already strokes both. Under web-friendly, render the
  plane against the sRGB edge and clamp the cursor's chroma to
  `GamutBoundary.maxChroma(…, in: .srgb)`. The "sRGB allows 0.xxxx here" readout and the
  "Outside sRGB" badge (`PickerPanel.swift:338-359`) become unreachable rather than
  wrong – hide them.

**The subtle one: `spelling(preferring:)`.** `ColorValue.spelling(preferring:)`
(`FormatCatalog.swift:108`) **promotes** a format to `color(display-p3 …)` whenever the
preferred one would gamut-map. It fires on `ColorStore.adopt`, `sampleFromScreen`,
`PickerState.cssToWrite()` and `TransformPanel`'s adopt – four paths that would each
quietly write a wide-gamut string into the field while the mode claims to be sRGB-only.
A screen sample off a P3 display is the everyday case.

Add `spelling(preferring:allowingWideGamut:)`, defaulting to `true` so nothing else
changes, and pass `!webFriendly` from `ColorStore.adopt` and `PickerState.cssToWrite()`.
When wide gamut is disallowed the color is mapped into sRGB on the way in – which is the
mode's whole promise, and it must be stated here that this is *lossy on purpose*.

**Testing.** `webFriendly` is a subset of `catalog` and every member is
in-sRGB-expressible. Each of the three enumeration sites returns only web-friendly
entries when the flag is set, and `p3WithFallback` is absent from the shape list.
Harmonies with `gamut: .srgb` produce only in-gamut members while the default still
escapes – **assert the disagreement**, since that is the claim, and the existing test
that a constant-chroma ramp really does leave the gamut is the model for it. `adopt` of a
P3 sample under the flag writes a string that re-parses inside sRGB. UI: the mix section
is absent under the flag and returns when it is cleared, with `store.mixSpace` unchanged
across the round trip. **Manual check, recorded for when this ships:** the mode on a P3
display – sample a wide color off-screen and confirm the field receives an sRGB
spelling, not a promoted `color(display-p3 …)`.

**Mutations to confirm:** derive `webFriendly` from `if case .color` instead of the table
(the `color(srgb …)` test must fail); drop the `spelling(preferring:)` change (the adopt
test must fail); restrict the mix space picker instead of hiding the section, then mix
from a typed out-of-gamut endpoint (the result must still escape sRGB – this is the
mutation that proves hiding was necessary rather than cautious).

Built as planned, plus four things the plan's own text did not settle and one gap it
could not have anticipated:

**The plan contradicts itself about `ColorSpace.allCases`, and the later text wins.**
The "three enumeration paths" survey names `TransformPanel.swift:277` – the mix
interpolation-space picker – as needing the `webFriendly` filter, and the very next
section says mixing is **hidden, not restricted**, naming a mutation
("restrict the mix space picker instead of hiding the section") as proof filtering
there is the wrong call. Filtering the picker while the section is hidden would also be
dead code no test could distinguish from doing nothing. Resolved in favor of the later,
mutation-tested text: `ColorSpace.allCases` is untouched, and the whole mix section is
wrapped in `if !store.webFriendly`.

**`ContrastSolver`'s clamp has to sit inside the bisection, not on its answer.** The
plan says "the same optional clamp on its returned color," which reads as clamping
after the search. That is unsound: pulling chroma in changes
`wcagRelativeLuminance`, so a color clamped only at the end could fall back under the
target the unclamped search thought it had reached – silently breaking the invariant
the solver exists to guarantee, that the returned color provably `meets` the
requirement. `solutions(for:on:target:resolution:gamut:)` instead clamps inside
`luminance(at:)` and builds the returned `solved` color through the identical
`candidate(at:)` closure, so the color the bisection measures at every step is the
color it hands back.
`gamutClampedSolutionsStillMeetTheTarget` is built specifically to catch a regression
to the after-the-fact version: it solves for a chroma (`0.35`) that fits nowhere in
sRGB, so an end-clamp would corrupt the ratio at every candidate lightness.

**Declining the `color(display-p3 …)` promotion does not by itself keep a value inside
sRGB, and the plan's wording ("the color is mapped into sRGB on the way in") undersold
what that takes.** `oklch()` is unbounded and `.lossless` does not gamut-map, so
`adopt`ing a wide sample and merely asking `spelling(preferring: .oklch,
allowingWideGamut: false)` would still write the wide `oklch()` string – the promotion
guard alone stops the *format* from becoming `color()`, not the *value* from leaving
sRGB. `ColorStore.adopt`/`adoptBackground` therefore call `ColorValue.pulledInto(.srgb)`
before asking for a spelling at all; `allowingWideGamut` is what stops that
already-safe color being promoted back out, not what does the clamping.
`adoptClampsWideGamutUnderWebFriendly` is parameterized over both `.hex` and `.oklch`
specifically because the `.hex` path alone cannot tell the two mechanisms apart – hex
`cannotRepresentOutOfGamut`, so it maps regardless of the flag, and only the unbounded
`.oklch` path proves the pre-clamp is doing the work.

**M19 landed after this plan was written, and persisted export preferences are a gap
neither text anticipated.** `ExportOptions.shape` and `.format` persist across a
launch (M19), so web-friendly mode can be turned on with `p3WithFallback` or a
`color()` format already chosen from an earlier session – hiding those choices from
the picker does not touch the stored value underneath it.
`ExportOptions.effective(webFriendly:)` computes a safe substitute (never mutating the
stored preference, so turning the mode back off restores exactly what was chosen
before – the same promise `mixSpace`/`mixHueMethod` keep) and
`ColorStore.exportDocument`/`exportGamutMappedCount` read it instead of `exportOptions`
directly. `exportDocumentNeverEscapesUnderWebFriendly` pins the document side of this
without ever touching `store.exportOptions.shape`, which is the point – a test that
set the shape back to something safe first would not catch the bug this exists for.

**`HarmonyOptions.gamut` and `ContrastSolver`'s `gamut:` parameter are read from one
computed property, `ColorStore.effectiveHarmonyOptions`, by both `TransformPanel`'s
preview and `entries(for: .harmony)`'s export path** – the same one-seam rule
`ExportOptions.mappedCountFormat` already follows, so a harmony's swatches and its
exported values cannot come to disagree about whether a member left the gamut.

**Testing.** `pulledInto(_:)` gained its own suite in `GamutBoundaryTests` (already
fitting is untouched, out-of-gamut reaches the boundary at the same lightness and hue,
an unbounded gamut is a no-op); `HarmonyTests.gamutOptionPullsMemberIn` re-uses
`harmoniesAreNotGamutMapped`'s exact base color so the two cannot silently agree by
testing different inputs; `ContrastSolverTests` gained a "Web-friendly mode" section
built around a chroma no lightness can hold in sRGB; `FormatCatalogTests` and
`FormatSectionTests` cover the table, the exclusion of `color(srgb …)`, and the
promotion guard; `ExportTests` and `ExportStoreTests` cover `effective(webFriendly:)`
at both the pure-value and the live-store level; `ColorStoreTests` and
`PickerStateTests` cover the adopt/picker clamp paths. One UI test,
`WebFriendlyModeSmokeTests`, confirms the mix section is actually absent in the
running app – launched with a new bare argument, `UITestWebFriendly`, read once in
`ColorKitApp`, because nothing in the app wires an accessibility identifier to
the Settings scene's Toggle and no UI test anywhere drives that window yet.
**The live round trip — flip the Toggle in Settings and watch the mix section and the
conversion panel's sections react, on a P3 display sampling a wide color and watching
the field receive an sRGB spelling — is a recorded manual check**, the same way the
file panels are; an agent cannot drive `NSOpenPanel`/`NSSavePanel` or a second scene's
window from here and should say so rather than infer it from a green suite. 473 unit
tests (443 before M22, 30 new), 59 CLI tests, and the full XCUITest suite (33 before
M22, plus `WebFriendlyModeSmokeTests`) pass.

### ✅ M23 – Recents row, and committing a pick on release

Two small changes that share a subject.

**The row.** New `Features/Shell/RecentsRow.swift`, placed in `ContentView`'s `VStack`
between `ColorInputField` and the tool `Picker` – above the switcher, because a recent
belongs to no tool, the same argument the input field itself sits on. Gated on
`store.showsRecents` (M19). Built from `SwatchButton`'s authored-text initializer (M21)
so clicking a recent returns *your* spelling, which is what `RecentColor.text` exists
for. A "Clear" affordance matching `MenuBarPanel:115`.

`recentLimit` becomes settings-backed (M19). Default stays 12 – "10 or so", and the menu
bar's 6-column grid divides evenly into it.

**Commit on release.** `PickerPanel.rememberWhenSettled()` (`:512-519`) is a 1-second
debounce shared by the plane, hue strip and alpha strip. Replace it with
`store.remember()` directly in each of the three `onEnded` handlers (`:173`, `:225`,
`:276`) and delete `rememberSoon`. This is what was asked for and it is also strictly
better than the debounce, which drops the first of two picks made within a second of
each other. `remember()` already dedupes by exact `ColorValue`, so a click that does not
move the cursor files one entry, not two.

**Testing.** Unit: `recentLimit` is honoured when lowered, and lowering it truncates an
already-full list. UI: `PickerSmokeTests` needs a look – anything timing-coupled to the
old debounce goes. A UI test that a recent appears in the window's row after a submit,
and that clicking it restores the authored spelling (the store-side half is already
covered by `ColorStoreTests`).

Built as planned, with two things the plan note above did not spell out.

**The row is gated on `showsRecents` alone, never additionally on `recents` being
non-empty.** The plan cited `MenuBarPanel:115`'s "Clear" affordance as the pattern to
match but did not say whether to match its always-rendered shape too. Read literally,
"a recent appears in the window's row after a submit" is equally true of a row that
materializes on the first remembered color – but that row would push the tool switcher
and every panel beneath it down a frame *after* the click that filled it, and this app
already has a scar at exactly this shape (`GeometryReader` inside a `ScrollView`
resizing out from under a click in flight, in the findings above). `RecentsRow`
therefore always renders once the preference is on, with
`MenuBarPanel`'s own empty-state line, `"Colors you copy or submit collect here."`, in
place of swatches – fixed footprint, and one fewer thing for this codebase's
short list of layout-shift bugs to grow by one.

**`recentLimit` needed a `didSet`, which the plan's prose implied without naming.**
Before this milestone the property was a plain `var`, so lowering it in Settings did
nothing until the next `remember()` happened to trim the list – "lowering it truncates
an already-full list" was the *test* the plan wrote in advance, and it fails against
that code, which is what confirmed the gap was real rather than already covered.
`recents.removeLast(recents.count - recentLimit)` moved into one private
`trimRecents()`, called from both the `didSet` and `remember()`, so the truncation rule
exists in exactly one place. `trimRecents()` clamps with `max(recentLimit, 0)` before
computing the count to remove – a `didSet` fires for *any* assignment to the property,
including one that reaches it directly rather than through `preferences`'s own
`max(1, …)` clamp, and without the second clamp a negative limit would ask
`removeLast` for more elements than the array holds and crash at the point of
assignment instead of at the next `remember()`. Property observers on an `@Observable`
stored property are also a sharper edge than they look – the macro rewrites stored
properties into accessor pairs, and the failure mode is not always a compile error;
it can be the property silently dropping out of observation. Confirmed both ways:
the app target builds, and `PreferencesTests.preferencesObservesEveryPersistedField`
gained a fourth mutation, `("recentLimit", { $0.recentLimit = 3 })`, to prove a change
still invalidates a read of `store.preferences`.

**Commit-on-release turns one settled pick into up to three recents, not one.** The
plan's "`remember()` already dedupes … a click that does not move the cursor files one
entry, not two" is true and stayed true, but only covers the no-move case. Dialing in
one color across the plane, then the hue strip, then the alpha slider now files three
distinct entries on the way there, because each release genuinely does leave a
different `ColorValue` behind – the exact-value dedupe has nothing to collapse until
the *last* release repeats what came before. That is the correct trade the plan asked
for (never dropping the first of two deliberate picks made close together), and it is
recorded here rather than left implicit, per this file's own standard for a decision
that reads as obvious and is not.

**`testReleasingTheDragFilesARecentWithoutTheOldDebounceDelay`, in `PickerSmokeTests`,
is a timing assertion, and it earns that risk rather than merely accepting it.** It
waits at most 0.6s after a plane release for a `recentColor-*` button to exist –
tight enough that the deleted 1-second debounce cannot pass it by accident, wide
enough for an ordinary SwiftUI render pass. Confirmed to actually discriminate the
two, not just read like it does: reintroducing a 1-second `Task.sleep` before
`store.remember()` in `planeView`'s `onEnded` and re-running only this test fails it
– `PickerSmokeTests` was otherwise clean beforehand, so this is the one case that
needed the debounce gone to pass.

**Testing, final.** One new `ColorStoreTests` case (truncation-on-lower) plus a fourth
mutation added to `PreferencesTests`'s existing observation test; one new UI test
file, `RecentsSmokeTests` (submit-then-click restores authored text; Clear empties the
row and hides itself), plus one new case in the existing `PickerSmokeTests`. Both new
regression tests were confirmed to fail against the unfixed code before the fix
landed: the truncation unit test against the plain `var`, the picker UI test against
a reintroduced debounce. 474 unit tests (473 before M23, 1 new), 59 CLI tests
unchanged, and the full XCUITest suite (34 before M23, 37 after) all pass in one
`** TEST SUCCEEDED **` run.

### ✅ M24 – A popover picker on the header swatch

`ColorInputField.swatch` (`:68-81`) becomes a `Button` presenting a `.popover`. The
dashed empty-state rectangle becomes a button too – with no color yet, opening the
picker is the single most useful thing that swatch could do.

**Share the controls; do not clone them.** `PickerPanel` currently renders the plane
(`:146-164`), hue strip (`:196-211`) and alpha strip (`:252-267`) inline. Extract the
three into their own small views in `Features/Picker/` and have both `PickerPanel` and a
new `CompactPicker` compose them. Two implementations of a gamut-clamped chroma axis
would drift, and M22 gives them a second reason to.

The popover owns its own `PickerState`, seeded from the store on appear and using the
same `lastWritten` loopback guard (`PickerState.syncing(with:color:)`, `:184`) – the
picker must ignore its own writes or every drag tick re-seeds it. It writes through
`store.inputText` on change and calls `store.remember()` on drag end, per M23.

The header swatch Button's label stays the swatch itself; the popover is a modifier, not
an overlay – M21's accessibility rule applies here too.

**Testing.** UI: the header swatch is hittable, opening it reveals `pickerPlane`, and
dragging changes `colorInput`. Wait on **hittability**, not existence – a popover
resizes nothing but the panel behind it can still move. Unit coverage stays on
`PickerState` (`PickerStateTests`, 263 lines), which is where the arithmetic is.

Built as planned, with four things the plan note above did not spell out.

**The popover's plane, hue strip and alpha slider carry their own identifier,
distinct from `PickerPanel`'s, rather than reusing `pickerPlane` / `pickerHue` /
`pickerAlpha` as the plan's own testing note implies.** The header swatch sits above
the tool switcher (`ContentView`), so nothing stops opening the popover while already
on the Pick tab – a scenario the plan's testing note does not mention and the running
app makes trivially reachable. Two elements sharing one accessibility identifier there
would be an ambiguous XCUITest query with no tree to read, exactly the hazard CLAUDE.md's
"never write a fallback chain of XCUITest queries" note exists to keep out of this
codebase. So each of `PickerPlaneView`, `PickerHueStripView` and `PickerAlphaSliderView`
takes an `identifier` parameter, defaulted to `PickerPanel`'s pre-M24 strings so every
existing test keeps passing unchanged; `CompactPicker` passes `"compactPickerPlane"`,
`"compactPickerHue"`, `"compactPickerAlpha"` and `"compactPickerMode"`.
`CompactPickerSmokeTests.testThePlaneAndItsPopoverCopyCanBothBeOnScreenAtOnce` opens the
Pick tab first and then the popover specifically to exercise the collision this avoids –
opening the popover from the default Convert tab, which the plan's own phrasing suggests,
would never have reached it, since `PickerPanel` is not mounted there.

**Rendering lives inside each of the three shared views, not in whichever host embeds
them.** `PickerPanel` and `CompactPicker` each hold their own `PickerState`, so each
needs its own rendered bitmap; hoisting the `.task(id:)` render loop up to the two hosts
would only relocate the duplication the plan asks to remove, not delete it. Each view
owns its own `@State` image cache and cancels the render it replaces, exactly as
`PickerPanel` did before the extraction.

**The M22 web-friendly clamp moved onto `PickerState` itself, as
`committing(_:in:)`, and that turned it from a recorded manual check into a unit test.**
It was private to `PickerPanel.apply(_:)` before M24, reachable only through a running
app. `committing` **returns** the text to write rather than assigning `store.inputText`
from inside its own body – every real caller reaches `self` through a `@Binding`, and
writing the store ahead of the binding's own write-back would leave `lastWritten` stale
in the source of truth at the exact moment the store's observers fire. Two new
`PickerStateTests` cover the clamp on and the clamp off; the first was confirmed to fail
against the clamp removed (`state.chroma → 0.35`, not clamped).

**The `@Binding` write-ordering argument above is a reasoned justification for
`committing`'s calling convention, not a claim any unit test pins, and a third
`PickerStateTests` case was written first as if it were one before that held up under
its own scrutiny.** `committingRoundTripsThroughTheStoreWithoutMisreadingItsOwnWrite`
(named `committingOrdersItsOwnWriteBeforeTheStores` in an earlier draft) calls
`committing` on a plain local `var`, which has no `@Binding` indirection to race –
`self` mutates in place with no copy-back step, so no ordering bug inside `committing`
could make that particular assertion fail either way, whatever the method's internal
implementation. What the test *does* pin, honestly: a committed change round-trips
through the store without `syncing(with:color:)` misreading it as an outside edit,
which is real and worth keeping. Caught on the advisor's second pass, not the first –
recorded per this file's own rule about a mutation that survives being a finding to
chase rather than a rule to trust.

**`PickerPlaneView`'s side became an explicit `.frame(width:height:)`, not a byte-for-byte
preservation of the implicit leftover-`HStack`-space layout — and this section's own
framing of that as settled turned out to be the thing that needed correcting, not the
layout.** The pre-M24 plane had no `.frame(width:)` of its own; `squareSide(forPanelWidth:)`
caps its result at `460` and that value was only ever applied to the row's *height*, so
above roughly 532pt of panel width the square was silently a rectangle. M24 closed that
by giving the plane the same value as its width too, called it "a considered behavior
change … not a side effect that should be found later in a screenshot," and shipped it
for both hosts unconditionally. **It was found later anyway, by the person who had
configured the fluid layout on purpose**: a wide `PickerPanel` filling its container
reads better than a fixed square beside empty space, which is exactly the shape M24
removed. `PickerPlaneView` gained `fillsAvailableWidth` (default `false`) as the
correction – `true` for `PickerPanel` restores the pre-M24 fluid width via
`.frame(width: nil, height: side)`, `CompactPicker`'s popover keeps the fixed square
since it has no container to fill. The lesson kept for next time: a layout fix that
closes one edge case (the >532pt rectangle) can still ship the wrong default shape for
the common case, and "closes a gap" is not the same claim as "is what was wanted" –
worth checking against a screenshot, or in this case, against the person who asked.

**One thing not in the plan at all: the dashed empty-state swatch, once it became a
`Button`, needed `.contentShape(RoundedRectangle(...))` to be clickable in the middle.**
`RoundedRectangle.strokeBorder` with no fill hit-tests only its 1pt outline, so a click
dead center on the 58×58 square would land on nothing without it – the filled
`ColorSwatch` case needs no such fix, since its `Rectangle().fill(...)` already gives
SwiftUI a shape to hit-test. Confirmed by mutation: removing the modifier fails
`CompactPickerSmokeTests.testTheEmptyStateSwatchOpensThePopoverToo` and nothing else.

**`CompactPicker`'s "seeded from the store on appear" claim was checked, not assumed –
and the check found the underlying platform behavior more forgiving than the code
defends against.** `ColorInputField` gives the popover's content a fresh view identity
on every open (`.id(pickerSession)`) rather than trusting `.popover` to discard its
content's `@State` on dismiss, since `.popover` documents no such guarantee. Measured
with `.id(pickerSession)` removed: `testReopeningThePopoverSeedsFromWhateverIsInTheFieldNow`
passes identically, because macOS already tears the content view down on close, `@State`
included, so `.task { seedFromStore() }` re-runs on every open regardless. `.id(_:)`
stays in as insurance against a future OS where that stops being true, and the test's
own doc comment says plainly that nothing here can discriminate it – the same honesty
the write-ordering finding above asked for.

**A fifth finding, and the one with the widest blast radius: the Pick tab and the
popover are two independent hosts sharing one preference, `store.pickerMode`, and
only one direction of that sharing worked.** Each host's own mode switcher wrote
`store.pickerMode` *and* its own local `PickerState.mode` together, so the two agreed
as long as only one of them ever changed the preference – true for the whole app
before M24, and false from the moment a second writer (`CompactPicker`) existed.
Switching axes in the popover while the Pick tab was already showing changed
`store.pickerMode` but left `PickerPanel`'s own `state.mode` frozen – its switcher, its
plane, its readout all showing the stale mode until the tool was left and re-entered.
Fixed with `.onChange(of: store.pickerMode)` on both hosts, each re-running
`state.setMode(store.pickerMode, carrying: store.color)` – safe to fire on a host's own
write too, since `setMode` no-ops when the mode already matches. Confirmed by mutation:
removing `PickerPanel`'s `onChange` fails
`CompactPickerSmokeTests.testSwitchingAxesInThePopoverKeepsThePickTabInSync`.
**The mirror-image test does not exist, and not for lack of trying.**
`testSwitchingAxesOnThePickTabKeepsTheOpenPopoverInSync` was written, and failed
consistently and reproducibly – not with a mismatched value, but with every element in
the window behind the popover reporting `isHittable == false` and the whole
`Application`/`Window` subtree reading `Disabled`, confirmed against an
otherwise-identical, passing test that interacts *inside* the popover instead. A
transient `.popover` holds key-window status while shown, so the window behind it is
not interactable from outside – the same shape of platform limitation as XCUITest's
inability to drive `NSOpenPanel` or a drag session, and the test was deleted rather
than kept red, per the standing rule against a test that fails whether the feature
works or not. `CompactPicker`'s own `.onChange(of: store.pickerMode)` stays in anyway,
as parity with `PickerPanel`'s reachable side and against any future writer of the
preference this popover cannot anticipate – see the code comment for why it is likely
unreachable via this exact path today.

**Testing, final.** Two new `PickerStateTests` cases pin the clamp (on and off); a third
was rewritten mid-milestone once its original claim did not survive scrutiny – see
above. One new UI file, `CompactPickerSmokeTests`, five cases: the popover opens and a
drag inside it reaches the field; the plane and its popover copy coexist without an
ambiguous query; the empty-state swatch is clickable; reopening the popover reseeds
from whatever is currently in the field; and switching axes in the popover updates the
Pick tab's own switcher underneath. 477 unit tests (474 before M24, 3 new – two clamp
cases plus the rewritten round-trip case, same count as the original three), 59 CLI
tests unchanged, 42 XCUITests (37 before M24, 5 new) – all passing in one
`** TEST SUCCEEDED **` run, 578
tests total.

### ✅ M25 – Click the notation to re-spell the active color

`ColorInputField.summary(for:)` rendered `Text(describe(result.notation))` – the
"6-digit hex" / "oklch()" line under the swatch. It is now a `Menu` listing every
format that can name the current color, grouped by `FormatSection` and narrowed under
`webFriendly` exactly the way `MenuBarPanel.copyMenu` already was. Choosing one calls
the new `ColorStore.respell(as:)`.

**`respell` is deliberately not built on `adopt(_:preferring:)`, and that turned out to
be the one real design decision here rather than a detail.** `adopt` exists for a color
with no notation opinion of its own – an eyedropper sample, a picker result – so its
`spelling(preferring:)` step is allowed to override the format it is handed when that
format can't hold the value losslessly, silently substituting `color(display-p3 …)`.
A menu click *is* the opinion: choosing "Hex" has to mean hex, gamut mapping and all,
never a quiet swap to a format the click never named. So `respell` calls
`ColorValue.formatted(as:options:)` directly with the exact format chosen and writes
back precisely its `css`, or nothing at all when the color can't be named that way –
only `.keyword` ever answers so, and while the menu already filters those out,
`respell` guards independently rather than trusting the caller to have filtered
correctly. It still pulls the color into sRGB first under `webFriendly`, the identical
recalibration `adopt` performs and for the identical reason: a perceptual function is
unbounded and `.lossless` will not clamp it on its own.

**The three-way `FormatSection.all`/`.webFriendly` ternary the plan flagged really was
worth consolidating.** `ConversionPanel`'s rows, `MenuBarPanel`'s copy menu, and this
new notation menu all spelled `store.webFriendly ? FormatSection.webFriendly :
FormatSection.all` independently; all three now call the new
`FormatSection.sections(webFriendly:)`.

**A mutation survived on the first pass, and the fix is the finding worth keeping.**
`respellNoOpsWhenTheColorCannotBeNamed` first used `#3b82f6` as its color: a mutation
that falls back to a hex spelling instead of no-opping when a format can't name the
color passed that version of the test outright, because `#3b82f6`'s hex spelling and
its typed spelling are the identical string – the mutation was invisible against a
starting text that already *was* what the fallback would produce. Rewritten against
`rgb(59 130 246)`, whose hex fallback (`#3b82f6`) differs textually from what was
typed, the same mutation now fails the test. Three other mutations were caught on the
first pass and each failure set was tight: dropping the `webFriendly` clamp fails only
the clamp test; reading at `formatOptions` instead of `.lossless` fails the precision
test directly and, incidentally, ten of the seventeen round-trip cases too (every
non-hex/rgb/hsl/hwb/keyword format loses enough precision at the default 4-decimal
display setting to trip the round trip's own 1e-7 tolerance); and routing through
`spelling(preferring:)` the way `adopt` does fails only the gamut-mapping test, which
is exactly the behavior that test exists to distinguish `respell` from `adopt` by.

**Testing.** `ColorStoreTests` gained a "Notation menu (M25)" section, seven cases: the
round trip parameterized over the whole catalog on `rebeccapurple` – chosen in-gamut
and keyword-nameable, so `.keyword` gets a real case instead of the vacuous no-op it
would be against an unnamed color; the honest gamut-mapping exception, which also
proves `respell` doesn't silently substitute a format the way `adopt` does; display
precision; the can't-name-it no-op described above; and both directions of the
`webFriendly` clamp. A new UI file, `NotationMenuSmokeTests`, two cases: the control
exists as a `menuButton`; choosing `rgb()` on `rebeccapurple` rewrites the field to
`rgb(102 51 153)`, cross-checked against `colorkit convert rebeccapurple --format rgb`
before being pinned so the exact string wasn't a guess. 483 unit tests (476 before
M25, 7 new), 59 CLI tests unchanged, 44 XCUITests (42 before M25, 2 new) – 586 total,
all passing in one `** TEST SUCCEEDED **` run.

### ✅ M26 – Import from the export shapes

The largest milestone, and last because it consumed M20's group vocabulary.

**Core: `ColorCore/Import/PaletteImport.swift`.** A separate `ImportShape` enum, not
`ExportShape` — design tokens are importable and not an export shape, and a bare list of
colors is importable and not a document shape at all:

```
customProperties · declaration · json · tailwindTheme · tailwindConfig
p3WithFallback · designTokens · looseColors
```

`detect(_:)` sniffs structurally, most specific first, exactly as planned. `parse(_:as:)`
throws only `PaletteImportError` for a whole-input failure (an empty paste, a design-token
file that isn't JSON); one bad value inside an otherwise good document is reported in
`ImportedPalette.skipped` instead, mirroring `DesignTokenImport`'s split between a thrown
error and a skip list.

**Two deliberate departures from the plan's sketch, both decided before any code was
written.**

1. **No `texts: [String: String]` side table.** A dictionary keyed by entry key breaks the
   instant two groups share a key — `brand.500` and `accent.500` both key `"500"`, and one
   pasted spelling silently overwrites the other. `ImportedEntry` carries `key`, `color`
   *and* `text` together instead, so the pasted spelling travels with the color it belongs
   to rather than living in a second collection indexed the same fragile way.
2. **Header comments decide grouping before segment inference does.** The plan's
   segment-wise extraction ("`primary-100`, `primary-200` → family `primary`") cannot by
   itself satisfy the plan's own round-trip oracle: a two-group `customProperties` export
   (`--brand-500, --brand-600, --accent-500`) has *no* shared segment across all three
   properties, so pure prefix inference would produce three singleton groups instead of two.
   What actually carries the grouping is `ColorExport`'s own `/* From "…" */` header comment
   — a *fact*, where prefix inference is a *guess* about a file this app never wrote. So a
   headered block strips exactly the header's name off every property; segment-wise
   inference is the fallback only when there is no header at all (a single-group export, or
   a hand-authored file). `p3WithFallback` inherits this for free, since it re-enters the
   same property-block parser on its `@media` override text.

**`p3WithFallback` reads only its `@media` override, never the hex fallback block.** Hex
`cannotRepresentOutOfGamut`, so trusting the fallback would silently round away exactly the
colors that motivated choosing the shape. `PaletteImportTests.p3WithFallbackReadsTheOverride`
renders a pure Display P3 primary and asserts both that the import matches it and that the
fallback block's own hex answer is a *materially different* color — not a rounding-tolerance
question but a "which block did this actually read" one.

**Name extraction is segment-wise, not character-wise, exactly as planned** — and this is
where `PaletteImportTests.familyExtractionIsSegmentWise` earns its keep: `primary-100` and
`primar-200` share seven raw characters and zero hyphen segments, so a character-wise
prefix (verified by mutation) would collapse them to `primar`, a family nothing named. No
shared segment at all becomes N singleton groups, M20's loose-color rule in reverse.

**Storage spelling is the "format" control, exactly as planned** — but the mechanism moved
down a layer from the sketch. `ProjectLibrary`'s fourth overload always writes
`ImportedEntry.text` verbatim; "keep as pasted" vs. a chosen format is decided by
`ImportTextSheet` *before* the call, which re-spells each entry's `text` with
`ColorValue.formatted(as:options:)` when a specific format is picked. This is the identical
discipline `ColorStore.respell(as:)` (M25) established for the same reason: a control naming
an exact format must not be second-guessed by a lower layer that is allowed to override it.

**The fourth `savePalette` overload reuses `.imported` rather than adding a `PaletteKind`
case**, the alternative the plan left open. Both this and the design-token overload mean the
identical thing — "somebody else's names, read out of a file or a paste box" — so a second
case would be a schema-visible string distinguishing nothing a user or a test needs told
apart.

**`ProjectLibrary.rename(_ palette:to:)` stays unwired, and this is a deliberate note rather
than an oversight.** The plan floated wiring it from the sheet's name field; the field
instead supplies the name at *creation* (`savePalette(importing:named:to:)` already takes
one), so there is no post-hoc rename to perform. The *palette* overload remains the
library's only unused mutation — the project one is wired, from `ProjectsPanel`'s name
field on submit. Naming the overload matters: written bare as `rename(_:to:)` the claim
covers both and is false.

**UI: `Menu("Import")` off the Projects panel's save-controls row, not an eighth tool** —
`Button("Import Tokens…")` became `Menu("Import")` with **From Text…** (`ImportTextSheet`,
new) and **From Token File…** (the pre-existing `fileImporter` flow, unchanged). The row
stays at four controls, per the tool-switcher ceiling this milestone series has respected
throughout.

The sheet: a plain `TextEditor` paste box (bound straight to state, deliberately never a
"Paste" button reading `NSPasteboard` — nothing outside a running app, and no XCUITest,
could type into that); an overridable shape picker; an editable name field that tracks the
parsed document's suggestion until the user actually types in it (single-group case only —
multiple groups already have their own names from structure); a storage-format picker
narrowed under `webFriendly` the same way `ExportPanel`'s already is; a destination segmented
control (existing project, defaulting to whatever `ProjectsPanel` has open, or a new one);
and a live preview of every group's swatches plus a skipped-value count.

**Testing.** Unit (`PaletteImportTests.swift`, 20 tests): shape detection including
ordering (`@theme` ahead of the JSON/declaration fallbacks); the segment-wise vs.
character-wise discriminator; the round trip through every export shape at both
cardinalities (a lone color, a two-group document), plus a sanitized-name case; the
`p3WithFallback` override-vs-fallback discriminator; a malformed value skipped without
losing its neighbours; `looseColors`' paren-depth-aware splitting (a `color-mix()`
argument's internal commas are not separators); `designTokens` delegation, including a
broken token skipped without losing a good one alongside it. Four mutations verified by
hand — ignoring headers, character-wise prefix, reading `p3WithFallback`'s hex block,
reordering `detect()`'s `@media`/`:root` checks — each failed exactly its own test and no
other. Persistence (`ProjectStoreTests.swift`, 2 tests): the fourth overload's stored text
is the literal pasted string, not a re-derivation (checked by mutation against
`.derived(_:preferring: .oklch)`, which both tests catch); the stored text reparses to the
stored components, the same check every other stored spelling in this app carries. UI
(`ProjectsSmokeTests.swift`): the Import menu offers both paths without clicking the
un-drivable one (`NSOpenPanel`, same limitation the pre-M26 test already worked around);
a full paste-to-palette run through `app.sheets`, typing a two-property `:root` block into
the `textViews` query, confirming, and asserting a palette row and the import summary
both appear — the one place the segment-wise family inference is checked reaching an
actual saved `Palette` rather than a parsed `ImportedPalette`. 505 unit tests (483 before
M26, 20 in `PaletteImportTests` + 2 in `ProjectStoreTests`), 59 CLI tests unchanged, 45
XCUITests (44 before M26, 1 net new — one pre-existing test rewritten for the menu, one
genuinely new) — 609 total, all passing in one `** TEST SUCCEEDED **` run.

**Two findings landed after the milestone's own commits, both from a post-landing review,
and both are the shape CLAUDE.md warns about — a test whose assertion could not fail for
the right reason.**

1. `topLevelSegments`' comma-list case, `case ",", "\n", ";" where depth == 0:`, does not
   guard all three separators the way it reads. Swift attaches a `where` written after the
   last pattern in a comma-separated case list to *that pattern alone* — `,` and `\n` split
   at any paren depth, and only `;` was actually depth-aware. `color-mix(in oklch, red,
   blue), #3b82f6` split into four pieces at every top-level *and* nested comma
   (`"color-mix(in oklch"`, `"red"`, `"blue)"`, `"#3b82f6"`), two of which — `"red"` and the
   trailing hex — happen to parse as colors on their own. So
   `functionCallCommasAreNotSeparators`, which only checked `entries.count == 2`, passed
   outright: a wrong split produced the right count by coincidence, the exact tautology
   shape M8b's `writableContentTypes` mistake was. Fixed by moving the depth check into an
   explicit `if` inside one shared case arm; the test now also asserts
   `imported.skipped.isEmpty` and the first entry's own text, which fails against the
   original code (confirmed before fixing) and cannot be satisfied by a coincidence of
   counts.
2. `ImportTextSheet`'s name-suggestion `.onChange(of: palette.detectedName)` sat on a
   subtree (`if palette.groups.count == 1 { … }`) that does not exist before the first
   successful parse — and `onChange` does not fire for the value a modifier is *created*
   with, only for changes after that. So the very first paste never populated the field:
   `name` stayed `""`, the field showed its placeholder, and `performImport`'s
   `!name.isEmpty ? name : group.name` fallback silently covered for it whenever the
   group's own name happened to equal the placeholder — which the one UI test exercising
   this used, `brand`, so it passed while the claimed behavior ("tracks the parsed
   document's suggestion") was false for every other family name. Fixed with
   `initial: true`; the UI test now asserts the field's value directly rather than only the
   palette that resulted, which would not have caught this on its own.

Both fixes were confirmed to fail against the unfixed code before being fixed, per this
project's own rule for a new regression assertion. Neither changed a test *count* — both
strengthened an existing test's assertions rather than adding a new one — so the totals
above are unchanged: still 505 unit tests, 45 XCUITests.

### Files touched, by area (M19–M26)

**ColorCore** – `Export/ExportTemplate.swift` (`PaletteGroup`), `Export/ColorExport.swift`
(grouped renderer), `Format/FormatCatalog.swift` (`webFriendly`,
`spelling(preferring:allowingWideGamut:)`), `Format/CSSFormatter.swift` (`Codable`),
`Convert/GamutBoundary.swift` (`pulledInto`), `Transform/Harmony.swift` +
`ContrastSolver.swift` + `ShadeRamp.swift` (optional output gamut), new
`Import/PaletteImport.swift`.

**App** – new `Features/Settings/`, new `Features/Shell/RecentsRow.swift`, new
`Services/Preferences.swift`; `DesignSystem/ColorSwatch.swift` (`SwatchButton`),
`ContentView.swift`, `Features/Conversion/ColorInputField.swift` +
`FormatPresentation.swift`, `Features/Picker/PickerPanel.swift` + `PickerState.swift`,
new `Features/Picker/PickerPlaneView.swift` + `PickerHueStripView.swift` +
`PickerAlphaSliderView.swift` + `CompactPicker.swift` (M24),
`Features/Export/ExportPanel.swift` + `ExportPresentation.swift`,
`Features/Projects/ProjectsPanel.swift`, `Features/Shell/ColorStore.swift`,
`Persistence/ProjectLibrary.swift`, `ColorKitApp.swift`.

**Docs** – this file gains the new invariants as each milestone lands (the grouped
renderer's uniquing rule; the `webFriendly` table's transcription rule and the
`color(srgb …)` discriminator; the hide-don't-restrict rule for tools that cannot stay
in sRGB, and why mixing is the only one; the fourth `savePalette` overload;
`UITestEphemeralPreferences`'s three launch strings) – CLAUDE.md picks up the same
invariants once each is built, per its own convention.

---

### ✅ M27 – Customizable keyboard shortcut

Not part of the planned M19–M26 series – a direct user request, taken up once that
series closed. **Scope was narrowed on inspection, not assumed**: the app has exactly
one keyboard shortcut anywhere in it, the global "sample color from screen" chord
(`GlobalShortcut.sampleColor`, ⌃⌥⌘C). There is no `Commands` scene customizing menu
shortcuts to extend. So "customizable keyboard shortcuts" means making that one binding
user-recordable, not a broader menu-shortcut system that does not exist yet.

**`GlobalShortcut` gained `Codable` and `isEligible`.** Persisting a shortcut needs
`Codable`; persisting one safely needs more than that; the two were added together
rather than dealing with the second as an afterthought. `isEligible` requires at least
one of ⌃⌥⌘, with a bare function key as the sole exception — ⇧ alone does not qualify,
since ⇧A still types a capital A, and a chord that can still type a character would
swallow every keystroke of it in every app on the machine if claimed system-wide. This
is exactly the class of hazard a hand-edited or corrupted preferences file can trigger
that `Codable` synthesis has no way to know about.

**Two write paths, deliberately not merged into one.** `ColorStore.globalShortcut` is a
computed property over a private backing field (not a stored `var` with a `didSet`,
`recentLimit`'s M23 shape) whose setter re-registers immediately and accepts a possible
failure silently — the right behavior for a hand-edited preferences file reaching
`PreferenceStore.load()`, or Settings' "Reset to Defaults" setting `store.preferences =
Preferences()` wholesale. `updateGlobalShortcut(_:)`, what the Settings recorder calls,
is stricter: it validates against `isEligible` first, tries the new chord before
committing, rolls back to the chord that was already working if the system refuses the
new one, and reports success back to the caller — a user recording a chord in front of
the app deserves better than the passive paths' silent possibility of ending up with
none. It writes the private backing field directly, bypassing `globalShortcut`'s own
setter, so a successful recording does not pay for a second, redundant
unregister/register round trip.

**`ShortcutRecorderField`** is a local `NSEvent.addLocalMonitorForEvents(matching:
.keyDown)` installed only while recording, not an `NSViewRepresentable` — no focus ring
or custom hit-testing is needed, and returning `nil` from the monitor's handler swallows
the captured event outright, which is what stops a recorded ⌘W from also closing the
Settings window mid-capture. Carbon's modifier masks are translated from
`NSEvent.ModifierFlags`, not cast — they are different numeric values, the same fact
`GlobalShortcut.modifiers`' own doc already states. A small keyCode→label table covers
Space/Tab/Return/Delete/arrows/F1–F20, since `charactersIgnoringModifiers` is empty or
unhelpful for all of them.

**Testing.** [GlobalHotKeyTests](ColorKitTests/GlobalHotKeyTests.swift) pins
`isEligible`'s boundary and `GlobalShortcut`'s `Codable` round trip.
[ColorStoreTests](ColorKitTests/ColorStoreTests.swift) covers
`updateGlobalShortcut(_:)` end to end, including the one branch that claims a real
system-wide chord (a four-modifier probe, the same convention `GlobalHotKeyTests`
already uses to avoid racing the host app's own `.sampleColor` registration) —
confirmed by mutation that removing the `unregisterAll()` call before a rebind's retry
fails exactly that test.
[PreferencesTests](ColorKitTests/PreferencesTests.swift) extends the M19 pattern
(round trip, observation, clamp-on-load) to the new field. **No XCUITest**: nothing
drives the Settings window today, and synthesizing a key event needs Accessibility
permission a test runner has no business holding — recorded as a manual check, the same
honesty this file already extends to `NSOpenPanel`/`NSSavePanel`.

**Files touched.** `Services/GlobalHotKey.swift` (`Codable`, `isEligible`),
`Services/Preferences.swift` (`globalShortcut` field), `Features/Shell/ColorStore.swift`
(`globalShortcut`, `updateGlobalShortcut(_:)`, `registerGlobalShortcut(_:)`), new
`Features/Settings/ShortcutRecorderField.swift`, `Features/Settings/SettingsView.swift`
(Shortcuts section), `Features/Conversion/ColorInputField.swift` +
`Features/Shell/MenuBarPanel.swift` (read the live shortcut instead of the hardcoded
default).

### ✅ M28 – Release build (Developer ID)

Also a direct request, not a planned milestone. **Most of a distributable Release
configuration already existed** before this: `CODE_SIGN_STYLE = Automatic`,
`DEVELOPMENT_TEAM`, `ENABLE_APP_SANDBOX`, `ENABLE_HARDENED_RUNTIME`, an app icon, a
bundle identifier, and `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` were all already
in the project. No `.entitlements` file exists anywhere in the repo, confirmed still
correct: Xcode synthesizes one from those build settings at sign time — checked by
building the app and reading `codesign -d --entitlements -` off the result, which shows
exactly `com.apple.security.app-sandbox` and
`com.apple.security.files.user-selected.read-write` (plus `get-task-allow` in Debug
only, see below).

**The channel was a question for the user, not a default to assume**, since it decides
`ExportOptions.plist`'s `method` and whether notarization is scripted at all. Asked and
answered: Developer ID (direct download), not the Mac App Store.

**What was added.** `ExportOptions.plist` at the repo root, fixing `method:
developer-id` for the `-exportArchive` step; a *Release build* section in CLAUDE.md's
Commands documenting the four-command archive → export → notarize → staple sequence;
`INFOPLIST_KEY_NSHumanReadableCopyright`, empty in both configurations before this,
filled in both.

**What was verified versus documented.** `xcodebuild archive` was actually run — it
needs no more credentials than an ordinary build — and the archived app's entitlements
were read directly: `com.apple.security.get-task-allow`, present in every Debug build,
is **absent** from the Release archive. That is the fact that actually distinguishes "a
debug build with distribution-shaped settings" from a build Gatekeeper will treat as
one to distribute, and a green `xcodebuild build` cannot show it on its own, because
`build` and `archive` sign differently even from the same configuration.
`-exportArchive` and `notarytool submit`/`stapler staple` were **not** run —
`security find-identity -v -p codesigning` found no "Developer ID Application"
certificate in this environment — and are documented rather than verified, the same
honesty this file extends to every step needing credentials or hardware an agent does
not have.

**One assumption corrected by actually looking, not by reasoning about the scheme.**
The scheme builds both the app and `colorkit`, which suggested `colorkit` might already
be embedded in the distributed app or might be entirely absent from an archive. Neither
is true: listing the archive's contents shows `colorkit` **is** installed, at
`Products/usr/local/bin/colorkit` — a plain command-line-tool target with no
`SKIP_INSTALL` gets installed there by `xcodebuild archive` regardless of the app target
— but `-exportArchive` only pulls `Products/Applications/*.app` out of an archive, so
today's Developer ID export carries the app only. Whether `colorkit` should ship
alongside it (a Copy Files phase embedding it in `Contents/MacOS/`, the pattern apps
that also ship a CLI use) is a product decision left to the user, not made here.

**Two settings left as found, deliberately.** `MACOSX_DEPLOYMENT_TARGET = 26.5` means
the shipped app targets essentially only the newest OS, and `REGISTER_APP_GROUPS = YES`
is confirmed inert — no `com.apple.security.application-groups` entitlement appears in
a signed binary either way, and nothing in the codebase uses an app group. Both are
recorded in CLAUDE.md rather than silently changed, since changing either is a product
call this milestone was not asked to make.

**Files touched.** New `ExportOptions.plist` (repo root);
`ColorKit.xcodeproj/project.pbxproj` (`INFOPLIST_KEY_NSHumanReadableCopyright` in
both the app target's Debug and Release configurations).

### ✅ M29 – Install colorkit command

Not part of the M19–M26 series and not requested alongside M27/M28 — raised
afterward, once M28 had already flagged `colorkit`'s missing distribution story as an
open decision rather than settling it. Full plan approved with Parker on 2026-08-08 and
recorded verbatim at the time in
`/Users/parker/.claude/plans/i-certainly-don-t-mind-merry-lamport.md`.

**The problem, recapped from M28.** `xcodebuild archive` deposits `colorkit` at
`Products/usr/local/bin/colorkit` in the raw archive, but `-exportArchive` only pulls
`Products/Applications/*.app` out — so the exported, notarizable `.app` never carried
it, and the CLI had no distribution story of its own. Parker wanted a
Homebrew-independent convenience: embed `colorkit` in the `.app`, and let Settings
install a `colorkit` command onto the user's `$PATH` — explicitly without a privileged
helper tool or admin authentication.

**Three decisions settled with Parker before building, not re-litigated during it:**
default the install panel to `/usr/local/bin`; ship **neither** Reveal-in-Finder nor
Uninstall in this first version; **refuse** rather than overwrite if something already
exists at the chosen destination.

**Why this needs a panel at all, and why nothing can be persisted afterward.** The app
is sandboxed (`ENABLE_APP_SANDBOX = YES`), with exactly one file-access entitlement,
`ENABLE_USER_SELECTED_FILES = readwrite` — and that grant only covers paths the user
explicitly picks through a panel. There is no way to skip a one-time panel interaction
while staying sandboxed, and the sandbox also blocks probing arbitrary paths outside
the container/granted scope on a later launch — so the app can never reliably re-verify
that a symlink it created earlier still exists. That is what rules out a persisted
"installed ✓" status, not a stylistic preference: there is nothing honest to persist,
the same reasoning that already keeps `ColorStore.globalShortcut`'s two write paths
(M27) from claiming more certainty than the sandbox can back up. Confirmed genuinely
greenfield before any of this was built: no `Process`/`NSTask`/`osascript`/
`Authorization*`/`SMJobBless`/`SMAppService` existed anywhere in this codebase, and
none was introduced — the whole feature stays inside the sandbox.

**1. Embedding `colorkit`** needed `project.pbxproj` surgery the file-system-
synchronized groups can't cover: a new `PBXBuildFile` (this project's first — every
other source compiles through the synchronized-group mechanism, never an explicit
build file) with `ATTRIBUTES = (CodeSignOnCopy, )` wrapping the *existing* `colorkit`
product reference, a new `PBXCopyFilesBuildPhase` with `dstSubfolderSpec = 6`
("Embed Executables"), and a `PBXContainerItemProxy`/`PBXTargetDependency` pair so
`colorkit` builds before the app's new copy phase runs (the app target's
`dependencies` list was empty before this). Every object ID was checked directly
against the live file immediately before editing: the highest existing `2CB180xx…`
ID in use was `…17`, so `…18` through `…1B` were free and are what this milestone
used.

**The plan's own destination assumption was wrong, and the correction is worth
recording precisely — this is the milestone's one genuine "verify, don't assume"
finding.** The plan, written before any of this was built, predicted the copy phase
would land `colorkit` at `Contents/Executables/colorkit` — reasoning from
`dstSubfolderSpec = 6`'s label, "Executables" — and said in so many words that this
was *not* `Contents/MacOS/`, contradicting what this file's own M28 entry and
CLAUDE.md's Release-build section had separately speculated. Measured after actually
building both a Debug build and a Release archive: `colorkit` lands in
**`Contents/MacOS/`**, right beside the app's own executable. Xcode's "Executables"
destination resolves, for a macOS *application* product specifically, to the same
folder the main executable occupies — the build-phase name describes Xcode's internal
enum case, not the folder it maps to on this product type. So the pre-M29 hypothetical
guess in CLAUDE.md/PLAN.md turned out to be the correct one after all, and the plan
document that was supposed to correct it was itself the thing that needed correcting.
`CommandLineToolInstaller.embeddedBinaryURL(inBundleAt:)` is written against the
measured path, with the discrepancy recorded in its own doc comment.

**Post-M29 addendum, from the app rename to `ColorKit`/`colorkit`:** landing bare in
`Contents/MacOS/` was safe only because the app's own executable and the embedded CLI
had unrelated names. Once the app became `ColorKit`, `Contents/MacOS/ColorKit` (the
app) and `Contents/MacOS/colorkit` (the embedded CLI) are the same path on the
case-insensitive filesystem every default macOS volume uses, and the later write
silently won — measured on a build made before the fix, which had only one file in
`Contents/MacOS/` where two were expected, and launched the CLI's `--help` in place of
the app. The Copy Files phase's `dstPath` is now `cli`, landing the binary at
`Contents/MacOS/cli/colorkit` instead; `embeddedBinaryURL(inBundleAt:)` and its test
were updated to match. Two build settings needed the identical fix for the identical
reason, one level down: the CLI's Xcode target is `ColorKitCLI` rather than `colorkit`
(so its intermediate build directory, named from the target, doesn't collide with the
app target's `ColorKit.build`), with `PRODUCT_NAME` set explicitly to `colorkit` so the
rename is invisible in the shipped binary's name; and `PRODUCT_MODULE_NAME` is set
explicitly to `ColorKitCLIModule`, because the module name Xcode derives by default
from `PRODUCT_NAME` — `colorkit` — collides with the app's own `ColorKit.swiftmodule`
in the shared build-products directory the same way. All three collisions were found
by building, not by reasoning about the settings in the abstract: the first surfaced as
a build failure with `-scheme ColorKit` that did not reproduce with `-target colorkit`
alone, the second as `ColorKitTests` failing to resolve `@testable import ColorKit`,
and the third — the broken app bundle itself — only by actually launching the built
`.app` and noticing it printed the CLI's usage text.

`CodeSignOnCopy` was required for the embedded binary to pass notarization
independently of the app — confirmed via `codesign -d --verbose=2` on the archived
`colorkit`, which reports `flags=…(runtime)`. **The Hardened Runtime question was
resolved in `colorkit`'s favor without changing its build settings**: `colorkit` has
no `ENABLE_HARDENED_RUNTIME` of its own, Debug or Release, and the embedded copy still
signs with the runtime flag set — `CodeSignOnCopy` alone is sufficient, confirmed by
reading the signature rather than assumed from the attribute's name. No build setting
was added.

`colorkit` still has no `SKIP_INSTALL`, so today's archive has it in *two* places —
the new embedded copy and the old loose `Products/usr/local/bin/colorkit`. Flagged as
a cosmetic follow-up, deliberately not folded into this change unverified, the same
discipline M28 already modeled for `-exportArchive`/`notarytool`.

**2. New service, `ColorKit/Services/CommandLineToolInstaller.swift`**, split pure
from impure the way `GlobalShortcut`/`GlobalHotKeyCenter` (M27) already do. Pure,
`nonisolated`, unit-tested directly: `embeddedBinaryURL(inBundleAt:)` and
`destinationURL(in:)` (both take a `URL` parameter rather than reading `Bundle.main`);
`isTranslocated(bundlePath:)`, a path-substring pre-flight refusal for macOS App
Translocation (there is no `SecTranslocate.h` in the installed SDK, confirmed by an
SDK search, so this is a recorded heuristic rather than a real API call); `PathAdvice`,
a transcribed table of well-known `$PATH` directories versus everything else, the same
"transcribe, don't derive" rule `ColorSpace.componentRoles` follows; `InstallOutcome`,
one case per terminal state with its own sentence — `.translocated`, `.binaryMissing`,
`.destinationOccupied(String)`, `.securityScopeFailed`, `.writeDenied`,
`.success(PathAdvice)` — and `outcome(for:at:scoped:)`, the function that maps a
thrown `createSymbolicLink` `NSError` onto one of them, split out specifically so the
discrimination is testable with a synthetic error and no real write. Cancellation is
not a case of `InstallOutcome` at all: the picker returning `nil` is handled entirely
by the Settings view not calling `install(embeddedBinary:into:)`, so there is nothing
to construct and nothing to say. Impure:
`presentDestinationPicker(startingAt:)` wraps `NSOpenPanel` directly — a second,
independent precedent alongside `ProjectsPanel`'s `.fileImporter`, not an extension of
it, because this is a write-destination directory picker
(`canChooseDirectories`/`canCreateDirectories`) rather than a file-read picker — and
`install(embeddedBinary:into:)`, which runs the pre-flight checks, then
`startAccessingSecurityScopedResource()`/`defer { if scoped { … } }` (the exact idiom
`ProjectsPanel.importTokens` already uses), then `createSymbolicLink`.

**3. `SettingsView.swift`** gained a "Command Line Tool" section after "Shortcuts," an
"Install…" button that never becomes "Installed ✓," and an ephemeral `@State
installOutcome` — cleared at the start of every click, not only a successful one, so a
stale message from a previous attempt is never mistaken for ongoing truth.

**What this did not build, recorded rather than left implicit:** no privileged helper
tool, no persisted install status, no Reveal-in-Finder, no Uninstall — all deliberate
scope decisions from the approved plan, not gaps found afterward.

**Verification.** Unit-tested without a panel or a real app, in
`CommandLineToolInstallerTests`: `embeddedBinaryURL`/`destinationURL` (pure, fake
URLs); `isTranslocated` (a real `/Applications/…` path against a synthetic
`AppTranslocation` one — both directions confirmed to actually discriminate by
mutation, not merely asserted); `adviceForInstalling` (`/usr/local/bin`/
`/opt/homebrew/bin` → `.likelyOnPath`; a home-relative or arbitrary directory →
`.needsProfileLine`, including `$HOME`-relative spelling, that the literal expanded
home path never leaks into the line, and correct quoting for a directory containing a
space); `InstallOutcome`'s message mapping, parameterized over one representative
instance per case (it carries associated values, so it cannot get `CaseIterable` for
free the way `ExportShape` does) for distinct non-empty strings; `outcome(for:at:
scoped:)`'s discrimination — already-exists vs. permission-denied, and
`.securityScopeFailed` vs. `.writeDenied` depending on whether the scope claim had
already failed — confirmed by mutation to actually depend on the `scoped` flag, not
merely to compile.

**One thing the plan assumed untestable turned out not to be, and it was worth
checking rather than assuming.** `ColorKitTests` carries no `ENABLE_APP_SANDBOX`
of its own — only the app target does — so unlike `NSOpenPanel`/`.fileImporter`
themselves, `install(embeddedBinary:into:)`'s real filesystem write **is** reachable
from a unit test, against a plain temp directory rather than a security-scoped
bookmark. Two tests exercise the genuine `createSymbolicLink` call end to end: one
confirms a real install actually creates a symlink pointing at the embedded binary,
and one confirms the "refuse rather than overwrite" decision holds against a real
pre-existing file, byte for byte. What remains a recorded manual check is narrower
than the plan first assumed: the panel itself (`NSOpenPanel` is a separate process,
same limitation as `NSSavePanel`/`.fileImporter` elsewhere in this file), and what a
*genuinely sandboxed* security-scoped claim does — this test target's `false`-returning,
still-working claim on a plain URL is not proof of what a real powerbox bookmark does
under `ENABLE_APP_SANDBOX`. Also unchecked by hand: the translocation guard firing on
a real translocated launch, and running `colorkit --help` from a fresh Terminal after
a real install.

**Code-signing verification, extending M28's own checks.** Both a Debug build and a
Release archive were built after adding the copy phase.
`codesign --verify --deep --strict --verbose=2` passes on the whole archived bundle;
`codesign -d --verbose=2` on the archived `colorkit` shows
`flags=0x10000(runtime)` — the Hardened Runtime finding above. Actual notarization
stays unverifiable in this environment, same as M28: no "Developer ID Application"
certificate here.

**Critical files.** `ColorKit.xcodeproj/project.pbxproj`; new
`ColorKit/Services/CommandLineToolInstaller.swift`;
`ColorKit/Features/Settings/SettingsView.swift`; `CLAUDE.md`; this file; new
`ColorKitTests/CommandLineToolInstallerTests.swift`.

**Addendum, same day: the recorded manual check found a real bug on first actual use,
and it was the default destination itself.** Parker ran the feature against the real
panel — exactly the check this section had just finished calling unverified — and
`/usr/local/bin`, the settled default, failed with `.writeDenied` every time, both
launched from `/Applications` and from elsewhere, ruling out translocation as the
cause. Confirmed directly rather than guessed at: `stat -f "%Su:%Sg %A" /usr/local/bin`
reports `root:wheel 755` on this Mac, and `/opt/homebrew/bin` (Homebrew's own, on
Apple Silicon) reports `parker:admin 775` — Homebrew here never touches `/usr/local`
at all, so nothing had ever made the settled default writable. **This is the common
case, not an edge case**: any Mac without an Intel-era Homebrew install (which does
chown `/usr/local`) has this exact permission on this exact directory out of the box,
which means the feature's own default destination was one it could not itself write
to, and the pre-fix message — "You don't have permission to write to that folder.
Choose a different one." — was true and useless, naming no folder and no fix, on the
one path most users would hit first.

**The fix, confirmed with Parker rather than decided unilaterally**, since it touches
a decision already settled once: keep `/usr/local/bin` as the picker's starting point
unchanged (re-litigating *that* was explicitly not wanted), and make `.writeDenied`
carry the directory that failed so its message can be genuinely actionable — the exact
`sudo chown "$(whoami)" "<path>"` line for a user who wants that folder specifically,
*and* a suggestion of `~/.local/bin` as a folder nobody needs a password to own, which
the picker's `canCreateDirectories = true` can already create on the spot. A dedicated
test (`writeDeniedMessageIsActionable`) pins that the message names the failed
directory, the `sudo chown` line, and `~/.local/bin` together — confirmed to actually
matter by mutation: softening the alternative-folder sentence alone fails exactly that
test and nothing else. `outcome(for:at:scoped:)`'s three `.writeDenied` call sites and
`InstallOutcome`'s own `Equatable` synthesis all needed the new associated `URL`, which
is what caught every site that needed updating — the compiler found the same set a
hand search would have needed to find by eye.

**Second addendum, same day: the `.writeDenied` fix's own suggestion exposed the next
gap.** Parker picked `~/.local/bin` — the very folder the fix above suggests as a
no-`sudo` alternative — and it was already on his shell `$PATH`. The install still
reported "Installed, but that folder isn't on your PATH by default," a flatly wrong
claim for exactly the folder the app had just recommended. **The tempting fix — add
`~/.local/bin` to `wellKnownPathDirectories` — was rejected, and the reasoning is worth
keeping rather than just the outcome.** `/usr/local/bin` earns its spot from macOS's
own default `/etc/paths`, and `/opt/homebrew/bin` from Homebrew's installer adding it
for every user of it; nothing puts `~/.local/bin` on `$PATH` by default on macOS, so a
user has it only if they, or some other tool (`pipx ensurepath`, a personal dotfile),
added it themselves. Adding it to the table would not have fixed the report so much as
moved it — right for users like Parker, confidently wrong for anyone who picks that
folder without having configured it, the identical "plausible-looking rule gets `~/bin`
wrong" trap `PathAdvice`'s own doc comment already named for a different path shape.
**The actual fix was in the message, not the table**: `PathAdvice.needsProfileLine`'s
case doc was rewritten to say plainly that it means "not one of the well-known ones,"
not "confirmed missing," and `InstallOutcome.message`'s `.needsProfileLine` case no
longer asserts the folder is missing from `$PATH` at all — it says to run
`colorkit --help` first and only offers the profile line if that actually fails. That
framing is correct regardless of which way any given folder turns out to be wrong,
which a table entry never can be. `needsProfileLineMessageDoesNotAssertPathIsMissing`
pins it, confirmed by mutation: reverting to the old assertive wording fails both of
its assertions, not zero and not one.

## Planned: M30–M34 – close the import/export round trip

M0–M29 are done, so this is a sixth series rather than more of the old list. Four of the
five come from Parker using the built app on 2026-08-09; the fifth is the asymmetry that
report uncovered while the first four were being scoped. They are all one theme – **what
this app writes, it should read back, and it should say plainly what it speaks**:

- **A single imported color becomes a palette of one.** Import a whole-project export and
  the Colors section comes back empty while the Palettes section fills with one-entry
  palettes, even though those values were loose colors when they left.
- **Import reads a *file* only in the one format the app cannot write.** The Import menu
  offers "From Token File…" and nothing else file-shaped, so exporting a `.css` and
  re-opening it means going through the paste box – and picking the app's own JSON export
  in that panel produces *"That JSON file contains no design tokens"*, which is correct
  and reads like a bug.
- **Nothing saved can be renamed.** A project can (`ProjectsPanel.swift:219`); a palette,
  a loose color and a palette entry cannot. `ProjectLibrary.rename(_ palette:to:)` has been
  written and unwired since M9.
- **Import is unreachable until a project exists.** The Import menu lives inside
  `saveControls(_:)`, which only renders under a selected project, so the feature is
  invisible to anyone who has not already made one and nothing says that is the order.
- **The app writes six document shapes and reads seven, plus a bare color list.** M17
  built design token *import* only. That was a deliberate scoping call and it is nowhere
  stated, so the Import menu appears to advertise a format the app can produce. (Stated
  this way rather than "reads eight" because `ImportShape.looseColors` is not a document
  shape at all – the two enums differ in both directions, which is the argument M26 made
  for keeping them separate. Design tokens are the one shape genuinely missing from
  export.)

**Five decisions were settled with Parker before planning, each overriding a more obvious
reading, and are not to be re-litigated when implementing:**

1. **Token support is extended, not removed.** Removal was Parker's first instinct once
   the asymmetry was confirmed, and it was costed rather than waved off: ~950 lines in
   `DesignTokens.swift` and `DesignTokenImportTests.swift` before any call site, plus
   `ImportShape.designTokens` (so the paste box would stop reading tokens too),
   `ProjectLibrary`'s third `savePalette` overload, four message helpers in
   `ProjectsPanel`, and **one of the CLI's nine commands** – `colorkit tokens`, which
   never had the asymmetry problem and is useful exactly as it stands. M34 adds the
   missing direction instead.
2. **"From Token File…" becomes "From File…", a superset rather than a swap.** Replacing
   it with "From CSS File" – the literal request – would delete a working, spec-conformant
   decoder on the strength of a premise that turned out to be false.
3. **Palette-entry renaming is in scope for M32**, having been scoped out of the first
   draft on the grounds that an entry's name *is* its export key. It is in with guard
   rails rather than out, because the keys are visible under every swatch in `paletteRow`
   and a user who can see them can reasonably expect to change them.
4. **A single-entry group imports as a loose color when its key is empty** – not on
   `count == 1`. See M30; this mirrors an argument the export layer already wrote down.
5. **The format is named by its actual name wherever it appears** – "Design tokens
   (DTCG)", not "tokens". It was the *lack of transparency* that produced the confusion,
   not the missing shape alone, so naming it is part of M34's deliverable rather than a
   nicety attached to it.

Order is M30 → M31 → M32 → M33 → M34, each its own commit. M31 inherits M30's fix, which
is the reason for that pairing rather than the reverse.

### ✅ M30 – A single color imports as a color

**Built.** `ImportedGroup.soleColor` (the empty-key predicate, mirror of
`ColorExport.soleEntry`), the fifth save door `ProjectLibrary.saveColor(importing:named:to:)`
(verbatim text + `notes`), and `ImportTextSheet`'s group-counted split — one `splitPhrase`
helper feeds both the preview caption and the confirmation, and the name seed filters
`defaultName` so the field never shows "brand" for a color it will store nameless. Three
tests: the recorded `project-export-p3-with-fallback.css` fixture (7 colors, 3 palettes),
a round trip over `.customProperties`/`.json`/`.tailwindConfig` (one color + one
one-entry palette), and a `ProjectStoreTests` verbatim-storage check on the new door. The
`entries.count == 1` mutation was run and failed exactly the three round-trip cases with
the fixture green, as planned below. All 539 `ColorKitTests` + 59 `ColorKitCLITests` pass.

**One UI-test edit is reasoned but unverified**, the same honesty this file extends to
`NSOpenPanel`/`NSSavePanel` and `updateGlobalShortcut`'s rejection branch.
`ProjectsSmokeTests.testImportingPastedCustomPropertiesCreatesAPalette` asserted the
old entry-counting summary `"Imported 2 colors"`; M30 counts *kinds of group*, so a
two-entry `brand` family is now `"Imported 1 palette"` and the assertion was updated to
match. The runner could not be exercised here — `xcodebuild` failed twice at
*"Timed out while enabling automation mode"*, a host capability failure rather than a
test result (Mac idle, no orphan runners, so not the frontmost-app cause documented in
CLAUDE.md). The trace is straightforward — one `brand` family of two →
`splitPhrase(0, 1)` → `"Imported 1 palette"`, and the name field still reads `"brand"`
because `commonFamily`'s "brand" is `soleColor`-negative so the seed filter leaves it —
but it was not run.

**The discriminator is an empty key, not a count of one, and the export layer settled this
first.** `ColorExport.soleEntry` decides whether a group nests as a JSON object or
flattens to a bare string, and it keys on the entry's key being empty *with the count test
explicitly rejected in its own doc comment*: "a harmony of one is still a scale – a
one-stop ramp keyed `1` should nest like an eleven-stop one, so that a consumer's
`brand.1` does not become `brand` when the stepper moves." The import side simply is not
reading a signal the export side already writes. The rule here is that function's mirror,
and citing it is what keeps this from reading as a coin flip.

Checked against every shape before committing to it, because the obvious counter-argument
– that a header carries the *raw* group name while a property carries the sanitized one,
so `name == header` would fail for any color named with a space – **is false for documents
this app writes**: `groupedPropertyLines` writes `group.identifier`, which is already
through `cssIdentifier` (`ColorExport.swift:347`), so `/* From "text-color" */` sits above
`--text-color` and the key strips to empty. The rule holds for:

| Input | Result |
|---|---|
| `--text-color` under its own header (project export) | key `""` → color |
| `--brand-500`, `--brand-600` under `/* From "brand" */` | keys `500`, `600` → palette |
| `{"Primary": {"50": …}}` – JSON object | palette |
| `{"Primary-Base": "oklch(…)"}` – JSON string | color |
| hand-authored `--brand: #fff; --accent: #000;` (no shared segment) | two colors |
| one pasted color (`parseLooseColors` already special-cases it to an empty key) | color |

**Where the rule lives.** `ImportedGroup.soleColor: ImportedEntry?` in
`ColorCore/Import/PaletteImport.swift`, one computed property rather than the test written
out at each site – the sheet's preview and its save both consult it and must not drift
about what "this is a color" means. Same one-predicate discipline as `isGamutMapped` and
`pulledInto`, and it makes the rule unit-testable without a save.

**The save is a fifth door, deliberately.** `ProjectLibrary.saveColor(importing entry:
ImportedEntry, to:)`, not a widened `saveColor(_:named:to:)`. It writes
`ColorRecord(entry.color, text: entry.text)` **verbatim** – never `.derived(_:preferring:)`
– which is the identical rule the fourth `savePalette` overload exists to protect, and a
new door into that room is exactly how it gets re-broken. It also carries `notes`, which
the existing `saveColor` has no parameter for and which a design token's `$description`
currently rides in on through the palette overload.

**What becomes the color's name:** the group name, *unless* it is `ExportOptions
.defaultName` (`"brand"`). That value is a placeholder – `parseLooseColors` and headerless
`parseDeclarations` both reach for it – so storing it would label a pasted color "brand" as
if somebody had chosen that. Leave the name empty there and let the tile fall back to
displaying the CSS text, which it already does.

**UI:** `ImportTextSheet`'s preview says which is which ("2 colors and 1 palette"), so the
split is visible before the save rather than discovered after it – **and the summary
`onImported` hands back to `ProjectsPanel.importSummary` splits the same way.**
`performImport` currently builds "Imported 3 colors", counting entries; leaving that while
the preview above it counted groups would put a preview and a confirmation on screen that
contradict each other about what just happened, which is the same defect as M8's
placeholder disagreeing with its own fallback.

**Tests – two of them, making different claims.** They look like one test and are not, and
the difference is the reason for keeping both.

1. **A recorded fixture**, `ColorKitTests/Fixtures/project-export-p3-with-fallback.css` –
   **a real document this app produced**, exported by Parker from a real project on
   2026-08-09 and the artifact that prompted this milestone, not a string a test author
   hand-wrote to match what the parser already does. It pins the parser against something
   the app actually shipped, so it catches the failure a self-consistent round trip cannot:
   both halves drifting *together* and still agreeing.
2. **A render-then-parse round trip**, built in the test: export a project holding one loose
   color *and* one one-entry palette, import it, assert one color and one palette come back.
   This catches the opposite failure – the two halves disagreeing *today* – and it is the
   only one of the pair that discriminates the palette-of-one case, since the fixture has
   no one-entry palette in it. Asserting only that loose colors survive would pass under
   the naive rule, which is the lesson `json` and `tailwindConfig` taught at both
   cardinalities in M8.

**The fixture's expected reading, traced against the parser before it was adopted:**
`detect` answers `p3WithFallback` (the `@media (color-gamut` test runs before the `:root {`
one, and the document satisfies both), so only the `@media` block is read; `headeredBlocks`
finds ten `/* From "…" */` blocks; and the key derivation at
`parsePropertyBlock`'s headered branch splits them:

| Blocks | Property vs. header | key | Imports as |
|---|---|---|---|
| `Greyscale`, `Primary`, `Accent` (11 entries each) | `Greyscale-50` has prefix `Greyscale-` | `50` … `950` | 3 palettes |
| `Primary-Base`, `Backgound`, `Body-Text-Base`, `Body-Text-Callout`, `Body-Text-Callout-Strong`, `Body-Text-Accent`, `Body-Text-Accent-Strong` | `name == header` exactly | `""` | 7 loose colors |

Today that same file yields **ten palettes**, seven of them holding one color, and an empty
Colors section – the reported defect, reproduced from a real artifact rather than described.

**Three further facts the fixture pins for free**, each of which already has a rule and none
of which currently has a test built on a genuine document: that `p3WithFallback` reads the
`@media` override and never the hex fallback (the imported values are the `color(display-p3
…)` spellings, materially different strings from the hex block above them); that a header is
authoritative over segment inference (`Primary-Base` must **not** be absorbed into the
`Primary` family, which naive prefix inference would do); and that
`saveColor(importing:)` stores `entry.text` **verbatim** – the assertion is that the seven
colors' stored text is the `color(display-p3 …)` substring, which a `.derived(_:preferring:)`
regression fails immediately.

Load it the way every other fixture here is loaded – `URL(fileURLWithPath: #filePath)` up to
the test directory, then `Fixtures/…` – which is **source-relative, not a bundle resource**,
so a new file type needs no project configuration and no copy phase. The same document also
serves M31 as the file that gets opened rather than pasted.

**It is also the first fixture in this repo that is not machine-generated, and that inverts
the rule the other five carry.** `reference-vectors.json`, `parse-vectors.json`,
`contrast-vectors.json`, `mix-vectors.json` and `cvd-vectors.json` all come from
`Tools/`, and CLAUDE.md's standing instruction for them is *regenerate, never hand-edit*.
This one is the opposite: it is a **recorded artifact**, and re-exporting it from a current
build would destroy exactly what it is for – the moment the document stops matching what a
newer exporter writes is the moment the test has something to say. Do not refresh it to make
it agree; if it disagrees, that is a finding. A note to this effect belongs beside it and in
CLAUDE.md's fixture rules when M30 lands.

Two honest limitations to state in the test rather than discover later: the seven colors
come back **named after the sanitized header** (`Body-Text-Callout-Strong`), because
`cssIdentifier` is lossy and has no inverse – M17's recorded limitation, and what M32 exists
to let a user repair; and their values are Display P3 spellings rounded to the export's
precision, not the original hex, which is what reading the override block means.

**Mutation:** flip the guard to `entries.count == 1` and confirm the failure set is exactly
the JSON/Tailwind one-entry-object cases plus the round trip's palette-of-one, and that the
fixture test still passes – it contains no one-entry palette, so a mutation run that fails it
too means something wider broke than the rule under test.

**CLAUDE.md when this lands:** the "four `savePalette` overloads" bullet gains a fifth
door with its own reason.

### M31 – Import from a file, in any shape it was written

The Import menu becomes **"From Text…"** (unchanged) and **"From File…"**, accepting
`.css`, `.json`, `.javaScript`, plain text and the existing dynamic `.tokens` type. The
file's bytes are read, then `ImportTextSheet` opens **pre-filled** with them and a name
suggested from the filename.

**Routing through the sheet is the point, not a convenience.** `PaletteImport.detect`
already sends a token document to `parseDesignTokens`, which delegates to the same
`DesignTokenImport` decoder the file picker uses today – so token files keep working, CSS
files start working, and file import inherits the shape override, the storage-format
control, the destination picker and the preview instead of running a second, silent path.
It also means **M30's fix covers file imports for free** rather than two paths having to
agree about what a single color is. It also reconciles a vocabulary M30 left split:
`ProjectsPanel.importTokens` (the surviving file-picker path) still builds its confirmation
by counting *entries* through `Self.summary`, where the sheet now counts *kinds of group*
("2 colors and 1 palette"). The file path always produces a palette so its count is not
wrong, only phrased differently — and routing it through the sheet here retires
`Self.summary` and the divergence with it, rather than patching two summary builders to
agree.

It also fixes the reported confusion at the root rather than at the message: the app's own
JSON export has no `$value`, so `detect` routes it to `.json` and it imports, where today
it reaches the token decoder and is correctly refused.

**One honest loss, recorded rather than hidden:** `ProjectsPanel.summary`'s "Ignored N
tokens of other types" has no equivalent in `PaletteImport`'s designTokens path, which
keeps `skipped` but not `otherTypeCount`. Accepted – threading a count through
`ImportedPalette` for one shape's benefit is worse than the sentence is worth. The CLI's
`colorkit tokens` still reports it in full.

**The file read itself is a recorded manual check**, the same boundary as M17's read and
M8b's write: `fileImporter`/`NSOpenPanel` is a separate process XCUITest cannot drive, and
driving it from outside needs assistive access `osascript` does not have here. The tests
stop at asserting the control exists and is hittable; the decode is
`PaletteImportTests`/`DesignTokenImportTests` and the save is `ProjectStoreTests`.

**CLAUDE.md when this lands:** the M26 sentence describing the Import menu ("beside the
pre-existing token-file picker") no longer describes it.

### M32 – Rename what you saved

**Two differently-named library methods, because a loose color's name and a palette
entry's name are not the same kind of thing.** They both write `SavedColor.name`; that is
precisely why they must not share a door.

- `rename(_ color: SavedColor, to:)` – a **label**. Empty is legal; the tile falls back to
  `saved.text`, which is the display rule everywhere (`saved.name.isEmpty ? saved.text :
  saved.name`). It must **not** route through `cleaned(_:fallback:)`.
- `rekey(_ entry: SavedColor, to:)` – **syntax**. `SavedColor.name` is the export key for a
  palette entry (`paletteEntry: PaletteEntry(key: name, …)`), and keys become CSS custom
  properties *and* bare JavaScript object keys. Empty falls back to the entry's position
  (`1`, `2`, …), matching `paletteKeys(for:)`; the result is deduplicated against its
  siblings' **sanitized** keys with the same `-2`/`-3` loop `DesignTokenImport.keyed` and
  `ProjectLibrary.paletteKeys` already use – two entries sharing a key do not produce a
  duplicate property, they produce *one* property, and a color vanishes from the export
  with nothing in the document to say so.
- `rename(_ palette:to:)` **already exists and is finally wired** – it has been the
  library's only unwired mutation since M9. It keeps `cleaned(_:fallback: kind.title)`.

Three renames, three different empty-name answers, and that is the substance of the
milestone rather than an inconsistency to tidy: a project falls back to "Untitled
Project", a palette to its kind, a color to nothing at all, and a key to its position.

**The rekey field shows the resulting identifier live underneath it**, because
`cssIdentifier` is lossy: typing `Triad 2` yields `--brand-triad-2`, and that belongs in
front of the user before they commit rather than in an export they read later. This is the
same honesty M17 recorded when it noted that a name leaving through export does not return
through import unchanged.

**UI.** Palettes get an `Edit` button beside Export and Delete on `paletteRow`, identifier
`paletteEdit-\(index)` matching the row's convention. Loose colors fold the name into the
existing notes popover, retitled Edit – it already binds straight to the model and stamps
once via `library.touch(saved)` on disappear, so this is a field, not a mechanism. Palette
entries get their rekey field from the same popover, reached from `SwatchButton`'s menu on
the entry swatch – **which means `paletteRow`'s swatches gain a menu closure they do not
have today**, so `palette-\(index)-swatch-\(entryIndex)` becomes a menu-bearing element.
That is the exact shape CLAUDE.md's "a SwiftUI `Button` is one accessibility element" rule
warns about: the popover is presented from the row, not layered over the button, and
anything interactive that has to sit beside a swatch goes in a `ZStack` sibling rather
than an `.overlay` – the trap `savedColorTile`'s selection tick already documents.

**Tests.** `ProjectStoreTests` for all three, including a rekey collision (two entries
renamed onto one key must not collapse), the asymmetric empty-name fallbacks, and a
round-trip claim that a rekeyed entry exports under its new key. The rekey dedupe is the
one worth a mutation: remove the suffix loop and confirm a color disappears from the
rendered document.

**CLAUDE.md when this lands:** the "`ProjectLibrary.rename(_ palette:to:)` is still the
library's only unwired mutation" bullet is retired, and `rekey` is added to the list of
places that decide a palette key alongside `ExportOptions.javaScriptKey` and
`cssIdentifier`.

### M33 – Import without a project first

A global Import button in both of the places the feature is currently invisible from: in
`emptyState`'s actions beside New Project, and in its own row above the project header
once projects exist. **One identifier, `projectsImport`, used in both branches** – safe for
the reason `projectsNew` already appears twice at `ProjectsPanel.swift:170` and `:194`:
the branches are mutually exclusive. Its own row, **not** a fifth control in the
`LabeledContent("Project")` HStack, which already carries four; crowding it is the tool
switcher's overflow lesson waiting to be re-learned at a different scale.

Three mechanical blockers, each of which silently produces a button that does nothing:

- The `.sheet(isPresented: $isImportingText)` hangs off `saveControls(_:)`, which only
  renders when a project exists **and** is selected. It moves to `body` level.
- `ImportTextSheet.onAppear` hardcodes `creatingNewProject = projects.isEmpty`. The global
  entry point needs a `preferringNewProject: Bool` so it defaults to New Project even when
  projects exist – "defaults to creating a new project from the content" is the requested
  behavior.
- `canImport` requires a non-empty `newProjectName` when creating, so the global path would
  open with Import disabled and nothing saying why. Prefill `newProjectName` from the
  parsed `detectedName`, using the **reseed-until-touched** discipline already in
  `shapeAndNameControls` – and `initial: true` on the `onChange` for the reason recorded
  there, since the control does not exist until the first successful parse.

**Testing hazard, not hypothetical:** new controls push content down inside a `ScrollView`,
and a swatch below the window's bottom edge produces the "never became hittable" failure
with an all-`Disabled` tree – the *second* cause documented in CLAUDE.md's Testing section
(a window shorter than its content), which retrying does not clear and which the app's
own `.defaultSize(width: 620, height: 700)` makes reachable on a fresh bundle.

### M34 – Design token export, and saying which one

The direction M17 left out, plus the transparency that would have made its absence
legible. Two halves of one milestone: without the naming work the shape ships and the
confusion that prompted it stays possible.

#### The seventh shape

`ExportShape.designTokens = "design-tokens"`, writing the W3C Design Tokens (DTCG) format
the app already reads. **The color math is the identity**, which is the whole reason this
is a shape and not a subsystem: DTCG `components` are CSS Color 4's *number* forms and this
app stores number forms, so there is no arithmetic and no range table – the correction M17
recorded against its own plan ("`fullScale` is a precision hint, not a bound") cuts the
same way in reverse. A writer picks the space, emits the three stored components, and emits
`alpha` when it is not 1. The work is shape plumbing.

Palettes become groups, loose colors become top-level tokens, and `$type: "color"` is
declared **once at the document root** rather than on every token – idiomatic, and
materially smaller on an eleven-stop ramp.

**That this app's own decoder honors a root-level `$type` was checked before the shape was
planned around it, not assumed.** It is the plan's riskiest assumption – if the root did
not inherit, the writer would have to stamp `$type` on every token (larger documents) or
M17's decoder would need changing (scope creep into a milestone that is done), and either
answer arrives after the writer is built. `DesignTokenImport.collect` is called as
`collect(root, path: [], inheritedType: nil, …)`, and the root node has no `$value`, so it
takes the group branch at `DesignTokens.swift:269` – `node["$type"] as? String ??
inheritedType` – and threads the root's type into every child. The root **is** a group by
construction rather than by analogy, and the `where !name.hasPrefix("$")` filter on the
recursion is what keeps `$type` itself from being read as a token. No branch point
remains.

```json
{
  "$type": "color",
  "Greyscale": {
    "50":  { "$value": { "colorSpace": "oklch", "components": [0.97, 0, 0] } },
    "100": { "$value": { "colorSpace": "oklch", "components": [0.9068, 0, 0] } }
  },
  "Primary-Base": { "$value": { "colorSpace": "oklch", "components": [0.5236, 0.1839, 309.99] } }
}
```

**Each token is written in its own color's space, never in one format across the
document.** This is the same rule `savePalette(importing tokens:)` and `colorkit tokens`'
default listing already keep – a token's `colorSpace` is authored information, like a typed
`rebeccapurple` – and it is what makes the round trip an identity on components rather than
a canonicalization. It is also why `usesFormat` is **false** for this shape: a
`CSSOutputFormat` names a CSS spelling and a `$value` has none. That is a *second* reason
for a `false` there, different in kind from `p3WithFallback`'s (which hides a control that
would be actively harmful); the flag's doc comment needs to say so or it reads as one rule
with two instances.

**No `hex` fallback is emitted.** The field is optional in the format and this app's own
decoder reads it *only* for a `colorSpace` it does not recognize – and every space this app
writes is one the spec defines, so it would never be read on the way back. Emitting it
would put a rounded sRGB approximation beside exact components for precisely the wide-gamut
colors that motivate an OKLCH pipeline: the p3WithFallback hex-fallback trap, in a format
that does not need the fallback at all.

**Three things a seventh case ripples into, two of which do not break the way they look
like they will:**

- `fileExtension` answers `json`, so `contentTypesAreDistinct` still finds three types and
  `writableContentTypes.count == 3` still holds – designTokens shares JSON's `UTType`.
  Neither test needs relaxing, which is worth stating because both look like they must.
- `suggestedFilename` should propose `brand.tokens.json`, the format's convention, via a
  new per-shape stem suffix (empty for every other shape). `ProjectsPanel.paletteName(for:)`
  **already strips a `.tokens` stem** on the way back in, so the filename round trip closes
  without touching the import side – a small piece of evidence that M17 anticipated this
  direction.
- `mappedCountFormat` currently answers `shape.usesFormat ? format : Self.fallbackFormat`,
  and hex is the wrong answer here: a token file never gamut-maps, so the badge would count
  out-of-sRGB colors and claim they were brought into gamut, which is **false of every one
  of them**. It becomes `CSSOutputFormat?`, `nil` meaning "this shape does not map";
  `ColorStore.exportGamutMappedCount` returns 0 for `nil` and `ExportPanel` hides the badge.
  The count and the copy stay one decision, as CLAUDE.md requires.

**Group naming needs a second sanitizer, and `resolvedGroups` is where it goes.** DTCG
forbids `.`, `{` and `}` in a name and reserves a leading `$`, but it permits spaces and
case – so `cssIdentifier` would flatten `Body Text Base` to `body-text-base` and throw away
a name the format can carry verbatim. `resolvedGroups` gains a naming parameter defaulting
to `cssIdentifier`, so the uniquing loop stays single and the naming rule becomes per shape;
`render(_ groups:)` passes `shape`'s. Entry keys take the same treatment – the token writer
builds nested JSON and never reaches `propertyName`.

**`isWebFriendly` is false**, on the same structural grounds as `p3WithFallback` rather
than a per-export gamut check: a token file exists to carry authored color spaces between
tools, and web-friendly mode is about what can be hand-typed into a stylesheet. A judgment
call, recorded as one.

**CLI:** one row in `Names.shapes` (`("design-tokens", .designTokens)`), which makes
`colorkit tokens file.json --shape design-tokens` a token-file round trip through the
tool. The existing test requiring every shape name to round-trip and be lowercase covers
the new row.

**Tests.** The oracle is this app's own importer, exactly as `Export/`'s oracle is its own
parser: render, feed the document back through `DesignTokenImport.decode`, and require the
colors to survive **in their own spaces** – not merely to parse. Both cardinalities, since
the lone-color and scale branches differ. One honest limitation to assert rather than
paper over: keys come back through `cssIdentifier`, so a group named `Body Text Base`
returns as `Body-Text-Base` – the name is *not* round-trip-identical, the colors are.

#### Saying which format, everywhere it appears

The reported confusion was not only the missing shape; it was that nothing anywhere names
the format. Every surface that mentions tokens says **"Design tokens (DTCG)"**:

- `ExportShape.designTokens.title` and its `summary`, in `ExportPresentation.swift` –
  the summary naming what reads it ("what Figma and Style Dictionary consume") the way the
  Tailwind pair's summaries name what decides between them.
- `ImportShape.designTokens.title` in `ImportTextSheet.swift`, currently "Design tokens".
- `ImportTextSheet`'s paste-box hint, currently "a design token file".
- `DesignTokenError.noTokens`'s message – the sentence in the report. It stays in ColorCore
  (error text there is established: `TokenSkipReason.message`, `PaletteImportError.message`)
  and names the format and the alternative rather than only what is absent. Note that after
  M31 this error is much harder to reach at all, since a JSON document without `$value`
  routes to the `json` shape; the wording is the belt, M31 is the braces.
- `colorkit tokens`' usage text, and `--shape design-tokens` in `shapeList`.
- README's feature list, which is the only place a reader outside the app could have
  learned the direction was missing.

**CLAUDE.md when this lands:** the `Names.shapes` table bullet gains a seventh row; the
`usesFormat` bullet gains its second, differently-reasoned `false`; the mapped-count bullet
becomes an optional format; the M20 `render` bullet notes `resolvedGroups`' naming
parameter; and the intro paragraph's "six document shapes" becomes seven.

### Files touched, by area (M30–M34)

- **ColorCore/Import** – `PaletteImport.swift` (`ImportedGroup.soleColor`), M34's error
  wording in `DesignTokens.swift`.
- **ColorCore/Export** – `ColorExport.swift`: the seventh `ExportShape` case and its four
  capability flags, `fileExtension`, the filename stem suffix, `mappedCountFormat` becoming
  optional, `resolvedGroups`' naming parameter, and the token writer itself.
- **ColorKit/Persistence** – `ProjectLibrary.swift`: `saveColor(importing:)`,
  `rename(_ color:to:)`, `rekey(_:to:)`.
- **ColorKit/Features/Projects** – `ProjectsPanel.swift` (the global Import button, the
  file importer, the Edit button, the retitled popover), `ImportTextSheet.swift`
  (`preferringNewProject`, the name prefill, the colors/palettes preview split).
- **ColorKit/Features/Export** – `ExportPresentation.swift` (title, summary, `mappedNote`),
  `ExportPanel.swift` (badge hidden on a `nil` count format).
- **ColorKitCLI** – `Names.swift` (one row), `PaletteCommands.swift` (usage text).
- **Tests** – `ColorKitTests/Fixtures/project-export-p3-with-fallback.css` (already in the
  tree; a real export, the first fixture here that is not machine-generated),
  `PaletteImportTests` (the sole-color rule, the fixture reading, the project round trip),
  `ProjectStoreTests` (three renames, the rekey collision, the imported loose color),
  `ExportTests` (the token shape at both cardinalities, the DTCG naming rule),
  `ExportStoreTests` (the optional mapped-count format), `ProjectsSmokeTests` (the global
  Import button, the Edit button), `ColorKitCLITests` (the new shape name).

## Verification

**A feature reached through a system loupe or a global chord has links no test can touch**, and they fail independently – so check them separately rather than as one gesture. For M4 that was: (1) does the menu bar show the chord, proving the OS accepted the registration and a scene's `.task` fired; (2) does the chord raise the loupe from *another* app, proving the key is captured and the C callback reaches the main actor; (3) does the picked color reach the field and the clipboard, proving the sandbox and the bridge. All three passed. Everything either side of them is covered by [ScreenSamplerTests](ColorKitTests/ScreenSamplerTests.swift) and [GlobalHotKeyTests](ColorKitTests/GlobalHotKeyTests.swift).

Per milestone:

- **M1/M2 (core):** `xcodebuild test` – parameterized tests against the colorjs.io fixture; round-trip idempotency; gamut-mapping boundary cases (`L≥1` → white, `L≤0` → black, in-gamut colors unchanged).
- **M5:** two different standards of proof, because the oracle only covers one of them. **APCA** is validated against colorjs.io directly (`node Tools/generate-contrast-fixtures.mjs`) at 1e-9, both polarities – real external validation, since the Swift is transcribed from that package. **WCAG** cannot be, because colorjs.io implements a different definition; correctness there comes from anchors that hold under any variant (`#000` on `#fff` = 21:1, a color against itself = 1:1) plus one pair chosen to *disagree* between the definitions, asserted both ways round.
- **M6:** the plane is a `Canvas`, so nothing about the pixels reaches the accessibility tree – the numeric readout is the assertable surface, and the boundary figures it prints were checked against the oracle from the panel's own screenshots. See [PickerSmokeTests](ColorKitUITests/PickerSmokeTests.swift).
- **M7:** the transforms have no oracle, so ColorCore asserts their defining properties and every load-bearing one was confirmed by mutation (see the milestone above). What *can* be cross-checked is the pipeline end to end, and was: the OKLCH string the panel wrote after adopting a triad member agrees with colorjs.io to ten decimals. See [TransformSmokeTests](ColorKitUITests/TransformSmokeTests.swift), where each derived swatch is a button labelled with its own CSS – the only handle a test has on a row of colored rectangles, and the thing a bare swatch owes VoiceOver anyway.
- **M8:** the only milestone whose output is *text a machine will read*, so the parser is the oracle – [ExportTests](ColorKitTests/ExportTests.swift) round-trips every exportable format back through `CSSColorParser` and requires the color to survive. Syntax is pinned with exact strings, and the identifier rules (JavaScript key quoting, CSS sanitizing) have their own parameterized cases, because a config that will not load is the failure mode and it is invisible from inside Swift. The source-to-entries mapping is asserted on `ColorStore` rather than through the UI – see [ExportStoreTests](ColorKitTests/ExportStoreTests.swift) – which is why that mapping lives on the store. [ExportSmokeTests](ColorKitUITests/ExportSmokeTests.swift) covers only what a running app can show: that the controls reach the document. It never clicks Copy, for the reason no test here touches the pasteboard.
- **M9:** three levels, split on what each can actually answer. [ColorRecordTests](ColorKitTests/ColorRecordTests.swift) takes the mapping with no container in sight – every space, the `none` mask, and the stored components agreeing with the stored spelling. [ProjectStoreTests](ColorKitTests/ProjectStoreTests.swift) takes what only SwiftData can answer, opening with the assertion that the container builds at all, because inverses are resolved there rather than at compile time. [ProjectsSmokeTests](ColorKitUITests/ProjectsSmokeTests.swift) takes the round trip through a running app – and launches every one with `UITestInMemoryStore`, because the alternative is writing into the real library. The end-to-end cross-check is the ramp in the status note: saved, reloaded, exported, and identical to the value M8 checked against colorjs.io.
- **M10:** the milestone has no behavior to test, so the test suite proves nothing beyond "still compiles". The real check is that **re-running all four generators reproduces every generated Swift file byte-for-byte** – that is what shows the output paths moved with the sources rather than quietly writing somewhere stale. (`cvd-vectors.json` is the exception and stays as committed; see the libm note in CLAUDE.md.)
- **M11:** the store rules are in [ProjectStoreTests](ColorKitTests/ProjectStoreTests.swift), each confirmed against a mutation of the rule it covers – dropping the move's offset discount, skipping the dense renumber, disabling key dedup, re-deriving stored text, and moving colors instead of copying them all fail the suite. Reordering is checked across a real store close and reopen, since an in-memory container proves only that the objects in hand were mutated. [ProjectsSmokeTests](ColorKitUITests/ProjectsSmokeTests.swift) covers the wiring – **through the menu commands, not the drag**, because XCUITest cannot start a dragging session and a drag-driven test would fail whether the feature worked or not. **The drag gesture itself is not covered by any automated test and wants a human to try it once.**
- **M12:** [MissingComponentTests](ColorKitTests/MissingComponentTests.swift), and the standard of proof is the spec rather than a reference implementation – colorjs.io resolves `none` on conversion, so it cannot answer this at all. Each test names the spec example or role-table property it encodes, and all five load-bearing rules were confirmed by mutation (see the milestone). The spec's *printed* conversions are asserted as roundings, not with a tolerance, because that is the claim actually available from a displayed figure.
- **M13:** [CalcTests](ColorKitTests/CalcTests.swift), hand-written throughout because there is no oracle – colorjs.io rejects `rgb(calc(10 + 20) 0 0)` outright with "Expected 3 coordinates … got 5", so `parse-vectors.json` is untouched. The arithmetic is checkable by inspection; what is not obvious from reading the code is pinned by five mutations, each failing only what it should. Stripping precedence fails one test, dropping the `±` type check one, ignoring leftover tokens two, and hoisting the tokenizer's operator rules above the number scanner fails the *curated fixture* – `rgb(+128 0 0)` – plus the numeric-edge-forms test. The fifth is the discriminating one: letting a calc body's slash escape to separator logic fails every test whose input contains a slash and **no test without one**, which is the sharpest available statement that consuming the body as a unit is what resolves the ambiguity. A first, blunter version of that mutation (not consuming the body at all) failed fifteen tests and proved nothing except that the feature was off. A sixth mutation covers the seam the other five do not touch: dropping `min` from `UnsupportedFunctions.names` makes `rgb(calc(min(1, 2) * 2) 0 0)` come back `calcUnsupportedSyntax("min(")` instead of naming the function, which is the observable proof that the pre-tokenize check still runs *before* calc consumption. `firstCalled` scans its own list rather than the input, so the case is checked with a first-listed name (`var`) and a later one (`min`) both.
- **M14:** [RelativeColorTests](ColorKitTests/RelativeColorTests.swift), hand-written for a *third* distinct no-oracle reason – colorjs.io 0.7.0 has no relative color syntax at all, so every form comes back "Expected 3 coordinates … got 4". (M13's reason was that it rejects `calc()`; M12's was that it resolves `none` on conversion and so cannot be asked the question.) The conversions underneath are oracle-validated already and are deliberately not re-tested. **Eight mutations, and the most useful one passed.** Seven failed exactly what they should – deriving the keyword table from roles, ignoring `numberScale`, dropping carry-forward, collapsing either half of the `none` rule, allowing legacy commas, and removing the alpha clamp. The eighth, replacing the origin's depth counting with "first close paren wins", **passed the entire suite**, which is the finding worth carrying: *a mutation that survives means the test set is incomplete, not that the rule is safe.* The obvious nesting cases do not discriminate – in `rgb(from color(display-p3 1 0 0) r g b)` the first `)` already is the right one, and `rgb(from rgb(from red r g b) r g b)` is still one level deep because `from red` opens nothing. Depth counting only earns its keep when the origin's function contains another function, so a case was added for the cheapest one, a `calc()` inside the origin, and the mutation now fails with `wrongComponentCount(got: 1)`. Two assertions are deliberately loose and say so in place: white's OKLab lightness is `1.0000000000000002` and an sRGB → OKLCh → sRGB round trip returns red as the same, so both claims are checked by discrimination – the competing readings are off by ~100× and ~1 – rather than by an equality the conversion never promised.
- **M15:** [ColorMixTests](ColorKitTests/ColorMixTests.swift), split on what each half can be held to. The **numbers** are generated – 1,760 vectors over fifteen color pairs, all fourteen interpolation spaces, four hue arcs and five positions along each mix – with the two oracle corrections above baked into the generator. The **grammar and the percentage rules** are hand-written, because colorjs.io can compute a mix and cannot parse one, which is the fourth distinct no-oracle reason this plan has recorded. Three assertions carry more than their length suggests: `null` in a recorded component is checked against our *missing mask* rather than against a number, which is a claim about §12.2's substitution rather than about arithmetic; the hue-arc test runs the same pair in both directions, because for any pair the four methods only ever produce two answers and it is *which method gets which* that proves direction is honoured rather than length; and the premultiplication case is stated as the wrong answer it discriminates against, `rgb(50% 0% 50%)` versus `rgb(33.3% 0% 66.7%)`. The tolerance is 1e-8 rather than the conversions' 1e-9, and says why in place: un-premultiplying divides by an interpolated alpha as low as 0.1, multiplying any upstream difference by up to ten. **Eleven mutations, all eleven killed, two of them only after three tests were added** – the survey found a shipped bug in the premultiplication guard plus two exemptions nothing was holding, and the milestone note above records all three. The failure sets are tight: the alpha shortfall is owned by two tests, the powerless marking by three, carry-forward by one, the hue's premultiplication exemption by the recorded vectors alone, and gamut-mapping the result by four – including `The ends of the mix are the colors themselves`, which is the cheapest possible statement that a mix returns its endpoints untouched.
- **M16:** the same oracle M8 has – this app's own parser – applied to *both* blocks at once, since `propertyValues(in:)` already trims before matching `--…;` and so returns the media block's lines unchanged. The discriminating input is a color **outside sRGB and inside P3**: asserting only that every value parses would pass a document that wrote the same rounded hex twice, so the test requires the fallback to come back inside sRGB *and* the override to come back as the color that went in. The syntax – the braces, the query, the blank line between blocks – is pinned with an exact string, while the P3 *values* in it are computed from the serializer rather than transcribed, because those conversions are oracle-validated in the fixture suite and re-typing them would only test whether they were copied correctly. **Four mutations, all four killed, and each failure set is tight**: a per-entry conditional media block fails four tests, a fallback honoring `options.format` fails three, desynchronized property names fail three, and the badge measured against the P3 block instead of the fallback fails exactly one – the store test written for that decision. One existing test had to change and the reason is worth keeping: `formattingReachesEveryShape` is parameterized over `allCases` and asserts a precision-sensitive string, so it now asks each shape for the format it *actually writes* – and for this shape that has to be the **wide** one, because **hex is precision-invariant**. Pointing it at the fallback would have left the test unable to fail, and its own `lossless != coarse` blindness guard could not have caught that, since the guard is computed from whatever format the test picks. That in turn left the *fallback's* `formatting` pass-through unpinned – hardcoding `.default` there would have survived the whole file – so a second test asserts it through hex casing, the cheapest setting hex does observe. **The last test added is the one that found a shipped defect**, and it found it by failing first: `p3OverrideIsNotAnExactnessPromise` was written against `.lossless` and reported the override *un*mapped, because that constant is `.preserve`. The override is not hex – it is not `cannotRepresentOutOfGamut` – so it has no fixed answer at all and follows the **app-wide gamut policy**, which is `.map` in the panel. Both policies are now asserted, because it is the dependence rather than either instance that makes an exactness claim unsafe.
- **M17:** [DesignTokenImportTests](ColorKitTests/DesignTokenImportTests.swift) for the decoder and [ProjectStoreTests](ColorKitTests/ProjectStoreTests.swift) for the path through a container. **A fifth distinct no-oracle reason, and the simplest one yet**: colorjs.io parses CSS, and a design token's `$value` is a JSON object rather than a CSS string, so there is nothing to ask it. The Color module's own documented shapes are the fixtures, written inline rather than in fixture files – the generated vector sets earn their own files by being thousands of numbers, where these are five lines of JSON apiece and only read as the spec examples they are when they sit beside the assertion. **Ten mutations, all ten killed, and every failure set is tight**: uniquing on the raw path instead of the sanitized key fails one test, ignoring a resolved reference's type one, letting `hex` rescue broken components one, sorting names as text two (both the ordering claims), dropping the `none` mask one, dropping the alpha clamp one, spelling imports `oklch()` one, keying on a token's leaf name instead of its whole path three (every claim about keys), and ignoring a token's own `$type` one – that last mutation being the one that *found* a gap, since nothing had pinned the first arm of the precedence chain until it was written. The cycle-detection mutation is the odd one out and worth its own sentence: removing the visited set fails the suite **without reporting a single test**, because the unbounded recursion takes the test process down with it. That is the shape of the bug the visited set prevents, and it is why the rule is not an optimization. Two claims are asserted by discrimination rather than by equality alone – an sRGB `[1, 0, 0]` is checked against the `1/255` it would be under `rgb()`'s scale, and the `hex` fallback is checked with a *known* space and broken components, where a fallback that fired would look perfectly plausible. One test deliberately does *not* isolate a rule: `awholeFileImports` takes an alias, two color spaces, a description and a dimension token in one document, because the per-rule tests are diagnostic precisely by testing one thing at a time and a real token file is never one thing. It asserts the three counts together, since those are what the panel reports and "imported 4, ignored 1" is only true if all three are – and it is in the failure set of the reference-type mutation, so it discriminates rather than decorates.
- **M17, the part no test reaches – and it passed.** This is the app's only file read, so it is the only place a **sandbox** denial can happen, and every test above loads its JSON from a string in the test bundle: that exercises the decoder and nothing about the sandbox. Same shape as M4's loupe and global chord – links a test cannot touch, wanting a named manual check instead. The check is *choose a token file in `~/Downloads` through the Import button and confirm a palette appears*, and it was run on the built app: four swatches under an `Imported` badge, with the summary reading `Imported 4 colors from colorkit-m17-check.tokens.json. Ignored 1 token of other types.` So the powerbox URL reads under `ENABLE_USER_SELECTED_FILES = readonly` with the security-scoped claim, which was the open question. **The screenshot happens to discriminate three separate rules, which is why it is worth more than a pass**: the second and fourth swatches are the *same blue*, so `semantic.primary` – a token with no `$type` of its own – resolved through its alias to `brand.500` and took both its value and its type, the rule a filter-then-resolve design drops silently; the order is `50, 500, 900, primary`, so numeric sorting held on real data where alphabetical would have filed `500` ahead of `50`; and the navy is the `display-p3` token, so the wide-gamut path rendered as well as the sRGB ones. XCUITest cannot drive `NSOpenPanel`, exactly as it cannot start a dragging session, so [ProjectsSmokeTests](ColorKitUITests/ProjectsSmokeTests.swift) stops at asserting the control reached the panel and is hittable – a test that clicked it would fail whether the feature worked or not. The panel's error copy is built for this: the open-panel dismissal, the read, the decode, "readable file with nothing importable in it", and the save are five outcomes with five different sentences, because a denial reported as "no color tokens in that file" would be undiagnosable.
- **M18:** [ColorKitCLITests](ColorKitCLITests/CommandTests.swift), and **the oracle is this app's own parser** – the same standard `Export/` is held to and for the same reason: the CLI's output is text a machine will read back. So the discriminating assertion is that a printed value survives `CSSColorParser`, applied to all six document shapes at both cardinalities and to every listing; exact strings are kept for *syntax* (exit codes, which stream a message lands on, `:root {`) and are wrong for anything editorial. Three claims are asserted as totality over an `allCases` rather than by example, because each is a table that a change in ColorCore can silently outgrow: every catalog format has a CLI name and the name inverts, every export shape has one that is lowercase and round-trips, and every command in the `--help` listing dispatches to something. **Twelve mutations, all twelve killed, and every failure set is tight** – collapsing the usage and failure exit codes fails one test, routing diagnostics to stdout five, accepting an unknown option as a positional one, accepting an inert `--format` one, uniquing export keys on the raw path instead of the sanitized key one, ignoring `mappedCountFormat` one, dropping `solve`'s read-back check two, canonicalizing the token listing's spelling one, short-circuiting `--help` before argument scanning one, deriving shape names from raw values three, dropping the listing's mapped note three, and dropping the `convert` table's mapped marker one. **The value extractor took two attempts and the first one is the lesson**: reading "everything after the first space" agreed with three output shapes and silently handed the other five a value with punctuation attached, which reads exactly like a broken serializer – so it now matches structurally, on a `#` run or a *color* function name followed by a balanced paren group. That last qualifier is not decoration: `tailwind-config` opens with `/** @type {import('tailwindcss').Config} */`, and `import(…)` satisfies every part of the shape rule but the name. **Three findings came out of the suite failing first.** The ramp's in-gamut assertion has to read the value at full precision, because a stop on the boundary rounds outward at four decimals and the test would otherwise be measuring the serializer; the mapped-note test had to move from `ramp` to `harmony`, because every ramp stop is already in gamut and asking a ramp for a mapped value tests nothing; and `solve`'s guarantee turned out not to survive serialization at all, which is the milestone note above.
- **M19:** [PreferencesTests](ColorKitTests/PreferencesTests.swift) – every field round-trips through encode/decode with each field changed from its default (including `exportFormat: .color(.displayP3)`, the one case that exercises `CSSOutputFormat`'s hand-written conformance rather than a plain raw value), decoding garbage yields defaults, and the negative-`recentLimit` crash is pinned as a regression after being reproduced directly (`Fatal error: Can't remove more items from a collection than it contains`, with the clamp removed). `withObservationTracking` confirms `ColorStore.preferences`'s getter reaches through both `formatOptions` and `exportOptions` rather than only the top level. **Confirmed the mutation directly**: dropping `webFriendly` from `CodingKeys` failed exactly the two tests that could tell. The quit-and-relaunch check is manual, in the shape of M8b's write and M17's read – see the M19 section above for what was found.
- **M20:** [GroupedExportTests](ColorKitTests/ExportTests.swift) and [StagedProjectTests](ColorKitTests/ExportStoreTests.swift). The single-group case is not re-pinned as a new assertion – it would be true by construction, since the one-list `render` is now a one-line call into the grouped renderer – so the discriminating check is that every exact string in the *pre-existing* `ExportShapeTests` and `ExportRoundTripTests` still passes unchanged. **That check turned out to be uneven across shapes**: `declaration` and the three shapes sharing `groupedPropertyLines` each guard their own header independently, and `tailwindTheme`'s pre-existing test (`.contains`/`.hasPrefix`/`.hasSuffix`) does not notice an extra comment appearing, so a dedicated single-group `tailwindTheme` test was added before that shape's byte-identity claim had anywhere to fail. Two-group documents are pinned exactly for `declaration`, `customProperties`, `tailwindTheme`, `json` and `tailwindConfig` (the latter two at both per-group cardinalities in one document – a lone-color group beside a scale), plus a multi-group round trip through `CSSColorParser`, `p3WithFallback` covering every group in both blocks, and a test that `options.name` moves a grouped document's filename and never its content. **Six mutations, all six caught by the intended test and no other**: uniquing against the raw name instead of the sanitized one fails `collidingGroupNamesStaySeparate`; deleting the suffix loop's `while` (always appending a bare `-2`) fails only `thirdCollisionSkipsTakenSuffix`, not the simpler two-way collision test – proof the loop itself is exercised, not just the branch that enters it; truncating `p3WithFallback`'s wide block to the first group fails `p3WithFallbackCoversEveryGroup`; forcing `groupedPropertyLines`'s header unconditionally fails three pre-existing tests and the new single-group `tailwindTheme` one, none of the new two-group ones; and both directions of `declaration`'s separate header guard were checked, one against a new two-group test and the other against two pre-existing single-group ones. [ProjectsSmokeTests](ColorKitUITests/ProjectsSmokeTests.swift) adds the end-to-end run – a ramp and a loose color, saved separately, exported together under the project's own groups – **and asserts the Source picker's "Project" segment is itself hittable**, not merely that the right document reached the field; the pre-existing `ExportSmokeTests` never click that segment, so they would not have caught a sixth entry rendering unusably, and this is the test that actually closes that question rather than the one first assumed to.
- **M21 (done):** met as stated – `TransformSmokeTests`' pattern extended to a CVD swatch (`CVDSmokeTests.testClickingTheSimulatedSwatchAdoptsIt`) and a palette tile (an extension to `ProjectsSmokeTests.testSavingASelectionMakesAPalette`); the authored-text claim was already covered store-side by the pre-existing `usingARecentRestoresItsText`, so no duplicate was added, and the new `adoptBackgroundWritesBackground` covers the one genuinely new store seam, `adoptBackground(_:preferring:)`. Two regressions were caught against the *running app*, not by a written test predicting them in advance – see the M21 retrospective above.
- **M22 (done):** `webFriendly` asserted as a subset of `catalog`, plus that every
  member is sRGB-expressible and that `color(srgb …)` is excluded despite fitting –
  the discriminating case the table exists for. Both filtered enumeration sites
  (`FormatSection.webFriendly`, `CSSOutputFormat.webFriendlyExportable`) assert they
  partition/subset correctly and that emptied sections are dropped, not merely hidden
  empty. The third named in the plan, `ColorSpace.allCases`, was **not** filtered –
  see the retrospective above for why the plan's own two sections disagree and which
  one won. A harmony's disagreement between `gamut: .srgb` and the unclamped default
  is asserted explicitly, re-using the same base color as the pre-existing
  never-gamut-mapped test. All three named mutations hold: the `color(srgb …)` test
  fails if the table is derived from `if case .color`; `adoptClampsWideGamutUnderWebFriendly`
  fails if the `spelling(preferring:)` guard is dropped; and there is no mix-picker
  restriction to mutate, because M22 hides the section instead (the plan's own
  reasoning for why that mutation matters is what settled the contradiction). One
  mutation risk the plan did not name and testing caught by construction:
  `ContrastSolver`'s gamut clamp, if applied to the bisection's answer instead of
  inside the search, would make `gamutClampedSolutionsStillMeetTheTarget` fail –
  built around a chroma (`0.35`) no sRGB lightness can hold, specifically so an
  after-the-fact clamp cannot pass by accident. The P3-display sample and the
  Settings Toggle round trip are recorded manual checks – see the M22 retrospective.
- **M23 (done):** `loweringRecentLimitTruncates` fails against the pre-M23 plain `var`
  (confirmed by reverting the `didSet` and re-running just that test) and passes with
  it; `preferencesObservesEveryPersistedField`'s new `recentLimit` mutation confirms
  the property observer didn't drop the field out of `@Observable` tracking, a
  compile-clean failure mode the other three mutations in that test can't catch.
  `testReleasingTheDragFilesARecentWithoutTheOldDebounceDelay` fails when a 1-second
  `Task.sleep` is reintroduced before `store.remember()` in the plane's `onEnded`
  (confirmed the same way), and passes at the real fix. `RecentsSmokeTests` covers the
  row itself: a submit-then-click round trip through the authored text, and Clear
  emptying the list and hiding itself.
- **M24 (done):** the header swatch hittable, opening it reveals `compactPickerPlane`
  (not `pickerPlane` – see the M24 retrospective above for why the identifier differs
  from what this section originally said to check), and dragging inside it changes
  `colorInput`, waited on hittability rather than existence. Extended past the
  standard stated in advance: the plane and its popover copy coexist on screen without
  an ambiguous query, reopening the popover reseeds from whatever the field currently
  holds, and the empty-state swatch's `.contentShape` fix is pinned by a mutation
  (`CompactPickerSmokeTests.testTheEmptyStateSwatchOpensThePopoverToo` fails without
  it). The web-friendly clamp, previously a recorded manual check, is now two
  `PickerStateTests` cases on `PickerState.committing(_:in:)`, each confirmed against a
  mutation of the rule it covers – a third case, aimed at the method's write-ordering
  *rationale* rather than its clamp, was found on review to be unable to fail no
  matter the ordering (a plain local `var` has no `@Binding` indirection to race) and
  was rewritten to pin the real, narrower claim it can actually observe. Same
  discipline applied to `.id(pickerSession)`: measured with it removed rather than
  assumed necessary, and the reopen-reseed test passes either way, because macOS
  already tears a popover's content down on dismiss. A fifth check found a real,
  previously-untested divergence rather than confirming one already guarded against:
  the Pick tab and the popover disagreeing about `PickerMode` once both could write
  `store.pickerMode`, fixed with `.onChange(of: store.pickerMode)` on both hosts and
  confirmed by mutation on the reachable direction; the unreachable direction was
  written, found to fail on a platform limitation (a transient popover holds
  key-window status, so the window behind it cannot be clicked into while it is
  shown), and deleted rather than left red.
- **M25 (done):** every catalog format round-trips `rebeccapurple` when chosen from the
  menu (`respellRoundTripsEveryFormat`, parameterized over `CSSOutputFormat.catalog`,
  including `.keyword` since the base color is itself nameable), and the honest
  exception is pinned separately – re-spelling a wide-gamut color into hex maps it
  rather than silently substituting `color(display-p3 …)` the way `adopt` would. The
  control is queried as a `menuButton`
  (`NotationMenuSmokeTests.testTheNotationControlExistsAsAMenuButton`), and choosing
  `rgb()` rewrites `colorInput` to the value `colorkit convert` was asked to confirm
  first. **Four mutations, four caught, one only after a fix**: dropping the
  `webFriendly` clamp and routing through `adopt`'s `spelling(preferring:)` were each
  caught by exactly the test built to catch them and nothing else; reading at
  `formatOptions` instead of `.lossless` was caught by its own test and, incidentally,
  by ten of the seventeen round-trip cases; and falling back to hex instead of no-oping
  when a format can't name the color passed the *first* version of its test, because
  that test started from `#3b82f6`, whose hex spelling is textually identical to what
  was typed – rewritten against `rgb(59 130 246)`, whose hex fallback reads differently
  from its own text, the same mutation fails. See the M25 section above for the full
  account.
- **M26:** [PaletteImportTests](ColorKitTests/PaletteImportTests.swift) (20
  tests) – shape detection for every shape including ordering (`@theme` ahead of the
  JSON/declaration fallbacks), the `primary`/`primar` segment-wise vs. character-wise
  discriminator, the round trip through every export shape at both cardinalities (a
  lone color, a two-group document) plus a sanitized-name case, the `p3WithFallback`
  override-vs-fallback discriminator, a malformed value skipped without losing its
  neighbours, `looseColors`' paren-depth-aware splitting, and `designTokens` delegation
  including a broken token skipped without losing a good one alongside it. **Four
  mutations verified by hand – ignoring headers, character-wise prefix, reading
  `p3WithFallback`'s hex block, reordering `detect()`'s `@media`/`:root` checks – each
  failed exactly its own test and no other.**
  [ProjectStoreTests](ColorKitTests/ProjectStoreTests.swift) (2 tests) pins the
  fourth `savePalette` overload's stored text as the literal pasted string rather than a
  re-derivation – checked by mutation against routing through
  `.derived(_:preferring: .oklch)`, which both tests catch – and that the stored text
  reparses to the stored components, the same check every other stored spelling in this
  app carries. [ProjectsSmokeTests](ColorKitUITests/ProjectsSmokeTests.swift)
  covers the Import menu offering both paths without clicking the un-drivable one
  (`NSOpenPanel`), and a full paste-to-palette run through `app.sheets` – typing a
  two-property `:root` block into the `textViews` query, confirming, and asserting a
  palette row and the import summary both appear. 505 unit tests (483 before M26), 59
  CLI tests unchanged, 45 XCUITests (44 before, 1 net new).

  **Two findings surfaced after the milestone's own commits landed, both from a
  post-landing review, and both the shape CLAUDE.md warns about – a test whose
  assertion could not fail for the right reason.** `topLevelSegments`' comma-list case
  attached its `where` clause to only the last of three patterns, so `,` and `\n` split
  at any paren depth and an input containing a nested function's commas split into
  pieces that happened to still produce the right *count* – fixed by moving the depth
  check into an explicit `if`, with the test now also asserting `imported.skipped.isEmpty`
  and the first entry's own text. `ImportTextSheet`'s name-suggestion `.onChange` sat on
  a subtree that does not exist before the first successful parse, so the very first
  paste never populated the name field – covered only by coincidence in the one UI test
  whose group name happened to match the field's placeholder – fixed with
  `initial: true`, with the UI test now asserting the field's value directly. Both fixes
  were confirmed to fail against the unfixed code before being fixed; neither changed a
  test count.
- **M27:** [GlobalHotKeyTests](ColorKitTests/GlobalHotKeyTests.swift) pins
  `isEligible` by discrimination on each of ⌃⌥⌘ alone (eligible) against ⇧ alone and no
  modifier at all (both not), plus a bare function key (eligible with nothing at all) –
  the exact boundary a hand-edited preferences file can cross. `GlobalShortcut`'s new
  `Codable` conformance round-trips. [ColorStoreTests](ColorKitTests/ColorStoreTests.swift)
  covers `updateGlobalShortcut(_:)`'s three reachable branches – commits directly while
  inactive, refuses an ineligible chord unchanged, no-ops on the chord already in
  effect – plus the one branch that claims a real system-wide chord: rebinding while
  active, proved by re-claiming the *old* chord afterward (`eventHotKeyExistsErr` if it
  were still held). **Confirmed by mutation**: removing the `unregisterAll()` call
  before the retry failed exactly that test. [PreferencesTests](ColorKitTests/PreferencesTests.swift)
  extends the M19 `recentLimit` pattern to `globalShortcut` – round-trips as part of
  `nonDefault`, clamps to `.sampleColor` when the loaded value is ineligible, and gets
  its own `withObservationTracking` mutation entry, since `globalShortcut` is a
  computed property over a private field rather than a stored `didSet` and needed its
  own proof that `@Observable` still sees through it. **No XCUITest** – nothing drives
  the Settings window (the same gap M22's own toggle already records), and synthesizing
  a key event to exercise `ShortcutRecorderField`'s live `NSEvent` monitor needs
  Accessibility permission a test runner has no business holding. Turning a captured
  `NSEvent` into a `GlobalShortcut` is a recorded manual check.
- **M28:** not a code milestone, so its verification is different in kind – there is no
  new logic to mutate, only build settings and a documented procedure. What was
  actually run: `xcodebuild archive` (needs no more credentials than `build` already
  does), then `codesign -d --entitlements -` on the archived app, confirming
  `com.apple.security.get-task-allow` – present in every ordinary Debug build – is
  absent from the Release one. That is the fact that distinguishes a debug build with
  distribution-shaped settings from one Gatekeeper will actually treat as distributable,
  and `xcodebuild build` alone cannot show it. Listing the archive's contents also
  settled a real question rather than an assumed one: `colorkit` **is** installed into
  the archive (`Products/usr/local/bin/colorkit`) but is **not** carried into an
  exported `.app`, since `-exportArchive` only pulls `Products/Applications/*.app` –
  confirmed by reading the archive tree, not inferred from the scheme. `-exportArchive`
  and `notarytool` were not run – `security find-identity -v -p codesigning` found no
  "Developer ID Application" identity in this environment, only the "Apple Development"
  one ordinary builds use – and are recorded as unverified, needing the app's own
  credentialed step.
- **M29:** [CommandLineToolInstallerTests](ColorKitTests/CommandLineToolInstallerTests.swift),
  and unlike M28 this target *is* reachable past the "recorded manual check" boundary
  most sandboxed I/O gets in this file – `ColorKitTests` carries no
  `ENABLE_APP_SANDBOX` of its own, so `install(embeddedBinary:into:)`'s real
  `createSymbolicLink` write is exercised end to end against a plain temp directory,
  not merely its guard clauses. Every pure helper is mutation-confirmed rather than
  merely asserted: flipping `isTranslocated`'s substring check to always return `false`
  fails exactly the two tests built to catch it (the direct predicate test and
  `install`'s own translocation guard), and flipping the `scoped ? .writeDenied :
  .securityScopeFailed` discrimination fails exactly the two permission-error tests
  that read the `scoped` flag – both confirmed by actually mutating the source and
  re-running, not assumed from the tests' shape. What remains a recorded manual check
  is narrower than a first read of "sandboxed I/O" would suggest: the panel itself
  (`NSOpenPanel`, the same limitation as `NSSavePanel`/`.fileImporter` elsewhere here),
  a real translocated launch, `colorkit --help` from a fresh Terminal after an actual
  install, and what a *genuinely sandboxed* security-scoped claim does – this target's
  own claim on a plain, non-powerbox URL returning `false`-yet-still-working is not
  proof of what a real bookmark does under `ENABLE_APP_SANDBOX`. Code-signing was
  verified the M28 way: a Release archive's embedded `colorkit` reads
  `flags=0x10000(runtime)` under `codesign -d --verbose=2`, settling – by reading the
  signature, not the attribute's name – that `CodeSignOnCopy` alone is sufficient and
  no `ENABLE_HARDENED_RUNTIME` needed adding to `colorkit`'s own build settings.
- **M3/M4 (UI):** run the app and verify interactively. Spot-check conversions against a browser's DevTools color picker, which implements the same spec – a fast, honest end-to-end sanity check.

The scheme is shared and works from the command line:

```bash
xcodebuild -project "ColorKit.xcodeproj" -scheme "ColorKit" -destination 'platform=macOS' test
```

`xcodebuild` does **not** print Swift Testing failure text – a failed run tells you which test failed and nothing about why. Capture a result bundle and read the `Failure Message` nodes out of it:

```bash
xcodebuild -project "ColorKit.xcodeproj" -scheme "ColorKit" -destination 'platform=macOS' -resultBundlePath /tmp/res.xcresult test
```

```bash
xcrun xcresulttool get test-results tests --path /tmp/res.xcresult --compact
```

Before asserting any gamut-containment claim, ask the reference rather than reasoning about which space is "wider":

```bash
cd Tools && node -e "import('colorjs.io').then(({default:C}) => console.log(new C('oklch(0.9 0.3 140)').inGamut('rec2020')))"
```

### Running the app

The app owns a `MenuBarExtra`, so **every running instance puts an icon in the menu
bar** – including one left behind by Xcode or by a UI test that did not terminate
cleanly. The symptom is a second, identical menu bar icon that does not respond to
clicks and survives quitting the app, because the app you quit was not the one that
owns it. There is no ghost to clear; there is a process to find:

```bash
ps -Ao pid,lstart,command | grep "ColorKit.app" | grep -v grep
```

Kill the stale pid and the icon goes with it. The UI tests in
[ColorKitUITests](ColorKitUITests/ConversionSmokeTests.swift) call
`app.terminate()` in `tearDown` specifically so they cannot be the cause.

**If `kill -9` does not work**, the instance is held by a debugger – a leftover test
host still attached to `debugserver`. `ps` shows it as state `SX`, where `X` means
traced. Seen once during M4: a UI test failed at `app.launch()` with *"Failed to
terminate me.parkersprouse.colorkit"*, and `sample` on the stuck process showed
its main thread frozen mid-`_AXXMIGAddNotification`. That stack is a red herring – a
traced process shows identical frames in every sample because it is not running at
all. Find the debugger and kill that first:

```bash
ps -Ao pid,ppid,stat,command | grep -E "debugserver|ColorKit.app" | grep -v grep
```

The run was clean on retry, so this is a flake in the unit-test-host → UI-test
handoff rather than anything in the app. Re-run before investigating.

**One cause of these is now established, and it is self-inflicted: two `xcodebuild test`
runs at once.** Found during M8. The symptoms are *"The test runner hung before
establishing connection"* and *"Lost connection to the application"* mid-test, and they
were reproduced twice by starting a second suite while the first was still alive – both
runs share the same DerivedData and the same test host and fight over them. Worse, the
loser leaves orphaned `UITests-Runner` and `ColorKit.app` processes reparented to
`init`, which then poison the *next* run too. So before blaming the host:

```bash
ps -Ao pid,ppid,command | grep -E "xcodebuild|UITests-Runner|ColorKit.app/Contents" | grep -v grep
```

Anything with `ppid 1` is an orphan. Kill it, and any second `xcodebuild`, then re-run.

**Two more ways to read a false pass**, both hit in the same session:

- **Never delete the worktree or its `-derivedDataPath` while the run is still alive.**
  Doing so removed `ColorKit.app` out from under the UI phase, and three tests
  failed with *"Could not launch … no such file"* – a failure that looks like a
  regression and is nothing but housekeeping. Confirm the process has exited first.
- **`Test run with N tests in M suites passed` is the Swift Testing line, not the
  verdict.** It prints minutes before the UI phase finishes. The only authoritative
  markers are `** TEST SUCCEEDED **` and `** TEST FAILED **`, and there should be exactly
  one; grep for those rather than for the word "passed". Note also that `Executed N
  tests` counts *XCTest* only and reads `0` on a Swift-Testing-only run, which is why
  the counts in the status note above are given per framework.

### Commit discipline

Commits follow milestone seams, and **each one must build and test on its own** – a green suite at HEAD says nothing about whether an intermediate commit is bisectable. Verify in a throwaway worktree with isolated DerivedData before stacking the next commit on top:

```bash
git worktree add -q --detach /tmp/wt <sha> && cd /tmp/wt && xcodebuild -project "ColorKit.xcodeproj" -scheme "ColorKit" -destination 'platform=macOS' -derivedDataPath /tmp/dd test
```

## Deferred (worth revisiting)

**Most of what stood here is now planned as M10–M18 above**, with the decisions that were
open at the time settled: `@media (color-gamut)` is an export shape rather than display
detection (there is no `NSScreen` usage anywhere in the app, and the badge's meaning is not
worth changing); palette import reads **W3C Design Tokens** rather than Figma's Variables
API or Tokens Studio; `ColorCore` moved to a repo-root group rather than becoming an SPM
package; and `calc()` is scoped to flat arithmetic over numbers, percentages and angles.

What remains genuinely deferred:

- **A UI control for `ShadeRamp.gamut`.** It defaults to `.srgb`, the CLI exposes it as
  `--gamut`, and nothing in the app binds it – so a ramp exported as
  `color(display-p3 …)` is sRGB colors re-spelled, never widened. Found by the 32-file
  export sweep after M8b. Small, but it wants a decision rather than a control: widening a
  ramp changes what "the same ramp" means across exports, and M22's web-friendly mode
  pushes in the opposite direction. Worth settling alongside M22.
- **Full `calc()`**: arbitrary nesting, parenthesized sub-expressions, `min()`/`max()`/
  `clamp()`. M13 deliberately stops short and now says so in its own errors rather than
  failing with a raw tokenizer complaint – `calc((1 + 2) * 3)` and `calc(1 + calc(2))`
  each name what is outside the subset. Going further wants real precedence climbing over
  a paren depth, at which point the flat two-level grammar in `CalcExpression` is replaced
  rather than extended. Also worth revisiting then: M13's `±` type rules are narrower than
  CSS Values 4, deliberately, and loosening them is a separate decision from nesting.
- **`var()` and `env()`** in parsing. Unlike `calc()`, these cannot be resolved from the
  string alone – they need a cascade the app does not have and should not invent.
- **The `alpha()` function** from CSS Color 5, which M14 scoped out. It has its own
  grammar row and, unlike every other relative form, its processing space is the
  *origin's* rather than the output's – so it is a genuinely separate rule and not one
  more case in the same switch.
- **Figma Variables API and Tokens Studio import.** M17 covers the vendor-neutral format;
  these are two more parsers with materially different shapes, worth adding only if a real
  file arrives that needs one.
- **Display-gamut detection** (`NSScreen.colorSpace`) driving the "mapped" badge. A
  different feature from M16 – which is now built – that happened to share its name.
- **A mapped count that separates the P3 shape's two blocks.** M16 counts what its
  *fallback* moved, so a color outside P3 is mapped in both blocks with nothing saying
  which. Answering it properly means two counts and a badge that can show them, which is
  a UI decision rather than a missing line.
- **~380 MainActor-isolation warnings across all 11 `ColorKitUITests` files**
  (`Call to main actor-isolated … in a synchronous nonisolated context`, one per
  `XCUIApplication`/`XCUIElement` call). See CLAUDE.md's Testing section for the full
  diagnosis and the two fixes already tried and ruled out. The real fix is per-file:
  `nonisolated override func setUpWithError()`/`tearDownWithError()` with their bodies
  wrapped in `MainActor.assumeIsolated { … }`, plus `@MainActor` on every test function
  — surgery across the same 11 files whose timing (hittability waits, frontmost-app
  checks, the popover key-window quirk) took real debugging to get right, so it wants
  its own pass rather than riding in on an unrelated change. Cosmetic in the meantime:
  test-target-only, the shipped app is unaffected, and the suite passes and runs
  correctly at runtime regardless, since XCTest genuinely does run these callbacks on
  the main thread.

*Note for later:* the APCA algorithm has carried usage/attribution terms. Irrelevant for personal use, but worth checking before ever distributing the app publicly.
