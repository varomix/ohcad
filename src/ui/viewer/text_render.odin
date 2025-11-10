// ui/viewer - Text rendering with fontstash
package ohcad_viewer

import "core:fmt"
import "core:strings"
import "core:math"
import m "../../core/math"
import gl "vendor:OpenGL"
import glsl "core:math/linalg/glsl"
import fs "vendor:fontstash"

// Text renderer with fontstash
TextRenderer :: struct {
    font_context: fs.FontContext,
    font_id: int,

    // OpenGL resources
    vao: u32,
    vbo: u32,
    texture: u32,
    shader_program: u32,

    // Texture size
    texture_width: int,
    texture_height: int,
}

// Initialize text renderer
text_renderer_init :: proc() -> (TextRenderer, bool) {
    renderer: TextRenderer

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

    // Create OpenGL texture for font atlas
    gl.GenTextures(1, &renderer.texture)
    gl.BindTexture(gl.TEXTURE_2D, renderer.texture)
    gl.TexImage2D(
        gl.TEXTURE_2D, 0, gl.R8,
        i32(renderer.texture_width), i32(renderer.texture_height),
        0, gl.RED, gl.UNSIGNED_BYTE,
        raw_data(renderer.font_context.textureData),
    )
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    gl.BindTexture(gl.TEXTURE_2D, 0)

    // Create VAO and VBO for text quads
    gl.GenVertexArrays(1, &renderer.vao)
    gl.GenBuffers(1, &renderer.vbo)

    gl.BindVertexArray(renderer.vao)
    gl.BindBuffer(gl.ARRAY_BUFFER, renderer.vbo)

    // Allocate buffer for dynamic text (max 256 characters = 1024 vertices)
    gl.BufferData(gl.ARRAY_BUFFER, 1024 * size_of(fs.Vertex), nil, gl.DYNAMIC_DRAW)

    // Position attribute (x, y)
    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, size_of(fs.Vertex), 0)

    // Texcoord attribute (u, v)
    gl.EnableVertexAttribArray(1)
    gl.VertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, size_of(fs.Vertex), offset_of(fs.Vertex, u))

    // Color attribute (rgba)
    gl.EnableVertexAttribArray(2)
    gl.VertexAttribPointer(2, 4, gl.UNSIGNED_BYTE, gl.TRUE, size_of(fs.Vertex), offset_of(fs.Vertex, color))

    gl.BindVertexArray(0)

    // Create shader program for text rendering
    renderer.shader_program = create_text_shader()
    if renderer.shader_program == 0 {
        fmt.eprintln("❌ Failed to create text shader!")
        text_renderer_destroy(&renderer)
        return renderer, false
    }

    fmt.println("✓ Text renderer initialized successfully")
    return renderer, true
}

// Destroy text renderer
text_renderer_destroy :: proc(renderer: ^TextRenderer) {
    fs.Destroy(&renderer.font_context)
    gl.DeleteTextures(1, &renderer.texture)
    gl.DeleteBuffers(1, &renderer.vbo)
    gl.DeleteVertexArrays(1, &renderer.vao)
    gl.DeleteProgram(renderer.shader_program)
}

// Set screen size uniform (call when window resizes or before rendering)
text_renderer_set_screen_size :: proc(renderer: ^TextRenderer, width, height: f32) {
    gl.UseProgram(renderer.shader_program)
    screen_size_loc := gl.GetUniformLocation(renderer.shader_program, "uScreenSize")
    gl.Uniform2f(screen_size_loc, width, height)
    gl.UseProgram(0)
}

