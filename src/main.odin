// OhCAD Interactive Sketcher Application
package main

import "core:fmt"
import "base:runtime"
import v "ui/viewer"
import sketch "features/sketch"
import m "core/math"
import glsl "core:math/linalg/glsl"
import glfw "vendor:glfw"
import gl "vendor:OpenGL"

// Application state
AppState :: struct {
    viewer: ^v.Viewer,
    shader: ^v.LineShader,
    sketch: ^sketch.Sketch2D,
    wireframe: v.WireframeMesh,
    wireframe_selected: v.WireframeMesh,  // Separate mesh for selected entity

    // Mode flags
    sketch_mode: bool,              // true = sketch mode, false = camera mode
    needs_wireframe_update: bool,   // Flag to rebuild wireframe on next frame
    needs_selection_update: bool,   // Flag to rebuild selection wireframe on next frame
}

// Apply horizontal constraint to selected line
apply_horizontal_constraint :: proc(app: ^AppState) {
    if app.sketch.selected_entity < 0 {
        fmt.println("❌ No entity selected - select a line first")
        return
    }

    entity := app.sketch.entities[app.sketch.selected_entity]

    // Check if selected entity is a line
    _, is_line := entity.(sketch.SketchLine)
    if !is_line {
        fmt.println("❌ Selected entity is not a line - horizontal constraint requires a line")
        return
    }

    // Add horizontal constraint
    sketch.sketch_add_constraint(app.sketch, .Horizontal, sketch.HorizontalData{
        line_id = app.sketch.selected_entity,
    })

    fmt.printf("✅ Horizontal constraint added to line %d\n", app.sketch.selected_entity)
}

// Apply vertical constraint to selected line
apply_vertical_constraint :: proc(app: ^AppState) {
    if app.sketch.selected_entity < 0 {
        fmt.println("❌ No entity selected - select a line first")
        return
    }

    entity := app.sketch.entities[app.sketch.selected_entity]

    // Check if selected entity is a line
    _, is_line := entity.(sketch.SketchLine)
    if !is_line {
        fmt.println("❌ Selected entity is not a line - vertical constraint requires a line")
        return
    }

    // Add vertical constraint
    sketch.sketch_add_constraint(app.sketch, .Vertical, sketch.VerticalData{
        line_id = app.sketch.selected_entity,
    })

    fmt.printf("✅ Vertical constraint added to line %d\n", app.sketch.selected_entity)
}

