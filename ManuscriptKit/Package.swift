// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ManuscriptKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "ManuscriptKit", targets: ["ManuscriptKit"]),
    ],
    dependencies: [
        // libgit2 compiled from source under SwiftPM. Vendored rather than fetched:
        // the package needs unsafe C flags, which SwiftPM allows only for local
        // packages. Upstream: https://github.com/Formkunft/swift-libgit2 v1.9.6.
        .package(path: "../Vendor/swift-libgit2"),
    ],
    targets: [
        .target(
            name: "ManuscriptKit",
            dependencies: [
                .product(name: "Clibgit2", package: "swift-libgit2"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ManuscriptKitTests",
            dependencies: ["ManuscriptKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