// Render text at 2D screen position (pixels from top-left)
text_render_2d :: proc(renderer: ^TextRenderer, text: string, x, y, size: f32, color: [4]u8) {
    if len(text) == 0 do return

    // Set font state
    fs.SetFont(&renderer.font_context, renderer.font_id)
    fs.SetSize(&renderer.font_context, size)
    fs.SetAlignHorizontal(&renderer.font_context, .LEFT)
    fs.SetAlignVertical(&renderer.font_context, .TOP)
    fs.SetColor(&renderer.font_context, color)

    // Collect vertices for text
    vertices: [1024]fs.Vertex  // Max 256 quads (4 verts each)
    vertex_count := 0

    iter := fs.TextIterInit(&renderer.font_context, x, y, text)
    quad: fs.Quad
    for fs.TextIterNext(&renderer.font_context, &iter, &quad) {
        if vertex_count + 6 > len(vertices) {
            break  // Buffer full
        }

        // First triangle (top-left, bottom-left, bottom-right)
        vertices[vertex_count + 0] = {quad.x0, quad.y0, quad.s0, quad.t0, color}
        vertices[vertex_count + 1] = {quad.x0, quad.y1, quad.s0, quad.t1, color}
        vertices[vertex_count + 2] = {quad.x1, quad.y1, quad.s1, quad.t1, color}

        // Second triangle (top-left, bottom-right, top-right)
        vertices[vertex_count + 3] = {quad.x0, quad.y0, quad.s0, quad.t0, color}
        vertices[vertex_count + 4] = {quad.x1, quad.y1, quad.s1, quad.t1, color}
        vertices[vertex_count + 5] = {quad.x1, quad.y0, quad.s1, quad.t0, color}

        vertex_count += 6
    }

    if vertex_count == 0 do return

    // Update font atlas texture (fontstash may have added new glyphs)
    dirty: [4]f32
    if fs.ValidateTexture(&renderer.font_context, &dirty) {
        // Texture was modified, update entire OpenGL texture
        // (Simpler and more reliable than partial updates)
        gl.BindTexture(gl.TEXTURE_2D, renderer.texture)
        gl.TexSubImage2D(
            gl.TEXTURE_2D, 0, 0, 0,
            i32(renderer.texture_width), i32(renderer.texture_height),
            gl.RED, gl.UNSIGNED_BYTE,
            raw_data(renderer.font_context.textureData),
        )
        gl.BindTexture(gl.TEXTURE_2D, 0)
    }

    // Upload vertices to GPU
    gl.BindBuffer(gl.ARRAY_BUFFER, renderer.vbo)
    gl.BufferSubData(gl.ARRAY_BUFFER, 0, vertex_count * size_of(fs.Vertex), raw_data(vertices[:]))

    // Render text
    gl.UseProgram(renderer.shader_program)
    gl.BindVertexArray(renderer.vao)
    gl.BindTexture(gl.TEXTURE_2D, renderer.texture)

    // Enable blending for text
    gl.Enable(gl.BLEND)
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

    // Disable depth test for 2D text overlay
    gl.Disable(gl.DEPTH_TEST)

    gl.DrawArrays(gl.TRIANGLES, 0, i32(vertex_count))

    // Restore state
    gl.Enable(gl.DEPTH_TEST)
    gl.Disable(gl.BLEND)

    gl.BindVertexArray(0)
    gl.BindTexture(gl.TEXTURE_2D, 0)
    gl.UseProgram(0)
}

// Measure text bounds
text_measure :: proc(renderer: ^TextRenderer, text: string, size: f32) -> (width: f32, height: f32) {
    fs.SetFont(&renderer.font_context, renderer.font_id)
    fs.SetSize(&renderer.font_context, size)

    bounds: [4]f32
    width_result := fs.TextBounds(&renderer.font_context, text, 0, 0, &bounds)

    return width_result, bounds[3] - bounds[1]
}

// Update font atlas texture (call after adding new glyphs)
text_renderer_update_texture :: proc(renderer: ^TextRenderer) {
    gl.BindTexture(gl.TEXTURE_2D, renderer.texture)
    gl.TexSubImage2D(
        gl.TEXTURE_2D, 0, 0, 0,
        i32(renderer.texture_width), i32(renderer.texture_height),
        gl.RED, gl.UNSIGNED_BYTE,
        raw_data(renderer.font_context.textureData),
    )
    gl.BindTexture(gl.TEXTURE_2D, 0)
}

