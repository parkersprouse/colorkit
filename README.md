# ColorKit

A native macOS app for the color work that happens while building for the web:
converting a color between formats, picking one off the screen, checking whether text
on it is readable, deriving a palette from it, and writing the result out as CSS you
can paste.

It lives in two places at once – a menu bar item for the quick things, and a window
with seven tools for everything else – and it ships with `colorkit`, a command line
version of the same engine.

Everything is computed on your Mac. Nothing is uploaded, and the app makes no network
requests at all.

---

## Requirements and setup

- **macOS 26.5 or later**
- **Xcode** – there is no prebuilt download, so you build it once from source

The simplest route is to open `ColorKit.xcodeproj` in Xcode and press **⌘R**. Once
it is running you'll see an eyedropper icon in the menu bar.

From the terminal:

```bash
xcodebuild -project "ColorKit.xcodeproj" -scheme "ColorKit" -destination 'platform=macOS' build
```

That puts `ColorKit.app` in Xcode's DerivedData folder rather than beside the
project. To find it:

```bash
xcodebuild -project "ColorKit.xcodeproj" -scheme "ColorKit" -showBuildSettings | grep -m1 BUILT_PRODUCTS_DIR
```

Drag the app from there into `/Applications` to install.

---

## The two ways in

### The menu bar

Click the eyedropper in the menu bar for a small panel holding the current color, a
**Copy as** menu listing every format, your recent colors, and three actions: **Color
Picker**, **Open ColorKit**, and **Quit**.

### The global shortcut

Press **⌃⌥⌘C** from *any* app to pick a color off the screen. A loupe appears, you
click a pixel, and the color is copied to your clipboard and added to the app's
recents. The menu bar icon flashes a checkmark to confirm – useful precisely because
you were looking at some other app when you pressed it.

The shortcut is only advertised in the panel once macOS has actually granted it, so if
you don't see it listed, another app claimed the chord first. It's also the only
keyboard shortcut anywhere in the app, and you can rebind it from **Settings ▸
Shortcuts**.

### The window

A collapsible sidebar sits on the left, holding the switcher for the seven tools and,
below it, your recent colors. Collapse it to an icon-only rail when you want the room
back.

Everything else lives in the content column beside it: a text field at the top that
accepts any CSS color, then whichever tool panel is showing.

**The field belongs to no tool.** Every tool is a different question asked about the
same color, so switching tools never changes what you typed.

---

## Typing a color

The field accepts CSS Color 4, and more of it than most tools do:

| You can type                | Example                                                               |
| --------------------------- | --------------------------------------------------------------------- |
| Hex, in 3/4/6/8 digits      | `#3b82f6`, `#fc0`                                                     |
| One of the 148 named colors | `rebeccapurple`                                                       |
| The classic functions       | `rgb(59 130 246)`, `hsl(217 91% 60%)`, `hwb(217 23% 4%)`              |
| Perceptual functions        | `oklch(0.62 0.19 260)`, `oklab()`, `lch()`, `lab()`                   |
| Wide-gamut spaces           | `color(display-p3 0.2 0.5 0.9)`, `rec2020`, `a98-rgb`, `prophoto-rgb` |
| Missing components          | `oklch(none 0.19 260)`                                                |
| Arithmetic                  | `rgb(calc(20 * 3) 130 246)`                                           |
| Relative color syntax       | `oklch(from #3b82f6 calc(l + 0.1) c h)`                               |
| Mixing                      | `color-mix(in oklch, red 40%, blue)`                                  |

It parses as you type, so a half-finished value doesn't blank the screen – the last
color that parsed stays on display until the next one does. If what you typed is valid
CSS but unusual, you get a warning rather than a rejection; if it isn't valid at all,
you get a plain-English error.

Click the swatch beside the field to open a compact color picker without leaving
whatever tool you're in. Click the format name under it (`6-digit hex`, `oklch()`) to
change the format of the color in-place.

---

## The seven tools

### Convert

The current color written in every format at once, grouped as **Web** (understood
everywhere), **Perceptual** (even lightness and hue steps), **Wide gamut** (reaches
past sRGB) and **Exact** (lossless, rarely authored). Click any row to copy it.

A badge marks any value that had to be moved to be written – a Display P3 green has no
honest hex, and the app says so rather than quietly rounding.

