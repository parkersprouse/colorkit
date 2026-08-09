//
//  ReferenceVectorTests.swift
//  ColorKitTests
//
//  Validates every conversion against vectors generated from colorjs.io — the
//  reference implementation written by the CSS Color 4 spec editors. This is the
//  gate that makes the rest of the app trustworthy: if these pass, a color shown
//  in ColorKit matches what a browser computes.
//
//  Regenerate the fixture with: node Tools/generate-fixtures.mjs
//

@testable import ColorKit
import Foundation
import Testing

// MARK: - Fixture loading

struct ReferenceFixture: Decodable {
  struct Generator: Decodable {
    let library: String
    let version: String
    let gamutMethod: String
  }

  struct ConversionCase: Decodable {
    let from: ColorSpace
    let components: [Double]
    let to: ColorSpace
    let expected: [Double?]
  }

  struct GamutCase: Decodable {
    let from: ColorSpace
    let components: [Double]
    let target: ColorSpace
    let inGamut: Bool
    let expected: [Double?]
  }

  let generator: Generator
  let conversions: [ConversionCase]
  let gamutMapping: [GamutCase]
}

enum Fixture {
  /// Loaded from source-relative path rather than the test bundle: synchronized
  /// Xcode groups don't reliably mark arbitrary JSON as a bundle resource, and a
  /// silently-missing fixture would turn this whole suite into a no-op.
  static let shared: ReferenceFixture = {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .appendingPathComponent("Fixtures/reference-vectors.json")
    guard let data = try? Data(contentsOf: url) else {
      fatalError("Missing fixture at \(url.path) — run: node Tools/generate-fixtures.mjs")
    }
    return try! JSONDecoder().decode(ReferenceFixture.self, from: data)
  }()
}

// MARK: - Comparison

/// Whether the reference's own output says this color is achromatic.
///
/// Derived from the expected values rather than ours, so the test can't excuse a
/// failure by declaring the color gray on its own authority.
private func referenceSaysAchromatic(_ expected: [Double?], space: ColorSpace) -> Bool {
  func value(_ i: Int) -> Double? {
    i < expected.count ? expected[i] : nil
  }

  switch space {
  case .hsl:
    // Saturation collapsed to nothing.
    return (value(1) ?? 1) < 1e-6
  case .hwb:
    // Whiteness + blackness saturating at 100 is the HWB spelling of gray.
    return (value(1) ?? 0) + (value(2) ?? 0) >= 100 - 1e-6
  case .lch, .oklch:
    // Chroma collapsed to nothing. Scales differ: Lab chroma runs to ~150,
    // OKLab chroma to ~0.4.
    let threshold = space == .lch ? 1e-4 : 1e-7
    return (value(1) ?? 1) < threshold
  default:
    return false
  }
}

/// Compares one converted component against its reference value.
///
/// Three components need special handling:
/// - **Hue** wraps, so 359.9999° and 0.0001° are adjacent, not 360 apart.
/// - **`null`** means the reference considers the component powerless. ColorCore
///   represents that as `0`.
/// - **Hue on an achromatic color** is genuinely undefined. HSL picks a hue from
///   whichever RGB channel is largest, but for a gray all three are equal, so the
///   winner is decided by last-ULP noise and differs harmlessly between any two
///   implementations. CSS Color 4 calls such a component "powerless"; asserting on
///   it would be asserting on rounding dust.
private func componentMatches(
  actual: Double,
  expected: [Double?],
  index: Int,
  space: ColorSpace,
  tolerance: Double,
) -> Bool {
  let isHue = space.hueIndex == index

  if isHue, referenceSaysAchromatic(expected, space: space) {
    return actual.isFinite
  }

  guard let target = expected[index] else {
    return abs(actual) < tolerance
  }
  guard actual.isFinite else { return false }

  if isHue {
    let delta = abs(Conversion.constrainAngle(actual - target))
    return min(delta, 360 - delta) <= tolerance * 360
  }

  // Relative tolerance, floored at 1, so components on a [0,100] or [0,360] scale
  // aren't held to the same absolute bar as sRGB's [0,1].
  return abs(actual - target) <= tolerance * max(1, abs(target))
}

private func describe(_ v: [Double?]) -> String {
  "[" + v.map { $0.map { String(format: "%.10g", $0) } ?? "none" }.joined(separator: ", ") + "]"
}

private func describe(_ v: SIMD3<Double>) -> String {
  "[" + [v.x, v.y, v.z].map { String(format: "%.10g", $0) }.joined(separator: ", ") + "]"
}

// MARK: - Tests

