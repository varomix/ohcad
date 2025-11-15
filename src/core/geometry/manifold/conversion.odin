package manifold

// Mesh Conversion Utilities
// Convert between SimpleSolid (OhCAD) and ManifoldMesh (ManifoldCAD)

import "core:fmt"
import "core:c"
import extrude "../../../features/extrude"
import m "../../math"
import glsl "core:math/linalg/glsl"

// =============================================================================
// SimpleSolid → ManifoldMesh Conversion
// =============================================================================

// Convert SimpleSolid triangle mesh to ManifoldMesh format
// Returns MeshGL handle (must be freed with destruct_meshgl)
solid_to_manifold_mesh :: proc(solid: ^extrude.SimpleSolid) -> (MeshGL, bool) {
    if solid == nil || len(solid.triangles) == 0 {
        fmt.println("Error: Cannot convert empty solid to manifold mesh")
        return nil, false
    }

    num_triangles := len(solid.triangles)

    // Build unique vertex list from triangles
    // ManifoldMesh requires unique vertices with indices
    unique_vertices: [dynamic]m.Vec3
    defer delete(unique_vertices)

    vertex_map := make(map[m.Vec3]u32)  // Map vertex position to index
    defer delete(vertex_map)

    tri_indices := make([dynamic]u32, 0, num_triangles * 3)
    defer delete(tri_indices)

    EPSILON :: 1e-6

    // Process each triangle and build unique vertex list
    for tri in solid.triangles {
        // Process each vertex of the triangle
        tri_verts := [3]m.Vec3{tri.v0, tri.v1, tri.v2}
        for v in tri_verts {
            // Check if vertex already exists (with epsilon comparison)
            found := false
            found_idx: u32

            for existing_v, idx in unique_vertices {
                diff := v - existing_v
                dist := glsl.length(diff)
                if dist < EPSILON {
                    found = true
                    found_idx = u32(idx)
                    break
                }
            }

            if found {
                append(&tri_indices, found_idx)
            } else {
                // Add new vertex
                new_idx := u32(len(unique_vertices))
                append(&unique_vertices, v)
                append(&tri_indices, new_idx)
            }
        }
    }

    fmt.printf("🔄 Converting solid: %d triangles → %d unique vertices\n",
               num_triangles, len(unique_vertices))

    // Pack vertex data as f32 array [x,y,z, x,y,z, ...]
    // Allocate as slice to ensure proper memory layout for C
    vert_props := make([]f32, len(unique_vertices) * 3)
    defer delete(vert_props)

    for v, i in unique_vertices {
        vert_props[i*3 + 0] = f32(v.x)
        vert_props[i*3 + 1] = f32(v.y)
        vert_props[i*3 + 2] = f32(v.z)
    }

    // Convert tri_indices to slice
    tri_indices_slice := tri_indices[:]

    // Quick volume check using signed volume of tetrahedrons
    // This tells us if the mesh winding is inverted
    signed_vol := 0.0
    for i := 0; i < len(tri_indices_slice); i += 3 {
        idx0 := tri_indices_slice[i + 0]
        idx1 := tri_indices_slice[i + 1]
        idx2 := tri_indices_slice[i + 2]

        v0 := unique_vertices[idx0]
        v1 := unique_vertices[idx1]
        v2 := unique_vertices[idx2]

        // Signed volume contribution (dot product of cross and position)
        signed_vol += glsl.dot(v0, glsl.cross(v1, v2))
    }

    // If negative volume, triangles are wound backwards - reverse them
    if signed_vol < 0 {
        fmt.println("🔄 Detected inverted winding, reversing triangle indices...")
        for i := 0; i < len(tri_indices_slice); i += 3 {
            // Swap second and third index to reverse winding
            tri_indices_slice[i + 1], tri_indices_slice[i + 2] = tri_indices_slice[i + 2], tri_indices_slice[i + 1]
        }
        fmt.println("✅ Winding corrected")
    }

    fmt.printf("🔧 Calling ManifoldCAD meshgl: %d verts (%d props), %d tris (%d indices)\n",
               len(unique_vertices), len(vert_props), num_triangles, len(tri_indices_slice))

    // Validate data before passing to C
    if len(unique_vertices) == 0 {
        fmt.println("❌ Error: No vertices to create mesh")
        return nil, false
    }

    if num_triangles == 0 {
        fmt.println("❌ Error: No triangles to create mesh")
        return nil, false
    }

    if len(vert_props) != len(unique_vertices) * 3 {
        fmt.printf("❌ Error: Vertex props size mismatch: got %d, expected %d\n",
                   len(vert_props), len(unique_vertices) * 3)
        return nil, false
    }

    if len(tri_indices_slice) != num_triangles * 3 {
        fmt.printf("❌ Error: Triangle indices size mismatch: got %d, expected %d\n",
                   len(tri_indices_slice), num_triangles * 3)
        return nil, false
    }

    // Print first few vertices for debugging
    fmt.println("📊 First 3 vertices:")
    for i in 0..<min(3, len(unique_vertices)) {
        v := unique_vertices[i]
        fmt.printf("   v[%d] = (%.3f, %.3f, %.3f)\n", i, v.x, v.y, v.z)
    }

    // Print all vertices to check for degeneracy
    fmt.printf("📊 All %d vertices:\n", len(unique_vertices))
    for v, i in unique_vertices {
        fmt.printf("   v[%d] = (%.6f, %.6f, %.6f)\n", i, v.x, v.y, v.z)
    }

    // Print first triangle for debugging
    if num_triangles > 0 {
        fmt.printf("📊 First triangle indices: [%d, %d, %d]\n",
                   tri_indices_slice[0], tri_indices_slice[1], tri_indices_slice[2])
    }

    // Check for degenerate mesh (all vertices on same plane)
    // Calculate bounding box volume
    if len(unique_vertices) > 0 {
        min_v := unique_vertices[0]
        max_v := unique_vertices[0]

        for v in unique_vertices {
            min_v.x = min(min_v.x, v.x)
            min_v.y = min(min_v.y, v.y)
            min_v.z = min(min_v.z, v.z)
            max_v.x = max(max_v.x, v.x)
            max_v.y = max(max_v.y, v.y)
            max_v.z = max(max_v.z, v.z)
        }

        size := max_v - min_v
        volume := size.x * size.y * size.z

        fmt.printf("📊 Bounding box: min=(%.3f, %.3f, %.3f), max=(%.3f, %.3f, %.3f)\n",
                   min_v.x, min_v.y, min_v.z, max_v.x, max_v.y, max_v.z)
        fmt.printf("📊 Size: (%.3f, %.3f, %.3f), volume=%.6f\n",
                   size.x, size.y, size.z, volume)

        if volume < 1e-6 {
            fmt.println("❌ Error: Mesh is degenerate (near-zero volume)!")
            fmt.println("   This mesh does not form a valid 3D solid")
            return nil, false
        }
    }

    // Create ManifoldMesh
    // Use raw_data() to get pointer to the first element
    fmt.println("🔧 Calling C API: manifold_meshgl...")

    // Allocate MeshGL object first (required by ManifoldCAD)
    mem := alloc_meshgl()
    if mem == nil {
        fmt.println("❌ Error: Failed to allocate MeshGL memory")
        return nil, false
    }

    mesh := meshgl(
        mem,  // Use allocated memory instead of nil
        raw_data(vert_props),
        c.size_t(len(unique_vertices)),
        3,  // n_props (x,y,z)
        raw_data(tri_indices_slice),
        c.size_t(num_triangles),
    )

    fmt.println("✅ C API call completed")

    if mesh == nil {
        fmt.println("❌ Error: Failed to create ManifoldMesh (returned nil)")
        delete_meshgl(mem)  // Clean up allocated memory
        return nil, false
    }

    fmt.println("✅ Successfully created ManifoldMesh")
    return mesh, true
}

