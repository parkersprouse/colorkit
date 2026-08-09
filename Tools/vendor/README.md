# Vendored source: Machado et al. (2009) Table 1

`machado2010.py` is a verbatim copy of the colour-science dataset that carries
the *simulation matrices* from:

> Machado, G. M., Oliveira, M. M., & Fernandes, L. A. F. (2009).
> *A physiologically-based model for simulation of color vision deficiency.*
> IEEE TVCG, 15(6), 1291–1298 — **Table 1: Simulation matrices**.

It is the pinned input to `Tools/generate-cvd-matrices.py`, which emits
`ColorKit/ColorCore/Analysis/CVDMatrices.swift`. It is vendored rather than
transcribed for the same reason the colorjs.io matrices are generated and never
hand-copied: retyping 33 3×3 matrices is the Bradford failure mode at scale.

- **Origin:** `colour/blindness/datasets/machado2010.py` from
  `colour-science==0.4.7` (downloaded from PyPI as an sdist).
- **License:** BSD-3-Clause (Colour Developers) — its header is preserved intact.
- **Contents:** `CVD_MATRICES_MACHADO2010`, a mapping of
  `Protanomaly` / `Deuteranomaly` / `Tritanomaly` → severity `0.0 … 1.0`
  (0.1 steps) → 3×3 matrix.

## Provenance is cross-checked, not assumed

Every one of the 33 matrices was verified to agree **exactly** with three
independent sources before generation:

| Source | Independent because | Agreement |
|---|---|---|
| `daltonlens` 0.1.5 (PyPI) | Nicolas Burrus's own transcription of Table 1 | all 33, 0.0 diff |
| `opticquiz-cvd` 1.1.0 (npm) | separate JS implementation | severity-1.0 endpoints, 0.0 diff |
| The paper's Table 1 (screenshot) | the primary source itself | all 33, 0.0 diff |

The generator re-asserts the identity-at-0.0 and the three severity-1.0
endpoints as loud guards, so a future swap of this file for the wrong data
fails generation rather than silently shipping different numbers.

## Colour space (the one trap here)

These are **linear-RGB → linear-RGB** simulation matrices. The simulation
pipeline decodes sRGB to linear light, applies the matrix, then re-encodes —
confirmed by daltonlens (`_simulate_cvd_linear_rgb`) and opticquiz-cvd, which
both apply them in linear RGB. Applying them directly to gamma-encoded sRGB is
a common and visible mistake.
