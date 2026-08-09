//
//  PrintedColors.swift
//  ColorKitCLITests
//

import Foundation

/// Every CSS color the CLI printed, whatever it printed around them.
///
/// **Structural rather than line-shaped, and it took two attempts to get there.** The
/// CLI writes colors into six document shapes and two listings, and each wraps them
/// differently: JSON and both Tailwind shapes quote and comma them, `declaration` follows
/// each with a `/* key */`, `solve` puts a ratio in a third column, and the `border` and
/// shadow templates bury the color mid-declaration. A "take everything after the first
/// space" reader agreed with three of those and quietly handed the other five a value
/// with punctuation stuck to it — which reads exactly like the serializer being broken.
///
/// So this looks for the two things a CSS color can be — a `#` run of hex digits, or an
/// identifier immediately followed by a balanced parenthesis group — and ignores
/// everything else. `@media (color-gamut: p3)` is excluded by the *immediately*: the
/// space after `@media` means that paren opens no function.
func printedColors(_ text: String) -> [String] {
  var found: [String] = []
  let characters = Array(text)
  var index = 0

  while index < characters.count {
    let character = characters[index]

    if character == "#" {
      var end = index + 1
      while end < characters.count, characters[end].isHexDigit {
        end += 1
      }
      if end > index + 1 {
        found.append(String(characters[index ..< end]))
        index = end
        continue
      }
    }

    if character == "(" {
      var start = index
      while start > 0, isIdentifierCharacter(characters[start - 1]) {
        start -= 1
      }
      // Only a *color* function counts. `tailwind-config` opens with
      // `/** @type {import('tailwindcss').Config} */`, and `import(…)` is an identifier
      // immediately followed by a balanced paren group like every color function is —
      // the one line in eight shapes' output where the shape rule alone is not enough.
      // The list comes from `ColorFunction`, so a function added there is covered.
      if start < index, colorFunctions.contains(String(characters[start ..< index])) {
        var depth = 0
        var end = index
        while end < characters.count {
          if characters[end] == "(" {
            depth += 1
          }
          if characters[end] == ")" {
            depth -= 1
            if depth == 0 {
              break
            }
          }
          end += 1
        }
        if end < characters.count {
          found.append(String(characters[start ... end]))
          index = end + 1
          continue
        }
      }
    }

    index += 1
  }

  return found
}

private let colorFunctions = Set(ColorFunction.allCases.map(\.rawValue) + ["color-mix"])

private func isIdentifierCharacter(_ character: Character) -> Bool {
  character.isLetter || character.isNumber || character == "-" || character == "_"
}
