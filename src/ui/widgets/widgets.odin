// OhCAD Custom UI Framework - Immediate Mode Widgets
package widgets

import "core:fmt"
import sdl "vendor:sdl3"
import glsl "core:math/linalg/glsl"
import v "../viewer"

// =============================================================================
// UI Context - Holds state for immediate-mode UI
// =============================================================================

UIContext :: struct {
    // Rendering resources
    viewer: ^v.ViewerGPU,
    text_renderer: ^v.TextRendererGPU,

    // Current frame state
    cmd: ^sdl.GPUCommandBuffer,
    pass: ^sdl.GPURenderPass,
    screen_width: u32,
    screen_height: u32,

    // Mouse state
    mouse_x: f32,
    mouse_y: f32,
    mouse_down: bool,
    mouse_clicked: bool,  // True for one frame after mouse up

    // Widget ID tracking (for hover/active states)
    hot_id: u64,     // Widget under mouse
    active_id: u64,  // Widget being clicked
    next_id: u64,    // ID counter

    // UI interaction blocking
    mouse_over_ui: bool,  // True if mouse is over any UI element this frame

    // Style
    style: UIStyle,
}

UIStyle :: struct {
    // Colors (RGBA, 0-255)
    bg_dark: [4]u8,
    bg_medium: [4]u8,
    bg_light: [4]u8,
    text_primary: [4]u8,
    text_secondary: [4]u8,
    accent_primary: [4]u8,
    accent_secondary: [4]u8,

    // Sizes
    padding: f32,
    button_height: f32,
    icon_size: f32,
    font_size_normal: f32,
    font_size_small: f32,
}

// Create default dark technical style matching reference image
ui_default_style :: proc() -> UIStyle {
    return UIStyle{
        bg_dark = {20, 20, 25, 255},           // Very dark gray/black
        bg_medium = {40, 45, 50, 255},         // Medium dark gray
        bg_light = {60, 65, 70, 255},          // Lighter gray
        text_primary = {220, 220, 220, 255},   // Off-white
        text_secondary = {140, 145, 150, 255}, // Gray text
        accent_primary = {0, 200, 200, 255},   // Cyan/teal
        accent_secondary = {0, 255, 100, 255}, // Green accent

        padding = 8.0,
        button_height = 32.0,
        icon_size = 48.0,
        font_size_normal = 22.0,  // Increased from 16.0
        font_size_small = 18.0,   // Increased from 12.0
    }
}

// Initialize UI context
ui_context_init :: proc(
    viewer: ^v.ViewerGPU,
    text_renderer: ^v.TextRendererGPU,
) -> UIContext {
    return UIContext{
        viewer = viewer,
        text_renderer = text_renderer,
        style = ui_default_style(),
        next_id = 1,
    }
}

// Begin UI frame (call at start of frame)
ui_begin_frame :: proc(
    ctx: ^UIContext,
    cmd: ^sdl.GPUCommandBuffer,
    pass: ^sdl.GPURenderPass,
    screen_width: u32,
    screen_height: u32,
    mouse_x: f32,
    mouse_y: f32,
    mouse_down: bool,
) {
    ctx.cmd = cmd
    ctx.pass = pass
    ctx.screen_width = screen_width
    ctx.screen_height = screen_height
    ctx.mouse_x = mouse_x
    ctx.mouse_y = mouse_y

    // Detect click (mouse was down last frame, now up)
    ctx.mouse_clicked = !mouse_down && ctx.mouse_down
    ctx.mouse_down = mouse_down

    // Reset ID counter
    ctx.next_id = 1

    // Reset mouse over UI flag (will be set by widgets)
    ctx.mouse_over_ui = false

    // Clear hot widget if mouse not down
    if !mouse_down {
        ctx.hot_id = 0
    }
}

// End UI frame (call at end of frame)
ui_end_frame :: proc(ctx: ^UIContext) {
    // Clear active if no longer pressed
    if !ctx.mouse_down {
        ctx.active_id = 0
    }
}

// Generate unique widget ID
ui_gen_id :: proc(ctx: ^UIContext) -> u64 {
    id := ctx.next_id
    ctx.next_id += 1
    return id
}

// Check if point is inside rectangle
ui_point_in_rect :: proc(x, y, rx, ry, rw, rh: f32) -> bool {
    return x >= rx && x <= rx + rw && y >= ry && y <= ry + rh
}

