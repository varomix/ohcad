// ui/viewer - SDL3 GPU Viewer with Metal backend (Phase 3)
// Combines SDL3 GPU rendering + camera system + multi-touch gestures
package ohcad_viewer

import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import "core:image/png"
import doc "../../core/document"
import m "../../core/math"
import t "../../core/topology"
import sketch "../../features/sketch"
import extrude "../../features/extrude"
import sdl "vendor:sdl3"
import glsl "core:math/linalg/glsl"
import fs "vendor:fontstash"

// =============================================================================
// Pre-allocated GPU resources for inline rendering (reusable buffers)
// =============================================================================

InlineRenderResources :: struct {
    rect_vertex_buffer: ^sdl.GPUBuffer,     // 6 vertices for a quad (2 triangles)
    rect_transfer_buffer: ^sdl.GPUTransferBuffer,
}

// =============================================================================
// Viewer Configuration
// =============================================================================

// Render mode for 3D solids
RenderMode :: enum {
    Wireframe,  // Lines only (edges)
    Shaded,     // Solid triangles with lighting
    Both,       // Wireframe + shaded combined
}

ViewerGPUConfig :: struct {
    window_width: i32,
    window_height: i32,
    window_title: cstring,
    shader_path: string,
}

DEFAULT_GPU_CONFIG :: ViewerGPUConfig{
    window_width = 1280,
    window_height = 720,
    window_title = "OhCAD - SDL3 GPU",
    shader_path = "src/ui/viewer/shaders/line_shader.metallib",  // Relative to project root
}

// =============================================================================
// SDL3 GPU Viewer State
// =============================================================================

ViewerGPU :: struct {
    // SDL3 window and GPU device
    window: ^sdl.Window,
    gpu_device: ^sdl.GPUDevice,

    // Graphics pipelines
    vertex_shader: ^sdl.GPUShader,
    fragment_shader: ^sdl.GPUShader,
    pipeline: ^sdl.GPUGraphicsPipeline,       // For line rendering
    triangle_pipeline: ^sdl.GPUGraphicsPipeline,  // For thick line rendering (quads) - no depth test for UI
    wireframe_pipeline: ^sdl.GPUGraphicsPipeline,  // For wireframe overlay - with depth testing

    // Shaded rendering pipeline (with lighting)
    triangle_vertex_shader: ^sdl.GPUShader,
    triangle_fragment_shader: ^sdl.GPUShader,
    shaded_pipeline: ^sdl.GPUGraphicsPipeline,  // For shaded triangle rendering with lighting

    // Vertex buffers
    axes_vertex_buffer: ^sdl.GPUBuffer,
    axes_vertex_count: u32,
    grid_vertex_buffer: ^sdl.GPUBuffer,
    grid_vertex_count: u32,

    // Camera system
    camera: Camera,

    // Input state
    mouse_x: f64,
    mouse_y: f64,
    mouse_left_down: bool,
    mouse_middle_down: bool,
    mouse_right_down: bool,
    shift_held: bool,

    // Multi-touch gesture state (trackpad)
    active_fingers: map[sdl.FingerID]TouchPoint,
    prev_centroid: Maybe([2]f32),
    prev_distance: f32,
    is_pinching: bool,  // Track if we're currently in a pinch gesture

    // Rendering state
    should_close: bool,
    window_width: u32,
    window_height: u32,
    render_mode: RenderMode,  // Current rendering mode (wireframe/shaded/both)
}

// Touch point for multi-touch tracking
TouchPoint :: struct {
    x: f32,
    y: f32,
}

// Uniform buffer structure (matches Metal shader)
Uniforms :: struct {
    mvp: matrix[4,4]f32,
    color: [4]f32,
}

// Vertex structure for line rendering
LineVertex :: struct {
    position: [3]f32,
}

// =============================================================================
// Wireframe Mesh (GPU version with f32 vertices)
// =============================================================================

// Wireframe mesh data for SDL3 GPU rendering
WireframeMeshGPU :: struct {
    edges: [dynamic][2][3]f32,  // List of edges (pairs of vertices)
}

// Create empty GPU wireframe mesh
wireframe_mesh_gpu_init :: proc() -> WireframeMeshGPU {
    return WireframeMeshGPU{
        edges = make([dynamic][2][3]f32),
    }
}

// Destroy GPU wireframe mesh
wireframe_mesh_gpu_destroy :: proc(mesh: ^WireframeMeshGPU) {
    delete(mesh.edges)
}

// Clear all edges from GPU wireframe mesh
wireframe_mesh_gpu_clear :: proc(mesh: ^WireframeMeshGPU) {
    clear(&mesh.edges)
}

// Add edge to GPU wireframe mesh (f32 version)
wireframe_mesh_gpu_add_edge :: proc(mesh: ^WireframeMeshGPU, v0, v1: [3]f32) {
    append(&mesh.edges, [2][3]f32{v0, v1})
}

// Add edge to GPU wireframe mesh (f64 version for compatibility)
wireframe_mesh_gpu_add_edge_f64 :: proc(mesh: ^WireframeMeshGPU, v0, v1: m.Vec3) {
    v0_f32 := [3]f32{f32(v0.x), f32(v0.y), f32(v0.z)}
    v1_f32 := [3]f32{f32(v1.x), f32(v1.y), f32(v1.z)}
    append(&mesh.edges, [2][3]f32{v0_f32, v1_f32})
}

// =============================================================================
// Triangle Mesh (GPU version for shaded rendering)
// =============================================================================

// Triangle vertex structure (position + normal for lighting)
TriangleVertex :: struct {
    position: [3]f32,
    normal: [3]f32,
}

// Triangle mesh data for SDL3 GPU rendering (with lighting)
TriangleMeshGPU :: struct {
    vertices: [dynamic]TriangleVertex,  // Triangle vertices with normals
}

// Create empty GPU triangle mesh
triangle_mesh_gpu_init :: proc() -> TriangleMeshGPU {
    return TriangleMeshGPU{
        vertices = make([dynamic]TriangleVertex),
    }
}

// Destroy GPU triangle mesh
triangle_mesh_gpu_destroy :: proc(mesh: ^TriangleMeshGPU) {
    delete(mesh.vertices)
}

// Clear all triangles from GPU triangle mesh
triangle_mesh_gpu_clear :: proc(mesh: ^TriangleMeshGPU) {
    clear(&mesh.vertices)
}

// Add triangle to GPU mesh (f64 version for compatibility)
triangle_mesh_gpu_add_triangle :: proc(mesh: ^TriangleMeshGPU, v0, v1, v2, normal: m.Vec3) {
    v0_f32 := [3]f32{f32(v0.x), f32(v0.y), f32(v0.z)}
    v1_f32 := [3]f32{f32(v1.x), f32(v1.y), f32(v1.z)}
    v2_f32 := [3]f32{f32(v2.x), f32(v2.y), f32(v2.z)}
    normal_f32 := [3]f32{f32(normal.x), f32(normal.y), f32(normal.z)}

    append(&mesh.vertices, TriangleVertex{v0_f32, normal_f32})
    append(&mesh.vertices, TriangleVertex{v1_f32, normal_f32})
    append(&mesh.vertices, TriangleVertex{v2_f32, normal_f32})
}

// Convert SimpleSolid to triangle mesh for shaded rendering (GPU version)
solid_to_triangle_mesh_gpu :: proc(solid: ^extrude.SimpleSolid) -> TriangleMeshGPU {
    mesh := triangle_mesh_gpu_init()

    if solid == nil {
        return mesh
    }

    // Add all triangles from solid
    for tri in solid.triangles {
        triangle_mesh_gpu_add_triangle(&mesh, tri.v0, tri.v1, tri.v2, tri.normal)
    }

    return mesh
}

// Create wireframe for a single sketch entity by index
sketch_entity_to_wireframe_gpu :: proc(sk: ^sketch.Sketch2D, entity_index: int) -> WireframeMeshGPU {
    mesh := wireframe_mesh_gpu_init()

    if entity_index < 0 || entity_index >= len(sk.entities) {
        return mesh
    }

    entity := sk.entities[entity_index]

    switch e in entity {
    case sketch.SketchLine:
        start := sketch.sketch_get_point(sk, e.start_id)
        end := sketch.sketch_get_point(sk, e.end_id)

        if start != nil && end != nil {
            start_2d := m.Vec2{start.x, start.y}
            end_2d := m.Vec2{end.x, end.y}

            start_3d := sketch.sketch_to_world(&sk.plane, start_2d)
            end_3d := sketch.sketch_to_world(&sk.plane, end_2d)

            wireframe_mesh_gpu_add_edge_f64(&mesh, start_3d, end_3d)
        }

    case sketch.SketchCircle:
        center_pt := sketch.sketch_get_point(sk, e.center_id)
        if center_pt != nil {
            segments := 64
            for i in 0..<segments {
                angle0 := f64(i) * (2.0 * math.PI) / f64(segments)
                angle1 := f64((i + 1) % segments) * (2.0 * math.PI) / f64(segments)

                p0_2d := m.Vec2{
                    center_pt.x + e.radius * math.cos(angle0),
                    center_pt.y + e.radius * math.sin(angle0),
                }
                p1_2d := m.Vec2{
                    center_pt.x + e.radius * math.cos(angle1),
                    center_pt.y + e.radius * math.sin(angle1),
                }

                p0_3d := sketch.sketch_to_world(&sk.plane, p0_2d)
                p1_3d := sketch.sketch_to_world(&sk.plane, p1_2d)

                wireframe_mesh_gpu_add_edge_f64(&mesh, p0_3d, p1_3d)
            }
        }

    case sketch.SketchArc:
        // TODO: Arc rendering
    }

    return mesh
}

// =============================================================================
// BRep to Wireframe Conversion
// =============================================================================

// Extract wireframe mesh from B-rep topology (GPU version)
brep_to_wireframe_gpu :: proc(brep: ^t.BRep) -> WireframeMeshGPU {
    mesh := wireframe_mesh_gpu_init()

    // Iterate through all edges in the B-rep
    for i in 0..<len(brep.edges) {
        edge := brep.edges[i]

        // Skip invalid edges (deleted or uninitialized)
        if edge.v0 == t.INVALID_HANDLE || edge.v1 == t.INVALID_HANDLE {
            continue
        }

        // Check if vertices are valid
        if int(edge.v0) >= len(brep.vertices) || int(edge.v1) >= len(brep.vertices) {
            continue
        }

        v0 := brep.vertices[edge.v0]
        v1 := brep.vertices[edge.v1]

        // Skip if vertices are not valid
        if !v0.valid || !v1.valid {
            continue
        }

        // Add edge to wireframe mesh (converts f64 to f32 automatically)
        wireframe_mesh_gpu_add_edge_f64(&mesh, v0.position, v1.position)
    }

    return mesh
}

// =============================================================================
// Text Rendering (SDL3 GPU + fontstash)
// =============================================================================

// Text vertex structure (matches Metal shader TextVertexIn)
TextVertex :: struct {
    position: [2]f32,    // Screen position in pixels
    texCoord: [2]f32,    // Texture coordinates
    color: [4]u8,         // RGBA color (0-255)
}

// Text uniforms structure (matches Metal shader TextUniforms)
TextUniforms :: struct {
    screenSize: [2]f32,  // Window size in pixels
}

// Text renderer for SDL3 GPU
TextRendererGPU :: struct {
    font_context: fs.FontContext,
    font_id: int,

    // SDL3 GPU resources
    gpu_device: ^sdl.GPUDevice,
    text_vertex_shader: ^sdl.GPUShader,
    text_fragment_shader: ^sdl.GPUShader,
    text_pipeline: ^sdl.GPUGraphicsPipeline,

    // Font atlas texture
    font_texture: ^sdl.GPUTexture,
    font_sampler: ^sdl.GPUSampler,

    // Texture size
    texture_width: int,
    texture_height: int,

    // Track if texture has been uploaded
    texture_uploaded: bool,
}

// Initialize text renderer for SDL3 GPU
text_renderer_gpu_init :: proc(gpu_device: ^sdl.GPUDevice, window: ^sdl.Window, shader_data: []byte) -> (TextRendererGPU, bool) {
    renderer: TextRendererGPU
    renderer.gpu_device = gpu_device

    // Initialize fontstash context (1024x1024 texture atlas for plenty of space)
    // Larger atlas prevents reorganization which would corrupt existing text
    renderer.texture_width = 1024
    renderer.texture_height = 1024
    fs.Init(&renderer.font_context, renderer.texture_width, renderer.texture_height, .TOPLEFT)

    // Load custom BigShoulders font from assets
    font_path := "assets/gui/fonts/BigShoulders_24pt-Regular.ttf"
    // font_path := "assets/gui/fonts/Mohave-Regular.ttf"
    font_id := fs.AddFontPath(&renderer.font_context, "bigshoulders", font_path)

    if font_id == fs.INVALID {
        fmt.eprintln("❌ Failed to load BigShoulders font from:", font_path)
        fs.Destroy(&renderer.font_context)
        return renderer, false
    }

    renderer.font_id = font_id
    fmt.printf("✓ Loaded custom font: %s\n", font_path)

    // CRITICAL FIX: Reset font atlas to clear any stale packing data
    // This ensures UV coordinates match where glyphs are actually rasterized
    fs.ResetAtlas(&renderer.font_context, renderer.texture_width, renderer.texture_height)
    fmt.println("✓ Font atlas reset (cleared stale packing data)")

    // Create text vertex shader
    text_vertex_shader_info := sdl.GPUShaderCreateInfo{
        code = raw_data(shader_data),
        code_size = len(shader_data),
        entrypoint = "text_vertex_main",
        format = {.METALLIB},
        stage = .VERTEX,
        num_uniform_buffers = 1,
    }

    text_vertex_shader := sdl.CreateGPUShader(gpu_device, text_vertex_shader_info)
    if text_vertex_shader == nil {
        fmt.eprintln("ERROR: Failed to create text vertex shader:", sdl.GetError())
        fs.Destroy(&renderer.font_context)
        return renderer, false
    }

    renderer.text_vertex_shader = text_vertex_shader

    // Create text fragment shader
    text_fragment_shader_info := sdl.GPUShaderCreateInfo{
        code = raw_data(shader_data),
        code_size = len(shader_data),
        entrypoint = "text_fragment_main",
        format = {.METALLIB},
        stage = .FRAGMENT,
        num_uniform_buffers = 0,
        num_samplers = 1,
        num_storage_textures = 0,
        num_storage_buffers = 0,
    }

    text_fragment_shader := sdl.CreateGPUShader(gpu_device, text_fragment_shader_info)
    if text_fragment_shader == nil {
        fmt.eprintln("ERROR: Failed to create text fragment shader:", sdl.GetError())
        sdl.ReleaseGPUShader(gpu_device, text_vertex_shader)
        fs.Destroy(&renderer.font_context)
        return renderer, false
    }

    renderer.text_fragment_shader = text_fragment_shader

    // Create font atlas texture (R8 format for single-channel grayscale)
    // REVERT to original working format
    texture_info := sdl.GPUTextureCreateInfo{
        type = .D2,
        format = .R8_UNORM,  // Single channel for alpha (original working format)
        usage = {.SAMPLER},
        width = u32(renderer.texture_width),
        height = u32(renderer.texture_height),
        layer_count_or_depth = 1,
        num_levels = 1,
    }

    font_texture := sdl.CreateGPUTexture(gpu_device, texture_info)
    if font_texture == nil {
        fmt.eprintln("ERROR: Failed to create font texture:", sdl.GetError())
        sdl.ReleaseGPUShader(gpu_device, text_fragment_shader)
        sdl.ReleaseGPUShader(gpu_device, text_vertex_shader)
        fs.Destroy(&renderer.font_context)
        return renderer, false
    }

    renderer.font_texture = font_texture

    // Create sampler for font texture
    sampler_info := sdl.GPUSamplerCreateInfo{
        min_filter = .LINEAR,
        mag_filter = .LINEAR,
        mipmap_mode = .LINEAR,
        address_mode_u = .CLAMP_TO_EDGE,
        address_mode_v = .CLAMP_TO_EDGE,
        address_mode_w = .CLAMP_TO_EDGE,
    }

    font_sampler := sdl.CreateGPUSampler(gpu_device, sampler_info)
    if font_sampler == nil {
        fmt.eprintln("ERROR: Failed to create font sampler:", sdl.GetError())
        sdl.ReleaseGPUTexture(gpu_device, font_texture)
        sdl.ReleaseGPUShader(gpu_device, text_fragment_shader)
        sdl.ReleaseGPUShader(gpu_device, text_vertex_shader)
        fs.Destroy(&renderer.font_context)
        return renderer, false
    }

    renderer.font_sampler = font_sampler

    // NOTE: Don't upload texture during init - fontstash hasn't rasterized any glyphs yet!
    // The texture will be uploaded on first text render after glyphs are generated
    renderer.texture_uploaded = false
    fmt.println("✓ Font texture will be uploaded on first text render")

    // Create text rendering pipeline
    vertex_attributes := []sdl.GPUVertexAttribute{
        {location = 0, format = .FLOAT2, offset = 0},  // position
        {location = 1, format = .FLOAT2, offset = 8},  // texCoord
        {location = 2, format = .UBYTE4, offset = 16},  // color (unnormalized - we divide by 255 in shader)
    }

    vertex_binding := sdl.GPUVertexBufferDescription{
        slot = 0,
        pitch = size_of(TextVertex),
        input_rate = .VERTEX,
    }

    vertex_input_state := sdl.GPUVertexInputState{
        vertex_buffer_descriptions = &vertex_binding,
        num_vertex_buffers = 1,
        vertex_attributes = raw_data(vertex_attributes),
        num_vertex_attributes = u32(len(vertex_attributes)),
    }

    color_target := sdl.GPUColorTargetDescription{
        format = sdl.GetGPUSwapchainTextureFormat(gpu_device, window),
        blend_state = {
            enable_blend = true,
            alpha_blend_op = .ADD,
            color_blend_op = .ADD,
            src_color_blendfactor = .SRC_ALPHA,
            dst_color_blendfactor = .ONE_MINUS_SRC_ALPHA,
            src_alpha_blendfactor = .ONE,
            dst_alpha_blendfactor = .ONE_MINUS_SRC_ALPHA,
        },
    }

    text_pipeline_info := sdl.GPUGraphicsPipelineCreateInfo{
        vertex_shader = text_vertex_shader,
        fragment_shader = text_fragment_shader,
        vertex_input_state = vertex_input_state,
        primitive_type = .TRIANGLELIST,
        rasterizer_state = {
            fill_mode = .FILL,
            cull_mode = .NONE,
            front_face = .COUNTER_CLOCKWISE,
        },
        depth_stencil_state = {
            // Disable depth testing for UI - always render on top
            enable_depth_test = false,
            enable_depth_write = false,
            enable_stencil_test = false,
        },
        target_info = {
            num_color_targets = 1,
            color_target_descriptions = &color_target,
            has_depth_stencil_target = true,  // Match render pass
            depth_stencil_format = .D16_UNORM,
        },
    }

    text_pipeline := sdl.CreateGPUGraphicsPipeline(gpu_device, text_pipeline_info)
    if text_pipeline == nil {
        fmt.eprintln("ERROR: Failed to create text pipeline:", sdl.GetError())
        sdl.ReleaseGPUSampler(gpu_device, font_sampler)
        sdl.ReleaseGPUTexture(gpu_device, font_texture)
        sdl.ReleaseGPUShader(gpu_device, text_fragment_shader)
        sdl.ReleaseGPUShader(gpu_device, text_vertex_shader)
        fs.Destroy(&renderer.font_context)
        return renderer, false
    }

    renderer.text_pipeline = text_pipeline

    // Pre-warm the font atlas with common characters
    // This prevents glyphs from missing on first render
    fs.SetFont(&renderer.font_context, font_id)
    fs.SetSize(&renderer.font_context, 28.0)

    // Pre-render common ASCII characters to populate atlas
    prewarm_text := " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"
    iter := fs.TextIterInit(&renderer.font_context, 0, 0, prewarm_text)
    quad: fs.Quad
    for fs.TextIterNext(&renderer.font_context, &iter, &quad) {
        // Just iterate to force glyph rasterization
    }

    fmt.println("✓ Font atlas pre-warmed with common characters")
    fmt.println("✓ Text renderer initialized successfully")
    return renderer, true
}

// Destroy text renderer
text_renderer_gpu_destroy :: proc(renderer: ^TextRendererGPU) {
    fs.Destroy(&renderer.font_context)

    if renderer.text_pipeline != nil {
        sdl.ReleaseGPUGraphicsPipeline(renderer.gpu_device, renderer.text_pipeline)
    }

    if renderer.font_sampler != nil {
        sdl.ReleaseGPUSampler(renderer.gpu_device, renderer.font_sampler)
    }

    if renderer.font_texture != nil {
        sdl.ReleaseGPUTexture(renderer.gpu_device, renderer.font_texture)
    }

    if renderer.text_fragment_shader != nil {
        sdl.ReleaseGPUShader(renderer.gpu_device, renderer.text_fragment_shader)
    }

    if renderer.text_vertex_shader != nil {
        sdl.ReleaseGPUShader(renderer.gpu_device, renderer.text_vertex_shader)
    }
}

// Render text at 2D screen position (pixels from top-left)
text_render_2d_gpu :: proc(
    renderer: ^TextRendererGPU,
    cmd: ^sdl.GPUCommandBuffer,
    pass: ^sdl.GPURenderPass,
    text: string,
    x, y, size: f32,
    color: [4]u8,
    screen_width, screen_height: u32,
) {
    if len(text) == 0 do return

    // Set font state
    fs.SetFont(&renderer.font_context, renderer.font_id)
    fs.SetSize(&renderer.font_context, size)
    fs.SetAlignHorizontal(&renderer.font_context, .LEFT)
    fs.SetAlignVertical(&renderer.font_context, .TOP)
    fs.SetColor(&renderer.font_context, color)

    // Collect vertices for text
    vertices: [1024]TextVertex  // Max 256 quads (4 verts each)
    vertex_count := 0

    // CRITICAL: Force fontstash to flush/render glyphs into texture BEFORE iterating
    // This ensures the glyphs are actually rasterized into textureData
    iter := fs.TextIterInit(&renderer.font_context, x, y, text)
    quad: fs.Quad
    quad_count := 0

    // Collect all quads first
    temp_quads := make([dynamic]fs.Quad, context.temp_allocator)
    for fs.TextIterNext(&renderer.font_context, &iter, &quad) {
        append(&temp_quads, quad)
    }

    // Now convert quads to vertices
    for quad in temp_quads {
        if vertex_count + 6 > len(vertices) {
            break  // Buffer full
        }

        // First triangle (top-left, bottom-left, bottom-right)
        vertices[vertex_count + 0] = {{quad.x0, quad.y0}, {quad.s0, quad.t0}, color}
        vertices[vertex_count + 1] = {{quad.x0, quad.y1}, {quad.s0, quad.t1}, color}
        vertices[vertex_count + 2] = {{quad.x1, quad.y1}, {quad.s1, quad.t1}, color}

        // Second triangle (top-left, bottom-right, top-right)
        vertices[vertex_count + 3] = {{quad.x0, quad.y0}, {quad.s0, quad.t0}, color}
        vertices[vertex_count + 4] = {{quad.x1, quad.y1}, {quad.s1, quad.t1}, color}
        vertices[vertex_count + 5] = {{quad.x1, quad.y0}, {quad.s1, quad.t0}, color}

        vertex_count += 6
    }

    if vertex_count == 0 do return

    // Create temporary vertex buffer for text
    buffer_info := sdl.GPUBufferCreateInfo{
        usage = {.VERTEX},
        size = u32(vertex_count * size_of(TextVertex)),
    }

    temp_vertex_buffer := sdl.CreateGPUBuffer(renderer.gpu_device, buffer_info)
    if temp_vertex_buffer == nil {
        fmt.eprintln("ERROR: Failed to create text vertex buffer")
        return
    }
    defer sdl.ReleaseGPUBuffer(renderer.gpu_device, temp_vertex_buffer)

    // Upload vertex data via transfer buffer
    transfer_info := sdl.GPUTransferBufferCreateInfo{
        usage = .UPLOAD,
        size = u32(vertex_count * size_of(TextVertex)),
    }

    transfer_buffer := sdl.CreateGPUTransferBuffer(renderer.gpu_device, transfer_info)
    if transfer_buffer == nil {
        fmt.eprintln("ERROR: Failed to create transfer buffer for text")
        return
    }
    defer sdl.ReleaseGPUTransferBuffer(renderer.gpu_device, transfer_buffer)

    // Map and copy vertex data
    transfer_ptr := sdl.MapGPUTransferBuffer(renderer.gpu_device, transfer_buffer, false)
    if transfer_ptr == nil {
        fmt.eprintln("ERROR: Failed to map transfer buffer for text")
        return
    }

    dest_slice := ([^]TextVertex)(transfer_ptr)[:vertex_count]
    copy(dest_slice, vertices[:vertex_count])
    sdl.UnmapGPUTransferBuffer(renderer.gpu_device, transfer_buffer)

    // Upload to GPU
    upload_cmd := sdl.AcquireGPUCommandBuffer(renderer.gpu_device)
    copy_pass := sdl.BeginGPUCopyPass(upload_cmd)

    src := sdl.GPUTransferBufferLocation{
        transfer_buffer = transfer_buffer,
        offset = 0,
    }

    dst := sdl.GPUBufferRegion{
        buffer = temp_vertex_buffer,
        offset = 0,
        size = u32(vertex_count * size_of(TextVertex)),
    }

    sdl.UploadToGPUBuffer(copy_pass, src, dst, false)
    sdl.EndGPUCopyPass(copy_pass)
    _ = sdl.SubmitGPUCommandBuffer(upload_cmd)

    // Wait for upload to complete
    _ = sdl.WaitForGPUIdle(renderer.gpu_device)

    // Bind text pipeline
    sdl.BindGPUGraphicsPipeline(pass, renderer.text_pipeline)

    // Bind vertex buffer
    binding := sdl.GPUBufferBinding{
        buffer = temp_vertex_buffer,
        offset = 0,
    }
    sdl.BindGPUVertexBuffers(pass, 0, &binding, 1)

    // Bind font texture and sampler
    texture_binding := sdl.GPUTextureSamplerBinding{
        texture = renderer.font_texture,
        sampler = renderer.font_sampler,
    }
    sdl.BindGPUFragmentSamplers(pass, 0, &texture_binding, 1)

    // Set uniforms (screen size)
    uniforms := TextUniforms{
        screenSize = {f32(screen_width), f32(screen_height)},
    }
    sdl.PushGPUVertexUniformData(cmd, 0, &uniforms, size_of(TextUniforms))

    // Draw text
    sdl.DrawGPUPrimitives(pass, u32(vertex_count), 1, 0, 0)
}

