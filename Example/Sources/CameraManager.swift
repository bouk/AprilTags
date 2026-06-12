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

/// A frozen full-resolution still that the user can re-run detection on with
/// different parameters. The grayscale `image` is what gets drawn; the luma is
/// retained separately (off the main thread) for re-detection.
struct CapturedFrame: Identifiable {
    let id = UUID()
    let image: CGImage
    let size: CGSize
}

/// Drives the camera, feeds each grayscale frame into the AprilTag detector and
/// publishes both the preview image and the detections for SwiftUI to render.
/// Tapping the screen captures a full-resolution still through the photo output
/// so detection can be tuned against a fixed, maximum-fidelity image.
final class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate {
    @Published var frame: CGImage?
    @Published var detections: [TagDetection] = []
    @Published var imageSize: CGSize = .zero
    @Published var permissionDenied = false
    @Published var fps: Double = 0

    /// All resolution / frame-rate combos the active camera supports.
    @Published var availableFormats: [CaptureFormat] = []
    /// The streaming format currently in use.
    @Published var activeFormatID: String?

    /// Still sizes each live format can capture, keyed by `CaptureFormat.id`.
    /// Lets the settings UI show (and default) the right photo sizes for the
    /// selected live format before it is applied — on iPhone only the
    /// full-resolution video format reaches 48 MP.
    @Published var photoSizesByFormatID: [String: [CaptureFormat]] = [:]

