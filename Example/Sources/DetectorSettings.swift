import Foundation
import Combine

/// An immutable snapshot of every tunable detector parameter. The camera
/// pipeline reads this on its background queue, so it is a plain value type.
struct DetectorConfig: Equatable {
    var threads: Int32
    var quadDecimate: Float
    var quadSigma: Float
    var refineEdges: Bool
    var decodeSharpening: Double
    var families: Set<TagFamily>

    // Quad threshold parameters (apriltag_quad_thresh_params).
    var minClusterPixels: Int32
    var maxNumMaxima: Int32
    var criticalRad: Float
    var maxLineFitMSE: Float
    var minWhiteBlackDiff: Int32
    var deglitch: Bool

    static let `default` = DetectorConfig(
        threads: 2,
        quadDecimate: 2.0,
        quadSigma: 0.0,
        refineEdges: true,
        decodeSharpening: 0.25,
        families: [.tagStandard52h13],
        minClusterPixels: 24,
        maxNumMaxima: 10,
        criticalRad: Float(10 * Double.pi / 180),
        maxLineFitMSE: 10,
        minWhiteBlackDiff: 5,
        deglitch: false
    )
}

/// Observable wrapper used by the settings UI. Changes are persisted to
/// `UserDefaults` and projected into an immutable `DetectorConfig`.
final class DetectorSettings: ObservableObject {
    @Published var threads: Double
    @Published var quadDecimate: Double
    @Published var quadSigma: Double
    @Published var refineEdges: Bool
    @Published var decodeSharpening: Double
    @Published var families: Set<TagFamily>

    // Quad threshold parameters. `criticalAngleDegrees` is shown in degrees for
    // readability and converted to radians in `config`.
    @Published var minClusterPixels: Double
    @Published var maxNumMaxima: Double
    @Published var criticalAngleDegrees: Double
    @Published var maxLineFitMSE: Double
    @Published var minWhiteBlackDiff: Double
    @Published var deglitch: Bool

    /// Display preference (not part of `DetectorConfig`).
    @Published var showFPS: Bool {
        didSet { defaults.set(showFPS, forKey: Keys.showFPS) }
    }

    /// Selected capture format id (`CaptureFormat.id`); `nil` uses the camera's
    /// default. Not part of `DetectorConfig` — it is a capture setting.
    @Published var selectedFormatID: String? {
        didSet { defaults.set(selectedFormatID, forKey: Keys.selectedFormatID) }
    }

    private let defaults = UserDefaults.standard

    init() {
        let d = DetectorConfig.default
        threads = Double(defaults.object(forKey: Keys.threads) as? Int ?? Int(d.threads))
        quadDecimate = defaults.object(forKey: Keys.quadDecimate) as? Double ?? Double(d.quadDecimate)
        quadSigma = defaults.object(forKey: Keys.quadSigma) as? Double ?? Double(d.quadSigma)
        refineEdges = defaults.object(forKey: Keys.refineEdges) as? Bool ?? d.refineEdges
        decodeSharpening = defaults.object(forKey: Keys.decodeSharpening) as? Double ?? d.decodeSharpening
        if let saved = defaults.array(forKey: Keys.families) as? [String] {
            families = Set(saved.compactMap(TagFamily.init(rawValue:)))
        } else {
            families = d.families
        }
        minClusterPixels = defaults.object(forKey: Keys.minClusterPixels) as? Double ?? Double(d.minClusterPixels)
        maxNumMaxima = defaults.object(forKey: Keys.maxNumMaxima) as? Double ?? Double(d.maxNumMaxima)
        criticalAngleDegrees = defaults.object(forKey: Keys.criticalAngleDegrees) as? Double ?? Double(d.criticalRad) * 180 / .pi
        maxLineFitMSE = defaults.object(forKey: Keys.maxLineFitMSE) as? Double ?? Double(d.maxLineFitMSE)
        minWhiteBlackDiff = defaults.object(forKey: Keys.minWhiteBlackDiff) as? Double ?? Double(d.minWhiteBlackDiff)
        deglitch = defaults.object(forKey: Keys.deglitch) as? Bool ?? d.deglitch
        showFPS = defaults.object(forKey: Keys.showFPS) as? Bool ?? true
        selectedFormatID = defaults.string(forKey: Keys.selectedFormatID)
    }

    var config: DetectorConfig {
        DetectorConfig(
            threads: Int32(threads.rounded()),
            quadDecimate: Float(quadDecimate),
            quadSigma: Float(quadSigma),
            refineEdges: refineEdges,
            decodeSharpening: decodeSharpening,
            families: families,
            minClusterPixels: Int32(minClusterPixels.rounded()),
            maxNumMaxima: Int32(maxNumMaxima.rounded()),
            criticalRad: Float(criticalAngleDegrees * .pi / 180),
            maxLineFitMSE: Float(maxLineFitMSE),
            minWhiteBlackDiff: Int32(minWhiteBlackDiff.rounded()),
            deglitch: deglitch
        )
    }

    func isEnabled(_ family: TagFamily) -> Bool {
        families.contains(family)
    }

    func toggle(_ family: TagFamily, on: Bool) {
        if on { families.insert(family) } else { families.remove(family) }
    }

    /// Writes the current values to `UserDefaults`. Called whenever the config
    /// changes so the choices survive app relaunches.
    func persist() {
        defaults.set(Int(threads.rounded()), forKey: Keys.threads)
        defaults.set(quadDecimate, forKey: Keys.quadDecimate)
        defaults.set(quadSigma, forKey: Keys.quadSigma)
        defaults.set(refineEdges, forKey: Keys.refineEdges)
        defaults.set(decodeSharpening, forKey: Keys.decodeSharpening)
        defaults.set(families.map(\.rawValue), forKey: Keys.families)
        defaults.set(minClusterPixels, forKey: Keys.minClusterPixels)
        defaults.set(maxNumMaxima, forKey: Keys.maxNumMaxima)
        defaults.set(criticalAngleDegrees, forKey: Keys.criticalAngleDegrees)
        defaults.set(maxLineFitMSE, forKey: Keys.maxLineFitMSE)
        defaults.set(minWhiteBlackDiff, forKey: Keys.minWhiteBlackDiff)
        defaults.set(deglitch, forKey: Keys.deglitch)
    }

    private enum Keys {
        static let threads = "threads"
        static let quadDecimate = "quadDecimate"
        static let quadSigma = "quadSigma"
        static let refineEdges = "refineEdges"
        static let decodeSharpening = "decodeSharpening"
        static let families = "families"
        static let showFPS = "showFPS"
        static let selectedFormatID = "selectedFormatID"
        static let minClusterPixels = "minClusterPixels"
        static let maxNumMaxima = "maxNumMaxima"
        static let criticalAngleDegrees = "criticalAngleDegrees"
        static let maxLineFitMSE = "maxLineFitMSE"
        static let minWhiteBlackDiff = "minWhiteBlackDiff"
        static let deglitch = "deglitch"
    }
}