// Update font atlas texture (upload to GPU)
// IMPORTANT: This must be called BEFORE rendering text in the same frame
text_renderer_gpu_update_texture :: proc(renderer: ^TextRendererGPU) {
    // Create transfer buffer for R8 texture data
    texture_size := u32(renderer.texture_width * renderer.texture_height)

    transfer_info := sdl.GPUTransferBufferCreateInfo{
        usage = .UPLOAD,
        size = texture_size,
    }

    transfer_buffer := sdl.CreateGPUTransferBuffer(renderer.gpu_device, transfer_info)
    if transfer_buffer == nil {
        fmt.eprintln("ERROR: Failed to create transfer buffer for font texture")
        return
    }
    defer sdl.ReleaseGPUTransferBuffer(renderer.gpu_device, transfer_buffer)

    // Map and copy R8 texture data directly (NO conversion)
    transfer_ptr := sdl.MapGPUTransferBuffer(renderer.gpu_device, transfer_buffer, false)
    if transfer_ptr == nil {
        fmt.eprintln("ERROR: Failed to map transfer buffer for font texture")
        return
    }

    // Copy R8 data directly - no conversion
    dest_slice := ([^]u8)(transfer_ptr)[:texture_size]
    copy(dest_slice, renderer.font_context.textureData[:texture_size])

    sdl.UnmapGPUTransferBuffer(renderer.gpu_device, transfer_buffer)

    // Upload to texture - use a dedicated command buffer and wait for completion
    // This ensures the texture is fully uploaded before any rendering happens
    upload_cmd := sdl.AcquireGPUCommandBuffer(renderer.gpu_device)
    copy_pass := sdl.BeginGPUCopyPass(upload_cmd)

    src := sdl.GPUTextureTransferInfo{
        transfer_buffer = transfer_buffer,
        offset = 0,
        pixels_per_row = u32(renderer.texture_width),
        rows_per_layer = u32(renderer.texture_height),
    }

    dst := sdl.GPUTextureRegion{
        texture = renderer.font_texture,
        w = u32(renderer.texture_width),
        h = u32(renderer.texture_height),
        d = 1,
    }

    sdl.UploadToGPUTexture(copy_pass, src, dst, false)
    sdl.EndGPUCopyPass(copy_pass)
    _ = sdl.SubmitGPUCommandBuffer(upload_cmd)

    // CRITICAL: Wait for texture upload to complete before proceeding
    // Without this, rendering might use the old/corrupted texture data
    _ = sdl.WaitForGPUIdle(renderer.gpu_device)
}

// DEBUG: Save font atlas texture to file for inspection
// DISABLED FOR NOW - focus on console debugging output
/*
text_renderer_gpu_save_atlas_debug :: proc(renderer: ^TextRendererGPU, filename: string) {

    // Convert R8 atlas to RGBA for PNG output
    r8_size := renderer.texture_width * renderer.texture_height
    rgba_data := make([]u8, r8_size * 4)
    defer delete(rgba_data)

    for i in 0..<r8_size {
        val := renderer.font_context.textureData[i]
        rgba_data[i*4 + 0] = val  // R
        rgba_data[i*4 + 1] = val  // G
        rgba_data[i*4 + 2] = val  // B
        rgba_data[i*4 + 3] = 255  // A (full opacity for visibility)
    }

    // Save as PNG
    ok := png.write_to_file(filename, rgba_data, i32(renderer.texture_width), i32(renderer.texture_height), 4)
    if ok {
        fmt.printf("✅ Saved font atlas to: %s\n", filename)
    } else {
        fmt.printf("❌ Failed to save font atlas to: %s\n", filename)
    }
}
*/

// Measure text bounds
text_measure_gpu :: proc(renderer: ^TextRendererGPU, text: string, size: f32) -> (width: f32, height: f32) {
    fs.SetFont(&renderer.font_context, renderer.font_id)
    fs.SetSize(&renderer.font_context, size)

    bounds: [4]f32
    width_result := fs.TextBounds(&renderer.font_context, text, 0, 0, &bounds)

    return width_result, bounds[3] - bounds[1]
}

// =============================================================================
// Sketch to Wireframe Conversion
// =============================================================================

// Convert sketch to wireframe mesh for rendering (GPU version) - EXCLUDING selected entity
sketch_to_wireframe_gpu :: proc(sk: ^sketch.Sketch2D) -> WireframeMeshGPU {
    mesh := wireframe_mesh_gpu_init()

    // Render all entities EXCEPT the selected one
    for entity, idx in sk.entities {
        // Skip selected entity - it will be rendered separately
        if idx == sk.selected_entity {
            continue
        }

        switch e in entity {
        case sketch.SketchLine:
            // Get start and end points
            start := sketch.sketch_get_point(sk, e.start_id)
            end := sketch.sketch_get_point(sk, e.end_id)

            if start != nil && end != nil {
                // Convert 2D sketch coordinates to 3D world coordinates
                start_2d := m.Vec2{start.x, start.y}
                end_2d := m.Vec2{end.x, end.y}

                start_3d := sketch.sketch_to_world(&sk.plane, start_2d)
                end_3d := sketch.sketch_to_world(&sk.plane, end_2d)

                wireframe_mesh_gpu_add_edge_f64(&mesh, start_3d, end_3d)
            }

        case sketch.SketchCircle:
            // Tessellate circle into line segments
            center_pt := sketch.sketch_get_point(sk, e.center_id)
            if center_pt != nil {
                // Draw circle with 64 segments
                segments := 64
                for i in 0..<segments {
                    angle0 := f64(i) * (2.0 * math.PI) / f64(segments)
                    angle1 := f64((i + 1) % segments) * (2.0 * math.PI) / f64(segments)

                    p0_2d := m.Vec2{
                        center_pt.x + e.radius * math.cos(angle0),
                        center_pt.y + e.radius * math.sin(angle0),
                    }
                    p1_2d := m.Vec2{
                        center_pt.x + e.radius * math.cos(angle1),
                        center_pt.y + e.radius * math.sin(angle1),
                    }

                    p0_3d := sketch.sketch_to_world(&sk.plane, p0_2d)
                    p1_3d := sketch.sketch_to_world(&sk.plane, p1_2d)

                    wireframe_mesh_gpu_add_edge_f64(&mesh, p0_3d, p1_3d)
                }
            }

        case sketch.SketchArc:
            // TODO: Implement arc rendering
        }
    }

    return mesh
}

// Convert ONLY selected entity to wireframe (for highlighting)
sketch_to_wireframe_selected_gpu :: proc(sk: ^sketch.Sketch2D) -> WireframeMeshGPU {
    mesh := wireframe_mesh_gpu_init()

    if sk.selected_entity < 0 || sk.selected_entity >= len(sk.entities) {
        return mesh // No selection
    }

    entity := sk.entities[sk.selected_entity]

    switch e in entity {
    case sketch.SketchLine:
        start := sketch.sketch_get_point(sk, e.start_id)
        end := sketch.sketch_get_point(sk, e.end_id)

        if start != nil && end != nil {
            start_2d := m.Vec2{start.x, start.y}
            end_2d := m.Vec2{end.x, end.y}

            start_3d := sketch.sketch_to_world(&sk.plane, start_2d)
            end_3d := sketch.sketch_to_world(&sk.plane, end_2d)

            wireframe_mesh_gpu_add_edge_f64(&mesh, start_3d, end_3d)
        }

    case sketch.SketchCircle:
        center_pt := sketch.sketch_get_point(sk, e.center_id)
        if center_pt != nil {
            segments := 64
            for i in 0..<segments {
                angle0 := f64(i) * (2.0 * math.PI) / f64(segments)
                angle1 := f64((i + 1) % segments) * (2.0 * math.PI) / f64(segments)

                p0_2d := m.Vec2{
                    center_pt.x + e.radius * math.cos(angle0),
                    center_pt.y + e.radius * math.sin(angle0),
                }
                p1_2d := m.Vec2{
                    center_pt.x + e.radius * math.cos(angle1),
                    center_pt.y + e.radius * math.sin(angle1),
                }

                p0_3d := sketch.sketch_to_world(&sk.plane, p0_2d)
                p1_3d := sketch.sketch_to_world(&sk.plane, p1_2d)

                wireframe_mesh_gpu_add_edge_f64(&mesh, p0_3d, p1_3d)
            }
        }

    case sketch.SketchArc:
        // TODO: Arc rendering
    }

    return mesh
}

// =============================================================================
// Sketch Points Rendering (as filled dots)
// =============================================================================

// Render sketch points as filled circular dots with screen-space constant size
// Calculate world-space size of one pixel at the sketch plane
// This accounts for both perspective and orthographic projection
get_pixel_size_world :: proc(viewer: ^ViewerGPU) -> f32 {
    viewport_height := f32(viewer.window_height)
    viewport_width := f32(viewer.window_width)

    if viewer.camera.projection_mode == .Orthographic {
        // Orthographic: pixel size is simply ortho_width divided by viewport width
        return viewer.camera.ortho_width / viewport_width
    } else {
        // Perspective: pixel size depends on distance and FOV
        fov_radians := math.to_radians(viewer.camera.fov)
        return (2.0 * viewer.camera.distance * math.tan(fov_radians * 0.5)) / viewport_height
    }
}

viewer_gpu_render_sketch_points :: proc(
    viewer: ^ViewerGPU,
    cmd: ^sdl.GPUCommandBuffer,
    pass: ^sdl.GPURenderPass,
    sk: ^sketch.Sketch2D,
    mvp: matrix[4,4]f32,
    color: [4]f32,
    point_size_pixels: f32,
) {
    if len(sk.points) == 0 do return

    // Calculate screen-space to world-space conversion
    pixel_size_world := get_pixel_size_world(viewer)

    // Calculate radius in world units for the desired pixel size
    radius := pixel_size_world * point_size_pixels

    segments := 16  // Number of segments for smooth circle

    // Generate triangle fan vertices for all points
    circle_verts := make([dynamic]LineVertex, context.temp_allocator)

    for point in sk.points {
        pt_2d := m.Vec2{point.x, point.y}
        center_3d := sketch.sketch_to_world(&sk.plane, pt_2d)

        // Center vertex
        center_f32 := [3]f32{f32(center_3d.x), f32(center_3d.y), f32(center_3d.z)}

        // Create triangle fan for filled circle
        for i in 0..<segments {
            angle0 := f64(i) * (2.0 * math.PI) / f64(segments)
            angle1 := f64((i + 1) % segments) * (2.0 * math.PI) / f64(segments)

            edge_2d_0 := m.Vec2{
                point.x + f64(radius) * math.cos(angle0),
                point.y + f64(radius) * math.sin(angle0),
            }
            edge_2d_1 := m.Vec2{
                point.x + f64(radius) * math.cos(angle1),
                point.y + f64(radius) * math.sin(angle1),
            }

            edge_3d_0 := sketch.sketch_to_world(&sk.plane, edge_2d_0)
            edge_3d_1 := sketch.sketch_to_world(&sk.plane, edge_2d_1)

            edge_f32_0 := [3]f32{f32(edge_3d_0.x), f32(edge_3d_0.y), f32(edge_3d_0.z)}
            edge_f32_1 := [3]f32{f32(edge_3d_1.x), f32(edge_3d_1.y), f32(edge_3d_1.z)}

            // Triangle: center, edge0, edge1
            append(&circle_verts, LineVertex{center_f32})
            append(&circle_verts, LineVertex{edge_f32_0})
            append(&circle_verts, LineVertex{edge_f32_1})
        }
    }

    if len(circle_verts) == 0 do return

    // Create temporary vertex buffer
    buffer_info := sdl.GPUBufferCreateInfo{
        usage = {.VERTEX},
        size = u32(len(circle_verts) * size_of(LineVertex)),
    }

    temp_vertex_buffer := sdl.CreateGPUBuffer(viewer.gpu_device, buffer_info)
    if temp_vertex_buffer == nil {
        fmt.eprintln("ERROR: Failed to create points vertex buffer")
        return
    }
    defer sdl.ReleaseGPUBuffer(viewer.gpu_device, temp_vertex_buffer)

    // Upload vertex data via transfer buffer
    transfer_info := sdl.GPUTransferBufferCreateInfo{
        usage = .UPLOAD,
        size = u32(len(circle_verts) * size_of(LineVertex)),
    }

    transfer_buffer := sdl.CreateGPUTransferBuffer(viewer.gpu_device, transfer_info)
    if transfer_buffer == nil {
        fmt.eprintln("ERROR: Failed to create transfer buffer for points")
        return
    }
    defer sdl.ReleaseGPUTransferBuffer(viewer.gpu_device, transfer_buffer)

    // Map and copy vertex data
    transfer_ptr := sdl.MapGPUTransferBuffer(viewer.gpu_device, transfer_buffer, false)
    if transfer_ptr == nil {
        fmt.eprintln("ERROR: Failed to map transfer buffer for points")
        return
    }

    dest_slice := ([^]LineVertex)(transfer_ptr)[:len(circle_verts)]
    copy(dest_slice, circle_verts[:])
    sdl.UnmapGPUTransferBuffer(viewer.gpu_device, transfer_buffer)

    // Upload to GPU
    upload_cmd := sdl.AcquireGPUCommandBuffer(viewer.gpu_device)
    copy_pass := sdl.BeginGPUCopyPass(upload_cmd)

    src := sdl.GPUTransferBufferLocation{
        transfer_buffer = transfer_buffer,
        offset = 0,
    }

    dst := sdl.GPUBufferRegion{
        buffer = temp_vertex_buffer,
        offset = 0,
        size = u32(len(circle_verts) * size_of(LineVertex)),
    }

    sdl.UploadToGPUBuffer(copy_pass, src, dst, false)
    sdl.EndGPUCopyPass(copy_pass)
    _ = sdl.SubmitGPUCommandBuffer(upload_cmd)

    // Wait for upload to complete
    _ = sdl.WaitForGPUIdle(viewer.gpu_device)

    // Switch to triangle pipeline
    sdl.BindGPUGraphicsPipeline(pass, viewer.triangle_pipeline)

    // Bind vertex buffer
    binding := sdl.GPUBufferBinding{
        buffer = temp_vertex_buffer,
        offset = 0,
    }
    sdl.BindGPUVertexBuffers(pass, 0, &binding, 1)

    // Draw points as filled circles
    uniforms := Uniforms{
        mvp = mvp,
        color = color,
    }
    sdl.PushGPUVertexUniformData(cmd, 0, &uniforms, size_of(Uniforms))
    sdl.PushGPUFragmentUniformData(cmd, 0, &uniforms, size_of(Uniforms))
    sdl.DrawGPUPrimitives(pass, u32(len(circle_verts)), 1, 0, 0)

    // Switch back to line pipeline
    sdl.BindGPUGraphicsPipeline(pass, viewer.pipeline)
}

// Render a single point with specified color and size
viewer_gpu_render_single_point :: proc(
    viewer: ^ViewerGPU,
    cmd: ^sdl.GPUCommandBuffer,
    pass: ^sdl.GPURenderPass,
    sk: ^sketch.Sketch2D,
    point: ^sketch.SketchPoint,
    mvp: matrix[4,4]f32,
    color: [4]f32,
    point_size_pixels: f32,
) {
    // Calculate screen-space to world-space conversion
    pixel_size_world := get_pixel_size_world(viewer)

    // Calculate radius in world units for the desired pixel size
    radius := pixel_size_world * point_size_pixels

    segments := 16  // Number of segments for smooth circle

    // Generate triangle fan vertices for the point
    circle_verts := make([dynamic]LineVertex, context.temp_allocator)

    pt_2d := m.Vec2{point.x, point.y}
    center_3d := sketch.sketch_to_world(&sk.plane, pt_2d)

    // Center vertex
    center_f32 := [3]f32{f32(center_3d.x), f32(center_3d.y), f32(center_3d.z)}

    // Create triangle fan for filled circle
    for i in 0..<segments {
        angle0 := f64(i) * (2.0 * math.PI) / f64(segments)
        angle1 := f64((i + 1) % segments) * (2.0 * math.PI) / f64(segments)

        edge_2d_0 := m.Vec2{
            point.x + f64(radius) * math.cos(angle0),
            point.y + f64(radius) * math.sin(angle0),
        }
        edge_2d_1 := m.Vec2{
            point.x + f64(radius) * math.cos(angle1),
            point.y + f64(radius) * math.sin(angle1),
        }

        edge_3d_0 := sketch.sketch_to_world(&sk.plane, edge_2d_0)
        edge_3d_1 := sketch.sketch_to_world(&sk.plane, edge_2d_1)

        edge_f32_0 := [3]f32{f32(edge_3d_0.x), f32(edge_3d_0.y), f32(edge_3d_0.z)}
        edge_f32_1 := [3]f32{f32(edge_3d_1.x), f32(edge_3d_1.y), f32(edge_3d_1.z)}

        // Triangle: center, edge0, edge1
        append(&circle_verts, LineVertex{center_f32})
        append(&circle_verts, LineVertex{edge_f32_0})
        append(&circle_verts, LineVertex{edge_f32_1})
    }

    if len(circle_verts) == 0 do return

    // Create temporary vertex buffer
    buffer_info := sdl.GPUBufferCreateInfo{
        usage = {.VERTEX},
        size = u32(len(circle_verts) * size_of(LineVertex)),
    }

    temp_vertex_buffer := sdl.CreateGPUBuffer(viewer.gpu_device, buffer_info)
    if temp_vertex_buffer == nil {
        fmt.eprintln("ERROR: Failed to create single point vertex buffer")
        return
    }
    defer sdl.ReleaseGPUBuffer(viewer.gpu_device, temp_vertex_buffer)

    // Upload vertex data via transfer buffer
    transfer_info := sdl.GPUTransferBufferCreateInfo{
        usage = .UPLOAD,
        size = u32(len(circle_verts) * size_of(LineVertex)),
    }

    transfer_buffer := sdl.CreateGPUTransferBuffer(viewer.gpu_device, transfer_info)
    if transfer_buffer == nil {
        fmt.eprintln("ERROR: Failed to create transfer buffer for single point")
        return
    }
    defer sdl.ReleaseGPUTransferBuffer(viewer.gpu_device, transfer_buffer)

    // Map and copy vertex data
    transfer_ptr := sdl.MapGPUTransferBuffer(viewer.gpu_device, transfer_buffer, false)
    if transfer_ptr == nil {
        fmt.eprintln("ERROR: Failed to map transfer buffer for single point")
        return
    }

    dest_slice := ([^]LineVertex)(transfer_ptr)[:len(circle_verts)]
    copy(dest_slice, circle_verts[:])
    sdl.UnmapGPUTransferBuffer(viewer.gpu_device, transfer_buffer)

    // Upload to GPU
    upload_cmd := sdl.AcquireGPUCommandBuffer(viewer.gpu_device)
    copy_pass := sdl.BeginGPUCopyPass(upload_cmd)

    src := sdl.GPUTransferBufferLocation{
        transfer_buffer = transfer_buffer,
        offset = 0,
    }

    dst := sdl.GPUBufferRegion{
        buffer = temp_vertex_buffer,
        offset = 0,
        size = u32(len(circle_verts) * size_of(LineVertex)),
    }

    sdl.UploadToGPUBuffer(copy_pass, src, dst, false)
    sdl.EndGPUCopyPass(copy_pass)
    _ = sdl.SubmitGPUCommandBuffer(upload_cmd)

    // Wait for upload to complete
    _ = sdl.WaitForGPUIdle(viewer.gpu_device)

    // Switch to triangle pipeline
    sdl.BindGPUGraphicsPipeline(pass, viewer.triangle_pipeline)

    // Bind vertex buffer
    binding := sdl.GPUBufferBinding{
        buffer = temp_vertex_buffer,
        offset = 0,
    }
    sdl.BindGPUVertexBuffers(pass, 0, &binding, 1)

    // Draw point as filled circle
    uniforms := Uniforms{
        mvp = mvp,
        color = color,
    }
    sdl.PushGPUVertexUniformData(cmd, 0, &uniforms, size_of(Uniforms))
    sdl.PushGPUFragmentUniformData(cmd, 0, &uniforms, size_of(Uniforms))
    sdl.DrawGPUPrimitives(pass, u32(len(circle_verts)), 1, 0, 0)

    // Switch back to line pipeline
    sdl.BindGPUGraphicsPipeline(pass, viewer.pipeline)
}

// =============================================================================
// Geometric Helper Functions
// =============================================================================

// Calculate intersection point of two lines in 2D
// Returns the intersection point, or midpoint if lines are parallel
calculate_line_intersection_2d :: proc(p1: m.Vec2, p2: m.Vec2, p3: m.Vec2, p4: m.Vec2) -> m.Vec2 {
    // Line 1: p1 + t * (p2 - p1)
    // Line 2: p3 + u * (p4 - p3)

    d1 := p2 - p1
    d2 := p4 - p3

    // Calculate denominator (cross product)
    denom := d1.x * d2.y - d1.y * d2.x

    // If lines are parallel (denominator ~ 0), return midpoint
    if glsl.abs(denom) < 1e-10 {
        return (p1 + p2) * 0.5
    }

    // Calculate t parameter for line 1
    diff := p3 - p1
    t := (diff.x * d2.y - diff.y * d2.x) / denom

    // Calculate intersection point
    return p1 + d1 * t
}

// =============================================================================
// Preview Geometry Rendering
// =============================================================================

