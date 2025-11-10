// OhCAD Interactive Sketcher Application
package main

import "core:fmt"
import "base:runtime"
import v "ui/viewer"
import sketch "features/sketch"
import extrude "features/extrude"
import ftree "features/feature_tree"
import m "core/math"
import glsl "core:math/linalg/glsl"
import glfw "vendor:glfw"
import gl "vendor:OpenGL"

// Application state
AppState :: struct {
    viewer: ^v.Viewer,
    shader: ^v.LineShader,
    text_renderer: v.TextRenderer,  // Text rendering for dimensions
    sketch: ^sketch.Sketch2D,
    wireframe: v.WireframeMesh,
    wireframe_selected: v.WireframeMesh,  // Separate mesh for selected entity

    // Feature tree (parametric system)
    feature_tree: ftree.FeatureTree,
    sketch_feature_id: int,     // ID of base sketch feature
    extrude_feature_id: int,    // ID of extrude feature (-1 if not extruded)

    // Wireframe cache for all solids
    solid_wireframes: [dynamic]v.WireframeMesh,  // One per feature

    // Update flags
    needs_wireframe_update: bool,   // Flag to rebuild wireframe on next frame
    needs_selection_update: bool,   // Flag to rebuild selection wireframe on next frame
    needs_solid_update: bool,       // Flag to rebuild solid wireframe on next frame
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

    // Initialize text renderer for dimensions
    text_renderer, text_ok := v.text_renderer_init()
    if !text_ok {
        fmt.eprintln("Failed to initialize text renderer")
        return
    }
    defer v.text_renderer_destroy(&text_renderer)

    // Create a sketch on XY plane
    fmt.println("\nCreating sketch...")
    sk := new(sketch.Sketch2D)
    sk^ = sketch.sketch_init("InteractiveSketch", sketch.sketch_plane_xy())
    // NOTE: Sketch will be owned and destroyed by feature tree!
    // Do NOT defer sketch.sketch_destroy(sk) or free(sk) here

    // Set Select tool by default (not Line)
    sketch.sketch_set_tool(sk, .Select)

    // Initial wireframe (empty)
    wireframe := v.sketch_to_wireframe(sk)
    defer v.wireframe_mesh_destroy(&wireframe)

    // Initial selection wireframe (empty)
    wireframe_selected := v.sketch_to_wireframe_selected(sk)
    defer v.wireframe_mesh_destroy(&wireframe_selected)

    // Initialize feature tree
    feature_tree := ftree.feature_tree_init()
    defer ftree.feature_tree_destroy(&feature_tree)

    // Add sketch as first feature (Feature 0)
    // The feature tree now OWNS this sketch and will destroy it
    sketch_feature_id := ftree.feature_tree_add_sketch(&feature_tree, sk, "Sketch001")

    // Create app state with pointers
    app := new(AppState)
    app.viewer = viewer_inst
    app.shader = &shader
    app.text_renderer = text_renderer  // Initialize text renderer
    app.sketch = sk
    app.wireframe = wireframe
    app.wireframe_selected = wireframe_selected
    app.feature_tree = feature_tree
    app.sketch_feature_id = sketch_feature_id
    app.extrude_feature_id = -1  // No extrude yet
    app.solid_wireframes = make([dynamic]v.WireframeMesh)
    app.needs_wireframe_update = false
    app.needs_selection_update = false
    defer {
        // Clean up solid wireframes
        for &mesh in app.solid_wireframes {
            v.wireframe_mesh_destroy(&mesh)
        }
        delete(app.solid_wireframes)
        free(app)
    }

    // Set user pointer for callbacks
    glfw.SetWindowUserPointer(viewer_inst.window, app)

    // Set our custom callbacks (will forward to viewer's camera handlers when in camera mode)
    glfw.SetMouseButtonCallback(viewer_inst.window, mouse_button_callback)
    glfw.SetCursorPosCallback(viewer_inst.window, mouse_move_callback)
    glfw.SetScrollCallback(viewer_inst.window, scroll_callback)
    glfw.SetKeyCallback(viewer_inst.window, key_callback)

    sketch.sketch_print_info(sk)

    fmt.println("\nControls:")
    fmt.println("  [S] Select tool (default)")
    fmt.println("  [L] Line tool (chains from previous point, ESC to finish)")
    fmt.println("  [C] Circle tool")
    fmt.println("  [D] Dimension tool (click two points to add distance constraint)")
    fmt.println("  [ESC] Cancel tool and return to Select mode")
    fmt.println("")
    fmt.println("  [H] Apply horizontal constraint (to selected line)")
    fmt.println("  [V] Apply vertical constraint (to selected line)")
    fmt.println("  [X] Solve constraints")
    fmt.println("  [P] Print profile detection (closed vs open)")
    fmt.println("  [E] Extrude sketch (creates 3D solid from closed profile)")
    fmt.println("  [+] or [=] Increase extrude depth")
    fmt.println("  [-] Decrease extrude depth")
    fmt.println("  [R] Regenerate all features")
    fmt.println("  [F] Print feature tree")
    fmt.println("")
    fmt.println("  [DELETE] Delete selected entity")
    fmt.println("  [Ctrl+S] Save sketch to file")
    fmt.println("  [Ctrl+O] Load sketch from file")
    fmt.println("  [Q] Quit")
    fmt.println("")
    fmt.println("Mouse Controls:")
    fmt.println("  Left Click: Use current tool / Select entities")
    fmt.println("  Middle Click + Drag: Orbit camera")
    fmt.println("  Right Click + Drag: Pan camera")
    fmt.println("  Scroll Wheel: Zoom\n")

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

        // Get viewport dimensions for text rendering in constraints
        width, height := glfw.GetFramebufferSize(viewer_inst.window)

        // Render constraint icons/indicators (with dimension text)
        v.render_sketch_constraints(&shader, app.sketch, mvp, &app.text_renderer, view, projection, width, height)

        // Render all 3D solids from feature tree in WHITE
        for &solid_mesh in app.solid_wireframes {
            v.render_wireframe_thick(&shader, &solid_mesh, mvp, viewer_inst.camera.position, {1.0, 1.0, 1.0, 1}, 2.0, f32(viewport_height), fov_radians, camera_distance)
        }

        // === TEXT RENDERING TEST ===
        // Update screen size for text shader
        v.text_renderer_set_screen_size(&app.text_renderer, f32(width), f32(height))

        // Render test text in top-left corner (bright cyan to match theme)
        v.text_render_2d(&app.text_renderer, "OhCAD v0.1 - Parametric CAD", 20, 20, 44, {0, 255, 255, 255})

        // Render current tool info
        tool_name := "Unknown"
        switch app.sketch.current_tool {
        case .Select: tool_name = "Select"
        case .Line: tool_name = "Line"
        case .Circle: tool_name = "Circle"
        case .Arc: tool_name = "Arc"
        case .Dimension: tool_name = "Dimension"
        }
        tool_text := fmt.tprintf("Tool: %s", tool_name)
        v.text_render_2d(&app.text_renderer, tool_text, 20, 64, 36, {200, 200, 200, 255})

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

    // LEFT CLICK - Sketch tools (drawing, selection)
    if button == glfw.MOUSE_BUTTON_LEFT && action == glfw.PRESS {
        // Get mouse position
        xpos, ypos := glfw.GetCursorPos(window)

        // Convert to sketch coordinates
        sketch_pos, ok := screen_to_sketch(app, xpos, ypos)
        if !ok {
            fmt.println("Failed to raycast to sketch plane")
            return
        }

        // NO GRID SNAPPING - use exact cursor position
        // Point snapping is handled by individual tools

        // Handle click with current tool
        sketch.sketch_handle_click(app.sketch, sketch_pos)

        // Mark wireframe and selection for update
        app.needs_wireframe_update = true
        app.needs_selection_update = true
    }

    // MIDDLE CLICK - Camera orbit
    if button == glfw.MOUSE_BUTTON_MIDDLE {
        app.viewer.mouse_middle_down = (action == glfw.PRESS)
    }

    // RIGHT CLICK - Camera pan
    if button == glfw.MOUSE_BUTTON_RIGHT {
        app.viewer.mouse_right_down = (action == glfw.PRESS)
    }
}

