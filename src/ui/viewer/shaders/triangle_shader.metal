// OhCAD Metal Shaders - Triangle rendering with lighting for shaded mode
// Uses push constants (uniform data) for MVP, color, and lighting parameters
#include <metal_stdlib>
using namespace metal;

// =============================================================================
// Vertex/Fragment Data Structures
// =============================================================================

// Vertex input from vertex buffer
struct TriangleVertexIn {
    float3 position [[attribute(0)]];  // 3D position
    float3 normal   [[attribute(1)]];  // Vertex normal
};

// Output from vertex shader, input to fragment shader
struct TriangleVertexOut {
    float4 position [[position]];  // Clip-space position
    float3 normal;                 // World-space normal
    float3 worldPos;               // World-space position
};

// Uniform data passed via push constants
struct TriangleUniforms {
    float4x4 mvp;          // Model-View-Projection matrix
    float4x4 model;        // Model matrix (for normal transformation)
    float4 baseColor;      // Base material color (RGBA)
    float3 lightDir;       // Directional light direction (world space)
    float ambientStrength; // Ambient light strength (0-1)
};

// =============================================================================
// Vertex Shader
// =============================================================================

vertex TriangleVertexOut triangle_vertex_main(
    TriangleVertexIn in [[stage_in]],
    constant TriangleUniforms& uniforms [[buffer(0)]]
) {
    TriangleVertexOut out;

    // Transform position to clip space
    out.position = uniforms.mvp * float4(in.position, 1.0);

    // Transform normal to world space (using model matrix)
    // Note: For non-uniform scaling, we'd need the inverse transpose
    // But for CAD models with uniform transforms, this works fine
    out.normal = normalize((uniforms.model * float4(in.normal, 0.0)).xyz);

    // Pass world position for fragment shader (if needed for advanced lighting)
    out.worldPos = (uniforms.model * float4(in.position, 1.0)).xyz;

    return out;
}

// =============================================================================
// Fragment Shader - Phong Lighting Model
// =============================================================================

fragment float4 triangle_fragment_main(
    TriangleVertexOut in [[stage_in]],
    constant TriangleUniforms& uniforms [[buffer(0)]]
) {
    // Normalize interpolated normal (can become denormalized during rasterization)
    float3 normal = normalize(in.normal);

    // Ambient lighting
    float3 ambient = uniforms.ambientStrength * uniforms.baseColor.rgb;

    // Diffuse lighting (Lambertian reflectance)
    float3 lightDir = normalize(-uniforms.lightDir);  // Light direction toward surface
    float diffuseStrength = max(dot(normal, lightDir), 0.0);
    float3 diffuse = diffuseStrength * uniforms.baseColor.rgb;

    // Combine ambient + diffuse
    float3 finalColor = ambient + diffuse;

    // Return final color with alpha
    return float4(finalColor, uniforms.baseColor.a);
}