// Render preview geometry (temporary line or circle following cursor)
viewer_gpu_render_sketch_preview :: proc(
    viewer: ^ViewerGPU,
    cmd: ^sdl.GPUCommandBuffer,
    pass: ^sdl.GPURenderPass,
    text_renderer: ^TextRendererGPU,
    sk: ^sketch.Sketch2D,
    mvp: matrix[4,4]f32,
    view: matrix[4,4]f32,
    proj: matrix[4,4]f32,
) {
    if !sk.temp_point_valid do return

    // Draw temporary cursor crosshair
    cursor_3d := sketch.sketch_to_world(&sk.plane, sk.temp_point)
    size: f64 = 0.05

    // Horizontal line
    h_line := [][2][3]f32{
        {
            {f32(cursor_3d.x - size), f32(cursor_3d.y), f32(cursor_3d.z)},
            {f32(cursor_3d.x + size), f32(cursor_3d.y), f32(cursor_3d.z)},
        },
    }
    viewer_gpu_render_thick_lines(viewer, cmd, pass, h_line, {0, 1, 1, 1}, mvp, 1.2)

    // Vertical line
    v_line := [][2][3]f32{
        {
            {f32(cursor_3d.x), f32(cursor_3d.y - size), f32(cursor_3d.z)},
            {f32(cursor_3d.x), f32(cursor_3d.y + size), f32(cursor_3d.z)},
        },
    }
    viewer_gpu_render_thick_lines(viewer, cmd, pass, v_line, {0, 1, 1, 1}, mvp, 1.2)

    // If line tool has first point, draw preview line
    if sk.current_tool == .Line && sk.first_point_id != -1 {
        first_pt := sketch.sketch_get_point(sk, sk.first_point_id)
        if first_pt != nil {
            start_2d := m.Vec2{first_pt.x, first_pt.y}
            start_3d := sketch.sketch_to_world(&sk.plane, start_2d)
            end_2d := sk.temp_point

            // Calculate line vector and length
            line_vec := end_2d - start_2d
            line_length := glsl.length(line_vec)

            // Horizontal/Vertical constraint snap detection
            SNAP_ANGLE_THRESHOLD :: 5.0  // degrees
            is_horizontal := false
            is_vertical := false
            snapped_end_2d := end_2d

            if line_length > 0.001 {
                // Calculate angle from horizontal
                angle_rad := math.atan2(line_vec.y, line_vec.x)
                angle_deg := angle_rad * 180.0 / math.PI

                // Normalize angle to 0-360
                if angle_deg < 0 do angle_deg += 360.0

                // DEBUG: Print angle and line vector for debugging constraint orientation
                // fmt.printf("DEBUG: Line angle=%.1f°, vec=(%.3f, %.3f), len=%.3f\n",
                    // angle_deg, line_vec.x, line_vec.y, line_length)

                // Check for horizontal snap (0° or 180°)
                if glsl.abs(angle_deg) < SNAP_ANGLE_THRESHOLD ||
                   glsl.abs(angle_deg - 180.0) < SNAP_ANGLE_THRESHOLD ||
                   glsl.abs(angle_deg - 360.0) < SNAP_ANGLE_THRESHOLD {
                    is_horizontal = true
                    // Snap Y coordinate to match start point
                    snapped_end_2d.y = start_2d.y
                    // fmt.println("DEBUG: Detected HORIZONTAL line (angle near 0°/180°)")
                } else if glsl.abs(angle_deg - 90.0) < SNAP_ANGLE_THRESHOLD ||
                          glsl.abs(angle_deg - 270.0) < SNAP_ANGLE_THRESHOLD {
                    // Check for vertical snap (90° or 270°)
                    is_vertical = true
                    // Snap X coordinate to match start point
                    snapped_end_2d.x = start_2d.x
                    // fmt.println("DEBUG: Detected VERTICAL line (angle near 90°/270°)")
                }
            }

            // Update sketch snap state for constraint application
            sk.preview_snap_horizontal = is_horizontal
            sk.preview_snap_vertical = is_vertical

            // Use snapped position for rendering if snapped
            cursor_3d_snapped := cursor_3d
            if is_horizontal || is_vertical {
                cursor_3d_snapped = sketch.sketch_to_world(&sk.plane, snapped_end_2d)
            }

            preview_line := [][2][3]f32{
                {
                    {f32(start_3d.x), f32(start_3d.y), f32(start_3d.z)},
                    {f32(cursor_3d_snapped.x), f32(cursor_3d_snapped.y), f32(cursor_3d_snapped.z)},
                },
            }

            // Draw preview line with different color if snapped
            line_color := is_horizontal || is_vertical ? [4]f32{1.0, 0.5, 0.0, 0.9} : [4]f32{0, 1, 1, 0.7}
            viewer_gpu_render_thick_lines(viewer, cmd, pass, preview_line, line_color, mvp, 1.2)

            // Display dimension text next to the preview line
            if text_renderer != nil {
                // Calculate actual line length (using snapped position if applicable)
                actual_end_2d := is_horizontal || is_vertical ? snapped_end_2d : end_2d
                actual_length := glsl.length(actual_end_2d - start_2d)

                // Calculate midpoint for text placement
                mid_3d := (start_3d + cursor_3d_snapped) * 0.5
                clip_pos := proj * view * glsl.vec4{f32(mid_3d.x), f32(mid_3d.y), f32(mid_3d.z), 1.0}

                if clip_pos.w != 0.0 {
                    ndc := clip_pos.xyz / clip_pos.w
                    screen_x := (ndc.x + 1.0) * 0.5 * f32(viewer.window_width)
                    screen_y := (1.0 - ndc.y) * 0.5 * f32(viewer.window_height)

                    // Display dimension text
                    dim_text := fmt.tprintf("%.2f", actual_length)
                    text_size: f32 = 14
                    text_offset: f32 = 15  // Offset text above the line

                    text_color := is_horizontal || is_vertical ? [4]u8{255, 128, 0, 255} : [4]u8{0, 255, 255, 255}
                    text_render_2d_gpu(text_renderer, cmd, pass, dim_text, screen_x, screen_y - text_offset, text_size, text_color, viewer.window_width, viewer.window_height)

                    // Display constraint indicator (H or V)
                    if is_horizontal {
                        constraint_text := "H"
                        text_render_2d_gpu(text_renderer, cmd, pass, constraint_text, screen_x + 30, screen_y - text_offset, text_size, [4]u8{255, 128, 0, 255}, viewer.window_width, viewer.window_height)
                    } else if is_vertical {
                        constraint_text := "V"
                        text_render_2d_gpu(text_renderer, cmd, pass, constraint_text, screen_x + 30, screen_y - text_offset, text_size, [4]u8{255, 128, 0, 255}, viewer.window_width, viewer.window_height)
                    }
                }
            }

            // Visual feedback for auto-close: Highlight chain start point in yellow if cursor is near it
            AUTO_CLOSE_THRESHOLD :: 0.15
            if sk.chain_start_point_id != -1 {
                chain_start_pt := sketch.sketch_get_point(sk, sk.chain_start_point_id)
                if chain_start_pt != nil {
                    chain_start_2d := m.Vec2{chain_start_pt.x, chain_start_pt.y}
                    dist_to_start := glsl.length(sk.temp_point - chain_start_2d)

                    // If cursor is near the chain start point, highlight it in yellow
                    if dist_to_start < AUTO_CLOSE_THRESHOLD {
                        // Render larger yellow point to indicate auto-close is available
                        viewer_gpu_render_single_point(viewer, cmd, pass, sk, chain_start_pt, mvp, {1.0, 1.0, 0.0, 1.0}, 8.0)
                    }
                }
            }
        }
    }

    // If dimension tool has both points selected, draw preview dimension
    if sk.current_tool == .Dimension && sk.first_point_id != -1 && sk.second_point_id != -1 {
        // Get the two points
        pt1 := sketch.sketch_get_point(sk, sk.first_point_id)
        pt2 := sketch.sketch_get_point(sk, sk.second_point_id)

        if pt1 != nil && pt2 != nil {
            p1_2d := m.Vec2{pt1.x, pt1.y}
            p2_2d := m.Vec2{pt2.x, pt2.y}

            edge_vec := p2_2d - p1_2d
            edge_midpoint := (p1_2d + p2_2d) * 0.5
            cursor_vec := sk.temp_point - edge_midpoint

            // Determine dimension type based on cursor position (matching tool logic)
            dimension_type: sketch.ConstraintType
            is_edge_dimension := sk.first_line_id >= 0

            if is_edge_dimension {
                // Edge dimension - always parallel to edge
                dimension_type = .Distance
            } else {
                // Point-to-point - smart H/V detection
                abs_cursor_x := glsl.abs(cursor_vec.x)
                abs_cursor_y := glsl.abs(cursor_vec.y)
                HORIZONTAL_THRESHOLD :: 0.3
                VERTICAL_THRESHOLD :: 0.3

                if abs_cursor_y > abs_cursor_x * (1.0 + HORIZONTAL_THRESHOLD) {
                    dimension_type = .DistanceX  // Horizontal
                } else if abs_cursor_x > abs_cursor_y * (1.0 + VERTICAL_THRESHOLD) {
                    dimension_type = .DistanceY  // Vertical
                } else {
                    dimension_type = .Distance   // Diagonal
                }
            }

            preview_lines := make([dynamic][2][3]f32, context.temp_allocator)

            // Render based on dimension type
            #partial switch dimension_type {
            case .DistanceX:
                // Horizontal dimension preview
                dim_y := sk.temp_point.y
                dim1_2d := m.Vec2{p1_2d.x, dim_y}
                dim2_2d := m.Vec2{p2_2d.x, dim_y}

                // Extension lines
                p1_3d := sketch.sketch_to_world(&sk.plane, p1_2d)
                dim1_3d := sketch.sketch_to_world(&sk.plane, dim1_2d)
                append(&preview_lines, [2][3]f32{
                    {f32(p1_3d.x), f32(p1_3d.y), f32(p1_3d.z)},
                    {f32(dim1_3d.x), f32(dim1_3d.y), f32(dim1_3d.z)},
                })

                p2_3d := sketch.sketch_to_world(&sk.plane, p2_2d)
                dim2_3d := sketch.sketch_to_world(&sk.plane, dim2_2d)
                append(&preview_lines, [2][3]f32{
                    {f32(p2_3d.x), f32(p2_3d.y), f32(p2_3d.z)},
                    {f32(dim2_3d.x), f32(dim2_3d.y), f32(dim2_3d.z)},
                })

                // Dimension line
                append(&preview_lines, [2][3]f32{
                    {f32(dim1_3d.x), f32(dim1_3d.y), f32(dim1_3d.z)},
                    {f32(dim2_3d.x), f32(dim2_3d.y), f32(dim2_3d.z)},
                })

                // Arrows
                dim_vec := dim2_2d - dim1_2d
                dim_len := glsl.length(dim_vec)
                dim_dir := m.Vec2{1.0, 0.0}
                if dim_len > 0.001 {
                    dim_dir = dim_vec / dim_len
                }
                arrow_lines := render_dimension_arrow_heads(sk, dim1_2d, dim2_2d, dim_dir, 0.15, 30.0)
                for arrow_line in arrow_lines {
                    append(&preview_lines, arrow_line)
                }

            case .DistanceY:
                // Vertical dimension preview
                dim_x := sk.temp_point.x
                dim1_2d := m.Vec2{dim_x, p1_2d.y}
                dim2_2d := m.Vec2{dim_x, p2_2d.y}

                // Extension lines
                p1_3d := sketch.sketch_to_world(&sk.plane, p1_2d)
                dim1_3d := sketch.sketch_to_world(&sk.plane, dim1_2d)
                append(&preview_lines, [2][3]f32{
                    {f32(p1_3d.x), f32(p1_3d.y), f32(p1_3d.z)},
                    {f32(dim1_3d.x), f32(dim1_3d.y), f32(dim1_3d.z)},
                })

                p2_3d := sketch.sketch_to_world(&sk.plane, p2_2d)
                dim2_3d := sketch.sketch_to_world(&sk.plane, dim2_2d)
                append(&preview_lines, [2][3]f32{
                    {f32(p2_3d.x), f32(p2_3d.y), f32(p2_3d.z)},
                    {f32(dim2_3d.x), f32(dim2_3d.y), f32(dim2_3d.z)},
                })

                // Dimension line
                append(&preview_lines, [2][3]f32{
                    {f32(dim1_3d.x), f32(dim1_3d.y), f32(dim1_3d.z)},
                    {f32(dim2_3d.x), f32(dim2_3d.y), f32(dim2_3d.z)},
                })

                // Arrows
                dim_vec := dim2_2d - dim1_2d
                dim_len := glsl.length(dim_vec)
                dim_dir := m.Vec2{0.0, 1.0}
                if dim_len > 0.001 {
                    dim_dir = dim_vec / dim_len
                }
                arrow_lines := render_dimension_arrow_heads(sk, dim1_2d, dim2_2d, dim_dir, 0.15, 30.0)
                for arrow_line in arrow_lines {
                    append(&preview_lines, arrow_line)
                }

            case .Distance:
                // Diagonal dimension preview (perpendicular offset)
                edge_len := glsl.length(edge_vec)
                if edge_len > 1e-10 {
                    edge_dir := edge_vec / edge_len
                    perp_dir := m.Vec2{-edge_dir.y, edge_dir.x}

                    to_offset := sk.temp_point - edge_midpoint
                    offset_distance := glsl.dot(to_offset, perp_dir)

                    MIN_OFFSET :: 0.3
                    if glsl.abs(offset_distance) < MIN_OFFSET {
                        offset_distance = MIN_OFFSET * glsl.sign(offset_distance)
                        if offset_distance == 0 {
                            offset_distance = MIN_OFFSET
                        }
                    }

                    dim1_2d := p1_2d + perp_dir * offset_distance
                    dim2_2d := p2_2d + perp_dir * offset_distance

                    dim1_3d := sketch.sketch_to_world(&sk.plane, dim1_2d)
                    dim2_3d := sketch.sketch_to_world(&sk.plane, dim2_2d)

                    // Extension lines
                    p1_3d := sketch.sketch_to_world(&sk.plane, p1_2d)
                    append(&preview_lines, [2][3]f32{
                        {f32(p1_3d.x), f32(p1_3d.y), f32(p1_3d.z)},
                        {f32(dim1_3d.x), f32(dim1_3d.y), f32(dim1_3d.z)},
                    })

                    p2_3d := sketch.sketch_to_world(&sk.plane, p2_2d)
                    append(&preview_lines, [2][3]f32{
                        {f32(p2_3d.x), f32(p2_3d.y), f32(p2_3d.z)},
                        {f32(dim2_3d.x), f32(dim2_3d.y), f32(dim2_3d.z)},
                    })

                    // Dimension line
                    append(&preview_lines, [2][3]f32{
                        {f32(dim1_3d.x), f32(dim1_3d.y), f32(dim1_3d.z)},
                        {f32(dim2_3d.x), f32(dim2_3d.y), f32(dim2_3d.z)},
                    })

                    // Arrows
                    dim_vec := dim2_2d - dim1_2d
                    dim_dir := dim_vec / glsl.length(dim_vec)
                    arrow_lines := render_dimension_arrow_heads(sk, dim1_2d, dim2_2d, dim_dir, 0.15, 30.0)
                    for arrow_line in arrow_lines {
                        append(&preview_lines, arrow_line)
                    }
                }
            }

            // Draw preview dimension in bright cyan (semi-transparent)
            viewer_gpu_render_thick_lines(viewer, cmd, pass, preview_lines[:], {0, 1, 1, 0.7}, mvp, 1.2)
        }
    }

    // ANGULAR DIMENSION PREVIEW: If dimension tool has both lines selected, draw preview arc
    if sk.current_tool == .Dimension && sk.first_line_id >= 0 && sk.second_line_id >= 0 {
        // Get both line entities
        line1, ok1 := sk.entities[sk.first_line_id].(sketch.SketchLine)
        line2, ok2 := sk.entities[sk.second_line_id].(sketch.SketchLine)

        if ok1 && ok2 {
            // Get line endpoints
            p1_start := sketch.sketch_get_point(sk, line1.start_id)
            p1_end := sketch.sketch_get_point(sk, line1.end_id)
            p2_start := sketch.sketch_get_point(sk, line2.start_id)
            p2_end := sketch.sketch_get_point(sk, line2.end_id)

            if p1_start != nil && p1_end != nil && p2_start != nil && p2_end != nil {
                // Calculate line direction vectors
                v1 := m.Vec2{p1_end.x - p1_start.x, p1_end.y - p1_start.y}
                v2 := m.Vec2{p2_end.x - p2_start.x, p2_end.y - p2_start.y}

                len1 := glsl.length(v1)
                len2 := glsl.length(v2)

                if len1 > 1e-10 && len2 > 1e-10 {
                    v1 = v1 / len1
                    v2 = v2 / len2

                    // Calculate angle using atan2
                    dot := v1.x * v2.x + v1.y * v2.y
                    cross := v1.x * v2.y - v1.y * v2.x
                    angle_rad := math.atan2(cross, dot)
                    angle_deg := angle_rad * 180.0 / math.PI
                    if angle_deg < 0 do angle_deg += 360.0
                    if angle_deg > 180.0 do angle_deg = 360.0 - angle_deg

                    // Find arc center: Use shared vertex if lines share one, otherwise use intersection
                    center_2d: m.Vec2

                    // Check if lines share a common vertex (adjacent edges)
                    p1_start_2d := m.Vec2{p1_start.x, p1_start.y}
                    p1_end_2d := m.Vec2{p1_end.x, p1_end.y}
                    p2_start_2d := m.Vec2{p2_start.x, p2_start.y}
                    p2_end_2d := m.Vec2{p2_end.x, p2_end.y}

                    VERTEX_TOLERANCE :: 0.001

                    if glsl.length(p1_start_2d - p2_start_2d) < VERTEX_TOLERANCE {
                        center_2d = p1_start_2d  // Shared start-start vertex
                    } else if glsl.length(p1_start_2d - p2_end_2d) < VERTEX_TOLERANCE {
                        center_2d = p1_start_2d  // Shared start-end vertex
                    } else if glsl.length(p1_end_2d - p2_start_2d) < VERTEX_TOLERANCE {
                        center_2d = p1_end_2d    // Shared end-start vertex
                    } else if glsl.length(p1_end_2d - p2_end_2d) < VERTEX_TOLERANCE {
                        center_2d = p1_end_2d    // Shared end-end vertex
                    } else {
                        // No shared vertex - calculate intersection point
                        center_2d = calculate_line_intersection_2d(p1_start_2d, p1_end_2d, p2_start_2d, p2_end_2d)
                    }

                    // Arc radius: distance from center to cursor
                    radius := glsl.length(sk.temp_point - center_2d)

                    // Clamp radius to reasonable range
                    MIN_RADIUS :: 0.3
                    MAX_RADIUS :: 3.0
                    radius = glsl.clamp(radius, MIN_RADIUS, MAX_RADIUS)

                    // QUADRANT-BASED ARC SELECTION (OnShape-style)
                    // Based on cursor position, select which pair of directions to use for the arc
                    // The 4 quadrants use different combinations of edge directions and extensions

                    // Determine which direction each line points FROM the shared vertex
                    v1_from_corner := v1
                    v2_from_corner := v2

                    // Check which endpoint of line1 is the shared corner
                    dist_to_p1_start := glsl.length(center_2d - p1_start_2d)
                    dist_to_p1_end := glsl.length(center_2d - p1_end_2d)

                    if dist_to_p1_start < 0.001 {
                        // START is corner → v1 points away (start to end)
                        v1_from_corner = v1
                    } else if dist_to_p1_end < 0.001 {
                        // END is corner → reverse v1 to point away (end to start)
                        v1_from_corner = -v1
                    }

                    // Check which endpoint of line2 is the shared corner
                    dist_to_p2_start := glsl.length(center_2d - p2_start_2d)
                    dist_to_p2_end := glsl.length(center_2d - p2_end_2d)

                    if dist_to_p2_start < 0.001 {
                        // START is corner → v2 points away (start to end)
                        v2_from_corner = v2
                    } else if dist_to_p2_end < 0.001 {
                        // END is corner → reverse v2 to point away (end to start)
                        v2_from_corner = -v2
                    }

                    // Calculate cursor direction from corner
                    to_cursor := sk.temp_point - center_2d
                    cursor_len := glsl.length(to_cursor)
                    if cursor_len < 1e-10 do return  // Cursor too close to corner

                    // CRITICAL INSIGHT: We need to test which of 4 arcs contains the cursor.
                    // Each arc is defined by two directions (which can be edge or -edge).
                    // The arc that contains the cursor is the one we draw.

                    // Calculate angles for the edge directions
                    a1 := math.atan2(f64(v1_from_corner.y), f64(v1_from_corner.x))
                    a2 := math.atan2(f64(v2_from_corner.y), f64(v2_from_corner.x))
                    a1_neg := a1 + math.PI  // Opposite of v1
                    a2_neg := a2 + math.PI  // Opposite of v2
                    a_cursor := math.atan2(f64(to_cursor.y), f64(to_cursor.x))

                    // Normalize all angles to [0, 2π]
                    normalize_angle :: proc(a: f64) -> f64 {
                        result := a
                        for result < 0 do result += 2.0 * math.PI
                        for result >= 2.0 * math.PI do result -= 2.0 * math.PI
                        return result
                    }

                    a1 = normalize_angle(a1)
                    a2 = normalize_angle(a2)
                    a1_neg = normalize_angle(a1_neg)
                    a2_neg = normalize_angle(a2_neg)
                    a_cursor = normalize_angle(a_cursor)

                    // Determine which pair of vectors to use for the arc
                    arc_start, arc_end: f64

                    // Test all 4 possible arcs in sequence - test if cursor is in CCW arc from start to end
                    // Arc 1: v1 → v2 (ORANGE - inside angle)
                    {
                        sweep := a2 - a1
                        if sweep < 0 do sweep += 2.0 * math.PI
                        offset := a_cursor - a1
                        if offset < 0 do offset += 2.0 * math.PI
                        if offset <= sweep {
                            arc_start = a1
                            arc_end = a2
                        } else {
                            // Arc 2: v2 → -v1 (PURPLE - one extension)
                            sweep2 := a1_neg - a2
                            if sweep2 < 0 do sweep2 += 2.0 * math.PI
                            offset2 := a_cursor - a2
                            if offset2 < 0 do offset2 += 2.0 * math.PI
                            if offset2 <= sweep2 {
                                arc_start = a2
                                arc_end = a1_neg
                            } else {
                                // Arc 3: -v1 → -v2 (BLUE - outside angle)
                                sweep3 := a2_neg - a1_neg
                                if sweep3 < 0 do sweep3 += 2.0 * math.PI
                                offset3 := a_cursor - a1_neg
                                if offset3 < 0 do offset3 += 2.0 * math.PI
                                if offset3 <= sweep3 {
                                    arc_start = a1_neg
                                    arc_end = a2_neg
                                } else {
                                    // Arc 4: -v2 → v1 (GREEN - other extension)
                                    arc_start = a2_neg
                                    arc_end = a1
                                }
                            }
                        }
                    }

                    // Calculate CCW sweep angle
                    start_angle := arc_start
                    sweep_angle := arc_end - arc_start
                    if sweep_angle < 0 do sweep_angle += 2.0 * math.PI

                    // Tessellate arc into line segments (24 segments for smooth preview)
                    segments := 24
                    arc_lines := make([dynamic][2][3]f32, context.temp_allocator)

                    for i in 0..<segments {
                        t0 := f64(i) / f64(segments)
                        t1 := f64(i + 1) / f64(segments)

                        angle0 := start_angle + sweep_angle * t0
                        angle1_seg := start_angle + sweep_angle * t1

                        p0_2d := center_2d + m.Vec2{radius * math.cos(angle0), radius * math.sin(angle0)}
                        p1_2d := center_2d + m.Vec2{radius * math.cos(angle1_seg), radius * math.sin(angle1_seg)}

                        p0_3d := sketch.sketch_to_world(&sk.plane, p0_2d)
                        p1_3d := sketch.sketch_to_world(&sk.plane, p1_2d)

                        append(&arc_lines, [2][3]f32{
                            {f32(p0_3d.x), f32(p0_3d.y), f32(p0_3d.z)},
                            {f32(p1_3d.x), f32(p1_3d.y), f32(p1_3d.z)},
                        })
                    }

                    // Draw preview arc in bright yellow (semi-transparent)
                    viewer_gpu_render_thick_lines(viewer, cmd, pass, arc_lines[:], {1.0, 1.0, 0.0, 0.7}, mvp, 1.5)
                }
            }
        }
    }

    // DIAMETER DIMENSION PREVIEW: If dimension tool has a circle selected, draw preview diameter
    if sk.current_tool == .Dimension && sk.first_line_id >= 0 &&
       sk.first_point_id == -1 && sk.second_point_id == -1 && sk.second_line_id == -1 {

        // Verify the entity is a circle
        if sk.first_line_id < len(sk.entities) {
            entity := sk.entities[sk.first_line_id]
            if circle, is_circle := entity.(sketch.SketchCircle); is_circle {
                // Get circle center point
                center_pt := sketch.sketch_get_point(sk, circle.center_id)
                if center_pt != nil {
                    center_2d := m.Vec2{center_pt.x, center_pt.y}

                    // Calculate diameter line direction from center to cursor
                    offset_vec := sk.temp_point - center_2d
                    offset_len := glsl.length(offset_vec)

                    // Default to horizontal if cursor is at center
                    dim_dir: m.Vec2
                    if offset_len < 1e-10 {
                        dim_dir = m.Vec2{1, 0}
                    } else {
                        dim_dir = offset_vec / offset_len
                    }

                    // Calculate two points on circle edge along diameter line
                    edge1_2d := center_2d - dim_dir * circle.radius
                    edge2_2d := center_2d + dim_dir * circle.radius

                    // Convert to 3D
                    edge1_3d := sketch.sketch_to_world(&sk.plane, edge1_2d)
                    edge2_3d := sketch.sketch_to_world(&sk.plane, edge2_2d)

                    // Dimension line
                    preview_lines := make([dynamic][2][3]f32, context.temp_allocator)
                    append(&preview_lines, [2][3]f32{
                        {f32(edge1_3d.x), f32(edge1_3d.y), f32(edge1_3d.z)},
                        {f32(edge2_3d.x), f32(edge2_3d.y), f32(edge2_3d.z)},
                    })

                    // Arrows at both ends
                    arrow_lines := render_dimension_arrow_heads(sk, edge1_2d, edge2_2d, dim_dir, 0.15, 30.0)
                    for arrow_line in arrow_lines {
                        append(&preview_lines, arrow_line)
                    }

                    // Draw preview dimension in bright yellow (semi-transparent)
                    viewer_gpu_render_thick_lines(viewer, cmd, pass, preview_lines[:], {1.0, 1.0, 0.0, 0.7}, mvp, 1.5)

                    // Display diameter text next to cursor
                    if text_renderer != nil {
                        diameter := circle.radius * 2.0
                        cursor_3d := sketch.sketch_to_world(&sk.plane, sk.temp_point)
                        clip_pos := proj * view * glsl.vec4{f32(cursor_3d.x), f32(cursor_3d.y), f32(cursor_3d.z), 1.0}

                        if clip_pos.w != 0.0 {
                            ndc := clip_pos.xyz / clip_pos.w
                            screen_x := (ndc.x + 1.0) * 0.5 * f32(viewer.window_width)
                            screen_y := (1.0 - ndc.y) * 0.5 * f32(viewer.window_height)

                            // Display dimension text with Ø symbol
                            dia_text := fmt.tprintf("Ø%.2f", diameter)
                            text_size: f32 = 14
                            text_offset: f32 = 15

                            text_render_2d_gpu(text_renderer, cmd, pass, dia_text, screen_x + text_offset, screen_y - text_offset, text_size, [4]u8{255, 255, 0, 255}, viewer.window_width, viewer.window_height)
                        }
                    }
                }
            }
        }
    }

    // If circle tool has center point, draw preview circle
    if sk.current_tool == .Circle && sk.first_point_id != -1 {
        center_pt := sketch.sketch_get_point(sk, sk.first_point_id)
        if center_pt != nil {
            center_2d := m.Vec2{center_pt.x, center_pt.y}

            // Calculate preview radius
            radius := glsl.length(sk.temp_point - center_2d)

            // Draw preview circle with 32 segments
            segments := 32
            circle_lines := make([dynamic][2][3]f32, context.temp_allocator)

            for i in 0..<segments {
                angle0 := f64(i) * (2.0 * math.PI) / f64(segments)
                angle1 := f64((i + 1) % segments) * (2.0 * math.PI) / f64(segments)

                p0_2d := m.Vec2{
                    center_pt.x + radius * math.cos(angle0),
                    center_pt.y + radius * math.sin(angle0),
                }
                p1_2d := m.Vec2{
                    center_pt.x + radius * math.cos(angle1),
                    center_pt.y + radius * math.sin(angle1),
                }

                p0_3d := sketch.sketch_to_world(&sk.plane, p0_2d)
                p1_3d := sketch.sketch_to_world(&sk.plane, p1_2d)

                append(&circle_lines, [2][3]f32{
                    {f32(p0_3d.x), f32(p0_3d.y), f32(p0_3d.z)},
                    {f32(p1_3d.x), f32(p1_3d.y), f32(p1_3d.z)},
                })
            }

            // Draw preview circle in bright cyan
            viewer_gpu_render_thick_lines(viewer, cmd, pass, circle_lines[:], {0, 1, 1, 0.7}, mvp, 1.2)

            // Draw radius line from center to cursor
            center_3d := sketch.sketch_to_world(&sk.plane, center_2d)
            radius_line := [][2][3]f32{
                {
                    {f32(center_3d.x), f32(center_3d.y), f32(center_3d.z)},
                    {f32(cursor_3d.x), f32(cursor_3d.y), f32(cursor_3d.z)},
                },
            }
            viewer_gpu_render_thick_lines(viewer, cmd, pass, radius_line, {0, 1, 1, 0.5}, mvp, 1.0)
        }
    }
}

