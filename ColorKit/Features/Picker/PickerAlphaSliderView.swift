//
//  PickerAlphaSliderView.swift
//  ColorKit
//

import SwiftUI

/// The alpha strip beneath the plane and hue strip.
///
/// See ``PickerPlaneView`` for why this is its own file, shared between `PickerPanel`
/// and the popover `CompactPicker` (M24) rather than cloned between them.
struct PickerAlphaSliderView: View {
  // MARK: Internal

  @Binding var state: PickerState

  /// See ``PickerPlaneView/identifier`` for why this has to vary per host.
  var identifier = "pickerAlpha"

  var body: some View {
    let opaque = ColorValue(
      space: state.color.space,
      components: state.color.components,
      alpha: 1,
    )

    return GeometryReader { proxy in
      let size = proxy.size

      ZStack {
        Checkerboard(squareSize: 6)
        LinearGradient(
          colors: [opaque.displayColor.opacity(0), opaque.displayColor],
          startPoint: .leading,
          endPoint: .trailing,
        )

        Canvas { context, canvasSize in
          let x = CGFloat(state.alpha) * canvasSize.width
          let marker = Path(
            roundedRect: CGRect(x: x - 3, y: -1, width: 6, height: canvasSize.height + 2),
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
            let fraction = PickerState.clampedFraction(value.location.x, over: size.width)
            store.inputText = state.committing({ $0.alpha = fraction }, in: store)
          }
          .onEnded { _ in store.remember() },
      )
    }
    .frame(height: 24)
    .clipShape(Capsule())
    .overlay { Capsule().strokeBorder(.separator, lineWidth: 1) }
    .accessibilityElement()
    .accessibilityIdentifier(identifier)
    .accessibilityLabel("Alpha")
  }

  // MARK: Private

  @Environment(ColorStore.self) private var store
}
