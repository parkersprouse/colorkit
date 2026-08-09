#!/usr/bin/env node
// Generates ColorCore constant tables directly from the pinned colorjs.io source.
//
// Why generate instead of transcribe: the matrices differ from commonly-published
// blog values in the 7th+ decimal place. Hand-copying them produces deltas against
// the reference fixtures that look exactly like conversion bugs but aren't.
// Nothing here is typed by hand.
//
// Requires colorjs.io >= 0.7, which exports each space's matrices as `M`. Earlier
// versions kept them as module-private consts and needed source scraping.

import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import KEYWORDS from "colorjs.io/src/keywords.js";

const here = dirname(fileURLToPath(import.meta.url));
const SRC = join(here, "node_modules", "colorjs.io", "src");
const OUT = join(here, "..", "ColorCore", "Spaces");

const pkgVersion = JSON.parse(
  readFileSync(join(here, "node_modules", "colorjs.io", "package.json"), "utf8"),
).version;

/** Verifies a value is a well-formed 3x3 of finite numbers. */
function assertMatrix3x3(rows, label) {
  if (
    !Array.isArray(rows) ||
    rows.length !== 3 ||
    rows.some((r) => !Array.isArray(r) || r.length !== 3 || r.some((v) => !Number.isFinite(v)))
  ) {
    throw new Error(`${label} is not a well-formed 3x3 of finite numbers`);
  }
  return rows;
}

/**
 * Reads a matrix from a space module's exported `M` table.
 *
 * As of 0.7.0 each space exports its matrices (`export const M = { toXYZ, fromXYZ }`,
 * also reachable as `Space.M`), so we import them rather than scraping source text.
 * That makes extraction immune to reformatting and renamed locals — the exact churn
 * that broke the previous regex approach on the 0.6 → 0.7 upgrade.
 */
async function spaceMatrix(file, key) {
  const mod = await import(`colorjs.io/src/${file}`);
  const table = mod.M ?? mod.default?.M;
  if (!table) {
    throw new Error(
      `${file} exports no matrix table \`M\`. colorjs.io <0.7 kept these as ` +
        `module-private consts (toXYZ_M / XYZtoLMS_M); this generator requires >=0.7.`,
    );
  }
  if (!(key in table)) {
    throw new Error(`${file} matrix table has no "${key}" (has: ${Object.keys(table).join(", ")})`);
  }
  return assertMatrix3x3(table[key], `${file}:${key}`);
}

/** Emit a Swift ColorMatrix literal. */
function swiftMatrix(name, rows, doc) {
  const body = rows
    .map((r) => `        ${r.map((v) => fmt(v)).join(", ")},`)
    .join("\n");
  return `    /// ${doc}\n    static let ${name} = ColorMatrix(\n${body}\n    )\n`;
}

/** Round-trip-safe Double literal: shortest form that reparses identically. */
function fmt(v) {
  for (let p = 1; p <= 17; p++) {
    const s = v.toPrecision(p);
    if (Number(s) === v) return normalize(s);
  }
  return normalize(v.toPrecision(17));
}

function normalize(s) {
  let n = Number(s).toString();
  if (!/[.eE]/.test(n)) n += ".0";
  return n;
}

const matrices = [
  ["srgbLinearToXYZD65", "spaces/srgb-linear.js", "toXYZ", "linear-sRGB → XYZ D65"],
  ["xyzD65ToSRGBLinear", "spaces/srgb-linear.js", "fromXYZ", "XYZ D65 → linear-sRGB"],
  ["p3LinearToXYZD65", "spaces/p3-linear.js", "toXYZ", "linear Display P3 → XYZ D65"],
  ["xyzD65ToP3Linear", "spaces/p3-linear.js", "fromXYZ", "XYZ D65 → linear Display P3"],
  ["a98LinearToXYZD65", "spaces/a98rgb-linear.js", "toXYZ", "linear A98 RGB → XYZ D65"],
  ["xyzD65ToA98Linear", "spaces/a98rgb-linear.js", "fromXYZ", "XYZ D65 → linear A98 RGB"],
  // ProPhoto is natively D50-referenced — note the target space in the names.
  ["proPhotoLinearToXYZD50", "spaces/prophoto-linear.js", "toXYZ", "linear ProPhoto → XYZ **D50**"],
  ["xyzD50ToProPhotoLinear", "spaces/prophoto-linear.js", "fromXYZ", "XYZ **D50** → linear ProPhoto"],
  ["rec2020LinearToXYZD65", "spaces/rec2020-linear.js", "toXYZ", "linear Rec.2020 → XYZ D65"],
  ["xyzD65ToRec2020Linear", "spaces/rec2020-linear.js", "fromXYZ", "XYZ D65 → linear Rec.2020"],
  ["xyzD65ToLMS", "spaces/oklab.js", "XYZtoLMS", "XYZ D65 → LMS cone domain (OKLab)"],
  ["lmsToXYZD65", "spaces/oklab.js", "LMStoXYZ", "LMS cone domain → XYZ D65 (OKLab)"],
  ["lmsToOKLab", "spaces/oklab.js", "LMStoLab", "nonlinear LMS → OKLab"],
  ["okLabToLMS", "spaces/oklab.js", "LabtoLMS", "OKLab → nonlinear LMS"],
];