// =============================================================================
// Low-Level Rendering Helpers
// =============================================================================

// Render filled rectangle
ui_render_rect :: proc(
    ctx: ^UIContext,
    x, y, width, height: f32,
    color: [4]u8,
) {
    // Convert to normalized color (0-1)
    color_f32 := [4]f32{
        f32(color.r) / 255.0,
        f32(color.g) / 255.0,
        f32(color.b) / 255.0,
        f32(color.a) / 255.0,
    }

    // Create 2 triangles for rectangle (in screen space)
    vertices := [6]v.LineVertex{
        {{x, y, 0}},                      // Top-left
        {{x + width, y, 0}},              // Top-right
        {{x, y + height, 0}},             // Bottom-left
        {{x, y + height, 0}},             // Bottom-left
        {{x + width, y, 0}},              // Top-right
        {{x + width, y + height, 0}},     // Bottom-right
    }

    // Upload vertices via transfer buffer
    buffer_size := u32(size_of(v.LineVertex) * 6)

    transfer_info := sdl.GPUTransferBufferCreateInfo{
        usage = .UPLOAD,
        size = buffer_size,
    }

    transfer_buffer := sdl.CreateGPUTransferBuffer(ctx.viewer.gpu_device, transfer_info)
    if transfer_buffer == nil do return
    defer sdl.ReleaseGPUTransferBuffer(ctx.viewer.gpu_device, transfer_buffer)

    transfer_ptr := sdl.MapGPUTransferBuffer(ctx.viewer.gpu_device, transfer_buffer, false)
    if transfer_ptr == nil do return

    dest_slice := ([^]v.LineVertex)(transfer_ptr)[:6]
    copy(dest_slice, vertices[:])
    sdl.UnmapGPUTransferBuffer(ctx.viewer.gpu_device, transfer_buffer)

    // Create temporary vertex buffer
    vertex_buffer_info := sdl.GPUBufferCreateInfo{
        usage = {.VERTEX},
        size = buffer_size,
    }

    temp_vertex_buffer := sdl.CreateGPUBuffer(ctx.viewer.gpu_device, vertex_buffer_info)
    if temp_vertex_buffer == nil do return
    defer sdl.ReleaseGPUBuffer(ctx.viewer.gpu_device, temp_vertex_buffer)

    // Upload to GPU
    upload_cmd := sdl.AcquireGPUCommandBuffer(ctx.viewer.gpu_device)
    copy_pass := sdl.BeginGPUCopyPass(upload_cmd)

    src := sdl.GPUTransferBufferLocation{
        transfer_buffer = transfer_buffer,
        offset = 0,
    }

    dst := sdl.GPUBufferRegion{
        buffer = temp_vertex_buffer,
        offset = 0,
        size = buffer_size,
    }

    sdl.UploadToGPUBuffer(copy_pass, src, dst, false)
    sdl.EndGPUCopyPass(copy_pass)
    _ = sdl.SubmitGPUCommandBuffer(upload_cmd)
    _ = sdl.WaitForGPUIdle(ctx.viewer.gpu_device)

    // Bind triangle pipeline
    sdl.BindGPUGraphicsPipeline(ctx.pass, ctx.viewer.triangle_pipeline)

    // Bind vertex buffer
    binding := sdl.GPUBufferBinding{
        buffer = temp_vertex_buffer,
        offset = 0,
    }
    sdl.BindGPUVertexBuffers(ctx.pass, 0, &binding, 1)

    // Create orthographic projection for 2D (screen space)
    ortho := glsl.mat4Ortho3d(0, f32(ctx.screen_width), f32(ctx.screen_height), 0, -1, 1)

    uniforms := v.Uniforms{
        mvp = ortho,
        color = color_f32,
    }

    sdl.PushGPUVertexUniformData(ctx.cmd, 0, &uniforms, size_of(v.Uniforms))
    sdl.PushGPUFragmentUniformData(ctx.cmd, 0, &uniforms, size_of(v.Uniforms))

    // Draw rectangle
    sdl.DrawGPUPrimitives(ctx.pass, 6, 1, 0, 0)

    // Switch back to line pipeline
    sdl.BindGPUGraphicsPipeline(ctx.pass, ctx.viewer.pipeline)
}

