//
//  ColorSwatch.swift
//  ColorKit
//

import SwiftUI

/// A color chip drawn over a checkerboard, so partial alpha is visible rather than
/// silently composited against whatever happens to be behind it.
struct ColorSwatch: View {
  // MARK: Internal

  let color: ColorValue
  var cornerRadius: CGFloat = 8
  var checkerSize: CGFloat = 5

  var body: some View {
    ZStack {
      if color.alpha < 1 {
        Checkerboard(squareSize: checkerSize)
      }
      Rectangle().fill(color.displayColor)
    }
    .clipShape(shape)
    // A hairline border, or a white swatch vanishes into a light window and a
    // black one into a dark one.
    .overlay {
      shape.strokeBorder(.separator, lineWidth: 1)
    }
  }

  // MARK: Private

  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
  }
}

/// A ``ColorSwatch`` wrapped in a real control: a tap to adopt the color, a menu with a
/// couple more ways to use it, and the accessibility a plain rectangle has none of.
///
/// Two initializers, never merged, because there are two different kinds of color on
/// screen and merging them would destroy a spelling — the same doctrine that keeps
/// `ProjectLibrary`'s three `savePalette` overloads apart. One takes a derived
/// ``ColorValue`` with no authored text of its own (a harmony member, a CVD simulation,
/// a mix, a solver result) and adopts it through ``ColorStore/adopt(_:preferring:)``,
/// the same seam the eyedropper and the transform panel use. The other takes a color
/// **and the text that produced it** (a recent, a saved color) and writes that text back
/// unchanged, through ``ColorStore/use(_:)``, so a stored `rebeccapurple` returns as
/// `rebeccapurple` rather than a re-derived `#663399`.
///
/// **The accessibility label is always the color's CSS, never a caller-supplied
/// override.** That is what makes a row of these testable at all — a harmony or a
/// palette that silently produced the same color twice would fail a distinctness check
/// on the label, and a label that instead read a caller-chosen name could not catch
/// that. A caller that also wants to show a name (a palette entry's key, a saved color's
/// title) draws it as a separate caption underneath, the way `ExportPanel.swatches` and
/// `ProjectsPanel.savedColorTile` already do — see the identifier the caller supplies
/// for how a test tells two same-colored swatches apart instead.
///
/// `onAdopt` runs after the built-in adopt-and-remember, only from the primary action —
/// never from "Use as background" or "Copy", which touch a color that need not be this
/// panel's own. It exists for the two spots where accepting a *pending, relative*
/// result also has to clear whatever produced it: `TransformPanel`'s Adjusted and Mixed
/// swatches. Clicking either without it would leave the sliders dialed in, and the next
/// click through "Apply" would compound the same nudge a second time — the exact bug
/// `TransformPanel.apply(_:)`'s own reset exists to prevent. Every other call site
/// leaves it `nil`.
///
/// `menuExtras` appends more items after the built-in three, for the one call site that
/// already had its own menu before M21: `ProjectsPanel.savedColorTile`'s Select/Deselect,
/// Move Left/Right, Notes… and Delete. **This is not optional API surface added on
/// spec.** The first cut of that conversion left the tile's existing `.contextMenu` on
/// its outer `ZStack`, one level above the button `SwatchButton` now owns — and measured
/// against the running app, that menu never appeared at all: right-clicking
/// `savedColor-N` showed only this component's own three items, and
/// `testMoveCommandsReorderTheGrid` failed with "No item Move Left on savedColor-2". A
/// `Button`'s own `.contextMenu` shadows an ancestor's rather than merging with it, so
/// the tile's items have to become part of *this* menu or they are unreachable.
///
/// `MenuExtras` is a generic parameter, not an `AnyView`-erased closure, and that is a
/// second thing measured rather than assumed: an erased version built with `AnyView`
/// compiled cleanly and *still* dropped every extra item — `.contextMenu` walks the
/// literal `@ViewBuilder` result to build native `NSMenuItem`s, and type-erasing it
/// defeats that walk. `SwatchButton<EmptyView>` (via the constrained extension below) is
/// the concrete type every call site without extras gets, so nothing changes for them.
struct SwatchButton<MenuExtras: View>: View {
  // MARK: Lifecycle

  /// A derived color with no spelling of its own.
  ///
  /// `format` is what the color is honestly spelled in once adopted — `.oklch` for a
  /// transform result, which can leave sRGB and would otherwise be quantized or mapped
  /// by hex; `.hex` (the default) everywhere else.
  init(
    color: ColorValue,
    preferring format: CSSOutputFormat = .hex,
    cornerRadius: CGFloat = 8,
    checkerSize: CGFloat = 5,
    accessibilityIdentifier: String,
    onAdopt: (() -> Void)? = nil,
    @ViewBuilder menuExtras: () -> MenuExtras,
  ) {
    self.color = color
    text = nil
    self.format = format
    self.cornerRadius = cornerRadius
    self.checkerSize = checkerSize
    identifier = accessibilityIdentifier
    self.onAdopt = onAdopt
    self.menuExtras = menuExtras()
  }

