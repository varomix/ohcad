// OCCT Extrude Integration
// Provides extrusion using OCCT for robust B-Rep modeling
package occt

import "core:fmt"
import "core:c"
import m "../../../core/math"

// =============================================================================
// Extrude Result - Both exact geometry and mesh
// =============================================================================

ExtrudeResult :: struct {
    shape: Shape,    // Exact B-Rep geometry (caller owns, must delete)
    mesh: ^Mesh,     // Tessellated mesh (caller owns, must delete)
}

// =============================================================================
// Profile → OCCT Shape + Mesh Extrusion
// =============================================================================

// Extrude a 2D profile and return both OCCT shape and tessellated mesh
// Caller is responsible for deleting both shape and mesh
extrude_profile_2d :: proc(
    profile_points: []m.Vec2,     // 2D profile points in order
    extrude_vector: m.Vec3,       // Extrusion direction and distance
) -> ExtrudeResult {

    result: ExtrudeResult

    if len(profile_points) < 3 {
        fmt.println("❌ OCCT Extrude: Profile must have at least 3 points")
        return result
    }

    fmt.printf("🔧 OCCT Extrude: Extruding %d-sided profile...\n", len(profile_points))

    // Step 1: Convert 2D profile points to OCCT format (array of f64 x,y pairs)
    occt_points := make([]f64, len(profile_points) * 2)
    defer delete(occt_points)

    for point, i in profile_points {
        occt_points[i*2 + 0] = f64(point.x)
        occt_points[i*2 + 1] = f64(point.y)
    }

    // Step 2: Create OCCT wire from 2D points
    wire := OCCT_Wire_FromPoints2D(
        raw_data(occt_points),
        c.int(len(profile_points)),
        true,  // closed loop
    )

    if wire == nil {
        fmt.println("❌ OCCT Extrude: Failed to create wire from profile")
        return result
    }
    defer OCCT_Wire_Delete(wire)

    fmt.println("✅ OCCT: Created wire from profile")

    // Step 3: Extrude wire to create solid
    solid_shape := OCCT_Extrude_Wire(
        wire,
        extrude_vector.x,
        extrude_vector.y,
        extrude_vector.z,
    )

    if solid_shape == nil {
        fmt.println("❌ OCCT Extrude: Failed to extrude wire")
        return result
    }
    // NOTE: Don't defer delete - we're returning this shape to caller

    // Validate solid
    if !is_valid(solid_shape) {
        fmt.println("❌ OCCT Extrude: Resulting shape is invalid")
        delete_shape(solid_shape)  // Clean up on error
        return result
    }

    shape_type := get_type(solid_shape)
    fmt.printf("✅ OCCT: Extruded to shape (type: %v)\n", shape_type)

    // Step 4: Tessellate to triangle mesh
    mesh := OCCT_Tessellate(solid_shape, DEFAULT_TESSELLATION)

    if mesh == nil {
        fmt.println("❌ OCCT Extrude: Failed to tessellate solid")
        delete_shape(solid_shape)  // Clean up on error
        return result
    }

    fmt.printf("✅ OCCT: Tessellated to %d vertices, %d triangles\n",
        mesh.num_vertices, mesh.num_triangles)

    // Return both exact geometry and tessellated mesh
    result.shape = solid_shape
    result.mesh = mesh

    return result
}
