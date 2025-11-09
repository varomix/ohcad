// ui/viewer - 3D OpenGL viewer for CAD geometry
package ohcad_viewer

import "core:fmt"
import "core:math"
import "base:runtime"
import glfw "vendor:glfw"
import gl "vendor:OpenGL"
import m "../../core/math"
import glsl "core:math/linalg/glsl"

// Viewer configuration
ViewerConfig :: struct {
    window_width: i32,
    window_height: i32,
    window_title: cstring,
    gl_major_version: i32,
    gl_minor_version: i32,
    msaa_samples: i32,
}

// Default viewer configuration
DEFAULT_VIEWER_CONFIG :: ViewerConfig{
    window_width = 1280,
    window_height = 720,
    window_title = "OhCAD Viewer",
    gl_major_version = 3,
    gl_minor_version = 3,
    msaa_samples = 4,
}

// Camera for 3D navigation
Camera :: struct {
    position: m.Vec3,
    target: m.Vec3,
    up: m.Vec3,

    // Orbit controls
    distance: f32,
    azimuth: f32,   // Horizontal rotation (radians)
    elevation: f32, // Vertical rotation (radians)

    // Projection
    fov: f32,
    near_plane: f32,
    far_plane: f32,
    aspect_ratio: f32,
}

// Viewer state
Viewer :: struct {
    window: glfw.WindowHandle,
    camera: Camera,
    config: ViewerConfig,

    // Input state
    mouse_x: f64,
    mouse_y: f64,
    mouse_left_down: bool,
    mouse_middle_down: bool,
    mouse_right_down: bool,

    // Rendering state
    should_close: bool,
}

// Initialize GLFW and create viewer window
viewer_init :: proc(config: ViewerConfig = DEFAULT_VIEWER_CONFIG) -> (^Viewer, bool) {
    // Initialize GLFW
    if !glfw.Init() {
        fmt.eprintln("ERROR: Failed to initialize GLFW")
        return nil, false
    }

    // Set OpenGL version hints
    glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, config.gl_major_version)
    glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, config.gl_minor_version)
    glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
    glfw.WindowHint(glfw.OPENGL_FORWARD_COMPAT, glfw.TRUE)
    glfw.WindowHint(glfw.SAMPLES, config.msaa_samples)

    // Create window
    window := glfw.CreateWindow(config.window_width, config.window_height, config.window_title, nil, nil)
    if window == nil {
        fmt.eprintln("ERROR: Failed to create GLFW window")
        glfw.Terminate()
        return nil, false
    }

    // Make OpenGL context current
    glfw.MakeContextCurrent(window)

    // Load OpenGL functions
    gl.load_up_to(int(config.gl_major_version), int(config.gl_minor_version), glfw.gl_set_proc_address)

    // Enable VSync
    glfw.SwapInterval(1)

    // Create viewer
    viewer := new(Viewer)
    viewer.window = window
    viewer.config = config
    viewer.should_close = false

    // Initialize camera with default position
    camera_init(&viewer.camera, f32(config.window_width) / f32(config.window_height))

    // Set up callbacks
    glfw.SetWindowUserPointer(window, viewer)
    glfw.SetFramebufferSizeCallback(window, framebuffer_size_callback)
    glfw.SetCursorPosCallback(window, mouse_callback)
    glfw.SetMouseButtonCallback(window, mouse_button_callback)
    glfw.SetScrollCallback(window, scroll_callback)
    glfw.SetKeyCallback(window, key_callback)

    // Enable OpenGL features
    gl.Enable(gl.DEPTH_TEST)
    gl.Enable(gl.MULTISAMPLE)
    gl.Enable(gl.LINE_SMOOTH)
    gl.Hint(gl.LINE_SMOOTH_HINT, gl.NICEST)

    // Set background color (dark gray HUD theme)
    gl.ClearColor(0.08, 0.08, 0.08, 1.0)  //

    fmt.println("OhCAD Viewer initialized successfully")
    fmt.printf("OpenGL Version: %s\n", gl.GetString(gl.VERSION))
    fmt.printf("GLSL Version: %s\n", gl.GetString(gl.SHADING_LANGUAGE_VERSION))

    return viewer, true
}

// Destroy viewer and clean up resources
viewer_destroy :: proc(viewer: ^Viewer) {
    if viewer.window != nil {
        glfw.DestroyWindow(viewer.window)
    }
    glfw.Terminate()
    free(viewer)
}

// Initialize camera with default values
camera_init :: proc(camera: ^Camera, aspect_ratio: f32) {
    camera.target = m.Vec3{0, 0, 0}
    camera.up = m.Vec3{0, 1, 0}

    // Default orbit parameters
    camera.distance = 10.0
    camera.azimuth = math.PI * 0.25  // 45 degrees
    camera.elevation = math.PI * 0.25 // 45 degrees

    // Projection parameters
    camera.fov = 45.0
    camera.near_plane = 0.1
    camera.far_plane = 1000.0
    camera.aspect_ratio = aspect_ratio

    // Update camera position from orbit parameters
    camera_update_position(camera)
}

