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
