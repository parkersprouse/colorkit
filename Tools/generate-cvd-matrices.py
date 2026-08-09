#!/usr/bin/env python3
# Generates the Machado et al. (2009) colour-vision-deficiency simulation matrices
# and a validation fixture, directly from a pinned vendored source.
#
# Why generate instead of transcribe: this is "Table 1: Simulation matrices" — 33
# 3x3 matrices (protan/deutan/tritan x severity 0.0..1.0). Retyping them by hand is
# the Bradford failure mode at scale, exactly the thing generate-constants.mjs exists
# to avoid. Nothing numeric here is typed by hand; it is read from
# Tools/vendor/machado2010.py (colour-science 0.4.7, BSD-3, header preserved).
#
# Unlike the sibling generators this one is Python, because the oracle that carries
# Table 1 (colour-science, also used by the daltonlens reference library) is Python.
# It needs only the standard library — the vendored dataset is parsed without numpy.
#
# Emits:
#   ColorCore/Analysis/CVDMatrices.swift            (the 33 matrices)
#   ColorKitTests/Fixtures/cvd-vectors.json    (pipeline cross-check)

import ast
import json
import os
import types

HERE = os.path.dirname(os.path.abspath(__file__))
VENDOR = os.path.join(HERE, "vendor", "machado2010.py")
SWIFT_OUT = os.path.join(
    HERE, "..", "ColorCore", "Analysis", "CVDMatrices.swift"
)
FIXTURE_OUT = os.path.join(
    HERE, "..", "ColorKitTests", "Fixtures", "cvd-vectors.json"
)

DEFICIENCIES = ["Protanomaly", "Deuteranomaly", "Tritanomaly"]
SEVERITIES = [round(0.1 * k, 1) for k in range(11)]  # 0.0 .. 1.0


# ---- Read the vendored dataset without numpy -----------------------------------

def load_matrices():
    """Parse CVD_MATRICES_MACHADO2010 from the vendored file.

    The file is `CanonicalMapping({...})` of `np.array([...])` literals. We stub
    both so the structure evaluates to plain dicts/lists with no dependencies.
    """
    src = open(VENDOR).read()
    tree = ast.parse(src)
    node = next(
        n
        for n in tree.body
        if isinstance(n, ast.AnnAssign)
        and getattr(n.target, "id", "") == "CVD_MATRICES_MACHADO2010"
    )
    expr = ast.get_source_segment(src, node.value)
    env = {
        "np": types.SimpleNamespace(array=lambda x: x),
        "CanonicalMapping": lambda d: d,
    }
    table = eval(expr, env)  # noqa: S307 — evaluating our own vendored data
    return {defc: {round(s, 1): table[defc][round(s, 1)] for s in SEVERITIES}
            for defc in DEFICIENCIES}


# ---- Provenance guards ----------------------------------------------------------
#
# These are not the source of the emitted numbers (that is the vendored file); they
# are assertions that fail loudly if the vendored file is ever swapped for something
# that is not Machado Table 1. The identity check and the three severity-1.0 rows are
# the paper's published endpoints, independently present in opticquiz-cvd 1.1.0.

ENDPOINTS_1_0 = {
    "Protanomaly": [[0.152286, 1.052583, -0.204868],
                    [0.114503, 0.786281, 0.099216],
                    [-0.003882, -0.048116, 1.051998]],
    "Deuteranomaly": [[0.367322, 0.860646, -0.227968],
                      [0.280085, 0.672501, 0.047413],
                      [-0.011820, 0.042940, 0.968881]],
    "Tritanomaly": [[1.255528, -0.076749, -0.178779],
                    [-0.078411, 0.930809, 0.147602],
                    [0.004733, 0.691367, 0.303900]],
}


def verify(m):
    for defc in DEFICIENCIES:
        levels = m[defc]
        assert sorted(levels.keys()) == SEVERITIES, f"{defc} severities wrong"
        ident = levels[0.0]
        for i in range(3):
            for j in range(3):
                want = 1.0 if i == j else 0.0
                assert abs(ident[i][j] - want) < 1e-9, f"{defc} 0.0 is not identity"
        end = levels[1.0]
        for i in range(3):
            for j in range(3):
                assert abs(end[i][j] - ENDPOINTS_1_0[defc][i][j]) < 1e-9, (
                    f"{defc} 1.0 endpoint drifted from published Table 1"
                )


# ---- Swift emission -------------------------------------------------------------

def fmt(v):
    """Shortest round-trip Double literal; normalize -0.0 to 0.0."""
    if v == 0.0:
        v = 0.0
    r = repr(float(v))
    if "e" not in r and "E" not in r and "." not in r:
        r += ".0"
    return r


def swift_matrix(rows):
    body = ",\n".join(
        "            " + ", ".join(fmt(x) for x in row) for row in rows
    )
    return "        ColorMatrix(\n" + body + "\n        )"


