// OhCAD Interactive Sketcher Application (SDL3 GPU Version)
package main

import "core:fmt"
import "core:os"
import "base:runtime"
import v "ui/viewer"
import ui "ui/widgets"
import sketch "features/sketch"
import extrude "features/extrude"
import ftree "features/feature_tree"
import m "core/math"
import glsl "core:math/linalg/glsl"
import sdl "vendor:sdl3"

// Application state
AppStateGPU :: struct {
    viewer: ^v.ViewerGPU,
    text_renderer: v.TextRendererGPU,
    ui_context: ui.UIContext,  // UI framework context
    cad_ui_state: ui.CADUIState,  // CAD-specific UI state
    sketch: ^sketch.Sketch2D,
    wireframe: v.WireframeMeshGPU,
    wireframe_selected: v.WireframeMeshGPU,

    // Feature tree (parametric system)
    feature_tree: ftree.FeatureTree,
    sketch_feature_id: int,
    extrude_feature_id: int,

    // Wireframe cache for all solids
    solid_wireframes: [dynamic]v.WireframeMeshGPU,

    // Update flags
    needs_wireframe_update: bool,
    needs_selection_update: bool,
    needs_solid_update: bool,

    // Input state for sketch interaction
    mouse_x: f64,
    mouse_y: f64,
    mouse_down_left: bool,  // Track left mouse button separately
    ctrl_held: bool,
}

// Apply horizontal constraint to selected line
apply_horizontal_constraint :: proc(app: ^AppStateGPU) {
    if app.sketch.selected_entity < 0 {
        fmt.println("❌ No entity selected - select a line first")
        return
    }

    entity := app.sketch.entities[app.sketch.selected_entity]

    _, is_line := entity.(sketch.SketchLine)
    if !is_line {
        fmt.println("❌ Selected entity is not a line - horizontal constraint requires a line")
        return
    }

    sketch.sketch_add_constraint(app.sketch, .Horizontal, sketch.HorizontalData{
        line_id = app.sketch.selected_entity,
    })

    fmt.printf("✅ Horizontal constraint added to line %d\n", app.sketch.selected_entity)
}

// Apply vertical constraint to selected line
apply_vertical_constraint :: proc(app: ^AppStateGPU) {
    if app.sketch.selected_entity < 0 {
        fmt.println("❌ No entity selected - select a line first")
        return
    }

    entity := app.sketch.entities[app.sketch.selected_entity]

    _, is_line := entity.(sketch.SketchLine)
    if !is_line {
        fmt.println("❌ Selected entity is not a line - vertical constraint requires a line")
        return
    }

    sketch.sketch_add_constraint(app.sketch, .Vertical, sketch.VerticalData{
        line_id = app.sketch.selected_entity,
    })

    fmt.printf("✅ Vertical constraint added to line %d\n", app.sketch.selected_entity)
}

// Solve all constraints
solve_constraints :: proc(app: ^AppStateGPU) {
    fmt.println("\n=== Running Constraint Solver ===")

    result := sketch.sketch_solve_constraints(app.sketch)
    sketch.solver_result_print(result)

    if result.status == .Success {
        fmt.println("✅ Constraints solved! Geometry updated.")
        app.needs_wireframe_update = true
        app.needs_selection_update = true
    } else if result.status == .Underconstrained {
        fmt.println("⚠️  Sketch needs more constraints to be fully defined")
    } else if result.status == .Overconstrained {
        fmt.println("❌ Sketch has conflicting constraints")
    } else if result.status == .MaxIterations {
        fmt.println("⚠️  Solver reached maximum iterations without converging")
    } else if result.status == .NumericalError {
        fmt.println("❌ Numerical error during solving")
    }
}

