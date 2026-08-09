//
//  PickerPlaneView.swift
//  ColorKit
//

import SwiftUI

/// The two-axis plane — saturation/value or chroma/lightness — with the sRGB (and,
/// off web-friendly mode, the display) gamut edge drawn over it.
///
/// Extracted out of `PickerPanel` for M24: the popover picker (`CompactPicker`) needs
/// the identical control at a different size, and two implementations of a
/// gamut-clamped chroma axis would drift — the same reasoning PLAN.md gives for why
/// this file exists. Rendering lives *inside* this view rather than in whichever host
/// embeds it: `PickerPanel` and `CompactPicker` each hold their own `PickerState`, so
/// each needs its own rendered bitmap, and hoisting the render loop to the hosts
/// would only move the duplication rather than remove it.
struct PickerPlaneView: View {
  // MARK: Internal

  @Binding var state: PickerState

  /// The plane's height always, and its width too unless ``fillsAvailableWidth`` is
  /// set. The host measures its own available width and passes the result down — see
  /// `PickerPanel.squareSide(forPanelWidth:)` — rather than this view re-deriving it,
  /// since a popover and a resizable panel size this two completely different ways.
  var side: CGFloat
  /// `true` for `PickerPanel`, `false` (the default) for `CompactPicker`.
  ///
  /// The plane used to fill whatever width the row had left over — no
  /// `.frame(width:)` of its own — and only its *height* came from `side`. M24's
  /// extraction gave it an explicit `.frame(width: side, height: side)` instead,
  /// reasoning that a true square was a correctness fix (see PLAN.md's M24
  /// retrospective on `squareSide(forPanelWidth:)`'s pre-M24 non-square edge case
  /// above 532pt of panel width). It reads correctly at that one width, and reads
  /// worse everywhere else: a `PickerPanel` wider than 460 + 72pt now shows a
  /// fixed square with empty space beside it, where it used to stretch to fill the
  /// panel — the shape actually wanted there, confirmed after the fact by the person
  /// who asked for it. `CompactPicker`'s popover has no such container to fill and
  /// is sized once, so it keeps the explicit square this parameter defaults to.
  var fillsAvailableWidth = false
  /// Distinct per host so `PickerPanel`'s Pick tab and `CompactPicker`'s popover can
  /// be on screen at once — the header swatch that opens the popover sits above the
  /// tool switcher, so nothing stops a person from opening it while already on the
  /// Pick tab. Two elements sharing one identifier there would be an ambiguous
  /// XCUITest query with no tree to read, so the default is `PickerPanel`'s own and
  /// every other host overrides it.
  var identifier = "pickerPlane"

