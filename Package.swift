// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AprilTags",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "AprilTags",
            targets: ["AprilTags"]),
    ],
    targets: [
        .target(
            name: "CAprilTags",
            exclude: ["./apriltag/apriltag_pywrap.c"],
            sources: [
                "./apriltag/common",
                "./apriltag/apriltag.c",
                "./apriltag/apriltag_pose.c",
                "./apriltag/apriltag_quad_thresh.c",
                "./apriltag/tag16h5.c",
                "./apriltag/tag25h9.c",
                "./apriltag/tag36h10.c",
                "./apriltag/tag36h11.c",
                "./apriltag/tagCircle21h7.c",
                "./apriltag/tagCircle49h12.c",
                "./apriltag/tagCustom48h12.c",
                "./apriltag/tagStandard41h12.c",
                "./apriltag/tagStandard52h13.c",
            ],
            publicHeadersPath: "apriltag",
            cSettings: [.headerSearchPath("./apriltag")]
        ),
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "AprilTags", dependencies: ["CAprilTags"]),
        .testTarget(
            name: "AprilTagsTests",
            dependencies: ["AprilTags"]),
    ]
)