main :: proc() {
    fmt.println("=== OhCAD Interactive Sketcher (SDL3 GPU) ===")

    // Initialize SDL3 GPU viewer
    viewer_inst, ok := v.viewer_gpu_init()
    if !ok {
        fmt.eprintln("Failed to initialize SDL3 GPU viewer")
        return
    }
    defer v.viewer_gpu_destroy(viewer_inst)

    // Load shader data for text renderer
    shader_data, shader_ok := read_entire_file_or_exit("src/ui/viewer/shaders/line_shader.metallib")
    if !shader_ok {
        return
    }
    defer delete(shader_data)

    // Initialize text renderer
    text_renderer, text_ok := v.text_renderer_gpu_init(viewer_inst.gpu_device, viewer_inst.window, shader_data)
    if !text_ok {
        fmt.eprintln("Failed to initialize text renderer")
        return
    }
    defer v.text_renderer_gpu_destroy(&text_renderer)

    // Create a sketch on XY plane
    fmt.println("\nCreating sketch...")
    sk := new(sketch.Sketch2D)
    sk^ = sketch.sketch_init("InteractiveSketch", sketch.sketch_plane_xy())

    sketch.sketch_set_tool(sk, .Select)

    // Initial wireframe (empty)
    wireframe := v.sketch_to_wireframe_gpu(sk)
    defer v.wireframe_mesh_gpu_destroy(&wireframe)

    // Initial selection wireframe (empty)
    wireframe_selected := v.sketch_to_wireframe_selected_gpu(sk)
    defer v.wireframe_mesh_gpu_destroy(&wireframe_selected)

    // Initialize feature tree
    feature_tree := ftree.feature_tree_init()
    defer ftree.feature_tree_destroy(&feature_tree)

    // Add sketch as first feature
    sketch_feature_id := ftree.feature_tree_add_sketch(&feature_tree, sk, "Sketch001")

    // Create app state
    app := new(AppStateGPU)
    app.viewer = viewer_inst
    app.text_renderer = text_renderer
    app.ui_context = ui.ui_context_init(viewer_inst, &text_renderer)
    app.cad_ui_state = ui.cad_ui_state_init()
    app.sketch = sk
    app.wireframe = wireframe
    app.wireframe_selected = wireframe_selected
    app.feature_tree = feature_tree
    app.sketch_feature_id = sketch_feature_id
    app.extrude_feature_id = -1
    app.solid_wireframes = make([dynamic]v.WireframeMeshGPU)
    app.needs_wireframe_update = false
    app.needs_selection_update = false

    defer {
        for &mesh in app.solid_wireframes {
            v.wireframe_mesh_gpu_destroy(&mesh)
        }
        delete(app.solid_wireframes)
        free(app)
    }

    sketch.sketch_print_info(sk)

    fmt.println("\nControls:")
    fmt.println("  [S] Select tool (default)")
    fmt.println("  [L] Line tool")
    fmt.println("  [C] Circle tool")
    fmt.println("  [D] Dimension tool")
    fmt.println("  [ESC] Cancel tool")
    fmt.println("")
    fmt.println("  [H] Horizontal constraint")
    fmt.println("  [V] Vertical constraint")
    fmt.println("  [X] Solve constraints")
    fmt.println("  [P] Print profile detection")
    fmt.println("  [E] Extrude sketch")
    fmt.println("  [+]/[-] Change extrude depth")
    fmt.println("  [R] Regenerate all features")
    fmt.println("  [F] Print feature tree")
    fmt.println("")
    fmt.println("  [DELETE] Delete selected")
    fmt.println("  [HOME] Reset camera")
    fmt.println("  [Q] Quit\n")

    // Main render loop
    for v.viewer_gpu_should_continue(viewer_inst) {
        // Poll events and handle input
        handle_events_gpu(app)

        // Update wireframe if needed
        if app.needs_wireframe_update {
            v.wireframe_mesh_gpu_destroy(&app.wireframe)
            app.wireframe = v.sketch_to_wireframe_gpu(app.sketch)
            app.needs_wireframe_update = false
        }

        // Update selection wireframe if needed
        if app.needs_selection_update {
            v.wireframe_mesh_gpu_destroy(&app.wireframe_selected)
            app.wireframe_selected = v.sketch_to_wireframe_selected_gpu(app.sketch)
            app.needs_selection_update = false
        }

        // Render frame
        render_frame_gpu(app)
    }

    fmt.println("\nFinal sketch:")
    sketch.sketch_print_info(sk)
    fmt.println("Viewer closed successfully")
}

// Handle SDL3 events
handle_events_gpu :: proc(app: ^AppStateGPU) {
    event: sdl.Event

    for sdl.PollEvent(&event) {
        #partial switch event.type {
        case .QUIT:
            app.viewer.should_close = true

        case .KEY_DOWN:
            handle_key_down_gpu(app, event.key.key, event.key.mod)

        case .KEY_UP:
            handle_key_up_gpu(app, event.key.key, event.key.mod)

        case .MOUSE_MOTION:
            app.mouse_x = f64(event.motion.x)
            app.mouse_y = f64(event.motion.y)

            // Update cursor preview
            sketch_pos, ok := screen_to_sketch_gpu(app, app.mouse_x, app.mouse_y)
            if ok {
                world_pos := sketch.sketch_to_world(&app.sketch.plane, sketch_pos)
                sketch.sketch_update_cursor(app.sketch, world_pos)
            }

            // Handle camera movement via viewer
            v.viewer_gpu_handle_mouse_motion(app.viewer, &event.motion)

        case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP:
            // Track left button state for UI
            if event.button.button == u8(sdl.BUTTON_LEFT) {
                app.mouse_down_left = event.button.down
            }

            handle_mouse_button_gpu(app, &event.button)
            v.viewer_gpu_handle_mouse_button(app.viewer, &event.button)

        case .MOUSE_WHEEL:
            v.viewer_gpu_handle_mouse_wheel(app.viewer, &event.wheel)

        case .FINGER_DOWN, .FINGER_UP, .FINGER_MOTION:
            v.viewer_gpu_handle_finger(app.viewer, &event)
        }
    }
}

