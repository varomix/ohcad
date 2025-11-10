// ui/viewer - 3D OpenGL viewer for CAD geometry (SDL3 version)
package ohcad_viewer

import "core:fmt"
import "core:math"
import "core:c"
import m "../../core/math"
import sdl "vendor:sdl3"
import gl "vendor:OpenGL"
import glsl "core:math/linalg/glsl"

// SDL3 Viewer state
ViewerSDL3 :: struct {
    window: ^sdl.Window,
    gl_context: sdl.GLContext,
    camera: Camera,
    config: ViewerConfig,

    // Input state
    mouse_x: f64,
    mouse_y: f64,
    mouse_left_down: bool,
    mouse_middle_down: bool,
    mouse_right_down: bool,

    // Touch/gesture state
    gesture_manager: GestureManager,

    // Rendering state
    should_close: bool,
}

// Gesture manager for multi-touch
GestureManager :: struct {
    active_fingers: map[sdl.FingerID]sdl.Finger,
    prev_centroid: Maybe([2]f32),
    prev_distance: f32,
    primary_touch_device: sdl.TouchID,
    shift_held: bool,
}

// Initialize SDL3 and create viewer window
viewer_sdl3_init :: proc(config: ViewerConfig = DEFAULT_VIEWER_CONFIG) -> (^ViewerSDL3, bool) {
    // Initialize SDL3 with video subsystem
    if !sdl.Init({.VIDEO}) {
        fmt.eprintln("ERROR: Failed to initialize SDL3:", sdl.GetError())
        return nil, false
    }

    // Set OpenGL attributes
    // Note: On macOS with SDL3, let SDL choose the OpenGL version
    // This gives us OpenGL 2.1 via Metal backend, which is sufficient for our needs
    sdl.GL_SetAttribute(.DOUBLEBUFFER, 1)

    // Create window
    window := sdl.CreateWindow(
        config.window_title,
        config.window_width,
        config.window_height,
        {.OPENGL, .RESIZABLE},
    )

    if window == nil {
        fmt.eprintln("ERROR: Failed to create SDL3 window:", sdl.GetError())
        sdl.Quit()
        return nil, false
    }

    // Create OpenGL context
    gl_context := sdl.GL_CreateContext(window)
    if gl_context == nil {
        fmt.eprintln("ERROR: Failed to create OpenGL context:", sdl.GetError())
        sdl.DestroyWindow(window)
        sdl.Quit()
        return nil, false
    }

    // Make context current
    sdl.GL_MakeCurrent(window, gl_context)

    // Load OpenGL functions
    sdl.GL_LoadLibrary(nil)
    gl.load_up_to(
        int(config.gl_major_version),
        int(config.gl_minor_version),
        sdl.gl_set_proc_address,
    )

    // Enable VSync
    sdl.GL_SetSwapInterval(1)

    // Create viewer
    viewer := new(ViewerSDL3)
    viewer.window = window
    viewer.gl_context = gl_context
    viewer.config = config
    viewer.should_close = false

    // Initialize camera with default position
    camera_init(&viewer.camera, f32(config.window_width) / f32(config.window_height))

    // Initialize gesture manager
    viewer.gesture_manager.active_fingers = make(map[sdl.FingerID]sdl.Finger)

    // Enumerate touch devices
    touch_count: c.int
    touch_devices := sdl.GetTouchDevices(&touch_count)
    if touch_devices != nil {
        defer sdl.free(touch_devices)

        fmt.printf("Found %d touch devices:\n", touch_count)
        for i in 0..<touch_count {
            touch_id := touch_devices[i]
            name := sdl.GetTouchDeviceName(touch_id)
            device_type := sdl.GetTouchDeviceType(touch_id)
            fmt.printf("  %d: %s (Type: %v)\n", i, name, device_type)

            // Store first touch device as primary
            if i == 0 {
                viewer.gesture_manager.primary_touch_device = touch_id
            }
        }
    } else {
        fmt.println("No touch devices detected")
    }

    // Enable OpenGL features
    gl.Enable(gl.DEPTH_TEST)
    gl.Enable(gl.MULTISAMPLE)
    gl.Enable(gl.LINE_SMOOTH)
    gl.Hint(gl.LINE_SMOOTH_HINT, gl.NICEST)

    // Set background color (dark gray HUD theme)
    gl.ClearColor(0.08, 0.08, 0.08, 1.0)

    fmt.println("OhCAD Viewer (SDL3) initialized successfully")
    fmt.printf("OpenGL Version: %s\n", gl.GetString(gl.VERSION))
    fmt.printf("GLSL Version: %s\n", gl.GetString(gl.SHADING_LANGUAGE_VERSION))

    version := sdl.GetVersion()
    fmt.printf("SDL Version: %d\n", version)

    return viewer, true
}

