import Foundation
import Metal
import SwiftUI

/// Hardware-accelerated Metal shader pipeline manager for Velora on Apple Silicon.
/// Compiles Metal Shading Language (MSL) source at runtime using macOS Metal drivers,
/// serializes to a persistent cache, and interfaces with SwiftUI's `ShaderLibrary`.
@MainActor
public final class VeloraShaderManager: ObservableObject {
    public static let shared = VeloraShaderManager()

    @Published public private(set) var isHardwareAccelerated: Bool = false
    @Published public private(set) var shaderLibrary: ShaderLibrary? = nil

    private var compilationAttempted: Bool = false

    private init() {
        initializePipeline()
    }

    /// Initializes and prepares the Metal shader pipeline.
    public func initializePipeline() {
        guard !compilationAttempted else { return }
        compilationAttempted = true

        guard let device = MTLCreateSystemDefaultDevice() else {
            print("⚠️ [VeloraShaderManager] No Metal system default device available. Falling back to CoreAnimation.")
            return
        }

        do {
            let metallibURL = try getOrCompileLibrary(device: device)
            let lib = ShaderLibrary(url: metallibURL)
            self.shaderLibrary = lib
            self.isHardwareAccelerated = true
            print("✨ [VeloraShaderManager] Apple Silicon Metal shader library initialized successfully at: \(metallibURL.path)")
        } catch {
            print("⚠️ [VeloraShaderManager] Failed to initialize Metal shader library: \(error.localizedDescription). Falling back to software rendering.")
        }
    }

    private func getOrCompileLibrary(device: MTLDevice) throws -> URL {
        let fileManager = FileManager.default
        let cachesDir = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let veloraCache = cachesDir.appendingPathComponent("com.velora.app/shaders", isDirectory: true)
        try fileManager.createDirectory(at: veloraCache, withIntermediateDirectories: true)

        let metallibURL = veloraCache.appendingPathComponent("velora_v1.metallib")

        // If a cached metallib exists and is valid, reuse it
        if fileManager.fileExists(atPath: metallibURL.path) {
            if let attrs = try? fileManager.attributesOfItem(atPath: metallibURL.path),
               let size = attrs[.size] as? UInt64, size > 1024 {
                return metallibURL
            }
        }

        // Load shader source code
        let sourceCode = loadMetalSource()

        // Compile via Metal runtime driver
        let compileOptions = MTLCompileOptions()
        compileOptions.mathMode = .fast
        let metalLib = try device.makeLibrary(source: sourceCode, options: compileOptions)

        // Serialize to metallib format
        try serializeLibrary(metalLib, to: metallibURL)

        return metallibURL
    }

    private func loadMetalSource() -> String {
        // 1. Try to load from SPM resource bundle
        if let bundleURL = Bundle.module.url(forResource: "VeloraShaders", withExtension: "metal"),
           let content = try? String(contentsOf: bundleURL, encoding: .utf8) {
            return content
        }

        // 2. Embedded MSL fallback source (ensures zero external file dependency failure)
        return VeloraShaderSources.embeddedMetalSource
    }

    private func serializeLibrary(_ library: MTLLibrary, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            try? fileManager.removeItem(at: destinationURL)
        }

        let selector = NSSelectorFromString("serializeToURL:error:")
        let obj = library as AnyObject
        guard obj.responds(to: selector) else {
            throw NSError(
                domain: "VeloraShaderManager",
                code: 101,
                userInfo: [NSLocalizedDescriptionKey: "Current Metal runtime does not support library serialization."]
            )
        }

        let methodImp = obj.method(for: selector)
        typealias SerializeFunc = @convention(c) (AnyObject, Selector, NSURL, AutoreleasingUnsafeMutablePointer<NSError?>?) -> Bool
        let function = unsafeBitCast(methodImp, to: SerializeFunc.self)

        var serializeError: NSError?
        let success = function(obj, selector, destinationURL as NSURL, &serializeError)

        if !success || serializeError != nil {
            throw serializeError ?? NSError(
                domain: "VeloraShaderManager",
                code: 102,
                userInfo: [NSLocalizedDescriptionKey: "Failed to write compiled Metal library to disk."]
            )
        }
    }
}

/// Embedded fallback shader source ensuring Velora never fails if external resources are moved.
public enum VeloraShaderSources {
    public static let embeddedMetalSource = """
    #include <metal_stdlib>
    using namespace metal;

    /// Procedural GPU-accelerated organic fluid mesh shader for Velora.
    /// Evaluates continuous domain-warped sinusoidal flow and radial falloff in a single GPU pass.
    [[ stitchable ]] half4 ambientFluidShader(
        float2 position,
        half4 baseColor,
        float2 size,
        float time,
        float velocity,
        half4 color1,
        half4 color2,
        half4 color3,
        half4 color4,
        float isBusy
    ) {
        if (size.x <= 1.0 || size.y <= 1.0) {
            return baseColor;
        }

        float2 uv = position / size;
        float2 p = (uv - 0.5) * 2.0;
        float r = length(p);

        if (r > 1.0) {
            return half4(0.0, 0.0, 0.0, 0.0);
        }

        float t = time * velocity;
        float angle = atan2(p.y, p.x);

        // Domain warping harmonic flow
        float w1 = sin(p.x * 2.4 + t * 0.85) * cos(p.y * 2.4 + t * 0.65);
        float w2 = sin(p.x * 4.5 - t * 1.05 + w1 * 1.6) * cos(p.y * 4.5 + t * 0.75);
        float w3 = sin(angle * 3.0 + t * 1.25) * 0.22;

        float flow = clamp(0.5 + 0.38 * (w1 + w2) + w3, 0.0, 1.0);

        float blendX = clamp(uv.x + w1 * 0.25, 0.0, 1.0);
        float blendY = clamp(uv.y + w2 * 0.25, 0.0, 1.0);

        half4 topMix = mix(color1, color2, half(blendX));
        half4 botMix = mix(color4, color3, half(blendX));
        half4 fluidColor = mix(topMix, botMix, half(blendY));

        fluidColor.rgb *= half(0.85 + flow * 0.35);

        // Active indexing telemetry pulse & scanning radar beam
        if (isBusy > 0.5) {
            float sweepAngle = fmod(angle - t * 2.2, 2.0 * M_PI_F);
            if (sweepAngle < 0.0) {
                sweepAngle += 2.0 * M_PI_F;
            }
            float radarBeam = pow(sweepAngle / (2.0 * M_PI_F), 7.0) * 0.42;

            float pulse = sin(r * 14.0 - t * 4.5) * 0.5 + 0.5;
            float pulseRing = smoothstep(0.45, 0.75, pulse) * smoothstep(0.9, 0.4, r) * 0.32;

            half3 cyberAccent = half3(color1.rgb * half(radarBeam + pulseRing));
            fluidColor.rgb += cyberAccent;
            fluidColor.a = max(fluidColor.a, half((radarBeam + pulseRing) * 0.6));
        }

        float alphaMask = smoothstep(1.0, 0.65, r);
        fluidColor.a *= half(alphaMask);

        return fluidColor;
    }
    """
}