  /// A color with the authored text that produced it.
  init(
    color: ColorValue,
    text: String,
    cornerRadius: CGFloat = 8,
    checkerSize: CGFloat = 5,
    accessibilityIdentifier: String,
    onAdopt: (() -> Void)? = nil,
    @ViewBuilder menuExtras: () -> MenuExtras,
  ) {
    self.color = color
    self.text = text
    format = .hex
    self.cornerRadius = cornerRadius
    self.checkerSize = checkerSize
    identifier = accessibilityIdentifier
    self.onAdopt = onAdopt
    self.menuExtras = menuExtras()
  }

  // MARK: Internal

  var body: some View {
    Button(action: adopt) {
      ColorSwatch(color: color, cornerRadius: cornerRadius, checkerSize: checkerSize)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(cssLabel)
    .accessibilityIdentifier(identifier)
    .contextMenu {
      Button("Use as color", action: adopt)
      Button("Use as background", action: useAsBackground)
      Button("Copy") { Clipboard.copy(cssLabel) }
      menuExtras
    }
  }

  // MARK: Private

  @Environment(ColorStore.self) private var store

  private let color: ColorValue
  /// `nil` for a derived color; set for one with authored text of its own. The presence
  /// of this, not a separate flag, is what the two actions below branch on — one value
  /// can't disagree with itself about which initializer built this instance.
  private let text: String?
  private let format: CSSOutputFormat
  private let cornerRadius: CGFloat
  private let checkerSize: CGFloat
  private let identifier: String
  private let onAdopt: (() -> Void)?
  private let menuExtras: MenuExtras

  /// Always spelled in hex, independent of `format` — the same split every panel's own
  /// `css(_:)` caption helper already makes: `format` decides what lands in the field on
  /// adoption, this decides what a caption, a tooltip, or a screen reader says about the
  /// swatch. Storage precision throughout (``CSSFormatOptions/lossless`` never enters
  /// here), because this is display, and display precision is `store.formatOptions`.
  private var cssLabel: String {
    text ?? color.cssStringOrHex(
      as: color.spelling(preferring: .hex),
      options: store.formatOptions,
    )
  }

  private func adopt() {
    if let text {
      store.use(RecentColor(color: color, text: text))
    } else {
      store.adopt(color, preferring: format)
    }
    store.remember()
    onAdopt?()
  }

  private func useAsBackground() {
    if let text {
      store.backgroundText = text
    } else {
      store.adoptBackground(color, preferring: format)
    }
  }
}

/// The plain-menu convenience — every call site but one.
///
/// A generic parameter can't carry its own default the way a plain parameter can, so
/// this constrained extension is what lets `SwatchButton(color:…)` keep compiling with
/// no `menuExtras` trailing closure at all: Swift infers `MenuExtras == EmptyView` from
/// the return type of the closure these two forward, and every existing call site
/// resolves to that concrete, non-erased specialization.
extension SwatchButton where MenuExtras == EmptyView {
  init(
    color: ColorValue,
    preferring format: CSSOutputFormat = .hex,
    cornerRadius: CGFloat = 8,
    checkerSize: CGFloat = 5,
    accessibilityIdentifier: String,
    onAdopt: (() -> Void)? = nil,
  ) {
    self.init(
      color: color,
      preferring: format,
      cornerRadius: cornerRadius,
      checkerSize: checkerSize,
      accessibilityIdentifier: accessibilityIdentifier,
      onAdopt: onAdopt,
    ) { EmptyView() }
  }

  init(
    color: ColorValue,
    text: String,
    cornerRadius: CGFloat = 8,
    checkerSize: CGFloat = 5,
    accessibilityIdentifier: String,
    onAdopt: (() -> Void)? = nil,
  ) {
    self.init(
      color: color,
      text: text,
      cornerRadius: cornerRadius,
      checkerSize: checkerSize,
      accessibilityIdentifier: accessibilityIdentifier,
      onAdopt: onAdopt,
    ) { EmptyView() }
  }
}

/// The conventional transparency backdrop.
///
/// Fixed light gray in both appearances on purpose: every design tool draws it this
/// way, so an adaptive version would read as part of the color rather than as the
/// absence of one.
struct Checkerboard: View {
  // MARK: Internal

  var squareSize: CGFloat = 5

  var body: some View {
    Canvas { context, size in
      context.fill(
        Path(CGRect(origin: .zero, size: size)),
        with: .color(Self.light),
      )

      let columns = Int((size.width / squareSize).rounded(.up))
      let rows = Int((size.height / squareSize).rounded(.up))

      // One accumulated path rather than a fill per square: a recents grid can
      // hold a dozen of these and each is redrawn on every window resize.
      var squares = Path()
      for row in 0 ..< max(rows, 0) {
        for column in 0 ..< max(columns, 0) where (row + column).isMultiple(of: 2) {
          squares.addRect(
            CGRect(
              x: CGFloat(column) * squareSize,
              y: CGFloat(row) * squareSize,
              width: squareSize,
              height: squareSize,
            ),
          )
        }
      }
      context.fill(squares, with: .color(Self.dark))
    }
  }

  // MARK: Private

  private static let light = Color(white: 1.0)
  private static let dark = Color(white: 0.82)
}

#Preview {
  HStack(spacing: 12) {
    ColorSwatch(color: .srgb8(59, 130, 246))
    ColorSwatch(color: .srgb8(255, 255, 255))
    ColorSwatch(color: .srgb8(220, 38, 38, alpha: 0.35))
    ColorSwatch(color: ColorValue(space: .oklch, 0.9, 0.3, 140))
  }
  .frame(height: 64)
  .padding()
}