// Handle key down events
handle_key_down_gpu :: proc(app: ^AppStateGPU, key: sdl.Keycode, mods: sdl.Keymod) {
    // Track modifiers
    if key == sdl.K_LCTRL || key == sdl.K_RCTRL {
        app.ctrl_held = true
    }

    switch key {
    case sdl.K_Q, sdl.K_ESCAPE:
        if key == sdl.K_Q {
            app.viewer.should_close = true
        } else if key == sdl.K_ESCAPE {
            sketch.sketch_cancel_tool(app.sketch)
            sketch.sketch_set_tool(app.sketch, .Select)
            fmt.println("Tool cancelled - switched to Select mode")
        }

    case sdl.K_L:
        sketch.sketch_set_tool(app.sketch, .Line)
        fmt.println("Tool: Line")

    case sdl.K_C:
        sketch.sketch_set_tool(app.sketch, .Circle)
        fmt.println("Tool: Circle")

    case sdl.K_D:
        sketch.sketch_set_tool(app.sketch, .Dimension)
        fmt.println("Tool: Dimension")

    case sdl.K_S:
        sketch.sketch_set_tool(app.sketch, .Select)
        fmt.println("Tool: Select")

    case sdl.K_DELETE, sdl.K_BACKSPACE:
        if sketch.sketch_delete_selected(app.sketch) {
            app.needs_wireframe_update = true
            app.needs_selection_update = true
        }

    case sdl.K_HOME:
        v.camera_init(&app.viewer.camera, app.viewer.camera.aspect_ratio)

    case sdl.K_H:
        apply_horizontal_constraint(app)

    case sdl.K_V:
        apply_vertical_constraint(app)

    case sdl.K_X:
        solve_constraints(app)

    case sdl.K_P:
        sketch.sketch_print_profiles(app.sketch)

    case sdl.K_E:
        test_extrude_gpu(app)

    case sdl.K_EQUALS, sdl.K_KP_PLUS:
        change_extrude_depth_gpu(app, 0.1)

    case sdl.K_MINUS, sdl.K_KP_MINUS:
        change_extrude_depth_gpu(app, -0.1)

    case sdl.K_R:
        ftree.feature_tree_regenerate_all(&app.feature_tree)
        update_solid_wireframes_gpu(app)

    case sdl.K_F:
        ftree.feature_tree_print(&app.feature_tree)
    }
}

// Handle key up events
handle_key_up_gpu :: proc(app: ^AppStateGPU, key: sdl.Keycode, mods: sdl.Keymod) {
    if key == sdl.K_LCTRL || key == sdl.K_RCTRL {
        app.ctrl_held = false
    }
}

// Handle mouse button events
handle_mouse_button_gpu :: proc(app: ^AppStateGPU, button: ^sdl.MouseButtonEvent) {
    if button.button == u8(sdl.BUTTON_LEFT) && button.down {
        // Check if mouse is over UI - if so, don't process sketch tools
        if app.ui_context.mouse_over_ui {
            return
        }

        // Left click - sketch tools
        sketch_pos, ok := screen_to_sketch_gpu(app, app.mouse_x, app.mouse_y)
        if !ok {
            fmt.println("Failed to raycast to sketch plane")
            return
        }

        sketch.sketch_handle_click(app.sketch, sketch_pos)
        app.needs_wireframe_update = true
        app.needs_selection_update = true
    }
}

