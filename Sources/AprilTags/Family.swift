//
//  File.swift
//  
//
//  Created by Bouke van der Bijl on 07/06/2024.
//

import Foundation
import CAprilTags

public class Family {
    internal let tf: UnsafeMutablePointer<apriltag_family_t>!
    private let destroy: (UnsafeMutablePointer<apriltag_family_t>?) -> Void

    fileprivate init(_ create: () -> UnsafeMutablePointer<apriltag_family_t>?, _ destroy: @escaping (UnsafeMutablePointer<apriltag_family_t>?) -> Void) {
        tf = create()
        self.destroy = destroy
    }

    deinit {
        destroy(tf)
    }

    public var name: String {
        String(cString: tf.pointee.name)
    }

    public static func tag16h5() -> Family {
        Family(tag16h5_create, tag16h5_destroy)
    }

    public static func tag25h9() -> Family {
        Family(tag25h9_create, tag25h9_destroy)
    }

    public static func tag36h10() -> Family {
        Family(tag36h10_create, tag36h10_destroy)
    }

    public static func tag36h11() -> Family {
        Family(tag36h11_create, tag36h11_destroy)
    }

    public static func tagCircle21h7() -> Family {
        Family(tagCircle21h7_create, tagCircle21h7_destroy)
    }

    public static func tagCircle49h12() -> Family {
        Family(tagCircle49h12_create, tagCircle49h12_destroy)
    }

    public static func tagCustom48h12() -> Family {
        Family(tagCustom48h12_create, tagCustom48h12_destroy)
    }

    public static func tagStandard41h12() -> Family {
        Family(tagStandard41h12_create, tagStandard41h12_destroy)
    }

    public static func tagStandard52h13() -> Family {
        Family(tagStandard52h13_create, tagStandard52h13_destroy)
    }
}