// Render text at screen position
ui_render_text :: proc(
    ctx: ^UIContext,
    text: string,
    x, y: f32,
    font_size: f32,
    color: [4]u8,
) {
    v.text_render_2d_gpu(
        ctx.text_renderer,
        ctx.cmd,
        ctx.pass,
        text,
        x, y,
        font_size,
        color,
        ctx.screen_width,
        ctx.screen_height,
    )
}

// Measure text size
ui_measure_text :: proc(
    ctx: ^UIContext,
    text: string,
    font_size: f32,
) -> (width: f32, height: f32) {
    return v.text_measure_gpu(ctx.text_renderer, text, font_size)
}

// =============================================================================
// Widget 1: Section Box (Title with colored accent rectangles)
// =============================================================================

ui_section_box :: proc(
    ctx: ^UIContext,
    x, y, width, height: f32,
    title: string,
    left_color: [4]u8,
    right_color: [4]u8,
) {
    accent_width: f32 = 4.0

    // Draw left accent
    ui_render_rect(ctx, x, y, accent_width, height, left_color)

    // Draw right accent
    ui_render_rect(ctx, x + width - accent_width, y, accent_width, height, right_color)

    // Draw main background (between accents)
    ui_render_rect(
        ctx,
        x + accent_width,
        y,
        width - accent_width * 2,
        height,
        ctx.style.bg_medium,
    )

    // Render title text (centered)
    text_width, text_height := ui_measure_text(ctx, title, ctx.style.font_size_normal)
    text_x := x + (width - text_width) * 0.5
    text_y := y + (height - text_height) * 0.5

    ui_render_text(ctx, title, text_x, text_y, ctx.style.font_size_normal, ctx.style.text_primary)
}

// =============================================================================
// Widget 2: Text Button (Simple rectangle with text)
// =============================================================================

ui_text_button :: proc(
    ctx: ^UIContext,
    x, y, width, height: f32,
    text: string,
) -> bool {
    id := ui_gen_id(ctx)

    // Check if mouse is over button
    is_hot := ui_point_in_rect(ctx.mouse_x, ctx.mouse_y, x, y, width, height)

    // Mark mouse over UI if hot
    if is_hot {
        ctx.mouse_over_ui = true
        ctx.hot_id = id
        if ctx.mouse_down && ctx.active_id == 0 {
            ctx.active_id = id
        }
    }

    // Determine button state
    is_active := ctx.active_id == id
    clicked := is_active && ctx.mouse_clicked && ctx.hot_id == id

    // Choose background color based on state
    bg_color := ctx.style.bg_medium
    if is_active {
        bg_color = ctx.style.bg_light
    } else if is_hot {
        bg_color = ctx.style.bg_medium
        bg_color.r += 10
        bg_color.g += 10
        bg_color.b += 10
    }

    // Draw button background
    ui_render_rect(ctx, x, y, width, height, bg_color)

    // Draw border (subtle)
    border_color := ctx.style.bg_light
    border_width: f32 = 1.0

    // Top border
    ui_render_rect(ctx, x, y, width, border_width, border_color)
    // Bottom border
    ui_render_rect(ctx, x, y + height - border_width, width, border_width, border_color)
    // Left border
    ui_render_rect(ctx, x, y, border_width, height, border_color)
    // Right border
    ui_render_rect(ctx, x + width - border_width, y, border_width, height, border_color)

    // Render text (centered)
    text_width, text_height := ui_measure_text(ctx, text, ctx.style.font_size_normal)
    text_x := x + (width - text_width) * 0.5
    text_y := y + (height - text_height) * 0.5

    text_color := is_active ? ctx.style.text_primary : ctx.style.text_secondary
    ui_render_text(ctx, text, text_x, text_y, ctx.style.font_size_normal, text_color)

    return clicked
}

// =============================================================================
// Widget 7: Toggle Switch (On/Off switch)
// =============================================================================

