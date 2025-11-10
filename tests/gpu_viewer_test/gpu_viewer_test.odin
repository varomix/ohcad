// SDL3 GPU Viewer Test - Test coordinate axes, grid, and wireframe rendering
package gpu_viewer_test

import "core:fmt"
import viewer "../../src/ui/viewer"
import sdl "vendor:sdl3"

main :: proc() {
    fmt.println("=== SDL3 GPU Viewer Test ===")
    fmt.println("Testing coordinate axes, grid, and wireframe mesh rendering\n")

    // Initialize viewer
    v, ok := viewer.viewer_gpu_init()
    if !ok {
        fmt.eprintln("Failed to initialize GPU viewer")
        return
    }
    defer viewer.viewer_gpu_destroy(v)

    // Create test wireframe geometry - a cube centered at origin
    cube_mesh := create_test_cube()
    defer viewer.wireframe_mesh_gpu_destroy(&cube_mesh)

    fmt.println("✓ Created test cube wireframe mesh (12 edges)")
    fmt.println("  - 4 edges on front face (Z = +1)")
    fmt.println("  - 4 edges on back face (Z = -1)")
    fmt.println("  - 4 vertical edges connecting front and back\n")

    // Main loop
    for viewer.viewer_gpu_should_continue(v) {
        // Poll events (handles input)
        viewer.viewer_gpu_poll_events(v)

        // Custom render with test geometry
        render_with_test_geometry(v, &cube_mesh)
    }

    fmt.println("\n✓ SDL3 GPU Viewer test completed")
}

// Create a wireframe cube for testing (2x2x2 centered at origin)
create_test_cube :: proc() -> viewer.WireframeMeshGPU {
    mesh := viewer.wireframe_mesh_gpu_init()

    // Define cube vertices
    // Front face (Z = +1)
    v0 := [3]f32{-1, -1,  1}
    v1 := [3]f32{ 1, -1,  1}
    v2 := [3]f32{ 1,  1,  1}
    v3 := [3]f32{-1,  1,  1}

    // Back face (Z = -1)
    v4 := [3]f32{-1, -1, -1}
    v5 := [3]f32{ 1, -1, -1}
    v6 := [3]f32{ 1,  1, -1}
    v7 := [3]f32{-1,  1, -1}

    // Front face edges
    viewer.wireframe_mesh_gpu_add_edge(&mesh, v0, v1)
    viewer.wireframe_mesh_gpu_add_edge(&mesh, v1, v2)
    viewer.wireframe_mesh_gpu_add_edge(&mesh, v2, v3)
    viewer.wireframe_mesh_gpu_add_edge(&mesh, v3, v0)

    // Back face edges
    viewer.wireframe_mesh_gpu_add_edge(&mesh, v4, v5)
    viewer.wireframe_mesh_gpu_add_edge(&mesh, v5, v6)
    viewer.wireframe_mesh_gpu_add_edge(&mesh, v6, v7)
    viewer.wireframe_mesh_gpu_add_edge(&mesh, v7, v4)

    // Connecting edges (front to back)
    viewer.wireframe_mesh_gpu_add_edge(&mesh, v0, v4)
    viewer.wireframe_mesh_gpu_add_edge(&mesh, v1, v5)
    viewer.wireframe_mesh_gpu_add_edge(&mesh, v2, v6)
    viewer.wireframe_mesh_gpu_add_edge(&mesh, v3, v7)

    return mesh
}

// Custom render function that includes test geometry
render_with_test_geometry :: proc(v: ^viewer.ViewerGPU, cube_mesh: ^viewer.WireframeMeshGPU) {
    // Acquire command buffer
    cmd := sdl.AcquireGPUCommandBuffer(v.gpu_device)
    if cmd == nil {
        return
    }

    // Acquire swapchain texture
    swapchain: ^sdl.GPUTexture
    w, h: u32
    if !sdl.AcquireGPUSwapchainTexture(cmd, v.window, &swapchain, &w, &h) {
        return
    }

    // Update window size if changed
    if w != v.window_width || h != v.window_height {
        v.window_width = w
        v.window_height = h
        v.camera.aspect_ratio = f32(w) / f32(h)
    }

    if swapchain != nil {
        // Begin render pass
        color_target := sdl.GPUColorTargetInfo{
            texture = swapchain,
            load_op = .CLEAR,
            store_op = .STORE,
            clear_color = {0.08, 0.08, 0.08, 1.0},  // Dark gray background
        }

        pass := sdl.BeginGPURenderPass(cmd, &color_target, 1, nil)

        // Bind pipeline
        sdl.BindGPUGraphicsPipeline(pass, v.pipeline)

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
        view := viewer.camera_get_view_matrix(&v.camera)
        proj := viewer.camera_get_projection_matrix(&v.camera)
        mvp := proj * view

        // Render grid first (background)
        viewer.viewer_gpu_render_grid(v, cmd, pass, mvp)

        // Render coordinate axes
        viewer.viewer_gpu_render_axes(v, cmd, pass, mvp)

        // Render test cube wireframe (cyan, 3 pixels thick)
        viewer.viewer_gpu_render_wireframe(v, cmd, pass, cube_mesh, {0.0, 1.0, 1.0, 1.0}, mvp, 3.0)

        sdl.EndGPURenderPass(pass)
    }

    // Submit command buffer
    _ = sdl.SubmitGPUCommandBuffer(cmd)
}
