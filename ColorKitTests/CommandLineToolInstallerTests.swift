//
//  CommandLineToolInstallerTests.swift
//  ColorKitTests
//

@testable import ColorKit
import Foundation
import Testing

/// - Note: `ColorKitTests` carries no `ENABLE_APP_SANDBOX` of its own — only the
///   app target does — so unlike ``ProjectsPanel``'s `NSOpenPanel`/`.fileImporter`
///   flows, ``CommandLineToolInstaller/install(embeddedBinary:into:)``'s real
///   filesystem writes *are* reachable here, against a plain temp directory rather
///   than a security-scoped bookmark. The only two things this file genuinely cannot
///   exercise are ``CommandLineToolInstaller/presentDestinationPicker(startingAt:)``
///   itself (a real `NSOpenPanel`) and what a *sandboxed* security-scoped claim does —
///   both recorded manual checks in PLAN.md's M29 entry.
@MainActor
@Suite("Command line tool installer")
struct CommandLineToolInstallerTests {
  // MARK: Internal

  // MARK: - Pure helpers

  @Test("The embedded binary sits in Contents/MacOS/cli, not Contents/Executables or bare Contents/MacOS")
  func embeddedBinaryURLPointsAtContentsMacOS() {
    let bundle = URL(fileURLWithPath: "/Applications/ColorKit.app")
    let result = CommandLineToolInstaller.embeddedBinaryURL(inBundleAt: bundle)
    #expect(result.path == "/Applications/ColorKit.app/Contents/MacOS/cli/colorkit")
  }

  @Test func destinationURLAppendsColorkit() {
    let directory = URL(fileURLWithPath: "/usr/local/bin")
    #expect(CommandLineToolInstaller.destinationURL(in: directory).path == "/usr/local/bin/colorkit")
  }