mouse_move_callback :: proc "c" (window: glfw.WindowHandle, xpos, ypos: f64) {
    context = runtime.default_context()

    app := cast(^AppState)glfw.GetWindowUserPointer(window)
    if app == nil do return

    // Always update cursor preview for sketch tools
    sketch_pos, ok := screen_to_sketch(app, xpos, ypos)
    if ok {
        // NO GRID SNAPPING - use exact cursor position
        // This allows selecting points after solving constraints

        // Convert back to 3D for preview
        world_pos := sketch.sketch_to_world(&app.sketch.plane, sketch_pos)
        sketch.sketch_update_cursor(app.sketch, world_pos)
    }

    // Handle camera movement
    dx := f32(xpos - app.viewer.mouse_x)
    dy := f32(ypos - app.viewer.mouse_y)

    app.viewer.mouse_x = xpos
    app.viewer.mouse_y = ypos

    // Middle mouse button - orbit
    if app.viewer.mouse_middle_down {
        sensitivity := f32(0.005)
        app.viewer.camera.azimuth += dx * sensitivity
        app.viewer.camera.elevation += dy * sensitivity

        // Clamp elevation
        app.viewer.camera.elevation = glsl.clamp(app.viewer.camera.elevation, -3.14159 * 0.49, 3.14159 * 0.49)

        v.camera_update_position(&app.viewer.camera)
    }

    // Right mouse button - pan
    if app.viewer.mouse_right_down {
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

        case glfw.KEY_D:
            sketch.sketch_set_tool(app.sketch, .Dimension)
            fmt.println("Tool: Dimension (click two points to add distance constraint)")

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

        case glfw.KEY_ESCAPE:
            // ESC - Cancel tool operation and switch to Select mode
            sketch.sketch_cancel_tool(app.sketch)
            sketch.sketch_set_tool(app.sketch, .Select)
            fmt.println("Tool cancelled - switched to Select mode")

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

        case glfw.KEY_P:
            // P - Print profile information
            sketch.sketch_print_profiles(app.sketch)

        case glfw.KEY_E:
            // E - Extrude sketch (test extrude feature)
            test_extrude(app)

        case glfw.KEY_EQUAL, glfw.KEY_KP_ADD:
            // [+] or [=] - Increase extrude depth
            change_extrude_depth(app, 0.1)

        case glfw.KEY_MINUS, glfw.KEY_KP_SUBTRACT:
            // [-] - Decrease extrude depth
            change_extrude_depth(app, -0.1)

        case glfw.KEY_R:
            // R - Regenerate all features
            ftree.feature_tree_regenerate_all(&app.feature_tree)
            update_solid_wireframes(app)

        case glfw.KEY_F:
            // F - Print feature tree
            ftree.feature_tree_print(&app.feature_tree)
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

// Test extrude feature
test_extrude :: proc(app: ^AppState) {
    fmt.println("\n=== Testing Extrude Feature ===")

    // Check if already extruded
    if app.extrude_feature_id >= 0 {
        fmt.println("⚠️  Sketch already extruded! Use [+]/[-] to change depth, [R] to regenerate")
        ftree.feature_tree_print(&app.feature_tree)
        return
    }

    // Check if sketch has closed profile
    if !sketch.sketch_has_closed_profile(app.sketch) {
        fmt.println("❌ Cannot extrude - sketch does not contain a closed profile")
        fmt.println("   Draw a closed shape (e.g., rectangle) first")
        sketch.sketch_print_profiles(app.sketch)
        return
    }

    fmt.println("✅ Closed profile detected!")

    // Add extrude feature to tree
    extrude_id := ftree.feature_tree_add_extrude(
        &app.feature_tree,
        app.sketch_feature_id,  // Parent sketch
        1.0,                     // Initial depth
        .Forward,                // Direction
        "Extrude001",
    )

    if extrude_id < 0 {
        fmt.println("❌ Failed to add extrude feature")
        return
    }

    app.extrude_feature_id = extrude_id

    // Regenerate the extrude feature
    if !ftree.feature_regenerate(&app.feature_tree, extrude_id) {
        fmt.println("❌ Failed to regenerate extrude")
        return
    }

    // Update solid wireframes
    update_solid_wireframes(app)

    // Print feature tree
    ftree.feature_tree_print(&app.feature_tree)

    fmt.println("\n✅ Extrude added to feature tree!")
    fmt.println("Controls:")
    fmt.println("  [+] or [=] Increase extrude depth")
    fmt.println("  [-] Decrease extrude depth")
    fmt.println("  [R] Regenerate all features")
    fmt.println("  [F] Print feature tree")
}

// Update solid wireframes from feature tree
update_solid_wireframes :: proc(app: ^AppState) {
    // Clean up old wireframes
    for &mesh in app.solid_wireframes {
        v.wireframe_mesh_destroy(&mesh)
    }
    clear(&app.solid_wireframes)

    // Create wireframes for all visible features with solids
    for feature in app.feature_tree.features {
        if !feature.visible || !feature.enabled {
            continue
        }

        if feature.result_solid != nil {
            mesh := v.solid_to_wireframe(feature.result_solid)
            append(&app.solid_wireframes, mesh)
        }
    }

    fmt.printf("Updated %d solid wireframes\n", len(app.solid_wireframes))
}

// Change extrude depth
change_extrude_depth :: proc(app: ^AppState, delta: f64) {
    if app.extrude_feature_id < 0 {
        fmt.println("❌ No extrude feature to modify - press [E] to extrude first")
        return
    }

    // Get extrude feature
    feature := ftree.feature_tree_get_feature(&app.feature_tree, app.extrude_feature_id)
    if feature == nil {
        fmt.println("❌ Extrude feature not found")
        return
    }

    // Get current parameters
    params, ok := feature.params.(ftree.ExtrudeParams)
    if !ok {
        fmt.println("❌ Invalid extrude parameters")
        return
    }

    // Update depth
    new_depth := params.depth + delta
    if new_depth < 0.1 {
        new_depth = 0.1  // Minimum depth
    }

    params.depth = new_depth
    feature.params = params

    fmt.printf("🔄 Extrude depth changed: %.2f → %.2f\n", params.depth - delta, new_depth)

    // Mark feature as needing update
    ftree.feature_tree_mark_dirty(&app.feature_tree, app.extrude_feature_id)

    // Regenerate
    if !ftree.feature_regenerate(&app.feature_tree, app.extrude_feature_id) {
        fmt.println("❌ Failed to regenerate extrude")
        return
    }

    // Update wireframes
    update_solid_wireframes(app)

    fmt.printf("✅ Parametric update complete! New depth: %.2f\n", new_depth)
}
