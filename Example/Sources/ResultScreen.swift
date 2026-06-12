import SwiftUI

/// Shows a frozen full-resolution still with detections drawn on top. Swiping
/// left reveals the same settings screen, so detection parameters can be tuned
/// and re-applied against this exact image. Swiping back re-runs detection.
/// The image can be pinched to zoom and panned to inspect fine detail.
struct ResultScreen: View {
    @ObservedObject var settings: DetectorSettings
    @ObservedObject var camera: CameraManager
    let captured: CapturedFrame
    var onDismiss: () -> Void

    private enum Page: Hashable { case result, settings }
    @State private var page: Page = .result

    var body: some View {
        TabView(selection: $page) {
            resultPage
                .tag(Page.result)

            SettingsScreen(settings: settings, camera: camera)
                .tag(Page.settings)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: page) { _, newPage in
            // Re-run detection on the frozen image with the edited parameters.
            if newPage == .result {
                camera.rerunDetection(config: settings.config)
                camera.selectPhotoSize(id: settings.selectedPhotoSizeID)
                settings.persist()
            }
        }
    }

    private var resultPage: some View {
        ZStack(alignment: .top) {
            ZoomableView {
                GeometryReader { geo in
                    let rect = aspectFittedRect(content: captured.size, in: geo.size)
                    ZStack {
                        Image(decorative: captured.image, scale: 1, orientation: .up)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)

                        DetectionView(detections: camera.capturedDetections, imageSize: captured.size)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }
                }
            }
            .ignoresSafeArea()
            .background(Color.black.ignoresSafeArea())

            header

            if camera.isRedetecting {
                ProgressView("Detecting…")
                    .progressViewStyle(.circular)
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.headline)
            }
            Label("\(camera.capturedDetections.count)", systemImage: "viewfinder")
                .font(.headline.monospacedDigit())
            Text("\(Int(captured.size.width))×\(Int(captured.size.height))")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            Label("Settings", systemImage: "chevron.left")
                .labelStyle(.titleAndIcon)
                .environment(\.layoutDirection, .rightToLeft)
                .font(.subheadline)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

/// Pinch-to-zoom and pan container. Panning only engages past 1× so the parent
/// page swipe keeps working when the image is not zoomed. Double-tap toggles a
/// 1×/3× zoom.
private struct ZoomableView<Content: View>: View {
    @ViewBuilder var content: () -> Content

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag: CGSize = .zero

    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 12

    var body: some View {
        content()
            .scaleEffect(scale * pinch)
            .offset(x: offset.width + drag.width, y: offset.height + drag.height)
            .gesture(magnification)
            .highPriorityGesture(panGesture, including: scale > 1 ? .gesture : .none)
            .onTapGesture(count: 2) { toggleZoom() }
            .animation(.interactiveSpring(response: 0.3), value: scale)
            .animation(.interactiveSpring(response: 0.3), value: offset)
    }

    private var magnification: some Gesture {
        MagnificationGesture()
            .updating($pinch) { value, state, _ in state = value }
            .onEnded { value in
                scale = min(max(scale * value, minScale), maxScale)
                if scale <= minScale { offset = .zero }
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .updating($drag) { value, state, _ in state = value.translation }
            .onEnded { value in
                offset.width += value.translation.width
                offset.height += value.translation.height
            }
    }

    private func toggleZoom() {
        if scale > minScale {
            scale = minScale
            offset = .zero
        } else {
            scale = 3
        }
    }
}