    /// The frozen still currently being inspected, or `nil` when live.
    @Published var capturedFrame: CapturedFrame?
    /// Detections for `capturedFrame`, refreshed when parameters change.
    @Published var capturedDetections: [TagDetection] = []
    /// True while a still capture is in flight.
    @Published var isCapturing = false
    /// True while detection is being re-run on the frozen still.
    @Published var isRedetecting = false

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "ke.bou.AprilTagsExample.camera")

    // Config is written from the main thread and read on `queue`.
    private let lock = NSLock()
    private var pendingConfig = DetectorConfig.default
    private var pendingFormatID: String?
    private var requestedPhotoSizeID: String?

    // Capture device + format lookup — only touched on `queue`.
    private var device: AVCaptureDevice?
    private var formatsByID: [String: AVCaptureDevice.Format] = [:]

    // Detector state — only touched on `queue`.
    private var detector: Detector?
    private var activeFamilies: Set<TagFamily> = []

    // Retained luma of the current capture, for re-detection — only on `queue`.
    private var capturedLuma: CopiedLuma?
    // Freezes the live preview while a still capture is being taken.
    private var capturing = false

    // Frame-rate tracking — only touched on `queue`.
    private var lastPresentationTime: Double = 0
    private var smoothedFPS: Double = 0

    /// A copied luma plane — owned, so it outlives the source pixel buffer.
    private struct CopiedLuma {
        let data: Data
        let width: Int
        let height: Int
        let stride: Int
    }

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

    /// Selects the still-capture size by `CaptureFormat.id`; `nil` uses the
    /// largest the current live format supports.
    func selectPhotoSize(id: String?) {
        lock.lock()
        requestedPhotoSizeID = id
        lock.unlock()
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

    // MARK: Still capture

    /// Captures one full-resolution still at the selected photo size and freezes
    /// it for inspection. `config` is the detector config to use for the first
    /// detection pass.
    func capturePhoto(config: DetectorConfig) {
        update(config: config)
        DispatchQueue.main.async { self.isCapturing = true }
        queue.async { self.triggerCapture() }
    }

    /// Re-runs detection on the frozen still with new parameters.
    func rerunDetection(config: DetectorConfig) {
        update(config: config)
        DispatchQueue.main.async { self.isRedetecting = true }
        queue.async {
            guard let luma = self.capturedLuma else {
                DispatchQueue.main.async { self.isRedetecting = false }
                return
            }
            let results = self.runDetection(on: luma, config: config)
            DispatchQueue.main.async {
                self.capturedDetections = results
                self.isRedetecting = false
            }
        }
    }

    /// Discards the frozen still and returns to the live feed.
    func dismissCapture() {
        capturedFrame = nil
        capturedDetections = []
        queue.async { self.capturedLuma = nil }
    }

    private func triggerCapture() {
        guard let device else {
            DispatchQueue.main.async { self.isCapturing = false }
            return
        }

        // Freeze the live preview so the brief sensor interruption during the
        // full-resolution readout isn't shown.
        capturing = true

        lock.lock()
        let requested = requestedPhotoSizeID
        lock.unlock()

        let dims = chosenPhotoDimensions(requested, for: device.activeFormat)
        let settings = makePhotoSettings(dims: dims)
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    /// Picks the requested still size if the active format supports it, else the
    /// largest it does support.
    private func chosenPhotoDimensions(_ requested: String?, for format: AVCaptureDevice.Format) -> CMVideoDimensions {
        let supported = format.supportedMaxPhotoDimensions
        if let requested,
           let match = supported.first(where: {
               CaptureFormat(photoWidth: Int($0.width), height: Int($0.height)).id == requested
           }) {
            return match
        }
        if let largest = supported.max(by: { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }) {
            return largest
        }
        return CMVideoFormatDescriptionGetDimensions(format.formatDescription)
    }

    private func makePhotoSettings(dims: CMVideoDimensions) -> AVCapturePhotoSettings {
        let biplanar = [
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ].first { photoOutput.availablePhotoPixelFormatTypes.contains($0) }

        let settings: AVCapturePhotoSettings
        if let biplanar {
            settings = AVCapturePhotoSettings(format: [kCVPixelBufferPixelFormatTypeKey as String: biplanar])
        } else {
            // Fall back to the default (likely HEIF) — extracted via CGImage.
            settings = AVCapturePhotoSettings()
        }
        settings.maxPhotoDimensions = dims
        settings.photoQualityPrioritization = .balanced
        return settings
    }

    private func prewarmPhotoPipeline() {
        guard session.isRunning, photoOutput.maxPhotoDimensions.width > 0 else { return }
        let settings = makePhotoSettings(dims: photoOutput.maxPhotoDimensions)
        photoOutput.setPreparedPhotoSettingsArray([settings]) { _, _ in }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        // Copy pixels synchronously: the buffer is only valid for this callback.
        let copied = Self.copyLuma(from: photo)

        queue.async {
            self.capturing = false

            guard let copied, let image = Self.makeGrayImage(copied) else {
                DispatchQueue.main.async { self.isCapturing = false }
                return
            }
            self.capturedLuma = copied
            let size = CGSize(width: copied.width, height: copied.height)

            // Show the captured frame right away; detection on a full-resolution
            // image is slow, so run it under the "Detecting…" indicator.
            DispatchQueue.main.async {
                self.capturedDetections = []
                self.capturedFrame = CapturedFrame(image: image, size: size)
                self.isCapturing = false
                self.isRedetecting = true
            }

            let config = self.currentConfig()
            let results = self.runDetection(on: copied, config: config)
            DispatchQueue.main.async {
                self.capturedDetections = results
                self.isRedetecting = false
            }
        }
    }

    // MARK: Session setup

    private func configureAndRun() {
        queue.async {
            self.configureSession()
            if !self.session.isRunning {
                self.session.startRunning()
            }
            self.prewarmPhotoPipeline()
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

        // Photo output for full-resolution tap-to-capture stills.
        photoOutput.maxPhotoQualityPrioritization = .quality
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        if photoOutput.isResponsiveCaptureSupported {
            photoOutput.isResponsiveCaptureEnabled = true
            if photoOutput.isFastCapturePrioritizationSupported {
                photoOutput.isFastCapturePrioritizationEnabled = true
            }
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

            // Keep the format with the largest still capability for each
            // resolution@fps id, preferring full-range otherwise.
            if let existing = map[candidate.id] {
                if maxStillArea(format) > maxStillArea(existing) ||
                   (maxStillArea(format) == maxStillArea(existing) && subtype == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
                    map[candidate.id] = format
                }
            } else {
                formats.append(candidate)
                map[candidate.id] = format
            }
        }

        formats.sort {
            ($0.width * $0.height, $0.frameRate) < ($1.width * $1.height, $1.frameRate)
        }

        var photoSizes: [String: [CaptureFormat]] = [:]
        for (id, format) in map {
            photoSizes[id] = stillSizes(for: format)
        }

        formatsByID = map
        DispatchQueue.main.async {
            self.availableFormats = formats
            self.photoSizesByFormatID = photoSizes
        }
    }

    /// The distinct still sizes a format can capture, sorted ascending.
    private func stillSizes(for format: AVCaptureDevice.Format) -> [CaptureFormat] {
        var seen: Set<String> = []
        return format.supportedMaxPhotoDimensions
            .map { CaptureFormat(photoWidth: Int($0.width), height: Int($0.height)) }
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.width * $0.height < $1.width * $1.height }
    }

    private func maxStillArea(_ format: AVCaptureDevice.Format) -> Int {
        format.supportedMaxPhotoDimensions
            .map { Int($0.width) * Int($0.height) }
            .max() ?? 0
    }

    /// Applies the pending (or default) format to the device, then updates the
    /// photo-output limits and the still sizes that format can shoot.
    private func applyPendingFormat() {
        guard let device else { return }

        lock.lock()
        let requested = pendingFormatID
        lock.unlock()

        let chosen = requested.flatMap { formatsByID[$0] != nil ? $0 : nil } ?? defaultFormatID()
        guard let chosen, let format = formatsByID[chosen] else { return }

        let maxRate = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 30
        let duration = CMTime(value: 1, timescale: CMTimeScale(maxRate.rounded()))
        let largestStill = format.supportedMaxPhotoDimensions
            .max { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }

        do {
            session.beginConfiguration()
            try device.lockForConfiguration()
            device.activeFormat = format
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            device.unlockForConfiguration()

            if let largestStill {
                photoOutput.maxPhotoDimensions = largestStill
            }
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
        prewarmPhotoPipeline()
        DispatchQueue.main.async { self.activeFormatID = chosen }
    }

    /// A sensible starting format: the one that can shoot the largest still
    /// (full sensor resolution), so tap-to-capture reaches maximum fidelity
    /// without ever switching formats.
    private func defaultFormatID() -> String? {
        let best = formatsByID.max { maxStillArea($0.value) < maxStillArea($1.value) }
        if let best, maxStillArea(best.value) > 0 { return best.key }
        return availableFormatsSortedIDs().first
    }

    private func availableFormatsSortedIDs() -> [String] {
        formatsByID.keys.sorted { lhs, rhs in
            let l = formatsByID[lhs]!, r = formatsByID[rhs]!
            let ld = CMVideoFormatDescriptionGetDimensions(l.formatDescription)
            let rd = CMVideoFormatDescriptionGetDimensions(r.formatDescription)
            return Int(ld.width) * Int(ld.height) < Int(rd.width) * Int(rd.height)
        }
    }

    // MARK: Detection

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

    private func currentConfig() -> DetectorConfig {
        lock.lock()
        let config = pendingConfig
        lock.unlock()
        return config
    }

    /// Runs the detector over a retained luma plane. Only called on `queue`.
    private func runDetection(on luma: CopiedLuma, config: DetectorConfig) -> [TagDetection] {
        guard let detector = ensureDetector(config) else { return [] }
        return luma.data.withUnsafeBytes { raw -> [TagDetection] in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return [] }
            return detector.detect(base, width: Int32(luma.width), height: Int32(luma.height), stride: Int32(luma.stride)).map {
                Self.makeDetection($0)
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Hold the last live frame while a still capture is in flight.
        if capturing { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return }
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let luma = base.assumingMemoryBound(to: UInt8.self)

        let config = currentConfig()

        var results: [TagDetection] = []
        if let detector = ensureDetector(config) {
            results = detector.detect(luma, width: Int32(width), height: Int32(height), stride: Int32(stride)).map {
                Self.makeDetection($0)
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

    private static func makeDetection(_ d: Detection) -> TagDetection {
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

    // MARK: Image helpers

    /// Copies the luma plane out of a captured photo so it survives the
    /// delegate callback. Prefers the biplanar pixel buffer; falls back to a
    /// CGImage rendered into a grayscale context.
    private static func copyLuma(from photo: AVCapturePhoto) -> CopiedLuma? {
        if let pixelBuffer = photo.pixelBuffer {
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
            if let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) {
                let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
                let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
                let stride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
                let data = Data(bytes: base, count: stride * height)
                return CopiedLuma(data: data, width: width, height: height, stride: stride)
            }
        }

        if let cgImage = photo.cgImageRepresentation() {
            return grayLuma(from: cgImage)
        }
        return nil
    }

    /// Renders an RGB CGImage into a tightly-packed grayscale buffer.
    private static func grayLuma(from image: CGImage) -> CopiedLuma? {
        let width = image.width
        let height = image.height
        let stride = width
        var bytes = [UInt8](repeating: 0, count: stride * height)
        let success = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: stride,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard success else { return nil }
        return CopiedLuma(data: Data(bytes), width: width, height: height, stride: stride)
    }

    private static func makeGrayImage(_ luma: CopiedLuma) -> CGImage? {
        luma.data.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return nil }
            return makeGrayImage(luma: base, width: luma.width, height: luma.height, stride: luma.stride)
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
