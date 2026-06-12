import CoreMedia

/// A selectable capture mode. Most are streaming video formats; a few are
/// full-sensor photo resolutions (e.g. 48 MP) that can only be reached through
/// `AVCapturePhotoOutput`.
struct CaptureFormat: Identifiable, Hashable {
    enum Kind: Hashable {
        /// Streamed through `AVCaptureVideoDataOutput` at `frameRate`.
        case video
        /// Captured one frame at a time through `AVCapturePhotoOutput`.
        case photo
    }

    let id: String
    let width: Int
    let height: Int
    let frameRate: Double
    let kind: Kind

    /// A streaming video resolution / max-frame-rate combination.
    init(width: Int, height: Int, frameRate: Double) {
        self.id = "\(width)x\(height)@\(Int(frameRate.rounded()))"
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.kind = .video
    }

    /// A full-resolution still-capture format, identified by its sensor
    /// dimensions. Frame rate is unknown up front (it depends on how fast the
    /// pipeline can deliver each capture), so it is reported live instead.
    init(photoWidth width: Int, height: Int) {
        self.id = "\(width)x\(height)@photo"
        self.width = width
        self.height = height
        self.frameRate = 0
        self.kind = .photo
    }

    /// Sensor megapixels, floored to a whole number to match how cameras are
    /// marketed (8064×6048 = 48.8 MP is sold as "48 MP", not 49).
    var megapixels: Int { (width * height) / 1_000_000 }

    var resolutionLabel: String { "\(width)×\(height)" }

    var label: String {
        switch kind {
        case .video:
            return "\(resolutionLabel) · \(Int(frameRate.rounded())) FPS"
        case .photo:
            return "\(megapixels) MP · Photo (\(resolutionLabel))"
        }
    }
}