// =============================================================================
// ManifoldMesh → Triangle3D Array Conversion
// =============================================================================

// Convert ManifoldMesh back to Triangle3D array for SimpleSolid
// Note: This loses face_id information - all triangles will have face_id = -1
manifold_mesh_to_triangles :: proc(mesh: MeshGL) -> [dynamic]extrude.Triangle3D {
    triangles := make([dynamic]extrude.Triangle3D, 0, 64)

    if mesh == nil {
        fmt.println("❌ Error: Cannot convert null ManifoldMesh to triangles")
        return triangles
    }

    // Get mesh data
    num_verts := meshgl_num_vert(mesh)
    num_tris := meshgl_num_tri(mesh)

    fmt.printf("🔄 Converting ManifoldMesh: %d vertices, %d triangles\n", num_verts, num_tris)

    if num_verts == 0 || num_tris == 0 {
        fmt.println("⚠️  Warning: MeshGL has no vertices or triangles")
        return triangles
    }

    // Allocate buffers for vertex properties and triangle indices
    vert_props_len := meshgl_vert_properties_length(mesh)
    tri_len := meshgl_tri_length(mesh)

    fmt.printf("🔧 Allocating buffers: %d vert props, %d tri indices\n", vert_props_len, tri_len)

    vert_props_array := make([]f32, vert_props_len)
    defer delete(vert_props_array)

    tri_indices_array := make([]u32, tri_len)
    defer delete(tri_indices_array)

    // Get vertex properties (copies into our allocated array)
    fmt.println("🔧 Accessing vertex properties...")
    vert_props := meshgl_vert_properties(raw_data(vert_props_array), mesh)
    if vert_props == nil {
        fmt.println("❌ Error: Failed to get vertex properties from ManifoldMesh")
        return triangles
    }
    fmt.println("✅ Vertex properties accessed")

    // Get triangle indices (copies into our allocated array)
    fmt.println("🔧 Accessing triangle indices...")
    tri_verts := meshgl_tri_verts(raw_data(tri_indices_array), mesh)
    if tri_verts == nil {
        fmt.println("❌ Error: Failed to get triangle indices from ManifoldMesh")
        return triangles
    }
    fmt.println("✅ Triangle indices accessed")

    // Build vertex array from interleaved properties
    fmt.println("🔧 Building vertex array...")
    vertices := make([dynamic]m.Vec3, num_verts)
    defer delete(vertices)

    for i in 0..<num_verts {
        idx := i * 3
        vertices[i] = m.Vec3{
            f64(vert_props[idx + 0]),
            f64(vert_props[idx + 1]),
            f64(vert_props[idx + 2]),
        }
    }
    fmt.printf("✅ Built %d vertices\n", len(vertices))

    // Build triangles
    fmt.println("🔧 Building triangles...")
    for i in 0..<num_tris {
        idx := i * 3
        i0 := tri_verts[idx + 0]
        i1 := tri_verts[idx + 1]
        i2 := tri_verts[idx + 2]

        if i0 >= u32(num_verts) || i1 >= u32(num_verts) || i2 >= u32(num_verts) {
            fmt.printf("⚠️  Warning: Triangle %d has out-of-bounds vertex index [%d, %d, %d]\n",
                       i, i0, i1, i2)
            continue
        }

        v0 := vertices[i0]
        v1 := vertices[i1]
        v2 := vertices[i2]

        // Calculate triangle normal
        edge1 := v1 - v0
        edge2 := v2 - v0
        normal := glsl.normalize(glsl.cross(edge1, edge2))

        tri := extrude.Triangle3D{
            v0 = v0,
            v1 = v1,
            v2 = v2,
            normal = normal,
            face_id = -1,  // Face ID is lost in conversion
        }

        append(&triangles, tri)
    }

    fmt.printf("✅ Converted %d triangles from ManifoldMesh\n", len(triangles))

    return triangles
}

