// tests/constraints - Constraint Visualization Test
// Creates a sketch with various constraints and launches viewer to see visual indicators
package constraint_viz_test

import "core:fmt"
import "base:runtime"
import v "../../src/ui/viewer"
import sketch "../../src/features/sketch"
import m "../../src/core/math"
import glsl "core:math/linalg/glsl"
import glfw "vendor:glfw"
import gl "vendor:OpenGL"

// Application state
AppState :: struct {
    viewer: ^v.Viewer,
    shader: ^v.LineShader,
    sketch: ^sketch.Sketch2D,
    wireframe: v.WireframeMesh,
}

main :: proc() {
    fmt.println("=== Constraint Visualization Test ===\n")

    // Initialize viewer
    viewer_inst, ok := v.viewer_init()
    if !ok {
        fmt.eprintln("Failed to initialize viewer")
        return
    }
    defer v.viewer_destroy(viewer_inst)

    // Initialize line shader
    shader, shader_ok := v.line_shader_init()
    if !shader_ok {
        fmt.eprintln("Failed to initialize shader")
        return
    }
    defer v.line_shader_destroy(&shader)

    // Create sketch with test constraints
    fmt.println("Creating test sketch with constraints...")
    sk := create_test_sketch()
    // Note: cleanup is manual at end to avoid double-free when switching tests

    // Initial wireframe
    wireframe := v.sketch_to_wireframe(sk)
    defer v.wireframe_mesh_destroy(&wireframe)

    // Create app state
    app := new(AppState)
    app.viewer = viewer_inst
    app.shader = &shader
    app.sketch = sk
    app.wireframe = wireframe
    defer free(app)

    // Set user pointer for callbacks
    glfw.SetWindowUserPointer(viewer_inst.window, app)
    glfw.SetKeyCallback(viewer_inst.window, key_callback)
    glfw.SetMouseButtonCallback(viewer_inst.window, mouse_button_callback)
    glfw.SetCursorPosCallback(viewer_inst.window, mouse_move_callback)
    glfw.SetScrollCallback(viewer_inst.window, scroll_callback)

    fmt.println("\nConstraint Visualization Active:")
    fmt.println("  Orange/Amber icons = Constraint indicators (H, V, ⊥, ||, =)")
    fmt.println("  Yellow lines = Dimension annotations")
    fmt.println("\nControls:")
    fmt.println("  [Q] Quit")
    fmt.println("  [1] Test 1: Rectangle with dimensions")
    fmt.println("  [2] Test 2: Perpendicular lines")
    fmt.println("  [3] Test 3: Equal lengths and parallel")
    fmt.println("  [4] Test 4: Mixed constraints")
    fmt.println("  [S] Solve constraints (run solver)")
    fmt.println("  [H] Apply horizontal constraint (placeholder)")
    fmt.println("  [V] Apply vertical constraint (placeholder)")
    fmt.println("  [HOME] Reset camera")
    fmt.println("  Mouse: Orbit, Pan, Zoom\n")

    // Main render loop
    for v.viewer_should_continue(viewer_inst) {
        v.viewer_process_input(viewer_inst)
        v.viewer_begin_frame(viewer_inst)

        // Calculate MVP matrix
        view := v.camera_get_view_matrix(&viewer_inst.camera)
        projection := v.camera_get_projection_matrix(&viewer_inst.camera)
        mvp := projection * view

        // Get viewport for screen-space sizing
        _, viewport_height := glfw.GetFramebufferSize(viewer_inst.window)
        fov_radians := glsl.radians(viewer_inst.camera.fov)
        camera_distance := viewer_inst.camera.distance

        // Render scene
        v.render_grid(&shader, mvp, 10.0, 20)
        v.render_axes(&shader, mvp, 2.0)
        v.render_sketch_plane(&shader, app.sketch, mvp, 5.0)

        // Render sketch geometry (3px thick, screen-space constant)
        v.render_wireframe_thick(&shader, &app.wireframe, mvp, viewer_inst.camera.position,
            {0.0, 0.6, 0.7, 1}, 3.0, f32(viewport_height), fov_radians, camera_distance)

        // Render sketch points (4px dots)
        gl.Disable(gl.DEPTH_TEST)
        v.render_sketch_points(&shader, app.sketch, mvp, {0.0, 0.6, 0.7, 1}, 4.0,
            f32(viewport_height), fov_radians, camera_distance)
        gl.Enable(gl.DEPTH_TEST)

        // ** RENDER CONSTRAINT ICONS/INDICATORS **
        v.render_sketch_constraints(&shader, app.sketch, mvp)

        v.viewer_end_frame(viewer_inst)
    }

    fmt.println("\nViewer closed")

    // Cleanup sketch manually
    sketch.sketch_destroy(app.sketch)
    free(app.sketch)
}

