//
//  File.swift
//  
//
//  Created by Bouke van der Bijl on 07/06/2024.
//

import Foundation
import CAprilTags

public class Detection {
    private let det: UnsafeMutablePointer<apriltag_detection_t>!
    public let family: Family

    internal init(_ det: UnsafeMutablePointer<apriltag_detection_t>!, family: Family) {
        self.det = det
        self.family = family
    }

    deinit {
        apriltag_detection_destroy(det)
    }

    public var id: Int32 {
        det.pointee.id
    }

    public var hamming: Int32 {
        det.pointee.hamming
    }

    public var decisionMargin: Float {
        det.pointee.decision_margin
    }

    public var center: CGPoint {
        .init(x: det.pointee.c.0, y: det.pointee.c.1)
    }

    public var corners: (CGPoint, CGPoint, CGPoint, CGPoint) {
        (
            .init(x: det.pointee.p.0.0, y: det.pointee.p.0.1),
            .init(x: det.pointee.p.1.0, y: det.pointee.p.1.1),
            .init(x: det.pointee.p.2.0, y: det.pointee.p.2.1),
            .init(x: det.pointee.p.3.0, y: det.pointee.p.3.1)
        )
    }
}
