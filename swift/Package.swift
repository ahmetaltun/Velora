// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Velora",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Velora", targets: ["VeloraApp"])
    ],
    targets: [
        .target(
            name: "velora_ffiFFI",
            path: "Sources/velora_ffiFFI"
        ),
        .target(
            name: "VeloraCore",
            dependencies: ["velora_ffiFFI"],
            path: "Sources/VeloraCore"
        ),
        .executableTarget(
            name: "VeloraApp",
            dependencies: ["VeloraCore"],
            path: "Sources/VeloraApp",
            linkerSettings: [
                .unsafeFlags([
                    "-L../target/debug",
                    "-lvelora_ffi"
                ])
            ]
        )
    ]
)
