#!/usr/bin/env node
// Emits parse fixtures for the CSS color grammar.
//
// IMPORTANT: unlike the conversion fixtures, this list is CURATED — every input below
// is valid per CSS Color 4. colorjs.io's parser is deliberately permissive and accepts
// things browsers reject (`rgb(a b c)` becomes `rgb(none none none)`; commas are
// tolerated in modern-only functions). Feeding it a generated sweep would bless that
// looseness as ground truth. It is used here only as an oracle for the valid subset,
// where it and the spec agree. Rejection behavior is asserted in Swift, by hand.

import { writeFileSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import Color from "colorjs.io";

const here = dirname(fileURLToPath(import.meta.url));
const version = JSON.parse(
  readFileSync(join(here, "node_modules", "colorjs.io", "package.json"), "utf8"),
).version;

// colorjs.io space id -> our ColorSpace raw value.
const SPACE_IDS = {
  srgb: "srgb",
  hsl: "hsl",
  hwb: "hwb",
  "srgb-linear": "srgb-linear",
  lab: "lab",
  lch: "lch",
  oklab: "oklab",
  oklch: "oklch",
  p3: "display-p3",
  a98rgb: "a98-rgb",
  prophoto: "prophoto-rgb",
  rec2020: "rec2020",
  "xyz-d50": "xyz-d50",
  "xyz-d65": "xyz-d65",
};

const inputs = [
  // Hex, all four lengths, both cases.
  "#f00", "#F00", "#f00a", "#ff0000", "#FF0000", "#ff0000aa", "#0000", "#ffffffff",

  // Keywords.
  "red", "RED", "Red", "rebeccapurple", "transparent", "aqua", "cyan",
  "gray", "grey", "darkslategray", "lightgoldenrodyellow",

  // rgb() modern.
  "rgb(255 0 0)", "rgb(255 128 0)", "rgb(0 0 0)",
  "rgb(255 0 0 / 0.5)", "rgb(255 0 0 / 50%)", "rgb(255 0 0 / 0)",
  "rgb(50% 0% 0%)", "rgb(50% 25% 12.5% / 25%)",
  "rgb(none 0 0)", "rgb(255 none 0)", "rgb(255 0 0 / none)",
  // Out-of-range numbers are syntactically valid and preserved.
  "rgb(300 -20 0)", "rgb(120% -10% 0%)",

  // rgb() legacy.
  "rgb(255, 0, 0)", "rgba(255, 0, 0, 0.5)", "rgba(255,0,0,50%)",
  "rgb(50%, 0%, 0%)", "rgba(50%, 0%, 0%, 0.25)",

  // hsl() modern.
  "hsl(120 50% 50%)", "hsl(120deg 50% 50%)", "hsl(0 0% 0%)",
  "hsl(120 50% 50% / 0.5)", "hsl(none 0% 50%)", "hsl(120 none 50%)",
  "hsl(-60 50% 50%)", "hsl(400 50% 50%)",
  "hsl(2rad 50% 50%)", "hsl(100grad 50% 50%)", "hsl(0.25turn 50% 50%)",

  // hsl() legacy.
  "hsl(120, 50%, 50%)", "hsla(120, 50%, 50%, 0.5)", "hsla(120deg, 50%, 50%, 50%)",

  // hwb().
  "hwb(0 0% 0%)", "hwb(120 20% 30%)", "hwb(120 20% 30% / 0.5)",
  "hwb(none 20% 30%)", "hwb(0.5turn 0% 0%)", "hwb(200 60% 60%)",

  // lab() — L accepts number or percentage; a/b accept both, 100% = 125.
  "lab(50% 20 30)", "lab(50 20 30)", "lab(100% 0 0)", "lab(0% 0 0)",
  "lab(50% 100% -100%)", "lab(50% 20 30 / 0.5)", "lab(50% none 30)",
  "lab(62.2% -34.9 47.6)",

  // lch() — C 100% = 150, H is an angle.
  "lch(50% 30 200)", "lch(50% 30 200deg)", "lch(50% 100% 0)",
  "lch(50% 30 none)", "lch(50% 30 0.5turn / 0.5)", "lch(0% 0 0)",

  // oklab() — L 100% = 1, a/b 100% = 0.4.
  "oklab(0.5 0.1 0.1)", "oklab(50% 20% -20%)", "oklab(1 0 0)",
  "oklab(0.5 0.1 0.1 / 0.5)", "oklab(0.5 none 0.1)", "oklab(100% 100% 100%)",

  // oklch() — C 100% = 0.4.
  "oklch(0.7 0.15 200)", "oklch(70% 0.15 200)", "oklch(70% 50% 0.5turn)",
  "oklch(0.7 0.15 200 / 0.5)", "oklch(0.5 none 200)", "oklch(0.62 0.26 29.23)",
  // Deliberately out of sRGB gamut.
  "oklch(0.9 0.3 140)", "oklch(0.85 0.35 145)",

  // color() across every predefined space.
  "color(srgb 1 0 0)", "color(srgb 0.5 0.2 0.9 / 0.5)", "color(srgb 100% 0% 0%)",
  "color(srgb-linear 1 0 0)", "color(srgb-linear 0.25 0.5 0.75)",
  "color(display-p3 1 0 0)", "color(display-p3 0.5 0.2 0.9 / 25%)",
  "color(a98-rgb 1 0 0)", "color(a98-rgb 0.3 0.7 0.2)",
  "color(prophoto-rgb 1 0 0)", "color(prophoto-rgb 0.4 0.6 0.8)",
  "color(rec2020 1 0 0)", "color(rec2020 0.5 0.2 0.7)",
  "color(xyz 0.4 0.2 0.6)", "color(xyz-d50 0.4 0.2 0.6)", "color(xyz-d65 0.4 0.2 0.6)",
  "color(display-p3 none 0.5 0.5)", "color(srgb 1 0 0 / none)",

  // Whitespace and case tolerance.
  "  rgb(255 0 0)  ", "RGB(255 0 0)", "OKLCH(0.7 0.15 200)", "Rgb(255, 0, 0)",
  "rgb(  255   0   0  )", "rgb( 255 , 0 , 0 )",

  // Numeric edge forms.
  "rgb(2.55e2 0 0)", "rgb(.5 0 0)", "rgb(+128 0 0)", "oklch(0.7 0.15 -200)",
];

const cases = [];
for (const input of inputs) {
  let parsed;
  try {
    parsed = Color.parse(input);
  } catch (e) {
    throw new Error(`Curated input rejected by reference — remove it or fix it: ${input}\n${e.message}`);
  }
  const space = SPACE_IDS[parsed.spaceId];
  if (!space) throw new Error(`Unmapped space id "${parsed.spaceId}" from ${input}`);

  cases.push({
    input,
    space,
    components: parsed.coords.map((v) => (typeof v === "number" && Number.isFinite(v) ? v : null)),
    alpha: typeof parsed.alpha === "number" && Number.isFinite(parsed.alpha) ? parsed.alpha : null,
  });
}

const fixture = {
  generator: {
    library: "colorjs.io",
    version,
    curated: true,
    note: "Valid CSS Color 4 only. Rejection cases live in Swift. Generated by Tools/generate-parse-fixtures.mjs.",
  },
  cases,
};

const out = join(here, "..", "ColorKitTests", "Fixtures", "parse-vectors.json");
writeFileSync(out, JSON.stringify(fixture, null, 1));
console.log(`parse cases  ${cases.length}`);
console.log(`written to   ${out}`);
