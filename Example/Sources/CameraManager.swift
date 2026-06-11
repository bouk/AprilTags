import AVFoundation
import Combine
import CoreGraphics
import AprilTags

/// A single decoded tag, in image-pixel coordinates.
struct TagDetection: Identifiable {
    let id = UUID()
    let tagID: Int32
    let familyName: String
    let corners: [CGPoint]
    let center: CGPoint
    let hamming: Int32
    let decisionMargin: Float
}

/// Drives the camera, feeds each grayscale frame into the AprilTag detector and
/// publishes both the preview image and the detections for SwiftUI to render.
final class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var frame: CGImage?
    @Published var detections: [TagDetection] = []
    @Published var imageSize: CGSize = .zero
    @Published var permissionDenied = false
    @Published var fps: Double = 0

    /// All resolution / frame-rate combos the active camera supports.
    @Published var availableFormats: [CaptureFormat] = []
    /// The format currently in use.
    @Published var activeFormatID: String?

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "ke.bou.AprilTagsExample.camera")

    // Config is written from the main thread and read on `queue`.
    private let lock = NSLock()
    private var pendingConfig = DetectorConfig.default
    private var pendingFormatID: String?

    // Capture device + format lookup — only touched on `queue`.
    private var device: AVCaptureDevice?
    private var formatsByID: [String: AVCaptureDevice.Format] = [:]

    // Detector state — only touched on `queue`.
    private var detector: Detector?
    private var activeFamilies: Set<TagFamily> = []

    // Frame-rate tracking — only touched on `queue`.
    private var lastPresentationTime: Double = 0
    private var smoothedFPS: Double = 0

    /// Pushes a new configuration to the detection pipeline.
    func update(config: DetectorConfig) {
        lock.lock()
        pendingConfig = config
        lock.unlock()
    }

    /// Selects a capture format by its `CaptureFormat.id`. `nil` keeps the
    /// current default. Applied immediately if the session is already running.
    func selectFormat(id: String?) {
        lock.lock()
        pendingFormatID = id
        lock.unlock()
        queue.async { self.applyPendingFormat() }
    }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.configureAndRun()
                } else {
                    DispatchQueue.main.async { self?.permissionDenied = true }
                }
            }
        default:
            DispatchQueue.main.async { self.permissionDenied = true }
        }
    }

    func stop() {
        queue.async { self.session.stopRunning() }
    }

    private func configureAndRun() {
        queue.async {
            self.configureSession()
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    private func configureSession() {
        session.beginConfiguration()

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        self.device = device
        session.addInput(input)

        // Deliver native biplanar buffers (no conversion) so high frame-rate
        // formats aren't held back; we only read the luma plane.
        output.videoSettings = nil
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) {
            session.addOutput(output)
        }

        // Rotate the delivered buffers so they match the portrait UI; this keeps
        // detection coordinates aligned with what is drawn on screen.
        if let connection = output.connection(with: .video),
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }

        session.commitConfiguration()

        publishFormats(for: device)
        applyPendingFormat()
    }

    /// Enumerates the device's biplanar formats as selectable resolution / max
    /// frame-rate combos and publishes them.
    private func publishFormats(for device: AVCaptureDevice) {
        var map: [String: AVCaptureDevice.Format] = [:]
        var formats: [CaptureFormat] = []

        for format in device.formats {
            let subtype = CMFormatDescriptionGetMediaSubType(format.formatDescription)
            guard subtype == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
                  subtype == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange else { continue }

            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let maxRate = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 30
            let candidate = CaptureFormat(width: Int(dims.width), height: Int(dims.height), frameRate: maxRate)

            // Keep the first format for each resolution@fps id; prefer full-range.
            if map[candidate.id] == nil || subtype == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange {
                if map[candidate.id] == nil { formats.append(candidate) }
                map[candidate.id] = format
            }
        }

        formats.sort {
            ($0.width * $0.height, $0.frameRate) < ($1.width * $1.height, $1.frameRate)
        }

        formatsByID = map
        DispatchQueue.main.async { self.availableFormats = formats }
    }

    /// Applies the pending (or default) format to the device.
    private func applyPendingFormat() {
        guard let device else { return }

        lock.lock()
        let requested = pendingFormatID
        lock.unlock()

        let chosen = requested.flatMap { formatsByID[$0] != nil ? $0 : nil } ?? defaultFormatID()
        guard let chosen, let format = formatsByID[chosen] else { return }

        let maxRate = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 30
        let duration = CMTime(value: 1, timescale: CMTimeScale(maxRate.rounded()))

        do {
            session.beginConfiguration()
            try device.lockForConfiguration()
            device.activeFormat = format
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            device.unlockForConfiguration()

            if let connection = output.connection(with: .video),
               connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            session.commitConfiguration()
        } catch {
            session.commitConfiguration()
            return
        }

        smoothedFPS = 0
        lastPresentationTime = 0
        DispatchQueue.main.async { self.activeFormatID = chosen }
    }

    /// A sensible starting format: 1280×720 (highest fps) if available, else the
    /// lowest-resolution option.
    private func defaultFormatID() -> String? {
        let preferred = formatsByID.keys
            .filter { $0.hasPrefix("1280x720@") }
            .max { lhs, rhs in (formatRate(lhs) ?? 0) < (formatRate(rhs) ?? 0) }
        if let preferred { return preferred }
        return availableFormatsSortedIDs().first
    }

    private func formatRate(_ id: String) -> Double? {
        id.split(separator: "@").last.flatMap { Double($0) }
    }

    private func availableFormatsSortedIDs() -> [String] {
        formatsByID.keys.sorted { lhs, rhs in
            let l = formatsByID[lhs]!, r = formatsByID[rhs]!
            let ld = CMVideoFormatDescriptionGetDimensions(l.formatDescription)
            let rd = CMVideoFormatDescriptionGetDimensions(r.formatDescription)
            return Int(ld.width) * Int(ld.height) < Int(rd.width) * Int(rd.height)
        }
    }

    /// Lazily (re)builds the detector when the family selection changes and
    /// applies the live scalar parameters. Returns `nil` when nothing should be
    /// detected (no families selected).
    private func ensureDetector(_ config: DetectorConfig) -> Detector? {
        if detector == nil || activeFamilies != config.families {
            let d = Detector()
            for family in config.families {
                d.addFamily(family.makeFamily())
            }
            detector = d
            activeFamilies = config.families
        }

        guard let detector, !config.families.isEmpty else { return nil }

        detector.threads = config.threads
        detector.quadDecimate = config.quadDecimate
        detector.quadSigma = config.quadSigma
        detector.refineEdges = config.refineEdges
        detector.decodeSharpening = config.decodeSharpening
        detector.minClusterPixels = config.minClusterPixels
        detector.maxNumMaxima = config.maxNumMaxima
        detector.criticalRad = config.criticalRad
        detector.maxLineFitMSE = config.maxLineFitMSE
        detector.minWhiteBlackDiff = config.minWhiteBlackDiff
        detector.deglitch = config.deglitch
        return detector
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return }
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let luma = base.assumingMemoryBound(to: UInt8.self)

        lock.lock()
        let config = pendingConfig
        lock.unlock()

        var results: [TagDetection] = []
        if let detector = ensureDetector(config) {
            results = detector.detect(luma, width: Int32(width), height: Int32(height), stride: Int32(stride)).map { d in
                let c = d.corners
                return TagDetection(
                    tagID: d.id,
                    familyName: d.family.name,
                    corners: [c.0, c.1, c.2, c.3],
                    center: d.center,
                    hamming: d.hamming,
                    decisionMargin: d.decisionMargin
                )
            }
        }

        let preview = Self.makeGrayImage(luma: luma, width: width, height: height, stride: stride)
        let size = CGSize(width: width, height: height)

        // Exponentially-smoothed frame rate from the buffer presentation times.
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        var fps = 0.0
        if lastPresentationTime > 0, pts > lastPresentationTime {
            let instant = 1.0 / (pts - lastPresentationTime)
            smoothedFPS = smoothedFPS == 0 ? instant : smoothedFPS * 0.9 + instant * 0.1
            fps = smoothedFPS
        }
        lastPresentationTime = pts

        DispatchQueue.main.async {
            self.frame = preview
            self.detections = results
            self.imageSize = size
            self.fps = fps
        }
    }

    /// Builds a grayscale `CGImage` from a copy of the luma plane.
    private static func makeGrayImage(luma: UnsafePointer<UInt8>, width: Int, height: Int, stride: Int) -> CGImage? {
        let data = Data(bytes: luma, count: stride * height)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: stride,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