@Suite("Reference vectors")
struct ReferenceVectorTests {
  /// Conversions are pure arithmetic over matrices byte-identical to the
  /// reference, so only operation-ordering noise should differ. Anything looser
  /// than this would let a genuinely wrong constant slip through.
  static let conversionTolerance = 1e-9

  /// Gamut mapping runs an iterative binary search with a float termination test,
  /// so tiny divergences in the search path are expected and harmless.
  static let gamutTolerance = 1e-6

  @Test("Fixture was generated with the expected reference and gamut method")
  func fixtureProvenance() {
    let generator = Fixture.shared.generator
    #expect(generator.library == "colorjs.io")
    #expect(generator.gamutMethod == "css", "Gamut fixtures must use the CSS Color 4 algorithm")
    #expect(!Fixture.shared.conversions.isEmpty)
  }

  @Test("Conversions match the reference", arguments: ColorSpace.allCases)
  func conversionsMatchReference(target: ColorSpace) {
    var failures: [String] = []
    var checked = 0

    for testCase in Fixture.shared.conversions where testCase.to == target {
      checked += 1
      let source = ColorValue(
        space: testCase.from,
        testCase.components[0],
        testCase.components[1],
        testCase.components[2],
      )
      let actual = source.converted(to: target).components

      for i in 0 ..< 3 {
        if !componentMatches(
          actual: actual[i],
          expected: testCase.expected,
          index: i,
          space: target,
          tolerance: Self.conversionTolerance,
        ) {
          failures.append(
            """
            \(testCase.from.rawValue) \(describe(SIMD3(
              testCase.components[0], testCase.components[1], testCase.components[2],
            ))) → \(target.rawValue)
              expected \(describe(testCase.expected))
              actual   \(describe(actual))
            """,
          )
          break
        }
      }
    }

    #expect(checked > 0, "No fixture cases target \(target.rawValue)")
    #expect(
      failures.isEmpty,
      """
      \(failures.count)/\(checked) conversions to \(target.rawValue) diverged:
      \(failures.prefix(5).joined(separator: "\n"))
      """,
    )
  }

  @Test(
    "Gamut mapping matches the CSS Color 4 algorithm",
    arguments: [ColorSpace.srgb, .displayP3, .rec2020],
  )
  func gamutMappingMatchesReference(target: ColorSpace) {
    var failures: [String] = []
    var checked = 0

    for testCase in Fixture.shared.gamutMapping where testCase.target == target {
      checked += 1
      let source = ColorValue(
        space: testCase.from,
        testCase.components[0],
        testCase.components[1],
        testCase.components[2],
      )
      let actual = source.gamutMapped(to: target).components

      for i in 0 ..< 3 {
        if !componentMatches(
          actual: actual[i],
          expected: testCase.expected,
          index: i,
          space: target,
          tolerance: Self.gamutTolerance,
        ) {
          failures.append(
            """
            \(testCase.from.rawValue) \(describe(SIMD3(
              testCase.components[0], testCase.components[1], testCase.components[2],
            ))) → gamut \(target.rawValue) (inGamut: \(testCase.inGamut))
              expected \(describe(testCase.expected))
              actual   \(describe(actual))
            """,
          )
          break
        }
      }
    }

    #expect(checked > 0)
    #expect(
      failures.isEmpty,
      """
      \(failures.count)/\(checked) gamut mappings to \(target.rawValue) diverged:
      \(failures.prefix(5).joined(separator: "\n"))
      """,
    )
  }

  @Test("In-gamut detection matches the reference", arguments: [ColorSpace.srgb, .displayP3, .rec2020])
  func inGamutMatchesReference(target: ColorSpace) {
    var mismatches: [String] = []

    for testCase in Fixture.shared.gamutMapping where testCase.target == target {
      let source = ColorValue(
        space: testCase.from,
        testCase.components[0],
        testCase.components[1],
        testCase.components[2],
      )
      let actual = source.inGamut(of: target)
      // Colors sitting exactly on the gamut boundary can land either side of
      // the test after float noise; only flag clear disagreements.
      if actual != testCase.inGamut {
        let rgb = source.converted(to: target.rgbBasis ?? target).components
        let margin = [rgb.x, rgb.y, rgb.z]
          .map { min(abs($0), abs($0 - 1)) }
          .min() ?? 0
        if margin > 1e-9 {
          mismatches.append(
            "\(testCase.from.rawValue) \(describe(rgb)) → \(target.rawValue): "
              + "expected \(testCase.inGamut), got \(actual)",
          )
        }
      }
    }

    #expect(
      mismatches.isEmpty,
      "\(mismatches.count) in-gamut mismatches:\n\(mismatches.prefix(5).joined(separator: "\n"))",
    )
  }
}
