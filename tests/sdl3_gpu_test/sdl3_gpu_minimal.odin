// SDL3 GPU Minimal Test - Verify Metal backend works
package sdl3_gpu_test

import "core:fmt"
import "core:c"
import sdl "vendor:sdl3"

main :: proc() {
    fmt.println("=== SDL3 GPU Minimal Test ===")
    fmt.println("Testing Metal backend on macOS\n")

    // Initialize SDL3
    if !sdl.Init({.VIDEO}) {
        fmt.eprintln("ERROR: Failed to initialize SDL3:", sdl.GetError())
        return
    }
    defer sdl.Quit()

    fmt.println("✓ SDL3 initialized")

    // Create window
    window := sdl.CreateWindow(
        "SDL3 GPU Test - Metal Backend",
        1280,
        720,
        {.RESIZABLE},
    )

    if window == nil {
        fmt.eprintln("ERROR: Failed to create window:", sdl.GetError())
        return
    }
    defer sdl.DestroyWindow(window)

    fmt.println("✓ Window created")

    // Create GPU device with Metal backend (METALLIB shader format for macOS)
    gpu_device := sdl.CreateGPUDevice(
        {.METALLIB},  // Metal shaders on macOS (bit_set format)
        false,  // debug_mode
        nil,  // driver name (nil = auto-select Metal on macOS)
    )

    if gpu_device == nil {
        fmt.eprintln("ERROR: Failed to create GPU device:", sdl.GetError())
        fmt.eprintln("Note: SDL3 GPU requires Metal support on macOS")
        return
    }
    defer sdl.DestroyGPUDevice(gpu_device)

    fmt.println("✓ GPU device created (Metal backend)")

    // Get GPU device driver info
    driver := sdl.GetGPUDeviceDriver(gpu_device)
    fmt.printf("  GPU Driver: %s\n", driver)

    // Claim window for GPU rendering
    if !sdl.ClaimWindowForGPUDevice(gpu_device, window) {
        fmt.eprintln("ERROR: Failed to claim window for GPU:", sdl.GetError())
        return
    }

    fmt.println("✓ Window claimed for GPU rendering")
    fmt.println("\nStarting render loop...")
    fmt.println("  Background: Dark gray (0.08, 0.08, 0.08)")
    fmt.println("  Press [Q] or [ESC] to quit\n")

    // Main loop
    running := true
    event: sdl.Event
    frame_count: u64 = 0

    for running {
        // Poll events
        for sdl.PollEvent(&event) {
            #partial switch event.type {
            case .QUIT:
                running = false

            case .KEY_DOWN:
                switch event.key.key {
                case sdl.K_ESCAPE, sdl.K_Q:
                    running = false
                }
            }
        }

        // Acquire command buffer
        cmd_buffer := sdl.AcquireGPUCommandBuffer(gpu_device)
        if cmd_buffer == nil {
            fmt.eprintln("ERROR: Failed to acquire command buffer")
            continue
        }

        // Acquire swapchain texture
        swapchain_texture: ^sdl.GPUTexture
        w, h: u32
        if !sdl.AcquireGPUSwapchainTexture(cmd_buffer, window, &swapchain_texture, &w, &h) {
            fmt.eprintln("ERROR: Failed to acquire swapchain texture")
            continue
        }

        if swapchain_texture != nil {
            // Begin render pass - clear to dark gray
            color_target := sdl.GPUColorTargetInfo{
                texture = swapchain_texture,
                load_op = .CLEAR,
                store_op = .STORE,
                clear_color = {0.08, 0.08, 0.08, 1.0},  // Dark gray background
            }

            render_pass := sdl.BeginGPURenderPass(cmd_buffer, &color_target, 1, nil)

            // TODO: Draw geometry here
            // For now, just clearing the screen

            sdl.EndGPURenderPass(render_pass)
        }

        // Submit command buffer
        submitted := sdl.SubmitGPUCommandBuffer(cmd_buffer)
        if !submitted {
            fmt.eprintln("WARNING: Failed to submit command buffer")
        }

        frame_count += 1

        // Print progress every 60 frames
        if frame_count % 60 == 0 {
            fmt.printf("  Frame %d rendered\n", frame_count)
        }
    }

    fmt.printf("\n✓ SDL3 GPU test completed successfully (%d frames rendered)\n", frame_count)
    fmt.println("✓ Metal backend is working!")
}