// Create text shader program
create_text_shader :: proc() -> u32 {
    // Vertex shader - screen space 2D text
    vertex_source := `#version 330 core
layout (location = 0) in vec2 aPos;
layout (location = 1) in vec2 aTexCoord;
layout (location = 2) in vec4 aColor;

out vec2 TexCoord;
out vec4 Color;

uniform vec2 uScreenSize;

void main() {
    // Convert from pixel coordinates to NDC [-1, 1]
    vec2 ndc = (aPos / uScreenSize) * 2.0 - 1.0;
    ndc.y = -ndc.y;  // Flip Y (screen coordinates are top-down)

    gl_Position = vec4(ndc, 0.0, 1.0);
    TexCoord = aTexCoord;
    Color = aColor;
}
`

    // Fragment shader - sample from font atlas (single channel)
    fragment_source := `#version 330 core
in vec2 TexCoord;
in vec4 Color;

out vec4 FragColor;

uniform sampler2D uTexture;

void main() {
    float alpha = texture(uTexture, TexCoord).r;
    FragColor = vec4(Color.rgb, Color.a * alpha);
}
`

    // Compile vertex shader
    vertex_shader := gl.CreateShader(gl.VERTEX_SHADER)
    vertex_source_cstr := strings.clone_to_cstring(vertex_source)
    defer delete(vertex_source_cstr)
    gl.ShaderSource(vertex_shader, 1, &vertex_source_cstr, nil)
    gl.CompileShader(vertex_shader)

    // Check vertex shader compilation
    success: i32
    gl.GetShaderiv(vertex_shader, gl.COMPILE_STATUS, &success)
    if success == 0 {
        info_log: [512]u8
        gl.GetShaderInfoLog(vertex_shader, 512, nil, raw_data(info_log[:]))
        fmt.eprintf("ERROR: Text vertex shader compilation failed: %s\n", cstring(raw_data(info_log[:])))
        gl.DeleteShader(vertex_shader)
        return 0
    }

    // Compile fragment shader
    fragment_shader := gl.CreateShader(gl.FRAGMENT_SHADER)
    fragment_source_cstr := strings.clone_to_cstring(fragment_source)
    defer delete(fragment_source_cstr)
    gl.ShaderSource(fragment_shader, 1, &fragment_source_cstr, nil)
    gl.CompileShader(fragment_shader)

    // Check fragment shader compilation
    gl.GetShaderiv(fragment_shader, gl.COMPILE_STATUS, &success)
    if success == 0 {
        info_log: [512]u8
        gl.GetShaderInfoLog(fragment_shader, 512, nil, raw_data(info_log[:]))
        fmt.eprintf("ERROR: Text fragment shader compilation failed: %s\n", cstring(raw_data(info_log[:])))
        gl.DeleteShader(vertex_shader)
        gl.DeleteShader(fragment_shader)
        return 0
    }

    // Link shader program
    shader_program := gl.CreateProgram()
    gl.AttachShader(shader_program, vertex_shader)
    gl.AttachShader(shader_program, fragment_shader)
    gl.LinkProgram(shader_program)

    // Check linking
    gl.GetProgramiv(shader_program, gl.LINK_STATUS, &success)
    if success == 0 {
        info_log: [512]u8
        gl.GetProgramInfoLog(shader_program, 512, nil, raw_data(info_log[:]))
        fmt.eprintf("ERROR: Text shader program linking failed: %s\n", cstring(raw_data(info_log[:])))
        gl.DeleteShader(vertex_shader)
        gl.DeleteShader(fragment_shader)
        gl.DeleteProgram(shader_program)
        return 0
    }

    // Clean up shaders (no longer needed after linking)
    gl.DeleteShader(vertex_shader)
    gl.DeleteShader(fragment_shader)

    // Set uniform locations
    gl.UseProgram(shader_program)
    screen_size_loc := gl.GetUniformLocation(shader_program, "uScreenSize")
    texture_loc := gl.GetUniformLocation(shader_program, "uTexture")

    // Set default screen size (will be updated in render)
    gl.Uniform2f(screen_size_loc, 1280, 720)
    gl.Uniform1i(texture_loc, 0)  // Texture unit 0

    gl.UseProgram(0)

    return shader_program
}