### Pick

A full-spectrum picker with two modes:

- **HSV** – the familiar saturation/value square with a hue strip.
- **OKLCH** – chroma against lightness, with the sRGB gamut edge drawn *on* the plane
  so you can see where colors stop being displayable. A dashed second line shows your
  display's own limit.

Drag on the square, the hue strip, or the alpha slider. The color is filed under
recents when you release, not while you drag, so a single pick doesn't fill the list
with the hundred colors you crossed on the way.

### Transform

Five things you can do to the color in the field:

- **Adjust** – nudge lightness, chroma and hue relative to where they are now, plus an
  S-curve for contrast.
- **Harmony** – Comp, Split, Triad, Tetrad, Analogous and Mono, each with a sentence on
  when it's the right choice.
- **Ramp** – a shade scale keyed `50` through `950`, every stop held inside the gamut.
- **Mix** – `color-mix()` between the foreground and background, in the space and
  around the hue arc you choose.
- **Legibility** – hand it a contrast target and it finds the nearest lighter and
  darker versions of your color that actually meet it.

Every derived swatch is a live handle: click it to load it into the field,
right-click for "Use as background" and the rest.

### Contrast

The foreground and background side by side, scored two ways:

- **WCAG 2.2**, the ratio audits check, with pass/fail against AA and AAA for normal
  text, large text, and non-text elements.
- **APCA**, the newer perceptual measure, which scores dark-on-light and light-on-dark
  differently – hence the swap button.

### CVD

The color as it appears to someone with **protanomaly**, **deuteranomaly** or
**tritanomaly**, at a severity you can dial from none to full. Your recent colors are
simulated alongside, which is the point: the question is rarely "how does this one
color look" and nearly always "can these two still be told apart".

### Projects

The only tool that remembers anything. Create a project, then:

- **Save Color** – keeps the color in the field, spelled the way you typed it.
- **Save Selection** – keeps the current harmony, ramp, or recents as a named palette.
- Drag saved colors to reorder them, or use **Move Left** / **Move Right** from the
  right-click menu. Attach a note to any color.
- **Import ▸ From Text…** – paste a stylesheet, a Tailwind config, a JSON file, a
  Design tokens (DTCG) file, or just a list of colors, and get its colors and palettes back. Individual colors are imported as a `Color` in the app, whereas color groups / palettes (denoted by the suffix format `-100`, `-200`, etc.) are imported as a `Palette` in the app.
   - A project export splits into exactly the colors and palettes it left as – the preview says which before you confirm the import.