// Create a test sketch with various constraints
create_test_sketch :: proc() -> ^sketch.Sketch2D {
    sk := new(sketch.Sketch2D)
    sk^ = sketch.sketch_init("ConstraintVizTest", sketch.sketch_plane_xy())

    // Create a rectangle-like shape to demonstrate constraints
    // Start with rough positions, constraints will be visualized
    p1_id := sketch.sketch_add_point(sk, 0.0, 0.0, true)   // Bottom-left (fixed)
    p2_id := sketch.sketch_add_point(sk, 3.2, 0.1, false)  // Bottom-right (rough)
    p3_id := sketch.sketch_add_point(sk, 3.1, 2.1, false)  // Top-right (rough)
    p4_id := sketch.sketch_add_point(sk, 0.1, 1.9, false)  // Top-left (rough)

    // Create lines
    line1_id := sketch.sketch_add_line(sk, p1_id, p2_id)  // Bottom
    line2_id := sketch.sketch_add_line(sk, p2_id, p3_id)  // Right
    line3_id := sketch.sketch_add_line(sk, p3_id, p4_id)  // Top
    line4_id := sketch.sketch_add_line(sk, p4_id, p1_id)  // Left

    // Add constraints (icons will be visualized!)

    // 1. Horizontal constraint - shows "H" icon
    sketch.sketch_add_constraint(sk, .Horizontal, sketch.HorizontalData{line_id = line1_id})

    // 2. Vertical constraint - shows "V" icon
    sketch.sketch_add_constraint(sk, .Vertical, sketch.VerticalData{line_id = line4_id})

    // 3. Perpendicular constraint - shows "⊥" icon
    sketch.sketch_add_constraint(sk, .Perpendicular, sketch.PerpendicularData{
        line1_id = line1_id,
        line2_id = line2_id,
    })

    // 4. Parallel constraint - shows "||" icon
    sketch.sketch_add_constraint(sk, .Parallel, sketch.ParallelData{
        line1_id = line1_id,
        line2_id = line3_id,
    })

    // 5. Distance dimensions - shows cyan dimension lines
    sketch.sketch_add_constraint(sk, .DistanceX, sketch.DistanceXData{
        point1_id = p1_id,
        point2_id = p2_id,
        distance = 3.0,
    })

    sketch.sketch_add_constraint(sk, .DistanceY, sketch.DistanceYData{
        point1_id = p1_id,
        point2_id = p4_id,
        distance = 2.0,
    })

    // Add two more lines to demonstrate Equal constraint
    p5_id := sketch.sketch_add_point(sk, -1.5, 0.5, false)
    p6_id := sketch.sketch_add_point(sk, -0.5, 0.5, false)
    p7_id := sketch.sketch_add_point(sk, -1.5, 1.5, false)
    p8_id := sketch.sketch_add_point(sk, -0.5, 1.5, false)

    line5_id := sketch.sketch_add_line(sk, p5_id, p6_id)
    line6_id := sketch.sketch_add_line(sk, p7_id, p8_id)

    // 6. Equal constraint - shows "=" icon
    sketch.sketch_add_constraint(sk, .Equal, sketch.EqualData{
        entity1_id = line5_id,
        entity2_id = line6_id,
    })

    // 7. Horizontal for the extra lines
    sketch.sketch_add_constraint(sk, .Horizontal, sketch.HorizontalData{line_id = line5_id})
    sketch.sketch_add_constraint(sk, .Horizontal, sketch.HorizontalData{line_id = line6_id})

    // Add a circle to test circle-related constraints
    circle_center_id := sketch.sketch_add_point(sk, 4.5, 1.0, false)
    circle_id := sketch.sketch_add_circle(sk, circle_center_id, 0.8)

    fmt.println("\nTest sketch created:")
    fmt.println("  - Rectangle with H, V, ⊥, || constraints")
    fmt.println("  - Dimensional constraints (DistanceX, DistanceY)")
    fmt.println("  - Two equal length lines with = constraint")
    fmt.println("  - Circle for future constraints")
    sketch.sketch_print_info(sk)

    // Print DOF info
    dof := sketch.sketch_calculate_dof(sk)
    sketch.dof_print_info(dof)

    return sk
}