def emit_swift(m):
    out = [
        "//",
        "//  CVDMatrices.swift",
        "//  ColorKit",
        "//",
        "//  GENERATED FILE — DO NOT EDIT BY HAND.",
        "//  Regenerate with: python3 Tools/generate-cvd-matrices.py",
        "//  Source: Machado, Oliveira & Fernandes (2009), \"A physiologically-based",
        "//  model for simulation of color vision deficiency\", IEEE TVCG 15(6),",
        "//  Table 1. Vendored via colour-science 0.4.7 CVD_MATRICES_MACHADO2010 and",
        "//  cross-checked against daltonlens 0.1.5 and opticquiz-cvd 1.1.0.",
        "//",
        "//  These are linear-RGB -> linear-RGB matrices: the simulation decodes sRGB",
        "//  to linear light, applies the matrix, then re-encodes. See CVDSimulation.",
        "//",
        "",
        "import Foundation",
        "",
        "/// The 33 pre-computed Machado (2009) simulation matrices, indexed by severity.",
        "///",
        "/// Each array holds eleven matrices for severity 0.0…1.0 in 0.1 steps (index",
        "/// `n` is severity `n/10`). Severity 0.0 is the identity. Rows sum to ~1, so a",
        "/// neutral gray is left unchanged — a fact the tests pin.",
        "nonisolated enum CVDMatrices {",
    ]
    swift_names = {
        "Protanomaly": "protanomaly",
        "Deuteranomaly": "deuteranomaly",
        "Tritanomaly": "tritanomaly",
    }
    for defc in DEFICIENCIES:
        out.append("")
        out.append(f"    /// {defc}, severity 0.0…1.0 in 0.1 steps (indices 0…10).")
        out.append(f"    static let {swift_names[defc]}: [ColorMatrix] = [")
        parts = []
        for s in SEVERITIES:
            parts.append(f"        // severity {s:.1f}\n" + swift_matrix(m[defc][s]))
        out.append(",\n".join(parts))
        out.append("    ]")
    out.append("}")
    text = "\n".join(out) + "\n"
    with open(SWIFT_OUT, "w") as f:
        f.write(text)
    print(f"CVDMatrices.swift     {len(DEFICIENCIES) * len(SEVERITIES)} matrices")


# ---- Fixture emission -----------------------------------------------------------
#
# Cross-checks the whole Swift pipeline, not just the matrices. Mirrors exactly what
# ColorValue.simulating(_:severity:) does, using the project's own sRGB transfer
# (threshold 0.04045, matching TransferFunctions.swift) so Swift can match to 1e-9:
#   decode sRGB -> linear, apply the severity-interpolated matrix, clamp to [0,1],
#   re-encode to sRGB.

def srgb_decode(v):
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


def srgb_encode(v):
    return 1.055 * (v ** (1 / 2.4)) - 0.055 if v > 0.0031308 else 12.92 * v


def interpolate(levels, severity):
    s10 = severity * 10.0
    lo = min(int(s10), 10)
    hi = min(lo + 1, 10)
    t = s10 - lo
    a, b = levels[round(lo / 10, 1)], levels[round(hi / 10, 1)]
    return [[a[i][j] + t * (b[i][j] - a[i][j]) for j in range(3)] for i in range(3)]


def apply_matrix(mat, rgb):
    return [sum(mat[i][j] * rgb[j] for j in range(3)) for i in range(3)]


def simulate(hex_in, mat):
    r = int(hex_in[1:3], 16) / 255
    g = int(hex_in[3:5], 16) / 255
    b = int(hex_in[5:7], 16) / 255
    lin = [srgb_decode(c) for c in (r, g, b)]
    sim = apply_matrix(mat, lin)
    clamped = [min(max(c, 0.0), 1.0) for c in sim]
    return [srgb_encode(c) for c in clamped]


def emit_fixture(m):
    # A deterministic in-gamut spread. APCA-style channel steps, thinned so the file
    # stays small; every colour is already inside sRGB so no gamut mapping is involved
    # and the pipeline under test is exactly decode -> matrix -> clamp -> encode.
    channels = [0, 51, 128, 204, 255]
    # Seed the anchors that matter — pure primaries (where the spectral shift is
    # largest), a mid-gray and white (which the matrices must leave alone) — then add
    # a thinned deterministic spread.
    colours = ["#ff0000", "#00ff00", "#0000ff", "#808080", "#ffffff"]
    for r in channels:
        for g in channels:
            for b in channels:
                if (r + g * 3 + b * 7) % 13 == 0:
                    h = f"#{r:02x}{g:02x}{b:02x}"
                    if h not in colours:
                        colours.append(h)

    # Exact 0.1 steps land on Table 1 verbatim (t == 0); the fractional ones exercise
    # the interpolation between adjacent matrices.
    severities = [0.0, 0.1, 0.25, 0.4, 0.5, 0.63, 0.8, 0.95, 1.0]

    cases = []
    swift_names = {
        "Protanomaly": "protanomaly",
        "Deuteranomaly": "deuteranomaly",
        "Tritanomaly": "tritanomaly",
    }
    for defc in DEFICIENCIES:
        for sev in severities:
            mat = interpolate(m[defc], sev)
            for c in colours:
                cases.append({
                    "input": c,
                    "deficiency": swift_names[defc],
                    "severity": sev,
                    "output": simulate(c, mat),
                })

    fixture = {
        "generator": {
            "source": "colour-science 0.4.7 CVD_MATRICES_MACHADO2010 "
                      "(Machado et al. 2009, Table 1)",
            "crossChecked": ["daltonlens 0.1.5", "opticquiz-cvd 1.1.0 (severity 1.0)"],
            "algorithm": "linear sRGB: decode(0.04045) -> interpolated 3x3 -> "
                         "clamp[0,1] -> encode",
            "note": "Generated by Tools/generate-cvd-matrices.py — do not edit by hand.",
        },
        "cases": cases,
    }
    with open(FIXTURE_OUT, "w") as f:
        json.dump(fixture, f)
    print(f"cvd-vectors.json      {len(cases)} cases "
          f"({len(colours)} colours x {len(severities)} severities x 3)")


def main():
    m = load_matrices()
    verify(m)
    emit_swift(m)
    emit_fixture(m)


if __name__ == "__main__":
    main()