- **Import ▸ From File…** – read any of the shapes below, or a
  [DTCG](https://www.designtokens.org/) Design tokens file, straight off disk.
- **Export Project** – hand every palette *and* individual color to the Export tool as
  one document.

Saved colors keep their original spelling. A `rebeccapurple` you saved comes back as
`rebeccapurple`, not as `#663399`.

### Export

Turns colors into something you can paste. Choose a **source** – this color, the
harmony, the ramp, your recents, a saved palette, or a whole project – and a **shape**:

| Shape             | What you get                                                                    |
| ----------------- | ------------------------------------------------------------------------------- |
| Declarations      | `background-color: #3b82f6;` – one property per color                           |
| Custom properties | a `:root { --brand-500: …; }` block                                             |
| JSON              | a plain object                                                                  |
| Tailwind v4       | a `@theme` block                                                                |
| Tailwind v3       | a `tailwind.config.js`                                                          |
| P3 with fallback  | a hex block plus a `@media (color-gamut: p3)` override in `color(display-p3 …)` |
| Design tokens (DTCG) | a [DTCG](https://www.designtokens.org/) document, each color in its own space |

Below the controls is a live preview of exactly what you'll get. **Copy** puts it on
the clipboard; **Save…** writes it to a file, named after your palette and tagged with
the right file type.

If any color had to be moved into gamut to be written, a line above the preview says
how many.

---

## Settings

Open with **⌘,**.

**Web-friendly mode** is the setting most worth knowing about. Turn it on and the app
hides every format and shape that isn't hand-authorable sRGB, and keeps every value it
produces inside sRGB – the picker, the harmonies, the ramps and the contrast solver all
recalibrate. It is for the case where the output has to work everywhere and a
`color(display-p3 …)` in your stylesheet is a problem rather than a feature.

The same section also holds whether to show the recents row and how many colors it
keeps.

**Shortcuts** lets you rebind the global sampling shortcut (⌃⌥⌘C by default) to
whatever chord you'd rather use.

The output preferences are shared by every panel and also reachable from the output
options icon beside the color field:

- Legacy comma syntax (`rgb(255, 0, 0)`)
- `rgb()` as percentages
- Uppercase hex, and shortening hex where possible
- Precision – Minimum, Normal, Increased, or Maximum
- Out of gamut – map values into gamut, or keep the originals
- Alpha – only when transparent, always, or never

**Command Line Tool** installs `colorkit` onto a directory on your `PATH` you pick,
without needing an admin password.

---

## The `colorkit` command line tool

The same engine, for scripts and for anyone who'd rather not leave the terminal.

```bash
xcodebuild -project "ColorKit.xcodeproj" -target ColorKitCLI -destination 'platform=macOS' build
```

It builds to `./build/Release/colorkit`. Copy it somewhere on your `PATH` if you want
it permanently.

### Nine commands

```
convert   Write a color in one format, or in all of them
contrast  Measure WCAG 2.2 and APCA contrast for a pair
solve     Find the nearest color that meets a contrast target
adjust    Move a color along the OKLCH axes
harmony   Derive a color's relatives
ramp      Build a shade scale around a color
cvd       Simulate color vision deficiencies
export    Write named colors as a stylesheet or config
tokens    Read a W3C design token file
```

Every command takes `--help` for its own arguments.

### Examples

Every format at once:

```bash
colorkit convert rebeccapurple
```

```
hex           #663399
keyword       rebeccapurple
rgb           rgb(102 51 153)
hsl           hsl(270 50% 40%)
oklch         oklch(0.4403 0.1603 303.37)
display-p3    color(display-p3 0.3737 0.2103 0.5791)
…
```

One format, ready to capture in a shell variable:

```bash
colorkit convert "color-mix(in oklch, red, blue)" --format hex
```

Check a pair:

```bash
colorkit contrast "#767676" "#ffffff"
```

```
WCAG 2.2  4.54:1
APCA      Lc 71.6
AA normal text   pass  (1.4.3, needs 4.5:1)
AA large text    pass  (1.4.3, needs 3:1)
AAA normal text  fail  (1.4.6, needs 7:1)
```

Build a shade scale:

```bash
colorkit ramp "#3b82f6" --format hex
```

```
50   #f0f6ff
100  #cce0ff
…
500  #3b82f6
…
950  #000f31
```

Find a color that passes:

```bash
colorkit solve "#7fb2ff" --on "#ffffff"
```

```
darker  oklch(0.5698 0.1241 258.4)  4.50:1
```

### Using it in scripts

Results go to **stdout** and everything else – warnings, errors, notes about gamut
mapping – goes to **stderr**, so a value can be captured directly:

```bash
BRAND=$(colorkit convert "oklch(0.62 0.19 260)" --format hex)
```

Exit codes are `0` for success, `1` for a command that ran and failed, and `2` for a
command line that was wrong. A failing run puts nothing at all on stdout.

There is no `mix` command, and that's deliberate: `convert` already accepts
`color-mix(…)` as input, so it would be a second door into the same room.

---

## A few things worth knowing

**Your spelling is kept.** The app treats the text you typed as the truth, not a
canonicalized value derived from it. Colors you save, and colors you click in recents,
come back the way you wrote them.

**Out-of-gamut colors are shown, not hidden.** A color past sRGB's edge gets a badge
saying so rather than being silently clamped. Which format you ask for decides whether
it has to move: hex can't hold it, `oklch()` can.

**Where your data lives.** Projects are stored locally in the app's own database.
Preferences are stored in macOS's standard preferences for the app. Nothing else is
written to disk unless you use **Save…** in the Export tool or import a file, both of
which use a normal macOS file panel.

---

## For contributors

`CLAUDE.md` covers what to run and what will break; `PLAN.md` is the source of truth for
why every design decision was made the way it was. Read `PLAN.md` before making a design
call.

The full test suite:

```bash
xcodebuild -project "ColorKit.xcodeproj" -scheme "ColorKit" -destination 'platform=macOS' test
```

There are no third-party runtime dependencies. Swift 6, SwiftUI, SwiftData.