// Raycast from screen coordinates to sketch plane
screen_to_sketch_gpu :: proc(app: ^AppStateGPU, screen_x, screen_y: f64) -> (m.Vec2, bool) {
    width := f64(app.viewer.window_width)
    height := f64(app.viewer.window_height)

    // Convert screen coordinates to NDC [-1, 1]
    ndc_x := (2.0 * screen_x) / width - 1.0
    ndc_y := 1.0 - (2.0 * screen_y) / height

    // Get view and projection matrices
    view := v.camera_get_view_matrix(&app.viewer.camera)
    projection := v.camera_get_projection_matrix(&app.viewer.camera)

    // Inverse matrices
    inv_proj := glsl.inverse(projection)
    inv_view := glsl.inverse(view)

    // Ray in view space
    ray_clip := glsl.vec4{f32(ndc_x), f32(ndc_y), -1.0, 1.0}
    ray_eye := inv_proj * ray_clip
    ray_eye = glsl.vec4{ray_eye.x, ray_eye.y, -1.0, 0.0}

    // Ray in world space
    ray_world_4 := inv_view * ray_eye
    ray_world := glsl.vec3{ray_world_4.x, ray_world_4.y, ray_world_4.z}
    ray_dir := glsl.normalize(ray_world)

    // Convert to double precision
    ray_origin := m.Vec3{
        f64(app.viewer.camera.position.x),
        f64(app.viewer.camera.position.y),
        f64(app.viewer.camera.position.z),
    }
    ray_direction := m.Vec3{f64(ray_dir.x), f64(ray_dir.y), f64(ray_dir.z)}

    // Intersect ray with sketch plane
    plane_normal := app.sketch.plane.normal
    plane_origin := app.sketch.plane.origin

    denom := glsl.dot(ray_direction, plane_normal)
    if glsl.abs(denom) < 1e-6 {
        return m.Vec2{}, false
    }

    diff := plane_origin - ray_origin
    t := glsl.dot(diff, plane_normal) / denom

    if t < 0 {
        return m.Vec2{}, false
    }

    intersection_world := ray_origin + ray_direction * t
    sketch_pos := sketch.world_to_sketch(&app.sketch.plane, intersection_world)

    return sketch_pos, true
}

// Render frame with SDL3 GPU
render_frame_gpu :: proc(app: ^AppStateGPU) {
    // Acquire command buffer
    cmd := sdl.AcquireGPUCommandBuffer(app.viewer.gpu_device)
    if cmd == nil do return

    // Acquire swapchain texture
    swapchain: ^sdl.GPUTexture
    w, h: u32
    if !sdl.AcquireGPUSwapchainTexture(cmd, app.viewer.window, &swapchain, &w, &h) {
        return
    }

    // Update window size if changed
    if w != app.viewer.window_width || h != app.viewer.window_height {
        app.viewer.window_width = w
        app.viewer.window_height = h
        app.viewer.camera.aspect_ratio = f32(w) / f32(h)
    }

    if swapchain != nil {
        // Begin render pass
        color_target := sdl.GPUColorTargetInfo{
            texture = swapchain,
            load_op = .CLEAR,
            store_op = .STORE,
            clear_color = {0.08, 0.08, 0.08, 1.0},
        }

        pass := sdl.BeginGPURenderPass(cmd, &color_target, 1, nil)

        // Bind pipeline
        sdl.BindGPUGraphicsPipeline(pass, app.viewer.pipeline)

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
        view := v.camera_get_view_matrix(&app.viewer.camera)
        proj := v.camera_get_projection_matrix(&app.viewer.camera)
        mvp := proj * view

        // Render grid (behind everything)
        v.viewer_gpu_render_grid(app.viewer, cmd, pass, mvp)

        // Render coordinate axes
        v.viewer_gpu_render_axes(app.viewer, cmd, pass, mvp)

        // Render sketch wireframe (non-selected) in darker cyan
        v.viewer_gpu_render_wireframe(app.viewer, cmd, pass, &app.wireframe, {0.0, 0.4, 0.5, 1}, mvp, 3.0)

        // Render selected entity in bright cyan
        if app.sketch.selected_entity >= 0 {
            v.viewer_gpu_render_wireframe(app.viewer, cmd, pass, &app.wireframe_selected, {0.0, 1.0, 1.0, 1}, mvp, 3.0)
        }

        // Render sketch points as filled dots (4 pixels diameter)
        v.viewer_gpu_render_sketch_points(app.viewer, cmd, pass, app.sketch, mvp, {0.0, 0.4, 0.5, 1}, 4.0)

        // Render preview geometry (cursor + temp line/circle)
        v.viewer_gpu_render_sketch_preview(app.viewer, cmd, pass, app.sketch, mvp)

        // Render constraints (dimensions, icons)
        v.viewer_gpu_render_sketch_constraints(app.viewer, cmd, pass, &app.text_renderer, app.sketch, mvp, view, proj)

        // Render 3D solids in white
        for &solid_mesh in app.solid_wireframes {
            v.viewer_gpu_render_wireframe(app.viewer, cmd, pass, &solid_mesh, {1.0, 1.0, 1.0, 1}, mvp, 2.0)
        }

        // Render text overlay
        v.text_render_2d_gpu(&app.text_renderer, cmd, pass, "OhCAD v0.1 - SDL3 GPU", 20, 20, 44, {0, 255, 255, 255}, w, h)

        // ========== Real CAD UI ==========
        // Begin UI frame
        ui.ui_begin_frame(
            &app.ui_context,
            cmd,
            pass,
            w, h,
            f32(app.mouse_x),
            f32(app.mouse_y),
            app.mouse_down_left,
        )

        // Render CAD UI layout (toolbar, properties, feature tree, status bar)
        needs_update := ui.ui_cad_layout(
            &app.ui_context,
            &app.cad_ui_state,
            app.sketch,
            &app.feature_tree,
            app.extrude_feature_id,
            w, h,
        )

        // If properties changed (e.g., extrude depth), update solids
        if needs_update {
            update_solid_wireframes_gpu(app)
        }

        // End UI frame
        ui.ui_end_frame(&app.ui_context)

        sdl.EndGPURenderPass(pass)
    }

    // Submit command buffer
    _ = sdl.SubmitGPUCommandBuffer(cmd)
}

