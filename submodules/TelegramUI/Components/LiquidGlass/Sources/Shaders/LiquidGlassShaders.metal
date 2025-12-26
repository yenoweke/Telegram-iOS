#include <metal_stdlib>
using namespace metal;

// MARK: - Shared Types (must match ShaderTypes.swift)

struct BlurUniforms {
    float2 texelSize;
    int blurRadius;
    int padding;
};

struct CompositeUniforms {
    float2 viewSize;     // 8 bytes, aligned to 8
    float cornerRadius;  // 4 bytes
    float opacity;       // 4 bytes
    float2 shapePadding; // 8 bytes - inset from edges
};   // Total: 24 bytes

struct RefractionUniforms {
    float2 viewSize;      // 8 bytes
    float cornerRadius;   // 4 bytes
    float opacity;        // 4 bytes
    float refThickness;   // 4 bytes
    float refFactor;      // 4 bytes
    float fresnelRange;   // 4 bytes
    float fresnelFactor;  // 4 bytes
    float fresnelHardness;// 4 bytes
    // Glare parameters
    float glareRange;     // 4 bytes
    float glareFactor;    // 4 bytes
    float glareHardness;  // 4 bytes
    float glareConvergence; // 4 bytes
    float glareAngle;     // 4 bytes
    float glareOppositeFactor; // 4 bytes
    // Dispersion and tint
    float refDispersion;  // 4 bytes
    float useReflection;  // 4 bytes (0.0 = refraction, 1.0 = reflection)
    float2 morphScale;    // 8 bytes - morph scale for stretch effect
    float2 shapePadding;  // 8 bytes - inset from edges
    float4 tint;          // 16 bytes
    float4 glareFarsideColor;  // 16 bytes - glare color on far side
    float4 glareNearsideColor; // 16 bytes - glare color on near side
};   // Total: 128 bytes

// Inner shadow pass uniforms
struct InnerShadowUniforms {
    float2 viewSize;      // 8 bytes
    float cornerRadius;   // 4 bytes
    float padding1;       // 4 bytes (alignment)
    float2 shapePadding;  // 8 bytes
    float2 morphScale;    // 8 bytes
};   // Total: 32 bytes

// Constants
constant float PI = 3.14159265359;

// Chromatic dispersion coefficients (different refraction indices for R/G/B)
constant float N_R = 1.0 + 0.04;   // Red refracts less
constant float N_G = 1.0;          // Green is baseline
constant float N_B = 1.0 - 0.04;   // Blue refracts more

// Shadow parameters (tune these constants to adjust shadow appearance)
constant float SHADOW_OPACITY = 0.25;        // Shadow intensity (0.0 - 1.0)
constant float SHADOW_RADIUS = 10.0;          // Shadow spread in pixels
constant float SHADOW_SOFTNESS = 1.0;        // Edge softness (higher = softer)
constant float3 SHADOW_COLOR = float3(0.0);  // Shadow color (black)
constant float2 SHADOW_DIRECTION = float2(0.0, 1.0); // Shadow direction: bottom only (X: -1=left, +1=right; Y: -1=top, +1=bottom)
constant float SHADOW_DIRECTION_HARDNESS = 1.0;       // How sharp the directional cutoff is (higher = sharper)

// Inner shadow parameters (applied inside the shape boundary)
constant float INNER_SHADOW_OPACITY = 0.15;      // Inner shadow intensity (0.0 - 1.0)
constant float INNER_SHADOW_RADIUS = 30.0;       // Inner shadow spread in pixels from edge
constant float INNER_SHADOW_SOFTNESS = 1.2;      // Inner edge softness (higher = softer fade)
constant float2 INNER_SHADOW_DIRECTION = float2(0.0, -1.0); // Inner shadow direction: top only (opposite of outer shadow)
// Note: SHADOW_COLOR is shared between inner and outer shadows

// Convert 2D vector to angle (0 to 2*PI)
float vec2ToAngle(float2 v) {
    float angle = atan2(v.y, v.x);
    if (angle < 0.0) angle += 2.0 * PI;
    return angle;
}

