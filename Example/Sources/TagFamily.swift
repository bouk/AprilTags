import AprilTags

/// The AprilTag families exposed by the `AprilTags` package, in a form that is
/// easy to list, persist and toggle from the settings UI.
enum TagFamily: String, CaseIterable, Identifiable {
    case tag16h5
    case tag25h9
    case tag36h10
    case tag36h11
    case tagCircle21h7
    case tagCircle49h12
    case tagCustom48h12
    case tagStandard41h12
    case tagStandard52h13

    var id: String { rawValue }

    /// Human friendly name shown in the settings list.
    var displayName: String {
        switch self {
        case .tag16h5: return "tag16h5"
        case .tag25h9: return "tag25h9"
        case .tag36h10: return "tag36h10"
        case .tag36h11: return "tag36h11"
        case .tagCircle21h7: return "tagCircle21h7"
        case .tagCircle49h12: return "tagCircle49h12"
        case .tagCustom48h12: return "tagCustom48h12"
        case .tagStandard41h12: return "tagStandard41h12"
        case .tagStandard52h13: return "tagStandard52h13"
        }
    }

    /// Creates a fresh `Family` instance for the detector.
    func makeFamily() -> Family {
        switch self {
        case .tag16h5: return .tag16h5()
        case .tag25h9: return .tag25h9()
        case .tag36h10: return .tag36h10()
        case .tag36h11: return .tag36h11()
        case .tagCircle21h7: return .tagCircle21h7()
        case .tagCircle49h12: return .tagCircle49h12()
        case .tagCustom48h12: return .tagCustom48h12()
        case .tagStandard41h12: return .tagStandard41h12()
        case .tagStandard52h13: return .tagStandard52h13()
        }
    }
}
