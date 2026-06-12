import SwiftUI

/// Shows the live grayscale camera frame with detected tags outlined and their
/// IDs drawn on top. Tapping anywhere captures a full-resolution still.
struct CameraScreen: View {
    @ObservedObject var camera: CameraManager
    var showFPS: Bool
    var onCapture: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            // The camera frame bleeds full-screen, behind the status bar.
            cameraLayer
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onCapture() }

            // The header stays within the top safe area.
            header

            if camera.isCapturing {
                capturingOverlay
            }
        }
    }

    private var cameraLayer: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                if let frame = camera.frame {
                    let rect = aspectFittedRect(content: camera.imageSize, in: geo.size)

                    Image(decorative: frame, scale: 1, orientation: .up)
                        .resizable()
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)

                    DetectionView(detections: camera.detections, imageSize: camera.imageSize)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }

                if camera.permissionDenied {
                    permissionMessage
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Label("\(camera.detections.count)", systemImage: "viewfinder")
                .font(.headline.monospacedDigit())
            if showFPS {
                Label(String(format: "%.0f FPS", camera.fps), systemImage: "speedometer")
                    .font(.headline.monospacedDigit())
            }
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

    private var capturingOverlay: some View {
        ProgressView("Capturing…")
            .progressViewStyle(.circular)
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black.opacity(0.25))
            .ignoresSafeArea()
    }

    private var permissionMessage: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.largeTitle)
            Text("Camera access is required")
                .font(.headline)
            Text("Enable camera access for this app in Settings.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(32)
    }
}
