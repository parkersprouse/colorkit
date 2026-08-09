//
//  Clipboard.swift
//  ColorKit
//

import AppKit

/// The system pasteboard, behind a name that says what it is used for.
///
/// A one-function wrapper earns its keep here: `NSPasteboard` requires
/// `clearContents()` before every write — skip it and the new value is appended as an
/// additional representation instead of replacing the old one, so paste can return a
/// stale color. Having exactly one call site makes that impossible to forget.
enum Clipboard {
  /// The pasteboard's current text, if it holds any.
  static var text: String? {
    NSPasteboard.general.string(forType: .string)
  }

  static func copy(_ string: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(string, forType: .string)
  }
}