// Destroy viewer and clean up resources
viewer_sdl3_destroy :: proc(viewer: ^ViewerSDL3) {
    if viewer.gesture_manager.active_fingers != nil {
        delete(viewer.gesture_manager.active_fingers)
    }
    if viewer.gl_context != nil {
        sdl.GL_DestroyContext(viewer.gl_context)
    }
    if viewer.window != nil {
        sdl.DestroyWindow(viewer.window)
    }
    sdl.Quit()
    free(viewer)
}

// Main viewer loop - returns true while viewer should continue running
viewer_sdl3_should_continue :: proc(viewer: ^ViewerSDL3) -> bool {
    return !viewer.should_close
}

// Begin frame - clear buffers and prepare for rendering
viewer_sdl3_begin_frame :: proc(viewer: ^ViewerSDL3) {
    gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
}

// End frame - swap buffers
viewer_sdl3_end_frame :: proc(viewer: ^ViewerSDL3) {
    sdl.GL_SwapWindow(viewer.window)
}

// Process input events - returns events for custom handling
viewer_sdl3_poll_event :: proc(viewer: ^ViewerSDL3, event: ^sdl.Event) -> bool {
    return sdl.PollEvent(event)
}

// Handle window resize
viewer_sdl3_handle_resize :: proc(viewer: ^ViewerSDL3, width, height: i32) {
    gl.Viewport(0, 0, width, height)
    viewer.camera.aspect_ratio = f32(width) / f32(height)
}

// Handle mouse motion
viewer_sdl3_handle_mouse_motion :: proc(viewer: ^ViewerSDL3, x, y: f32) {
    dx := x - f32(viewer.mouse_x)
    dy := y - f32(viewer.mouse_y)

    viewer.mouse_x = f64(x)
    viewer.mouse_y = f64(y)

    // Left mouse button - orbit (for backward compatibility)
    if viewer.mouse_left_down {
        sensitivity := f32(0.005)
        viewer.camera.azimuth -= dx * sensitivity
        viewer.camera.elevation += dy * sensitivity

        // Clamp elevation to avoid gimbal lock
        viewer.camera.elevation = glsl.clamp(viewer.camera.elevation, -math.PI * 0.49, math.PI * 0.49)

        camera_update_position(&viewer.camera)
    }

    // Middle mouse button - pan (for backward compatibility)
    if viewer.mouse_middle_down {
        sensitivity := f32(0.01)

        // Calculate camera right and up vectors
        pos_f32 := glsl.vec3{f32(viewer.camera.position.x), f32(viewer.camera.position.y), f32(viewer.camera.position.z)}
        target_f32 := glsl.vec3{f32(viewer.camera.target.x), f32(viewer.camera.target.y), f32(viewer.camera.target.z)}
        up_f32 := glsl.vec3{f32(viewer.camera.up.x), f32(viewer.camera.up.y), f32(viewer.camera.up.z)}

        view_dir := glsl.normalize(target_f32 - pos_f32)
        right := glsl.normalize(glsl.cross(view_dir, up_f32))
        up := glsl.cross(right, view_dir)

        // Pan camera
        pan_x := f64(right.x * (-dx * sensitivity * viewer.camera.distance * 0.1))
        pan_y := f64(right.y * (-dx * sensitivity * viewer.camera.distance * 0.1))
        pan_z := f64(right.z * (-dx * sensitivity * viewer.camera.distance * 0.1))
        viewer.camera.target.x += pan_x
        viewer.camera.target.y += pan_y
        viewer.camera.target.z += pan_z

        pan_x = f64(up.x * (dy * sensitivity * viewer.camera.distance * 0.1))
        pan_y = f64(up.y * (dy * sensitivity * viewer.camera.distance * 0.1))
        pan_z = f64(up.z * (dy * sensitivity * viewer.camera.distance * 0.1))
        viewer.camera.target.x += pan_x
        viewer.camera.target.y += pan_y
        viewer.camera.target.z += pan_z

        camera_update_position(&viewer.camera)
    }
}

