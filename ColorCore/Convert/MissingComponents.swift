//
//  MissingComponents.swift
//  ColorKit
//

import Foundation

// MARK: - Carrying missing components across a conversion

nonisolated extension ColorValue {
  /// Which components of `target` inherit this color's `none`s, per CSS Color 4 §13.2.
  ///
  /// Two mechanisms, and the second is easy to miss entirely:
  ///
  /// 1. **Individually analogous components.** A component whose ``ComponentRole``
  ///    also exists in `target` hands its missingness to that slot — the hue of
  ///    `hsl()` to the hue of `oklch()`, and so on.
  /// 2. **Analogous *sets*.** Whatever is left on each side after removing the
  ///    individually-analogous components forms a set, and if *every* member of
  ///    this color's set is missing, the whole of `target`'s set is missing. This
  ///    is what makes `lab(50% none none)` convert to `lch(50% none none)` rather
  ///    than `lch(50% 0 0)`, and `rgb(none none none)` convert to
  ///    `oklab(none none none)` even though sRGB and OKLab share no role at all.
  ///
  /// Alpha is analogous to alpha, and to nothing else.
  ///
  /// Note the asymmetry the set rule introduces: `lab(50% none none)` → `lch` carries
  /// both, while `lch(50% none none)` → `lab` also carries both, but
  /// `lab(50% 0 none)` → `lch` carries neither, because a set only travels whole.
  func carriedForwardMissing(to target: ColorSpace) -> ComponentMask {
    guard space != target else { return missing }

    // Alpha's role is itself, so it always carries.
    var carried: ComponentMask = missing.contains(.alpha) ? .alpha : []

    let sourceRoles = space.orderedComponentRoles
    var unpairedSource: [Int] = []

    for index in 0 ..< 3 {
      guard let paired = target.componentIndex(of: sourceRoles[index]) else {
        unpairedSource.append(index)
        continue
      }
      if missing.contains(.component(index)) {
        carried.insert(.component(paired))
      }
    }

    // The set rule. `allSatisfy` is vacuously true on an empty set, and an empty
    // one means every component paired off — in which case `target`'s leftovers
    // are empty too and the loop below does nothing. The guard says so out loud
    // rather than relying on that.
    guard !unpairedSource.isEmpty,
          unpairedSource.allSatisfy({ missing.contains(.component($0)) })
    else { return carried }

    let targetRoles = target.orderedComponentRoles
    for index in 0 ..< 3 where space.componentIndex(of: targetRoles[index]) == nil {
      carried.insert(.component(index))
    }
    return carried
  }

  /// This color in `target`, with missing components carried forward.
  ///
  /// The conversion itself is unchanged — ``converted(to:)`` stays a pure numeric
  /// operation, because the spec scopes carry-forward to *interpolation* and says
  /// something different about plain conversion (a converted color's own powerless
  /// components become missing, which is
  /// ``markingPowerlessComponents()``'s job and a presentation choice).
  ///
  /// - Important: This must run **before** any powerless-component handling, not
  ///   after. The spec is explicit about the ordering, and the reason is that the
  ///   two treatments of a missing component are not the same: a carried-forward
  ///   one takes the *other* color's value when interpolated, where a powerless one
  ///   is zero. Marking powerless components first, then carrying, would convert a
  ///   value the spec wants preserved into a zero.
  ///
  /// The components themselves keep whatever the conversion produced — a flag says
  /// the value is absent, it does not blank it. Interpolation substitutes the other
  /// color's value at the point of use.
  func convertedForInterpolation(to target: ColorSpace) -> ColorValue {
    var result = converted(to: target)
    result.missing = carriedForwardMissing(to: target)
    return result
  }
}