// Load different test configurations
load_test_1 :: proc(sk: ^sketch.Sketch2D) {
    fmt.println("\n[Test 1] Rectangle with dimensions")
    // Already loaded in create_test_sketch
}

load_test_2 :: proc(sk: ^sketch.Sketch2D) {
    fmt.println("\n[Test 2] Perpendicular lines")

    // Clear existing sketch
    sketch.sketch_destroy(sk)
    sk^ = sketch.sketch_init("PerpendicularTest", sketch.sketch_plane_xy())

    // Create two perpendicular lines
    p1 := sketch.sketch_add_point(sk, 0.0, 0.0, true)
    p2 := sketch.sketch_add_point(sk, 2.0, 0.0, false)
    p3 := sketch.sketch_add_point(sk, 0.0, 0.0, true)
    p4 := sketch.sketch_add_point(sk, 0.5, 1.8, false)

    line1 := sketch.sketch_add_line(sk, p1, p2)
    line2 := sketch.sketch_add_line(sk, p3, p4)

    // Add constraints
    sketch.sketch_add_constraint(sk, .Horizontal, sketch.HorizontalData{line_id = line1})
    sketch.sketch_add_constraint(sk, .Perpendicular, sketch.PerpendicularData{
        line1_id = line1,
        line2_id = line2,
    })

    sketch.sketch_print_info(sk)
}

load_test_3 :: proc(sk: ^sketch.Sketch2D) {
    fmt.println("\n[Test 3] Equal lengths and parallel")

    // Clear existing sketch
    sketch.sketch_destroy(sk)
    sk^ = sketch.sketch_init("EqualParallelTest", sketch.sketch_plane_xy())

    // Create three horizontal lines
    p1 := sketch.sketch_add_point(sk, 0.0, 0.0, true)
    p2 := sketch.sketch_add_point(sk, 2.0, 0.0, false)
    p3 := sketch.sketch_add_point(sk, 0.0, 1.0, false)
    p4 := sketch.sketch_add_point(sk, 2.0, 1.0, false)
    p5 := sketch.sketch_add_point(sk, 0.0, 2.0, false)
    p6 := sketch.sketch_add_point(sk, 2.0, 2.0, false)

    line1 := sketch.sketch_add_line(sk, p1, p2)
    line2 := sketch.sketch_add_line(sk, p3, p4)
    line3 := sketch.sketch_add_line(sk, p5, p6)

    // Add constraints
    sketch.sketch_add_constraint(sk, .Horizontal, sketch.HorizontalData{line_id = line1})
    sketch.sketch_add_constraint(sk, .Horizontal, sketch.HorizontalData{line_id = line2})
    sketch.sketch_add_constraint(sk, .Horizontal, sketch.HorizontalData{line_id = line3})

    sketch.sketch_add_constraint(sk, .Parallel, sketch.ParallelData{
        line1_id = line1,
        line2_id = line2,
    })

    sketch.sketch_add_constraint(sk, .Equal, sketch.EqualData{
        entity1_id = line1,
        entity2_id = line2,
    })

    sketch.sketch_add_constraint(sk, .Equal, sketch.EqualData{
        entity1_id = line2,
        entity2_id = line3,
    })

    sketch.sketch_print_info(sk)
}

