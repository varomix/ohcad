// OhCAD Metal Shaders - Triangle rendering with UNIFORM lighting for CAD viewing
// Simple, flat lighting optimized for technical visualization
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
    out.normal = normalize((uniforms.model * float4(in.normal, 0.0)).xyz);

    // Pass world position for fragment shader
    out.worldPos = (uniforms.model * float4(in.position, 1.0)).xyz;

    return out;
}

// =============================================================================
// Fragment Shader - UNIFORM LIGHTING for CAD (very simple, everything visible)
// =============================================================================

fragment float4 triangle_fragment_main(
    TriangleVertexOut in [[stage_in]],
    constant TriangleUniforms& uniforms [[buffer(0)]]
) {
    // Normalize interpolated normal
    float3 normal = normalize(in.normal);

    // CAD LIGHTING: 50% ambient + 50% directional = good contrast while keeping shadows visible
    // This provides clear edge definition without harsh shadows

    float3 ambient = 0.50 * uniforms.baseColor.rgb;  // 50% base lighting

    // Directional component for contrast and depth perception
    float3 lightDir = normalize(-uniforms.lightDir);
    float diffuseStrength = max(dot(normal, lightDir), 0.0);
    float3 diffuse = diffuseStrength * uniforms.baseColor.rgb * 0.50;  // 50% directional

    // Combine (heavily weighted toward ambient for uniform appearance)
    float3 finalColor = ambient + diffuse;

    // Return final color with alpha
    return float4(finalColor, uniforms.baseColor.a);
}
