// The entry point, and nothing else.
//
// It lives in its own root group because top-level code is only legal in an
// executable module: `ColorKitCLI/` is compiled by the CLI *and* by the CLI's
// test bundle, and a `main.swift` in that group would fail the second one. Two
// root groups is the whole fix — no synchronized-group membership exceptions to
// keep in step with the file system.

import Foundation

let outcome = ColorKitCLI.run(Array(CommandLine.arguments.dropFirst()))

if !outcome.output.isEmpty {
  print(outcome.output)
}

if !outcome.diagnostic.isEmpty {
  FileHandle.standardError.write(Data((outcome.diagnostic + "\n").utf8))
}

exit(outcome.status.code)