// The Bradford matrices are the one pair still not exported — they live inside
// adapt.js as two `env.M` assignments, one per direction. Scraped, with a count
// guard so a restructure fails loudly instead of silently emitting one direction.
const adaptSrc = readFileSync(join(SRC, "adapt.js"), "utf8");
const adaptBlocks = [...adaptSrc.matchAll(/env\.M\s*=\s*\[([\s\S]*?)\];/g)];
if (adaptBlocks.length !== 2) {
  throw new Error(`expected 2 Bradford matrices in adapt.js, found ${adaptBlocks.length}`);
}
const parseBlock = (b) =>
  [...b.matchAll(/\[([^\]]*)\]/g)].map((r) =>
    r[1].split(",").map((s) => s.trim()).filter(Boolean).map(Number),
  );
const [d65to50, d50to65] = adaptBlocks.map((b, i) =>
  assertMatrix3x3(parseBlock(b[1]), `adapt.js Bradford matrix ${i + 1}`),
);

let out = `//
//  Matrices.swift
//  ColorKit
//
//  GENERATED FILE — DO NOT EDIT BY HAND.
//  Regenerate with: node Tools/generate-constants.mjs
//  Source: colorjs.io v${pkgVersion} (pinned), authored by the CSS Color 4 spec editors.
//

import Foundation

/// Row-major 3x3 matrices for linear color-space conversion.
nonisolated enum Matrices {
`;

for (const [name, file, key, doc] of matrices) {
  out += swiftMatrix(name, await spaceMatrix(file, key), doc);
}
out += swiftMatrix("bradfordD65ToD50", d65to50, "Bradford chromatic adaptation D65 → D50");
out += swiftMatrix("bradfordD50ToD65", d50to65, "Bradford chromatic adaptation D50 → D65");
out += `}\n`;

writeFileSync(join(OUT, "Matrices.swift"), out);
console.log(`Matrices.swift        ${matrices.length + 2} matrices`);

// ---- Named colors -------------------------------------------------------
// keywords.js stores n/255 fractions; recover the exact integer channel values
// so the Swift table stays readable and divides identically under IEEE 754.
const names = Object.keys(KEYWORDS).sort();
let kw = `//
//  NamedColors.swift
//  ColorKit
//
//  GENERATED FILE — DO NOT EDIT BY HAND.
//  Regenerate with: node Tools/generate-constants.mjs
//  Source: colorjs.io v${pkgVersion} keywords.js (CSS Color 4 named-color table).
//

import Foundation

/// The CSS named-color table. Values are 8-bit sRGB channels.
/// \`transparent\` is handled by the parser, not stored here.
nonisolated enum NamedColors {
    static let table: [String: (UInt8, UInt8, UInt8)] = [
`;

for (const n of names) {
  const [r, g, b] = KEYWORDS[n].map((c) => {
    const v = Math.round(c * 255);
    if (Math.abs(c * 255 - v) > 1e-9) throw new Error(`${n} channel is not an /255 fraction`);
    return v;
  });
  kw += `        "${n}": (${r}, ${g}, ${b}),\n`;
}

kw += `    ]

    /// Reverse lookup: exact 8-bit sRGB match to a keyword, if one exists.
    ///
    /// Nine RGB values have two spellings, and in every case the two names are the
    /// same length (\`gray\`/\`grey\`, \`aqua\`/\`cyan\`, \`fuchsia\`/\`magenta\`, and the six
    /// other \`*gray\`/\`*grey\` pairs). A length-only tie-break therefore decides
    /// nothing, leaving the winner to \`Dictionary\` iteration order — which Swift
    /// randomizes per process launch. That would make \`namedKeyword\` return "gray"
    /// on one run and "grey" on the next.
    ///
    /// Shortest name wins, ties broken alphabetically. Alphabetical order happens to
    /// select the conventional CSS spelling in all nine cases.
    static let byValue: [SIMD3<UInt8>: String] = {
        var map: [SIMD3<UInt8>: String] = [:]
        for (name, c) in table {
            let key = SIMD3<UInt8>(c.0, c.1, c.2)
            if let existing = map[key] {
                if existing.count < name.count { continue }
                if existing.count == name.count && existing <= name { continue }
            }
            map[key] = name
        }
        return map
    }()
}
`;

writeFileSync(join(OUT, "NamedColors.swift"), kw);
console.log(`NamedColors.swift     ${names.length} keywords`);
