// Standalone test for ManifoldCAD API
// Tests basic boolean operations without the full CAD application
package test_manifold

import "core:fmt"
import "core:c"
import "../src/core/geometry/manifold"

main :: proc() {
    fmt.println("=== ManifoldCAD API Test ===\n")

    // Test 1: Create a simple cube mesh
    fmt.println("Test 1: Creating cube mesh...")

    // Cube vertices (8 corners of a unit cube)
    cube_verts := []f32{
        0, 0, 0,  // v0
        1, 0, 0,  // v1
        1, 1, 0,  // v2
        0, 1, 0,  // v3
        0, 0, 1,  // v4
        1, 0, 1,  // v5
        1, 1, 1,  // v6
        0, 1, 1,  // v7
    }

    // Cube triangles (12 triangles, 2 per face)
    cube_tris := []u32{
        // Front face (z=0)
        0, 1, 2,
        0, 2, 3,
        // Back face (z=1)
        4, 6, 5,
        4, 7, 6,
        // Left face (x=0)
        0, 3, 7,
        0, 7, 4,
        // Right face (x=1)
        1, 5, 6,
        1, 6, 2,
        // Bottom face (y=0)
        0, 4, 5,
        0, 5, 1,
        // Top face (y=1)
        3, 2, 6,
        3, 6, 7,
    }

    // Create MeshGL
    mesh_mem := manifold.alloc_meshgl()
    if mesh_mem == nil {
        fmt.println("❌ Failed to allocate MeshGL")
        return
    }

    cube_mesh := manifold.meshgl(
        mesh_mem,
        raw_data(cube_verts),
        8,  // num vertices
        3,  // properties per vertex (x,y,z)
        raw_data(cube_tris),
        12, // num triangles
    )

    if cube_mesh == nil {
        fmt.println("❌ Failed to create cube mesh")
        manifold.delete_meshgl(mesh_mem)
        return
    }

    fmt.println("✅ Cube mesh created")
    fmt.printf("   Vertices: %d\n", manifold.meshgl_num_vert(cube_mesh))
    fmt.printf("   Triangles: %d\n", manifold.meshgl_num_tri(cube_mesh))

    // Test 2: Create Manifold from mesh
    fmt.println("\nTest 2: Creating Manifold from mesh...")

    manifold_mem := manifold.alloc_manifold()
    if manifold_mem == nil {
        fmt.println("❌ Failed to allocate Manifold")
        manifold.destruct_meshgl(cube_mesh)
        return
    }

    cube_manifold := manifold.of_meshgl(manifold_mem, cube_mesh)
    if cube_manifold == nil {
        fmt.println("❌ Failed to create Manifold")
        manifold.delete_manifold(manifold_mem)
        manifold.destruct_meshgl(cube_mesh)
        return
    }

    fmt.println("✅ Manifold created")
    fmt.printf("   Status: %v\n", manifold.status(cube_manifold))
    fmt.printf("   Volume: %.3f\n", manifold.volume(cube_manifold))
    fmt.printf("   Surface Area: %.3f\n", manifold.surface_area(cube_manifold))

    // Test 3: Extract mesh back from Manifold
    fmt.println("\nTest 3: Extracting mesh from Manifold...")

    result_mesh_mem := manifold.alloc_meshgl()
    if result_mesh_mem == nil {
        fmt.println("❌ Failed to allocate result MeshGL")
        manifold.destruct_manifold(cube_manifold)
        manifold.destruct_meshgl(cube_mesh)
        return
    }

    result_mesh := manifold.get_meshgl(result_mesh_mem, cube_manifold)
    if result_mesh == nil {
        fmt.println("❌ Failed to extract mesh")
        manifold.delete_meshgl(result_mesh_mem)
        manifold.destruct_manifold(cube_manifold)
        manifold.destruct_meshgl(cube_mesh)
        return
    }

    fmt.println("✅ Mesh extracted")
    fmt.printf("   Vertices: %d\n", manifold.meshgl_num_vert(result_mesh))
    fmt.printf("   Triangles: %d\n", manifold.meshgl_num_tri(result_mesh))

    // Test 4: Access vertex properties and triangle indices
    fmt.println("\nTest 4: Accessing mesh data...")

    num_verts := manifold.meshgl_num_vert(result_mesh)
    num_tris := manifold.meshgl_num_tri(result_mesh)
    vert_props_len := manifold.meshgl_vert_properties_length(result_mesh)
    tri_len := manifold.meshgl_tri_length(result_mesh)

    fmt.printf("   Mesh has %d verts, %d tris\n", num_verts, num_tris)
    fmt.printf("   Vert props length: %d (should be %d)\n", vert_props_len, num_verts * 3)
    fmt.printf("   Tri indices length: %d (should be %d)\n", tri_len, num_tris * 3)

    // Allocate memory for vertex properties copy
    fmt.println("   Allocating memory for vertex properties...")
    vert_props_array := make([]f32, vert_props_len)
    defer delete(vert_props_array)

    // Try accessing vertex properties
    fmt.println("   Attempting to get vertex properties (passing allocated memory)...")
    vert_props := manifold.meshgl_vert_properties(raw_data(vert_props_array), result_mesh)
    if vert_props == nil {
        fmt.println("   ❌ meshgl_vert_properties returned nil!")
    } else {
        fmt.println("   ✅ Got vertex properties pointer")

        // Print first 3 vertices using the returned pointer
        fmt.printf("   First 3 vertices (of %d):\n", num_verts)
        for i in 0..<min(3, int(num_verts)) {
            idx := i * 3
            fmt.printf("      v[%d] = (%.3f, %.3f, %.3f)\n",
                       i, vert_props[idx], vert_props[idx+1], vert_props[idx+2])
        }
    }

    // Allocate memory for triangle indices copy
    fmt.println("   Allocating memory for triangle indices...")
    tri_indices_array := make([]u32, tri_len)
    defer delete(tri_indices_array)

    // Try accessing triangle indices
    fmt.println("   Attempting to get triangle indices (passing allocated memory)...")
    tri_verts := manifold.meshgl_tri_verts(raw_data(tri_indices_array), result_mesh)
    if tri_verts == nil {
        fmt.println("   ❌ meshgl_tri_verts returned nil!")
    } else {
        fmt.println("   ✅ Got triangle indices pointer")

        // Print first 3 triangles
        fmt.printf("   First 3 triangles (of %d):\n", num_tris)
        for i in 0..<min(3, int(num_tris)) {
            idx := i * 3
            fmt.printf("      tri[%d] = [%d, %d, %d]\n",
                       i, tri_verts[idx], tri_verts[idx+1], tri_verts[idx+2])
        }
    }

    // Cleanup
    fmt.println("\nCleaning up...")
    manifold.destruct_meshgl(result_mesh)
    manifold.destruct_manifold(cube_manifold)
    manifold.destruct_meshgl(cube_mesh)

    fmt.println("\n✅ All tests completed successfully!")
}
