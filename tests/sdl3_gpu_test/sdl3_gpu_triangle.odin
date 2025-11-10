// SDL3 GPU Triangle Test - Load metallib and render a triangle
package sdl3_gpu_triangle_test

import "core:fmt"
import "core:os"
import sdl "vendor:sdl3"

// Vertex structure matching Metal shader
Vertex :: struct {
    position: [3]f32,
}

// Uniform buffer matching Metal shader
Uniforms :: struct {
    mvp: matrix[4,4]f32,
    color: [4]f32,
}

main :: proc() {
    fmt.println("=== SDL3 GPU Triangle Test ===")
    fmt.println("Testing Metal shader pipeline\n")

    // Initialize SDL3
    if !sdl.Init({.VIDEO}) {
        fmt.eprintln("ERROR: Failed to initialize SDL3:", sdl.GetError())
        return
    }
    defer sdl.Quit()

    // Create window
    window := sdl.CreateWindow(
        "SDL3 GPU - Triangle Test",
        1280,
        720,
        {.RESIZABLE},
    )

    if window == nil {
        fmt.eprintln("ERROR: Failed to create window:", sdl.GetError())
        return
    }
    defer sdl.DestroyWindow(window)

    // Create GPU device
    gpu_device := sdl.CreateGPUDevice(
        {.METALLIB},
        false,
        nil,
    )

    if gpu_device == nil {
        fmt.eprintln("ERROR: Failed to create GPU device:", sdl.GetError())
        return
    }
    defer sdl.DestroyGPUDevice(gpu_device)

    fmt.println("✓ GPU device created (Metal backend)")

    // Claim window for GPU rendering
    if !sdl.ClaimWindowForGPUDevice(gpu_device, window) {
        fmt.eprintln("ERROR: Failed to claim window for GPU:", sdl.GetError())
        return
    }

    // Load metallib shader (with push constants for uniforms)
    metallib_path := "../../src/ui/viewer/shaders/line_shader.metallib"
    shader_data, shader_ok := os.read_entire_file(metallib_path)
    if !shader_ok {
        fmt.eprintln("ERROR: Failed to read metallib file:", metallib_path)
        return
    }
    defer delete(shader_data)

    fmt.printf("✓ Loaded metallib: %s (%d bytes)\n", metallib_path, len(shader_data))

    // Create vertex shader
    vertex_shader_info := sdl.GPUShaderCreateInfo{
        code = raw_data(shader_data),
        code_size = len(shader_data),
        entrypoint = "vertex_main",
        format = {.METALLIB},  // bit_set format
        stage = .VERTEX,
        num_uniform_buffers = 1,  // We have 1 uniform buffer (push constants)
        num_storage_buffers = 0,
    }

    vertex_shader := sdl.CreateGPUShader(gpu_device, vertex_shader_info)
    if vertex_shader == nil {
        fmt.eprintln("ERROR: Failed to create vertex shader:", sdl.GetError())
        return
    }
    defer sdl.ReleaseGPUShader(gpu_device, vertex_shader)

    fmt.println("✓ Vertex shader created")

    // Create fragment shader
    fragment_shader_info := sdl.GPUShaderCreateInfo{
        code = raw_data(shader_data),
        code_size = len(shader_data),
        entrypoint = "fragment_main",
        format = {.METALLIB},  // bit_set format
        stage = .FRAGMENT,
        num_uniform_buffers = 1,  // We have 1 uniform buffer (push constants)
        num_storage_buffers = 0,
    }

    fragment_shader := sdl.CreateGPUShader(gpu_device, fragment_shader_info)
    if fragment_shader == nil {
        fmt.eprintln("ERROR: Failed to create fragment shader:", sdl.GetError())
        return
    }
    defer sdl.ReleaseGPUShader(gpu_device, fragment_shader)

    fmt.println("✓ Fragment shader created")

    // Create graphics pipeline
    vertex_attribute := sdl.GPUVertexAttribute{
        location = 0,
        format = .FLOAT3,  // vec3 position
        offset = 0,
    }

    vertex_binding := sdl.GPUVertexBufferDescription{
        slot = 0,
        pitch = size_of(Vertex),
        input_rate = .VERTEX,
    }

    vertex_input_state := sdl.GPUVertexInputState{
        vertex_buffer_descriptions = &vertex_binding,
        num_vertex_buffers = 1,
        vertex_attributes = &vertex_attribute,
        num_vertex_attributes = 1,
    }

    color_target := sdl.GPUColorTargetDescription{
        format = sdl.GetGPUSwapchainTextureFormat(gpu_device, window),
        blend_state = {
            enable_blend = false,
            alpha_blend_op = .ADD,
            color_blend_op = .ADD,
            src_color_blendfactor = .ONE,
            src_alpha_blendfactor = .ONE,
            dst_color_blendfactor = .ZERO,
            dst_alpha_blendfactor = .ZERO,
        },
    }

    pipeline_info := sdl.GPUGraphicsPipelineCreateInfo{
        vertex_shader = vertex_shader,
        fragment_shader = fragment_shader,
        vertex_input_state = vertex_input_state,
        primitive_type = .TRIANGLELIST,
        rasterizer_state = {
            fill_mode = .FILL,
            cull_mode = .NONE,
            front_face = .COUNTER_CLOCKWISE,
        },
        target_info = {
            num_color_targets = 1,
            color_target_descriptions = &color_target,
            has_depth_stencil_target = false,
        },
    }

    pipeline := sdl.CreateGPUGraphicsPipeline(gpu_device, pipeline_info)
    if pipeline == nil {
        fmt.eprintln("ERROR: Failed to create graphics pipeline:", sdl.GetError())
        return
    }
    defer sdl.ReleaseGPUGraphicsPipeline(gpu_device, pipeline)

    fmt.println("✓ Graphics pipeline created")

    // Create vertex buffer with triangle data
    vertices := []Vertex{
        {{0.0, 0.5, 0.0}},   // Top
        {{-0.5, -0.5, 0.0}}, // Bottom left
        {{0.5, -0.5, 0.0}},  // Bottom right
    }

    vertex_buffer_info := sdl.GPUBufferCreateInfo{
        usage = {.VERTEX},
        size = u32(len(vertices) * size_of(Vertex)),
    }

    vertex_buffer := sdl.CreateGPUBuffer(gpu_device, vertex_buffer_info)
    if vertex_buffer == nil {
        fmt.eprintln("ERROR: Failed to create vertex buffer:", sdl.GetError())
        return
    }
    defer sdl.ReleaseGPUBuffer(gpu_device, vertex_buffer)

    // Upload vertex data via transfer buffer
    transfer_buffer_info := sdl.GPUTransferBufferCreateInfo{
        usage = .UPLOAD,
        size = u32(len(vertices) * size_of(Vertex)),
    }

    transfer_buffer := sdl.CreateGPUTransferBuffer(gpu_device, transfer_buffer_info)
    if transfer_buffer == nil {
        fmt.eprintln("ERROR: Failed to create transfer buffer:", sdl.GetError())
        return
    }
    defer sdl.ReleaseGPUTransferBuffer(gpu_device, transfer_buffer)

    // Map and copy vertex data
    transfer_ptr := sdl.MapGPUTransferBuffer(gpu_device, transfer_buffer, false)
    if transfer_ptr == nil {
        fmt.eprintln("ERROR: Failed to map transfer buffer")
        return
    }

    // Copy vertices to transfer buffer
    dest_slice := ([^]Vertex)(transfer_ptr)[:len(vertices)]
    copy(dest_slice, vertices)

    sdl.UnmapGPUTransferBuffer(gpu_device, transfer_buffer)

    // Upload transfer buffer to GPU
    upload_cmd := sdl.AcquireGPUCommandBuffer(gpu_device)
    copy_pass := sdl.BeginGPUCopyPass(upload_cmd)

    buffer_region := sdl.GPUTransferBufferLocation{
        transfer_buffer = transfer_buffer,
        offset = 0,
    }

    buffer_dest := sdl.GPUBufferRegion{
        buffer = vertex_buffer,
        offset = 0,
        size = u32(len(vertices) * size_of(Vertex)),
    }

    sdl.UploadToGPUBuffer(copy_pass, buffer_region, buffer_dest, false)
    sdl.EndGPUCopyPass(copy_pass)
    _ = sdl.SubmitGPUCommandBuffer(upload_cmd)

    fmt.println("✓ Vertex buffer created and uploaded")

    // Create uniform buffer
    uniform_buffer_info := sdl.GPUBufferCreateInfo{
        usage = {.GRAPHICS_STORAGE_READ},  // For uniform buffers
        size = u32(size_of(Uniforms)),
    }

    uniform_buffer := sdl.CreateGPUBuffer(gpu_device, uniform_buffer_info)
    if uniform_buffer == nil {
        fmt.eprintln("ERROR: Failed to create uniform buffer:", sdl.GetError())
        return
    }
    defer sdl.ReleaseGPUBuffer(gpu_device, uniform_buffer)

    fmt.println("✓ Uniform buffer created")
    fmt.println("\nStarting render loop...")
    fmt.println("  Triangle: Cyan color")
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

        // Update uniforms (identity matrix for now, cyan color)
        uniforms := Uniforms{
            mvp = matrix[4,4]f32{
                1, 0, 0, 0,
                0, 1, 0, 0,
                0, 0, 1, 0,
                0, 0, 0, 1,
            },
            color = {0.0, 1.0, 1.0, 1.0},  // Cyan
        }

        // Debug: Print uniform data once
        if frame_count == 0 {
            fmt.printf("\n[DEBUG] Uniform data:\n")
            fmt.printf("  MVP: %v\n", uniforms.mvp)
            fmt.printf("  Color: %v\n", uniforms.color)
            fmt.printf("  Sizeof(Uniforms): %d bytes\n", size_of(Uniforms))
            fmt.printf("  Sizeof(matrix[4,4]f32): %d bytes\n", size_of(matrix[4,4]f32))
            fmt.printf("  Sizeof([4]f32): %d bytes\n\n", size_of([4]f32))
        }

        // Upload uniforms
        uniform_transfer := sdl.CreateGPUTransferBuffer(gpu_device, sdl.GPUTransferBufferCreateInfo{
            usage = .UPLOAD,
            size = u32(size_of(Uniforms)),
        })

        if uniform_transfer != nil {
            uniform_ptr := sdl.MapGPUTransferBuffer(gpu_device, uniform_transfer, false)
            if uniform_ptr != nil {
                uniform_dest := ([^]Uniforms)(uniform_ptr)[:1]
                uniform_dest[0] = uniforms
                sdl.UnmapGPUTransferBuffer(gpu_device, uniform_transfer)

                // Upload to uniform buffer
                uniform_cmd := sdl.AcquireGPUCommandBuffer(gpu_device)
                uniform_copy := sdl.BeginGPUCopyPass(uniform_cmd)

                uniform_src := sdl.GPUTransferBufferLocation{
                    transfer_buffer = uniform_transfer,
                    offset = 0,
                }

                uniform_dst := sdl.GPUBufferRegion{
                    buffer = uniform_buffer,
                    offset = 0,
                    size = u32(size_of(Uniforms)),
                }

                sdl.UploadToGPUBuffer(uniform_copy, uniform_src, uniform_dst, false)
                sdl.EndGPUCopyPass(uniform_copy)
                _ = sdl.SubmitGPUCommandBuffer(uniform_cmd)
            }

            sdl.ReleaseGPUTransferBuffer(gpu_device, uniform_transfer)
        }

        // Acquire command buffer
        cmd_buffer := sdl.AcquireGPUCommandBuffer(gpu_device)
        if cmd_buffer == nil {
            continue
        }

        // Acquire swapchain texture
        swapchain_texture: ^sdl.GPUTexture
        w, h: u32
        if !sdl.AcquireGPUSwapchainTexture(cmd_buffer, window, &swapchain_texture, &w, &h) {
            continue
        }

        if swapchain_texture != nil {
            // Begin render pass
            color_target_info := sdl.GPUColorTargetInfo{
                texture = swapchain_texture,
                load_op = .CLEAR,
                store_op = .STORE,
                clear_color = {0.08, 0.08, 0.08, 1.0},
            }

            render_pass := sdl.BeginGPURenderPass(cmd_buffer, &color_target_info, 1, nil)

            // Bind pipeline
            sdl.BindGPUGraphicsPipeline(render_pass, pipeline)

            // Set viewport to match window size
            viewport := sdl.GPUViewport{
                x = 0,
                y = 0,
                w = f32(w),
                h = f32(h),
                min_depth = 0.0,
                max_depth = 1.0,
            }
            sdl.SetGPUViewport(render_pass, viewport)

            // Set scissor to match window size
            scissor := sdl.Rect{
                x = 0,
                y = 0,
                w = i32(w),
                h = i32(h),
            }
            sdl.SetGPUScissor(render_pass, scissor)

            // Bind vertex buffer
            vertex_binding_info := sdl.GPUBufferBinding{
                buffer = vertex_buffer,
                offset = 0,
            }
            sdl.BindGPUVertexBuffers(render_pass, 0, &vertex_binding_info, 1)

            // Push uniform data (MVP + color) to shaders
            sdl.PushGPUVertexUniformData(cmd_buffer, 0, &uniforms, size_of(Uniforms))
            sdl.PushGPUFragmentUniformData(cmd_buffer, 0, &uniforms, size_of(Uniforms))

            // Draw triangle
            sdl.DrawGPUPrimitives(render_pass, 3, 1, 0, 0)

            sdl.EndGPURenderPass(render_pass)
        }

        // Submit command buffer
        _ = sdl.SubmitGPUCommandBuffer(cmd_buffer)

        frame_count += 1

        // Print progress every 60 frames
        if frame_count % 60 == 0 {
            fmt.printf("  Frame %d rendered\n", frame_count)
        }
    }

    fmt.printf("\n✓ Triangle test completed successfully (%d frames rendered)\n", frame_count)
    fmt.println("✓ Metal shaders and graphics pipeline working!")
}
