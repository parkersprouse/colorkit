//
//  CVDSimulationTests.swift
//  ColorKitTests
//
//  Regenerate the fixture (and the matrices) with:
//    python3 Tools/generate-cvd-matrices.py
//

@testable import ColorKit
import Foundation
import Testing

// MARK: - Fixture loading

struct CVDFixture: Decodable {
  struct Case: Decodable {
    let input: String
    let deficiency: String
    let severity: Double
    let output: [Double]
  }

  let cases: [Case]
}

enum CVDVectors {
  static let shared: CVDFixture = {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .appendingPathComponent("Fixtures/cvd-vectors.json")
    guard let data = try? Data(contentsOf: url) else {
      fatalError(
        "Missing fixture at \(url.path) — run: python3 Tools/generate-cvd-matrices.py",
      )
    }
    return try! JSONDecoder().decode(CVDFixture.self, from: data)
  }()

  static let deficiencies: [String: ColorVisionDeficiency] = [
    "protanomaly": .protanomaly,
    "deuteranomaly": .deuteranomaly,
    "tritanomaly": .tritanomaly,
  ]

  static func parse(_ css: String) throws -> ColorValue {
    try CSSColorParser.parse(css).color
  }
}

// MARK: - The matrix table

/// The 33 numbers are the whole point of this milestone — everything downstream is a
/// standard linear-RGB filter. These assertions pin the *shape* of the generated
/// table; the values themselves are cross-checked against three independent copies of
/// Machado's Table 1 in the generator, not re-transcribed here.
@Suite("CVD matrix table")
struct CVDMatrixTableTests {
  @Test("Three deficiencies, eleven severities each")
  func tableShape() {
    #expect(ColorVisionDeficiency.allCases.count == 3)
    for deficiency in ColorVisionDeficiency.allCases {
      #expect(deficiency.matrices.count == 11)
    }
  }

  /// Severity 0.0 is the identity — normal vision changes nothing. A wrong index
  /// alignment in the generator would land some other matrix here.
  @Test("Severity 0.0 is the identity", arguments: ColorVisionDeficiency.allCases)
  func severityZeroIsIdentity(deficiency: ColorVisionDeficiency) {
    let identity = deficiency.matrices[0]
    #expect(identity.m00 == 1 && identity.m11 == 1 && identity.m22 == 1)
    #expect(identity.m01 == 0 && identity.m02 == 0)
    #expect(identity.m10 == 0 && identity.m12 == 0)
    #expect(identity.m20 == 0 && identity.m21 == 0)
  }

  /// Rows sum to ~1, which is why a neutral gray survives the transform (see
  /// `graysAreUnchanged`). This is a property of Machado's construction, not
  /// something enforced — so it doubles as a check that the right numbers loaded.
  @Test("Every matrix row sums to one", arguments: ColorVisionDeficiency.allCases)
  func rowsSumToOne(deficiency: ColorVisionDeficiency) {
    for matrix in deficiency.matrices {
      #expect(abs(matrix.m00 + matrix.m01 + matrix.m02 - 1) < 5e-6)
      #expect(abs(matrix.m10 + matrix.m11 + matrix.m12 - 1) < 5e-6)
      #expect(abs(matrix.m20 + matrix.m21 + matrix.m22 - 1) < 5e-6)
    }
  }
}

// MARK: - Severity interpolation

@Suite("CVD severity")
struct CVDSeverityTests {
  /// An exact 0.1 step must return that Table 1 matrix untouched — the interpolation
  /// blends only *between* published steps, so `severity(0.7)` is `matrices[7]`, not a
  /// blend of 6 and 7. An off-by-one in the index maths fails here.
  @Test("Exact 0.1 steps are the tabulated matrix", arguments: 0 ... 10)
  func exactStepsAreTabulated(step: Int) {
    let deficiency = ColorVisionDeficiency.deuteranomaly
    let m = deficiency.matrix(severity: Double(step) / 10)
    let expected = deficiency.matrices[step]
    #expect(m.m00 == expected.m00)
    #expect(m.m11 == expected.m11)
    #expect(m.m22 == expected.m22)
    #expect(m.m01 == expected.m01)
  }

  /// Halfway between two steps is their midpoint. Pins that the blend is linear and
  /// that `t` is measured from the lower step.
  @Test("A half-step is the midpoint of its neighbours")
  func halfStepIsMidpoint() {
    let deficiency = ColorVisionDeficiency.protanomaly
    let m = deficiency.matrix(severity: 0.55)
    let a = deficiency.matrices[5]
    let b = deficiency.matrices[6]
    #expect(abs(m.m00 - (a.m00 + b.m00) / 2) < 1e-12)
    #expect(abs(m.m01 - (a.m01 + b.m01) / 2) < 1e-12)
    #expect(abs(m.m22 - (a.m22 + b.m22) / 2) < 1e-12)
  }

  /// Out-of-range severities clamp rather than crash the array subscript.
  @Test("Severity clamps to 0…1")
  func severityClamps() {
    let deficiency = ColorVisionDeficiency.tritanomaly
    let below = deficiency.matrix(severity: -0.5)
    let atZero = deficiency.matrices[0]
    #expect(below.m00 == atZero.m00)

    let above = deficiency.matrix(severity: 1.5)
    let atOne = deficiency.matrices[10]
    #expect(above.m00 == atOne.m00)
  }
}