ui_toggle :: proc(
    ctx: ^UIContext,
    x, y, width, height: f32,
    label: string,
    value: ^bool,
) -> bool {
    changed := false
    id := ui_gen_id(ctx)

    // Check if mouse is over toggle
    is_hot := ui_point_in_rect(ctx.mouse_x, ctx.mouse_y, x, y, width, height)

    // Mark mouse over UI if hot
    if is_hot {
        ctx.mouse_over_ui = true
        ctx.hot_id = id
        if ctx.mouse_down && ctx.active_id == 0 {
            ctx.active_id = id
        }
    }

    // Detect click
    is_pressed := ctx.active_id == id
    if is_pressed && ctx.mouse_clicked && ctx.hot_id == id {
        value^ = !value^
        changed = true
    }

    // Draw background
    bg_color := ctx.style.bg_dark
    if is_hot {
        bg_color.r += 10
        bg_color.g += 10
        bg_color.b += 10
    }
    ui_render_rect(ctx, x, y, width, height, bg_color)

    // Draw border
    border_color := ctx.style.bg_light
    border_width: f32 = 1.0
    ui_render_rect(ctx, x, y, width, border_width, border_color)
    ui_render_rect(ctx, x, y + height - border_width, width, border_width, border_color)
    ui_render_rect(ctx, x, y, border_width, height, border_color)
    ui_render_rect(ctx, x + width - border_width, y, border_width, height, border_color)

    // Draw label
    text_x := x + ctx.style.padding
    text_y := y + (height - ctx.style.font_size_small) * 0.5
    ui_render_text(ctx, label, text_x, text_y, ctx.style.font_size_small, ctx.style.text_primary)

    // Draw switch on the right
    switch_width: f32 = 40
    switch_height: f32 = 20
    switch_x := x + width - ctx.style.padding - switch_width
    switch_y := y + (height - switch_height) * 0.5

    // Switch track color (on = green, off = dark)
    track_color := value^ ? ctx.style.accent_secondary : ctx.style.bg_medium
    ui_render_rect(ctx, switch_x, switch_y, switch_width, switch_height, track_color)

    // Switch handle (small circle/square)
    handle_size: f32 = switch_height - 4
    handle_x := value^ ? (switch_x + switch_width - handle_size - 2) : (switch_x + 2)
    handle_y := switch_y + 2
    handle_color := ctx.style.text_primary
    ui_render_rect(ctx, handle_x, handle_y, handle_size, handle_size, handle_color)

    return changed
}

// =============================================================================
// Widget 8: Radio Button (Mutually exclusive option)
// =============================================================================

ui_radio_button :: proc(
    ctx: ^UIContext,
    x, y, size: f32,
    label: string,
    selected: bool,
) -> bool {
    clicked := false
    id := ui_gen_id(ctx)

    // Total width includes label
    text_width, _ := ui_measure_text(ctx, label, ctx.style.font_size_small)
    total_width := size + ctx.style.padding + text_width

    // Check if mouse is over radio button
    is_hot := ui_point_in_rect(ctx.mouse_x, ctx.mouse_y, x, y, total_width, size)

    // Mark mouse over UI if hot
    if is_hot {
        ctx.mouse_over_ui = true
        ctx.hot_id = id
        if ctx.mouse_down && ctx.active_id == 0 {
            ctx.active_id = id
        }
    }

    // Detect click
    is_pressed := ctx.active_id == id
    if is_pressed && ctx.mouse_clicked && ctx.hot_id == id {
        clicked = true
    }

    // Draw radio button circle (simplified as square for now)
    border_color := selected ? ctx.style.accent_primary : ctx.style.bg_light
    bg_color := is_hot ? ctx.style.bg_medium : ctx.style.bg_dark

    // Outer square (simulating circle)
    ui_render_rect(ctx, x, y, size, size, bg_color)

    // Border
    border_width: f32 = 2.0
    ui_render_rect(ctx, x, y, size, border_width, border_color)
    ui_render_rect(ctx, x, y + size - border_width, size, border_width, border_color)
    ui_render_rect(ctx, x, y, border_width, size, border_color)
    ui_render_rect(ctx, x + size - border_width, y, border_width, size, border_color)

    // Inner dot if selected
    if selected {
        inner_size := size * 0.5
        inner_offset := (size - inner_size) * 0.5
        ui_render_rect(ctx, x + inner_offset, y + inner_offset, inner_size, inner_size, ctx.style.accent_primary)
    }

    // Draw label
    label_x := x + size + ctx.style.padding
    label_y := y + (size - ctx.style.font_size_small) * 0.5
    ui_render_text(ctx, label, label_x, label_y, ctx.style.font_size_small, ctx.style.text_primary)

    return clicked
}

// =============================================================================
// Widget 9: Color Picker (Simple RGB selector)
// =============================================================================

