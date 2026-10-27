import AVFoundation
import SwiftUI

private let buttonSize: CGFloat = 72
private let buttonFill = Color(white: 0.22)
private let accent = Color(red: 0.96, green: 0.76, blue: 0.16)

struct ControlPanel: View {
    let model: AppModel
    let camera: CameraService
    let openSettings: () -> Void

    /// Gap between the panel and the screen edges, the same on the sides and the bottom.
    private let edgeGap: CGFloat = 8
    /// Width of the button rows: four columns and three gaps.
    private let contentWidth = buttonSize * 4 + 15 * 3
    /// Panel width, measured, so the inside bottom padding can match the inside side padding.
    @State private var panelWidth: CGFloat = 0
    private var insidePadding: CGFloat { max((panelWidth - contentWidth) / 2, 18) }

    private enum DrawerEdge { case expanded, collapsed }

    /// Natural height of the bottom row, including the spacing above it.
    @State private var rowHeight: CGFloat = 0
    @State private var isExpanded = true
    /// Live drag distance; positive is downward.
    @State private var dragOffset: CGFloat = 0
    /// The extent the drawer last touched, so the haptic fires once per arrival.
    @State private var lastEdge: DrawerEdge? = .expanded
    @State private var edgeHits = 0

    var body: some View {
        VStack(spacing: 0) {
            handle
            HStack(spacing: 15) {
                zoomCapsule
                torchButton
            }
            .padding(.top, 14)
            bottomRow
        }
        .padding(.top, 12)
        .padding(.bottom, insidePadding)
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { panelWidth = $0 }
        .background(Color(white: 0.09), in: .rect(cornerRadii: .init(topLeading: 44, bottomLeading: 50, bottomTrailing: 50, topTrailing: 44)))
        .contentShape(.rect)
        .gesture(drawerDrag)
        .sensoryFeedback(.impact(weight: .medium), trigger: edgeHits)
        .padding(.horizontal, edgeGap)
        .padding(.bottom, edgeGap)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Drawer

    private var handle: some View {
        Button {
            setExpanded(!isExpanded)
        } label: {
            Capsule()
                .fill(Color(white: 0.45))
                .frame(width: 44, height: 5)
                .frame(width: 120, height: 20)
                .contentShape(.rect)
        }
        .padding(.vertical, -8)
        .accessibilityLabel(isExpanded ? "Hide buttons" : "Show buttons")
    }

    /// Flip, Ask, Capture and Settings; dragging the drawer down tucks this row away.
    private var bottomRow: some View {
        let reveal = self.reveal
        return HStack(alignment: .top, spacing: 15) {
            labeled("Flip") { flipButton }
            labeled("Ask") { askButton }
            labeled("Capture") { captureButton }
            labeled("Settings") {
                circleButton("gear", label: "Settings", action: openSettings)
            }
        }
        .padding(.top, 14)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowHeight = $0 }
        .frame(height: rowHeight > 0 ? reveal : nil, alignment: .top)
        .clipped()
        .opacity(rowHeight > 0 ? reveal / rowHeight : 1)
        .allowsHitTesting(rowHeight == 0 || reveal >= rowHeight)
        .accessibilityHidden(rowHeight > 0 && reveal <= 0)
    }

    /// How much of the bottom row shows, 0...rowHeight, following the finger while dragging.
    private var reveal: CGFloat {
        min(max(unclampedReveal, 0), rowHeight)
    }

    private var unclampedReveal: CGFloat {
        (isExpanded ? rowHeight : 0) - dragOffset
    }

    private var drawerDrag: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                dragOffset = value.translation.height
                let edge: DrawerEdge? = unclampedReveal >= rowHeight ? .expanded : unclampedReveal <= 0 ? .collapsed : nil
                if let edge, edge != lastEdge { edgeHits += 1 }
                lastEdge = edge
            }
            .onEnded { value in
                let predicted = (isExpanded ? rowHeight : 0) - value.predictedEndTranslation.height
                setExpanded(predicted > rowHeight / 2)
            }
    }

    private func setExpanded(_ expanded: Bool) {
        let edge: DrawerEdge = expanded ? .expanded : .collapsed
        if edge != lastEdge { edgeHits += 1 }
        lastEdge = edge
        withAnimation(.snappy) {
            isExpanded = expanded
            dragOffset = 0
        }
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

    /// In Ask each time mode, Ask opens a Voice/Text menu; otherwise it asks straight away.
    @ViewBuilder private var askButton: some View {
        if model.choosesInputEachTime {
            Menu {
                Button("Voice", systemImage: "mic.fill") { model.ask(using: .voice) }
                Button("Text", systemImage: "keyboard") { model.ask(using: .text) }
            } label: {
                circleLabel("text.bubble")
            }
            .menuOrder(.fixed)
            .accessibilityLabel("Ask")
        } else {
            circleButton("text.bubble", label: "Ask") { model.askTapped() }
        }
    }

    private var torchButton: some View {
        circleButton(
            camera.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill",
            label: "Flashlight",
            tint: camera.isTorchOn ? accent : .white
        ) {
            camera.setTorch(!camera.isTorchOn)
        }
        .accessibilityValue(camera.isTorchOn ? "On" : "Off")
        .disabled(!camera.hasTorch)
        .opacity(camera.hasTorch ? 1 : 0.4)
    }

    private var flipButton: some View {
        circleButton("arrow.triangle.2.circlepath.camera", label: "Flip camera") {
            Task { await camera.flip() }
        }
        .accessibilityValue(camera.position == .front ? "Front camera" : "Back camera")
        // A frozen frame belongs to the camera that took it.
        .disabled(model.isFrozen || camera.isSwitching)
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
        Button(action: action) { circleLabel(symbol, tint: tint) }
            .accessibilityLabel(label)
    }

    private func circleLabel(_ symbol: String, tint: Color = .white) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 28))
            .foregroundStyle(tint)
            .frame(width: buttonSize, height: buttonSize)
            .background(buttonFill, in: .circle)
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