// Handle mouse button
viewer_sdl3_handle_mouse_button :: proc(viewer: ^ViewerSDL3, button: u8, pressed: bool) {
    switch button {
    case 1: // SDL_BUTTON_LEFT
        viewer.mouse_left_down = pressed
    case 2: // SDL_BUTTON_MIDDLE
        viewer.mouse_middle_down = pressed
    case 3: // SDL_BUTTON_RIGHT
        viewer.mouse_right_down = pressed
    }
}

// Handle mouse wheel
viewer_sdl3_handle_mouse_wheel :: proc(viewer: ^ViewerSDL3, y: f32) {
    // Zoom in/out
    zoom_speed := f32(0.1)
    viewer.camera.distance -= y * zoom_speed * viewer.camera.distance

    // Clamp distance
    viewer.camera.distance = glsl.clamp(viewer.camera.distance, 0.5, 100.0)

    camera_update_position(&viewer.camera)
}

// =============================================================================
// Multi-Touch Gesture Handling
// =============================================================================

// Handle finger down event
viewer_sdl3_handle_finger_down :: proc(viewer: ^ViewerSDL3, event: ^sdl.TouchFingerEvent) {
    gesture := &viewer.gesture_manager

    // Store finger in active fingers
    finger := sdl.Finger{
        id = event.fingerID,
        x = event.x,
        y = event.y,
        pressure = event.pressure,
    }
    gesture.active_fingers[event.fingerID] = finger

    fmt.printf("Finger %d down at (%.2f, %.2f) pressure=%.2f\n",
               finger.id, finger.x, finger.y, finger.pressure)
}

// Handle finger up event
viewer_sdl3_handle_finger_up :: proc(viewer: ^ViewerSDL3, event: ^sdl.TouchFingerEvent) {
    gesture := &viewer.gesture_manager

    // Remove finger from active fingers
    delete_key(&gesture.active_fingers, event.fingerID)

    // Reset gesture state when no fingers touching
    if len(gesture.active_fingers) == 0 {
        gesture.prev_centroid = nil
        gesture.prev_distance = 0
    }

    fmt.printf("Finger %d up (remaining: %d)\n", event.fingerID, len(gesture.active_fingers))
}

// Handle finger motion event
viewer_sdl3_handle_finger_motion :: proc(viewer: ^ViewerSDL3, event: ^sdl.TouchFingerEvent) {
    gesture := &viewer.gesture_manager

    // Update finger position
    if finger_ptr, ok := &gesture.active_fingers[event.fingerID]; ok {
        finger_ptr.x = event.x
        finger_ptr.y = event.y
        finger_ptr.pressure = event.pressure
    }

    // Detect gestures based on number of active fingers
    switch len(gesture.active_fingers) {
    case 2:
        // 2-finger gestures
        viewer_sdl3_handle_two_finger_gesture(viewer)
    }
}