// Update camera position from orbit parameters
camera_update_position :: proc(camera: ^Camera) {
    // Convert spherical coordinates to Cartesian
    x := camera.distance * math.cos(camera.elevation) * math.cos(camera.azimuth)
    y := camera.distance * math.sin(camera.elevation)
    z := camera.distance * math.cos(camera.elevation) * math.sin(camera.azimuth)

    camera.position = camera.target + m.Vec3{f64(x), f64(y), f64(z)}
}

// Get view matrix for camera
camera_get_view_matrix :: proc(camera: ^Camera) -> glsl.mat4 {
    // Convert f64 vectors to f32 for glsl.mat4LookAt
    pos := glsl.vec3{f32(camera.position.x), f32(camera.position.y), f32(camera.position.z)}
    target := glsl.vec3{f32(camera.target.x), f32(camera.target.y), f32(camera.target.z)}
    up := glsl.vec3{f32(camera.up.x), f32(camera.up.y), f32(camera.up.z)}
    return glsl.mat4LookAt(pos, target, up)
}

// Get projection matrix for camera
camera_get_projection_matrix :: proc(camera: ^Camera) -> glsl.mat4 {
    return glsl.mat4Perspective(
        math.to_radians(camera.fov),
        camera.aspect_ratio,
        camera.near_plane,
        camera.far_plane,
    )
}

// Main viewer loop - returns true while viewer should continue running
viewer_should_continue :: proc(viewer: ^Viewer) -> bool {
    return !glfw.WindowShouldClose(viewer.window) && !viewer.should_close
}

// Begin frame - clear buffers and prepare for rendering
viewer_begin_frame :: proc(viewer: ^Viewer) {
    gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
}

// End frame - swap buffers and poll events
viewer_end_frame :: proc(viewer: ^Viewer) {
    glfw.SwapBuffers(viewer.window)
    glfw.PollEvents()
}

// Process keyboard input
viewer_process_input :: proc(viewer: ^Viewer) {
    // ESC to close
    if glfw.GetKey(viewer.window, glfw.KEY_ESCAPE) == glfw.PRESS {
        viewer.should_close = true
    }
}

// =============================================================================
// GLFW Callbacks
// =============================================================================

framebuffer_size_callback :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
    context = runtime.default_context()
    gl.Viewport(0, 0, width, height)

    viewer := cast(^Viewer)glfw.GetWindowUserPointer(window)
    if viewer != nil {
        viewer.camera.aspect_ratio = f32(width) / f32(height)
    }
}

mouse_callback :: proc "c" (window: glfw.WindowHandle, xpos, ypos: f64) {
    context = runtime.default_context()

    viewer := cast(^Viewer)glfw.GetWindowUserPointer(window)
    if viewer == nil do return

    dx := f32(xpos - viewer.mouse_x)
    dy := f32(ypos - viewer.mouse_y)

    viewer.mouse_x = xpos
    viewer.mouse_y = ypos

    // Left mouse button - orbit
    if viewer.mouse_left_down {
        sensitivity := f32(0.005)
        viewer.camera.azimuth -= dx * sensitivity
        viewer.camera.elevation += dy * sensitivity

        // Clamp elevation to avoid gimbal lock
        viewer.camera.elevation = glsl.clamp(viewer.camera.elevation, -math.PI * 0.49, math.PI * 0.49)

        camera_update_position(&viewer.camera)
    }

    // Middle mouse button - pan
    if viewer.mouse_middle_down {
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

mouse_button_callback :: proc "c" (window: glfw.WindowHandle, button, action, mods: i32) {
    context = runtime.default_context()

    viewer := cast(^Viewer)glfw.GetWindowUserPointer(window)
    if viewer == nil do return

    if button == glfw.MOUSE_BUTTON_LEFT {
        viewer.mouse_left_down = (action == glfw.PRESS)
    }
    if button == glfw.MOUSE_BUTTON_MIDDLE {
        viewer.mouse_middle_down = (action == glfw.PRESS)
    }
    if button == glfw.MOUSE_BUTTON_RIGHT {
        viewer.mouse_right_down = (action == glfw.PRESS)
    }
}

scroll_callback :: proc "c" (window: glfw.WindowHandle, xoffset, yoffset: f64) {
    context = runtime.default_context()

    viewer := cast(^Viewer)glfw.GetWindowUserPointer(window)
    if viewer == nil do return

    // Zoom in/out
    zoom_speed := f32(0.1)
    viewer.camera.distance -= f32(yoffset) * zoom_speed * viewer.camera.distance

    // Clamp distance
    viewer.camera.distance = glsl.clamp(viewer.camera.distance, 0.5, 100.0)

    camera_update_position(&viewer.camera)
}

key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
    context = runtime.default_context()

    viewer := cast(^Viewer)glfw.GetWindowUserPointer(window)
    if viewer == nil do return

    if action == glfw.PRESS {
        // Home key - reset camera
        if key == glfw.KEY_HOME {
            camera_init(&viewer.camera, viewer.camera.aspect_ratio)
        }
    }
}