// MARK: - Simulation

@Suite("CVD simulation")
struct CVDSimulationTests {
  // MARK: Internal

  /// Severity 0.0 returns the colour unchanged, to within an sRGB decode/encode round
  /// trip. If the identity matrix were not exactly identity this would drift.
  @Test(
    "Normal vision is a no-op",
    arguments: ["#3b82f6", "#ff0000", "#cc00ff", "#123456"],
  )
  func normalVisionIsNoOp(css: String) throws {
    let original = try color(css)
    for deficiency in ColorVisionDeficiency.allCases {
      let simulated = original.simulating(deficiency, severity: 0)
      let a = original.converted(to: .srgb).components
      let b = simulated.components
      #expect(abs(a.x - b.x) < 1e-9 && abs(a.y - b.y) < 1e-9 && abs(a.z - b.z) < 1e-9)
    }
  }

  /// A neutral gray confuses no cones, so every deficiency at every severity leaves it
  /// alone — a direct consequence of the rows summing to one.
  @Test("Grays are unchanged", arguments: ["#000000", "#808080", "#bbbbbb", "#ffffff"])
  func graysAreUnchanged(css: String) throws {
    let gray = try color(css)
    for deficiency in ColorVisionDeficiency.allCases {
      for severity in stride(from: 0.0, through: 1.0, by: 0.25) {
        let simulated = gray.simulating(deficiency, severity: severity)
        let g = gray.converted(to: .srgb).components
        let s = simulated.components
        #expect(
          abs(g.x - s.x) < 1e-4 && abs(g.y - s.y) < 1e-4 && abs(g.z - s.z) < 1e-4,
          "\(css) \(deficiency) \(severity)",
        )
      }
    }
  }

  /// The assertion that pins the **linear-RGB** decision, the one correctness trap in
  /// this milestone. `#cc00ff` seen as a protanope is `[0, 0.447, 1]` when the matrix
  /// is applied in linear light. Applying the very same matrix to the gamma-encoded
  /// sRGB channels instead — the common mistake — lands somewhere else entirely, and
  /// the second `#expect` asserts that mistake is *not* what we compute. Together they
  /// mean a regression to gamma-space application fails rather than passes.
  @Test("The matrix is applied in linear light, not gamma-encoded sRGB")
  func appliesInLinearLight() throws {
    let simulated = try color("#cc00ff").simulating(.protanomaly, severity: 1)

    // Anchor: the linear-pipeline result, measured independently of the fixture.
    let expected = SIMD3<Double>(0.0, 0.4471665194930911, 0.9999999999999999)
    #expect(abs(simulated.components.x - expected.x) < 1e-9)
    #expect(abs(simulated.components.y - expected.y) < 1e-9)
    #expect(abs(simulated.components.z - expected.z) < 1e-9)

    // What a naive gamma-space application would produce: the same matrix applied
    // to the raw sRGB channels, clamped, with no linearization.
    let raw = SIMD3<Double>(0xCC / 255.0, 0, 1)
    let gammaSpace = CVDMatrices.protanomaly[10](raw)
    let clampedGamma = SIMD3<Double>(
      min(max(gammaSpace.x, 0), 1),
      min(max(gammaSpace.y, 0), 1),
      min(max(gammaSpace.z, 0), 1),
    )
    // The two answers differ by roughly a quarter of the range — nowhere near a
    // rounding artifact, so this cannot pass by accident.
    let gap = abs(simulated.components.y - clampedGamma.y)
    #expect(gap > 0.1)
  }

  /// Alpha rides through untouched — a deficiency changes which colours are confused,
  /// not their opacity.
  @Test("Alpha is preserved")
  func alphaPreserved() throws {
    let translucent = try color("rgb(204 0 255 / 40%)")
    let simulated = translucent.simulating(.deuteranomaly, severity: 0.8)
    #expect(abs(simulated.alpha - 0.4) < 1e-9)
  }

  /// An out-of-sRGB input has no on-screen appearance to simulate; it is gamut-mapped
  /// first, so the result is always a finite, displayable sRGB colour rather than a
  /// NaN from `pow` of a negative channel.
  @Test("Out-of-gamut input yields a finite in-gamut result")
  func outOfGamutIsHandled() throws {
    let wide = try color("oklch(0.7 0.35 150)")
    let simulated = wide.simulating(.tritanomaly, severity: 1)
    for i in 0 ..< 3 {
      #expect(simulated.components[i].isFinite)
      #expect(simulated.components[i] >= -1e-9 && simulated.components[i] <= 1 + 1e-9)
    }
  }

  /// The whole pipeline against the reference, both the exact 0.1 steps (Table 1
  /// verbatim) and the interpolated severities in between.
  @Test("Simulated colours match the generated fixture")
  func matchesFixture() throws {
    for c in CVDVectors.shared.cases {
      let deficiency = try #require(CVDVectors.deficiencies[c.deficiency])
      let result = try color(c.input).simulating(deficiency, severity: c.severity)
      let out = result.components
      #expect(
        abs(out.x - c.output[0]) < 1e-9
          && abs(out.y - c.output[1]) < 1e-9
          && abs(out.z - c.output[2]) < 1e-9,
        "\(c.input) \(c.deficiency) @\(c.severity)",
      )
    }
  }

  // MARK: Private

  private func color(_ css: String) throws -> ColorValue {
    try CVDVectors.parse(css)
  }
}