  @Test("Only a genuine App Translocation path is flagged")
  func isTranslocatedDetectsOnlyTheQuarantineCopy() {
    #expect(!CommandLineToolInstaller.isTranslocated(
      bundlePath: "/Applications/ColorKit.app/Contents/MacOS/cli/colorkit",
    ))
    #expect(CommandLineToolInstaller.isTranslocated(
      bundlePath: "/private/var/folders/xy/T/AppTranslocation/1234-5678/d/"
        + "ColorKit.app/Contents/MacOS/cli/colorkit",
    ))
  }

  // MARK: - PathAdvice

  @Test(
    "Well-known PATH directories read as likely already on PATH",
    arguments: ["/usr/local/bin", "/opt/homebrew/bin"],
  )
  func wellKnownDirectoriesAreLikelyOnPath(_ path: String) {
    let advice = CommandLineToolInstaller.adviceForInstalling(at: URL(fileURLWithPath: path))
    #expect(advice == .likelyOnPath)
  }

  @Test("A directory under $HOME gets a $HOME-relative profile line")
  func homeRelativeDirectorySpellsFromHOME() {
    let home = NSHomeDirectory()
    let directory = URL(fileURLWithPath: home).appending(path: "bin")

    guard case let .needsProfileLine(line) = CommandLineToolInstaller.adviceForInstalling(at: directory)
    else {
      Issue.record("expected .needsProfileLine")
      return
    }
    #expect(line.contains("$HOME/bin"))
    // The literal expanded home path must not leak into the line the user pastes —
    // that would be wrong the moment it runs on a different account.
    #expect(!line.contains(home))
  }

  @Test("A directory containing a space is quoted")
  func directoryContainingASpaceIsQuoted() {
    let directory = URL(fileURLWithPath: "/Users/Shared/My Tools")
    guard case let .needsProfileLine(line) = CommandLineToolInstaller.adviceForInstalling(at: directory)
    else {
      Issue.record("expected .needsProfileLine")
      return
    }
    #expect(line == "export PATH=\"/Users/Shared/My Tools:$PATH\"")
  }

  @Test("An arbitrary directory outside the well-known list still needs a profile line")
  func arbitraryDirectoryNeedsAProfileLine() {
    let advice = CommandLineToolInstaller.adviceForInstalling(at: URL(fileURLWithPath: "/opt/custom/bin"))
    #expect(advice == .needsProfileLine("export PATH=\"/opt/custom/bin:$PATH\""))
  }

  @Test("Every outcome has its own non-empty message", arguments: everyOutcome)
  func everyOutcomeHasANonEmptyMessage(_ outcome: CommandLineToolInstaller.InstallOutcome) {
    #expect(!outcome.message.isEmpty)
  }

  @Test("No two outcomes share a message")
  func everyOutcomesMessageIsDistinct() {
    let messages = Set(Self.everyOutcome.map(\.message))
    #expect(messages.count == Self.everyOutcome.count)
  }

  @Test("Only .success reports isSuccess")
  func onlySuccessReportsIsSuccess() {
    for outcome in Self.everyOutcome {
      if case .success = outcome {
        #expect(outcome.isSuccess)
      } else {
        #expect(!outcome.isSuccess)
      }
    }
  }

  /// The bug this test originally guarded against was real, not hypothetical:
  /// `/usr/local/bin` — this feature's own default destination — is `root:wheel 755`
  /// on a stock Mac and stays that way even with Homebrew installed on Apple Silicon,
  /// which lives under `/opt/homebrew` instead. A first version of this message said
  /// only "You don't have permission to write to that folder. Choose a different
  /// one." — true, but useless against the one destination the panel actually opens
  /// to by default, and the fix at the time was to add the failed directory *and* a
  /// `sudo chown`/`~/.local/bin` fix. **A 2026-08-14 wording pass shortened the
  /// message back down** — the directory is still named, but the specific fix is
  /// gone again; that shortening was a deliberate, confirmed choice, not a regression
  /// this test should still fail on. What remains worth pinning is the one fact that
  /// keeps the message from reading like the original bug: it names the directory.
  @Test("writeDenied names the failed directory")
  func writeDeniedMessageIsActionable() {
    let outcome = CommandLineToolInstaller.InstallOutcome.writeDenied(
      URL(fileURLWithPath: "/usr/local/bin"),
    )
    #expect(outcome.message.contains("/usr/local/bin"))
  }

  /// The bug this test guards against was also real, and reported by hand: a user
  /// whose `~/.local/bin` was already on their shell `$PATH` (`.writeDenied`'s own
  /// message used to suggest it) still got told the folder wasn't. `needsProfileLine`'s
  /// message must not *assert* the folder is missing — it can only honestly suggest
  /// checking, since this app has no way to read the user's real shell `$PATH` from
  /// inside the sandbox. **A 2026-08-14 wording pass rewrote the sentence again and,
  /// with it, stopped printing the associated profile line at all** — `message` no
  /// longer reads the case's payload (see `PathAdvice.needsProfileLine`'s doc comment),
  /// so this test no longer asserts the line appears. What still has to hold, and is
  /// the actual point of the test, is that the message keeps recommending a check
  /// (`colorkit --help`) instead of a flat claim that the folder is missing.
  @Test(".needsProfileLine suggests checking first, not that PATH is missing it")
  func needsProfileLineMessageDoesNotAssertPathIsMissing() {
    let line = "export PATH=\"$HOME/.local/bin:$PATH\""
    let outcome = CommandLineToolInstaller.InstallOutcome.success(.needsProfileLine(line))

    #expect(outcome.message.contains("colorkit --help"))
    // The old wording stated flatly that the folder was missing from PATH — wrong
    // whenever it happened to already be there, which is exactly what was reported.
    #expect(!outcome.message.contains("isn't on your PATH by default. Add"))
  }

  // MARK: - NSError → InstallOutcome mapping

  @Test("An already-exists error reports destinationOccupied, describing what's there")
  func alreadyExistsErrorDescribesASymlink() throws {
    let directory = try Self.makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let target = directory.appending(path: "elsewhere")
    let destination = CommandLineToolInstaller.destinationURL(in: directory)
    try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: target)

    let error = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteFileExistsError)
    let outcome = CommandLineToolInstaller.outcome(for: error, at: destination, scoped: true)

    guard case let .destinationOccupied(description) = outcome else {
      Issue.record("expected .destinationOccupied, got \(outcome)")
      return
    }
    #expect(description.contains("symlink to"))
    #expect(description.contains(target.path))
  }

  @Test("An already-exists error against a plain file says so, not \"symlink\"")
  func alreadyExistsErrorDescribesAPlainFile() throws {
    let directory = try Self.makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let destination = CommandLineToolInstaller.destinationURL(in: directory)
    try Data().write(to: destination)

    let error = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteFileExistsError)
    let outcome = CommandLineToolInstaller.outcome(for: error, at: destination, scoped: true)

    #expect(outcome == .destinationOccupied("a file"))
  }

  @Test("A permission error with a failed scope claim reads as securityScopeFailed")
  func permissionErrorWithFailedScopeReadsAsSecurityScopeFailed() {
    let error = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
    let destination = URL(fileURLWithPath: "/usr/local/bin/colorkit")
    #expect(
      CommandLineToolInstaller.outcome(for: error, at: destination, scoped: false)
        == .securityScopeFailed(URL(fileURLWithPath: "/usr/local/bin")),
    )
  }

  @Test("The identical permission error with a claimed scope reads as writeDenied")
  func permissionErrorWithClaimedScopeReadsAsWriteDenied() {
    let error = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
    let destination = URL(fileURLWithPath: "/usr/local/bin/colorkit")
    #expect(
      CommandLineToolInstaller.outcome(for: error, at: destination, scoped: true)
        == .writeDenied(URL(fileURLWithPath: "/usr/local/bin")),
    )
  }

  @Test("A POSIX EACCES with a failed scope claim also reads as securityScopeFailed")
  func posixPermissionErrorWithFailedScopeReadsAsSecurityScopeFailed() {
    let error = NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))
    let destination = URL(fileURLWithPath: "/usr/local/bin/colorkit")
    #expect(
      CommandLineToolInstaller.outcome(for: error, at: destination, scoped: false)
        == .securityScopeFailed(URL(fileURLWithPath: "/usr/local/bin")),
    )
  }

  @Test("An unrelated error falls back to writeDenied rather than a false already-exists claim")
  func unrelatedErrorFallsBackToWriteDenied() {
    let error = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)
    let destination = URL(fileURLWithPath: "/usr/local/bin/colorkit")
    #expect(
      CommandLineToolInstaller.outcome(for: error, at: destination, scoped: true)
        == .writeDenied(URL(fileURLWithPath: "/usr/local/bin")),
    )
  }

  // MARK: - install(embeddedBinary:into:) dispatch, and — since this target is unsandboxed — the real write too

  @Test("A translocated bundle is refused before anything touches the filesystem")
  func installRefusesATranslocatedBundle() {
    let translocatedBinary = URL(fileURLWithPath:
      "/private/var/folders/xy/T/AppTranslocation/1234-5678/d/ColorKit.app/Contents/MacOS/cli/colorkit")
    // A destination that does not exist: proof the guard fires before any directory
    // is ever touched, since a real write attempt here would itself fail differently.
    let nonExistentDirectory = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")

    let outcome = CommandLineToolInstaller.install(
      embeddedBinary: translocatedBinary,
      into: nonExistentDirectory,
    )
    #expect(outcome == .translocated)
  }

  @Test("A missing binary is reported before any directory is touched")
  func installReportsAMissingBinary() {
    let missingBinary = URL(fileURLWithPath: "/Applications/Nonexistent-\(UUID().uuidString).app/colorkit")
    let nonExistentDirectory = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")

    let outcome = CommandLineToolInstaller.install(embeddedBinary: missingBinary, into: nonExistentDirectory)
    #expect(outcome == .binaryMissing)
  }

  @Test("A real install creates a symlink pointing at the embedded binary")
  func installCreatesASymlinkToTheEmbeddedBinary() throws {
    let binary = try Self.makeExecutableFixture()
    defer { try? FileManager.default.removeItem(at: binary) }
    let directory = try Self.makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let outcome = CommandLineToolInstaller.install(embeddedBinary: binary, into: directory)

    guard case .success = outcome else {
      Issue.record("expected .success, got \(outcome)")
      return
    }
    let destination = CommandLineToolInstaller.destinationURL(in: directory)
    let target = try FileManager.default.destinationOfSymbolicLink(atPath: destination.path)
    #expect(target == binary.path)
  }

  @Test("A real install refuses to overwrite something already there")
  func installRefusesAnExistingDestination() throws {
    let binary = try Self.makeExecutableFixture()
    defer { try? FileManager.default.removeItem(at: binary) }
    let directory = try Self.makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let destination = CommandLineToolInstaller.destinationURL(in: directory)
    try Data("not colorkit".utf8).write(to: destination)

    let outcome = CommandLineToolInstaller.install(embeddedBinary: binary, into: directory)

    #expect(outcome == .destinationOccupied("a file"))
    // And the refusal really did refuse: the stale file is untouched.
    #expect(try Data(contentsOf: destination) == Data("not colorkit".utf8))
  }

  // MARK: Private

  // MARK: - InstallOutcome messages

  /// One representative instance per case — `InstallOutcome` carries associated
  /// values, so it cannot get `CaseIterable` for free the way `ExportShape` does, and
  /// this list stands in for it the same cheap way.
  private nonisolated static let everyOutcome: [CommandLineToolInstaller.InstallOutcome] = [
    .translocated,
    .binaryMissing,
    .destinationOccupied("a file"),
    .securityScopeFailed(URL(fileURLWithPath: "/usr/local/bin")),
    .writeDenied(URL(fileURLWithPath: "/usr/local/bin")),
    .success(.likelyOnPath),
    .success(.needsProfileLine("export PATH=\"$HOME/bin:$PATH\"")),
  ]

  private static func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "CommandLineToolInstallerTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  /// A file that merely needs to exist — `install`'s own binary-exists check is a
  /// plain `fileExists(atPath:)`, not a Mach-O validity check.
  private static func makeExecutableFixture() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "colorkit-fixture-\(UUID().uuidString)")
    try Data("#!/bin/sh\n".utf8).write(to: url)
    return url
  }
}
