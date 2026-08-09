#!/usr/bin/env node
// Emits the reference interpolation fixture behind `color-mix()` (M15).
//
// Two things about this oracle are not optional, and both produce plausible wrong
// answers rather than errors when gotten wrong:
//
//   1. `premultiplied: true`. colorjs.io defaults to NOT premultiplying and CSS
//      always premultiplies, so the default quietly returns the wrong color for any
//      mix involving alpha — `rgb(50% 0% 50%)` where CSS says `rgb(33.3% 0% 66.7%)`.
//      Same class of trap as the WCAG 0.03928/0.04045 split.
//   2. colorjs.io's `range()` GAMUT MAPS both endpoints before interpolating ("to
//      avoid areas of flat color" — a gradient nicety). CSS Color 4 §12 has no such
//      step, and neither does ColorCore: a mix in a bounded space is allowed to land
//      outside it. So a case whose endpoints are out of the interpolation space's
//      gamut is asking the oracle a DIFFERENT QUESTION, and is skipped here rather
//      than recorded. That divergence is pinned from the other side, in Swift, by a
//      test asserting the un-mapped answer.
//
// The oracle covers numbers only. Grammar is hand-written in ColorMixTests.swift —
// colorjs.io's parser rejects `color-mix()` outright — and so are the percentage
// rules, which are CSS Color 5 syntax rather than interpolation arithmetic.

import { writeFileSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import Color from "colorjs.io";

const here = dirname(fileURLToPath(import.meta.url));
const version = JSON.parse(
  readFileSync(join(here, "node_modules", "colorjs.io", "package.json"), "utf8"),
).version;

// Our ColorSpace raw value -> colorjs.io space id.
const SPACES = {
  srgb: "srgb",
  hsl: "hsl",
  hwb: "hwb",
  "srgb-linear": "srgb-linear",
  lab: "lab",
  lch: "lch",
  oklab: "oklab",
  oklch: "oklch",
  "display-p3": "p3",
  "a98-rgb": "a98rgb",
  "prophoto-rgb": "prophoto",
  rec2020: "rec2020",
  "xyz-d50": "xyz-d50",
  "xyz-d65": "xyz-d65",
};

// Spaces with a hue, and therefore an arc to choose. Read off colorjs.io rather than
// listed, so the two cannot drift.
const POLAR = Object.keys(SPACES).filter((ours) => Color.spaces[SPACES[ours]].hueId);
const HUE_METHODS = ["shorter", "longer", "increasing", "decreasing"];

const clean = (coords) =>
  coords.map((v) => (typeof v === "number" && Number.isFinite(v) ? v : null));

// ---- Endpoints ----------------------------------------------------------
// Named so the pair list below reads as colors rather than coordinates.
const C = {
  red: { space: "srgb", components: [1, 0, 0], alpha: 1 },
  blue: { space: "srgb", components: [0, 0, 1], alpha: 1 },
  white: { space: "srgb", components: [1, 1, 1], alpha: 1 },
  black: { space: "srgb", components: [0, 0, 0], alpha: 1 },
  gray: { space: "srgb", components: [0.5, 0.5, 0.5], alpha: 1 },
  brand: { space: "srgb", components: [0.23137254901960785, 0.5098039215686274, 0.9647058823529412], alpha: 1 },
  // Alpha, which is where premultiplication shows up at all.
  fadedRed: { space: "srgb", components: [1, 0, 0], alpha: 0.2 },
  clearBlue: { space: "srgb", components: [0, 0, 1], alpha: 0 },
  halfGreen: { space: "oklch", components: [0.8, 0.05, 100], alpha: 0.5 },
  // A hue pair either side of 0°, so the four arcs give four different answers.
  warm: { space: "oklch", components: [0.6, 0.15, 20], alpha: 1 },
  cool: { space: "oklch", components: [0.6, 0.15, 340], alpha: 1 },
  cyan: { space: "hsl", components: [200, 80, 50], alpha: 1 },
  teal: { space: "lab", components: [50, 40, -30], alpha: 1 },
  // Outside sRGB, so most bounded interpolation spaces skip it and the unbounded
  // ones still exercise a wide endpoint.
  p3Green: { space: "display-p3", components: [0, 1, 0], alpha: 1 },
};

const PAIRS = [
  [C.red, C.blue],
  [C.white, C.blue],
  [C.black, C.red],
  [C.gray, C.brand],
  [C.white, C.black],
  [C.fadedRed, C.blue],
  [C.clearBlue, C.red],
  [C.fadedRed, C.halfGreen],
  [C.warm, C.cool],
  [C.cool, C.warm],
  [C.halfGreen, C.cyan],
  [C.teal, C.white],
  [C.brand, C.halfGreen],
  [C.p3Green, C.black],
  [C.p3Green, C.red],
];

const PROGRESSIONS = [0, 0.25, 0.5, 0.75, 1];

const toColor = (c) => new Color(SPACES[c.space], c.components, c.alpha);

// ---- Mixes --------------------------------------------------------------
const mixes = [];
let skipped = 0;

for (const [first, second] of PAIRS) {
  for (const space of Object.keys(SPACES)) {
    // See the header: an out-of-gamut endpoint would be gamut mapped by the oracle
    // and not by CSS, so the two are answering different questions.
    const inGamut = [first, second].every((c) =>
      toColor(c).to(SPACES[space]).inGamut(SPACES[space], { epsilon: 0 }),
    );
    if (!inGamut) {
      skipped += 1;
      continue;
    }

    const arcs = POLAR.includes(space) ? HUE_METHODS : ["shorter"];
    for (const hue of arcs) {
      for (const progress of PROGRESSIONS) {
        const mixed = Color.mix(toColor(first), toColor(second), progress, {
          space: SPACES[space],
          hue,
          premultiplied: true,
        });
        mixes.push({
          space,
          hue,
          progress,
          from: first,
          to: second,
          expected: { components: clean(mixed.coords), alpha: mixed.alpha },
        });
      }
    }
  }
}

const fixture = {
  generator: {
    library: "colorjs.io",
    version,
    premultiplied: true,
    note:
      "Generated by Tools/generate-mix-fixtures.mjs — do not edit by hand. " +
      "Cases whose endpoints leave the interpolation space's gamut are omitted: " +
      "colorjs.io gamut maps before interpolating and CSS does not.",
  },
  mixes,
};

const out = join(here, "..", "ColorKitTests", "Fixtures", "mix-vectors.json");
writeFileSync(out, JSON.stringify(fixture));
console.log(`mixes         ${mixes.length}`);
console.log(`skipped       ${skipped} pair/space combinations (out of gamut)`);
console.log(`polar spaces  ${POLAR.join(", ")}`);
console.log(`written to    ${out}`);