// Solve all constraints using Levenberg-Marquardt solver
solve_constraints :: proc(app: ^AppState) {
    fmt.println("\n=== Running Constraint Solver ===")

    // Run solver
    result := sketch.sketch_solve_constraints(app.sketch)

    // Print result
    sketch.solver_result_print(result)

    // Update wireframe if successful
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
    fmt.println("=== OhCAD Interactive Sketcher ===")

    // Initialize viewer
    viewer_inst, ok := v.viewer_init()
    if !ok {
        fmt.eprintln("Failed to initialize viewer")
        return
    }
    defer v.viewer_destroy(viewer_inst)

    // Initialize line shader for rendering
    shader, shader_ok := v.line_shader_init()
    if !shader_ok {
        fmt.eprintln("Failed to initialize shader")
        return
    }
    defer v.line_shader_destroy(&shader)

    // Create a sketch on XY plane
    fmt.println("\nCreating sketch...")
    sk := new(sketch.Sketch2D)
    sk^ = sketch.sketch_init("InteractiveSketch", sketch.sketch_plane_xy())
    defer sketch.sketch_destroy(sk)
    defer free(sk)

    // Set line tool by default
    sketch.sketch_set_tool(sk, .Line)

    // Initial wireframe (empty)
    wireframe := v.sketch_to_wireframe(sk)
    defer v.wireframe_mesh_destroy(&wireframe)

    // Initial selection wireframe (empty)
    wireframe_selected := v.sketch_to_wireframe_selected(sk)
    defer v.wireframe_mesh_destroy(&wireframe_selected)

    // Create app state with pointers
    app := new(AppState)
    app.viewer = viewer_inst
    app.shader = &shader
    app.sketch = sk
    app.wireframe = wireframe
    app.wireframe_selected = wireframe_selected
    app.sketch_mode = true
    app.needs_wireframe_update = false
    app.needs_selection_update = false
    defer free(app)

    // Set user pointer for callbacks
    glfw.SetWindowUserPointer(viewer_inst.window, app)

    // Set our custom callbacks (will forward to viewer's camera handlers when in camera mode)
    glfw.SetMouseButtonCallback(viewer_inst.window, mouse_button_callback)
    glfw.SetCursorPosCallback(viewer_inst.window, mouse_move_callback)
    glfw.SetScrollCallback(viewer_inst.window, scroll_callback)
    glfw.SetKeyCallback(viewer_inst.window, key_callback)

    sketch.sketch_print_info(sk)

    fmt.println("\nControls:")
    fmt.println("  [S] Select tool")
    fmt.println("  [L] Line tool")
    fmt.println("  [C] Circle tool")
    fmt.println("  [H] Apply horizontal constraint (to selected line)")
    fmt.println("  [V] Apply vertical constraint (to selected line)")
    fmt.println("  [X] Solve constraints")
    fmt.println("  [DELETE] Delete selected entity")
    fmt.println("  [TAB] Toggle sketch mode / camera mode")
    fmt.println("  [ESC] Cancel current operation")
    fmt.println("  [Ctrl+S] Save sketch to file")
    fmt.println("  [Ctrl+O] Load sketch from file")
    fmt.println("  [Q] Quit")
    fmt.println("\nSketch Mode (active by default):")
    fmt.println("  Click: Place points / create lines")
    fmt.println("  Move mouse: See orange cursor on sketch plane")
    fmt.println("\nCamera Mode:")
    fmt.println("  Left Mouse: Orbit")
    fmt.println("  Middle Mouse: Pan")
    fmt.println("  Scroll: Zoom\n")

    // Main render loop
    for v.viewer_should_continue(viewer_inst) {
        v.viewer_process_input(viewer_inst)
        v.viewer_begin_frame(viewer_inst)

        // Update wireframe if needed
        if app.needs_wireframe_update {
            v.wireframe_mesh_destroy(&app.wireframe)
            app.wireframe = v.sketch_to_wireframe(app.sketch)
            app.needs_wireframe_update = false
        }

        // Update selection wireframe if needed
        if app.needs_selection_update {
            v.wireframe_mesh_destroy(&app.wireframe_selected)
            app.wireframe_selected = v.sketch_to_wireframe_selected(app.sketch)
            app.needs_selection_update = false
        }

        // Calculate MVP matrix
        view := v.camera_get_view_matrix(&viewer_inst.camera)
        projection := v.camera_get_projection_matrix(&viewer_inst.camera)
        mvp := projection * view

        // Get viewport height for screen-space line thickness
        _, viewport_height := glfw.GetFramebufferSize(viewer_inst.window)
        fov_radians := glsl.radians(viewer_inst.camera.fov)
        camera_distance := viewer_inst.camera.distance

        // Render grid and axes
        v.render_grid(&shader, mvp, 10.0, 20)
        v.render_axes(&shader, mvp, 2.0)

        // Render sketch plane indicator
        v.render_sketch_plane(&shader, app.sketch, mvp, 4.0)

        // Render NON-SELECTED entities in darker cyan (3 pixels wide, screen-space constant)
        v.render_wireframe_thick(&shader, &app.wireframe, mvp, viewer_inst.camera.position, {0.0, 0.4, 0.5, 1}, 3.0, f32(viewport_height), fov_radians, camera_distance)

        // Render SELECTED entity in bright cyan (3 pixels wide, screen-space constant)
        if app.sketch.selected_entity >= 0 {
            v.render_wireframe_thick(&shader, &app.wireframe_selected, mvp, viewer_inst.camera.position, {0.0, 1.0, 1.0, 1}, 3.0, f32(viewport_height), fov_radians, camera_distance)
        }

        // Render sketch points as filled dots ON TOP of lines (4 pixels diameter, screen-space constant)
        // Unselected points in darker cyan, selected points in bright cyan
        // Disable depth test so dots always appear on top
        gl.Disable(gl.DEPTH_TEST)

        // Render all dots in darker cyan first
        v.render_sketch_points(&shader, app.sketch, mvp, {0.0, 0.4, 0.5, 1}, 4.0, f32(viewport_height), fov_radians, camera_distance)

        // TODO: Render selected entity's points in bright cyan on top

        gl.Enable(gl.DEPTH_TEST)

        // Render preview (cursor, preview line, etc.)
        v.render_sketch_preview(&shader, app.sketch, mvp, viewer_inst.camera.position)

        // Render constraint icons/indicators
        v.render_sketch_constraints(&shader, app.sketch, mvp)

        v.viewer_end_frame(viewer_inst)
    }

    fmt.println("\nFinal sketch:")
    sketch.sketch_print_info(sk)
    fmt.println("Viewer closed successfully")
}