ui_color_picker :: proc(
    ctx: ^UIContext,
    x, y, width, height: f32,
    label: string,
    color: ^[3]u8,
) -> bool {
    changed := false
    id := ui_gen_id(ctx)

    // Check if mouse is over picker
    is_hot := ui_point_in_rect(ctx.mouse_x, ctx.mouse_y, x, y, width, height)

    // Mark mouse over UI if hot
    if is_hot {
        ctx.mouse_over_ui = true
        ctx.hot_id = id
        if ctx.mouse_down && ctx.active_id == 0 {
            ctx.active_id = id
        }
    }

    // Detect click
    is_pressed := ctx.active_id == id
    clicked := is_pressed && ctx.mouse_clicked && ctx.hot_id == id

    // Draw background
    bg_color := ctx.style.bg_dark
    if is_hot {
        bg_color.r += 10
        bg_color.g += 10
        bg_color.b += 10
    }
    ui_render_rect(ctx, x, y, width, height, bg_color)

    // Draw border
    border_color := is_pressed ? ctx.style.accent_primary : ctx.style.bg_light
    border_width: f32 = 1.0
    ui_render_rect(ctx, x, y, width, border_width, border_color)
    ui_render_rect(ctx, x, y + height - border_width, width, border_width, border_color)
    ui_render_rect(ctx, x, y, border_width, height, border_color)
    ui_render_rect(ctx, x + width - border_width, y, border_width, height, border_color)

    // Draw label
    text_x := x + ctx.style.padding
    text_y := y + (height - ctx.style.font_size_small) * 0.5
    ui_render_text(ctx, label, text_x, text_y, ctx.style.font_size_small, ctx.style.text_primary)

    // Draw color preview swatch on the right
    swatch_size: f32 = height - 8
    swatch_x := x + width - ctx.style.padding - swatch_size
    swatch_y := y + 4

    preview_color := [4]u8{color.r, color.g, color.b, 255}
    ui_render_rect(ctx, swatch_x, swatch_y, swatch_size, swatch_size, preview_color)

    // Draw swatch border
    ui_render_rect(ctx, swatch_x, swatch_y, swatch_size, 1, ctx.style.text_secondary)
    ui_render_rect(ctx, swatch_x, swatch_y + swatch_size - 1, swatch_size, 1, ctx.style.text_secondary)
    ui_render_rect(ctx, swatch_x, swatch_y, 1, swatch_size, ctx.style.text_secondary)
    ui_render_rect(ctx, swatch_x + swatch_size - 1, swatch_y, 1, swatch_size, ctx.style.text_secondary)

    return clicked
}

// =============================================================================
// Widget 10: Numeric Stepper (Value with +/- buttons)
// =============================================================================

ui_numeric_stepper :: proc(
    ctx: ^UIContext,
    x, y, width, height: f32,
    label: string,
    value: ^f32,
    step: f32,
    min_value: f32,
    max_value: f32,
) -> bool {
    changed := false

    // Layout: [Label] [Value] [-] [+]
    button_size: f32 = height
    value_width: f32 = 60
    label_width := width - value_width - button_size * 2 - ctx.style.padding * 3

    label_x := x
    value_x := x + label_width + ctx.style.padding
    minus_x := value_x + value_width + ctx.style.padding
    plus_x := minus_x + button_size + ctx.style.padding

    // Draw label
    label_y := y + (height - ctx.style.font_size_small) * 0.5
    ui_render_text(ctx, label, label_x, label_y, ctx.style.font_size_small, ctx.style.text_secondary)

    // Draw value box
    ui_render_rect(ctx, value_x, y, value_width, height, ctx.style.bg_dark)

    // Border around value
    border_color := ctx.style.bg_light
    border_width: f32 = 1.0
    ui_render_rect(ctx, value_x, y, value_width, border_width, border_color)
    ui_render_rect(ctx, value_x, y + height - border_width, value_width, border_width, border_color)
    ui_render_rect(ctx, value_x, y, border_width, height, border_color)
    ui_render_rect(ctx, value_x + value_width - border_width, y, border_width, height, border_color)

    // Render value text
    value_text := fmt.tprintf("%.2f", value^)
    text_width, text_height := ui_measure_text(ctx, value_text, ctx.style.font_size_small)
    text_x := value_x + (value_width - text_width) * 0.5
    text_y := y + (height - text_height) * 0.5
    ui_render_text(ctx, value_text, text_x, text_y, ctx.style.font_size_small, ctx.style.text_primary)

    // Minus button
    if ui_text_button(ctx, minus_x, y, button_size, height, "-") {
        new_value := value^ - step
        if new_value >= min_value {
            value^ = new_value
            changed = true
        }
    }

    // Plus button
    if ui_text_button(ctx, plus_x, y, button_size, height, "+") {
        new_value := value^ + step
        if new_value <= max_value {
            value^ = new_value
            changed = true
        }
    }

    return changed
}