// =============================================================================
// Constraint/Dimension Rendering
// =============================================================================

// Render constraint icons and dimension lines (simplified version for SDL3 GPU)
viewer_gpu_render_sketch_constraints :: proc(
    viewer: ^ViewerGPU,
    cmd: ^sdl.GPUCommandBuffer,
    pass: ^sdl.GPURenderPass,
    text_renderer: ^TextRendererGPU,
    sk: ^sketch.Sketch2D,
    mvp: matrix[4,4]f32,
    view: matrix[4,4]f32,
    proj: matrix[4,4]f32,
    document_settings: ^doc.DocumentSettings = nil,  // NEW: For unit formatting
) {
    if sk == nil do return
    if sk.constraints == nil do return
    if len(sk.constraints) == 0 do return

    for constraint in sk.constraints {
        if !constraint.enabled do continue

        // Check if this constraint is selected
        is_selected := (constraint.id == sk.selected_constraint_id)

        switch data in constraint.data {
        case sketch.DistanceData:
            render_distance_dimension_gpu(viewer, cmd, pass, text_renderer, sk, data, mvp, view, proj, is_selected, document_settings)

        case sketch.HorizontalData:
            render_horizontal_icon_gpu(viewer, cmd, pass, sk, data, mvp, is_selected)

        case sketch.VerticalData:
            render_vertical_icon_gpu(viewer, cmd, pass, sk, data, mvp, is_selected)

        case sketch.AngleData:
            render_angular_dimension_gpu(viewer, cmd, pass, text_renderer, sk, data, mvp, view, proj, is_selected)

        case sketch.DistanceXData:
            render_distance_x_dimension_gpu(viewer, cmd, pass, text_renderer, sk, data, mvp, view, proj, is_selected, document_settings)

        case sketch.DistanceYData:
            render_distance_y_dimension_gpu(viewer, cmd, pass, text_renderer, sk, data, mvp, view, proj, is_selected, document_settings)

        case sketch.DiameterData:
            render_diameter_dimension_gpu(viewer, cmd, pass, text_renderer, sk, data, mvp, view, proj, is_selected, document_settings)

        case sketch.PerpendicularData, sketch.ParallelData, sketch.CoincidentData, sketch.EqualData:
            // These constraint types can be added later if needed
            // For now, focusing on the most important: Distance dimensions

        case sketch.TangentData, sketch.PointOnLineData, sketch.PointOnCircleData, sketch.FixedPointData:
            // Additional constraint types - can be added incrementally
        }
    }
}

// Render distance dimension with extension lines and text
render_distance_dimension_gpu :: proc(
    viewer: ^ViewerGPU,
    cmd: ^sdl.GPUCommandBuffer,
    pass: ^sdl.GPURenderPass,
    text_renderer: ^TextRendererGPU,
    sk: ^sketch.Sketch2D,
    data: sketch.DistanceData,
    mvp: matrix[4,4]f32,
    view: matrix[4,4]f32,
    proj: matrix[4,4]f32,
    is_selected: bool,  // NEW: Highlight if selected
    document_settings: ^doc.DocumentSettings = nil,  // NEW: For unit formatting
) {
    if data.point1_id < 0 || data.point1_id >= len(sk.points) do return
    if data.point2_id < 0 || data.point2_id >= len(sk.points) do return

    p1 := sketch.sketch_get_point(sk, data.point1_id)
    p2 := sketch.sketch_get_point(sk, data.point2_id)
    if p1 == nil || p2 == nil do return

    p1_2d := m.Vec2{p1.x, p1.y}
    p2_2d := m.Vec2{p2.x, p2.y}

    // Calculate direction vector from p1 to p2
    edge_vec := p2_2d - p1_2d
    edge_len := glsl.length(edge_vec)
    if edge_len < 1e-10 do return

    edge_dir := edge_vec / edge_len

    // Calculate perpendicular vector (rotate 90 degrees)
    perp_dir := m.Vec2{-edge_dir.y, edge_dir.x}

    // Project offset position onto perpendicular axis
    mid := (p1_2d + p2_2d) * 0.5
    to_offset := data.offset - mid
    offset_distance := glsl.dot(to_offset, perp_dir)

    // Ensure minimum offset
    MIN_OFFSET :: 0.3
    if glsl.abs(offset_distance) < MIN_OFFSET {
        offset_distance = MIN_OFFSET * glsl.sign(offset_distance)
        if offset_distance == 0 {
            offset_distance = MIN_OFFSET
        }
    }

    // Calculate dimension line endpoints
    dim1_2d := p1_2d + perp_dir * offset_distance
    dim2_2d := p2_2d + perp_dir * offset_distance

    dim1_3d := sketch.sketch_to_world(&sk.plane, dim1_2d)
    dim2_3d := sketch.sketch_to_world(&sk.plane, dim2_2d)

    // Build dimension lines
    dim_lines := make([dynamic][2][3]f32, context.temp_allocator)

    // Extension line from p1 to dimension line
    p1_3d := sketch.sketch_to_world(&sk.plane, p1_2d)
    append(&dim_lines, [2][3]f32{
        {f32(p1_3d.x), f32(p1_3d.y), f32(p1_3d.z)},
        {f32(dim1_3d.x), f32(dim1_3d.y), f32(dim1_3d.z)},
    })

    // Extension line from p2 to dimension line
    p2_3d := sketch.sketch_to_world(&sk.plane, p2_2d)
    append(&dim_lines, [2][3]f32{
        {f32(p2_3d.x), f32(p2_3d.y), f32(p2_3d.z)},
        {f32(dim2_3d.x), f32(dim2_3d.y), f32(dim2_3d.z)},
    })

    // Calculate dimension line direction in 2D
    dim_vec := dim2_2d - dim1_2d
    dim_dir := dim_vec / glsl.length(dim_vec)

    // Calculate text width to create gap
    text_size: f32 = 20  // Larger, more readable text size
    text_width_world: f64 = 0.5  // Default gap width in world units
    text_width_pixels: f32 = 0
    text_height_pixels: f32 = 0

    if text_renderer != nil {
        // Format distance value with units if document_settings provided
        dist_text: string
        if document_settings != nil {
            dist_text = doc.document_format_value_conditional(document_settings, math.abs(data.distance), document_settings.show_units_on_dimensions)
        } else {
            dist_text = fmt.tprintf("%.2f", math.abs(data.distance))
        }
        text_width_pixels, text_height_pixels = text_measure_gpu(text_renderer, dist_text, text_size)

        // Convert text width from screen pixels to world units
        pixel_size_world := f64(get_pixel_size_world(viewer))

        // Add padding (40% on each side for breathing room)
        text_width_world = f64(text_width_pixels) * pixel_size_world * 1.8
    }

    // Calculate gap positions (centered on midpoint)
    gap_half := text_width_world * 0.5
    dim_mid_2d := (dim1_2d + dim2_2d) * 0.5  // Midpoint of dimension line
    gap_start_2d := dim_mid_2d - dim_dir * gap_half
    gap_end_2d := dim_mid_2d + dim_dir * gap_half

    // Calculate dimension line length to check if gap fits
    dim_line_len := glsl.length(dim2_2d - dim1_2d)
    gap_total_width := text_width_world

    // Only draw gap if it fits within the dimension line
    if gap_total_width < dim_line_len - 0.02 {
        // Gap fits - draw dimension line with gap (split into two segments)

        // Left segment: dim1 to gap_start
        gap_start_3d := sketch.sketch_to_world(&sk.plane, gap_start_2d)
        append(&dim_lines, [2][3]f32{
            {f32(dim1_3d.x), f32(dim1_3d.y), f32(dim1_3d.z)},
            {f32(gap_start_3d.x), f32(gap_start_3d.y), f32(gap_start_3d.z)},
        })

        // Right segment: gap_end to dim2
        gap_end_3d := sketch.sketch_to_world(&sk.plane, gap_end_2d)
        append(&dim_lines, [2][3]f32{
            {f32(gap_end_3d.x), f32(gap_end_3d.y), f32(gap_end_3d.z)},
            {f32(dim2_3d.x), f32(dim2_3d.y), f32(dim2_3d.z)},
        })
    } else {
        // Gap too wide - draw full line without gap (text will overlap, but dimension is still visible)
        append(&dim_lines, [2][3]f32{
            {f32(dim1_3d.x), f32(dim1_3d.y), f32(dim1_3d.z)},
            {f32(dim2_3d.x), f32(dim2_3d.y), f32(dim2_3d.z)},
        })
    }

    // Arrow head size - scale with camera distance for consistent screen size
    // At distance 100 (default for mm), arrow is 1.5mm. Scales linearly with zoom.
    camera_distance := glsl.length(viewer.camera.position - viewer.camera.target)
    ARROW_BASE_SIZE :: 1.5  // Base size in mm at default camera distance
    arrow_size := ARROW_BASE_SIZE * (camera_distance / 100.0)  // Scale with camera distance
    ARROW_ANGLE :: 30.0 // degrees

    // Draw arrow heads at both ends
    arrow_lines := render_dimension_arrow_heads(
        sk,
        dim1_2d,
        dim2_2d,
        dim_dir,
        arrow_size,
        ARROW_ANGLE,
    )

    // Combine dimension lines and arrow lines
    for arrow_line in arrow_lines {
        append(&dim_lines, arrow_line)
    }

    // Draw dimension lines in bright yellow (or white if selected)
    dim_color := is_selected ? [4]f32{1.0, 1.0, 1.0, 1.0} : [4]f32{1.0, 1.0, 0.0, 1.0}
    viewer_gpu_render_thick_lines(viewer, cmd, pass, dim_lines[:], dim_color, mvp, 1.5)

    // Render dimension text if text renderer available
    if text_renderer != nil {
        // Calculate midpoint of dimension line
        mid_dim_3d := (dim1_3d + dim2_3d) * 0.5

        // Project to screen space
        clip_pos := proj * view * glsl.vec4{f32(mid_dim_3d.x), f32(mid_dim_3d.y), f32(mid_dim_3d.z), 1.0}

        if clip_pos.w != 0.0 {
            // Convert from clip space to screen space
            ndc := clip_pos.xyz / clip_pos.w
            screen_x := (ndc.x + 1.0) * 0.5 * f32(viewer.window_width)
            screen_y := (1.0 - ndc.y) * 0.5 * f32(viewer.window_height)

            // Format distance value with units if document_settings provided
            dist_text: string
            if document_settings != nil {
                dist_text = doc.document_format_value_conditional(document_settings, math.abs(data.distance), document_settings.show_units_on_dimensions)
            } else {
                dist_text = fmt.tprintf("%.2f", math.abs(data.distance))
            }

            // Center the text by offsetting by half width and half height
            // Text is rendered with top-left anchor, so we need to shift it
            text_offset_x := text_width_pixels * 0.5
            text_offset_y := text_height_pixels * 0.5

            // Render text centered on the midpoint (bright yellow if not selected, white if selected)
            text_color := is_selected ? [4]u8{255, 255, 255, 255} : [4]u8{255, 255, 0, 255}
            text_render_2d_gpu(
                text_renderer,
                cmd,
                pass,
                dist_text,
                screen_x - text_offset_x,  // Center horizontally
                screen_y - text_offset_y,  // Center vertically
                text_size,                 // Use larger text size
                text_color,
                viewer.window_width,
                viewer.window_height,
            )
        }
    }
}

// Render diameter dimension for circles
render_diameter_dimension_gpu :: proc(
    viewer: ^ViewerGPU,
    cmd: ^sdl.GPUCommandBuffer,
    pass: ^sdl.GPURenderPass,
    text_renderer: ^TextRendererGPU,
    sk: ^sketch.Sketch2D,
    data: sketch.DiameterData,
    mvp: matrix[4,4]f32,
    view: matrix[4,4]f32,
    proj: matrix[4,4]f32,
    is_selected: bool,
    document_settings: ^doc.DocumentSettings = nil,
) {
    // Get circle entity
    if data.circle_id < 0 || data.circle_id >= len(sk.entities) do return

    entity := sk.entities[data.circle_id]
    circle, ok := entity.(sketch.SketchCircle)
    if !ok do return

    // Get center point
    center_pt := sketch.sketch_get_point(sk, circle.center_id)
    if center_pt == nil do return

    center_2d := m.Vec2{center_pt.x, center_pt.y}

    // Calculate diameter line direction from center to offset position
    // This determines which diameter line to show (user can click different sides of circle)
    offset_vec := data.offset - center_2d
    offset_len := glsl.length(offset_vec)

    // Default to horizontal if offset is at center (shouldn't happen, but safe fallback)
    dim_dir: m.Vec2
    if offset_len < 1e-10 {
        dim_dir = m.Vec2{1, 0}  // Horizontal fallback
    } else {
        dim_dir = offset_vec / offset_len
    }

    // Calculate two points on circle edge along diameter line
    edge1_2d := center_2d - dim_dir * circle.radius
    edge2_2d := center_2d + dim_dir * circle.radius

    // Convert to 3D world space
    edge1_3d := sketch.sketch_to_world(&sk.plane, edge1_2d)
    edge2_3d := sketch.sketch_to_world(&sk.plane, edge2_2d)
    center_3d := sketch.sketch_to_world(&sk.plane, center_2d)

    // Build dimension lines
    dim_lines := make([dynamic][2][3]f32, context.temp_allocator)

    // Calculate text width to create gap
    text_size: f32 = 20
    text_width_world: f64 = 0.5
    text_width_pixels: f32 = 0
    text_height_pixels: f32 = 0

    if text_renderer != nil {
        // Format diameter value with Ø symbol and units
        dia_text: string
        if document_settings != nil {
            value_text := doc.document_format_value_conditional(document_settings, data.diameter, document_settings.show_units_on_dimensions)
            dia_text = fmt.tprintf("Ø%s", value_text)
        } else {
            dia_text = fmt.tprintf("Ø%.2f", data.diameter)
        }
        text_width_pixels, text_height_pixels = text_measure_gpu(text_renderer, dia_text, text_size)

        // Convert text width from screen pixels to world units
        pixel_size_world := f64(get_pixel_size_world(viewer))

        // Add padding (40% on each side)
        text_width_world = f64(text_width_pixels) * pixel_size_world * 1.8
    }

    // Calculate gap positions (centered on circle center)
    gap_half := text_width_world * 0.5
    gap_start_2d := center_2d - dim_dir * gap_half
    gap_end_2d := center_2d + dim_dir * gap_half

    // Diameter line is always at least as long as the diameter, so gap always fits
    // Draw dimension line with gap (split into two segments)

    // Left segment: edge1 to gap_start
    gap_start_3d := sketch.sketch_to_world(&sk.plane, gap_start_2d)
    append(&dim_lines, [2][3]f32{
        {f32(edge1_3d.x), f32(edge1_3d.y), f32(edge1_3d.z)},
        {f32(gap_start_3d.x), f32(gap_start_3d.y), f32(gap_start_3d.z)},
    })

    // Right segment: gap_end to edge2
    gap_end_3d := sketch.sketch_to_world(&sk.plane, gap_end_2d)
    append(&dim_lines, [2][3]f32{
        {f32(gap_end_3d.x), f32(gap_end_3d.y), f32(gap_end_3d.z)},
        {f32(edge2_3d.x), f32(edge2_3d.y), f32(edge2_3d.z)},
    })

    // Arrow head size - scale with camera distance
    camera_distance := glsl.length(viewer.camera.position - viewer.camera.target)
    ARROW_BASE_SIZE :: 1.5
    arrow_size := ARROW_BASE_SIZE * (camera_distance / 100.0)
    ARROW_ANGLE :: 30.0

    // Draw arrow heads at both ends (pointing outward from center)
    arrow_lines := render_dimension_arrow_heads(
        sk,
        edge1_2d,
        edge2_2d,
        dim_dir,
        arrow_size,
        ARROW_ANGLE,
    )

    // Combine dimension lines and arrow lines
    for arrow_line in arrow_lines {
        append(&dim_lines, arrow_line)
    }

    // Draw dimension lines in bright yellow (or white if selected)
    dim_color := is_selected ? [4]f32{1.0, 1.0, 1.0, 1.0} : [4]f32{1.0, 1.0, 0.0, 1.0}
    viewer_gpu_render_thick_lines(viewer, cmd, pass, dim_lines[:], dim_color, mvp, 1.5)

    // Render diameter text with Ø symbol
    if text_renderer != nil {
        // Project center to screen space
        clip_pos := proj * view * glsl.vec4{f32(center_3d.x), f32(center_3d.y), f32(center_3d.z), 1.0}

        if clip_pos.w != 0.0 {
            // Convert from clip space to screen space
            ndc := clip_pos.xyz / clip_pos.w
            screen_x := (ndc.x + 1.0) * 0.5 * f32(viewer.window_width)
            screen_y := (1.0 - ndc.y) * 0.5 * f32(viewer.window_height)

            // Format diameter value with Ø symbol and units
            dia_text: string
            if document_settings != nil {
                value_text := doc.document_format_value_conditional(document_settings, data.diameter, document_settings.show_units_on_dimensions)
                dia_text = fmt.tprintf("Ø%s", value_text)
            } else {
                dia_text = fmt.tprintf("Ø%.2f", data.diameter)
            }

            // Center the text horizontally
            text_offset_x := text_width_pixels * 0.5
            text_offset_y := text_height_pixels * 0.5

            // Position text ABOVE the diameter line (like reference image)
            // Move upward by 1.2x text height from center to position above the line
            text_vertical_offset := text_height_pixels * 1.2

            // Render text above the diameter line (bright yellow if not selected, white if selected)
            text_color := is_selected ? [4]u8{255, 255, 255, 255} : [4]u8{255, 255, 0, 255}
            text_render_2d_gpu(
                text_renderer,
                cmd,
                pass,
                dia_text,
                screen_x - text_offset_x,
                screen_y - text_offset_y - text_vertical_offset,  // Move upward in screen space
                text_size,
                text_color,
                viewer.window_width,
                viewer.window_height,
            )
        }
    }
}

// Helper function to create arrow heads for dimension lines
render_dimension_arrow_heads :: proc(
    sk: ^sketch.Sketch2D,
    dim1_2d: m.Vec2,
    dim2_2d: m.Vec2,
    dim_dir: m.Vec2,
    arrow_size: f64,
    arrow_angle_deg: f64,
) -> [dynamic][2][3]f32 {
    arrow_lines := make([dynamic][2][3]f32, context.temp_allocator)

    arrow_angle := math.to_radians(arrow_angle_deg)

    // Left arrow (at dim1, pointing inward)
    // Rotate dim_dir by +arrow_angle and -arrow_angle
    cos_a := math.cos(arrow_angle)
    sin_a := math.sin(arrow_angle)

    // First arrow line (upper)
    arrow1_dir := m.Vec2{
        dim_dir.x * cos_a - dim_dir.y * sin_a,
        dim_dir.x * sin_a + dim_dir.y * cos_a,
    }
    arrow1_end_2d := dim1_2d + arrow1_dir * arrow_size
    arrow1_end_3d := sketch.sketch_to_world(&sk.plane, arrow1_end_2d)
    dim1_3d := sketch.sketch_to_world(&sk.plane, dim1_2d)

    append(&arrow_lines, [2][3]f32{
        {f32(dim1_3d.x), f32(dim1_3d.y), f32(dim1_3d.z)},
        {f32(arrow1_end_3d.x), f32(arrow1_end_3d.y), f32(arrow1_end_3d.z)},
    })

    // Second arrow line (lower)
    arrow2_dir := m.Vec2{
        dim_dir.x * cos_a + dim_dir.y * sin_a,
        -dim_dir.x * sin_a + dim_dir.y * cos_a,
    }
    arrow2_end_2d := dim1_2d + arrow2_dir * arrow_size
    arrow2_end_3d := sketch.sketch_to_world(&sk.plane, arrow2_end_2d)

    append(&arrow_lines, [2][3]f32{
        {f32(dim1_3d.x), f32(dim1_3d.y), f32(dim1_3d.z)},
        {f32(arrow2_end_3d.x), f32(arrow2_end_3d.y), f32(arrow2_end_3d.z)},
    })

    // Right arrow (at dim2, pointing inward - so use -dim_dir)
    neg_dir := -dim_dir

    // First arrow line (upper)
    arrow3_dir := m.Vec2{
        neg_dir.x * cos_a - neg_dir.y * sin_a,
        neg_dir.x * sin_a + neg_dir.y * cos_a,
    }
    arrow3_end_2d := dim2_2d + arrow3_dir * arrow_size
    arrow3_end_3d := sketch.sketch_to_world(&sk.plane, arrow3_end_2d)
    dim2_3d := sketch.sketch_to_world(&sk.plane, dim2_2d)

    append(&arrow_lines, [2][3]f32{
        {f32(dim2_3d.x), f32(dim2_3d.y), f32(dim2_3d.z)},
        {f32(arrow3_end_3d.x), f32(arrow3_end_3d.y), f32(arrow3_end_3d.z)},
    })

    // Second arrow line (lower)
    arrow4_dir := m.Vec2{
        neg_dir.x * cos_a + neg_dir.y * sin_a,
        -neg_dir.x * sin_a + neg_dir.y * cos_a,
    }
    arrow4_end_2d := dim2_2d + arrow4_dir * arrow_size
    arrow4_end_3d := sketch.sketch_to_world(&sk.plane, arrow4_end_2d)

    append(&arrow_lines, [2][3]f32{
        {f32(dim2_3d.x), f32(dim2_3d.y), f32(dim2_3d.z)},
        {f32(arrow4_end_3d.x), f32(arrow4_end_3d.y), f32(arrow4_end_3d.z)},
    })

    return arrow_lines
}