load_test_4 :: proc(sk: ^sketch.Sketch2D) {
    fmt.println("\n[Test 4] Mixed constraints")

    // Clear existing sketch
    sketch.sketch_destroy(sk)
    sk^ = sketch.sketch_init("MixedTest", sketch.sketch_plane_xy())

    // Create various geometry
    p1 := sketch.sketch_add_point(sk, 0.0, 0.0, true)
    p2 := sketch.sketch_add_point(sk, 1.5, 0.0, false)
    p3 := sketch.sketch_add_point(sk, 1.5, 1.5, false)

    line1 := sketch.sketch_add_line(sk, p1, p2)
    line2 := sketch.sketch_add_line(sk, p2, p3)

    circle_c := sketch.sketch_add_point(sk, -1.0, 0.5, false)
    circle := sketch.sketch_add_circle(sk, circle_c, 0.5)

    // Add various constraints
    sketch.sketch_add_constraint(sk, .Horizontal, sketch.HorizontalData{line_id = line1})
    sketch.sketch_add_constraint(sk, .Vertical, sketch.VerticalData{line_id = line2})

    sketch.sketch_add_constraint(sk, .Distance, sketch.DistanceData{
        point1_id = p1,
        point2_id = p2,
        distance = 1.5,
    })

    sketch.sketch_print_info(sk)
}

// Keyboard callback
key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
    context = runtime.default_context()

    app := cast(^AppState)glfw.GetWindowUserPointer(window)
    if app == nil do return

    if action == glfw.PRESS {
        switch key {
        case glfw.KEY_Q:
            glfw.SetWindowShouldClose(window, true)

        case glfw.KEY_1:
            load_test_1(app.sketch)
            v.wireframe_mesh_destroy(&app.wireframe)
            app.wireframe = v.sketch_to_wireframe(app.sketch)

        case glfw.KEY_2:
            load_test_2(app.sketch)
            v.wireframe_mesh_destroy(&app.wireframe)
            app.wireframe = v.sketch_to_wireframe(app.sketch)

        case glfw.KEY_3:
            load_test_3(app.sketch)
            v.wireframe_mesh_destroy(&app.wireframe)
            app.wireframe = v.sketch_to_wireframe(app.sketch)

        case glfw.KEY_4:
            load_test_4(app.sketch)
            v.wireframe_mesh_destroy(&app.wireframe)
            app.wireframe = v.sketch_to_wireframe(app.sketch)

        case glfw.KEY_S:
            fmt.println("\n=== Running Constraint Solver ===")
            result := sketch.sketch_solve_constraints(app.sketch)
            sketch.solver_result_print(result)

            if result.status == .Success {
                fmt.println("✅ Constraints solved! Geometry updated.")
                // Update wireframe with solved positions
                v.wireframe_mesh_destroy(&app.wireframe)
                app.wireframe = v.sketch_to_wireframe(app.sketch)
            }

        case glfw.KEY_HOME:
            v.camera_init(&app.viewer.camera, app.viewer.camera.aspect_ratio)

        // === CONSTRAINT SHORTCUTS ===
        case glfw.KEY_H:
            // H - Horizontal constraint (requires line selected)
            fmt.println("⚠️  Horizontal constraint shortcut: Select a line first (entity selection not yet in test)")

        case glfw.KEY_V:
            // V - Vertical constraint (requires line selected)
            fmt.println("⚠️  Vertical constraint shortcut: Select a line first (entity selection not yet in test)")
        }
    }
}

// Mouse button callback
mouse_button_callback :: proc "c" (window: glfw.WindowHandle, button, action, mods: i32) {
    context = runtime.default_context()

    app := cast(^AppState)glfw.GetWindowUserPointer(window)
    if app == nil do return

    // Update viewer's mouse button state
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

// Mouse move callback
mouse_move_callback :: proc "c" (window: glfw.WindowHandle, xpos, ypos: f64) {
    context = runtime.default_context()

    app := cast(^AppState)glfw.GetWindowUserPointer(window)
    if app == nil do return

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

// Scroll callback
scroll_callback :: proc "c" (window: glfw.WindowHandle, xoffset, yoffset: f64) {
    context = runtime.default_context()

    app := cast(^AppState)glfw.GetWindowUserPointer(window)
    if app == nil do return

    // Zoom in/out
    zoom_speed := f32(0.1)
    app.viewer.camera.distance -= f32(yoffset) * zoom_speed * app.viewer.camera.distance

    // Clamp distance
    app.viewer.camera.distance = glsl.clamp(app.viewer.camera.distance, 0.5, 100.0)

    v.camera_update_position(&app.viewer.camera)
}