// Raycast from screen coordinates to sketch plane
screen_to_sketch :: proc(app: ^AppState, screen_x, screen_y: f64) -> (m.Vec2, bool) {
    // Get WINDOW dimensions (not framebuffer) for correct cursor mapping on Retina displays
    width, height := glfw.GetWindowSize(app.viewer.window)

    // Convert screen coordinates to NDC [-1, 1]
    ndc_x := (2.0 * screen_x) / f64(width) - 1.0
    ndc_y := 1.0 - (2.0 * screen_y) / f64(height)

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

    // Convert to double precision for math operations
    ray_origin := m.Vec3{
        f64(app.viewer.camera.position.x),
        f64(app.viewer.camera.position.y),
        f64(app.viewer.camera.position.z),
    }
    ray_direction := m.Vec3{f64(ray_dir.x), f64(ray_dir.y), f64(ray_dir.z)}

    // Intersect ray with sketch plane
    plane_normal := app.sketch.plane.normal
    plane_origin := app.sketch.plane.origin

    // Ray-plane intersection
    denom := glsl.dot(ray_direction, plane_normal)
    if glsl.abs(denom) < 1e-6 {
        return m.Vec2{}, false // Ray parallel to plane
    }

    diff := plane_origin - ray_origin
    t := glsl.dot(diff, plane_normal) / denom

    if t < 0 {
        return m.Vec2{}, false // Intersection behind camera
    }

    // Calculate intersection point in world space
    intersection_world := ray_origin + ray_direction * t

    // Convert to sketch 2D coordinates
    sketch_pos := sketch.world_to_sketch(&app.sketch.plane, intersection_world)

    return sketch_pos, true
}

// =============================================================================
// GLFW Callbacks
// =============================================================================

mouse_button_callback :: proc "c" (window: glfw.WindowHandle, button, action, mods: i32) {
    context = runtime.default_context()

    app := cast(^AppState)glfw.GetWindowUserPointer(window)
    if app == nil do return

    // In sketch mode - handle sketch tool clicks
    if app.sketch_mode {
        if button == glfw.MOUSE_BUTTON_LEFT && action == glfw.PRESS {
            // Get mouse position
            xpos, ypos := glfw.GetCursorPos(window)

            // Convert to sketch coordinates
            sketch_pos, ok := screen_to_sketch(app, xpos, ypos)
            if !ok {
                fmt.println("Failed to raycast to sketch plane")
                return
            }

            // Snap to grid
            sketch_pos = sketch.sketch_snap_to_grid(sketch_pos, 0.1)

            // Handle click with current tool
            sketch.sketch_handle_click(app.sketch, sketch_pos)

            // Mark wireframe and selection for update
            app.needs_wireframe_update = true
            app.needs_selection_update = true
        }
    } else {
        // In camera mode - update viewer's mouse button state directly
        if button == glfw.MOUSE_BUTTON_LEFT {
            app.viewer.mouse_left_down = (action == glfw.PRESS)
        }
        if button == glfw.MOUSE_BUTTON_MIDDLE {
            app.viewer.mouse_middle_down = (action == glfw.PRESS)
        }
        if button == glfw.MOUSE_BUTTON_RIGHT {
            app.viewer.mouse_right_down = (action == glfw.PRESS)
        }
    }
}

mouse_move_callback :: proc "c" (window: glfw.WindowHandle, xpos, ypos: f64) {
    context = runtime.default_context()

    app := cast(^AppState)glfw.GetWindowUserPointer(window)
    if app == nil do return

    // In sketch mode - update cursor preview
    if app.sketch_mode {
        sketch_pos, ok := screen_to_sketch(app, xpos, ypos)
        if ok {
            // Snap to grid
            sketch_pos = sketch.sketch_snap_to_grid(sketch_pos, 0.1)

            // Convert back to 3D for preview
            world_pos := sketch.sketch_to_world(&app.sketch.plane, sketch_pos)
            sketch.sketch_update_cursor(app.sketch, world_pos)
        }
    } else {
        // In camera mode - handle camera movement directly
        dx := f32(xpos - app.viewer.mouse_x)
        dy := f32(ypos - app.viewer.mouse_y)

        app.viewer.mouse_x = xpos
        app.viewer.mouse_y = ypos

        // Left mouse button - orbit
        if app.viewer.mouse_left_down {
            sensitivity := f32(0.005)
            app.viewer.camera.azimuth += dx * sensitivity
            app.viewer.camera.elevation += dy * sensitivity

            // Clamp elevation
            app.viewer.camera.elevation = glsl.clamp(app.viewer.camera.elevation, -3.14159 * 0.49, 3.14159 * 0.49)

            v.camera_update_position(&app.viewer.camera)
        }

        // Middle mouse button - pan
        if app.viewer.mouse_middle_down {
            sensitivity := f32(0.01)

            pos_f32 := glsl.vec3{f32(app.viewer.camera.position.x), f32(app.viewer.camera.position.y), f32(app.viewer.camera.position.z)}
            target_f32 := glsl.vec3{f32(app.viewer.camera.target.x), f32(app.viewer.camera.target.y), f32(app.viewer.camera.target.z)}
            up_f32 := glsl.vec3{f32(app.viewer.camera.up.x), f32(app.viewer.camera.up.y), f32(app.viewer.camera.up.z)}

            view_dir := glsl.normalize(target_f32 - pos_f32)
            right := glsl.normalize(glsl.cross(view_dir, up_f32))
            up := glsl.cross(right, view_dir)

            pan_x := f64(right.x * (-dx * sensitivity * app.viewer.camera.distance * 0.1))
            pan_y := f64(right.y * (-dx * sensitivity * app.viewer.camera.distance * 0.1))
            pan_z := f64(right.z * (-dx * sensitivity * app.viewer.camera.distance * 0.1))
            app.viewer.camera.target.x += pan_x
            app.viewer.camera.target.y += pan_y
            app.viewer.camera.target.z += pan_z

            pan_x = f64(up.x * (dy * sensitivity * app.viewer.camera.distance * 0.1))
            pan_y = f64(up.y * (dy * sensitivity * app.viewer.camera.distance * 0.1))
            pan_z = f64(up.z * (dy * sensitivity * app.viewer.camera.distance * 0.1))
            app.viewer.camera.target.x += pan_x
            app.viewer.camera.target.y += pan_y
            app.viewer.camera.target.z += pan_z

            v.camera_update_position(&app.viewer.camera)
        }
    }
}