// =============================================================================
// Boolean Operations on SimpleSolids
// =============================================================================

// Perform boolean difference: base_solid - cut_solid
// Returns new triangle array for the result
boolean_subtract_solids :: proc(
    base_solid: ^extrude.SimpleSolid,
    cut_solid: ^extrude.SimpleSolid,
) -> (result_triangles: [dynamic]extrude.Triangle3D, success: bool) {

    fmt.println("\n🔧 Starting ManifoldCAD boolean subtraction...")

    // Convert base solid to ManifoldMesh
    base_mesh, base_ok := solid_to_manifold_mesh(base_solid)
    if !base_ok {
        fmt.println("❌ Failed to convert base solid to ManifoldMesh")
        return make([dynamic]extrude.Triangle3D), false
    }
    defer destruct_meshgl(base_mesh)

    // Convert cut solid to ManifoldMesh
    cut_mesh, cut_ok := solid_to_manifold_mesh(cut_solid)
    if !cut_ok {
        fmt.println("❌ Failed to convert cut solid to ManifoldMesh")
        return make([dynamic]extrude.Triangle3D), false
    }
    defer destruct_meshgl(cut_mesh)

    // Create Manifold objects from meshes
    fmt.println("🔧 Creating base Manifold from MeshGL...")
    base_mem := alloc_manifold()
    if base_mem == nil {
        fmt.println("❌ Failed to allocate base Manifold memory")
        return make([dynamic]extrude.Triangle3D), false
    }

    base_manifold := of_meshgl(base_mem, base_mesh)
    if base_manifold == nil {
        fmt.println("❌ Failed to create base Manifold")
        delete_manifold(base_mem)
        return make([dynamic]extrude.Triangle3D), false
    }
    defer destruct_manifold(base_manifold)

    fmt.println("🔧 Creating cut Manifold from MeshGL...")
    cut_mem := alloc_manifold()
    if cut_mem == nil {
        fmt.println("❌ Failed to allocate cut Manifold memory")
        return make([dynamic]extrude.Triangle3D), false
    }

    cut_manifold := of_meshgl(cut_mem, cut_mesh)
    if cut_manifold == nil {
        fmt.println("❌ Failed to create cut Manifold")
        delete_manifold(cut_mem)
        return make([dynamic]extrude.Triangle3D), false
    }
    defer destruct_manifold(cut_manifold)

    // Check if manifolds are valid
    base_status := status(base_manifold)
    if base_status != .NoError {
        fmt.printf("❌ Base manifold error: %s\n", error_string(base_status))
        return make([dynamic]extrude.Triangle3D), false
    }

    cut_status := status(cut_manifold)
    if cut_status != .NoError {
        fmt.printf("❌ Cut manifold error: %s\n", error_string(cut_status))
        return make([dynamic]extrude.Triangle3D), false
    }

    base_vol := volume(base_manifold)
    cut_vol := volume(cut_manifold)

    fmt.printf("✅ Base manifold: %d verts, %d tris, volume=%.3f\n",
               num_vert(base_manifold), num_tri(base_manifold), base_vol)
    fmt.printf("✅ Cut manifold: %d verts, %d tris, volume=%.3f\n",
               num_vert(cut_manifold), num_tri(cut_manifold), cut_vol)

    // Check for inverted meshes (negative volume = inside-out)
    if base_vol < 0 {
        fmt.printf("⚠️  WARNING: Base manifold has NEGATIVE volume (%.3f)\n", base_vol)
        fmt.println("   This means the mesh has inverted winding (inside-out)")
        fmt.println("   ManifoldCAD cannot perform boolean operations on inverted meshes")
        fmt.println("   The triangles need to be wound counter-clockwise when viewed from outside")
        return make([dynamic]extrude.Triangle3D), false
    }

    if cut_vol < 0 {
        fmt.printf("⚠️  WARNING: Cut manifold has NEGATIVE volume (%.3f)\n", cut_vol)
        fmt.println("   This means the mesh has inverted winding (inside-out)")
        return make([dynamic]extrude.Triangle3D), false
    }

    // Perform boolean difference operation
    fmt.println("🔧 Performing boolean difference (base - cut)...")

    // Allocate memory for result manifold
    result_mem := alloc_manifold()
    if result_mem == nil {
        fmt.println("❌ Failed to allocate result Manifold memory")
        return make([dynamic]extrude.Triangle3D), false
    }

    result_manifold := difference(result_mem, base_manifold, cut_manifold)
    if result_manifold == nil {
        fmt.println("❌ Boolean difference operation failed (returned nil)")
        delete_manifold(result_mem)
        return make([dynamic]extrude.Triangle3D), false
    }
    defer destruct_manifold(result_manifold)

    // Check result status
    result_status := status(result_manifold)
    if result_status != .NoError {
        fmt.printf("❌ Result manifold error: %s\n", error_string(result_status))
        return make([dynamic]extrude.Triangle3D), false
    }

    fmt.printf("✅ Result manifold: %d verts, %d tris, volume=%.3f\n",
               num_vert(result_manifold), num_tri(result_manifold),
               volume(result_manifold))

    // Extract result mesh
    fmt.println("🔧 Extracting result mesh from Manifold...")
    result_mesh_mem := alloc_meshgl()
    if result_mesh_mem == nil {
        fmt.println("❌ Failed to allocate result MeshGL memory")
        return make([dynamic]extrude.Triangle3D), false
    }

    result_mesh := get_meshgl(result_mesh_mem, result_manifold)
    if result_mesh == nil {
        fmt.println("❌ Failed to extract result mesh")
        delete_meshgl(result_mesh_mem)
        return make([dynamic]extrude.Triangle3D), false
    }
    defer destruct_meshgl(result_mesh)

    fmt.println("✅ Result mesh extracted")

    // Convert result mesh back to triangles
    result_triangles = manifold_mesh_to_triangles(result_mesh)

    if len(result_triangles) == 0 {
        fmt.println("⚠️  Warning: Boolean operation produced empty result")
        return result_triangles, false
    }

    fmt.printf("✅ Boolean subtraction complete: %d triangles\n", len(result_triangles))

    return result_triangles, true
}
