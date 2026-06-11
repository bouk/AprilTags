import CoreMedia

/// A selectable camera resolution / max-frame-rate combination, derived from an
/// `AVCaptureDevice.Format`. The `id` is stable across launches so the choice
/// can be persisted and matched against the device's formats on the next run.
struct CaptureFormat: Identifiable, Hashable {
    let id: String
    let width: Int
    let height: Int
    let frameRate: Double

    init(width: Int, height: Int, frameRate: Double) {
        self.id = "\(width)x\(height)@\(Int(frameRate.rounded()))"
        self.width = width
        self.height = height
        self.frameRate = frameRate
    }

    var resolutionLabel: String { "\(width)×\(height)" }
    var label: String { "\(resolutionLabel) · \(Int(frameRate.rounded())) FPS" }
}
