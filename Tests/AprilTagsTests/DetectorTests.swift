import XCTest
@testable import AprilTags

final class AprilTagsTests: XCTestCase {
    func testExample() throws {
        let detector = Detector()
        detector.addFamily(.tag16h5())
    }
}