// Handle 2-finger gestures (orbit, zoom, pan)
viewer_sdl3_handle_two_finger_gesture :: proc(viewer: ^ViewerSDL3) {
    gesture := &viewer.gesture_manager

    if len(gesture.active_fingers) != 2 do return

    // Get 2 finger positions
    fingers := make([dynamic]sdl.Finger, 0, 2)
    defer delete(fingers)

    for _, finger in gesture.active_fingers {
        append(&fingers, finger)
    }

    // Calculate centroid
    centroid := [2]f32{
        (fingers[0].x + fingers[1].x) / 2.0,
        (fingers[0].y + fingers[1].y) / 2.0,
    }

    // Calculate distance between fingers (for pinch zoom)
    dx_fingers := fingers[1].x - fingers[0].x
    dy_fingers := fingers[1].y - fingers[0].y
    distance := math.sqrt(dx_fingers*dx_fingers + dy_fingers*dy_fingers)

    // First time with 2 fingers - initialize
    if gesture.prev_centroid == nil {
        gesture.prev_centroid = centroid
        gesture.prev_distance = distance
        return
    }

    prev_centroid := gesture.prev_centroid.? or_else centroid

    // Calculate centroid delta
    dx := centroid.x - prev_centroid.x
    dy := centroid.y - prev_centroid.y

    // Check if shift is held (for pan mode)
    if gesture.shift_held {
        // 2-finger + shift = Pan
        sensitivity := f32(0.5)

        pos_f32 := glsl.vec3{f32(viewer.camera.position.x), f32(viewer.camera.position.y), f32(viewer.camera.position.z)}
        target_f32 := glsl.vec3{f32(viewer.camera.target.x), f32(viewer.camera.target.y), f32(viewer.camera.target.z)}
        up_f32 := glsl.vec3{f32(viewer.camera.up.x), f32(viewer.camera.up.y), f32(viewer.camera.up.z)}

        view_dir := glsl.normalize(target_f32 - pos_f32)
        right := glsl.normalize(glsl.cross(view_dir, up_f32))
        up := glsl.cross(right, view_dir)

        // Apply pan
        pan_amount := viewer.camera.distance * sensitivity
        viewer.camera.target.x += f64(right.x * (-dx * pan_amount))
        viewer.camera.target.y += f64(right.y * (-dx * pan_amount))
        viewer.camera.target.z += f64(right.z * (-dx * pan_amount))

        viewer.camera.target.x += f64(up.x * (dy * pan_amount))
        viewer.camera.target.y += f64(up.y * (dy * pan_amount))
        viewer.camera.target.z += f64(up.z * (dy * pan_amount))

        camera_update_position(&viewer.camera)
    } else {
        // 2-finger drag = Orbit
        sensitivity := f32(2.0)
        viewer.camera.azimuth += dx * sensitivity
        viewer.camera.elevation -= dy * sensitivity

        // Clamp elevation
        viewer.camera.elevation = glsl.clamp(viewer.camera.elevation, -math.PI * 0.49, math.PI * 0.49)

        camera_update_position(&viewer.camera)

        // 2-finger pinch = Zoom (simultaneously)
        if gesture.prev_distance > 0 {
            zoom_factor := distance / gesture.prev_distance

            // Invert for natural feel (pinch in = zoom out)
            viewer.camera.distance *= (2.0 - zoom_factor)

            // Clamp zoom
            viewer.camera.distance = glsl.clamp(viewer.camera.distance, 0.5, 100.0)

            camera_update_position(&viewer.camera)
        }
    }

    // Update previous state
    gesture.prev_centroid = centroid
    gesture.prev_distance = distance
}

// Update shift key state
viewer_sdl3_update_shift_state :: proc(viewer: ^ViewerSDL3, shift_held: bool) {
    viewer.gesture_manager.shift_held = shift_held
}
