# SDL3 Rendering Options for OhCAD - Comparison & Recommendation

**Date:** November 9, 2024
**Issue:** OpenGL 2.1 is too old (from 2006), we need modern graphics API
**Goal:** Choose best rendering backend for OhCAD on macOS with SDL3

---

## Problem Statement

The current SDL3 viewer uses **OpenGL 2.1** (via Metal compatibility layer), which is:
- ❌ **Ancient** - Released in 2006, nearly 20 years old
- ❌ **Limited features** - No compute shaders, limited GLSL support
- ❌ **Deprecated** - macOS deprecated OpenGL in 2018
- ❌ **Poor performance** - Compatibility layer overhead

Even **OpenGL 4.1** (macOS maximum) is from 2010 - 15 years old and deprecated.

---

## Available Options with SDL3

### Option 1: SDL3 GPU API ⭐ **RECOMMENDED**

**What is it?**
SDL3's new modern cross-platform GPU abstraction (released in SDL 3.0). It's SDL's answer to replacing OpenGL with modern APIs.

**Backend Support:**
- **macOS/iOS**: Uses **Metal** natively
- **Windows**: Uses **Direct3D 12**
- **Linux/Android**: Uses **Vulkan**

**Advantages:**
- ✅ **Modern** - Uses Metal on macOS (Apple's native 3D API)
- ✅ **Cross-platform** - Single API, multiple backends
- ✅ **High performance** - Direct Metal access, no OpenGL overhead
- ✅ **Future-proof** - SDL's official modern rendering path
- ✅ **Well-documented** - Part of SDL3 core
- ✅ **Actively developed** - SDL team maintains it
- ✅ **Shader support** - Modern shader formats (SPIR-V, Metal SL)

**Disadvantages:**
- ⚠️ **Learning curve** - Different from OpenGL (but similar to Vulkan/Metal)
- ⚠️ **Shader conversion** - Need to convert GLSL shaders to Metal/SPIR-V
- ⚠️ **New API** - Less community resources than OpenGL

**API Overview:**
```odin
import sdl "vendor:sdl3"

// Create GPU device (automatically uses Metal on macOS)
gpu_device := sdl.CreateGPUDevice(
    sdl.GPU_SHADERFORMAT_METALLIB,  // Metal shaders on macOS
    debug_mode = false,
    name = "OhCAD",
)

// Claim window for GPU rendering
sdl.ClaimWindowForGPUDevice(gpu_device, window)

// Create graphics pipeline (vertex + fragment shaders)
pipeline := sdl.CreateGPUGraphicsPipeline(gpu_device, &pipeline_info)

// Render loop
cmd_buffer := sdl.AcquireGPUCommandBuffer(gpu_device)
render_pass := sdl.BeginGPURenderPass(cmd_buffer, &pass_info)
sdl.BindGPUGraphicsPipeline(render_pass, pipeline)
sdl.DrawGPUPrimitives(render_pass, vertex_count, instance_count)
sdl.EndGPURenderPass(render_pass)
sdl.SubmitGPUCommandBuffer(cmd_buffer)
```

**Key Features:**
- Modern pipeline state objects
- Explicit resource management
- Command buffers for efficient rendering
- Compute shader support
- Modern texture formats
- Multiple render targets
- Built-in MSAA support

---

### Option 2: Direct Metal via SDL3

**What is it?**
Use SDL3's Metal bindings to access Metal directly, bypassing OpenGL entirely.

**Advantages:**
- ✅ **Native macOS** - Direct Metal access, zero overhead
- ✅ **Maximum performance** - No abstraction layer
- ✅ **Full Metal features** - Access to all Metal capabilities
- ✅ **Apple optimized** - Best performance on macOS

**Disadvantages:**
- ❌ **macOS only** - Not cross-platform
- ❌ **Complex** - Must manage Metal manually
- ❌ **More code** - No abstraction layer to simplify things
- ❌ **Odin bindings limited** - SDL3 Metal bindings are minimal:
  ```odin
  Metal_CreateView  :: proc(window: ^Window) -> MetalView
  Metal_DestroyView :: proc(view: MetalView)
  Metal_GetLayer    :: proc(view: MetalView) -> rawptr
  ```

**Use Case:**
Only recommended if you need maximum performance on macOS and don't care about cross-platform support. For a CAD application that should work on Windows/Linux, this is not ideal.

---

### Option 3: OpenGL 4.1 (Fix Context Creation)

**What is it?**
Fix the OpenGL 4.1 context creation issue with SDL3 on macOS.

**Advantages:**
- ✅ **Familiar** - We already have OpenGL shaders
- ✅ **Mature** - Lots of resources and examples
- ✅ **Cross-platform** - Works on macOS, Windows, Linux

**Disadvantages:**
- ❌ **Deprecated on macOS** - Apple deprecated OpenGL in 2018
- ❌ **Old** - OpenGL 4.1 from 2010 (15 years old)
- ❌ **Slower** - OpenGL on macOS runs through Metal translation layer
- ❌ **No future** - Apple won't update OpenGL, stuck at 4.1 forever
- ❌ **Context creation issues** - SDL3 having problems creating 4.1 core context

**Current Issue:**
SDL3 on macOS fails to create OpenGL 4.1 Core profile context, even though it should work. This might be fixable, but it's fighting against deprecated technology.

---

### Option 4: SDL3 Renderer (2D/3D)

**What is it?**
SDL's higher-level 2D/3D renderer that can use various backends.

**Advantages:**
- ✅ **Easy to use** - Higher-level API
- ✅ **Cross-platform** - Works everywhere
- ✅ **Multiple backends** - Can use Metal, Vulkan, D3D, or OpenGL

**Disadvantages:**
- ❌ **Limited 3D support** - Primarily designed for 2D
- ❌ **Less control** - Higher-level means less customization
- ❌ **May be insufficient for CAD** - Complex 3D rendering might be limited

**Verdict:**
Not ideal for a 3D CAD application with custom shaders and advanced rendering.

---

## Comparison Table

| Feature | SDL3 GPU API | Direct Metal | OpenGL 4.1 | SDL Renderer |
|---------|-------------|--------------|------------|--------------|
| **Modern** | ✅ Yes (Metal) | ✅ Yes | ❌ No (deprecated) | ⚠️ Depends |
| **Cross-platform** | ✅ Yes | ❌ macOS only | ✅ Yes | ✅ Yes |
| **Performance** | ✅ Excellent | ✅ Maximum | ⚠️ Good (overhead) | ⚠️ Good |
| **Future-proof** | ✅ Yes | ✅ Yes (macOS) | ❌ No | ⚠️ Limited |
| **Learning curve** | ⚠️ Medium | ❌ High | ✅ Low | ✅ Low |
| **3D CAD support** | ✅ Excellent | ✅ Excellent | ✅ Good | ❌ Limited |
| **Shader support** | ✅ Modern | ✅ Metal SL | ✅ GLSL | ⚠️ Limited |
| **Community** | ⚠️ Growing | ⚠️ macOS only | ✅ Large | ✅ Large |
| **Maintenance** | ✅ Active | ✅ Apple | ❌ Frozen | ✅ Active |

---

## Recommendation: SDL3 GPU API

### Why SDL3 GPU API is Best for OhCAD

1. **Future-Proof**
   - Uses Metal on macOS (Apple's modern API)
   - Automatically uses Vulkan on Linux, D3D12 on Windows
   - SDL team actively developing and supporting it

2. **Cross-Platform**
   - Single codebase works on macOS, Windows, Linux
   - Automatic backend selection per platform
   - No platform-specific code needed

3. **Modern & Performant**
   - Native Metal on macOS (no OpenGL translation layer)
   - Direct access to GPU features
   - Efficient command buffer model

4. **CAD-Appropriate**
   - Full control over rendering pipeline
   - Modern shader support
   - Compute shaders for future features
   - Multiple render targets for advanced rendering

5. **SDL Integration**
   - Part of SDL3 core, not a separate library
   - Works seamlessly with SDL3 windows and events
   - Well-integrated with multi-touch and input

---

## Migration Strategy

### Phase 1: SDL3 GPU Basics (1-2 days)
- [ ] Create GPU device with Metal backend
- [ ] Claim window for GPU rendering
- [ ] Set up basic render pass
- [ ] Clear screen with solid color
- [ ] Test window resize and events

### Phase 2: Shader Conversion (2-3 days)
- [ ] Convert GLSL vertex shader to Metal Shading Language
- [ ] Convert GLSL fragment shader to Metal Shading Language
- [ ] Compile Metal shaders to .metallib format
- [ ] Load shaders in SDL3 GPU
- [ ] Create graphics pipeline with shaders

### Phase 3: Geometry Rendering (2-3 days)
- [ ] Create GPU buffers for vertices
- [ ] Upload wireframe mesh data
- [ ] Implement basic line rendering
- [ ] Add MVP matrix uniforms
- [ ] Render coordinate axes

### Phase 4: Advanced Features (3-4 days)
- [ ] Implement text rendering (fontstash integration)
- [ ] Add thick line rendering (quads)
- [ ] Multi-pass rendering (3D + overlay)
- [ ] Depth testing and blending
- [ ] Complete sketch + solid rendering

### Phase 5: Polish & Optimization (1-2 days)
- [ ] Profile performance vs OpenGL
- [ ] Optimize buffer usage
- [ ] Add MSAA if needed
- [ ] Test on different macOS versions
- [ ] Document GPU rendering pipeline

**Total Estimate: 1-2 weeks** (faster if we have Metal shader experience)

---

## Code Example: Minimal SDL3 GPU Setup

```odin
import sdl "vendor:sdl3"
import "core:fmt"

main :: proc() {
    // Initialize SDL3
    sdl.Init({.VIDEO})
    defer sdl.Quit()

    // Create window
    window := sdl.CreateWindow("OhCAD GPU", 1280, 720, {.RESIZABLE})
    defer sdl.DestroyWindow(window)

    // Create GPU device (Metal on macOS)
    gpu := sdl.CreateGPUDevice(
        sdl.GPU_SHADERFORMAT_METALLIB,  // Metal shaders
        debug_mode = false,
        name = "OhCAD",
    )
    defer sdl.DestroyGPUDevice(gpu)

    // Claim window for GPU
    sdl.ClaimWindowForGPUDevice(gpu, window)

    // Main loop
    running := true
    event: sdl.Event

    for running {
        // Events
        for sdl.PollEvent(&event) {
            if event.type == .QUIT do running = false
        }

        // Render
        cmd_buffer := sdl.AcquireGPUCommandBuffer(gpu)

        swapchain_texture := sdl.AcquireGPUSwapchainTexture(cmd_buffer, window)
        if swapchain_texture != nil {
            // Begin render pass
            color_target := sdl.GPUColorTargetInfo{
                texture = swapchain_texture,
                load_op = .CLEAR,
                store_op = .STORE,
                clear_color = {0.08, 0.08, 0.08, 1.0},  // Dark background
            }

            pass := sdl.BeginGPURenderPass(cmd_buffer, &color_target, 1, nil)

            // TODO: Draw geometry here

            sdl.EndGPURenderPass(pass)
        }

        sdl.SubmitGPUCommandBuffer(cmd_buffer)
    }
}
```

---

## Shader Conversion Notes

### GLSL to Metal Shading Language

**Vertex Shader Example:**

GLSL (OpenGL):
```glsl
#version 330 core

layout(location = 0) in vec3 aPos;

uniform mat4 uMVP;

void main() {
    gl_Position = uMVP * vec4(aPos, 1.0);
}
```

Metal Shading Language:
```metal
#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
};

struct VertexOut {
    float4 position [[position]];
};

struct Uniforms {
    float4x4 mvp;
};

vertex VertexOut vertex_main(
    VertexIn in [[stage_in]],
    constant Uniforms& uniforms [[buffer(1)]]
) {
    VertexOut out;
    out.position = uniforms.mvp * float4(in.position, 1.0);
    return out;
}
```

**Differences:**
- Metal uses `struct` for vertex attributes
- Uniforms passed as buffer bindings
- `[[attribute(n)]]`, `[[position]]`, `[[buffer(n)]]` for semantics
- Column-major matrices (same as OpenGL)

---

## Resources

### SDL3 GPU Documentation
- **SDL3 GPU Header**: `/Users/varomix/dev/ODIN_DEV/Odin/vendor/sdl3/include/SDL_gpu.h`
- **Odin Bindings**: `/Users/varomix/dev/ODIN_DEV/Odin/vendor/sdl3/sdl3_gpu.odin`
- **SDL3 Wiki**: https://wiki.libsdl.org/SDL3/CategoryGPU

### Metal Resources
- **Metal Shading Language Spec**: https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf
- **Metal Best Practices**: https://developer.apple.com/documentation/metal/
- **GLSL to Metal Guide**: Search "GLSL to Metal conversion"

### Example Projects
- Search GitHub for "SDL3 GPU" examples
- Look for SDL3 test programs with GPU rendering

---

## Decision Matrix

### For OhCAD specifically:

**Requirements:**
- ✅ Must support macOS (primary development platform)
- ✅ Should support Windows/Linux (future)
- ✅ Need modern graphics features
- ✅ Want good performance
- ✅ Need to render wireframes, lines, text
- ✅ Multi-touch already using SDL3

**Best Match: SDL3 GPU API**
- Uses Metal on macOS (✅ modern, ✅ performant)
- Cross-platform ready (✅ future Windows/Linux)
- Integrates with existing SDL3 multi-touch code (✅ synergy)
- Modern API design (✅ future-proof)
- SDL team support (✅ actively maintained)

---

## Conclusion

**Recommendation: Migrate to SDL3 GPU API**

The SDL3 GPU API is the best choice for OhCAD because:
1. **Modern**: Uses Metal on macOS (Apple's native 3D API)
2. **Cross-platform**: Single API for macOS/Windows/Linux
3. **Future-proof**: Active development, not deprecated
4. **Performant**: Direct Metal access, no OpenGL overhead
5. **Integrated**: Works seamlessly with SDL3 events and multi-touch

While there's a learning curve (new API, shader conversion), it's the right long-term investment for a modern CAD application. The alternative (OpenGL) is deprecated and will only get slower and more problematic on macOS.

**Next Step:** Create SDL3 GPU minimal renderer and test basic triangle rendering with Metal backend.
