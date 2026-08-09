//
//  DesignTokenImportTests.swift
//  ColorKitTests
//

@testable import ColorKit
import Foundation
import Testing

/// Reading the W3C Design Tokens format.
///
/// **The oracle here is the specification, not a reference implementation** — the fifth
/// distinct no-oracle reason this project has recorded, and the simplest: colorjs.io
/// parses CSS, and a design token's `$value` is a JSON object rather than a CSS string.
/// There is nothing to ask. So the inputs below are the shapes the Color module
/// documents, each test naming the rule it encodes.
///
/// Documents are written inline rather than kept as fixture files. The generated vector
/// sets earn their separate files by being thousands of lines of numbers; these are five
/// lines of JSON apiece and read as the spec examples they are, which is only true when
/// the input sits next to the assertion about it.
@Suite("Design token import")
struct DesignTokenImportTests {
  // MARK: Internal

  // MARK: - Component scale

  /// **The single discriminating input for the whole numeric mapping.**
  ///
  /// The format's `srgb` components run 0–1, and so does this app's storage, so the
  /// mapping is the identity. The mistake with a plausible-looking result is reaching for
  /// `rgb()`'s grammar, whose *number* form runs 0–255: red would import with a red
  /// channel of `1/255` — a near-black that still renders, still round-trips and looks
  /// like nothing in particular went wrong.
  @Test("An sRGB component is a fraction, not a 0–255 channel")
  func srgbComponentsAreNotTheRGBFunctionScale() throws {
    let document = try Self.decode(#"""
    { "brand": { "$type": "color",
      "red": { "$value": { "colorSpace": "srgb", "components": [1, 0, 0] } } } }
    """#)

    let color = try #require(document.colors.first).color
    #expect(color == ColorValue(space: .srgb, 1, 0, 0))
    // The competing reading, stated so the tolerance-free equality above is not mistaken
    // for an arbitrary choice of fixture.
    #expect(color.components.x != 1.0 / 255.0)
  }

  /// Every space, because the identity claim is made about all fourteen at once.
  ///
  /// Components deliberately not round: `0.5` survives a great many wrong scalings that
  /// `0.3178` does not.
  @Test("Every color space imports its components unchanged", arguments: ColorSpace.allCases)
  func everySpaceImportsUnchanged(space: ColorSpace) throws {
    let document = try Self.decode(#"""
    { "t": { "$type": "color", "c": { "$value": {
      "colorSpace": "\#(space.rawValue)", "components": [0.3178, 0.4271, 0.5093] } } } }
    """#)

    let color = try #require(document.colors.first).color
    #expect(color == ColorValue(space: space, 0.3178, 0.4271, 0.5093))
  }

  /// What makes "no scaling" a claim rather than an omission.
  ///
  /// The importer performs no arithmetic on a component and does not consult
  /// ``ColorGrammar`` at all — those tables are CSS syntax, which has no authority over
  /// this format. That is only *correct*, rather than merely uncoupled, while the number
  /// form each space is written in coincides with the range the Color module documents.
  /// This is the tripwire for that: if a grammar ever gains a scale, it fails here and
  /// says the importer now needs a conversion, instead of fourteen spaces quietly
  /// importing wrong.
  @Test("No imported space needs a number scale", arguments: ColorSpace.allCases)
  func writtenScaleIsUnityForEverySpace(space: ColorSpace) {
    let grammars = Self.writtenGrammar(for: space)

    #expect(grammars.count == 3)
    #expect(grammars.allSatisfy { $0.numberScale == 1 })
  }

  /// The inverse of ``CSSOutputFormat/space`` really is an inverse.
  ///
  /// Cheap, and the thing that keeps an imported color from being stored spelled in some
  /// other space than the one its token named.
  @Test("A native format round-trips through its space", arguments: ColorSpace.allCases)
  func nativeFormatRoundTripsThroughItsSpace(space: ColorSpace) {
    #expect(CSSOutputFormat.native(for: space).space == space)
  }

  /// An imported color has to survive being written down, because that is what storage
  /// does to it — the ``Export`` oracle, pointed the other way.
  @Test("An imported color survives serialization", arguments: ColorSpace.allCases)
  func importedColorsSurviveSerialization(space: ColorSpace) throws {
    let document = try Self.decode(#"""
    { "t": { "$type": "color", "c": { "$value": {
      "colorSpace": "\#(space.rawValue)", "components": [0.3178, 0.4271, 0.5093] } } } }
    """#)

    let color = try #require(document.colors.first).color
    let text = color.cssStringOrHex(as: .native(for: space), options: .lossless)
    let reparsed = try CSSColorParser.parse(text).color

    #expect(reparsed.space == space)
    for index in 0 ..< 3 {
      #expect(abs(reparsed.components[index] - color.components[index]) < 1e-9)
    }
  }

  // MARK: - Missing components and alpha

  /// `none` is the reason M17 waited on M12: a decoded token now has somewhere honest to
  /// put an absent component. Zero in the slot and the fact of absence in the mask —
  /// exactly the pair the parser writes for a CSS `none`.
  @Test("A “none” component is absent rather than zero")
  func noneIsAMissingComponent() throws {
    let document = try Self.decode(#"""
    { "t": { "$type": "color", "c": { "$value": {
      "colorSpace": "oklch", "components": [0.7, 0.15, "none"] } } } }
    """#)

    let color = try #require(document.colors.first).color
    #expect(color.missing.contains(.component(2)))
    #expect(color.components.z == 0)
    #expect(!color.missing.contains(.component(0)))
  }

  @Test("Alpha defaults to fully opaque")
  func alphaDefaultsToOpaque() throws {
    let document = try Self.decode(#"""
    { "t": { "$type": "color", "c": { "$value": {
      "colorSpace": "srgb", "components": [0, 0, 0] } } } }
    """#)

    #expect(try #require(document.colors.first).color.alpha == 1)
  }

  /// Alpha clamps where the three components do not — the parser's rule, restated. There
  /// is nothing beyond fully opaque, while an out-of-gamut color has to stay writable.
  @Test("Alpha is clamped and components are not")
  func alphaClampsWhereComponentsDoNot() throws {
    let document = try Self.decode(#"""
    { "t": { "$type": "color", "c": { "$value": {
      "colorSpace": "srgb", "components": [1.4, -0.2, 0], "alpha": 1.5 } } } }
    """#)

    let color = try #require(document.colors.first).color
    #expect(color.alpha == 1)
    #expect(color.components.x == 1.4)
    #expect(color.components.y == -0.2)
  }

  @Test("An alpha of “none” is absent rather than rejected")
  func alphaCanBeNone() throws {
    let document = try Self.decode(#"""
    { "t": { "$type": "color", "c": { "$value": {
      "colorSpace": "srgb", "components": [0, 0, 0], "alpha": "none" } } } }
    """#)

    let color = try #require(document.colors.first).color
    #expect(color.missing.contains(.alpha))
    #expect(color.alpha == 1)
  }

  // MARK: - Types

  /// A group's `$type` reaches every token below it, however deep.
  @Test("A group's type reaches the tokens under it")
  func groupTypeIsInherited() throws {
    let document = try Self.decode(#"""
    { "palette": { "$type": "color", "brand": { "deep": { "$value": {
      "colorSpace": "srgb", "components": [0, 0, 1] } } } } }
    """#)

    #expect(document.colors.count == 1)
    #expect(try #require(document.colors.first).name == "palette.brand.deep")
  }

  /// The first arm of the format's precedence chain, which the other two tests here do
  /// not reach: a token's own `$type` beats the group's. A file that groups a stray color
  /// in with its spacing scale is odd but legal, and reading it as a dimension would drop
  /// a color that says plainly what it is.
  @Test("A token's own type beats the group's")
  func explicitTypeBeatsTheGroups() throws {
    let document = try Self.decode(#"""
    { "space": { "$type": "dimension",
      "sm": { "$value": "4px" },
      "tint": { "$type": "color", "$value": {
        "colorSpace": "srgb", "components": [0, 0, 1] } } } }
    """#)

    #expect(document.colors.map(\.name) == ["space.tint"])
    #expect(document.otherTypeCount == 1)
  }

  /// Tokens of other types are *counted*, not reported as failures. A real token file is
  /// mostly dimensions and typography, and listing three hundred of them as problems
  /// would bury the four that are.
  @Test("Tokens of other types are counted rather than skipped")
  func otherTypesAreCountedNotSkipped() throws {
    let document = try Self.decode(#"""
    { "space": { "$type": "dimension", "sm": { "$value": "4px" }, "md": { "$value": "8px" } },
      "brand": { "$type": "color", "blue": { "$value": {
        "colorSpace": "srgb", "components": [0, 0, 1] } } } }
    """#)

    #expect(document.colors.count == 1)
    #expect(document.otherTypeCount == 2)
    #expect(document.skipped.isEmpty)
  }

  // MARK: - References

  /// **The precedence that decides whether aliases can be resolved lazily: they cannot.**
  ///
  /// `semantic.primary` has no `$type` of its own and no group above it that supplies one.
  /// Its type comes from the token it references — which itself only has one by
  /// inheritance. Filter on `$type` before resolving and this token disappears without a
  /// word, which is the same class of defect as a key collision.
  @Test("A token takes its type from the token it references")
  func typeComesThroughAReference() throws {
    let document = try Self.decode(#"""
    { "palette": { "$type": "color", "blue": { "$value": {
        "colorSpace": "srgb", "components": [0, 0, 1] } } },
      "semantic": { "primary": { "$value": "{palette.blue}" } } }
    """#)

    #expect(document.colors.count == 2)
    let primary = try #require(document.colors.first { $0.name == "semantic.primary" })
    #expect(primary.color == ColorValue(space: .srgb, 0, 0, 1))
  }

  /// The current draft's JSON Pointer spelling of the same idea. Supported because a file
  /// using it would otherwise import as empty.
  @Test("A JSON Pointer reference resolves like a braced one")
  func jsonPointerReferencesResolve() throws {
    let document = try Self.decode(#"""
    { "palette": { "$type": "color", "blue": { "$value": {
        "colorSpace": "srgb", "components": [0, 0, 1] } } },
      "semantic": { "$type": "color",
        "primary": { "$value": { "$ref": "#/palette/blue/$value" } } } }
    """#)

    let primary = try #require(document.colors.first { $0.name == "semantic.primary" })
    #expect(primary.color == ColorValue(space: .srgb, 0, 0, 1))
  }

  /// A file that defines a token in terms of itself is legal JSON and a plausible
  /// hand-editing mistake. Without the visited set this test does not fail — it hangs.
  @Test("An alias cycle is reported rather than followed forever")
  func aliasCyclesTerminate() throws {
    let document = try Self.decode(#"""
    { "$type": "color",
      "a": { "$value": "{b}" },
      "b": { "$value": "{a}" } }
    """#)

    #expect(document.colors.isEmpty)
    #expect(document.skipped.count == 2)
    #expect(document.skipped.allSatisfy {
      if case .aliasCycle = $0.reason {
        true
      } else {
        false
      }
    })
  }

  @Test("A reference to a token that is not there is reported")
  func unresolvedAliasesAreReported() throws {
    let document = try Self.decode(#"""
    { "$type": "color", "a": { "$value": "{nowhere.at.all}" } }
    """#)

    #expect(document.skipped.first?.reason == .unresolvedAlias("nowhere.at.all"))
  }

  // MARK: - Failures within a readable file

  /// `hex` is a fallback for a space this build cannot construct — which is what makes it
  /// worth having at all, since the alternative for such a token is nothing.
  @Test("An unknown color space falls back to hex")
  func unknownSpaceFallsBackToHex() throws {
    let document = try Self.decode(#"""
    { "t": { "$type": "color", "c": { "$value": {
      "colorSpace": "cmyk", "components": [0, 1, 1, 0], "hex": "#3b82f6" } } } }
    """#)

    let expected = try CSSColorParser.parse("#3b82f6").color
    #expect(try #require(document.colors.first).color == expected)
  }

  @Test("An unknown color space with no hex is skipped")
  func unknownSpaceWithoutHexIsSkipped() throws {
    let document = try Self.decode(#"""
    { "t": { "$type": "color", "c": { "$value": {
      "colorSpace": "cmyk", "components": [0, 1, 1, 0] } } } }
    """#)

    #expect(document.colors.isEmpty)
    #expect(document.skipped.first?.reason == .unknownColorSpace("cmyk"))
  }

  /// **The discriminating case for what `hex` is *for*.**
  ///
  /// A known space with unreadable components is a broken token, and there is a hex right
  /// there to rescue it with. Taking it would silently substitute a 6-digit sRGB
  /// approximation for whatever the components meant — quietly wrong in the one direction
  /// this app refuses to be. So the fallback is for an unknown *space* only.
  @Test("A known space with broken components is skipped, hex or no hex")
  func brokenComponentsDoNotFallBackToHex() throws {
    let document = try Self.decode(#"""
    { "t": { "$type": "color", "c": { "$value": {
      "colorSpace": "display-p3", "components": [1, 0], "hex": "#3b82f6" } } } }
    """#)

    #expect(document.colors.isEmpty)
    #expect(document.skipped.count == 1)
    if case .malformedValue = try #require(document.skipped.first).reason {} else {
      Issue.record("Expected a malformed-value skip, got \(document.skipped)")
    }
  }

  @Test("A component that is neither a number nor “none” is skipped")
  func nonNumericComponentsAreSkipped() throws {
    let document = try Self.decode(#"""
    { "t": { "$type": "color", "c": { "$value": {
      "colorSpace": "srgb", "components": [1, "half", 0] } } } }
    """#)

    #expect(document.skipped.count == 1)
    #expect(document.colors.isEmpty)
  }

  // MARK: - A whole file

  /// **Every rule above, in one document, because they interact.**
  ///
  /// The tests either side of this each isolate a rule, which is what makes them
  /// diagnostic and also what makes them miss a file where an alias sits beside a
  /// dimension token beside two color spaces — the ordinary shape of a real token file.
  /// The three counts are asserted together because they are what the panel reports back,
  /// and a summary that says "imported 4, ignored 1" is only true if all three are.
  @Test("A realistic file imports as a whole")
  func awholeFileImports() throws {
    let document = try Self.decode(#"""
    { "brand": { "$type": "color",
        "50":  { "$value": { "colorSpace": "srgb", "components": [0.93, 0.96, 1] } },
        "500": { "$description": "The one on the buttons",
                 "$value": { "colorSpace": "srgb", "components": [0.23, 0.51, 0.96] } },
        "900": { "$value": { "colorSpace": "display-p3", "components": [0.05, 0.12, 0.42] } } },
      "semantic": { "primary": { "$value": "{brand.500}" } },
      "space": { "$type": "dimension", "sm": { "$value": "4px" } } }
    """#)

    #expect(document.colors.map(\.key) == ["brand-50", "brand-500", "brand-900", "semantic-primary"])
    #expect(document.otherTypeCount == 1)
    #expect(document.skipped.isEmpty)

    // The alias took both the value *and* the type of what it points at.
    let primary = try #require(document.colors.last)
    #expect(primary.color == ColorValue(space: .srgb, 0.23, 0.51, 0.96))
    // Spaces are per token, not per file.
    #expect(document.colors.map(\.color.space) == [.srgb, .srgb, .displayP3, .srgb])
    #expect(document.colors[1].description == "The one on the buttons")
  }

  // MARK: - Keys and order

  /// **Paths are unique; the keys they sanitize to are not.**
  ///
  /// `-` is a legal name character and `.` is not, so `brand.500` and `brand-500` are two
  /// distinct, legal tokens that reduce to one CSS identifier. Two entries sharing a key
  /// do not produce a duplicate property — they produce a single one, and a color vanishes
  /// from the export with nothing in the document to say so.
  @Test("Two paths that sanitize alike keep distinct keys")
  func sanitizedKeysAreMadeUnique() throws {
    let document = try Self.decode(#"""
    { "$type": "color",
      "brand": { "500": { "$value": { "colorSpace": "srgb", "components": [0, 0, 1] } } },
      "brand-500": { "$value": { "colorSpace": "srgb", "components": [1, 0, 0] } } }
    """#)

    let keys = document.colors.map(\.key)
    #expect(keys.count == 2)
    #expect(Set(keys).count == 2, "Two colors collapsed into one export key: \(keys)")
    #expect(keys.contains("brand-500"))
  }

  /// A ramp's order is its meaning, and `JSONSerialization` hands back an unordered
  /// dictionary — so an order has to be chosen. Alphabetically `1000` sorts between `100`
  /// and `50`, which is the failure this rule exists to prevent.
  @Test("Numeric names sort as numbers, not as text")
  func numericNamesSortNumerically() throws {
    let document = try Self.decode(#"""
    { "brand": { "$type": "color",
      "1000": { "$value": { "colorSpace": "srgb", "components": [0, 0, 0.1] } },
      "50":   { "$value": { "colorSpace": "srgb", "components": [0, 0, 0.2] } },
      "100":  { "$value": { "colorSpace": "srgb", "components": [0, 0, 0.3] } } } }
    """#)

    #expect(document.colors.map(\.path).map(\.last) == ["50", "100", "1000"])
  }

  @Test("A token's description travels with it")
  func descriptionsAreCarried() throws {
    let document = try Self.decode(#"""
    { "t": { "$type": "color", "c": {
      "$description": "The one on the buttons",
      "$value": { "colorSpace": "srgb", "components": [0, 0, 1] } } } }
    """#)

    #expect(try #require(document.colors.first).description == "The one on the buttons")
  }

  // MARK: - Not a token file at all

  /// Three ways a file can fail before any token is read, kept apart because a sandbox
  /// denial reported as "no color tokens" would be undiagnosable — see the panel's note.
  @Test("A file that is not JSON is rejected as such")
  func nonJSONIsRejected() {
    #expect(throws: DesignTokenError.notJSON) {
      try DesignTokenImport.decode(Data("not json at all".utf8))
    }
  }

  @Test("JSON that is not an object is rejected as such")
  func nonObjectJSONIsRejected() {
    #expect(throws: DesignTokenError.notAnObject) {
      try DesignTokenImport.decode(Data("[1, 2, 3]".utf8))
    }
  }

  @Test("A JSON object with no tokens in it is rejected as such")
  func objectWithoutTokensIsRejected() {
    #expect(throws: DesignTokenError.noTokens) {
      try DesignTokenImport.decode(Data(#"{ "a": { "b": {} } }"#.utf8))
    }
  }

  // MARK: Private

  private static func decode(_ json: String) throws -> DesignTokenDocument {
    try DesignTokenImport.decode(Data(json.utf8))
  }

  /// The CSS grammar whose *written* scale a space's token components would have to match.
  ///
  /// Every RGB-like space and both XYZ spaces are written through `color()`, whose
  /// components run 0–1 exactly as the format's do. `rgb()` is the one that disagrees, at
  /// 0–255, which is why an RGB space maps here to `color()` and not to `rgb()`.
  ///
  /// Lives in the tests because it is a cross-check rather than a step: the importer must
  /// not consult it, or a change to CSS spelling would change what a token file means.
  private static func writtenGrammar(for space: ColorSpace) -> [ComponentGrammar] {
    guard !space.isColorFunctionSpace else {
      return ColorGrammar.components(for: .color)
    }
    let function = ColorFunction.allCases.first { $0.space == space } ?? .color
    return ColorGrammar.components(for: function)
  }
}
