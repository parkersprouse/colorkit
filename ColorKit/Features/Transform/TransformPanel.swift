//
//  TransformPanel.swift
//  ColorKit
//

import SwiftUI

/// Four things to do with a color you already have: nudge it, find its relatives, build
/// a ramp from it, or make it legible.
///
/// Every section follows the same shape — the panel's color goes in, one or more colors
/// come out, and any of them can be clicked to become the panel's color. That is what
/// makes the tools compose: derive a triad, adopt one member, ramp *that*. Nothing here
/// mutates anything until you click, so the whole panel is a preview.
///
/// **The pending adjustment lives here, not on the store**, unlike the harmony and ramp
/// settings beside it. Those are preferences — how you like to work — and losing them on
/// every trip through another tool would be a small rudeness. A half-dialed adjustment
/// is the opposite: an unfinished edit, and finding it still applied on the way back
/// would mean this panel was previewing a color the input field does not contain.
struct TransformPanel: View {
  // MARK: Internal

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        if let color = store.color {
          adjustSection(color)
          Divider()
          harmonySection(color)
          Divider()
          rampSection(color)
          // Hidden rather than restricted under web-friendly (M22): CSS Color 4 §12
          // has no gamut-mapping step, so a mix has no honest sRGB-only answer —
          // restricting the interpolation space would only guarantee an in-gamut
          // result for in-gamut endpoints, and the field still accepts a typed
          // out-of-gamut one even under the flag. See PLAN.md.
          if !store.webFriendly {
            Divider()
            mixSection(color)
          }
          Divider()
          legibilitySection(color)
        } else {
          ContentUnavailableView(
            "No color yet",
            systemImage: "dial.medium",
            description: Text(
              "Type a CSS color above and everything derived from it appears here.",
            ),
          )
          .frame(maxWidth: .infinity)
        }
      }
      .padding(16)
    }
  }

  // MARK: Private

  /// Where the mix strip samples. Five is enough to read as a gradient and few enough
  /// that each swatch stays clickable.
  private static let mixStops = [0.0, 0.25, 0.5, 0.75, 1.0]

  @Environment(ColorStore.self) private var store

  /// Reset by ``apply(_:)``, because an adjustment is relative: leaving the sliders up
  /// after adopting their result would compound the same nudge on every click.
  @State private var adjustment = OKLCHAdjustment.identity
  @State private var curve = LightnessCurve.identity

  /// How far the contrast section has pushed the color away from the background.
  /// Panel state for the same reason as `adjustment` — an unfinished edit.
  @State private var push = 0.0

  /// How much of the background the mix section is pulling in. Panel state for the
  /// same reason again, and reset by ``apply(_:)`` for the reason the push is: a mix
  /// is relative to the color it starts from, so leaving it up would blend the
  /// background in a second time on the next click.
  @State private var mixAmount = 0.0

  /// The curve's caption, which has to explain a slider whose units nobody knows.
  private var curveCaption: String {
    if curve.isIdentity {
      return "no bend"
    }
    return curve.strength > 0
      ? String(format: "punchier · γ %.2f", curve.gamma)
      : String(format: "flatter · γ %.2f", curve.gamma)
  }

  private func adjustSection(_ color: ColorValue) -> some View {
    let result = adjusted(color)
    let isPending = !adjustment.isIdentity || !curve.isIdentity

    return VStack(alignment: .leading, spacing: 12) {
      sectionHeading(
        "Adjust",
        note: "Relative, so it composes: the picker already sets L, C and h outright.",
      )

      slider(
        "Lightness",
        value: Binding(
          get: { adjustment.lightnessDelta },
          set: { adjustment.lightnessDelta = $0 },
        ),
        range: -0.5 ... 0.5,
        caption: signed(adjustment.lightnessDelta, decimals: 3),
      )
      slider(
        "Chroma",
        value: Binding(
          get: { adjustment.chromaScale },
          set: { adjustment.chromaScale = $0 },
        ),
        range: 0 ... 2,
        caption: String(format: "×%.2f", adjustment.chromaScale),
      )
      slider(
        "Hue",
        value: Binding(
          get: { adjustment.hueRotation },
          set: { adjustment.hueRotation = $0 },
        ),
        range: -180 ... 180,
        caption: signed(adjustment.hueRotation, decimals: 0) + "°",
      )
      slider(
        "Curve",
        value: Binding(get: { curve.strength }, set: { curve.strength = $0 }),
        range: -1 ... 1,
        caption: curveCaption,
      )

      HStack(alignment: .center, spacing: 14) {
        labeledSwatch(color, caption: "Now", identifier: "transformNow") {
          adjustment = .identity
          curve = .identity
        }
        Image(systemName: "arrow.right").foregroundStyle(.secondary)
        labeledSwatch(
          result,
          caption: isPending ? "Adjusted" : "Unchanged",
          identifier: "transformAdjustedSwatch",
        ) {
          adjustment = .identity
          curve = .identity
        }

        VStack(alignment: .leading, spacing: 6) {
          Text(css(result))
            .font(.system(.callout, design: .monospaced))
            .textSelection(.enabled)
            .accessibilityIdentifier("transformAdjusted")
          if !result.inGamut(of: .srgb) {
            ColorBadge(text: "outside sRGB")
          }
        }
        Spacer()
      }

      HStack(spacing: 10) {
        Button("Apply") { apply(result) }
          .disabled(!isPending)
          .accessibilityIdentifier("transformApply")
        Button("Reset") {
          adjustment = .identity
          curve = .identity
        }
        .disabled(!isPending)
      }
    }
  }

  // MARK: - Harmony

  private func harmonySection(_ color: ColorValue) -> some View {
    @Bindable var store = store
    // `store.effectiveHarmonyOptions` rather than `store.harmonyOptions` directly —
    // the same options `entries(for: .harmony)` reads, so this preview and an
    // exported harmony can never disagree about whether web-friendly mode (M22)
    // pulled a member back inside sRGB.
    let options = store.effectiveHarmonyOptions
    let members = color.harmony(store.harmony, options: options)
    let baseIndex = store.harmony.baseIndex(options: options)

    return VStack(alignment: .leading, spacing: 12) {
      sectionHeading(
        "Harmony",
        note: "Turned on OKLCH's wheel, where equal degrees are equal steps.",
      )

      Picker("Harmony", selection: $store.harmony) {
        ForEach(Harmony.allCases) { harmony in
          Text(HarmonyPresentation.of(harmony).title).tag(harmony)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()

      Text(HarmonyPresentation.of(store.harmony).summary)
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      if store.harmony == .analogous {
        slider(
          "Spread",
          value: $store.harmonyOptions.analogousSpread,
          range: 5 ... 90,
          caption: String(format: "±%.0f°", store.harmonyOptions.analogousSpread),
        )
      }

      // A gray has no hue, so it has no relatives. Said plainly rather than shown
      // as five identical swatches with no explanation.
      if color.isAchromatic, store.harmony != .monochromatic {
        Label(
          "A gray has no hue to turn, so every member is the same color. "
            + "Monochromatic still works.",
          systemImage: "info.circle",
        )
        .font(.callout)
        .foregroundStyle(.secondary)
      }

      swatchRow(members, identifier: "transformHarmony", markingBaseAt: baseIndex)
    }
  }

  // MARK: - Ramp

  private func rampSection(_ color: ColorValue) -> some View {
    @Bindable var store = store
    let stops = store.shadeRamp.generated(from: color)

    return VStack(alignment: .leading, spacing: 12) {
      sectionHeading(
        "Shade ramp",
        note: "Chroma tapers toward the ends and no stop leaves the gamut, "
          + "which is what a constant-chroma ramp gets wrong.",
      )

      HStack(spacing: 18) {
        Stepper(
          "Stops: \(ShadeRamp.stopCount(for: store.shadeRamp.stops))",
          value: $store.shadeRamp.stops,
          in: 3 ... 21,
          step: 2,
        )
        .fixedSize()
        Spacer()
      }

      slider(
        "Taper",
        value: $store.shadeRamp.chromaTaper,
        range: 0 ... 1,
        caption: store.shadeRamp.chromaTaper == 0
          ? "none · the naive ramp"
          : String(
            format: "ends keep %.0f%%",
            (1 - store.shadeRamp.chromaTaper) * 100,
          ),
      )

      swatchRow(
        stops,
        identifier: "transformRamp",
        markingBaseAt: stops.count / 2,
      )
    }
  }

  // MARK: - Mix

  /// `color-mix()`, against the background the contrast tool already holds.
  ///
  /// The second color is the background rather than a third field of this panel's own,
  /// for the reason the legibility section below takes it: the app already edits a
  /// *pair*, and inventing another color to type would make this the only section that
  /// does not compose with the rest of the app.
  ///
  /// The strip is the live preview and the slider is the pending edit — the same split
  /// as the contrast push, and for the same reason. Every stop on the strip is a color
  /// you can click, so the section is useful with the slider left alone.
  private func mixSection(_ color: ColorValue) -> some View {
    @Bindable var store = store

    return VStack(alignment: .leading, spacing: 12) {
      sectionHeading(
        "Mix",
        note: "Blended with the background. The space is the whole choice: sRGB runs "
          + "through a washed-out middle where OKLCH keeps the chroma.",
      )

      HStack(spacing: 18) {
        Picker("Space", selection: $store.mixSpace) {
          ForEach(ColorSpace.allCases, id: \.self) { space in
            // The CSS identifier rather than a display name, because it is what goes
            // in the expression underneath — a fact, not editorial copy.
            Text(space.rawValue).tag(space)
          }
        }
        .fixedSize()
        .accessibilityIdentifier("transformMixSpace")

        // A rectangular space has no arc to choose, and CSS forbids writing one down.
        if store.mixSpace.hueIndex != nil {
          Picker("Hue", selection: $store.mixHueMethod) {
            ForEach(HueInterpolationMethod.allCases) { method in
              Text(method.rawValue).tag(method)
            }
          }
          .fixedSize()
          .accessibilityIdentifier("transformMixHue")
        }
        Spacer()
      }

      if let background = store.backgroundColor {
        mixBody(color: color, background: background)
      } else {
        Label(
          "Set a background in the Contrast tool — a mix needs two colors.",
          systemImage: "circle.lefthalf.filled",
        )
        .font(.callout)
        .foregroundStyle(.secondary)
      }
    }
  }

  private func mixBody(color: ColorValue, background: ColorValue) -> some View {
    let interpolation = ColorInterpolation(space: store.mixSpace, hue: store.mixHueMethod)
    let stops = Self.mixStops.map {
      color.mixed(with: background, using: interpolation, at: $0)
    }
    let mixed = color.mixed(with: background, using: interpolation, at: mixAmount)

    return VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        // The text initializer: this is `store.backgroundColor` rendered, and it has
        // an authored spelling of its own — see the identical reasoning at
        // `ContrastPanel`'s background swatch.
        SwatchButton(
          color: background,
          text: store.backgroundText,
          cornerRadius: 6,
          accessibilityIdentifier: "transformMixBackground",
        )
        .frame(width: 24, height: 24)
        Text("with \(css(background))")
          .font(.system(.caption, design: .monospaced))
          .foregroundStyle(.secondary)
        Spacer()
      }

      // The base is the first stop, which really is the panel's own color: a mix at 0%
      // is the color untouched.
      swatchRow(stops, identifier: "transformMix", markingBaseAt: 0)

      slider(
        "Amount",
        value: $mixAmount,
        range: 0 ... 1,
        caption: mixAmount == 0
          ? "all yours"
          : String(format: "%.0f%% of the background", mixAmount * 100),
      )

      if mixAmount != 0 {
        HStack(alignment: .center, spacing: 14) {
          labeledSwatch(mixed, caption: "Mixed", identifier: "transformMixedSwatch") {
            mixAmount = 0
          }

          VStack(alignment: .leading, spacing: 6) {
            Text(css(mixed))
              .font(.system(.callout, design: .monospaced))
              .textSelection(.enabled)
              .accessibilityIdentifier("transformMixResult")
            Text(mixExpression(color, background))
              .font(.system(.caption, design: .monospaced))
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
              .accessibilityIdentifier("transformMixExpression")
            if !mixed.inGamut(of: .srgb) {
              ColorBadge(text: "outside sRGB")
            }
            Button("Use it") { apply(mixed) }
              .accessibilityIdentifier("transformUseMix")
          }
          Spacer()
        }
      }
    }
  }

  // MARK: - Legibility

  private func legibilitySection(_ color: ColorValue) -> some View {
    @Bindable var store = store

    return VStack(alignment: .leading, spacing: 12) {
      sectionHeading(
        "Make it legible",
        note: "Push it by hand or jump to a target. Both move lightness only, so "
          + "the color keeps its hue and its chroma.",
      )

      Picker("Target", selection: $store.contrastTarget) {
        ForEach(RequirementPresentation.all) { presentation in
          Text(
            "\(presentation.title) · \(ratioText(presentation.requirement.minimumRatio))",
          )
          .tag(presentation.requirement)
        }
      }
      .accessibilityIdentifier("transformTargetPicker")

      if let background = store.backgroundColor {
        solverBody(color: color, background: background)
      } else {
        Label(
          "Set a background in the Contrast tool — legibility is a property of "
            + "a pair.",
          systemImage: "circle.lefthalf.filled",
        )
        .font(.callout)
        .foregroundStyle(.secondary)
      }
    }
  }

  private func solverBody(color: ColorValue, background: ColorValue) -> some View {
    let target = store.contrastTarget.minimumRatio
    let current = color.contrastRatio(with: background)
    let ceiling = ContrastSolver.ceiling(against: background)
    let solutions = ContrastSolver.solutions(
      for: color,
      on: background,
      target: target,
      gamut: store.webFriendly ? .srgb : nil,
    )

    return VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        SwatchButton(
          color: background,
          text: store.backgroundText,
          cornerRadius: 6,
          accessibilityIdentifier: "transformSolverBackground",
        )
        .frame(width: 24, height: 24)
        Text("on \(css(background))")
          .font(.system(.caption, design: .monospaced))
          .foregroundStyle(.secondary)
        Spacer()
        Text("now \(ratioText(current))")
          .font(.system(.callout, design: .monospaced))
          .accessibilityIdentifier("transformCurrentRatio")
      }

      pushControl(color: color, background: background)

      if color.meets(store.contrastTarget, on: background) {
        Label(
          "Already reaches \(ratioText(target)) — nothing to fix.",
          systemImage: "checkmark.circle.fill",
        )
        .font(.callout)
        .foregroundStyle(.green)
        .accessibilityIdentifier("transformSolverVerdict")
      } else if solutions.isEmpty {
        // The honest failure, and the one people do not expect: in the middle of
        // the luminance range the ceiling is far below AAA, so this is not a
        // hard target but an impossible one.
        Label(
          "Out of reach on this background. No color at all beats "
            + "\(ratioText(ceiling)) here, so \(ratioText(target)) is "
            + "impossible — change the background.",
          systemImage: "exclamationmark.triangle.fill",
        )
        .font(.callout)
        .foregroundStyle(.orange)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("transformSolverVerdict")
      } else {
        Text(
          solutions.count == 1
            ? "One way out of it:"
            : "Two ways out of it — the nearest is marked.",
        )
        .font(.callout)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("transformSolverVerdict")

        // Only worth marking when there is something to compare it against —
        // "nearest" beside a lone option is noise.
        let nearest = solutions.count > 1
          ? solutions.min { abs($0.lightnessDelta) < abs($1.lightnessDelta) }
          : nil

        HStack(alignment: .top, spacing: 14) {
          ForEach(solutions, id: \.direction) { solution in
            solutionColumn(
              solution,
              background: background,
              isNearest: solution == nearest,
            )
          }
          Spacer()
        }
      }
    }
  }

  /// The manual half of the contrast tool: drag, and watch the ratio move.
  ///
  /// Right is always *more* contrast, whichever polarity the pair is — the direction
  /// comes from ``ContrastSolver/awayFromBackground(for:on:)`` rather than from a fixed
  /// sign, so this control means the same thing for dark text on light and for light
  /// text on dark. Dragging left far enough crosses the background's own luminance and
  /// the ratio climbs again, which is the V in person and the reason the number beside
  /// the slider is live rather than derived from the slider's sign.
  private func pushControl(color: ColorValue, background: ColorValue) -> some View {
    let pushed = ContrastSolver.pushed(
      color,
      on: background,
      by: push,
      gamut: store.webFriendly ? .srgb : nil,
    )
    let ratio = pushed.contrastRatio(with: background)
    let direction = ContrastSolver.awayFromBackground(for: color, on: background)

    return VStack(alignment: .leading, spacing: 8) {
      slider(
        "Push",
        value: $push,
        range: -0.4 ... 0.4,
        caption: push == 0
          ? "\(direction.rawValue) is apart"
          : "\(ratioText(ratio)) · \(signed(push, decimals: 2)) L",
      )

      if push != 0 {
        HStack(spacing: 12) {
          sample(text: pushed, background: background)
            .frame(maxWidth: 260)

          VStack(alignment: .leading, spacing: 4) {
            Text(css(pushed))
              .font(.system(.caption, design: .monospaced))
              .textSelection(.enabled)
              .accessibilityIdentifier("transformPushed")
            // Pushing a saturated color toward either end of the lightness
            // scale leaves sRGB long before the end, which is why the
            // spelling above turns into `color(display-p3 …)` — the app
            // declines to spell a wide color as hex. Said out loud here for
            // the same reason the Adjust section says it.
            if !pushed.inGamut(of: .srgb) {
              ColorBadge(text: "outside sRGB")
            }
            Button("Use it") { apply(pushed) }
              .accessibilityIdentifier("transformUsePushed")
          }
          Spacer()
        }
      }
    }
  }

  private func sample(text: ColorValue, background: ColorValue) -> some View {
    Text("The quick brown fox")
      .font(.system(size: 14, weight: .medium))
      .foregroundStyle(text.displayColor)
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(background.displayColor, in: RoundedRectangle(cornerRadius: 8))
      .overlay(
        RoundedRectangle(cornerRadius: 8)
          .strokeBorder(.separator.opacity(0.5), lineWidth: 1),
      )
  }

  private func solutionColumn(
    _ solution: ContrastSolution,
    background: ColorValue,
    isNearest: Bool,
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Button {
        apply(solution.color)
      } label: {
        Text("The quick brown fox")
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(solution.color.displayColor)
          .padding(10)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(
            background.displayColor, in: RoundedRectangle(cornerRadius: 8),
          )
          .overlay(
            RoundedRectangle(cornerRadius: 8)
              // Erased, because the two branches are different
              // `ShapeStyle` types and a ternary has to pick one.
              .strokeBorder(
                isNearest
                  ? AnyShapeStyle(Color.accentColor)
                  : AnyShapeStyle(.separator.opacity(0.5)),
                lineWidth: isNearest ? 2 : 1,
              ),
          )
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("\(solution.direction.rawValue), \(css(solution.color))")
      .accessibilityIdentifier("transformSolution-\(solution.direction.rawValue)")
      .help("Use \(css(solution.color)) — \(ratioText(solution.ratio))")

      HStack(spacing: 6) {
        Text(solution.direction.rawValue.capitalized)
          .font(.caption.weight(.medium))
        Text(ratioText(solution.ratio))
          .font(.system(.caption, design: .monospaced))
          .foregroundStyle(.secondary)
        if isNearest {
          ColorBadge(text: "nearest", tint: .accentColor)
        }
      }
    }
    .frame(maxWidth: 240)
  }

  // MARK: - Shared pieces

  private func sectionHeading(_ title: String, note: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title).font(.headline)
      Text(note)
        .font(.caption)
        .foregroundStyle(.tertiary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  /// A labeled slider with a value readout, which every section needs and macOS does
  /// not provide — a `Slider`'s own label renders as visible text beside it.
  private func slider(
    _ label: String,
    value: Binding<Double>,
    range: ClosedRange<Double>,
    caption: String,
  ) -> some View {
    HStack(spacing: 12) {
      Text(label)
        .font(.callout)
        .frame(width: 74, alignment: .leading)
      Slider(value: value, in: range)
        .labelsHidden()
        .accessibilityLabel(label)
      Text(caption)
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.secondary)
        .frame(width: 132, alignment: .trailing)
    }
  }

  /// A row of derived colors, any of which can become the panel's color.
  ///
  /// Each swatch is a button carrying its own CSS as its accessibility label. Not
  /// decoration: a bare swatch announces nothing at all to VoiceOver, and it is also
  /// the only handle a UI test has on a row of colored rectangles.
  private func swatchRow(
    _ colors: [ColorValue],
    identifier: String,
    markingBaseAt baseIndex: Int,
  ) -> some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(alignment: .top, spacing: 8) {
        ForEach(Array(colors.enumerated()), id: \.offset) { index, color in
          let isBase = index == baseIndex
          VStack(spacing: 5) {
            // The accent ring is a *sibling* in this ZStack, not an overlay on the
            // button inside `SwatchButton` — the same accessibility trap
            // `ProjectsPanel.savedColorTile` documents. Decorative chrome layered
            // directly on a `Button` vanishes from the tree; a sibling stays visible.
            ZStack {
              SwatchButton(
                color: color,
                preferring: .oklch,
                cornerRadius: 7,
                accessibilityIdentifier: "\(identifier)-\(index)",
              )
              .frame(width: 46, height: 52)
              .help("Use \(css(color))")

              if isBase {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                  .strokeBorder(Color.accentColor, lineWidth: 2)
                  .allowsHitTesting(false)
              }
            }
            .frame(width: 46, height: 52)

            if isBase {
              Text("yours")
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else if !color.inGamut(of: .srgb) {
              Text("wide")
                .font(.caption2)
                .foregroundStyle(.orange)
                .help("Outside sRGB. Kept exact rather than mapped in.")
            }
          }
        }
      }
      .padding(.vertical, 2)
    }
  }

  /// `onAdopt` is required, not defaulted, because every call site here shows a
  /// *pending, relative* result — adopting one without also clearing whatever produced
  /// it would let the next click through "Apply" or "Use it" compound the same nudge a
  /// second time. See the note on ``SwatchButton``.
  private func labeledSwatch(
    _ color: ColorValue,
    caption: String,
    identifier: String,
    onAdopt: @escaping () -> Void,
  ) -> some View {
    VStack(spacing: 6) {
      SwatchButton(
        color: color,
        preferring: .oklch,
        cornerRadius: 10,
        accessibilityIdentifier: identifier,
        onAdopt: onAdopt,
      )
      .frame(width: 76, height: 54)
      Text(caption)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  /// The `color-mix()` that produces what the panel is showing, spelled to paste.
  ///
  /// Worth showing beside the result rather than only the result, because this app now
  /// *reads* the syntax as well as computing it — so the line below the swatch is
  /// something you can put straight back in the field. Both colors are printed at
  /// display precision, like every other caption here, so pasting it reproduces the
  /// preview to the digits shown rather than to the last bit.
  private func mixExpression(_ color: ColorValue, _ background: ColorValue) -> String {
    let arc = store.mixSpace.hueIndex == nil ? "" : " \(store.mixHueMethod.rawValue) hue"
    let share = String(format: "%.0f%%", (1 - mixAmount) * 100)
    return "color-mix(in \(store.mixSpace.rawValue)\(arc), "
      + "\(css(color)) \(share), \(css(background)))"
  }

  // MARK: - Adjust

  /// The color as the sliders currently describe it. Curve after adjustment, because
  /// the curve is about where a lightness sits on the scale and the adjustment is what
  /// decides that.
  ///
  /// Pulled into sRGB under web-friendly (M22) — at the call site rather than as a
  /// field on `OKLCHAdjustment`/`LightnessCurve` themselves, since both are transient
  /// per-drag state (not a persisted preference like `HarmonyOptions`), and a stored
  /// `gamut` would change their `Equatable` conformance and light up "Apply"/"Reset"
  /// with nothing actually pending the moment the mode is on.
  private func adjusted(_ color: ColorValue) -> ColorValue {
    let result = curve.applied(to: adjustment.applied(to: color))
    return store.webFriendly ? result.pulledInto(.srgb) : result
  }

  // MARK: - Output

  /// Adopts a derived color and clears the pending adjustment.
  ///
  /// `preferring: .oklch` rather than hex, and for the reason the picker's OKLCH mode
  /// writes the same format: every transform here computes in OKLCH and half of them
  /// can leave the sRGB gamut, so hex would quantize the result onto the 8-bit grid or
  /// map it in outright. The store keeps *text* as its source of truth, which makes
  /// either loss permanent.
  private func apply(_ color: ColorValue) {
    store.adopt(color, preferring: .oklch)
    store.remember()
    adjustment = .identity
    curve = .identity
    // The push is relative too, so leaving it up would apply the same shove again
    // to a color that has already taken it. The mix amount is relative in exactly
    // the same way — repeated applications converge on the background.
    push = 0
    mixAmount = 0
  }

  /// Display precision, not storage precision — this is a caption, and the string that
  /// actually lands in the field goes through ``ColorStore/adopt(_:preferring:)``.
  private func css(_ color: ColorValue) -> String {
    color.cssStringOrHex(
      as: color.spelling(preferring: .hex),
      options: store.formatOptions,
    )
  }

  private func ratioText(_ ratio: Double) -> String {
    String(format: "%.2f:1", ratio)
  }

  private func signed(_ value: Double, decimals: Int) -> String {
    let formatted = String(format: "%.\(decimals)f", value)
    return value > 0 ? "+\(formatted)" : formatted
  }
}

/// Wording for each harmony, kept out of ColorCore.
///
/// ``Harmony`` carries the angles, which are facts. What a split-complementary is *for*
/// is editorial — the same split ``CVDPresentation`` and ``RequirementPresentation``
/// keep.
struct HarmonyPresentation {
  let harmony: Harmony
  let title: String
  let summary: String

  static func of(_ harmony: Harmony) -> HarmonyPresentation {
    switch harmony {
    case .complementary:
      HarmonyPresentation(
        harmony: harmony,
        title: "Comp",
        summary: "The hue directly opposite. Maximum separation, and the pairing "
          + "most likely to shout — good for one accent against a base.",
      )
    case .splitComplementary:
      HarmonyPresentation(
        harmony: harmony,
        title: "Split",
        summary: "The two hues either side of the complement. Nearly the contrast "
          + "of a complement without the head-on collision.",
      )
    case .triad:
      HarmonyPresentation(
        harmony: harmony,
        title: "Triad",
        summary: "Three hues evenly spaced. Balanced and vivid; usually wants one "
          + "dominant member and two accents rather than equal billing.",
      )
    case .tetrad:
      HarmonyPresentation(
        harmony: harmony,
        title: "Tetrad",
        summary: "Four hues evenly spaced — two complementary pairs. The most "
          + "colors a small interface can usually carry.",
      )
    case .analogous:
      HarmonyPresentation(
        harmony: harmony,
        title: "Analogous",
        summary: "Immediate neighbours. Quiet and cohesive, with little contrast "
          + "of its own, so lean on lightness to separate them.",
      )
    case .monochromatic:
      HarmonyPresentation(
        harmony: harmony,
        title: "Mono",
        summary: "One hue, many lightnesses — a short shade ramp, so it inherits "
          + "the tapering and stays in gamut.",
      )
    }
  }
}
