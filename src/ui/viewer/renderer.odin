// ui/viewer - Simple rendering utilities for the viewer
package ohcad_viewer

import "core:fmt"
import gl "vendor:OpenGL"
import m "../../core/math"
import glsl "core:math/linalg/glsl"

// Simple shader program for colored lines
LineShader :: struct {
    program: u32,
    vao: u32,
    vbo: u32,
    mvp_loc: i32,
    color_loc: i32,
}

// Initialize line shader for drawing axes and grid
line_shader_init :: proc() -> (LineShader, bool) {
    shader: LineShader

    // Vertex shader source
    vertex_shader_source := `#version 330 core
layout (location = 0) in vec3 aPos;

uniform mat4 uMVP;

void main() {
    gl_Position = uMVP * vec4(aPos, 1.0);
}
`

    // Fragment shader source
    fragment_shader_source := `#version 330 core
out vec4 FragColor;

uniform vec4 uColor;

void main() {
    FragColor = uColor;
}
`

    // Compile vertex shader
    vertex_shader := gl.CreateShader(gl.VERTEX_SHADER)
    vertex_c_str := cstring(raw_data(vertex_shader_source))
    gl.ShaderSource(vertex_shader, 1, &vertex_c_str, nil)
    gl.CompileShader(vertex_shader)

    // Check vertex shader compilation
    success: i32
    gl.GetShaderiv(vertex_shader, gl.COMPILE_STATUS, &success)
    if success == 0 {
        info_log: [512]u8
        gl.GetShaderInfoLog(vertex_shader, 512, nil, raw_data(info_log[:]))
        fmt.eprintln("ERROR: Vertex shader compilation failed")
        fmt.eprintln(string(info_log[:]))
        return shader, false
    }

    // Compile fragment shader
    fragment_shader := gl.CreateShader(gl.FRAGMENT_SHADER)
    fragment_c_str := cstring(raw_data(fragment_shader_source))
    gl.ShaderSource(fragment_shader, 1, &fragment_c_str, nil)
    gl.CompileShader(fragment_shader)

    // Check fragment shader compilation
    gl.GetShaderiv(fragment_shader, gl.COMPILE_STATUS, &success)
    if success == 0 {
        info_log: [512]u8
        gl.GetShaderInfoLog(fragment_shader, 512, nil, raw_data(info_log[:]))
        fmt.eprintln("ERROR: Fragment shader compilation failed")
        fmt.eprintln(string(info_log[:]))
        return shader, false
    }

    // Link shader program
    shader.program = gl.CreateProgram()
    gl.AttachShader(shader.program, vertex_shader)
    gl.AttachShader(shader.program, fragment_shader)
    gl.LinkProgram(shader.program)

    // Check linking
    gl.GetProgramiv(shader.program, gl.LINK_STATUS, &success)
    if success == 0 {
        info_log: [512]u8
        gl.GetProgramInfoLog(shader.program, 512, nil, raw_data(info_log[:]))
        fmt.eprintln("ERROR: Shader program linking failed")
        fmt.eprintln(string(info_log[:]))
        return shader, false
    }

    // Clean up shaders
    gl.DeleteShader(vertex_shader)
    gl.DeleteShader(fragment_shader)

    // Get uniform locations
    shader.mvp_loc = gl.GetUniformLocation(shader.program, "uMVP")
    shader.color_loc = gl.GetUniformLocation(shader.program, "uColor")

    // Create VAO and VBO
    gl.GenVertexArrays(1, &shader.vao)
    gl.GenBuffers(1, &shader.vbo)

    gl.BindVertexArray(shader.vao)
    gl.BindBuffer(gl.ARRAY_BUFFER, shader.vbo)

    // Configure vertex attributes (3 f64 values per vertex)
    gl.VertexAttribPointer(0, 3, gl.DOUBLE, gl.FALSE, 3 * size_of(f64), 0)
    gl.EnableVertexAttribArray(0)

    gl.BindBuffer(gl.ARRAY_BUFFER, 0)
    gl.BindVertexArray(0)

    fmt.println("Line shader initialized successfully")
    return shader, true
}

// Destroy line shader
line_shader_destroy :: proc(shader: ^LineShader) {
    gl.DeleteVertexArrays(1, &shader.vao)
    gl.DeleteBuffers(1, &shader.vbo)
    gl.DeleteProgram(shader.program)
}

