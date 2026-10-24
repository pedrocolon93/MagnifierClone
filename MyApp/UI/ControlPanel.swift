import SwiftUI

private let buttonSize: CGFloat = 72
private let buttonFill = Color(white: 0.22)
private let accent = Color(red: 0.96, green: 0.76, blue: 0.16)

struct ControlPanel: View {
    let model: AppModel
    let camera: CameraService
    let openSettings: () -> Void

    private let columns = Array(repeating: GridItem(.fixed(buttonSize), spacing: 15), count: 4)

    var body: some View {
        VStack(spacing: 14) {
            Capsule()
                .fill(Color(white: 0.45))
                .frame(width: 44, height: 5)
                .accessibilityHidden(true)
            Grid(horizontalSpacing: 15, verticalSpacing: 14) {
                GridRow {
                    zoomCapsule.gridCellColumns(3)
                    placeholder("flashlight.off.fill", label: "Torch")
                }
                GridRow {
                    placeholder("circle.grid.cross.fill", label: "Filters")
                    placeholder("arrow.triangle.2.circlepath.camera", label: "Flip camera")
                    placeholder("sun.max.fill", label: "Brightness", tint: accent)
                    placeholder("circle.circle", label: "Color and contrast", tint: Color(white: 0.55))
                }
                GridRow(alignment: .top) {
                    labeled("Detect") { placeholder("viewfinder", label: "Detect") }
                    labeled("Ask") {
                        circleButton("text.bubble", label: "Ask") { model.askTapped() }
                    }
                    labeled("Capture") { captureButton }
                    labeled("Settings") {
                        circleButton("gear", label: "Settings", action: openSettings)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .background(Color(white: 0.09), in: .rect(cornerRadii: .init(topLeading: 44, bottomLeading: 50, bottomTrailing: 50, topTrailing: 44)))
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
        .accessibilityElement(children: .contain)
    }

    private var zoomCapsule: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.magnifyingglass")
                .font(.system(size: 26))
                .foregroundStyle(.white)
                .accessibilityHidden(true)
            Button { camera.setZoom(slider: camera.zoom.stepped(from: camera.sliderValue, by: -1)) } label: {
                Image(systemName: "minus").font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 32, height: buttonSize)
            }
            .accessibilityLabel("Zoom out")
            ZoomSlider(value: camera.sliderValue) { camera.setZoom(slider: $0) }
            Button { camera.setZoom(slider: camera.zoom.stepped(from: camera.sliderValue, by: 1)) } label: {
                Image(systemName: "plus").font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 32, height: buttonSize)
            }
            .accessibilityLabel("Zoom in")
        }
        .padding(.horizontal, 16)
        .frame(width: buttonSize * 3 + 30, height: buttonSize)
        .background(buttonFill, in: .capsule)
    }

    private var captureButton: some View {
        Button {
            if model.isFrozen { model.release() } else { model.capture() }
        } label: {
            ZStack {
                Circle().stroke(.white, lineWidth: 4)
                if model.isFrozen {
                    Image(systemName: "xmark").font(.system(size: 28, weight: .semibold)).foregroundStyle(.white)
                } else {
                    Circle().stroke(.white, lineWidth: 4).frame(width: 30, height: 30)
                }
            }
            .frame(width: buttonSize, height: buttonSize)
            .contentShape(.circle)
        }
        .accessibilityLabel(model.isFrozen ? "Release" : "Capture")
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 6) {
            content()
            Text(title).font(.system(size: 17)).foregroundStyle(.white)
                .fixedSize()
                .accessibilityHidden(true)
        }
        .frame(width: buttonSize)
    }

    private func circleButton(_ symbol: String, label: String, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 28))
                .foregroundStyle(tint)
                .frame(width: buttonSize, height: buttonSize)
                .background(buttonFill, in: .circle)
        }
        .accessibilityLabel(label)
    }

    private func placeholder(_ symbol: String, label: String, tint: Color = .white) -> some View {
        circleButton(symbol, label: label, tint: tint) {}
            .accessibilityHint("Not available yet")
    }
}

/// Thin track with a yellow knob; reports 0...1.
private struct ZoomSlider: View {
    let value: Double
    let onChange: (Double) -> Void
    private let knob: CGFloat = 28

    var body: some View {
        GeometryReader { proxy in
            let travel = max(proxy.size.width - knob, 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color(white: 0.5)).frame(height: 3)
                Circle().fill(accent).frame(width: knob, height: knob)
                    .offset(x: travel * value)
            }
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                onChange(min(max((g.location.x - knob / 2) / travel, 0), 1))
            })
        }
        .frame(height: buttonSize)
        .accessibilityElement()
        .accessibilityLabel("Zoom")
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(min(value + 0.1, 1))
            case .decrement: onChange(max(value - 0.1, 0))
            @unknown default: break
            }
        }
    }
}