// =============================================================================
// Widget 3: Tool Icon (Square with letters and colored accent line)
// =============================================================================

ui_tool_icon :: proc(
    ctx: ^UIContext,
    x, y, size: f32,
    icon_text: string,
    accent_color: [4]u8,
    active: bool,
) -> bool {
    id := ui_gen_id(ctx)

    // Check if mouse is over icon
    is_hot := ui_point_in_rect(ctx.mouse_x, ctx.mouse_y, x, y, size, size)

    // Mark mouse over UI if hot
    if is_hot {
        ctx.mouse_over_ui = true
        ctx.hot_id = id
        if ctx.mouse_down && ctx.active_id == 0 {
            ctx.active_id = id
        }
    }

    // Determine icon state
    is_pressed := ctx.active_id == id
    clicked := is_pressed && ctx.mouse_clicked && ctx.hot_id == id

    // Choose background color based on state
    bg_color := ctx.style.bg_medium
    if active {
        bg_color = ctx.style.bg_light
    } else if is_pressed {
        bg_color = ctx.style.bg_light
    } else if is_hot {
        bg_color = ctx.style.bg_medium
        bg_color.r += 10
        bg_color.g += 10
        bg_color.b += 10
    }

    // Draw main background
    ui_render_rect(ctx, x, y, size, size, bg_color)

    // Draw accent line at bottom right
    accent_height: f32 = 3.0
    accent_width: f32 = size * 0.4  // 40% of icon width

    ui_render_rect(
        ctx,
        x + size - accent_width,
        y + size - accent_height,
        accent_width,
        accent_height,
        accent_color,
    )

    // Draw border if active
    if active {
        border_color := ctx.style.accent_primary
        border_width: f32 = 2.0

        // Top border
        ui_render_rect(ctx, x, y, size, border_width, border_color)
        // Bottom border
        ui_render_rect(ctx, x, y + size - border_width, size, border_width, border_color)
        // Left border
        ui_render_rect(ctx, x, y, border_width, size, border_color)
        // Right border
        ui_render_rect(ctx, x + size - border_width, y, border_width, size, border_color)
    }

    // Render icon text (centered, large font)
    font_size := size * 0.65  // 65% of icon size for text
    text_width, text_height := ui_measure_text(ctx, icon_text, font_size)
    text_x := x + (size - text_width) * 0.5
    text_y := y + (size - text_height) * 0.5

    text_color := active ? ctx.style.text_primary : ctx.style.text_secondary
    ui_render_text(ctx, icon_text, text_x, text_y, font_size, text_color)

    return clicked
}

// =============================================================================
// Widget 4: Slider (Value input + slider track + handle)
// =============================================================================