// Draw lines with the shader (with optional line width)
// Note: For thick lines on macOS, we use quad geometry instead of glLineWidth
line_shader_draw :: proc(shader: ^LineShader, vertices: []m.Vec3, color: [4]f32, mvp: glsl.mat4, line_width: f32 = 1.0) {
    gl.UseProgram(shader.program)

    // Set line width (may not work on macOS Core Profile)
    gl.LineWidth(line_width)

    // Set uniforms (get pointer to first element of matrix)
    mvp_data := mvp
    gl.UniformMatrix4fv(shader.mvp_loc, 1, gl.FALSE, &mvp_data[0][0])
    color_data := color
    gl.Uniform4fv(shader.color_loc, 1, &color_data[0])

    // Upload vertices
    gl.BindBuffer(gl.ARRAY_BUFFER, shader.vbo)
    gl.BufferData(gl.ARRAY_BUFFER, len(vertices) * size_of(m.Vec3), raw_data(vertices), gl.DYNAMIC_DRAW)

    // Draw
    gl.BindVertexArray(shader.vao)
    gl.DrawArrays(gl.LINES, 0, i32(len(vertices)))
    gl.BindVertexArray(0)

    // Reset line width to default
    gl.LineWidth(1.0)
}

// Draw filled circle using triangle fan (for point markers)
line_shader_draw_filled_circle :: proc(shader: ^LineShader, vertices: []m.Vec3, color: [4]f32, mvp: glsl.mat4) {
    if len(vertices) < 3 {
        return // Need at least 3 vertices for a triangle
    }

    gl.UseProgram(shader.program)

    // Set uniforms
    mvp_data := mvp
    gl.UniformMatrix4fv(shader.mvp_loc, 1, gl.FALSE, &mvp_data[0][0])
    color_data := color
    gl.Uniform4fv(shader.color_loc, 1, &color_data[0])

    // Upload vertices
    gl.BindBuffer(gl.ARRAY_BUFFER, shader.vbo)
    gl.BufferData(gl.ARRAY_BUFFER, len(vertices) * size_of(m.Vec3), raw_data(vertices), gl.DYNAMIC_DRAW)

    // Draw as triangle fan (first vertex is center, rest are perimeter)
    gl.BindVertexArray(shader.vao)
    gl.DrawArrays(gl.TRIANGLE_FAN, 0, i32(len(vertices)))
    gl.BindVertexArray(0)
}

// Draw thick lines using quad geometry (works reliably on all platforms including macOS)
// thickness_pixels: desired thickness in screen pixels (e.g., 3.0 for 3-pixel wide lines)
// viewport_height: screen height in pixels for screen-space calculation
// fov: field of view in radians
// camera_distance: distance from camera to target
line_shader_draw_thick :: proc(shader: ^LineShader, vertices: []m.Vec3, color: [4]f32, mvp: glsl.mat4, thickness_pixels: f32, camera_pos: m.Vec3, viewport_height: f32, fov: f32, camera_distance: f32) {
    if len(vertices) < 2 || len(vertices) % 2 != 0 {
        return // Need pairs of vertices for lines
    }

    gl.UseProgram(shader.program)

    // Set uniforms
    mvp_data := mvp
    gl.UniformMatrix4fv(shader.mvp_loc, 1, gl.FALSE, &mvp_data[0][0])
    color_data := color
    gl.Uniform4fv(shader.color_loc, 1, &color_data[0])

    // Calculate screen-space to world-space conversion
    // At the camera's distance, calculate how big one pixel is in world units
    // Formula: pixel_size_world = (2 * distance * tan(fov/2)) / viewport_height
    pixel_size_world := f64((2.0 * camera_distance * glsl.tan(fov * 0.5)) / viewport_height)

    // Calculate actual thickness in world units
    thick := pixel_size_world * f64(thickness_pixels) * 0.5  // Half-thickness for offset

    // Generate quad vertices for each line segment
    quad_verts := make([dynamic]m.Vec3, 0, len(vertices) * 3)
    defer delete(quad_verts)

    for i := 0; i < len(vertices); i += 2 {
        start := vertices[i]
        end := vertices[i + 1]

        // Calculate line direction
        dir := end - start
        dir_len := glsl.length(dir)
        if dir_len < 0.0001 {
            continue // Skip degenerate lines
        }
        dir = dir / dir_len

        // Calculate perpendicular vector (billboard towards camera)
        to_camera := camera_pos - (start + end) * 0.5
        right := glsl.cross(dir, to_camera)
        right_len := glsl.length(right)
        if right_len < 0.0001 {
            // Fallback if line points at camera
            right = glsl.cross(dir, m.Vec3{0, 1, 0})
            right_len = glsl.length(right)
            if right_len < 0.0001 {
                right = glsl.cross(dir, m.Vec3{1, 0, 0})
            }
        }
        right = glsl.normalize(right) * thick

        // Create quad vertices (two triangles)
        p0 := start - right
        p1 := start + right
        p2 := end + right
        p3 := end - right

        // First triangle
        append(&quad_verts, p0)
        append(&quad_verts, p1)
        append(&quad_verts, p2)

        // Second triangle
        append(&quad_verts, p0)
        append(&quad_verts, p2)
        append(&quad_verts, p3)
    }

    if len(quad_verts) == 0 {
        return
    }

    // Upload and draw quads
    gl.BindBuffer(gl.ARRAY_BUFFER, shader.vbo)
    gl.BufferData(gl.ARRAY_BUFFER, len(quad_verts) * size_of(m.Vec3), raw_data(quad_verts), gl.DYNAMIC_DRAW)

    gl.BindVertexArray(shader.vao)
    gl.DrawArrays(gl.TRIANGLES, 0, i32(len(quad_verts)))
    gl.BindVertexArray(0)
}

