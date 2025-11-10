// Simple SDL3 test program to verify SDL3 installation
// This is a classic "getting started" program that creates a window and handles events
package sdl3_test

import "core:fmt"
import sdl "vendor:sdl3"

main :: proc() {
    fmt.println("=== SDL3 Simple Test ===")

    // Initialize SDL3 with video subsystem
    fmt.println("Initializing SDL3...")
    if !sdl.Init({.VIDEO}) {
        fmt.eprintln("Failed to initialize SDL3:", sdl.GetError())
        return
    }
    defer sdl.Quit()

    fmt.println("✓ SDL3 initialized successfully")

    // Get SDL version info (returns single integer in SDL3)
    version := sdl.GetVersion()
    fmt.printf("SDL Version: %d\n", version)

    // Create a window
    fmt.println("\nCreating window...")
    window := sdl.CreateWindow(
        "SDL3 Test Window",
        800, 600,
        {.RESIZABLE},
    )

    if window == nil {
        fmt.eprintln("Failed to create window:", sdl.GetError())
        return
    }
    defer sdl.DestroyWindow(window)

    fmt.println("✓ Window created successfully")
    fmt.println("\nWindow is open! Press ESC or close window to exit.")
    fmt.println("Controls:")
    fmt.println("  ESC - Exit")
    fmt.println("  Space - Print message")

    // Main event loop
    running := true
    event: sdl.Event

    for running {
        // Poll events
        for sdl.PollEvent(&event) {
            #partial switch event.type {
            case .QUIT:
                fmt.println("\nQuit event received")
                running = false

            case .KEY_DOWN:
                // SDL3 uses Keycode as distinct Uint32, compare directly
                switch event.key.key {
                case sdl.K_ESCAPE:
                    fmt.println("\nESC pressed - exiting")
                    running = false

                case sdl.K_SPACE:
                    fmt.println("Space bar pressed!")
                }

            case .WINDOW_RESIZED:
                w := event.window.data1
                h := event.window.data2
                fmt.printf("Window resized to: %d x %d\n", w, h)
            }
        }

        // Small delay to prevent CPU spinning
        sdl.Delay(16)  // ~60 FPS
    }

    fmt.println("\n✓ SDL3 test completed successfully")
    fmt.println("SDL3 is working correctly on your system!")
}