// Render horizontal constraint icon (H symbol)
render_horizontal_icon_gpu :: proc(
    viewer: ^ViewerGPU,
    cmd: ^sdl.GPUCommandBuffer,
    pass: ^sdl.GPURenderPass,
    sk: ^sketch.Sketch2D,
    data: sketch.HorizontalData,
    mvp: matrix[4,4]f32,
    is_selected: bool,  // NEW: Highlight if selected
) {
    if data.line_id < 0 || data.line_id >= len(sk.entities) do return

    entity := sk.entities[data.line_id]
    line, ok := entity.(sketch.SketchLine)
    if !ok do return

    // Get line midpoint
    p1 := sketch.sketch_get_point(sk, line.start_id)
    p2 := sketch.sketch_get_point(sk, line.end_id)
    if p1 == nil || p2 == nil do return

    mid_2d := m.Vec2{(p1.x + p2.x) * 0.5, (p1.y + p2.y) * 0.5}

    // SCREEN-SPACE CONSTANT SIZE: Calculate icon size based on screen pixels
    pixel_size_world := get_pixel_size_world(viewer)
    icon_size_pixels: f32 = 24  // Icon size in pixels (was 0.15 world units)
    offset_pixels: f32 = 40     // Offset from line in pixels (was 1.5 * size)

    size := f64(pixel_size_world * icon_size_pixels)
    offset_distance := f64(pixel_size_world * offset_pixels)

    // Calculate line direction in sketch space
    line_dir := m.Vec2{p2.x - p1.x, p2.y - p1.y}
    line_len := glsl.length(line_dir)

    // Offset perpendicular to the line (horizontal line is parallel to X, so offset in Y)
    // For horizontal constraint: line is parallel to X axis (dy=0), so perpendicular is (0,1)
    perpendicular := m.Vec2{0, 1}
    if line_len > 0.001 {
        line_dir = line_dir / line_len
        // Perpendicular vector (rotate 90° CCW): (x,y) → (-y,x)
        perpendicular = m.Vec2{-line_dir.y, line_dir.x}
    }

    offset_2d := mid_2d + perpendicular * offset_distance

    // Draw 'H' shape
    h_lines := make([dynamic][2][3]f32, context.temp_allocator)

    // Left vertical line
    left_2d := m.Vec2{offset_2d.x - size * 0.4, offset_2d.y}
    append(&h_lines, [2][3]f32{
        {f32(sketch.sketch_to_world(&sk.plane, m.Vec2{left_2d.x, left_2d.y - size * 0.4}).x),
         f32(sketch.sketch_to_world(&sk.plane, m.Vec2{left_2d.x, left_2d.y - size * 0.4}).y),
         f32(sketch.sketch_to_world(&sk.plane, m.Vec2{left_2d.x, left_2d.y - size * 0.4}).z)},
        {f32(sketch.sketch_to_world(&sk.plane, m.Vec2{left_2d.x, left_2d.y + size * 0.4}).x),
         f32(sketch.sketch_to_world(&sk.plane, m.Vec2{left_2d.x, left_2d.y + size * 0.4}).y),
         f32(sketch.sketch_to_world(&sk.plane, m.Vec2{left_2d.x, left_2d.y + size * 0.4}).z)},
    })

    // Right vertical line
    right_2d := m.Vec2{offset_2d.x + size * 0.4, offset_2d.y}
    append(&h_lines, [2][3]f32{
        {f32(sketch.sketch_to_world(&sk.plane, m.Vec2{right_2d.x, right_2d.y - size * 0.4}).x),
         f32(sketch.sketch_to_world(&sk.plane, m.Vec2{right_2d.x, right_2d.y - size * 0.4}).y),
         f32(sketch.sketch_to_world(&sk.plane, m.Vec2{right_2d.x, right_2d.y - size * 0.4}).z)},
        {f32(sketch.sketch_to_world(&sk.plane, m.Vec2{right_2d.x, right_2d.y + size * 0.4}).x),
         f32(sketch.sketch_to_world(&sk.plane, m.Vec2{right_2d.x, right_2d.y + size * 0.4}).y),
         f32(sketch.sketch_to_world(&sk.plane, m.Vec2{right_2d.x, right_2d.y + size * 0.4}).z)},
    })

    // Horizontal crossbar
    append(&h_lines, [2][3]f32{
        {f32(sketch.sketch_to_world(&sk.plane, m.Vec2{left_2d.x, offset_2d.y}).x),
         f32(sketch.sketch_to_world(&sk.plane, m.Vec2{left_2d.x, offset_2d.y}).y),
         f32(sketch.sketch_to_world(&sk.plane, m.Vec2{left_2d.x, offset_2d.y}).z)},
        {f32(sketch.sketch_to_world(&sk.plane, m.Vec2{right_2d.x, offset_2d.y}).x),
         f32(sketch.sketch_to_world(&sk.plane, m.Vec2{right_2d.x, offset_2d.y}).y),
         f32(sketch.sketch_to_world(&sk.plane, m.Vec2{right_2d.x, offset_2d.y}).z)},
    })

    // Draw in orange/amber
    viewer_gpu_render_thick_lines(viewer, cmd, pass, h_lines[:], {1.0, 0.7, 0.0, 1.0}, mvp, 1.2)
}

// Render horizontal constraint icon (V symbol)
render_vertical_icon_gpu :: proc(
    viewer: ^ViewerGPU,
    cmd: ^sdl.GPUCommandBuffer,
    pass: ^sdl.GPURenderPass,
    sk: ^sketch.Sketch2D,
    data: sketch.VerticalData,
    mvp: matrix[4,4]f32,
    is_selected: bool,  // NEW: Highlight if selected
) {
    if data.line_id < 0 || data.line_id >= len(sk.entities) do return

    entity := sk.entities[data.line_id]
    line, ok := entity.(sketch.SketchLine)
    if !ok do return

    // Get line midpoint
    p1 := sketch.sketch_get_point(sk, line.start_id)
    p2 := sketch.sketch_get_point(sk, line.end_id)
    if p1 == nil || p2 == nil do return

    mid_2d := m.Vec2{(p1.x + p2.x) * 0.5, (p1.y + p2.y) * 0.5}

    // SCREEN-SPACE CONSTANT SIZE: Calculate icon size based on screen pixels
    pixel_size_world := get_pixel_size_world(viewer)
    icon_size_pixels: f32 = 24  // Icon size in pixels (was 0.15 world units)
    offset_pixels: f32 = 40     // Offset from line in pixels (was 1.5 * size)

    size := f64(pixel_size_world * icon_size_pixels)
    offset_distance := f64(pixel_size_world * offset_pixels)

    // Calculate line direction in sketch space
    line_dir := m.Vec2{p2.x - p1.x, p2.y - p1.y}
    line_len := glsl.length(line_dir)

    // Offset perpendicular to the line (vertical line is parallel to Y, so offset in X)
    // For vertical constraint: line is parallel to Y axis (dx=0), so perpendicular is (1,0)
    perpendicular := m.Vec2{1, 0}
    if line_len > 0.001 {
        line_dir = line_dir / line_len
        // Perpendicular vector (rotate 90° CCW): (x,y) → (-y,x)
        perpendicular = m.Vec2{-line_dir.y, line_dir.x}
    }

    offset_2d := mid_2d + perpendicular * offset_distance

    // Draw 'V' shape
    v_lines := make([dynamic][2][3]f32, context.temp_allocator)

    // Left diagonal
    append(&v_lines, [2][3]f32{
        {f32(sketch.sketch_to_world(&sk.plane, m.Vec2{offset_2d.x - size * 0.3, offset_2d.y + size * 0.4}).x),
         f32(sketch.sketch_to_world(&sk.plane, m.Vec2{offset_2d.x - size * 0.3, offset_2d.y + size * 0.4}).y),
         f32(sketch.sketch_to_world(&sk.plane, m.Vec2{offset_2d.x - size * 0.3, offset_2d.y + size * 0.4}).z)},
        {f32(sketch.sketch_to_world(&sk.plane, m.Vec2{offset_2d.x, offset_2d.y - size * 0.4}).x),
         f32(sketch.sketch_to_world(&sk.plane, m.Vec2{offset_2d.x, offset_2d.y - size * 0.4}).y),
         f32(sketch.sketch_to_world(&sk.plane, m.Vec2{offset_2d.x, offset_2d.y - size * 0.4}).z)},
    })

    // Right diagonal
    append(&v_lines, [2][3]f32{
        {f32(sketch.sketch_to_world(&sk.plane, m.Vec2{offset_2d.x, offset_2d.y - size * 0.4}).x),
         f32(sketch.sketch_to_world(&sk.plane, m.Vec2{offset_2d.x, offset_2d.y - size * 0.4}).y),
         f32(sketch.sketch_to_world(&sk.plane, m.Vec2{offset_2d.x, offset_2d.y - size * 0.4}).z)},
        {f32(sketch.sketch_to_world(&sk.plane, m.Vec2{offset_2d.x + size * 0.3, offset_2d.y + size * 0.4}).x),
         f32(sketch.sketch_to_world(&sk.plane, m.Vec2{offset_2d.x + size * 0.3, offset_2d.y + size * 0.4}).y),
         f32(sketch.sketch_to_world(&sk.plane, m.Vec2{offset_2d.x + size * 0.3, offset_2d.y + size * 0.4}).z)},
    })

    // Draw in orange/amber
    viewer_gpu_render_thick_lines(viewer, cmd, pass, v_lines[:], {1.0, 0.7, 0.0, 1.0}, mvp, 1.2)
}

// Render horizontal distance dimension (DistanceX) - measures X-axis distance
render_distance_x_dimension_gpu :: proc(
    viewer: ^ViewerGPU,
    cmd: ^sdl.GPUCommandBuffer,
    pass: ^sdl.GPURenderPass,
    text_renderer: ^TextRendererGPU,
    sk: ^sketch.Sketch2D,
    data: sketch.DistanceXData,
    mvp: matrix[4,4]f32,
    view: matrix[4,4]f32,
    proj: matrix[4,4]f32,
    is_selected: bool,
    document_settings: ^doc.DocumentSettings = nil,  // NEW: For unit formatting
) {
    if data.point1_id < 0 || data.point1_id >= len(sk.points) do return
    if data.point2_id < 0 || data.point2_id >= len(sk.points) do return

    p1 := sketch.sketch_get_point(sk, data.point1_id)
    p2 := sketch.sketch_get_point(sk, data.point2_id)
    if p1 == nil || p2 == nil do return

    p1_2d := m.Vec2{p1.x, p1.y}
    p2_2d := m.Vec2{p2.x, p2.y}

    // Horizontal dimension: measure X distance
    // Dimension line is horizontal, perpendicular extensions are vertical

    // Get Y position from offset
    dim_y := data.offset.y

    // Ensure minimum offset from points
    MIN_OFFSET :: 0.3
    mid_y := (p1.y + p2.y) * 0.5
    if glsl.abs(dim_y - mid_y) < MIN_OFFSET {
        dim_y = mid_y + MIN_OFFSET * glsl.sign(dim_y - mid_y)
        if dim_y == mid_y {
            dim_y = mid_y + MIN_OFFSET
        }
    }

    // Dimension line endpoints (horizontal)
    dim1_2d := m.Vec2{p1.x, dim_y}
    dim2_2d := m.Vec2{p2.x, dim_y}

    dim1_3d := sketch.sketch_to_world(&sk.plane, dim1_2d)
    dim2_3d := sketch.sketch_to_world(&sk.plane, dim2_2d)

    // Build dimension lines
    dim_lines := make([dynamic][2][3]f32, context.temp_allocator)

    // Vertical extension line from p1 to dimension line
    p1_3d := sketch.sketch_to_world(&sk.plane, p1_2d)
    append(&dim_lines, [2][3]f32{
        {f32(p1_3d.x), f32(p1_3d.y), f32(p1_3d.z)},
        {f32(dim1_3d.x), f32(dim1_3d.y), f32(dim1_3d.z)},
    })

    // Vertical extension line from p2 to dimension line
    p2_3d := sketch.sketch_to_world(&sk.plane, p2_2d)
    append(&dim_lines, [2][3]f32{
        {f32(p2_3d.x), f32(p2_3d.y), f32(p2_3d.z)},
        {f32(dim2_3d.x), f32(dim2_3d.y), f32(dim2_3d.z)},
    })

    // Calculate text width for gap
    text_size: f32 = 20
    text_width_world: f64 = 0.5
    text_width_pixels: f32 = 0
    text_height_pixels: f32 = 0

    if text_renderer != nil {
        dist_text := fmt.tprintf("%.2f", math.abs(data.distance))
        text_width_pixels, text_height_pixels = text_measure_gpu(text_renderer, dist_text, text_size)

        pixel_size_world := f64(get_pixel_size_world(viewer))
        text_width_world = f64(text_width_pixels) * pixel_size_world * 2.2  // Increased padding for gap
    }

    // Calculate gap positions (centered on X midpoint)
    mid_x := (p1.x + p2.x) * 0.5
    gap_half := text_width_world * 0.5
    gap_start_2d := m.Vec2{mid_x - gap_half, dim_y}
    gap_end_2d := m.Vec2{mid_x + gap_half, dim_y}

    // Calculate dimension line length to check if gap fits
    dim_line_len := glsl.abs(dim2_2d.x - dim1_2d.x)
    gap_total_width := text_width_world

    // Only draw gap if it fits within the dimension line
    if gap_total_width < dim_line_len - 0.02 {
        // Gap fits - draw dimension line with gap (split into two segments)
        gap_start_3d := sketch.sketch_to_world(&sk.plane, gap_start_2d)
        append(&dim_lines, [2][3]f32{
            {f32(dim1_3d.x), f32(dim1_3d.y), f32(dim1_3d.z)},
            {f32(gap_start_3d.x), f32(gap_start_3d.y), f32(gap_start_3d.z)},
        })

        gap_end_3d := sketch.sketch_to_world(&sk.plane, gap_end_2d)
        append(&dim_lines, [2][3]f32{
            {f32(gap_end_3d.x), f32(gap_end_3d.y), f32(gap_end_3d.z)},
            {f32(dim2_3d.x), f32(dim2_3d.y), f32(dim2_3d.z)},
        })
    } else {
        // Gap too wide - draw full line without gap
        append(&dim_lines, [2][3]f32{
            {f32(dim1_3d.x), f32(dim1_3d.y), f32(dim1_3d.z)},
            {f32(dim2_3d.x), f32(dim2_3d.y), f32(dim2_3d.z)},
        })
    }

    // Arrow heads (horizontal direction)
    // Calculate actual direction from dim1 to dim2
    dim_vec := dim2_2d - dim1_2d
    dim_len := glsl.length(dim_vec)
    dim_dir := m.Vec2{1.0, 0.0}
    if dim_len > 0.001 {
        dim_dir = dim_vec / dim_len
    }

    // Arrow head size - scale with camera distance for consistent screen size
    camera_distance := glsl.length(viewer.camera.position - viewer.camera.target)
    ARROW_BASE_SIZE :: 1.5  // Base size in mm
    arrow_size := ARROW_BASE_SIZE * (camera_distance / 100.0)
    ARROW_ANGLE :: 30.0

    arrow_lines := render_dimension_arrow_heads(sk, dim1_2d, dim2_2d, dim_dir, arrow_size, ARROW_ANGLE)
    for arrow_line in arrow_lines {
        append(&dim_lines, arrow_line)
    }

    // Draw dimension lines
    dim_color := is_selected ? [4]f32{1.0, 1.0, 1.0, 1.0} : [4]f32{1.0, 1.0, 0.0, 1.0}
    viewer_gpu_render_thick_lines(viewer, cmd, pass, dim_lines[:], dim_color, mvp, 1.5)

    // Render dimension text
    if text_renderer != nil {
        mid_dim_3d := (dim1_3d + dim2_3d) * 0.5
        clip_pos := proj * view * glsl.vec4{f32(mid_dim_3d.x), f32(mid_dim_3d.y), f32(mid_dim_3d.z), 1.0}

        if clip_pos.w != 0.0 {
            ndc := clip_pos.xyz / clip_pos.w
            screen_x := (ndc.x + 1.0) * 0.5 * f32(viewer.window_width)
            screen_y := (1.0 - ndc.y) * 0.5 * f32(viewer.window_height)

            dist_text := fmt.tprintf("%.2f", math.abs(data.distance))
            text_offset_x := text_width_pixels * 0.5
            text_offset_y := text_height_pixels * 0.5

            text_color := is_selected ? [4]u8{255, 255, 255, 255} : [4]u8{255, 255, 0, 255}
            text_render_2d_gpu(text_renderer, cmd, pass, dist_text, screen_x - text_offset_x, screen_y - text_offset_y, text_size, text_color, viewer.window_width, viewer.window_height)
        }
    }
}

// Render vertical distance dimension (DistanceY) - measures Y-axis distance
render_distance_y_dimension_gpu :: proc(
    viewer: ^ViewerGPU,
    cmd: ^sdl.GPUCommandBuffer,
    pass: ^sdl.GPURenderPass,
    text_renderer: ^TextRendererGPU,
    sk: ^sketch.Sketch2D,
    data: sketch.DistanceYData,
    mvp: matrix[4,4]f32,
    view: matrix[4,4]f32,
    proj: matrix[4,4]f32,
    is_selected: bool,
    document_settings: ^doc.DocumentSettings = nil,  // NEW: For unit formatting
) {
    if data.point1_id < 0 || data.point1_id >= len(sk.points) do return
    if data.point2_id < 0 || data.point2_id >= len(sk.points) do return

    p1 := sketch.sketch_get_point(sk, data.point1_id)
    p2 := sketch.sketch_get_point(sk, data.point2_id)
    if p1 == nil || p2 == nil do return

    p1_2d := m.Vec2{p1.x, p1.y}
    p2_2d := m.Vec2{p2.x, p2.y}

    // Vertical dimension: measure Y distance
    // Dimension line is vertical, perpendicular extensions are horizontal

    // Get X position from offset
    dim_x := data.offset.x

    // Ensure minimum offset from points
    MIN_OFFSET :: 0.3
    mid_x := (p1.x + p2.x) * 0.5
    if glsl.abs(dim_x - mid_x) < MIN_OFFSET {
        dim_x = mid_x + MIN_OFFSET * glsl.sign(dim_x - mid_x)
        if dim_x == mid_x {
            dim_x = mid_x + MIN_OFFSET
        }
    }

    // Dimension line endpoints (vertical)
    dim1_2d := m.Vec2{dim_x, p1.y}
    dim2_2d := m.Vec2{dim_x, p2.y}

    dim1_3d := sketch.sketch_to_world(&sk.plane, dim1_2d)
    dim2_3d := sketch.sketch_to_world(&sk.plane, dim2_2d)

    // Build dimension lines
    dim_lines := make([dynamic][2][3]f32, context.temp_allocator)

    // Horizontal extension line from p1 to dimension line
    p1_3d := sketch.sketch_to_world(&sk.plane, p1_2d)
    append(&dim_lines, [2][3]f32{
        {f32(p1_3d.x), f32(p1_3d.y), f32(p1_3d.z)},
        {f32(dim1_3d.x), f32(dim1_3d.y), f32(dim1_3d.z)},
    })

    // Horizontal extension line from p2 to dimension line
    p2_3d := sketch.sketch_to_world(&sk.plane, p2_2d)
    append(&dim_lines, [2][3]f32{
        {f32(p2_3d.x), f32(p2_3d.y), f32(p2_3d.z)},
        {f32(dim2_3d.x), f32(dim2_3d.y), f32(dim2_3d.z)},
    })

    // Calculate text dimensions for gap
    text_size: f32 = 20
    text_gap_world: f64 = 0.5  // Default gap size
    text_width_pixels: f32 = 0
    text_height_pixels: f32 = 0

    if text_renderer != nil {
        dist_text := fmt.tprintf("%.2f", math.abs(data.distance))
        text_width_pixels, text_height_pixels = text_measure_gpu(text_renderer, dist_text, text_size)

        pixel_size_world := f64(get_pixel_size_world(viewer))

        // For vertical dimensions, the gap along Y-axis must account for text WIDTH
        // (text is horizontal but placed along a vertical line, so its width spans the Y gap)
        // Use larger multiplier (4.0) to ensure arrows don't overlap with horizontal text
        text_gap_world = f64(text_width_pixels) * pixel_size_world * 4.0
    }

    // Calculate gap positions (centered on Y midpoint)
    mid_y := (p1.y + p2.y) * 0.5
    gap_half := text_gap_world * 0.5
    gap_start_2d := m.Vec2{dim_x, mid_y - gap_half}
    gap_end_2d := m.Vec2{dim_x, mid_y + gap_half}

    // Calculate dimension line length to check if gap fits
    dim_line_len := glsl.abs(dim2_2d.y - dim1_2d.y)
    gap_total_width := text_gap_world

    // Only draw gap if it fits within the dimension line
    if gap_total_width < dim_line_len - 0.02 {
        // Gap fits - draw dimension line with gap (split into two segments)
        gap_start_3d := sketch.sketch_to_world(&sk.plane, gap_start_2d)
        append(&dim_lines, [2][3]f32{
            {f32(dim1_3d.x), f32(dim1_3d.y), f32(dim1_3d.z)},
            {f32(gap_start_3d.x), f32(gap_start_3d.y), f32(gap_start_3d.z)},
        })

        gap_end_3d := sketch.sketch_to_world(&sk.plane, gap_end_2d)
        append(&dim_lines, [2][3]f32{
            {f32(gap_end_3d.x), f32(gap_end_3d.y), f32(gap_end_3d.z)},
            {f32(dim2_3d.x), f32(dim2_3d.y), f32(dim2_3d.z)},
        })
    } else {
        // Gap too wide - draw full line without gap
        append(&dim_lines, [2][3]f32{
            {f32(dim1_3d.x), f32(dim1_3d.y), f32(dim1_3d.z)},
            {f32(dim2_3d.x), f32(dim2_3d.y), f32(dim2_3d.z)},
        })
    }

    // Arrow heads (vertical direction)
    // Calculate actual direction from dim1 to dim2
    dim_vec := dim2_2d - dim1_2d
    dim_len := glsl.length(dim_vec)
    dim_dir := m.Vec2{0.0, 1.0}
    if dim_len > 0.001 {
        dim_dir = dim_vec / dim_len
    }

    // Arrow head size - scale with camera distance for consistent screen size
    camera_distance := glsl.length(viewer.camera.position - viewer.camera.target)
    ARROW_BASE_SIZE :: 1.5  // Base size in mm
    arrow_size := ARROW_BASE_SIZE * (camera_distance / 100.0)
    ARROW_ANGLE :: 30.0

    arrow_lines := render_dimension_arrow_heads(sk, dim1_2d, dim2_2d, dim_dir, arrow_size, ARROW_ANGLE)
    for arrow_line in arrow_lines {
        append(&dim_lines, arrow_line)
    }

    // Draw dimension lines
    dim_color := is_selected ? [4]f32{1.0, 1.0, 1.0, 1.0} : [4]f32{1.0, 1.0, 0.0, 1.0}
    viewer_gpu_render_thick_lines(viewer, cmd, pass, dim_lines[:], dim_color, mvp, 1.5)

    // Render dimension text
    if text_renderer != nil {
        mid_dim_3d := (dim1_3d + dim2_3d) * 0.5
        clip_pos := proj * view * glsl.vec4{f32(mid_dim_3d.x), f32(mid_dim_3d.y), f32(mid_dim_3d.z), 1.0}

        if clip_pos.w != 0.0 {
            ndc := clip_pos.xyz / clip_pos.w
            screen_x := (ndc.x + 1.0) * 0.5 * f32(viewer.window_width)
            screen_y := (1.0 - ndc.y) * 0.5 * f32(viewer.window_height)

            dist_text := fmt.tprintf("%.2f", math.abs(data.distance))
            text_offset_x := text_width_pixels * 0.5
            text_offset_y := text_height_pixels * 0.5

            text_color := is_selected ? [4]u8{255, 255, 255, 255} : [4]u8{255, 255, 0, 255}
            text_render_2d_gpu(text_renderer, cmd, pass, dist_text, screen_x - text_offset_x, screen_y - text_offset_y, text_size, text_color, viewer.window_width, viewer.window_height)
        }
    }
}

