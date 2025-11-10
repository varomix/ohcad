// ui/viewer - SDL3 GPU Viewer with Metal backend (Phase 3)
// Combines SDL3 GPU rendering + camera system + multi-touch gestures
package ohcad_viewer

import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import m "../../core/math"
import t "../../core/topology"
import sketch "../../features/sketch"
import extrude "../../features/extrude"
import sdl "vendor:sdl3"
import glsl "core:math/linalg/glsl"
import fs "vendor:fontstash"

// =============================================================================
// Viewer Configuration
// =============================================================================

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
    triangle_pipeline: ^sdl.GPUGraphicsPipeline,  // For thick line rendering (quads)

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
}

// Initialize text renderer for SDL3 GPU
text_renderer_gpu_init :: proc(gpu_device: ^sdl.GPUDevice, window: ^sdl.Window, shader_data: []byte) -> (TextRendererGPU, bool) {
    renderer: TextRendererGPU
    renderer.gpu_device = gpu_device

    // Initialize fontstash context (512x512 texture atlas)
    renderer.texture_width = 512
    renderer.texture_height = 512
    fs.Init(&renderer.font_context, renderer.texture_width, renderer.texture_height, .TOPLEFT)

    // Load custom BigShoulders font from assets
    font_path := "assets/gui/fonts/BigShoulders_24pt-Regular.ttf"
    font_id := fs.AddFontPath(&renderer.font_context, "bigshoulders", font_path)

    if font_id == fs.INVALID {
        fmt.eprintln("❌ Failed to load BigShoulders font from:", font_path)
        fs.Destroy(&renderer.font_context)
        return renderer, false
    }

    renderer.font_id = font_id
    fmt.printf("✓ Loaded custom font: %s\n", font_path)

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
    texture_info := sdl.GPUTextureCreateInfo{
        type = .D2,
        format = .R8_UNORM,  // Single channel for alpha
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
        target_info = {
            num_color_targets = 1,
            color_target_descriptions = &color_target,
            has_depth_stencil_target = false,
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

    iter := fs.TextIterInit(&renderer.font_context, x, y, text)
    quad: fs.Quad
    for fs.TextIterNext(&renderer.font_context, &iter, &quad) {
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

    // Update font atlas texture if needed
    dirty: [4]f32
    if fs.ValidateTexture(&renderer.font_context, &dirty) {
        // Upload entire texture (simpler and more reliable)
        text_renderer_gpu_update_texture(renderer, cmd)
    }

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
text_renderer_gpu_update_texture :: proc(renderer: ^TextRendererGPU, cmd: ^sdl.GPUCommandBuffer) {
    // Create transfer buffer for texture data
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

    // Map and copy texture data
    transfer_ptr := sdl.MapGPUTransferBuffer(renderer.gpu_device, transfer_buffer, false)
    if transfer_ptr == nil {
        fmt.eprintln("ERROR: Failed to map transfer buffer for font texture")
        return
    }

    dest_slice := ([^]u8)(transfer_ptr)[:texture_size]
    copy(dest_slice, renderer.font_context.textureData[:texture_size])
    sdl.UnmapGPUTransferBuffer(renderer.gpu_device, transfer_buffer)

    // Upload to texture
    upload_cmd := sdl.AcquireGPUCommandBuffer(renderer.gpu_device)
    copy_pass := sdl.BeginGPUCopyPass(upload_cmd)

    src := sdl.GPUTextureTransferInfo{
        transfer_buffer = transfer_buffer,
        offset = 0,
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
}

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
    viewport_height := f32(viewer.window_height)
    fov_radians := math.to_radians(viewer.camera.fov)
    pixel_size_world := (2.0 * viewer.camera.distance * math.tan(fov_radians * 0.5)) / viewport_height

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

// =============================================================================
// Preview Geometry Rendering
// =============================================================================

// Render preview geometry (temporary line or circle following cursor)
viewer_gpu_render_sketch_preview :: proc(
    viewer: ^ViewerGPU,
    cmd: ^sdl.GPUCommandBuffer,
    pass: ^sdl.GPURenderPass,
    sk: ^sketch.Sketch2D,
    mvp: matrix[4,4]f32,
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
    viewer_gpu_render_thick_lines(viewer, cmd, pass, h_line, {0, 1, 1, 1}, mvp, 2.0)

    // Vertical line
    v_line := [][2][3]f32{
        {
            {f32(cursor_3d.x), f32(cursor_3d.y - size), f32(cursor_3d.z)},
            {f32(cursor_3d.x), f32(cursor_3d.y + size), f32(cursor_3d.z)},
        },
    }
    viewer_gpu_render_thick_lines(viewer, cmd, pass, v_line, {0, 1, 1, 1}, mvp, 2.0)

    // If line tool has first point, draw preview line
    if sk.current_tool == .Line && sk.first_point_id != -1 {
        first_pt := sketch.sketch_get_point(sk, sk.first_point_id)
        if first_pt != nil {
            start_2d := m.Vec2{first_pt.x, first_pt.y}
            start_3d := sketch.sketch_to_world(&sk.plane, start_2d)

            preview_line := [][2][3]f32{
                {
                    {f32(start_3d.x), f32(start_3d.y), f32(start_3d.z)},
                    {f32(cursor_3d.x), f32(cursor_3d.y), f32(cursor_3d.z)},
                },
            }
            viewer_gpu_render_thick_lines(viewer, cmd, pass, preview_line, {0, 1, 1, 0.7}, mvp, 2.0)
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
            viewer_gpu_render_thick_lines(viewer, cmd, pass, circle_lines[:], {0, 1, 1, 0.7}, mvp, 2.0)

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
) {
    if sk == nil do return
    if sk.constraints == nil do return
    if len(sk.constraints) == 0 do return

    for constraint in sk.constraints {
        if !constraint.enabled do continue

        switch data in constraint.data {
        case sketch.DistanceData:
            render_distance_dimension_gpu(viewer, cmd, pass, text_renderer, sk, data, mvp, view, proj)

        case sketch.HorizontalData:
            render_horizontal_icon_gpu(viewer, cmd, pass, sk, data, mvp)

        case sketch.VerticalData:
            render_vertical_icon_gpu(viewer, cmd, pass, sk, data, mvp)

        case sketch.PerpendicularData, sketch.ParallelData, sketch.CoincidentData, sketch.EqualData:
            // These constraint types can be added later if needed
            // For now, focusing on the most important: Distance dimensions

        case sketch.DistanceXData, sketch.DistanceYData, sketch.AngleData, sketch.TangentData,
             sketch.PointOnLineData, sketch.PointOnCircleData, sketch.FixedPointData:
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

    // Dimension line itself
    append(&dim_lines, [2][3]f32{
        {f32(dim1_3d.x), f32(dim1_3d.y), f32(dim1_3d.z)},
        {f32(dim2_3d.x), f32(dim2_3d.y), f32(dim2_3d.z)},
    })

    // Draw dimension lines in bright yellow
    viewer_gpu_render_thick_lines(viewer, cmd, pass, dim_lines[:], {1.0, 1.0, 0.0, 1.0}, mvp, 2.5)

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

            // Format distance value
            dist_text := fmt.tprintf("%.2f", data.distance)

            // Render text (bright yellow to match dimension line)
            text_render_2d_gpu(text_renderer, cmd, pass, dist_text, screen_x, screen_y, 16, {255, 255, 0, 255}, viewer.window_width, viewer.window_height)
        }
    }
}

// Render horizontal constraint icon (H symbol)
render_horizontal_icon_gpu :: proc(
    viewer: ^ViewerGPU,
    cmd: ^sdl.GPUCommandBuffer,
    pass: ^sdl.GPURenderPass,
    sk: ^sketch.Sketch2D,
    data: sketch.HorizontalData,
    mvp: matrix[4,4]f32,
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

    // Offset upward
    size := 0.15
    offset_2d := m.Vec2{mid_2d.x, mid_2d.y + size * 1.5}

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
    viewer_gpu_render_thick_lines(viewer, cmd, pass, h_lines[:], {1.0, 0.7, 0.0, 1.0}, mvp, 2.0)
}

// Render vertical constraint icon (V symbol)
render_vertical_icon_gpu :: proc(
    viewer: ^ViewerGPU,
    cmd: ^sdl.GPUCommandBuffer,
    pass: ^sdl.GPURenderPass,
    sk: ^sketch.Sketch2D,
    data: sketch.VerticalData,
    mvp: matrix[4,4]f32,
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

    // Offset to the side
    size := 0.15
    offset_2d := m.Vec2{mid_2d.x + size * 1.5, mid_2d.y}

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
    viewer_gpu_render_thick_lines(viewer, cmd, pass, v_lines[:], {1.0, 0.7, 0.0, 1.0}, mvp, 2.0)
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

    // Create triangle pipeline for thick lines (same shaders, different primitive type)
    triangle_pipeline_info := sdl.GPUGraphicsPipelineCreateInfo{
        vertex_shader = vertex_shader,
        fragment_shader = fragment_shader,
        vertex_input_state = vertex_input_state,
        primitive_type = .TRIANGLELIST,  // For thick line quads
        rasterizer_state = {
            fill_mode = .FILL,
            cull_mode = .NONE,
            front_face = .COUNTER_CLOCKWISE,
        },
        target_info = {
            num_color_targets = 1,
            color_target_descriptions = &color_target,
            has_depth_stencil_target = false,
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

    // Create viewer
    viewer := new(ViewerGPU)
    viewer.window = window
    viewer.gpu_device = gpu_device
    viewer.vertex_shader = vertex_shader
    viewer.fragment_shader = fragment_shader
    viewer.pipeline = pipeline
    viewer.triangle_pipeline = triangle_pipeline
    viewer.should_close = false
    viewer.window_width = u32(config.window_width)
    viewer.window_height = u32(config.window_height)

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

    // Create grid vertex buffer
    if !viewer_gpu_create_grid(viewer, 10.0, 20) {
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
    axes_length: f32 = 5.0

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
    x_axis := [][2][3]f32{{{0, 0, 0}, {axes_length, 0, 0}}}
    y_axis := [][2][3]f32{{{0, 0, 0}, {0, axes_length, 0}}}
    z_axis := [][2][3]f32{{{0, 0, 0}, {0, 0, axes_length}}}

    // Render with thick lines (4 pixels wide for visibility)
    thickness: f32 = 4.0

    // X axis (red)
    viewer_gpu_render_thick_lines(viewer, cmd, pass, x_axis, {1.0, 0.0, 0.0, 1.0}, mvp, thickness)

    // Y axis (green)
    viewer_gpu_render_thick_lines(viewer, cmd, pass, y_axis, {0.0, 1.0, 0.0, 1.0}, mvp, thickness)

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
    viewer.camera.distance -= wheel.y * zoom_speed * viewer.camera.distance

    // Clamp distance
    viewer.camera.distance = glsl.clamp(viewer.camera.distance, 0.5, 100.0)

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
                viewer.camera.distance = glsl.clamp(viewer.camera.distance, 0.5, 100.0)

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
) {
    if len(lines) == 0 {
        return
    }

    // Calculate screen-space to world-space conversion
    // At the camera's distance, calculate how big one pixel is in world units
    viewport_height := f32(viewer.window_height)
    fov_radians := math.to_radians(viewer.camera.fov)
    pixel_size_world := (2.0 * viewer.camera.distance * math.tan(fov_radians * 0.5)) / viewport_height

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

    // Switch to triangle pipeline
    sdl.BindGPUGraphicsPipeline(pass, viewer.triangle_pipeline)

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

    // Use thick line rendering for all edges
    viewer_gpu_render_thick_lines(viewer, cmd, pass, mesh.edges[:], color, mvp, thickness_pixels)
}