  var body: some View {
    GeometryReader { proxy in
      let size = proxy.size

      ZStack {
        if let plane {
          Image(decorative: plane.image, scale: 1)
            .resizable()
            .interpolation(.high)
        } else {
          Rectangle().fill(.quaternary)
        }

        Canvas { context, canvasSize in
          if state.mode == .oklch, let plane, plane.rows > 1 {
            // The display edge is not drawn under web-friendly mode (M22): the
            // plane's pixels already stop at the sRGB line, so a dashed curve past
            // it would be a boundary this square cannot actually reach.
            if !store.webFriendly {
              // Dashed first so the solid sRGB line wins where they overlap
              // at the pinched ends.
              strokeEdge(
                plane.displayEdge, in: canvasSize, context: &context,
                dash: [4, 3], width: 1,
              )
            }
            strokeEdge(plane.srgbEdge, in: canvasSize, context: &context, width: 1.5)
          }
          drawCursor(in: canvasSize, context: &context)
        }
      }
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { moveCursor(to: $0.location, in: size) }
          // Never mid-drag — a drag crosses hundreds of colors on the way to
          // the one that was wanted — but directly on release (M23), which the
          // hue strip and alpha slider below share too via
          // ``PickerState/committing(_:in:)``.
          .onEnded { _ in store.remember() },
      )
    }
    .frame(width: fillsAvailableWidth ? nil : side, height: side)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .strokeBorder(.separator, lineWidth: 1)
    }
    // One element rather than a container: a plane has no children worth landing
    // on, and XCUITest cannot drag something that is not an element.
    .accessibilityElement()
    .accessibilityIdentifier(identifier)
    .accessibilityLabel(state.mode == .hsv ? "Saturation and value" : "Chroma and lightness")
    // `.task(id:)` restarts when the id moves, which discards the stale result.
    // Stopping the *work* takes an explicit cancel — see `renderPlane()`.
    .task(id: planeKey) { await renderPlane() }
  }

  // MARK: Private

  /// What the plane's pixels depend on. Only a change here is worth re-rendering
  /// sixty thousand conversions for — moving the cursor around a plane does not
  /// change the plane.
  private struct PlaneKey: Equatable {
    let mode: PickerMode
    let hue: Double
    /// Included so toggling ``ColorStore/webFriendly`` (M22) mid-session re-renders
    /// the plane against the new edge rather than leaving the old one on screen —
    /// `.task(id:)` only restarts when the key itself changes.
    let webFriendly: Bool
  }

  @Environment(ColorStore.self) private var store

  @State private var plane: PickerPlane?
  @State private var planeRender: Task<PickerPlane?, Never>?

  private var planeKey: PlaneKey {
    PlaneKey(
      mode: state.mode,
      hue: state.mode == .hsv ? state.hsvHue : state.oklchHue,
      webFriendly: store.webFriendly,
    )
  }

  /// Where the cursor sits, as a fraction of the plane.
  ///
  /// Clamped, because a typed color can be off the plane entirely — `oklch(0.7 0.5
  /// 30)` has more chroma than the axis carries. Parking the ring on the edge is
  /// better than drawing it out of bounds, and the panel's readout states the real
  /// number either way.
  private var cursorFraction: CGPoint {
    switch state.mode {
    case .hsv:
      CGPoint(x: state.saturation / 100, y: 1 - state.value / 100)
    case .oklch:
      CGPoint(
        x: min(state.chroma / PickerState.chromaAxisMaximum, 1),
        y: 1 - min(max(state.lightness, 0), 1),
      )
    }
  }

  /// Two passes: a dark line under a light one, so the curve stays visible whether it
  /// crosses a pale yellow or a deep blue. A single stroke in either color disappears
  /// somewhere along its own length.
  private func strokeEdge(
    _ edge: [Double],
    in size: CGSize,
    context: inout GraphicsContext,
    dash: [CGFloat] = [],
    width: CGFloat,
  ) {
    guard edge.count > 1 else { return }

    var path = Path()
    for (row, chroma) in edge.enumerated() {
      let point = CGPoint(
        x: CGFloat(chroma / PickerState.chromaAxisMaximum) * size.width,
        y: CGFloat(row) / CGFloat(edge.count - 1) * size.height,
      )
      if row == 0 {
        path.move(to: point)
      } else {
        path.addLine(to: point)
      }
    }

    let style = StrokeStyle(lineWidth: width + 1.5, lineCap: .round, dash: dash)
    context.stroke(path, with: .color(.black.opacity(0.45)), style: style)
    context.stroke(
      path,
      with: .color(.white.opacity(0.95)),
      style: StrokeStyle(lineWidth: width, lineCap: .round, dash: dash),
    )
  }

  private func drawCursor(in size: CGSize, context: inout GraphicsContext) {
    let position = CGPoint(
      x: cursorFraction.x * size.width,
      y: cursorFraction.y * size.height,
    )
    let ring = Path(ellipseIn: CGRect(x: position.x - 7, y: position.y - 7, width: 14, height: 14))
    context.stroke(ring, with: .color(.black.opacity(0.55)), lineWidth: 3)
    context.stroke(ring, with: .color(.white), lineWidth: 1.5)
  }

  private func moveCursor(to point: CGPoint, in size: CGSize) {
    let x = PickerState.clampedFraction(point.x, over: size.width)
    let y = PickerState.clampedFraction(point.y, over: size.height)

    store.inputText = state.committing({ state in
      switch state.mode {
      case .hsv:
        state.saturation = x * 100
        state.value = (1 - y) * 100
      case .oklch:
        state.chroma = x * PickerState.chromaAxisMaximum
        state.lightness = 1 - y
      }
    }, in: store)
  }

  /// Renders off the main actor, and **cancels the render it replaces**.
  ///
  /// The cancellation has to be explicit. A detached task does not inherit its
  /// parent's — that is what "detached" means — so `.task(id:)` tearing down the
  /// wrapper leaves the render itself running to completion on a background thread.
  /// Dropping its stale result afterwards would still look correct and would still
  /// burn a full plane's worth of conversions per frame of a hue drag.
  private func renderPlane() async {
    let snapshot = state
    let webFriendly = store.webFriendly
    planeRender?.cancel()
    let task = Task.detached(priority: .userInitiated) {
      PickerPlaneRenderer.plane(mode: snapshot.mode, state: snapshot, webFriendly: webFriendly)
    }
    planeRender = task

    let rendered = await task.value
    guard !Task.isCancelled, let rendered else { return }
    plane = rendered
  }
}
