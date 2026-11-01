#include <metal_stdlib>
using namespace metal;

/// Procedural GPU-accelerated organic fluid mesh shader for Velora.
/// Evaluates continuous domain-warped sinusoidal flow and radial falloff in a single GPU pass,
/// replacing expensive CPU/CoreAnimation multi-layer Gaussian blurs.
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

    // Normalized UV [0.0, 1.0]
    float2 uv = position / size;

    // Centered coordinate space [-1.0, 1.0]
    float2 p = (uv - 0.5) * 2.0;
    float r = length(p);

    // Fast discard outside the bounding circle
    if (r > 1.0) {
        return half4(0.0, 0.0, 0.0, 0.0);
    }

    float t = time * velocity;
    float angle = atan2(p.y, p.x);

    // Domain warping harmonic flow
    float w1 = sin(p.x * 2.4 + t * 0.85) * cos(p.y * 2.4 + t * 0.65);
    float w2 = sin(p.x * 4.5 - t * 1.05 + w1 * 1.6) * cos(p.y * 4.5 + t * 0.75);
    float w3 = sin(angle * 3.0 + t * 1.25) * 0.22;

    // Flow intensity in [0.0, 1.0]
    float flow = clamp(0.5 + 0.38 * (w1 + w2) + w3, 0.0, 1.0);

    // 4-Quadrant color interpolation based on position and fluid perturbation
    float blendX = clamp(uv.x + w1 * 0.25, 0.0, 1.0);
    float blendY = clamp(uv.y + w2 * 0.25, 0.0, 1.0);

    half4 topMix = mix(color1, color2, half(blendX));
    half4 botMix = mix(color4, color3, half(blendX));
    half4 fluidColor = mix(topMix, botMix, half(blendY));

    // Modulate brightness slightly by the flow field
    fluidColor.rgb *= half(0.85 + flow * 0.35);

    // Active indexing telemetry pulse & scanning radar beam
    if (isBusy > 0.5) {
        // Rotating radar beam
        float sweepAngle = fmod(angle - t * 2.2, 2.0 * M_PI_F);
        if (sweepAngle < 0.0) {
            sweepAngle += 2.0 * M_PI_F;
        }
        float radarBeam = pow(sweepAngle / (2.0 * M_PI_F), 7.0) * 0.42;

        // Expanding concentric energy pulse
        float pulse = sin(r * 14.0 - t * 4.5) * 0.5 + 0.5;
        float pulseRing = smoothstep(0.45, 0.75, pulse) * smoothstep(0.9, 0.4, r) * 0.32;

        half3 cyberAccent = half3(color1.rgb * half(radarBeam + pulseRing));
        fluidColor.rgb += cyberAccent;
        fluidColor.a = max(fluidColor.a, half((radarBeam + pulseRing) * 0.6));
    }

    // Smooth feathered radial alpha mask to prevent any rectangular boundary artifacts
    float alphaMask = smoothstep(1.0, 0.65, r);
    fluidColor.a *= half(alphaMask);

    return fluidColor;
}