// Test extrude feature
test_extrude_gpu :: proc(app: ^AppStateGPU) {
    fmt.println("\n=== Testing Extrude Feature ===")

    if app.extrude_feature_id >= 0 {
        fmt.println("⚠️  Sketch already extruded!")
        return
    }

    if !sketch.sketch_has_closed_profile(app.sketch) {
        fmt.println("❌ Cannot extrude - sketch does not contain a closed profile")
        return
    }

    fmt.println("✅ Closed profile detected!")

    extrude_id := ftree.feature_tree_add_extrude(
        &app.feature_tree,
        app.sketch_feature_id,
        1.0,
        .Forward,
        "Extrude001",
    )

    if extrude_id < 0 {
        fmt.println("❌ Failed to add extrude feature")
        return
    }

    app.extrude_feature_id = extrude_id
    app.cad_ui_state.temp_extrude_depth = 1.0  // Initialize UI state

    if !ftree.feature_regenerate(&app.feature_tree, extrude_id) {
        fmt.println("❌ Failed to regenerate extrude")
        return
    }

    update_solid_wireframes_gpu(app)
    ftree.feature_tree_print(&app.feature_tree)

    fmt.println("\n✅ Extrude added!")
}

// Update solid wireframes from feature tree
update_solid_wireframes_gpu :: proc(app: ^AppStateGPU) {
    for &mesh in app.solid_wireframes {
        v.wireframe_mesh_gpu_destroy(&mesh)
    }
    clear(&app.solid_wireframes)

    for feature in app.feature_tree.features {
        if !feature.visible || !feature.enabled {
            continue
        }

        if feature.result_solid != nil {
            mesh := v.solid_to_wireframe_gpu(feature.result_solid)
            append(&app.solid_wireframes, mesh)
        }
    }

    fmt.printf("Updated %d solid wireframes\n", len(app.solid_wireframes))
}

// Change extrude depth
change_extrude_depth_gpu :: proc(app: ^AppStateGPU, delta: f64) {
    if app.extrude_feature_id < 0 {
        fmt.println("❌ No extrude feature")
        return
    }

    feature := ftree.feature_tree_get_feature(&app.feature_tree, app.extrude_feature_id)
    if feature == nil do return

    params, ok := feature.params.(ftree.ExtrudeParams)
    if !ok do return

    new_depth := params.depth + delta
    if new_depth < 0.1 {
        new_depth = 0.1
    }

    params.depth = new_depth
    feature.params = params

    fmt.printf("🔄 Extrude depth: %.2f\n", new_depth)

    ftree.feature_tree_mark_dirty(&app.feature_tree, app.extrude_feature_id)

    if ftree.feature_regenerate(&app.feature_tree, app.extrude_feature_id) {
        update_solid_wireframes_gpu(app)
        fmt.printf("✅ Depth updated: %.2f\n", new_depth)
    }
}

// Helper to read file or exit
read_entire_file_or_exit :: proc(path: string) -> ([]byte, bool) {
    data, ok := os.read_entire_file(path)
    if !ok {
        fmt.eprintln("ERROR: Failed to read file:", path)
        return nil, false
    }
    return data, true
}
