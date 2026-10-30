// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Velora",
    platforms: [
        .macOS(.v15)
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
                    "../target/release/libvelora_ffi.a"
                ], .when(configuration: .release)),
                .unsafeFlags([
                    "-L../target/debug",
                    "-lvelora_ffi"
                ], .when(configuration: .debug))
            ]
        )
    ]
)
