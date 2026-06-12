import Foundation
import CAprilTags

public class Detector {
    private let td: UnsafeMutablePointer<apriltag_detector_t>!

    // Keep reference to families so they don't get deallocated
    private var families: [Family] = []

    public init(
        threads: Int32 = 1,
        quadDecimate: Float = 2.0,
        quadSigma: Float = 0.0,
        refineEdges: Bool = true,
        decodeSharpening: Double = 0.25
    ) {
        td = apriltag_detector_create()

        self.threads = threads
        self.quadDecimate = quadDecimate
        self.quadSigma = quadSigma
        self.refineEdges = refineEdges
        self.decodeSharpening = decodeSharpening
    }

    deinit {
        apriltag_detector_destroy(td)
    }

    public var threads: Int32 {
        get {
            td.pointee.nthreads
        }
        set {
            td.pointee.nthreads = newValue
        }
    }

    public var quadDecimate: Float {
        get {
            td.pointee.quad_decimate
        }
        set {
            td.pointee.quad_decimate = newValue
        }
    }


    public var quadSigma: Float {
        get {
            td.pointee.quad_sigma
        }
        set {
            td.pointee.quad_sigma = newValue
        }
    }


    public var refineEdges: Bool {
        get {
            td.pointee.refine_edges
        }
        set {
            td.pointee.refine_edges = newValue
        }
    }


    public var decodeSharpening: Double {
        get {
            td.pointee.decode_sharpening
        }
        set {
            td.pointee.decode_sharpening = newValue
        }
    }

    // MARK: - Quad threshold parameters (apriltag_quad_thresh_params)

    /// Reject quads containing fewer than this many pixels.
    public var minClusterPixels: Int32 {
        get { td.pointee.qtp.min_cluster_pixels }
        set { td.pointee.qtp.min_cluster_pixels = newValue }
    }

    /// How many corner candidates to consider when segmenting a group of pixels
    /// into a quad.
    public var maxNumMaxima: Int32 {
        get { td.pointee.qtp.max_nmaxima }
        set { td.pointee.qtp.max_nmaxima = newValue }
    }

    /// Reject quads where pairs of edges have angles too close to straight or
    /// 180 degrees (in radians). Zero rejects nothing. Setting this also updates
    /// the cached cosine the detector uses internally.
    public var criticalRad: Float {
        get { td.pointee.qtp.critical_rad }
        set {
            td.pointee.qtp.critical_rad = newValue
            td.pointee.qtp.cos_critical_rad = cosf(newValue)
        }
    }

    /// Maximum mean squared error allowed when fitting lines to contours;
    /// rejecting bad contours early saves expensive decoding.
    public var maxLineFitMSE: Float {
        get { td.pointee.qtp.max_line_fit_mse }
        set { td.pointee.qtp.max_line_fit_mse = newValue }
    }

    /// How much brighter (in pixel values, [0,255]) the white model must be than
    /// the black model.
    public var minWhiteBlackDiff: Int32 {
        get { td.pointee.qtp.min_white_black_diff }
        set { td.pointee.qtp.min_white_black_diff = newValue }
    }

    /// Deglitch the thresholded image. Only useful for very noisy images.
    public var deglitch: Bool {
        get { td.pointee.qtp.deglitch != 0 }
        set { td.pointee.qtp.deglitch = newValue ? 1 : 0 }
    }

    public func addFamily(_ family: Family, bits: Int32 = 2) {
        apriltag_detector_add_family_bits(td, family.tf, bits)
        self.families.append(family)
    }

    public func detect(_ data: UnsafePointer<UInt8>!, width: Int32, height: Int32, stride: Int32) -> [Detection] {
        var image = image_u8(width: width, height: height, stride: stride, buf: .init(mutating: data))
        let detected = apriltag_detector_detect(td, &image)
        defer { zarray_destroy(detected) }

        var result: [Detection] = []

        let size = zarray_size(detected)
        result.reserveCapacity(Int(size))

        for i in 0..<size {
            var p = UnsafeMutablePointer<apriltag_detection_t>(bitPattern: 0)
            zarray_get(detected, i, &p)
            result.append(Detection(p, family: families.first(where: { $0.tf == p?.pointee.family } )!))
        }

        return result
    }
}
