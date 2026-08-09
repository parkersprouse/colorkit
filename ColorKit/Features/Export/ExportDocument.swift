//
//  ExportDocument.swift
//  ColorKit
//

import SwiftUI
import UniformTypeIdentifiers

/// The export document, wrapped so `.fileExporter` can write it.
///
/// A `FileDocument` over a `String` and nothing more. Deliberately not a
/// `ReferenceFileDocument` and deliberately not an app document model: this app has no
/// documents, it has a clipboard and now a save panel. The text always comes from
/// ``ColorStore/exportDocument``, which is generated in ColorCore — so the file, the
/// preview and the clipboard are one string with three destinations rather than three
/// renderings that can disagree.
///
/// `nonisolated` like everything else that is plain data here: the app builds with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, and `FileDocument`'s requirements are not
/// main-actor isolated, so without it the conformance does not compile.
nonisolated struct ExportDocument: FileDocument {
  // MARK: Lifecycle

  init(text: String) {
    self.text = text
  }

  /// Required by the protocol and unreachable, since ``readableContentTypes`` is empty.
  ///
  /// Throwing rather than returning an empty document, so that a future change making the
  /// type readable fails loudly instead of silently opening every file as blank.
  init(configuration _: ReadConfiguration) throws {
    throw CocoaError(.fileReadUnsupportedScheme)
  }

  // MARK: Internal

  /// Derived from ``ExportShape/contentType`` rather than listed a second time, so a shape
  /// cannot come to propose `brand.css` while the exporter refuses to write CSS. Deduped
  /// because four of the six shapes answer the same type.
  static let writableContentTypes: [UTType] = {
    var seen: [UTType] = []
    for type in ExportShape.allCases.map(\.contentType) where !seen.contains(type) {
      seen.append(type)
    }
    return seen
  }()

  /// Empty on purpose. The type is write-only, because opening a stylesheet is not
  /// something this app does — reading one back is M26's job and it goes through the
  /// pasteboard and `PaletteImport`, not through a document type. Declaring it readable
  /// would advertise this app in Finder's "Open With" for every `.css` on the disk.
  static let readableContentTypes: [UTType] = []

  let text: String

  func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: Data(text.utf8))
  }
}

nonisolated extension ExportShape {
  /// The concrete content type for this shape, for the save panel's benefit.
  ///
  /// Derived from ``fileExtension`` rather than transcribed a second time — one table, so
  /// a shape cannot propose one extension and tag the file as something else. The fallback
  /// is `.plainText`, which is true of all three and is what an extension the system does
  /// not recognize would deserve anyway.
  var contentType: UTType {
    UTType(filenameExtension: fileExtension) ?? .plainText
  }
}