// Render angular dimension with arc and angle text
render_angular_dimension_gpu :: proc(
    viewer: ^ViewerGPU,
    cmd: ^sdl.GPUCommandBuffer,
    pass: ^sdl.GPURenderPass,
    text_renderer: ^TextRendererGPU,
    sk: ^sketch.Sketch2D,
    data: sketch.AngleData,
    mvp: matrix[4,4]f32,
    view: matrix[4,4]f32,
    proj: matrix[4,4]f32,
    is_selected: bool,
) {
    if data.line1_id < 0 || data.line1_id >= len(sk.entities) do return
    if data.line2_id < 0 || data.line2_id >= len(sk.entities) do return

    entity1 := sk.entities[data.line1_id]
    entity2 := sk.entities[data.line2_id]

    line1, ok1 := entity1.(sketch.SketchLine)
    line2, ok2 := entity2.(sketch.SketchLine)
    if !ok1 || !ok2 do return

    p1_start := sketch.sketch_get_point(sk, line1.start_id)
    p1_end := sketch.sketch_get_point(sk, line1.end_id)
    p2_start := sketch.sketch_get_point(sk, line2.start_id)
    p2_end := sketch.sketch_get_point(sk, line2.end_id)

    if p1_start == nil || p1_end == nil || p2_start == nil || p2_end == nil do return

    p1_start_2d := m.Vec2{p1_start.x, p1_start.y}
    p1_end_2d := m.Vec2{p1_end.x, p1_end.y}
    p2_start_2d := m.Vec2{p2_start.x, p2_start.y}
    p2_end_2d := m.Vec2{p2_end.x, p2_end.y}

    // Find shared corner (intersection point)
    center_2d: m.Vec2
    EPSILON :: 0.001

    if glsl.length(p1_start_2d - p2_start_2d) < EPSILON {
        center_2d = p1_start_2d
    } else if glsl.length(p1_start_2d - p2_end_2d) < EPSILON {
        center_2d = p1_start_2d
    } else if glsl.length(p1_end_2d - p2_start_2d) < EPSILON {
        center_2d = p1_end_2d
    } else if glsl.length(p1_end_2d - p2_end_2d) < EPSILON {
        center_2d = p1_end_2d
    } else {
        return
    }

    // Calculate direction vectors from shared corner
    v1 := p1_end_2d - p1_start_2d
    v2 := p2_end_2d - p2_start_2d

    len_v1 := glsl.length(v1)
    len_v2 := glsl.length(v2)

    if len_v1 < 1e-10 || len_v2 < 1e-10 do return

    v1 = v1 / len_v1
    v2 = v2 / len_v2

    // Determine which direction each line points FROM the shared corner
    v1_from_corner := v1
    v2_from_corner := v2

    dist_to_p1_start := glsl.length(center_2d - p1_start_2d)
    dist_to_p1_end := glsl.length(center_2d - p1_end_2d)

    if dist_to_p1_start < 0.001 {
        v1_from_corner = v1
    } else if dist_to_p1_end < 0.001 {
        v1_from_corner = -v1
    }

    dist_to_p2_start := glsl.length(center_2d - p2_start_2d)
    dist_to_p2_end := glsl.length(center_2d - p2_end_2d)

    if dist_to_p2_start < 0.001 {
        v2_from_corner = v2
    } else if dist_to_p2_end < 0.001 {
        v2_from_corner = -v2
    }

    // Calculate arc radius based on offset position
    to_offset := data.offset - center_2d
    radius := glsl.length(to_offset)

    MIN_RADIUS :: 0.3
    MAX_RADIUS :: 3.0
    radius = glsl.clamp(radius, MIN_RADIUS, MAX_RADIUS)

    // Calculate angles for the edge directions (same quadrant logic as preview)
    a1 := math.atan2(f64(v1_from_corner.y), f64(v1_from_corner.x))
    a2 := math.atan2(f64(v2_from_corner.y), f64(v2_from_corner.x))
    a1_neg := a1 + math.PI
    a2_neg := a2 + math.PI
    a_cursor := math.atan2(f64(to_offset.y), f64(to_offset.x))

    // Normalize all angles to [0, 2π]
    normalize_angle :: proc(a: f64) -> f64 {
        result := a
        for result < 0 do result += 2.0 * math.PI
        for result >= 2.0 * math.PI do result -= 2.0 * math.PI
        return result
    }

    a1 = normalize_angle(a1)
    a2 = normalize_angle(a2)
    a1_neg = normalize_angle(a1_neg)
    a2_neg = normalize_angle(a2_neg)
    a_cursor = normalize_angle(a_cursor)

    // Determine which pair of vectors to use for the arc
    arc_start, arc_end: f64

    // Test all 4 possible arcs - test if cursor is in CCW arc from start to end
    {
        sweep := a2 - a1
        if sweep < 0 do sweep += 2.0 * math.PI
        offset := a_cursor - a1
        if offset < 0 do offset += 2.0 * math.PI
        if offset <= sweep {
            arc_start = a1
            arc_end = a2
        } else {
            sweep2 := a1_neg - a2
            if sweep2 < 0 do sweep2 += 2.0 * math.PI
            offset2 := a_cursor - a2
            if offset2 < 0 do offset2 += 2.0 * math.PI
            if offset2 <= sweep2 {
                arc_start = a2
                arc_end = a1_neg
            } else {
                sweep3 := a2_neg - a1_neg
                if sweep3 < 0 do sweep3 += 2.0 * math.PI
                offset3 := a_cursor - a1_neg
                if offset3 < 0 do offset3 += 2.0 * math.PI
                if offset3 <= sweep3 {
                    arc_start = a1_neg
                    arc_end = a2_neg
                } else {
                    arc_start = a2_neg
                    arc_end = a1
                }
            }
        }
    }

    // Calculate CCW sweep angle
    start_angle := arc_start
    sweep_angle := arc_end - arc_start
    if sweep_angle < 0 do sweep_angle += 2.0 * math.PI

    // Tessellate arc into line segments (24 segments for smooth arc)
    segments := 24
    arc_lines := make([dynamic][2][3]f32, context.temp_allocator)

    for i in 0..<segments {
        t0 := f64(i) / f64(segments)
        t1 := f64(i + 1) / f64(segments)

        angle0 := start_angle + sweep_angle * t0
        angle1 := start_angle + sweep_angle * t1

        p0_2d := center_2d + m.Vec2{radius * math.cos(angle0), radius * math.sin(angle0)}
        p1_2d := center_2d + m.Vec2{radius * math.cos(angle1), radius * math.sin(angle1)}

        p0_3d := sketch.sketch_to_world(&sk.plane, p0_2d)
        p1_3d := sketch.sketch_to_world(&sk.plane, p1_2d)

        append(&arc_lines, [2][3]f32{
            {f32(p0_3d.x), f32(p0_3d.y), f32(p0_3d.z)},
            {f32(p1_3d.x), f32(p1_3d.y), f32(p1_3d.z)},
        })
    }

    // Draw arc in bright yellow (or white if selected)
    arc_color := is_selected ? [4]f32{1.0, 1.0, 1.0, 1.0} : [4]f32{1.0, 1.0, 0.0, 1.0}
    viewer_gpu_render_thick_lines(viewer, cmd, pass, arc_lines[:], arc_color, mvp, 1.5)

    // Render angle text value
    if text_renderer != nil {
        // Calculate midpoint of arc in 3D
        mid_angle := start_angle + sweep_angle * 0.5
        mid_radius := radius * 1.3
        mid_2d := center_2d + m.Vec2{mid_radius * math.cos(mid_angle), mid_radius * math.sin(mid_angle)}
        mid_3d := sketch.sketch_to_world(&sk.plane, mid_2d)

        // Project 3D midpoint to screen space
        clip_pos := proj * view * glsl.vec4{f32(mid_3d.x), f32(mid_3d.y), f32(mid_3d.z), 1.0}

        if clip_pos.w != 0.0 {
            ndc := clip_pos.xyz / clip_pos.w
            screen_x := (ndc.x + 1.0) * 0.5 * f32(viewer.window_width)
            screen_y := (1.0 - ndc.y) * 0.5 * f32(viewer.window_height)

            // Format angle value as string (data.angle is already in degrees)
            angle_text := fmt.tprintf("%.1f°", data.angle)

            // Render text at screen position (bright yellow to match arc)
            text_color := is_selected ? [4]u8{255, 255, 255, 255} : [4]u8{255, 255, 0, 255}
            text_render_2d_gpu(text_renderer, cmd, pass, angle_text, screen_x, screen_y, 16, text_color, viewer.window_width, viewer.window_height)
        }
    }
}

// =============================================================================
// SimpleSolid to Wireframe Conversion
// =============================================================================

// Convert SimpleSolid to wireframe mesh for rendering (GPU version)
solid_to_wireframe_gpu :: proc(solid: ^extrude.SimpleSolid) -> WireframeMeshGPU {
    mesh := wireframe_mesh_gpu_init()

    if solid == nil {
        return mesh
    }

    // Add all edges from solid
    for edge in solid.edges {
        if edge.v0 != nil && edge.v1 != nil {
            wireframe_mesh_gpu_add_edge_f64(&mesh, edge.v0.position, edge.v1.position)
        }
    }

    return mesh
}

// =============================================================================
// Initialization
// =============================================================================

viewer_gpu_init :: proc(config: ViewerGPUConfig = DEFAULT_GPU_CONFIG) -> (^ViewerGPU, bool) {
    fmt.println("=== Initializing SDL3 GPU Viewer ===\n")

    // Set hint BEFORE SDL_Init to treat trackpad as touch device
    // This enables FINGER_* events for Blender-style gestures!
    sdl.SetHint(sdl.HINT_TRACKPAD_IS_TOUCH_ONLY, "1")
    fmt.println("✓ Trackpad configured for touch events (Blender-style gestures)")

    // Initialize SDL3
    if !sdl.Init({.VIDEO}) {
        fmt.eprintln("ERROR: Failed to initialize SDL3:", sdl.GetError())
        return nil, false
    }

    fmt.println("✓ SDL3 initialized")

    // Create window
    window := sdl.CreateWindow(
        config.window_title,
        config.window_width,
        config.window_height,
        {.RESIZABLE},
    )

    if window == nil {
        fmt.eprintln("ERROR: Failed to create window:", sdl.GetError())
        sdl.Quit()
        return nil, false
    }

    fmt.println("✓ Window created")

    // macOS: Raise window and give it keyboard focus
    _ = sdl.RaiseWindow(window)
    _ = sdl.SetWindowKeyboardGrab(window, true)

    // Create GPU device (Metal on macOS)
    gpu_device := sdl.CreateGPUDevice(
        {.METALLIB},
        false,
        nil,
    )

    if gpu_device == nil {
        fmt.eprintln("ERROR: Failed to create GPU device:", sdl.GetError())
        sdl.DestroyWindow(window)
        sdl.Quit()
        return nil, false
    }

    driver := sdl.GetGPUDeviceDriver(gpu_device)
    fmt.printf("✓ GPU device created (%s backend)\n", driver)

    // Claim window for GPU rendering
    if !sdl.ClaimWindowForGPUDevice(gpu_device, window) {
        fmt.eprintln("ERROR: Failed to claim window for GPU:", sdl.GetError())
        sdl.DestroyGPUDevice(gpu_device)
        sdl.DestroyWindow(window)
        sdl.Quit()
        return nil, false
    }

    fmt.println("✓ Window claimed for GPU rendering")

    // Load shaders
    shader_data, shader_ok := os.read_entire_file(config.shader_path)
    if !shader_ok {
        fmt.eprintln("ERROR: Failed to read metallib file:", config.shader_path)
        sdl.DestroyGPUDevice(gpu_device)
        sdl.DestroyWindow(window)
        sdl.Quit()
        return nil, false
    }
    defer delete(shader_data)

    fmt.printf("✓ Loaded shaders: %s (%d bytes)\n", config.shader_path, len(shader_data))

    // Create vertex shader
    vertex_shader_info := sdl.GPUShaderCreateInfo{
        code = raw_data(shader_data),
        code_size = len(shader_data),
        entrypoint = "vertex_main",
        format = {.METALLIB},
        stage = .VERTEX,
        num_uniform_buffers = 1,
        num_storage_buffers = 0,
    }

    vertex_shader := sdl.CreateGPUShader(gpu_device, vertex_shader_info)
    if vertex_shader == nil {
        fmt.eprintln("ERROR: Failed to create vertex shader:", sdl.GetError())
        sdl.DestroyGPUDevice(gpu_device)
        sdl.DestroyWindow(window)
        sdl.Quit()
        return nil, false
    }

    // Create fragment shader
    fragment_shader_info := sdl.GPUShaderCreateInfo{
        code = raw_data(shader_data),
        code_size = len(shader_data),
        entrypoint = "fragment_main",
        format = {.METALLIB},
        stage = .FRAGMENT,
        num_uniform_buffers = 1,
        num_storage_buffers = 0,
    }

    fragment_shader := sdl.CreateGPUShader(gpu_device, fragment_shader_info)
    if fragment_shader == nil {
        fmt.eprintln("ERROR: Failed to create fragment shader:", sdl.GetError())
        sdl.ReleaseGPUShader(gpu_device, vertex_shader)
        sdl.DestroyGPUDevice(gpu_device)
        sdl.DestroyWindow(window)
        sdl.Quit()
        return nil, false
    }

    fmt.println("✓ Shaders created")

    // Create graphics pipeline
    vertex_attribute := sdl.GPUVertexAttribute{
        location = 0,
        format = .FLOAT3,
        offset = 0,
    }

    vertex_binding := sdl.GPUVertexBufferDescription{
        slot = 0,
        pitch = size_of(LineVertex),
        input_rate = .VERTEX,
    }

    vertex_input_state := sdl.GPUVertexInputState{
        vertex_buffer_descriptions = &vertex_binding,
        num_vertex_buffers = 1,
        vertex_attributes = &vertex_attribute,
        num_vertex_attributes = 1,
    }

    color_target := sdl.GPUColorTargetDescription{
        format = sdl.GetGPUSwapchainTextureFormat(gpu_device, window),
        blend_state = {
            enable_blend = false,
            alpha_blend_op = .ADD,
            color_blend_op = .ADD,
            src_color_blendfactor = .ONE,
            src_alpha_blendfactor = .ONE,
            dst_color_blendfactor = .ZERO,
            dst_alpha_blendfactor = .ZERO,
        },
    }

    pipeline_info := sdl.GPUGraphicsPipelineCreateInfo{
        vertex_shader = vertex_shader,
        fragment_shader = fragment_shader,
        vertex_input_state = vertex_input_state,
        primitive_type = .LINELIST,  // For line rendering
        rasterizer_state = {
            fill_mode = .FILL,
            cull_mode = .NONE,
            front_face = .COUNTER_CLOCKWISE,
        },
        multisample_state = {
            sample_count = ._4,  // 4x MSAA for antialiasing
            sample_mask = 0xFFFFFFFF,
        },
        target_info = {
            num_color_targets = 1,
            color_target_descriptions = &color_target,
            has_depth_stencil_target = false,
        },
    }

    pipeline := sdl.CreateGPUGraphicsPipeline(gpu_device, pipeline_info)
    if pipeline == nil {
        fmt.eprintln("ERROR: Failed to create graphics pipeline:", sdl.GetError())
        sdl.ReleaseGPUShader(gpu_device, fragment_shader)
        sdl.ReleaseGPUShader(gpu_device, vertex_shader)
        sdl.DestroyGPUDevice(gpu_device)
        sdl.DestroyWindow(window)
        sdl.Quit()
        return nil, false
    }

    fmt.println("✓ Graphics pipeline created")

    // Create triangle pipeline for thick lines and UI (same shaders, different primitive type)
    // Enable alpha blending for transparency (profile fills)
    triangle_color_target := sdl.GPUColorTargetDescription{
        format = sdl.GetGPUSwapchainTextureFormat(gpu_device, window),
        blend_state = {
            enable_blend = true,
            alpha_blend_op = .ADD,
            color_blend_op = .ADD,
            src_color_blendfactor = .SRC_ALPHA,
            dst_color_blendfactor = .ONE_MINUS_SRC_ALPHA,
            src_alpha_blendfactor = .ONE,
            dst_alpha_blendfactor = .ONE_MINUS_SRC_ALPHA,
        },
    }

    triangle_pipeline_info := sdl.GPUGraphicsPipelineCreateInfo{
        vertex_shader = vertex_shader,
        fragment_shader = fragment_shader,
        vertex_input_state = vertex_input_state,
        primitive_type = .TRIANGLELIST,  // For thick line quads and UI widgets
        rasterizer_state = {
            fill_mode = .FILL,
            cull_mode = .NONE,
            front_face = .COUNTER_CLOCKWISE,
        },
        multisample_state = {
            sample_count = ._4,  // 4x MSAA for antialiasing
            sample_mask = 0xFFFFFFFF,
        },
        depth_stencil_state = {
            // Disable depth testing for UI widgets - always render on top
            enable_depth_test = false,
            enable_depth_write = false,
            enable_stencil_test = false,
        },
        target_info = {
            num_color_targets = 1,
            color_target_descriptions = &triangle_color_target,
            has_depth_stencil_target = true,  // Match render pass
            depth_stencil_format = .D16_UNORM,
        },
    }

    triangle_pipeline := sdl.CreateGPUGraphicsPipeline(gpu_device, triangle_pipeline_info)
    if triangle_pipeline == nil {
        fmt.eprintln("ERROR: Failed to create triangle pipeline:", sdl.GetError())
        sdl.ReleaseGPUGraphicsPipeline(gpu_device, pipeline)
        sdl.ReleaseGPUShader(gpu_device, fragment_shader)
        sdl.ReleaseGPUShader(gpu_device, vertex_shader)
        sdl.DestroyGPUDevice(gpu_device)
        sdl.DestroyWindow(window)
        sdl.Quit()
        return nil, false
    }

    fmt.println("✓ Triangle pipeline created (for thick lines)")

    // Create wireframe pipeline (same as triangle pipeline but with depth testing enabled)
    wireframe_pipeline_info := sdl.GPUGraphicsPipelineCreateInfo{
        vertex_shader = vertex_shader,
        fragment_shader = fragment_shader,
        vertex_input_state = vertex_input_state,
        primitive_type = .TRIANGLELIST,
        rasterizer_state = {
            fill_mode = .FILL,
            cull_mode = .NONE,
            front_face = .COUNTER_CLOCKWISE,
        },
        multisample_state = {
            sample_count = ._4,
            sample_mask = 0xFFFFFFFF,
        },
        depth_stencil_state = {
            // Enable depth testing for wireframe overlay - respects geometry occlusion
            enable_depth_test = true,
            enable_depth_write = false,  // Don't write to depth buffer (overlay only)
            compare_op = .LESS_OR_EQUAL,  // Render if depth <= existing (allows co-planar edges)
            enable_stencil_test = false,
        },
        target_info = {
            num_color_targets = 1,
            color_target_descriptions = &triangle_color_target,
            has_depth_stencil_target = true,
            depth_stencil_format = .D16_UNORM,
        },
    }

    wireframe_pipeline := sdl.CreateGPUGraphicsPipeline(gpu_device, wireframe_pipeline_info)
    if wireframe_pipeline == nil {
        fmt.eprintln("ERROR: Failed to create wireframe pipeline:", sdl.GetError())
        sdl.ReleaseGPUGraphicsPipeline(gpu_device, triangle_pipeline)
        sdl.ReleaseGPUGraphicsPipeline(gpu_device, pipeline)
        sdl.ReleaseGPUShader(gpu_device, fragment_shader)
        sdl.ReleaseGPUShader(gpu_device, vertex_shader)
        sdl.DestroyGPUDevice(gpu_device)
        sdl.DestroyWindow(window)
        sdl.Quit()
        return nil, false
    }

    fmt.println("✓ Wireframe pipeline created (depth-tested overlay)")

    // Create viewer (will be assigned in branches below)
    viewer := new(ViewerGPU)
    viewer.window = window
    viewer.gpu_device = gpu_device
    viewer.vertex_shader = vertex_shader
    viewer.fragment_shader = fragment_shader
    viewer.pipeline = pipeline
    viewer.triangle_pipeline = triangle_pipeline
    viewer.wireframe_pipeline = wireframe_pipeline

    // Load triangle shaders for shaded rendering
    triangle_shader_path := "src/ui/viewer/shaders/triangle_shader.metallib"
    triangle_shader_data, triangle_shader_ok := os.read_entire_file(triangle_shader_path)
    if !triangle_shader_ok {
        fmt.eprintln("WARNING: Failed to read triangle shader, shaded rendering will be disabled:", triangle_shader_path)
        // Continue without shaded rendering support
        viewer.triangle_vertex_shader = nil
        viewer.triangle_fragment_shader = nil
        viewer.shaded_pipeline = nil
    } else {
        defer delete(triangle_shader_data)
        fmt.printf("✓ Loaded triangle shaders: %s (%d bytes)\n", triangle_shader_path, len(triangle_shader_data))

        // Create triangle vertex shader
        tri_vertex_shader_info := sdl.GPUShaderCreateInfo{
            code = raw_data(triangle_shader_data),
            code_size = len(triangle_shader_data),
            entrypoint = "triangle_vertex_main",
            format = {.METALLIB},
            stage = .VERTEX,
            num_uniform_buffers = 1,
        }

        tri_vertex_shader := sdl.CreateGPUShader(gpu_device, tri_vertex_shader_info)
        if tri_vertex_shader == nil {
            fmt.eprintln("WARNING: Failed to create triangle vertex shader, shaded rendering disabled:", sdl.GetError())
        }

        // Create triangle fragment shader
        tri_fragment_shader_info := sdl.GPUShaderCreateInfo{
            code = raw_data(triangle_shader_data),
            code_size = len(triangle_shader_data),
            entrypoint = "triangle_fragment_main",
            format = {.METALLIB},
            stage = .FRAGMENT,
            num_uniform_buffers = 1,
        }

        tri_fragment_shader := sdl.CreateGPUShader(gpu_device, tri_fragment_shader_info)
        if tri_fragment_shader == nil {
            fmt.eprintln("WARNING: Failed to create triangle fragment shader, shaded rendering disabled:", sdl.GetError())
            if tri_vertex_shader != nil {
                sdl.ReleaseGPUShader(gpu_device, tri_vertex_shader)
            }
        }

        if tri_vertex_shader != nil && tri_fragment_shader != nil {
            fmt.println("✓ Triangle shaders created")

            // Create shaded rendering pipeline (for lit triangles)
            tri_vertex_attributes := []sdl.GPUVertexAttribute{
                {location = 0, format = .FLOAT3, offset = 0},  // position
                {location = 1, format = .FLOAT3, offset = 12}, // normal
            }

            tri_vertex_binding := sdl.GPUVertexBufferDescription{
                slot = 0,
                pitch = size_of(TriangleVertex),
                input_rate = .VERTEX,
            }

            tri_vertex_input_state := sdl.GPUVertexInputState{
                vertex_buffer_descriptions = &tri_vertex_binding,
                num_vertex_buffers = 1,
                vertex_attributes = raw_data(tri_vertex_attributes),
                num_vertex_attributes = u32(len(tri_vertex_attributes)),
            }

            shaded_pipeline_info := sdl.GPUGraphicsPipelineCreateInfo{
                vertex_shader = tri_vertex_shader,
                fragment_shader = tri_fragment_shader,
                vertex_input_state = tri_vertex_input_state,
                primitive_type = .TRIANGLELIST,
                rasterizer_state = {
                    fill_mode = .FILL,
                    cull_mode = .NONE,  // Disable backface culling (for debugging normals)
                    front_face = .COUNTER_CLOCKWISE,
                },
                depth_stencil_state = {
                    compare_op = .LESS,  // Pass depth test if fragment is closer
                    enable_depth_test = true,
                    enable_depth_write = true,
                    enable_stencil_test = false,
                },
                target_info = {
                    num_color_targets = 1,
                    color_target_descriptions = &color_target,
                    has_depth_stencil_target = true,
                    depth_stencil_format = .D16_UNORM,  // 16-bit depth buffer
                },
            }

            shaded_pipeline := sdl.CreateGPUGraphicsPipeline(gpu_device, shaded_pipeline_info)
            if shaded_pipeline == nil {
                fmt.eprintln("WARNING: Failed to create shaded pipeline, shaded rendering disabled:", sdl.GetError())
                sdl.ReleaseGPUShader(gpu_device, tri_fragment_shader)
                sdl.ReleaseGPUShader(gpu_device, tri_vertex_shader)
                viewer.triangle_vertex_shader = nil
                viewer.triangle_fragment_shader = nil
                viewer.shaded_pipeline = nil
            } else {
                fmt.println("✓ Shaded rendering pipeline created")
                viewer.triangle_vertex_shader = tri_vertex_shader
                viewer.triangle_fragment_shader = tri_fragment_shader
                viewer.shaded_pipeline = shaded_pipeline
            }
        } else {
            // Fall back to no shaded rendering
            fmt.println("⚠ Shaded rendering will not be available")
            viewer.triangle_vertex_shader = nil
            viewer.triangle_fragment_shader = nil
            viewer.shaded_pipeline = nil
        }
    }
    viewer.window = window
    viewer.gpu_device = gpu_device
    viewer.vertex_shader = vertex_shader
    viewer.fragment_shader = fragment_shader
    viewer.pipeline = pipeline
    viewer.triangle_pipeline = triangle_pipeline
    viewer.should_close = false
    viewer.window_width = u32(config.window_width)
    viewer.window_height = u32(config.window_height)
    viewer.render_mode = .Wireframe  // Default to wireframe mode

    // Initialize camera
    aspect_ratio := f32(config.window_width) / f32(config.window_height)
    camera_init(&viewer.camera, aspect_ratio)

    // Initialize multi-touch tracking
    viewer.active_fingers = make(map[sdl.FingerID]TouchPoint)
    viewer.shift_held = false

    // Create coordinate axes vertex buffer
    if !viewer_gpu_create_axes(viewer) {
        fmt.eprintln("ERROR: Failed to create axes vertex buffer")
        viewer_gpu_destroy(viewer)
        return nil, false
    }

    // Create grid for ground plane (100mm size for millimeter-scale parts)
    if !viewer_gpu_create_grid(viewer, 100.0, 20) {
        fmt.eprintln("ERROR: Failed to create grid vertex buffer")
        viewer_gpu_destroy(viewer)
        return nil, false
    }

    fmt.println("✓ Coordinate axes and grid created\n")
    fmt.println("=== SDL3 GPU Viewer initialized successfully ===")
    fmt.println("Controls:")
    fmt.println("  Middle Mouse: Orbit camera")
    fmt.println("  Right Mouse: Pan camera")
    fmt.println("  Scroll Wheel: Zoom camera")
    fmt.println("  Trackpad 2-finger drag: Orbit camera (Blender-style)")
    fmt.println("  Trackpad 2-finger pinch: Zoom camera")
    fmt.println("  Trackpad 2-finger drag + SHIFT: Pan camera")
    fmt.println("  HOME: Reset camera")
    fmt.println("  ESC / Q: Quit\n")

    return viewer, true
}

