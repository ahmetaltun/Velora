// swift-tools-version: 6.0
import PackageDescription
import Foundation

#if !arch(arm64)
fatalError("Velora is designed exclusively for Apple Silicon (ARM64) macOS devices.")
#endif

let package = Package(
    name: "Velora",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Velora", targets: ["VeloraApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.4")
    ],
    targets: [
        .target(
            name: "velora_ffiFFI",
            path: "Sources/velora_ffiFFI"
        ),
        .target(
            name: "VeloraCore",
            dependencies: ["velora_ffiFFI"],
            path: "Sources/VeloraCore",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "VeloraApp",
            dependencies: [
                "VeloraCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/VeloraApp",
            resources: [
                .process("Shaders/VeloraShaders.metal")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .unsafeFlags([
                    "../target/aarch64-apple-darwin/release/libvelora_ffi.a"
                ], .when(configuration: .release)),
                .unsafeFlags([
                    "../target/aarch64-apple-darwin/debug/libvelora_ffi.a"
                ], .when(configuration: .debug))
            ]
        )
    ]
)
