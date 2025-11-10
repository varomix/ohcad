// OhCAD Metal Shaders - SIMPLE TEST VERSION (hard-coded color)
// Testing to verify triangle geometry renders correctly
#include <metal_stdlib>
using namespace metal;

// Vertex input from vertex buffer
struct VertexIn {
    float3 position [[attribute(0)]];
};

// Output from vertex shader, input to fragment shader
struct VertexOut {
    float4 position [[position]];
};

// Vertex Shader - Just pass through position
vertex VertexOut vertex_main(VertexIn in [[stage_in]]) {
    VertexOut out;
    out.position = float4(in.position, 1.0);  // No MVP transform for now
    return out;
}

// Fragment Shader - Hard-coded cyan color
fragment float4 fragment_main(VertexOut in [[stage_in]]) {
    return float4(0.0, 1.0, 1.0, 1.0);  // Cyan color hard-coded
}