// Create coordinate axes vertex buffer
viewer_gpu_create_axes :: proc(viewer: ^ViewerGPU) -> bool {
    // Define axes vertices (X=red, Y=green, Z=blue)
    axes_length: f32 = 3.0

    axes_vertices := []LineVertex{
        // X axis (red) - origin to +X
        {{0, 0, 0}},
        {{axes_length, 0, 0}},

        // Y axis (green) - origin to +Y
        {{0, 0, 0}},
        {{0, axes_length, 0}},

        // Z axis (blue) - origin to +Z
        {{0, 0, 0}},
        {{0, 0, axes_length}},
    }

    viewer.axes_vertex_count = u32(len(axes_vertices))

    // Create vertex buffer
    buffer_info := sdl.GPUBufferCreateInfo{
        usage = {.VERTEX},
        size = u32(len(axes_vertices) * size_of(LineVertex)),
    }

    vertex_buffer := sdl.CreateGPUBuffer(viewer.gpu_device, buffer_info)
    if vertex_buffer == nil {
        fmt.eprintln("ERROR: Failed to create axes vertex buffer:", sdl.GetError())
        return false
    }

    // Upload vertex data via transfer buffer
    transfer_info := sdl.GPUTransferBufferCreateInfo{
        usage = .UPLOAD,
        size = u32(len(axes_vertices) * size_of(LineVertex)),
    }

    transfer_buffer := sdl.CreateGPUTransferBuffer(viewer.gpu_device, transfer_info)
    if transfer_buffer == nil {
        fmt.eprintln("ERROR: Failed to create transfer buffer:", sdl.GetError())
        sdl.ReleaseGPUBuffer(viewer.gpu_device, vertex_buffer)
        return false
    }
    defer sdl.ReleaseGPUTransferBuffer(viewer.gpu_device, transfer_buffer)

    // Map and copy vertex data
    transfer_ptr := sdl.MapGPUTransferBuffer(viewer.gpu_device, transfer_buffer, false)
    if transfer_ptr == nil {
        fmt.eprintln("ERROR: Failed to map transfer buffer")
        sdl.ReleaseGPUBuffer(viewer.gpu_device, vertex_buffer)
        return false
    }

    dest_slice := ([^]LineVertex)(transfer_ptr)[:len(axes_vertices)]
    copy(dest_slice, axes_vertices)
    sdl.UnmapGPUTransferBuffer(viewer.gpu_device, transfer_buffer)

    // Upload to GPU
    cmd := sdl.AcquireGPUCommandBuffer(viewer.gpu_device)
    copy_pass := sdl.BeginGPUCopyPass(cmd)

    src := sdl.GPUTransferBufferLocation{
        transfer_buffer = transfer_buffer,
        offset = 0,
    }

    dst := sdl.GPUBufferRegion{
        buffer = vertex_buffer,
        offset = 0,
        size = u32(len(axes_vertices) * size_of(LineVertex)),
    }

    sdl.UploadToGPUBuffer(copy_pass, src, dst, false)
    sdl.EndGPUCopyPass(copy_pass)
    _ = sdl.SubmitGPUCommandBuffer(cmd)

    viewer.axes_vertex_buffer = vertex_buffer
    return true
}

// Create grid vertex buffer
viewer_gpu_create_grid :: proc(viewer: ^ViewerGPU, size: f32 = 10.0, divisions: i32 = 20) -> bool {
    // Generate grid vertices on XZ plane
    vertices := make([dynamic]LineVertex, context.temp_allocator)

    step := size / f32(divisions)
    half_size := size * 0.5

    // Grid lines parallel to X axis
    for i in 0..=divisions {
        z := -half_size + f32(i) * step
        append(&vertices, LineVertex{{-half_size, 0, z}})
        append(&vertices, LineVertex{{half_size, 0, z}})
    }

    // Grid lines parallel to Z axis
    for i in 0..=divisions {
        x := -half_size + f32(i) * step
        append(&vertices, LineVertex{{x, 0, -half_size}})
        append(&vertices, LineVertex{{x, 0, half_size}})
    }

    viewer.grid_vertex_count = u32(len(vertices))

    // Create vertex buffer
    buffer_info := sdl.GPUBufferCreateInfo{
        usage = {.VERTEX},
        size = u32(len(vertices) * size_of(LineVertex)),
    }

    vertex_buffer := sdl.CreateGPUBuffer(viewer.gpu_device, buffer_info)
    if vertex_buffer == nil {
        fmt.eprintln("ERROR: Failed to create grid vertex buffer:", sdl.GetError())
        return false
    }

    // Upload vertex data via transfer buffer
    transfer_info := sdl.GPUTransferBufferCreateInfo{
        usage = .UPLOAD,
        size = u32(len(vertices) * size_of(LineVertex)),
    }

    transfer_buffer := sdl.CreateGPUTransferBuffer(viewer.gpu_device, transfer_info)
    if transfer_buffer == nil {
        fmt.eprintln("ERROR: Failed to create transfer buffer:", sdl.GetError())
        sdl.ReleaseGPUBuffer(viewer.gpu_device, vertex_buffer)
        return false
    }
    defer sdl.ReleaseGPUTransferBuffer(viewer.gpu_device, transfer_buffer)

    // Map and copy vertex data
    transfer_ptr := sdl.MapGPUTransferBuffer(viewer.gpu_device, transfer_buffer, false)
    if transfer_ptr == nil {
        fmt.eprintln("ERROR: Failed to map transfer buffer")
        sdl.ReleaseGPUBuffer(viewer.gpu_device, vertex_buffer)
        return false
    }

    dest_slice := ([^]LineVertex)(transfer_ptr)[:len(vertices)]
    copy(dest_slice, vertices[:])
    sdl.UnmapGPUTransferBuffer(viewer.gpu_device, transfer_buffer)

    // Upload to GPU
    cmd := sdl.AcquireGPUCommandBuffer(viewer.gpu_device)
    copy_pass := sdl.BeginGPUCopyPass(cmd)

    src := sdl.GPUTransferBufferLocation{
        transfer_buffer = transfer_buffer,
        offset = 0,
    }

    dst := sdl.GPUBufferRegion{
        buffer = vertex_buffer,
        offset = 0,
        size = u32(len(vertices) * size_of(LineVertex)),
    }

    sdl.UploadToGPUBuffer(copy_pass, src, dst, false)
    sdl.EndGPUCopyPass(copy_pass)
    _ = sdl.SubmitGPUCommandBuffer(cmd)

    viewer.grid_vertex_buffer = vertex_buffer
    return true
}

// =============================================================================
// Destroy
// =============================================================================

viewer_gpu_destroy :: proc(viewer: ^ViewerGPU) {
    if viewer.axes_vertex_buffer != nil {
        sdl.ReleaseGPUBuffer(viewer.gpu_device, viewer.axes_vertex_buffer)
    }

    if viewer.grid_vertex_buffer != nil {
        sdl.ReleaseGPUBuffer(viewer.gpu_device, viewer.grid_vertex_buffer)
    }

    if viewer.triangle_pipeline != nil {
        sdl.ReleaseGPUGraphicsPipeline(viewer.gpu_device, viewer.triangle_pipeline)
    }

    if viewer.wireframe_pipeline != nil {
        sdl.ReleaseGPUGraphicsPipeline(viewer.gpu_device, viewer.wireframe_pipeline)
    }

    if viewer.pipeline != nil {
        sdl.ReleaseGPUGraphicsPipeline(viewer.gpu_device, viewer.pipeline)
    }

    if viewer.fragment_shader != nil {
        sdl.ReleaseGPUShader(viewer.gpu_device, viewer.fragment_shader)
    }

    if viewer.vertex_shader != nil {
        sdl.ReleaseGPUShader(viewer.gpu_device, viewer.vertex_shader)
    }

    if viewer.gpu_device != nil {
        sdl.DestroyGPUDevice(viewer.gpu_device)
    }

    if viewer.window != nil {
        sdl.DestroyWindow(viewer.window)
    }

    delete(viewer.active_fingers)

    sdl.Quit()
    free(viewer)
}

// =============================================================================
// Main Loop
// =============================================================================

viewer_gpu_should_continue :: proc(viewer: ^ViewerGPU) -> bool {
    return !viewer.should_close
}

viewer_gpu_poll_events :: proc(viewer: ^ViewerGPU) {
    event: sdl.Event

    for sdl.PollEvent(&event) {
        #partial switch event.type {
        case .QUIT:
            viewer.should_close = true

        case .KEY_DOWN:
            switch event.key.key {
            case sdl.K_ESCAPE, sdl.K_Q:
                viewer.should_close = true
            case sdl.K_HOME:
                camera_init(&viewer.camera, viewer.camera.aspect_ratio)
            case sdl.K_LSHIFT, sdl.K_RSHIFT:
                viewer.shift_held = true
            }

        case .KEY_UP:
            switch event.key.key {
            case sdl.K_LSHIFT, sdl.K_RSHIFT:
                viewer.shift_held = false
            }

        case .MOUSE_MOTION:
            viewer_gpu_handle_mouse_motion(viewer, &event.motion)

        case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP:
            viewer_gpu_handle_mouse_button(viewer, &event.button)

        case .MOUSE_WHEEL:
            viewer_gpu_handle_mouse_wheel(viewer, &event.wheel)

        case .FINGER_DOWN, .FINGER_UP, .FINGER_MOTION:
            viewer_gpu_handle_finger(viewer, &event)
        }
    }
}

viewer_gpu_render :: proc(viewer: ^ViewerGPU) {
    // Acquire command buffer
    cmd := sdl.AcquireGPUCommandBuffer(viewer.gpu_device)
    if cmd == nil {
        return
    }

    // Acquire swapchain texture
    swapchain: ^sdl.GPUTexture
    w, h: u32
    if !sdl.AcquireGPUSwapchainTexture(cmd, viewer.window, &swapchain, &w, &h) {
        return
    }

    // Update window size if changed
    if w != viewer.window_width || h != viewer.window_height {
        viewer.window_width = w
        viewer.window_height = h
        viewer.camera.aspect_ratio = f32(w) / f32(h)
    }

    if swapchain != nil {
        // Begin render pass
        color_target := sdl.GPUColorTargetInfo{
            texture = swapchain,
            load_op = .CLEAR,
            store_op = .STORE,
            clear_color = {0.08, 0.08, 0.08, 1.0},  // Dark gray background
        }

        pass := sdl.BeginGPURenderPass(cmd, &color_target, 1, nil)

        // Bind pipeline
        sdl.BindGPUGraphicsPipeline(pass, viewer.pipeline)

        // Set viewport
        viewport := sdl.GPUViewport{
            x = 0,
            y = 0,
            w = f32(w),
            h = f32(h),
            min_depth = 0.0,
            max_depth = 1.0,
        }
        sdl.SetGPUViewport(pass, viewport)

        // Set scissor
        scissor := sdl.Rect{
            x = 0,
            y = 0,
            w = i32(w),
            h = i32(h),
        }
        sdl.SetGPUScissor(pass, scissor)

        // Calculate MVP matrix
        view := camera_get_view_matrix(&viewer.camera)
        proj := camera_get_projection_matrix(&viewer.camera)
        mvp := proj * view

        // Render grid first (so it appears behind axes)
        viewer_gpu_render_grid(viewer, cmd, pass, mvp)

        // Render coordinate axes on top
        viewer_gpu_render_axes(viewer, cmd, pass, mvp)

        sdl.EndGPURenderPass(pass)
    }

    // Submit command buffer
    _ = sdl.SubmitGPUCommandBuffer(cmd)
}

// Render coordinate axes (X=red, Y=green, Z=blue) with thick lines
viewer_gpu_render_axes :: proc(viewer: ^ViewerGPU, cmd: ^sdl.GPUCommandBuffer, pass: ^sdl.GPURenderPass, mvp: matrix[4,4]f32) {
    axes_length: f32 = 5.0

    // Define axes as line segments
    x_axis := [][2][3]f32{{{0-axes_length, 0, 0}, {axes_length, 0, 0}}}
    y_axis := [][2][3]f32{{{0, 0, 0}, {0, 1.0, 0}}}
    z_axis := [][2][3]f32{{{0, 0, -axes_length}, {0, 0, axes_length}}}

    // Render with thick lines (4 pixels wide for visibility)
    thickness: f32 = 2.0

    // X axis (red)
    viewer_gpu_render_thick_lines(viewer, cmd, pass, x_axis, {1.0, 0.0, 0.0, 1.0}, mvp, thickness)

    // Y axis (green)
    viewer_gpu_render_thick_lines(viewer, cmd, pass, y_axis, {0.0, 1.0, 0.0, 1.0}, mvp, 1.0)

    // Z axis (blue)
    viewer_gpu_render_thick_lines(viewer, cmd, pass, z_axis, {0.0, 0.0, 1.0, 1.0}, mvp, thickness)
}

// Render grid on XZ plane
viewer_gpu_render_grid :: proc(viewer: ^ViewerGPU, cmd: ^sdl.GPUCommandBuffer, pass: ^sdl.GPURenderPass, mvp: matrix[4,4]f32) {
    // Bind grid vertex buffer
    binding := sdl.GPUBufferBinding{
        buffer = viewer.grid_vertex_buffer,
        offset = 0,
    }
    sdl.BindGPUVertexBuffers(pass, 0, &binding, 1)

    // Draw grid in dark gray (subtle)
    uniforms := Uniforms{
        mvp = mvp,
        color = {0.14, 0.14, 0.14, 0.3},  // Dark gray, slightly transparent
    }
    sdl.PushGPUVertexUniformData(cmd, 0, &uniforms, size_of(Uniforms))
    sdl.PushGPUFragmentUniformData(cmd, 0, &uniforms, size_of(Uniforms))
    sdl.DrawGPUPrimitives(pass, viewer.grid_vertex_count, 1, 0, 0)
}

// =============================================================================
// Input Handlers
// =============================================================================

viewer_gpu_handle_mouse_motion :: proc(viewer: ^ViewerGPU, motion: ^sdl.MouseMotionEvent) {
    dx := f32(motion.xrel)
    dy := f32(motion.yrel)

    // Middle mouse button - orbit (fixed: inverted left-right)
    if viewer.mouse_middle_down {
        sensitivity := f32(0.005)
        viewer.camera.azimuth += dx * sensitivity  // Fixed: + instead of - to uninvert
        viewer.camera.elevation += dy * sensitivity

        // Clamp elevation to avoid gimbal lock
        viewer.camera.elevation = glsl.clamp(viewer.camera.elevation, -math.PI * 0.49, math.PI * 0.49)

        camera_update_position(&viewer.camera)
    }

    // Right mouse button - pan
    if viewer.mouse_right_down {
        sensitivity := f32(0.01)

        // Calculate camera right and up vectors
        view_dir := glsl.normalize(viewer.camera.target - viewer.camera.position)
        right := glsl.normalize(glsl.cross(view_dir, viewer.camera.up))
        up := glsl.cross(right, view_dir)

        // Pan camera
        pan_scale := f64(-dx * sensitivity * viewer.camera.distance * 0.1)
        viewer.camera.target += right * pan_scale
        pan_scale_y := f64(dy * sensitivity * viewer.camera.distance * 0.1)
        viewer.camera.target += up * pan_scale_y

        camera_update_position(&viewer.camera)
    }
}

viewer_gpu_handle_mouse_button :: proc(viewer: ^ViewerGPU, button: ^sdl.MouseButtonEvent) {
    is_down := button.down

    switch button.button {
    case u8(sdl.BUTTON_LEFT):
        viewer.mouse_left_down = is_down
    case u8(sdl.BUTTON_MIDDLE):
        viewer.mouse_middle_down = is_down
    case u8(sdl.BUTTON_RIGHT):
        viewer.mouse_right_down = is_down
    }
}

viewer_gpu_handle_mouse_wheel :: proc(viewer: ^ViewerGPU, wheel: ^sdl.MouseWheelEvent) {
    // Zoom in/out
    zoom_speed := f32(0.1)

    // Update camera distance (for camera positioning)
    viewer.camera.distance -= wheel.y * zoom_speed * viewer.camera.distance
    viewer.camera.distance = glsl.clamp(viewer.camera.distance, 0.5, 1000.0)

    // Update orthographic width (for orthographic zoom)
    if viewer.camera.projection_mode == .Orthographic {
        viewer.camera.ortho_width -= wheel.y * zoom_speed * viewer.camera.ortho_width
        viewer.camera.ortho_width = glsl.clamp(viewer.camera.ortho_width, 1.0, 500.0)
    }

    camera_update_position(&viewer.camera)
}

// Handle multi-touch finger events (Blender-style trackpad gestures)
viewer_gpu_handle_finger :: proc(viewer: ^ViewerGPU, event: ^sdl.Event) {
    #partial switch event.type {
    case .FINGER_DOWN:
        // Add finger to active tracking
        finger_id := event.tfinger.fingerID
        viewer.active_fingers[finger_id] = TouchPoint{
            x = event.tfinger.x,
            y = event.tfinger.y,
        }

        // Reset previous centroid when starting new gesture
        if len(viewer.active_fingers) == 2 {
            viewer.prev_centroid = nil
            viewer.prev_distance = 0
        }

    case .FINGER_UP:
        // Remove finger from active tracking
        finger_id := event.tfinger.fingerID
        delete_key(&viewer.active_fingers, finger_id)

        // Reset gesture state when all fingers lifted
        if len(viewer.active_fingers) == 0 {
            viewer.prev_centroid = nil
            viewer.prev_distance = 0
        }

    case .FINGER_MOTION:
        // Update finger position
        finger_id := event.tfinger.fingerID
        viewer.active_fingers[finger_id] = TouchPoint{
            x = event.tfinger.x,
            y = event.tfinger.y,
        }

        // Handle 2-finger gestures
        if len(viewer.active_fingers) == 2 {
            // Calculate centroid of 2 fingers
            centroid := calculate_centroid(viewer.active_fingers)

            // Calculate distance between 2 fingers (for pinch detection)
            distance := calculate_finger_distance(viewer.active_fingers)

            // First motion event - store initial values
            if viewer.prev_centroid == nil {
                viewer.prev_centroid = centroid
                viewer.prev_distance = distance
                viewer.is_pinching = false
                return
            }

            prev_cent := viewer.prev_centroid.?

            // Calculate centroid movement
            dx := (centroid.x - prev_cent.x) * f32(viewer.window_width)
            dy := (centroid.y - prev_cent.y) * f32(viewer.window_height)

            // Calculate distance change (for pinch zoom)
            distance_delta := distance - viewer.prev_distance

            // Calculate relative distance change (more robust pinch detection)
            relative_distance_change := abs(distance_delta / viewer.prev_distance)

            // Calculate centroid movement magnitude
            movement_magnitude := math.sqrt(dx*dx + dy*dy)

            // Calculate ratio of distance change to movement
            // This is the key to distinguishing pinch from drag!
            distance_change_pixels := abs(distance_delta) * f32(viewer.window_width)  // Convert to pixels
            pinch_ratio := distance_change_pixels / max(movement_magnitude, 0.1)  // Avoid division by zero

            // RATIO-BASED PINCH DETECTION
            // Pinch: Distance change is LARGER than movement (ratio > 0.5)
            // Drag: Movement is LARGER than distance change (ratio < 0.3)
            pinch_start_ratio: f32 = 0.5   // Distance change must be 50% of movement
            pinch_stop_ratio: f32 = 0.25   // Drop below 25% to stop pinch
            min_distance_change: f32 = 1.5 // Minimum 1.5% distance change to START

            // DETECT PINCH STATE
            if !viewer.is_pinching && pinch_ratio > pinch_start_ratio && relative_distance_change > min_distance_change / 100.0 {
                // Start pinching (need high ratio + minimum distance change)
                viewer.is_pinching = true
            } else if viewer.is_pinching && pinch_ratio < pinch_stop_ratio {
                // Stop pinching (only check ratio, not percentage - prevents flicker!)
                viewer.is_pinching = false
            }

            // EXECUTE GESTURE based on current state
            if viewer.is_pinching {
                // PINCH GESTURE - Zoom camera ONLY (completely isolated!)
                zoom_speed: f32 = 2.0
                viewer.camera.distance -= distance_delta * zoom_speed * viewer.camera.distance

                // Clamp distance
                viewer.camera.distance = glsl.clamp(viewer.camera.distance, 0.5, 1000.0)

                // Update orthographic width (for orthographic zoom)
                if viewer.camera.projection_mode == .Orthographic {
                    viewer.camera.ortho_width -= distance_delta * zoom_speed * viewer.camera.ortho_width
                    viewer.camera.ortho_width = glsl.clamp(viewer.camera.ortho_width, 1.0, 500.0)
                }

                camera_update_position(&viewer.camera)

                // Update ONLY distance, keep centroid to maintain gesture context
                viewer.prev_distance = distance
                viewer.prev_centroid = centroid  // Update centroid too to prevent jump

            } else if viewer.shift_held && movement_magnitude > 1.0 {
                // 2-FINGER DRAG + SHIFT - Pan camera
                sensitivity := f32(0.003)

                // Calculate camera right and up vectors
                view_dir := glsl.normalize(viewer.camera.target - viewer.camera.position)
                right := glsl.normalize(glsl.cross(view_dir, viewer.camera.up))
                up := glsl.cross(right, view_dir)

                // Pan camera
                pan_scale := f64(-dx * sensitivity * viewer.camera.distance * 0.1)
                viewer.camera.target += right * pan_scale
                pan_scale_y := f64(dy * sensitivity * viewer.camera.distance * 0.1)
                viewer.camera.target += up * pan_scale_y

                camera_update_position(&viewer.camera)

                // Update previous values
                viewer.prev_centroid = centroid
                viewer.prev_distance = distance

            } else if movement_magnitude > 1.0 {
                // 2-FINGER DRAG - Orbit camera (Blender-style!)
                sensitivity := f32(0.025)
                viewer.camera.azimuth += dx * sensitivity
                viewer.camera.elevation += dy * sensitivity

                // Clamp elevation to avoid gimbal lock
                viewer.camera.elevation = glsl.clamp(viewer.camera.elevation, -math.PI * 0.49, math.PI * 0.49)

                camera_update_position(&viewer.camera)

                // Update previous values
                viewer.prev_centroid = centroid
                viewer.prev_distance = distance
            }
        }
    }
}