// =============================================================================
// Coordinate Axes and Grid Rendering
// =============================================================================

// Render coordinate axes (X=red, Y=green, Z=blue) - HUD cyan theme
render_axes :: proc(shader: ^LineShader, mvp: glsl.mat4, length: f32 = 1.0) {
    l := f64(length)  // Convert to f64 for m.Vec3

    // X axis - Dark cyan
    x_axis := []m.Vec3{
        {0, 0, 0},
        {l, 0, 0},
    }
    line_shader_draw(shader, x_axis, {1.0, 0.0, 0.0, 0.6}, mvp)

    // Y axis - Medium cyan
    y_axis := []m.Vec3{
        {0, 0, 0},
        {0, l, 0},
    }
    line_shader_draw(shader, y_axis, {0.0, 1.0, 0.0, 0.6}, mvp)

    // Z axis - Bright cyan
    z_axis := []m.Vec3{
        {0, 0, 0},
        {0, 0, l},
    }
    line_shader_draw(shader, z_axis, {0.0, 0.0, 1.0, 0.6}, mvp)
}

// Render grid on XZ plane - HUD cyan theme
render_grid :: proc(shader: ^LineShader, mvp: glsl.mat4, size: f32 = 10.0, divisions: i32 = 20) {
    vertices := make([dynamic]m.Vec3, 0, (divisions + 1) * 4)
    defer delete(vertices)

    step := f64(size) / f64(divisions)
    half_size := f64(size) * 0.5

    // Grid lines parallel to X axis
    for i in 0..=divisions {
        z := -half_size + f64(i) * step
        append(&vertices, m.Vec3{-half_size, 0, z})
        append(&vertices, m.Vec3{half_size, 0, z})
    }

    // Grid lines parallel to Z axis
    for i in 0..=divisions {
        x := -half_size + f64(i) * step
        append(&vertices, m.Vec3{x, 0, -half_size})
        append(&vertices, m.Vec3{x, 0, half_size})
    }

    // Draw grid in dark gray (subtle)
    line_shader_draw(shader, vertices[:], {0.14, 0.14, 0.14, 0.2}, mvp)
}

// =============================================================================
// Wireframe Mesh Rendering
// =============================================================================

// Wireframe mesh data (edge-based representation)
WireframeMesh :: struct {
    edges: [dynamic][2]m.Vec3,  // List of edges (pairs of vertices)
}

// Create empty wireframe mesh
wireframe_mesh_init :: proc() -> WireframeMesh {
    return WireframeMesh{
        edges = make([dynamic][2]m.Vec3),
    }
}

// Destroy wireframe mesh
wireframe_mesh_destroy :: proc(mesh: ^WireframeMesh) {
    delete(mesh.edges)
}

// Add edge to wireframe mesh
wireframe_mesh_add_edge :: proc(mesh: ^WireframeMesh, v0, v1: m.Vec3) {
    append(&mesh.edges, [2]m.Vec3{v0, v1})
}

// Render wireframe mesh (with configurable line width)
// For thick lines on macOS, use render_wireframe_thick instead
render_wireframe :: proc(shader: ^LineShader, mesh: ^WireframeMesh, mvp: glsl.mat4, color: [4]f32 = {0, 0, 0, 1}, line_width: f32 = 1.0) {
    if len(mesh.edges) == 0 do return

    // Convert edges to vertex list for rendering
    vertices := make([dynamic]m.Vec3, 0, len(mesh.edges) * 2)
    defer delete(vertices)

    for edge in mesh.edges {
        append(&vertices, edge[0])
        append(&vertices, edge[1])
    }

    // Draw all edges with specified line width
    line_shader_draw(shader, vertices[:], color, mvp, line_width)
}

// Render wireframe mesh with thick lines (works on macOS)
// Screen-space constant thickness - lines stay same pixel width regardless of zoom
render_wireframe_thick :: proc(shader: ^LineShader, mesh: ^WireframeMesh, mvp: glsl.mat4, camera_pos: m.Vec3, color: [4]f32, thickness_pixels: f32, viewport_height: f32, fov: f32, camera_distance: f32) {
    if len(mesh.edges) == 0 do return

    // Convert edges to vertex list for rendering
    vertices := make([dynamic]m.Vec3, 0, len(mesh.edges) * 2)
    defer delete(vertices)

    for edge in mesh.edges {
        append(&vertices, edge[0])
        append(&vertices, edge[1])
    }

    // Draw all edges as thick quads with screen-space constant thickness
    line_shader_draw_thick(shader, vertices[:], color, mvp, thickness_pixels, camera_pos, viewport_height, fov, camera_distance)
}