key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
    context = runtime.default_context()

    app := cast(^AppState)glfw.GetWindowUserPointer(window)
    if app == nil do return

    if action == glfw.PRESS {
        switch key {
        case glfw.KEY_Q:
            glfw.SetWindowShouldClose(window, true)

        case glfw.KEY_L:
            sketch.sketch_set_tool(app.sketch, .Line)
            fmt.println("Tool: Line")

        case glfw.KEY_C:
            sketch.sketch_set_tool(app.sketch, .Circle)
            fmt.println("Tool: Circle")

        case glfw.KEY_S:
            if (mods & glfw.MOD_CONTROL) != 0 {
                // Ctrl+S - Save sketch
                filename := "sketch.json"
                if sketch.sketch_save_to_file(app.sketch, filename) {
                    fmt.printf("✓ Sketch saved successfully\n")
                }
            } else {
                // Just S - Select tool
                sketch.sketch_set_tool(app.sketch, .Select)
                fmt.println("Tool: Select")
            }

        case glfw.KEY_O:
            if (mods & glfw.MOD_CONTROL) != 0 {
                // Ctrl+O - Load sketch
                filename := "sketch.json"
                loaded_sketch, ok := sketch.sketch_load_from_file(filename)
                if ok {
                    // Clean up old sketch
                    sketch.sketch_destroy(app.sketch)

                    // Replace with loaded sketch
                    app.sketch^ = loaded_sketch

                    // Update wireframes
                    app.needs_wireframe_update = true
                    app.needs_selection_update = true

                    fmt.printf("✓ Sketch loaded successfully\n")
                    sketch.sketch_print_info(app.sketch)
                }
            }

        case glfw.KEY_DELETE, glfw.KEY_BACKSPACE:
            if sketch.sketch_delete_selected(app.sketch) {
                app.needs_wireframe_update = true
                app.needs_selection_update = true
            }

        case glfw.KEY_TAB:
            app.sketch_mode = !app.sketch_mode

            // Don't change user pointer - keep it as app always
            if app.sketch_mode {
                fmt.println("Mode: SKETCH (camera disabled)")
            } else {
                fmt.println("Mode: CAMERA (sketch disabled)")
            }

        case glfw.KEY_ESCAPE:
            sketch.sketch_cancel_tool(app.sketch)
            fmt.println("Tool operation cancelled")

        case glfw.KEY_HOME:
            // Reset camera to default position
            v.camera_init(&app.viewer.camera, app.viewer.camera.aspect_ratio)

        // === CONSTRAINT SHORTCUTS ===
        case glfw.KEY_H:
            // H - Horizontal constraint (requires line selected)
            apply_horizontal_constraint(app)

        case glfw.KEY_V:
            // V - Vertical constraint (requires line selected)
            apply_vertical_constraint(app)

        case glfw.KEY_X:
            // X - Solve constraints (execute solver)
            solve_constraints(app)
        }
    }
}

scroll_callback :: proc "c" (window: glfw.WindowHandle, xoffset, yoffset: f64) {
    context = runtime.default_context()

    app := cast(^AppState)glfw.GetWindowUserPointer(window)
    if app == nil do return

    // Zoom in/out (works in both modes)
    zoom_speed := f32(0.1)
    app.viewer.camera.distance -= f32(yoffset) * zoom_speed * app.viewer.camera.distance

    // Clamp distance
    app.viewer.camera.distance = glsl.clamp(app.viewer.camera.distance, 0.5, 100.0)

    v.camera_update_position(&app.viewer.camera)
}
