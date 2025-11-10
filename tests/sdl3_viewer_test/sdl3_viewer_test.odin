// SDL3 Viewer Test - Minimal test to verify SDL3 viewer works
package sdl3_viewer_test

import "core:fmt"
import v "../../src/ui/viewer"
import sdl "vendor:sdl3"

main :: proc() {
    fmt.println("=== SDL3 Viewer Test ===")

    // Initialize SDL3 viewer
    viewer, ok := v.viewer_sdl3_init()
    if !ok {
        fmt.eprintln("Failed to initialize SDL3 viewer")
        return
    }
    defer v.viewer_sdl3_destroy(viewer)

    fmt.println("\nSDL3 Viewer initialized successfully!")
    fmt.println("Camera controls:")
    fmt.println("  Mouse: Left = Orbit, Middle = Pan, Wheel = Zoom")
    fmt.println("  Touch: 2-finger drag = Orbit, 2-finger pinch = Zoom")
    fmt.println("  Touch: 2-finger + Shift = Pan")
    fmt.println("  [HOME] Reset camera")
    fmt.println("  [Q] or [ESC] Quit")
    fmt.println("")

    // Main loop
    event: sdl.Event
    for v.viewer_sdl3_should_continue(viewer) {
        // Poll events
        for v.viewer_sdl3_poll_event(viewer, &event) {
            #partial switch event.type {
            case .QUIT:
                viewer.should_close = true

            case .WINDOW_RESIZED:
                w := event.window.data1
                h := event.window.data2
                v.viewer_sdl3_handle_resize(viewer, w, h)

            case .MOUSE_MOTION:
                v.viewer_sdl3_handle_mouse_motion(viewer, event.motion.x, event.motion.y)

            case .MOUSE_BUTTON_DOWN:
                v.viewer_sdl3_handle_mouse_button(viewer, event.button.button, true)

            case .MOUSE_BUTTON_UP:
                v.viewer_sdl3_handle_mouse_button(viewer, event.button.button, false)

            case .MOUSE_WHEEL:
                v.viewer_sdl3_handle_mouse_wheel(viewer, event.wheel.y)

            case .KEY_DOWN:
                switch event.key.key {
                case sdl.K_ESCAPE, sdl.K_Q:
                    viewer.should_close = true

                case sdl.K_HOME:
                    v.camera_init(&viewer.camera, viewer.camera.aspect_ratio)
                    fmt.println("Camera reset")

                case sdl.K_LSHIFT, sdl.K_RSHIFT:
                    v.viewer_sdl3_update_shift_state(viewer, true)
                }

            case .KEY_UP:
                switch event.key.key {
                case sdl.K_LSHIFT, sdl.K_RSHIFT:
                    v.viewer_sdl3_update_shift_state(viewer, false)
                }

            // Touch events
            case .FINGER_DOWN:
                v.viewer_sdl3_handle_finger_down(viewer, &event.tfinger)

            case .FINGER_UP:
                v.viewer_sdl3_handle_finger_up(viewer, &event.tfinger)

            case .FINGER_MOTION:
                v.viewer_sdl3_handle_finger_motion(viewer, &event.tfinger)
            }
        }

        // Render
        v.viewer_sdl3_begin_frame(viewer)

        // Calculate MVP matrix
        view := v.camera_get_view_matrix(&viewer.camera)
        projection := v.camera_get_projection_matrix(&viewer.camera)
        mvp := projection * view

        // Render grid and axes (if we have those functions)
        // For now, just clear screen

        v.viewer_sdl3_end_frame(viewer)
    }

    fmt.println("\n✓ SDL3 Viewer test completed successfully")
}