ui_slider :: proc(
    ctx: ^UIContext,
    x, y, width, height: f32,
    value: ^f32,
    min_value: f32,
    max_value: f32,
) -> bool {
    changed := false

    // Layout: [Value Input Box]:[Slider Track + Handle]
    input_width: f32 = 50
    colon_width: f32 = 10
    slider_width := width - input_width - colon_width

    input_x := x
    colon_x := x + input_width
    slider_x := colon_x + colon_width

    // Draw value input box
    ui_render_rect(ctx, input_x, y, input_width, height, ctx.style.bg_dark)

    // Draw border around input
    border_color := ctx.style.bg_light
    border_width: f32 = 1.0
    ui_render_rect(ctx, input_x, y, input_width, border_width, border_color)
    ui_render_rect(ctx, input_x, y + height - border_width, input_width, border_width, border_color)
    ui_render_rect(ctx, input_x, y, border_width, height, border_color)
    ui_render_rect(ctx, input_x + input_width - border_width, y, border_width, height, border_color)

    // Render value text
    value_text := fmt.tprintf("%.2f", value^)
    text_width, text_height := ui_measure_text(ctx, value_text, ctx.style.font_size_small)
    text_x := input_x + (input_width - text_width) * 0.5
    text_y := y + (height - text_height) * 0.5
    ui_render_text(ctx, value_text, text_x, text_y, ctx.style.font_size_small, ctx.style.text_primary)

    // Draw colon separator
    colon_text_width, colon_text_height := ui_measure_text(ctx, ":", ctx.style.font_size_normal)
    colon_text_x := colon_x + (colon_width - colon_text_width) * 0.5
    colon_text_y := y + (height - colon_text_height) * 0.5
    ui_render_text(ctx, ":", colon_text_x, colon_text_y, ctx.style.font_size_normal, ctx.style.text_secondary)

    // Calculate normalized value
    normalized := (value^ - min_value) / (max_value - min_value)
    if normalized < 0 do normalized = 0
    if normalized > 1 do normalized = 1

    // Draw slider track background (full width)
    track_height: f32 = height - 4
    track_y := y + 2
    ui_render_rect(ctx, slider_x, track_y, slider_width, track_height, ctx.style.bg_dark)

    // Draw filled portion (from left to handle position)
    filled_width := slider_width * normalized
    if filled_width > 0 {
        fill_color := ctx.style.accent_primary
        fill_color.a = 100  // Semi-transparent
        ui_render_rect(ctx, slider_x, track_y, filled_width, track_height, fill_color)
    }

    // Draw track border (matching other widgets)
    track_border_color := ctx.style.bg_light
    track_border_width: f32 = 1.0
    ui_render_rect(ctx, slider_x, track_y, slider_width, track_border_width, track_border_color)
    ui_render_rect(ctx, slider_x, track_y + track_height - track_border_width, slider_width, track_border_width, track_border_color)
    ui_render_rect(ctx, slider_x, track_y, track_border_width, track_height, track_border_color)
    ui_render_rect(ctx, slider_x + slider_width - track_border_width, track_y, track_border_width, track_height, track_border_color)

    // Calculate handle position
    handle_width: f32 = 12
    handle_height: f32 = height - 4
    handle_x := slider_x + (slider_width - handle_width) * normalized
    handle_y := y + 2

    // Check if mouse is over slider area
    id := ui_gen_id(ctx)
    is_hot := ui_point_in_rect(ctx.mouse_x, ctx.mouse_y, slider_x, y, slider_width, height)

    // Handle interaction
    if is_hot {
        ctx.mouse_over_ui = true
        ctx.hot_id = id
        if ctx.mouse_down && ctx.active_id == 0 {
            ctx.active_id = id
        }
    }

    // Update value if dragging
    if ctx.active_id == id && ctx.mouse_down {
        // Calculate new value from mouse position
        mouse_offset := ctx.mouse_x - slider_x
        new_normalized := mouse_offset / slider_width
        if new_normalized < 0 do new_normalized = 0
        if new_normalized > 1 do new_normalized = 1

        new_value := min_value + new_normalized * (max_value - min_value)
        if new_value != value^ {
            value^ = new_value
            changed = true
        }
    }

    // Choose handle color based on state
    handle_color := ctx.style.bg_light
    if ctx.active_id == id {
        handle_color = ctx.style.accent_primary
    } else if is_hot {
        handle_color = ctx.style.bg_light
        handle_color.r += 20
        handle_color.g += 20
        handle_color.b += 20
    }

    // Draw slider handle
    ui_render_rect(ctx, handle_x, handle_y, handle_width, handle_height, handle_color)

    return changed
}

// =============================================================================
// Widget 5: Dropdown Menu (Text box with dropdown arrow)
// =============================================================================

