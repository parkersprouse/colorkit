//
//  FormatSectionTests.swift
//  ColorKitTests
//

@testable import ColorKit
import Testing

/// The conversion panel renders sections, not the flat catalog, so a format that
/// exists in ColorCore but sits in no section is invisible to the user while every
/// core test still passes. This is the seam where that goes unnoticed.
@Suite("Conversion panel sections")
struct FormatSectionTests {
  @Test("Every catalog format is reachable from exactly one section")
  func sectionsPartitionCatalog() {
    let sectioned = FormatSection.all.flatMap(\.formats)

    // Set equality catches an omission; the count catches a format placed in two
    // sections, which set equality alone would happily allow.
    #expect(Set(sectioned) == Set(CSSOutputFormat.catalog))
    #expect(sectioned.count == CSSOutputFormat.catalog.count)
  }

  @Test("Sections keep the catalog's ordering")
  func sectionsPreserveCatalogOrder() {
    let sectioned = FormatSection.all.flatMap(\.formats)
    let catalogRank = Dictionary(
      uniqueKeysWithValues: CSSOutputFormat.catalog.enumerated().map { ($1, $0) },
    )

    // Reading order should match the deliberate ordering in the catalog, so the
    // two cannot be reshuffled independently and quietly disagree.
    let ranks = sectioned.compactMap { catalogRank[$0] }
    #expect(ranks == ranks.sorted())
  }

  @Test("Every format has a label")
  func everyFormatIsLabeled() {
    for format in CSSOutputFormat.catalog {
      #expect(!format.title.isEmpty)
    }
    #expect(CSSOutputFormat.color(.displayP3).title == "color(display-p3)")
  }

  // MARK: - Web-friendly mode (M22)

  @Test("The filtered sections partition webFriendly exactly")
  func webFriendlySectionsPartitionWebFriendlyFormats() {
    let sectioned = FormatSection.webFriendly.flatMap(\.formats)
    #expect(Set(sectioned) == Set(CSSOutputFormat.webFriendly))
    #expect(sectioned.count == CSSOutputFormat.webFriendly.count)
  }

  /// Wide gamut and Exact lose every one of their entries under the filter, which is
  /// the case the empty-section guard exists for — an empty "Wide gamut" header would
  /// be exactly the negative feedback the mode is built to avoid.
  @Test("Wide gamut and Exact are absent entirely, not merely emptied")
  func emptiedSectionsAreDropped() {
    let titles = Set(FormatSection.webFriendly.map(\.title))
    #expect(titles == ["Web", "Perceptual"])
  }
}
