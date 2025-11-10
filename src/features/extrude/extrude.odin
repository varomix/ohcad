// features/extrude - Extrude Feature (Sketch → 3D Solid)
// Takes a closed 2D sketch profile and extrudes it along the sketch plane normal
package ohcad_extrude

import "core:fmt"
import "core:slice"
import sketch "../../features/sketch"
import topo "../../core/topology"
import m "../../core/math"
import glsl "core:math/linalg/glsl"

// Extrude direction
ExtrudeDirection :: enum {
    Forward,    // Extrude in +normal direction
    Backward,   // Extrude in -normal direction
    Symmetric,  // Extrude equally in both directions
}

// Extrude parameters
ExtrudeParams :: struct {
    depth:     f64,              // Extrude depth/distance
    direction: ExtrudeDirection,  // Extrusion direction
}

// Extrude result
ExtrudeResult :: struct {
    solid:   ^SimpleSolid,  // Resulting 3D solid (simplified wireframe)
    success: bool,           // Operation success flag
    message: string,         // Error/status message
}

// =============================================================================
// Extrude Operation
// =============================================================================

// Simple solid structure (wireframe only for now)
SimpleSolid :: struct {
    vertices: [dynamic]^Vertex,
    edges: [dynamic]^Edge,
}

// Simple vertex (world space)
Vertex :: struct {
    position: m.Vec3,
}

// Simple edge (connects two vertices)
Edge :: struct {
    v0, v1: ^Vertex,
}

// Extrude a sketch profile to create a 3D solid
extrude_sketch :: proc(sk: ^sketch.Sketch2D, params: ExtrudeParams) -> ExtrudeResult {
    result: ExtrudeResult

    // Validate parameters
    if params.depth <= 0 {
        result.message = "Extrude depth must be positive"
        return result
    }

    // Detect profiles
    profiles := sketch.sketch_detect_profiles(sk)
    defer {
        for &profile in profiles {
            sketch.profile_destroy(&profile)
        }
        delete(profiles)
    }

    // Find first closed profile
    closed_profile: sketch.Profile
    has_closed := false

    for profile in profiles {
        if profile.type == .Closed {
            closed_profile = profile
            has_closed = true
            break
        }
    }

    if !has_closed {
        result.message = "No closed profile found - sketch must form a closed loop"
        return result
    }

    fmt.printf("Extruding closed profile with %d entities, %d points\n",
        len(closed_profile.entities), len(closed_profile.points))

    // Create solid from profile
    solid := extrude_profile(sk, closed_profile, params)

    if solid == nil {
        result.message = "Failed to create solid from profile"
        return result
    }

    result.solid = solid
    result.success = true
    result.message = "Extrude successful"

    return result
}

// Extrude a single closed profile
extrude_profile :: proc(
    sk: ^sketch.Sketch2D,
    profile: sketch.Profile,
    params: ExtrudeParams,
) -> ^SimpleSolid {

    // Calculate extrusion vector
    extrude_offset := calculate_extrude_offset(&sk.plane, params)

    // Get profile points in order
    profile_points := get_profile_points_ordered(sk, profile)
    defer delete(profile_points)

    if len(profile_points) < 3 {
        fmt.println("Error: Profile must have at least 3 points")
        return nil
    }

    // Create solid
    solid := new(SimpleSolid)
    solid.vertices = make([dynamic]^Vertex, 0, len(profile_points) * 2)
    solid.edges = make([dynamic]^Edge, 0, len(profile_points) * 3)

    // Create bottom vertices (on sketch plane)
    bottom_vertices := make([dynamic]^Vertex, 0, len(profile_points))
    defer delete(bottom_vertices)

    for point_2d in profile_points {
        point_3d := sketch.sketch_to_world(&sk.plane, point_2d)
        vertex := new(Vertex)
        vertex.position = point_3d
        append(&solid.vertices, vertex)
        append(&bottom_vertices, vertex)
    }

    // Create top vertices (offset by extrude vector)
    top_vertices := make([dynamic]^Vertex, 0, len(profile_points))
    defer delete(top_vertices)

    for point_2d in profile_points {
        point_3d := sketch.sketch_to_world(&sk.plane, point_2d)
        extruded_point := point_3d + extrude_offset
        vertex := new(Vertex)
        vertex.position = extruded_point
        append(&solid.vertices, vertex)
        append(&top_vertices, vertex)
    }

    // Create bottom edges (connecting bottom vertices in a loop)
    for i in 0..<len(bottom_vertices) {
        next_i := (i + 1) % len(bottom_vertices)
        edge := new(Edge)
        edge.v0 = bottom_vertices[i]
        edge.v1 = bottom_vertices[next_i]
        append(&solid.edges, edge)
    }

    // Create top edges (connecting top vertices in a loop)
    for i in 0..<len(top_vertices) {
        next_i := (i + 1) % len(top_vertices)
        edge := new(Edge)
        edge.v0 = top_vertices[i]
        edge.v1 = top_vertices[next_i]
        append(&solid.edges, edge)
    }

    // Create vertical edges (connecting bottom to top)
    for i in 0..<len(bottom_vertices) {
        edge := new(Edge)
        edge.v0 = bottom_vertices[i]
        edge.v1 = top_vertices[i]
        append(&solid.edges, edge)
    }

    fmt.printf("✅ Created extruded solid: %d vertices, %d edges\n",
        len(solid.vertices), len(solid.edges))

    return solid
}

// Calculate extrusion offset vector
calculate_extrude_offset :: proc(plane: ^sketch.SketchPlane, params: ExtrudeParams) -> m.Vec3 {
    depth := params.depth

    // Adjust depth based on direction
    switch params.direction {
    case .Forward:
        // Use normal direction as-is
    case .Backward:
        depth = -depth
    case .Symmetric:
        // For symmetric, we'd extrude half in each direction
        // For now, just use forward
        depth = depth / 2.0
    }

    // Extrusion vector is normal * depth
    offset := plane.normal * depth

    return offset
}

// Get profile points in order (following the loop)
get_profile_points_ordered :: proc(sk: ^sketch.Sketch2D, profile: sketch.Profile) -> [dynamic]m.Vec2 {
    points := make([dynamic]m.Vec2, 0, len(profile.points))

    // Profile.points already contains the ordered point IDs
    // We just need to look up their coordinates
    for point_id in profile.points {
        if point_id >= 0 && point_id < len(sk.points) {
            point := sk.points[point_id]
            append(&points, m.Vec2{point.x, point.y})
        }
    }

    return points
}

// =============================================================================
// Extrude Helpers
// =============================================================================

// Print extrude result
extrude_result_print :: proc(result: ExtrudeResult) {
    fmt.printf("\n=== Extrude Result ===\n")
    fmt.printf("Success: %v\n", result.success)
    fmt.printf("Message: %s\n", result.message)

    if result.solid != nil {
        fmt.printf("Solid Info:\n")
        fmt.printf("  Vertices: %d\n", len(result.solid.vertices))
        fmt.printf("  Edges: %d\n", len(result.solid.edges))
    }
}

// Destroy extrude result (cleanup)
extrude_result_destroy :: proc(result: ^ExtrudeResult) {
    if result.solid != nil {
        // Free all vertices
        for vertex in result.solid.vertices {
            free(vertex)
        }
        delete(result.solid.vertices)

        // Free all edges
        for edge in result.solid.edges {
            free(edge)
        }
        delete(result.solid.edges)

        // Free solid itself
        free(result.solid)
        result.solid = nil
    }
}