ui_dropdown :: proc(
    ctx: ^UIContext,
    x, y, width, height: f32,
    label: string,
    selected_item: string,
    is_open: ^bool,
) -> bool {
    clicked := false
    id := ui_gen_id(ctx)

    // Check if mouse is over dropdown
    is_hot := ui_point_in_rect(ctx.mouse_x, ctx.mouse_y, x, y, width, height)

    // Mark mouse over UI if hot
    if is_hot {
        ctx.mouse_over_ui = true
        ctx.hot_id = id
        if ctx.mouse_down && ctx.active_id == 0 {
            ctx.active_id = id
        }
    }

    // Detect click
    is_pressed := ctx.active_id == id
    if is_pressed && ctx.mouse_clicked && ctx.hot_id == id {
        clicked = true
        is_open^ = !is_open^  // Toggle open/closed
    }

    // Choose background color
    bg_color := ctx.style.bg_dark
    if is_pressed || is_open^ {
        bg_color = ctx.style.bg_medium
    } else if is_hot {
        bg_color = ctx.style.bg_dark
        bg_color.r += 10
        bg_color.g += 10
        bg_color.b += 10
    }

    // Draw main background
    ui_render_rect(ctx, x, y, width, height, bg_color)

    // Draw border
    border_color := ctx.style.bg_light
    border_width: f32 = 1.0
    ui_render_rect(ctx, x, y, width, border_width, border_color)
    ui_render_rect(ctx, x, y + height - border_width, width, border_width, border_color)
    ui_render_rect(ctx, x, y, border_width, height, border_color)
    ui_render_rect(ctx, x + width - border_width, y, border_width, height, border_color)

    // Draw text (label + selected item)
    full_text := fmt.tprintf("%s: %s", label, selected_item)
    text_width, text_height := ui_measure_text(ctx, full_text, ctx.style.font_size_small)
    text_x := x + ctx.style.padding
    text_y := y + (height - text_height) * 0.5
    ui_render_text(ctx, full_text, text_x, text_y, ctx.style.font_size_small, ctx.style.text_primary)

    // Draw dropdown arrow (small triangle)
    arrow_size: f32 = 6
    arrow_x := x + width - ctx.style.padding - arrow_size
    arrow_y := y + (height - arrow_size) * 0.5

    // Simple arrow using rectangles (inverted V shape)
    // Left diagonal
    ui_render_rect(ctx, arrow_x, arrow_y + arrow_size * 0.3, arrow_size * 0.5, 2, ctx.style.text_secondary)
    // Right diagonal
    ui_render_rect(ctx, arrow_x + arrow_size * 0.5, arrow_y + arrow_size * 0.3, arrow_size * 0.5, 2, ctx.style.text_secondary)

    return clicked
}

// =============================================================================
// Widget 6: Text Input (Editable text field)
// =============================================================================

ui_text_input :: proc(
    ctx: ^UIContext,
    x, y, width, height: f32,
    label: string,
    text: string,
) -> bool {
    clicked := false
    id := ui_gen_id(ctx)

    // Check if mouse is over input
    is_hot := ui_point_in_rect(ctx.mouse_x, ctx.mouse_y, x, y, width, height)

    // Mark mouse over UI if hot
    if is_hot {
        ctx.mouse_over_ui = true
        ctx.hot_id = id
        if ctx.mouse_down && ctx.active_id == 0 {
            ctx.active_id = id
        }
    }

    // Detect click
    is_pressed := ctx.active_id == id
    if is_pressed && ctx.mouse_clicked && ctx.hot_id == id {
        clicked = true
    }

    // Choose background color
    bg_color := ctx.style.bg_dark
    if is_pressed {
        bg_color = ctx.style.bg_medium
    } else if is_hot {
        bg_color = ctx.style.bg_dark
        bg_color.r += 10
        bg_color.g += 10
        bg_color.b += 10
    }

    // Draw main background
    ui_render_rect(ctx, x, y, width, height, bg_color)

    // Draw border
    border_color := ctx.style.bg_light
    if is_pressed {
        border_color = ctx.style.accent_primary  // Highlight when focused
    }
    border_width: f32 = 1.0
    ui_render_rect(ctx, x, y, width, border_width, border_color)
    ui_render_rect(ctx, x, y + height - border_width, width, border_width, border_color)
    ui_render_rect(ctx, x, y, border_width, height, border_color)
    ui_render_rect(ctx, x + width - border_width, y, border_width, height, border_color)

    // Draw text (label + input text)
    full_text := label != "" ? fmt.tprintf("%s: %s", label, text) : text
    text_width, text_height := ui_measure_text(ctx, full_text, ctx.style.font_size_small)
    text_x := x + ctx.style.padding
    text_y := y + (height - text_height) * 0.5
    ui_render_text(ctx, full_text, text_x, text_y, ctx.style.font_size_small, ctx.style.text_primary)

    // Draw cursor if focused (simple blinking line)
    if is_pressed {
        cursor_x := text_x + text_width + 2
        cursor_y := y + 4
        cursor_height := height - 8
        ui_render_rect(ctx, cursor_x, cursor_y, 2, cursor_height, ctx.style.accent_primary)
    }

    return clicked
}