// Calculate centroid (average position) of all active fingers
calculate_centroid :: proc(fingers: map[sdl.FingerID]TouchPoint) -> [2]f32 {
    if len(fingers) == 0 do return {0, 0}

    sum := [2]f32{0, 0}
    for _, finger in fingers {
        sum.x += finger.x
        sum.y += finger.y
    }

    count := f32(len(fingers))
    return {sum.x / count, sum.y / count}
}

// Calculate distance between 2 fingers (for pinch detection)
calculate_finger_distance :: proc(fingers: map[sdl.FingerID]TouchPoint) -> f32 {
    if len(fingers) != 2 do return 0

    // Get the 2 finger positions
    points := make([dynamic]TouchPoint, context.temp_allocator)
    for _, finger in fingers {
        append(&points, finger)
    }

    dx := points[1].x - points[0].x
    dy := points[1].y - points[0].y

    return math.sqrt(dx*dx + dy*dy)
}

// =============================================================================
// Thick Line Rendering (Quad-based for macOS compatibility)
// =============================================================================

// Draw thick lines using quad geometry (works reliably on all platforms including macOS)
// Lines are rendered as quads (2 triangles per line segment) billboarded toward camera
// thickness_pixels: desired thickness in screen pixels (e.g., 3.0 for 3-pixel wide lines)
viewer_gpu_render_thick_lines :: proc(
    viewer: ^ViewerGPU,
    cmd: ^sdl.GPUCommandBuffer,
    pass: ^sdl.GPURenderPass,
    lines: [][2][3]f32,  // Array of line segments (pairs of vertices)
    color: [4]f32,
    mvp: matrix[4,4]f32,
    thickness_pixels: f32,
    use_depth_testing := false,  // NEW: Enable depth testing for 3D wireframe overlay
) {
    if len(lines) == 0 {
        return
    }

    // Calculate screen-space to world-space conversion
    pixel_size_world := get_pixel_size_world(viewer)

    // Calculate actual thickness in world units
    thick := pixel_size_world * thickness_pixels * 0.5  // Half-thickness for offset

    // Generate quad vertices for each line segment
    quad_verts := make([dynamic]LineVertex, context.temp_allocator)

    for line in lines {
        start := line[0]
        end := line[1]

        // Calculate line direction
        dir := [3]f32{end.x - start.x, end.y - start.y, end.z - start.z}
        dir_len := math.sqrt(dir.x*dir.x + dir.y*dir.y + dir.z*dir.z)
        if dir_len < 0.0001 {
            continue // Skip degenerate lines
        }
        dir = {dir.x / dir_len, dir.y / dir_len, dir.z / dir_len}

        // Calculate perpendicular vector (billboard towards camera)
        mid := [3]f32{
            (start.x + end.x) * 0.5,
            (start.y + end.y) * 0.5,
            (start.z + end.z) * 0.5,
        }

        to_camera := [3]f32{
            f32(viewer.camera.position.x) - mid.x,
            f32(viewer.camera.position.y) - mid.y,
            f32(viewer.camera.position.z) - mid.z,
        }

        // Cross product: dir × to_camera
        right := [3]f32{
            dir.y * to_camera.z - dir.z * to_camera.y,
            dir.z * to_camera.x - dir.x * to_camera.z,
            dir.x * to_camera.y - dir.y * to_camera.x,
        }

        right_len := math.sqrt(right.x*right.x + right.y*right.y + right.z*right.z)
        if right_len < 0.0001 {
            // Fallback if line points at camera
            right = {dir.y * 1.0 - dir.z * 0.0, dir.z * 0.0 - dir.x * 1.0, dir.x * 0.0 - dir.y * 0.0}
            right_len = math.sqrt(right.x*right.x + right.y*right.y + right.z*right.z)
            if right_len < 0.0001 {
                right = {dir.y * 0.0 - dir.z * 0.0, dir.z * 1.0 - dir.x * 0.0, dir.x * 0.0 - dir.y * 1.0}
            }
        }
        right = {
            (right.x / right_len) * thick,
            (right.y / right_len) * thick,
            (right.z / right_len) * thick,
        }

        // Create quad vertices (two triangles)
        p0 := [3]f32{start.x - right.x, start.y - right.y, start.z - right.z}
        p1 := [3]f32{start.x + right.x, start.y + right.y, start.z + right.z}
        p2 := [3]f32{end.x + right.x, end.y + right.y, end.z + right.z}
        p3 := [3]f32{end.x - right.x, end.y - right.y, end.z - right.z}

        // First triangle (p0, p1, p2)
        append(&quad_verts, LineVertex{p0})
        append(&quad_verts, LineVertex{p1})
        append(&quad_verts, LineVertex{p2})

        // Second triangle (p0, p2, p3)
        append(&quad_verts, LineVertex{p0})
        append(&quad_verts, LineVertex{p2})
        append(&quad_verts, LineVertex{p3})
    }

    if len(quad_verts) == 0 {
        return
    }

    // Create temporary vertex buffer for thick lines
    buffer_info := sdl.GPUBufferCreateInfo{
        usage = {.VERTEX},
        size = u32(len(quad_verts) * size_of(LineVertex)),
    }

    temp_vertex_buffer := sdl.CreateGPUBuffer(viewer.gpu_device, buffer_info)
    if temp_vertex_buffer == nil {
        fmt.eprintln("ERROR: Failed to create thick line vertex buffer")
        return
    }
    defer sdl.ReleaseGPUBuffer(viewer.gpu_device, temp_vertex_buffer)

    // Upload vertex data via transfer buffer
    transfer_info := sdl.GPUTransferBufferCreateInfo{
        usage = .UPLOAD,
        size = u32(len(quad_verts) * size_of(LineVertex)),
    }

    transfer_buffer := sdl.CreateGPUTransferBuffer(viewer.gpu_device, transfer_info)
    if transfer_buffer == nil {
        fmt.eprintln("ERROR: Failed to create transfer buffer for thick lines")
        return
    }
    defer sdl.ReleaseGPUTransferBuffer(viewer.gpu_device, transfer_buffer)

    // Map and copy vertex data
    transfer_ptr := sdl.MapGPUTransferBuffer(viewer.gpu_device, transfer_buffer, false)
    if transfer_ptr == nil {
        fmt.eprintln("ERROR: Failed to map transfer buffer for thick lines")
        return
    }

    dest_slice := ([^]LineVertex)(transfer_ptr)[:len(quad_verts)]
    copy(dest_slice, quad_verts[:])
    sdl.UnmapGPUTransferBuffer(viewer.gpu_device, transfer_buffer)

    // Upload to GPU
    upload_cmd := sdl.AcquireGPUCommandBuffer(viewer.gpu_device)
    copy_pass := sdl.BeginGPUCopyPass(upload_cmd)

    src := sdl.GPUTransferBufferLocation{
        transfer_buffer = transfer_buffer,
        offset = 0,
    }

    dst := sdl.GPUBufferRegion{
        buffer = temp_vertex_buffer,
        offset = 0,
        size = u32(len(quad_verts) * size_of(LineVertex)),
    }

    sdl.UploadToGPUBuffer(copy_pass, src, dst, false)
    sdl.EndGPUCopyPass(copy_pass)
    _ = sdl.SubmitGPUCommandBuffer(upload_cmd)

    // Wait for upload to complete (synchronous for now)
    _ = sdl.WaitForGPUIdle(viewer.gpu_device)

    // Choose pipeline based on depth testing requirement
    pipeline_to_use := viewer.triangle_pipeline  // Default: no depth testing (for UI)
    if use_depth_testing {
        pipeline_to_use = viewer.wireframe_pipeline  // Depth-tested for 3D wireframe overlay
    }

    // Bind selected pipeline
    sdl.BindGPUGraphicsPipeline(pass, pipeline_to_use)

    // Bind thick line vertex buffer
    binding := sdl.GPUBufferBinding{
        buffer = temp_vertex_buffer,
        offset = 0,
    }
    sdl.BindGPUVertexBuffers(pass, 0, &binding, 1)

    // Draw thick lines as triangles
    uniforms := Uniforms{
        mvp = mvp,
        color = color,
    }
    sdl.PushGPUVertexUniformData(cmd, 0, &uniforms, size_of(Uniforms))
    sdl.PushGPUFragmentUniformData(cmd, 0, &uniforms, size_of(Uniforms))
    sdl.DrawGPUPrimitives(pass, u32(len(quad_verts)), 1, 0, 0)

    // Switch back to line pipeline
    sdl.BindGPUGraphicsPipeline(pass, viewer.pipeline)
}

// =============================================================================
// Wireframe Mesh Rendering
// =============================================================================

// Render wireframe mesh with thick lines (screen-space constant thickness)
viewer_gpu_render_wireframe :: proc(
    viewer: ^ViewerGPU,
    cmd: ^sdl.GPUCommandBuffer,
    pass: ^sdl.GPURenderPass,
    mesh: ^WireframeMeshGPU,
    color: [4]f32,
    mvp: matrix[4,4]f32,
    thickness_pixels: f32 = 2.0,
) {
    if len(mesh.edges) == 0 {
        return
    }

    // Use thick line rendering with depth testing enabled for 3D wireframe overlay
    viewer_gpu_render_thick_lines(viewer, cmd, pass, mesh.edges[:], color, mvp, thickness_pixels, use_depth_testing = true)
}

// =============================================================================
// Inline Rectangle Rendering (for UI widgets in 3D space)
// =============================================================================

// Render a filled rectangle inline within current render pass (no GPU waits)
// This is designed to work within an active render pass for UI widgets
viewer_gpu_render_rect_inline :: proc(
    viewer: ^ViewerGPU,
    cmd: ^sdl.GPUCommandBuffer,
    pass: ^sdl.GPURenderPass,
    x, y, width, height: f32,
    color: [4]f32,
    screen_width, screen_height: u32,
) {
    // Convert screen space to NDC [-1, 1]
    x_ndc := (2.0 * x) / f32(screen_width) - 1.0
    y_ndc := 1.0 - (2.0 * y) / f32(screen_height)
    width_ndc := (2.0 * width) / f32(screen_width)
    height_ndc := (2.0 * height) / f32(screen_height)

    // Create rectangle vertices (2 triangles forming a quad)
    vertices := [6]LineVertex{
        // First triangle (top-left, bottom-left, bottom-right)
        {{x_ndc, y_ndc, 0}},
        {{x_ndc, y_ndc - height_ndc, 0}},
        {{x_ndc + width_ndc, y_ndc - height_ndc, 0}},
        // Second triangle (top-left, bottom-right, top-right)
        {{x_ndc, y_ndc, 0}},
        {{x_ndc + width_ndc, y_ndc - height_ndc, 0}},
        {{x_ndc + width_ndc, y_ndc, 0}},
    }

    // Create temporary vertex buffer
    buffer_info := sdl.GPUBufferCreateInfo{
        usage = {.VERTEX},
        size = u32(len(vertices) * size_of(LineVertex)),
    }

    temp_vertex_buffer := sdl.CreateGPUBuffer(viewer.gpu_device, buffer_info)
    if temp_vertex_buffer == nil do return
    defer sdl.ReleaseGPUBuffer(viewer.gpu_device, temp_vertex_buffer)

    // Upload vertex data
    transfer_info := sdl.GPUTransferBufferCreateInfo{
        usage = .UPLOAD,
        size = u32(len(vertices) * size_of(LineVertex)),
    }

    transfer_buffer := sdl.CreateGPUTransferBuffer(viewer.gpu_device, transfer_info)
    if transfer_buffer == nil do return
    defer sdl.ReleaseGPUTransferBuffer(viewer.gpu_device, transfer_buffer)

    transfer_ptr := sdl.MapGPUTransferBuffer(viewer.gpu_device, transfer_buffer, false)
    if transfer_ptr == nil do return

    dest_slice := ([^]LineVertex)(transfer_ptr)[:len(vertices)]
    copy(dest_slice, vertices[:])
    sdl.UnmapGPUTransferBuffer(viewer.gpu_device, transfer_buffer)

    // Upload to GPU
    upload_cmd := sdl.AcquireGPUCommandBuffer(viewer.gpu_device)
    copy_pass := sdl.BeginGPUCopyPass(upload_cmd)

    src := sdl.GPUTransferBufferLocation{
        transfer_buffer = transfer_buffer,
        offset = 0,
    }

    dst := sdl.GPUBufferRegion{
        buffer = temp_vertex_buffer,
        offset = 0,
        size = u32(len(vertices) * size_of(LineVertex)),
    }

    sdl.UploadToGPUBuffer(copy_pass, src, dst, false)
    sdl.EndGPUCopyPass(copy_pass)
    _ = sdl.SubmitGPUCommandBuffer(upload_cmd)

    // Wait for upload
    _ = sdl.WaitForGPUIdle(viewer.gpu_device)

    // Switch to triangle pipeline
    sdl.BindGPUGraphicsPipeline(pass, viewer.triangle_pipeline)

    // Bind vertex buffer
    binding := sdl.GPUBufferBinding{
        buffer = temp_vertex_buffer,
        offset = 0,
    }
    sdl.BindGPUVertexBuffers(pass, 0, &binding, 1)

    // Use identity matrix since we're already in NDC
    identity := matrix[4,4]f32{
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    }

    // Draw rectangle with color
    uniforms := Uniforms{
        mvp = identity,
        color = color,
    }
    sdl.PushGPUVertexUniformData(cmd, 0, &uniforms, size_of(Uniforms))
    sdl.PushGPUFragmentUniformData(cmd, 0, &uniforms, size_of(Uniforms))
    sdl.DrawGPUPrimitives(pass, u32(len(vertices)), 1, 0, 0)

    // Switch back to line pipeline
    sdl.BindGPUGraphicsPipeline(pass, viewer.pipeline)
}

// =============================================================================
// Triangle Mesh Rendering (Shaded with Lighting)
// =============================================================================

// Triangle uniforms structure (matches Metal shader TriangleUniforms)
TriangleUniforms :: struct {
    mvp: matrix[4,4]f32,          // Model-View-Projection matrix
    model: matrix[4,4]f32,        // Model matrix (identity for now)
    baseColor: [4]f32,            // Base material color
    lightDir: [3]f32,             // Directional light direction
    ambientStrength: f32,         // Ambient light strength
}

// Render triangle mesh with lighting (shaded mode)
viewer_gpu_render_triangle_mesh :: proc(
    viewer: ^ViewerGPU,
    cmd: ^sdl.GPUCommandBuffer,
    pass: ^sdl.GPURenderPass,
    mesh: ^TriangleMeshGPU,
    color: [4]f32,
    mvp: matrix[4,4]f32,
) {
    if viewer.shaded_pipeline == nil {
        return  // Shaded rendering not available
    }

    if len(mesh.vertices) == 0 {
        return
    }

    // Create temporary vertex buffer for triangle mesh
    buffer_info := sdl.GPUBufferCreateInfo{
        usage = {.VERTEX},
        size = u32(len(mesh.vertices) * size_of(TriangleVertex)),
    }

    temp_vertex_buffer := sdl.CreateGPUBuffer(viewer.gpu_device, buffer_info)
    if temp_vertex_buffer == nil {
        fmt.eprintln("ERROR: Failed to create triangle mesh vertex buffer")
        return
    }
    defer sdl.ReleaseGPUBuffer(viewer.gpu_device, temp_vertex_buffer)

    // Upload vertex data via transfer buffer
    transfer_info := sdl.GPUTransferBufferCreateInfo{
        usage = .UPLOAD,
        size = u32(len(mesh.vertices) * size_of(TriangleVertex)),
    }

    transfer_buffer := sdl.CreateGPUTransferBuffer(viewer.gpu_device, transfer_info)
    if transfer_buffer == nil {
        fmt.eprintln("ERROR: Failed to create transfer buffer for triangle mesh")
        return
    }
    defer sdl.ReleaseGPUTransferBuffer(viewer.gpu_device, transfer_buffer)

    // Map and copy vertex data
    transfer_ptr := sdl.MapGPUTransferBuffer(viewer.gpu_device, transfer_buffer, false)
    if transfer_ptr == nil {
        fmt.eprintln("ERROR: Failed to map transfer buffer for triangle mesh")
        return
    }

    dest_slice := ([^]TriangleVertex)(transfer_ptr)[:len(mesh.vertices)]
    copy(dest_slice, mesh.vertices[:])
    sdl.UnmapGPUTransferBuffer(viewer.gpu_device, transfer_buffer)

    // Upload to GPU
    upload_cmd := sdl.AcquireGPUCommandBuffer(viewer.gpu_device)
    copy_pass := sdl.BeginGPUCopyPass(upload_cmd)

    src := sdl.GPUTransferBufferLocation{
        transfer_buffer = transfer_buffer,
        offset = 0,
    }

    dst := sdl.GPUBufferRegion{
        buffer = temp_vertex_buffer,
        offset = 0,
        size = u32(len(mesh.vertices) * size_of(TriangleVertex)),
    }

    sdl.UploadToGPUBuffer(copy_pass, src, dst, false)
    sdl.EndGPUCopyPass(copy_pass)
    _ = sdl.SubmitGPUCommandBuffer(upload_cmd)

    // Wait for upload to complete
    _ = sdl.WaitForGPUIdle(viewer.gpu_device)

    // Switch to shaded rendering pipeline
    sdl.BindGPUGraphicsPipeline(pass, viewer.shaded_pipeline)

    // Bind vertex buffer
    binding := sdl.GPUBufferBinding{
        buffer = temp_vertex_buffer,
        offset = 0,
    }
    sdl.BindGPUVertexBuffers(pass, 0, &binding, 1)

    // Set up lighting parameters
    // Light direction: from upper-right-front (balanced for CAD viewing)
    // The shader negates this, so this vector points FROM the light source (use negative values!)
    light_dir := [3]f32{-0.4, -0.5, -0.3}  // Gentle angle from upper-right-front
    ambient_strength: f32 = 0.9            // 90% ambient light for minimal shadows (CAD-friendly)

    // Create identity matrix for model transform
    model_matrix := matrix[4,4]f32{
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    }

    tri_uniforms := TriangleUniforms{
        mvp = mvp,
        model = model_matrix,
        baseColor = color,
        lightDir = light_dir,
        ambientStrength = ambient_strength,
    }

    // Push uniforms to shader
    sdl.PushGPUVertexUniformData(cmd, 0, &tri_uniforms, size_of(TriangleUniforms))
    sdl.PushGPUFragmentUniformData(cmd, 0, &tri_uniforms, size_of(TriangleUniforms))

    // Draw triangles
    sdl.DrawGPUPrimitives(pass, u32(len(mesh.vertices)), 1, 0, 0)

    // Switch back to line pipeline
    sdl.BindGPUGraphicsPipeline(pass, viewer.pipeline)
}

// Render highlighted face (filled polygon overlay)
viewer_gpu_render_face_highlight :: proc(
    viewer: ^ViewerGPU,
    cmd: ^sdl.GPUCommandBuffer,
    pass: ^sdl.GPURenderPass,
    face: ^extrude.SimpleFace,
    color: [4]f32,
    mvp: matrix[4,4]f32,
) {
    if len(face.vertices) < 3 {
        return
    }

    // Tessellate face into triangles (simple fan triangulation from first vertex)
    // For now, assume faces are convex (which they are for extruded boxes)
    triangle_vertices := make([dynamic]LineVertex, 0, (len(face.vertices) - 2) * 3)
    defer delete(triangle_vertices)

    // Triangle fan from first vertex
    for i in 1..<len(face.vertices) - 1 {
        v0 := face.vertices[0].position
        v1 := face.vertices[i].position
        v2 := face.vertices[i + 1].position

        // Add triangle (v0, v1, v2) - convert f64 to f32
        append(&triangle_vertices, LineVertex{position = {f32(v0.x), f32(v0.y), f32(v0.z)}})
        append(&triangle_vertices, LineVertex{position = {f32(v1.x), f32(v1.y), f32(v1.z)}})
        append(&triangle_vertices, LineVertex{position = {f32(v2.x), f32(v2.y), f32(v2.z)}})
    }

    if len(triangle_vertices) == 0 {
        return
    }

    // Create vertex buffer for triangles
    buffer_info := sdl.GPUBufferCreateInfo{
        usage = {.VERTEX},
        size = u32(len(triangle_vertices) * size_of(LineVertex)),
    }

    vertex_buffer := sdl.CreateGPUBuffer(viewer.gpu_device, buffer_info)
    if vertex_buffer == nil {
        fmt.eprintln("ERROR: Failed to create face highlight vertex buffer")
        return
    }
    defer sdl.ReleaseGPUBuffer(viewer.gpu_device, vertex_buffer)

    // Create transfer buffer
    transfer_info := sdl.GPUTransferBufferCreateInfo{
        usage = .UPLOAD,
        size = u32(len(triangle_vertices) * size_of(LineVertex)),
    }

    transfer_buffer := sdl.CreateGPUTransferBuffer(viewer.gpu_device, transfer_info)
    if transfer_buffer == nil {
        fmt.eprintln("ERROR: Failed to create transfer buffer for face highlight")
        return
    }
    defer sdl.ReleaseGPUTransferBuffer(viewer.gpu_device, transfer_buffer)

    // Map and copy vertex data
    transfer_ptr := sdl.MapGPUTransferBuffer(viewer.gpu_device, transfer_buffer, false)
    if transfer_ptr == nil {
        fmt.eprintln("ERROR: Failed to map transfer buffer for face highlight")
        return
    }

    dest_slice := ([^]LineVertex)(transfer_ptr)[:len(triangle_vertices)]
    copy(dest_slice, triangle_vertices[:])
    sdl.UnmapGPUTransferBuffer(viewer.gpu_device, transfer_buffer)

    // Upload to GPU
    upload_cmd := sdl.AcquireGPUCommandBuffer(viewer.gpu_device)
    copy_pass := sdl.BeginGPUCopyPass(upload_cmd)

    upload_copy := sdl.GPUTransferBufferLocation{
        transfer_buffer = transfer_buffer,
        offset = 0,
    }

    destination := sdl.GPUBufferRegion{
        buffer = vertex_buffer,
        offset = 0,
        size = u32(len(triangle_vertices) * size_of(LineVertex)),
    }

    sdl.UploadToGPUBuffer(copy_pass, upload_copy, destination, false)
    sdl.EndGPUCopyPass(copy_pass)
    _ = sdl.SubmitGPUCommandBuffer(upload_cmd)

    // Wait for upload to complete
    _ = sdl.WaitForGPUIdle(viewer.gpu_device)

    // Bind triangle pipeline for filled face rendering
    sdl.BindGPUGraphicsPipeline(pass, viewer.triangle_pipeline)

    // Bind vertex buffer
    buffer_binding := sdl.GPUBufferBinding{
        buffer = vertex_buffer,
        offset = 0,
    }
    sdl.BindGPUVertexBuffers(pass, 0, &buffer_binding, 1)

    // Push MVP matrix and color
    uniforms := Uniforms{
        mvp = mvp,
        color = color,
    }
    sdl.PushGPUVertexUniformData(cmd, 0, &uniforms, size_of(Uniforms))
    sdl.PushGPUFragmentUniformData(cmd, 0, &uniforms, size_of(Uniforms))

    // Draw triangles
    sdl.DrawGPUPrimitives(pass, u32(len(triangle_vertices)), 1, 0, 0)

    // Switch back to line pipeline
    sdl.BindGPUGraphicsPipeline(pass, viewer.pipeline)
}
