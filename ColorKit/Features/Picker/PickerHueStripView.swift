//
//  PickerHueStripView.swift
//  ColorKit
//

import SwiftUI

/// The one-dimensional hue strip beside the plane. Follows the cursor rather than
/// the plane's own hue axis, which is why it renders far more cheaply.
///
/// See ``PickerPlaneView`` for why this is its own file and why rendering lives
/// inside it rather than in whichever host embeds it.
struct PickerHueStripView: View {
  // MARK: Internal

  @Binding var state: PickerState

  /// Matches the plane's own side, so the two read as one control rather than two
  /// unrelated strips of different heights.
  var height: CGFloat
  /// See ``PickerPlaneView/identifier`` for why this has to vary per host.
  var identifier = "pickerHue"

  var body: some View {
    GeometryReader { proxy in
      let size = proxy.size

      ZStack {
        if let strip {
          Image(decorative: strip, scale: 1)
            .resizable()
            .interpolation(.high)
        } else {
          Rectangle().fill(.quaternary)
        }

        Canvas { context, canvasSize in
          let y = CGFloat(currentHue / 360) * canvasSize.height
          let marker = Path(
            roundedRect: CGRect(x: -1, y: y - 3, width: canvasSize.width + 2, height: 6),
            cornerRadius: 3,
          )
          context.stroke(marker, with: .color(.black.opacity(0.55)), lineWidth: 3)
          context.stroke(marker, with: .color(.white), lineWidth: 1.5)
        }
      }
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            let fraction = PickerState.clampedFraction(value.location.y, over: size.height)
            store.inputText = state.committing({ state in
              switch state.mode {
              case .hsv: state.hsvHue = fraction * 360
              case .oklch: state.oklchHue = fraction * 360
              }
            }, in: store)
          }
          .onEnded { _ in store.remember() },
      )
    }
    .frame(width: 28, height: height)
    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .strokeBorder(.separator, lineWidth: 1)
    }
    .accessibilityElement()
    .accessibilityIdentifier(identifier)
    .accessibilityLabel("Hue")
    .task(id: stripKey) { await renderStrip() }
  }

  // MARK: Private

  /// The strip shows hues *at the current position*, so it follows the cursor. It is
  /// one-dimensional and correspondingly cheap.
  private struct StripKey: Equatable {
    let mode: PickerMode
    let first: Double
    let second: Double
    let webFriendly: Bool
  }

  @Environment(ColorStore.self) private var store

  @State private var strip: CGImage?
  @State private var stripRender: Task<CGImage?, Never>?

  private var currentHue: Double {
    state.mode == .hsv ? state.hsvHue : state.oklchHue
  }

  private var stripKey: StripKey {
    switch state.mode {
    case .hsv:
      StripKey(mode: .hsv, first: state.saturation, second: state.value, webFriendly: store.webFriendly)
    case .oklch:
      StripKey(mode: .oklch, first: state.lightness, second: state.chroma, webFriendly: store.webFriendly)
    }
  }

  private func renderStrip() async {
    let snapshot = state
    let webFriendly = store.webFriendly
    stripRender?.cancel()
    let task = Task.detached(priority: .userInitiated) {
      PickerPlaneRenderer.hueStrip(mode: snapshot.mode, state: snapshot, webFriendly: webFriendly)
    }
    stripRender = task

    let rendered = await task.value
    guard !Task.isCancelled, let rendered else { return }
    strip = rendered
  }
}
