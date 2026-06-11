import SwiftUI

/// Shows the live grayscale camera frame with detected tags outlined and their
/// IDs drawn on top.
struct CameraScreen: View {
    @ObservedObject var camera: CameraManager
    var showFPS: Bool

    var body: some View {
        ZStack(alignment: .top) {
            // The camera frame bleeds full-screen, behind the status bar.
            cameraLayer
                .ignoresSafeArea()

            // The header stays within the top safe area.
            header
        }
    }

    private var cameraLayer: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                if let frame = camera.frame {
                    let rect = fittedRect(content: camera.imageSize, in: geo.size)

                    Image(decorative: frame, scale: 1, orientation: .up)
                        .resizable()
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)

                    DetectionOverlay(detections: camera.detections, imageSize: camera.imageSize)
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

    /// Aspect-fits `content` inside `container`, centered.
    private func fittedRect(content: CGSize, in container: CGSize) -> CGRect {
        guard content.width > 0, content.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let scale = min(container.width / content.width, container.height / content.height)
        let size = CGSize(width: content.width * scale, height: content.height * scale)
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}

/// Draws tag outlines and IDs. Its own bounds match the displayed image, so it
/// only needs to scale image-pixel coordinates to its local space.
private struct DetectionOverlay: View {
    let detections: [TagDetection]
    let imageSize: CGSize

    var body: some View {
        Canvas { context, size in
            guard imageSize.width > 0, imageSize.height > 0 else { return }
            let sx = size.width / imageSize.width
            let sy = size.height / imageSize.height
            let map = { (p: CGPoint) in CGPoint(x: p.x * sx, y: p.y * sy) }

            for detection in detections {
                let points = detection.corners.map(map)
                guard points.count == 4 else { continue }

                var path = Path()
                path.move(to: points[0])
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
                path.closeSubpath()
                context.stroke(path, with: .color(.green), lineWidth: 3)

                let center = map(detection.center)
                let label = Text("\(detection.tagID)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                let resolved = context.resolve(label)
                let textSize = resolved.measure(in: size)
                let padding = CGSize(width: 12, height: 6)
                let bgRect = CGRect(
                    x: center.x - textSize.width / 2 - padding.width / 2,
                    y: center.y - textSize.height / 2 - padding.height / 2,
                    width: textSize.width + padding.width,
                    height: textSize.height + padding.height
                )
                context.fill(
                    Path(roundedRect: bgRect, cornerRadius: 6),
                    with: .color(.green.opacity(0.85))
                )
                context.draw(resolved, at: center)
            }
        }
        .allowsHitTesting(false)
    }
}
