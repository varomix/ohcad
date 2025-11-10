// OhCAD Metal Shaders - Line rendering for wireframes and axes
// Uses push constants (uniform data) for MVP and color
#include <metal_stdlib>
using namespace metal;

// =============================================================================
// Vertex/Fragment Data Structures
// =============================================================================

// Vertex input from vertex buffer
struct VertexIn {
    float3 position [[attribute(0)]];  // 3D position
};

// Output from vertex shader, input to fragment shader
struct VertexOut {
    float4 position [[position]];  // Clip-space position
};

// Uniform data passed via push constants
struct Uniforms {
    float4x4 mvp;     // Model-View-Projection matrix
    float4 color;     // Line/shape color (RGBA)
};

// =============================================================================
// Vertex Shader
// =============================================================================

vertex VertexOut vertex_main(
    VertexIn in [[stage_in]],
    constant Uniforms& uniforms [[buffer(0)]]  // Push constants at buffer 0
) {
    VertexOut out;
    out.position = uniforms.mvp * float4(in.position, 1.0);
    return out;
}

// =============================================================================
// Fragment Shader
// =============================================================================

fragment float4 fragment_main(
    VertexOut in [[stage_in]],
    constant Uniforms& uniforms [[buffer(0)]]  // Push constants at buffer 0
) {
    return uniforms.color;
}

// =============================================================================
// Text Rendering Structures
// =============================================================================

// Vertex input for text rendering (screen-space 2D)
struct TextVertexIn {
    float2 position [[attribute(0)]];  // Screen position in pixels
    float2 texCoord [[attribute(1)]];  // Texture coordinates
    uchar4 color    [[attribute(2)]];  // RGBA color (0-255)
};

// Output from text vertex shader
struct TextVertexOut {
    float4 position [[position]];  // Clip-space position
    float2 texCoord;
    float4 color;
};

// Uniform data for text rendering
struct TextUniforms {
    float2 screenSize;  // Window size in pixels (width, height)
};

// =============================================================================
// Text Vertex Shader
// =============================================================================

vertex TextVertexOut text_vertex_main(
    TextVertexIn in [[stage_in]],
    constant TextUniforms& uniforms [[buffer(0)]]
) {
    TextVertexOut out;

    // Convert from pixel coordinates to NDC [-1, 1]
    float2 ndc = (in.position / uniforms.screenSize) * 2.0 - 1.0;
    ndc.y = -ndc.y;  // Flip Y (screen coordinates are top-down)

    out.position = float4(ndc, 0.0, 1.0);
    out.texCoord = in.texCoord;

    // Convert uchar4 color to normalized float4
    out.color = float4(in.color) / 255.0;

    return out;
}

// =============================================================================
// Text Fragment Shader
// =============================================================================

fragment float4 text_fragment_main(
    TextVertexOut in [[stage_in]],
    texture2d<float> fontTexture [[texture(0)]],
    sampler textureSampler [[sampler(0)]]
) {
    // Sample from font atlas (single channel R8)
    float alpha = fontTexture.sample(textureSampler, in.texCoord).r;

    // Return color with alpha from texture
    return float4(in.color.rgb, in.color.a * alpha);
}
