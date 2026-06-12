import SwiftUI

/// Aspect-fits `content` inside `container`, centered. Shared by the live and
/// captured-result views so detections line up with the displayed image.
func aspectFittedRect(content: CGSize, in container: CGSize) -> CGRect {
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

/// Draws tag outlines and their IDs. Outlines are stroked in a `Canvas`; each ID
/// is a `Text` projected onto the tag's quad so it sits on the surface in
/// perspective and scales with the tag. Its bounds match the displayed image, so
/// it maps image-pixel coordinates to its local space with a single scale.
struct DetectionView: View {
    let detections: [TagDetection]
    let imageSize: CGSize

    var body: some View {
        GeometryReader { geo in
            let scale = imageSize.width > 0 ? geo.size.width / imageSize.width : 1

            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    for detection in detections {
                        let pts = detection.corners.map { CGPoint(x: $0.x * scale, y: $0.y * scale) }
                        guard pts.count == 4 else { continue }
                        var path = Path()
                        path.move(to: pts[0])
                        for p in pts.dropFirst() { path.addLine(to: p) }
                        path.closeSubpath()
                        context.stroke(path, with: .color(.green), lineWidth: 3)
                    }
                }

                ForEach(detections) { detection in
                    let pts = detection.corners.map { CGPoint(x: $0.x * scale, y: $0.y * scale) }
                    // Base the font size on the tag's on-screen size so the
                    // projection maps it roughly 1:1 (keeps it crisp).
                    let side = hypot(pts[3].x - pts[0].x, pts[3].y - pts[0].y)
                    let base = max(min(side * 0.7, 500), 12)
                    Text("\(detection.tagID)")
                        .font(.system(size: base, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, base * 0.3)
                        .padding(.vertical, base * 0.12)
                        .background(.green, in: RoundedRectangle(cornerRadius: base * 0.25))
                        .fixedSize()
                        .modifier(QuadProjection(corners: pts, fill: 0.88))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Maps a view's rectangle onto an arbitrary quad (the tag corners) as a true
/// projective transform, so text appears painted on the tag in perspective.
private struct QuadProjection: GeometryEffect {
    /// Tag corners in container coordinates, in AprilTag order:
    /// p0 bottom-left, p1 bottom-right, p2 top-right, p3 top-left (tag frame).
    var corners: [CGPoint]
    /// Fraction of the tag the label fills (aspect-preserving, centered).
    var fill: CGFloat = 0.72

    func effectValue(size: CGSize) -> ProjectionTransform {
        guard corners.count == 4, size.width > 0, size.height > 0 else {
            return ProjectionTransform()
        }
        let p0 = corners[0], p1 = corners[1], p2 = corners[2], p3 = corners[3]

        // Unit square -> tag quad, oriented so the text reads upright on the tag:
        // (0,0)->top-left=p3, (1,0)->top-right=p2, (1,1)->bottom-right=p1, (0,1)->bottom-left=p0.
        let toQuad = unitSquareToQuad(tl: p3, tr: p2, br: p1, bl: p0)

        // Centered, aspect-preserving sub-rectangle of the tag for the text.
        let ar = size.width / size.height
        let uw = ar >= 1 ? fill : fill * ar
        let uh = ar >= 1 ? fill / ar : fill
        let unitCorners = [
            CGPoint(x: 0.5 - uw / 2, y: 0.5 - uh / 2),
            CGPoint(x: 0.5 + uw / 2, y: 0.5 - uh / 2),
            CGPoint(x: 0.5 + uw / 2, y: 0.5 + uh / 2),
            CGPoint(x: 0.5 - uw / 2, y: 0.5 + uh / 2),
        ]
        let dest = unitCorners.map { project(toQuad, $0) }

        // text-local rect -> unit square -> destination quad.
        let normalize = ProjectionTransform(CGAffineTransform(scaleX: 1 / size.width, y: 1 / size.height))
        let unitToDest = unitSquareToQuad(tl: dest[0], tr: dest[1], br: dest[2], bl: dest[3])
        return normalize.concatenating(unitToDest)
    }
}

/// Homography mapping the unit square (0,0),(1,0),(1,1),(0,1) to the given quad
/// corners (Heckbert's projective mapping).
private func unitSquareToQuad(tl: CGPoint, tr: CGPoint, br: CGPoint, bl: CGPoint) -> ProjectionTransform {
    let x0 = tl.x, y0 = tl.y
    let x1 = tr.x, y1 = tr.y
    let x2 = br.x, y2 = br.y
    let x3 = bl.x, y3 = bl.y

    let dx1 = x1 - x2, dx2 = x3 - x2, dx3 = x0 - x1 + x2 - x3
    let dy1 = y1 - y2, dy2 = y3 - y2, dy3 = y0 - y1 + y2 - y3

    let a, b, c, d, e, f, g, h: CGFloat
    c = x0
    f = y0
    if abs(dx3) < 1e-9 && abs(dy3) < 1e-9 {
        a = x1 - x0; b = x2 - x1; d = y1 - y0; e = y2 - y1; g = 0; h = 0
    } else {
        let denom = dx1 * dy2 - dx2 * dy1
        g = (dx3 * dy2 - dx2 * dy3) / denom
        h = (dx1 * dy3 - dx3 * dy1) / denom
        a = x1 - x0 + g * x1
        b = x3 - x0 + h * x3
        d = y1 - y0 + g * y1
        e = y3 - y0 + h * y3
    }

    var t = ProjectionTransform()
    t.m11 = a; t.m12 = d; t.m13 = g
    t.m21 = b; t.m22 = e; t.m23 = h
    t.m31 = c; t.m32 = f; t.m33 = 1
    return t
}

/// Applies a projective transform to a point (row-vector convention).
private func project(_ t: ProjectionTransform, _ p: CGPoint) -> CGPoint {
    let X = p.x * t.m11 + p.y * t.m21 + t.m31
    let Y = p.x * t.m12 + p.y * t.m22 + t.m32
    let W = p.x * t.m13 + p.y * t.m23 + t.m33
    guard W != 0 else { return CGPoint(x: X, y: Y) }
    return CGPoint(x: X / W, y: Y / W)
}
