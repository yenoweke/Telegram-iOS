import simd

/// Uniforms for Gaussian blur passes
/// Memory layout must match the struct in LiquidGlassShaders.metal
struct BlurUniforms {
    var texelSize: SIMD2<Float>   // 1.0 / textureSize
    var blurRadius: Int32         // Number of samples per direction
    var padding: Int32 = 0        // Alignment padding to 16 bytes
}

/// Uniforms for composite pass (final output with corner radius)
/// Memory layout must match the struct in LiquidGlassShaders.metal
struct CompositeUniforms {
    var viewSize: SIMD2<Float>    // View size in pixels (8 bytes, aligned to 8)
    var cornerRadius: Float       // Corner radius in pixels (4 bytes)
    var opacity: Float            // Overall opacity (0.0 - 1.0) (4 bytes)
    var shapePadding: SIMD2<Float> // Inset from edges in pixels (8 bytes)
}   // Total: 24 bytes

/// Vertex data for full-screen quad rendering
/// Memory layout must match the struct in LiquidGlassShaders.metal
struct Vertex {
    var position: SIMD2<Float>    // Clip-space position (-1 to 1)
    var texCoord: SIMD2<Float>    // Texture coordinates (0 to 1)
}

/// Uniforms for refraction composite pass
/// Memory layout must match the struct in LiquidGlassShaders.metal
struct RefractionUniforms {
    var viewSize: SIMD2<Float>    // View size in pixels (8 bytes)
    var cornerRadius: Float       // Corner radius in pixels (4 bytes)
    var opacity: Float            // Overall opacity (4 bytes)
    var refThickness: Float       // Refraction edge thickness (4 bytes)
    var refFactor: Float          // Refraction index factor (4 bytes)
    var fresnelRange: Float       // Fresnel effect range (4 bytes)
    var fresnelFactor: Float      // Fresnel intensity multiplier (4 bytes)
    var fresnelHardness: Float    // Fresnel curve shift (4 bytes)
    // Glare parameters
    var glareRange: Float         // Glare effect range (4 bytes)
    var glareFactor: Float        // Glare intensity multiplier (4 bytes)
    var glareHardness: Float      // Glare curve shift (4 bytes)
    var glareConvergence: Float   // Glare convergence/focus (4 bytes)
    var glareAngle: Float         // Light source angle in radians (4 bytes)
    var glareOppositeFactor: Float // Factor for opposite side glare (4 bytes)
    // Dispersion and tint
    var refDispersion: Float      // Chromatic dispersion strength (4 bytes)
    var useReflection: Float = 0  // Effect mode: 0.0 = refraction, 1.0 = reflection (4 bytes)
    var morphScale: SIMD2<Float>  // Morph scale for stretch effect (8 bytes)
    var shapePadding: SIMD2<Float> // Inset from edges in pixels (8 bytes)
    var tint: SIMD4<Float>        // Tint color RGBA (16 bytes)
    var glareFarsideColor: SIMD4<Float>   // Glare color on far side RGBA (16 bytes)
    var glareNearsideColor: SIMD4<Float>  // Glare color on near side RGBA (16 bytes)
}   // Total: 128 bytes

/// Uniforms for inner shadow pass
/// Memory layout must match the struct in LiquidGlassShaders.metal
struct InnerShadowUniforms {
    var viewSize: SIMD2<Float>      // View size in pixels (8 bytes)
    var cornerRadius: Float         // Corner radius in pixels (4 bytes)
    var padding1: Float = 0         // Alignment padding (4 bytes)
    var shapePadding: SIMD2<Float>  // Inset from edges in pixels (8 bytes)
    var morphScale: SIMD2<Float>    // Morph scale for stretch effect (8 bytes)
}   // Total: 32 bytes