struct Vertex {
    float2 position;
    float2 texCoord;
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// MARK: - Vertex Shader

vertex VertexOut vertexPassthrough(
    uint vertexID [[vertex_id]],
    constant Vertex* vertices [[buffer(0)]]
) {
    VertexOut out;
    out.position = float4(vertices[vertexID].position, 0.0, 1.0);
    out.texCoord = vertices[vertexID].texCoord;
    return out;
}

// MARK: - Horizontal Gaussian Blur

fragment half4 gaussianBlurHorizontal(
    VertexOut in [[stage_in]],
    texture2d<half, access::sample> srcTexture [[texture(0)]],
    constant BlurUniforms& uniforms [[buffer(0)]],
    constant float* weights [[buffer(1)]]
) {
    constexpr sampler textureSampler(
        mag_filter::linear,
        min_filter::linear,
        address::clamp_to_edge
    );

    // Center sample
    half4 color = srcTexture.sample(textureSampler, in.texCoord) * half(weights[0]);

    // Symmetric samples left and right
    for (int i = 1; i <= uniforms.blurRadius; ++i) {
        half w = half(weights[i]);
        float offsetX = float(i) * uniforms.texelSize.x;

        color += srcTexture.sample(textureSampler, in.texCoord + float2(offsetX, 0.0)) * w;
        color += srcTexture.sample(textureSampler, in.texCoord - float2(offsetX, 0.0)) * w;
    }

    return color;
}

// MARK: - Vertical Gaussian Blur

fragment half4 gaussianBlurVertical(
    VertexOut in [[stage_in]],
    texture2d<half, access::sample> srcTexture [[texture(0)]],
    constant BlurUniforms& uniforms [[buffer(0)]],
    constant float* weights [[buffer(1)]]
) {
    constexpr sampler textureSampler(
        mag_filter::linear,
        min_filter::linear,
        address::clamp_to_edge
    );

    // Center sample
    half4 color = srcTexture.sample(textureSampler, in.texCoord) * half(weights[0]);

    // Symmetric samples up and down
    for (int i = 1; i <= uniforms.blurRadius; ++i) {
        half w = half(weights[i]);
        float offsetY = float(i) * uniforms.texelSize.y;

        color += srcTexture.sample(textureSampler, in.texCoord + float2(0.0, offsetY)) * w;
        color += srcTexture.sample(textureSampler, in.texCoord - float2(0.0, offsetY)) * w;
    }

    return color;
}

// MARK: - Composite Pass (Final Output with Corner Radius)

// Signed distance function for rounded rectangle
float roundedRectSDF(float2 position, float2 halfSize, float radius) {
    float2 q = abs(position) - halfSize + radius;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

// Analytical gradient of roundedRectSDF - returns normalized direction away from shape
float2 getRoundedRectGradient(float2 position, float2 halfSize, float radius) {
    float2 q = abs(position) - halfSize + radius;
    float2 signP = sign(position);

    float2 grad;
    if (q.x > 0.0 && q.y > 0.0) {
        // Corner region: gradient points away from corner arc center
        float len = length(q);
        grad = (len > 0.0001) ? (q / len) : float2(0.707, 0.707);
        grad *= signP;
    } else if (q.x > q.y) {
        // Vertical edge region
        grad = float2(signP.x, 0.0);
    } else {
        // Horizontal edge region
        grad = float2(0.0, signP.y);
    }

    return grad;
}

fragment half4 compositeFragment(
    VertexOut in [[stage_in]],
    texture2d<half, access::sample> blurredTexture [[texture(0)]],
    constant CompositeUniforms& uniforms [[buffer(0)]]
) {
    constexpr sampler textureSampler(
        mag_filter::linear,
        min_filter::linear,
        address::clamp_to_edge
    );

    half4 color = blurredTexture.sample(textureSampler, in.texCoord);

    // Apply corner radius mask with directional shadow yenoweke
    if (uniforms.cornerRadius > 0.0) {
        // Convert UV to pixel coordinates centered at view center
        float2 pixelPos = in.texCoord * uniforms.viewSize;
        float2 center = uniforms.viewSize * 0.5;
        float2 centered = pixelPos - center;

        // Calculate SDF for rounded rectangle (with padding inset)
        float2 halfSize = center - uniforms.shapePadding;
        float dist = roundedRectSDF(centered, halfSize, uniforms.cornerRadius);

        if (dist < -INNER_SHADOW_RADIUS) {
            // Deep inside shape - no shadow, keep full opacity
            // color.a unchanged

        } else if (dist < 0.0) {
            // Inside shape within inner shadow range
            float innerDist = -dist;

            // Get gradient (direction away from shape edge)
            float2 grad = getRoundedRectGradient(centered, halfSize, uniforms.cornerRadius);

            // Calculate directional factor: how aligned is gradient with inner shadow direction
            float2 innerShadowDir = normalize(INNER_SHADOW_DIRECTION);
            float dirFactor = dot(grad, innerShadowDir);
            dirFactor = clamp(pow(max(0.0, dirFactor), SHADOW_DIRECTION_HARDNESS), 0.0, 1.0);

            // Inner shadow zone - fade from edge inward
            float innerShadowFactor = 1.0 - smoothstep(0.0, INNER_SHADOW_RADIUS * INNER_SHADOW_SOFTNESS, innerDist);
            innerShadowFactor *= INNER_SHADOW_OPACITY * dirFactor;

            // Blend shadow with existing color
            if (innerShadowFactor > 0.001) {
                // Mix current color with shadow color
                color.rgb = mix(color.rgb, half3(SHADOW_COLOR), half(innerShadowFactor));
                // Note: We don't modify alpha here - we're darkening the existing content
            }

        } else if (dist < SHADOW_RADIUS) {
            // Outer shadow zone (existing logic)
            // Get gradient (direction away from shape edge)
            float2 grad = getRoundedRectGradient(centered, halfSize, uniforms.cornerRadius);

            // Calculate directional factor: how aligned is gradient with shadow direction
            float2 shadowDir = normalize(SHADOW_DIRECTION);
            float dirFactor = dot(grad, shadowDir);
            dirFactor = clamp(pow(max(0.0, dirFactor), SHADOW_DIRECTION_HARDNESS), 0.0, 1.0);

            // Shadow zone - fade from shadow to transparent
            float shadowFactor = 1.0 - smoothstep(0.0, SHADOW_RADIUS * SHADOW_SOFTNESS, dist);
            shadowFactor *= SHADOW_OPACITY * dirFactor;

            if (shadowFactor > 0.001) {
                color.rgb = half3(SHADOW_COLOR);
                color.a = half(shadowFactor);
            } else {
                color.a = 0.0;
            }
        } else {
            // Outside shadow - fully transparent
            color.a = 0.0;
        }
    }

    // Apply overall opacity
    color.a *= half(uniforms.opacity);

    return color;
}

// MARK: - Inner Shadow Pass

fragment half4 innerShadowFragment(
    VertexOut in [[stage_in]],
    texture2d<half, access::sample> blurredTexture [[texture(0)]],
    constant InnerShadowUniforms& uniforms [[buffer(0)]]
) {
    constexpr sampler textureSampler(
        mag_filter::linear,
        min_filter::linear,
        address::clamp_to_edge
    );

    // Sample the blurred texture
    half4 color = blurredTexture.sample(textureSampler, in.texCoord);

    // Convert UV to centered pixel coordinates
    float2 pixelPos = in.texCoord * uniforms.viewSize - uniforms.viewSize * 0.5;
    float2 halfSize = uniforms.viewSize * 0.5 - uniforms.shapePadding;
    float2 scaledPixelPos = pixelPos / uniforms.morphScale;

    // Calculate SDF
    float dist = roundedRectSDF(scaledPixelPos, halfSize, uniforms.cornerRadius);

    // Apply inner shadow only if within range
    if (dist >= -INNER_SHADOW_RADIUS && dist < 0.0) {
        float innerDist = -dist;
        float2 grad = getRoundedRectGradient(scaledPixelPos, halfSize, uniforms.cornerRadius);

        // Calculate directional factor: shadow only at top
        float2 innerShadowDir = normalize(INNER_SHADOW_DIRECTION);
        float dirFactor = dot(grad, innerShadowDir);
        dirFactor = clamp(pow(max(0.0, dirFactor), SHADOW_DIRECTION_HARDNESS), 0.0, 1.0);

        // Inner shadow zone - fade from edge inward
        float innerShadowFactor = 1.0 - smoothstep(0.0, INNER_SHADOW_RADIUS * INNER_SHADOW_SOFTNESS, innerDist);
        innerShadowFactor *= INNER_SHADOW_OPACITY * dirFactor;

        if (innerShadowFactor > 0.001) {
            color.rgb = mix(color.rgb, half3(SHADOW_COLOR), half(innerShadowFactor));
        }
    }

    return color;
}

// MARK: - Refraction Effect

// Sample texture with chromatic dispersion (different UV offsets for R/G/B)
half4 sampleWithDispersion(
    texture2d<half, access::sample> tex,
    sampler s,
    float2 baseUV,
    float2 offset,
    float dispersionFactor
) {
    // Each channel gets a different offset based on its refraction index
    // N_R - 1.0 = -0.02, so red offset is multiplied by (1.0 + 0.02 * factor) - MORE offset
    // N_G - 1.0 = 0.0, so green offset stays the same
    // N_B - 1.0 = +0.02, so blue offset is multiplied by (1.0 - 0.02 * factor) - LESS offset
    half4 pixel = half4(1.0h);
    pixel.r = tex.sample(s, baseUV + offset * (1.0 - (N_R - 1.0) * dispersionFactor)).r;
    pixel.g = tex.sample(s, baseUV + offset * (1.0 - (N_G - 1.0) * dispersionFactor)).g;
    pixel.b = tex.sample(s, baseUV + offset * (1.0 - (N_B - 1.0) * dispersionFactor)).b;
    return pixel;
}

// Scale factor for refraction gradient (from GLSL: 1.414213562 * 1000.0)
constant float REFRACTION_GRADIENT_SCALE = 1414.21356;

fragment half4 refractionCompositeFragment(
    VertexOut in [[stage_in]],
    texture2d<half, access::sample> blurredTexture [[texture(0)]],
    constant RefractionUniforms& uniforms [[buffer(0)]]
) {
    constexpr sampler textureSampler(
        mag_filter::linear,
        min_filter::linear,
        address::clamp_to_edge
    );

    // Convert UV to centered pixel coordinates (in physical pixels)
    float2 pixelPos = in.texCoord * uniforms.viewSize - uniforms.viewSize * 0.5;
    float2 halfSize = uniforms.viewSize * 0.5 - uniforms.shapePadding;

    // Apply morph scale - divide pixelPos to "stretch" the shape visually
    // When morphScale > 1, coordinates are compressed, making the shape appear larger
    float2 scaledPixelPos = pixelPos / uniforms.morphScale;

    // Calculate SDF (negative = inside shape, in pixels)
    // Use scaledPixelPos so the shape visually stretches with morphScale
    float dist = roundedRectSDF(scaledPixelPos, halfSize, uniforms.cornerRadius);

    half4 color;

    if (dist < 0.0) {
        // Inside shape - apply refraction
        float2 normal = getRoundedRectGradient(scaledPixelPos, halfSize, uniforms.cornerRadius) * REFRACTION_GRADIENT_SCALE;
        float nDist = -dist;  // positive distance inside (in pixels)

        // Snell's law approximation for edge factor
        // refThickness is already in pixels (scaled by contentsScale in Swift)
        float x_R_ratio = clamp(1.0 - nDist / uniforms.refThickness, 0.0, 1.0);
        float thetaI = asin(x_R_ratio * x_R_ratio);
        float sinThetaT = sin(thetaI) / uniforms.refFactor;
        float thetaT = asin(clamp(sinThetaT, -1.0, 1.0));
        float edgeFactor = -tan(thetaT - thetaI);

        // Force zero inside threshold
        if (nDist >= uniforms.refThickness) {
            edgeFactor = 0.0;
        }

        // Calculate Fresnel factor (based on distance from edge)
        // dist is negative inside shape
        // Formula from GLSL: pow(1.0 + (merged * resolution1x.y / 1500.0) * pow(500.0 / fresnelRange, 2.0) + fresnelHardness, 5.0)
        float fresnelRangeScale = pow(500.0 / uniforms.fresnelRange, 2.0);
        float fresnelBase = 1.0 + (dist * uniforms.viewSize.y / 1500.0) * fresnelRangeScale + uniforms.fresnelHardness;
        float fresnel = clamp(pow(fresnelBase, 5.0), 0.0, 1.0);

        // Calculate Glare geometric factor (similar to fresnel but with glare parameters)
        float glareRangeScale = pow(500.0 / uniforms.glareRange, 2.0);
        float glareGeoBase = 1.0 + (dist * uniforms.viewSize.y / 1500.0) * glareRangeScale + uniforms.glareHardness;
        float glareGeoFactor = clamp(pow(glareGeoBase, 5.0), 0.0, 1.0);

        // Get tint color from uniforms
        half4 tintColor = half4(uniforms.tint);

        // Check if we're in the reflection zone
        if (uniforms.useReflection > 0.5 && nDist < uniforms.refThickness) {
            // REFLECTION MODE: True mirror effect
            float halfThickness = uniforms.refThickness * 0.5;

            if (nDist < halfThickness) {
                // ZONE 1: Mirror reflection with curved edge effect
                float2 direction = normalize(normal);

                // Curved mirror progression (simulates rounded glass edge)
                // t: normalized distance from edge (0 at edge, 1 at fold line)
                float t = nDist / halfThickness;
                // Arc curve using sine: faster progression at edge, slower toward fold
                float curvedT = sin(t * PI / 2.0);

                // Apply curved offset (content wraps around like a cylinder edge)
                float pixelOffset = uniforms.refThickness - 2.0 * curvedT * halfThickness;
                float2 mirrorOffset = -direction * pixelOffset / uniforms.viewSize * uniforms.refFactor;

                // Sample with chromatic dispersion
                color = sampleWithDispersion(
                    blurredTexture,
                    textureSampler,
                    in.texCoord,
                    mirrorOffset,
                    uniforms.refDispersion
                );

            } else {
                // ZONE 2: Beyond fold line - show original blurred content (sharp cutoff)
                color = blurredTexture.sample(textureSampler, in.texCoord);
            }

        } else if (uniforms.useReflection < 0.5 && edgeFactor > 0.0) {
            // REFRACTION MODE: Original light bending effect
            float2 uvOffset = -normal * edgeFactor * 0.05 / uniforms.viewSize.y;

            color = sampleWithDispersion(
                blurredTexture,
                textureSampler,
                in.texCoord,
                uvOffset,
                uniforms.refDispersion
            );

        } else {
            // Outside effect zones or no effect
            color = blurredTexture.sample(textureSampler, in.texCoord);
        }

        // Apply tint color (applies to all modes: refraction, reflection, no effect)
        color = mix(color, half4(tintColor.rgb, 1.0h), tintColor.a * 0.8h);

        // Apply Fresnel highlight - mix with white
        color = mix(color, half4(1.0), half(fresnel * uniforms.fresnelFactor * 0.7));

        // Calculate Glare angle factor
        // Based on normal direction and light angle
        float2 normalizedNormal = normalize(normal);
        float glareAngle = (vec2ToAngle(normalizedNormal) - PI / 4.0 + uniforms.glareAngle) * 2.0;

        // Determine if on far side (opposite to light direction)
        int glareFarside = 0;
        if ((glareAngle > PI * (2.0 - 0.5) && glareAngle < PI * (4.0 - 0.5)) ||
            glareAngle < PI * (0.0 - 0.5)) {
            glareFarside = 1;
        }

        // Calculate angle factor with opposite side attenuation
        // GLSL original: (glareFarside == 1 ? 0.8 : 1.2) * u_glareFactor
        // We use glareOppositeFactor to make it configurable (default 0.8/1.2 ≈ 0.667)
        float glareAngleFactor = (0.5 + sin(glareAngle) * 0.5) *
            (glareFarside == 1 ? 1.2 * uniforms.glareOppositeFactor : 1.2) *
            uniforms.glareFactor;
        glareAngleFactor = clamp(pow(glareAngleFactor, 0.3 + uniforms.glareConvergence * 1.5), 0.0, 1.0);

        half4 glareColor = glareFarside == 1 ? half4(uniforms.glareFarsideColor) : half4(uniforms.glareNearsideColor);
        color = mix(color, glareColor, half(glareAngleFactor * glareGeoFactor));
    } else {
        // Outside shape
        color = blurredTexture.sample(textureSampler, in.texCoord);
    }

    // Apply corner radius mask with outer shadow only
    if (uniforms.cornerRadius > 0.0) {
        if (dist < 0.0) {
            // Inside shape - inner shadow already applied in previous pass
            // Keep full alpha

        } else if (dist < SHADOW_RADIUS) {
            // Outer shadow zone (existing logic)
            // Get gradient (direction away from shape edge)
            float2 grad = getRoundedRectGradient(scaledPixelPos, halfSize, uniforms.cornerRadius);

            // Calculate directional factor: how aligned is gradient with shadow direction
            float2 shadowDir = normalize(SHADOW_DIRECTION);
            float dirFactor = dot(grad, shadowDir);
            dirFactor = clamp(pow(max(0.0, dirFactor), SHADOW_DIRECTION_HARDNESS), 0.0, 1.0);

            // Shadow zone - fade from shadow to transparent
            float shadowFactor = 1.0 - smoothstep(0.0, SHADOW_RADIUS * SHADOW_SOFTNESS, dist);
            shadowFactor *= SHADOW_OPACITY * dirFactor;

            if (shadowFactor > 0.001) {
                color.rgb = half3(SHADOW_COLOR);
                color.a = half(shadowFactor);
            } else {
                color.a = 0.0;
            }
        } else {
            // Outside shadow - fully transparent
            color.a = 0.0;
        }
    }

    // Apply overall opacity
    color.a *= half(uniforms.opacity);

    return color;
}
