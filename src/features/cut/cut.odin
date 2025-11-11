// features/cut - Cut/Pocket Feature (Boolean Subtract)
// Takes a closed 2D sketch profile and removes material from an existing solid
package ohcad_cut

import "core:fmt"
import "core:slice"
import "core:math"
import sketch "../../features/sketch"
import extrude "../../features/extrude"
import m "../../core/math"
import glsl "core:math/linalg/glsl"

// Cut direction
CutDirection :: enum {
    Forward,    // Cut in +normal direction
    Backward,   // Cut in -normal direction
    Symmetric,  // Cut equally in both directions
}

// Cut parameters
CutParams :: struct {
    depth:       f64,            // Cut depth/distance
    direction:   CutDirection,   // Cut direction
    base_solid:  ^extrude.SimpleSolid,  // Solid to cut from
}

// Cut result
CutResult :: struct {
    solid:   ^extrude.SimpleSolid,  // Resulting 3D solid after cut
    success: bool,                   // Operation success flag
    message: string,                 // Error/status message
}

// =============================================================================
// Cut Operation
// =============================================================================

// Cut a sketch profile from an existing solid (boolean subtract)
cut_sketch :: proc(sk: ^sketch.Sketch2D, params: CutParams) -> CutResult {
    result: CutResult

    // Validate parameters
    if params.depth <= 0 {
        result.message = "Cut depth must be positive"
        return result
    }

    if params.base_solid == nil {
        result.message = "No base solid provided to cut from"
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

    fmt.printf("Cutting with closed profile with %d entities, %d points\n",
        len(closed_profile.entities), len(closed_profile.points))

    // Perform boolean subtract
    solid := boolean_subtract(sk, closed_profile, params)

    if solid == nil {
        result.message = "Failed to perform boolean subtract"
        return result
    }

    result.solid = solid
    result.success = true
    result.message = "Cut successful"

    return result
}

// =============================================================================
// Boolean Subtract Implementation (Wireframe-based)
// =============================================================================

// Boolean subtract - removes cut volume from base solid
// Strategy: For wireframe solids, we need to:
// 1. Create cut volume (extrude the cut profile)
// 2. Find intersections between base solid edges and cut volume faces
// 3. Remove/trim edges that are inside the cut volume
// 4. Add new edges at the intersection boundaries
//
// Simplified approach for MVP:
// - Generate cut volume wireframe
// - Clip base solid edges against cut volume
// - Add cut volume boundary edges to result
boolean_subtract :: proc(
    sk: ^sketch.Sketch2D,
    profile: sketch.Profile,
    params: CutParams,
) -> ^extrude.SimpleSolid {

    // Step 1: Create the cut volume (similar to extrude)
    cut_volume := create_cut_volume(sk, profile, params)
    if cut_volume == nil {
        fmt.println("Error: Failed to create cut volume")
        return nil
    }
    defer {
        // Clean up cut volume after we're done
        for v in cut_volume.vertices {
            free(v)
        }
        delete(cut_volume.vertices)
        for e in cut_volume.edges {
            free(e)
        }
        delete(cut_volume.edges)
        free(cut_volume)
    }

    // Step 2: Create result solid (copy base solid)
    result := copy_solid(params.base_solid)
    if result == nil {
        fmt.println("Error: Failed to copy base solid")
        return nil
    }

    // Step 3: Compute bounding box of cut volume
    cut_bbox := compute_bounding_box(cut_volume)

    // Step 4: Remove edges from base solid that intersect cut volume
    // For simplicity in MVP, we'll use a geometric approach:
    // - Check if edge endpoints are inside cut volume
    // - Remove edges that are fully inside
    // - Trim edges that partially intersect (simplified to removal for MVP)

    edges_to_remove := make([dynamic]int)
    defer delete(edges_to_remove)

    for i in 0..<len(result.edges) {
        edge := result.edges[i]

        // Check if both vertices are inside cut volume bounding box
        v0_inside := point_in_bbox(edge.v0.position, cut_bbox)
        v1_inside := point_in_bbox(edge.v1.position, cut_bbox)

        // If both endpoints are inside the cut region, mark for removal
        if v0_inside && v1_inside {
            // Additional check: is edge center inside cut volume?
            edge_center := (edge.v0.position + edge.v1.position) * 0.5
            if point_inside_cut_volume(edge_center, sk, profile, params) {
                append(&edges_to_remove, i)
            }
        }
    }

    // Remove edges in reverse order to maintain indices
    #reverse for idx in edges_to_remove {
        free(result.edges[idx])
        ordered_remove(&result.edges, idx)
    }

    // Step 5: Add cut volume boundary edges to show the cut
    // Add the top surface edges of the cut (where material was removed)
    add_cut_boundary_edges(result, cut_volume, params)

    fmt.printf("✅ Cut operation complete: removed %d edges, result has %d vertices, %d edges\n",
        len(edges_to_remove), len(result.vertices), len(result.edges))

    return result
}

// Create the cut volume solid (extruded profile to be subtracted)
create_cut_volume :: proc(
    sk: ^sketch.Sketch2D,
    profile: sketch.Profile,
    params: CutParams,
) -> ^extrude.SimpleSolid {

    // Use extrude logic to create cut volume
    extrude_params := extrude.ExtrudeParams{
        depth = params.depth,
        direction = cast(extrude.ExtrudeDirection)params.direction,
    }

    // Get profile points in order
    profile_points := get_profile_points_ordered(sk, profile)
    defer delete(profile_points)

    if len(profile_points) < 3 {
        fmt.println("Error: Profile must have at least 3 points")
        return nil
    }

    // Calculate cut offset
    cut_offset := calculate_cut_offset(&sk.plane, params)

    // Create solid
    solid := new(extrude.SimpleSolid)
    solid.vertices = make([dynamic]^extrude.Vertex, 0, len(profile_points) * 2)
    solid.edges = make([dynamic]^extrude.Edge, 0, len(profile_points) * 3)

    // Create bottom vertices (on sketch plane)
    bottom_vertices := make([dynamic]^extrude.Vertex, 0, len(profile_points))
    defer delete(bottom_vertices)

    for point_2d in profile_points {
        point_3d := sketch.sketch_to_world(&sk.plane, point_2d)
        vertex := new(extrude.Vertex)
        vertex.position = point_3d
        append(&solid.vertices, vertex)
        append(&bottom_vertices, vertex)
    }

    // Create top vertices (offset by cut vector)
    top_vertices := make([dynamic]^extrude.Vertex, 0, len(profile_points))
    defer delete(top_vertices)

    for point_2d in profile_points {
        point_3d := sketch.sketch_to_world(&sk.plane, point_2d)
        cut_point := point_3d + cut_offset
        vertex := new(extrude.Vertex)
        vertex.position = cut_point
        append(&solid.vertices, vertex)
        append(&top_vertices, vertex)
    }

    // Create edges (similar to extrude)
    for i in 0..<len(bottom_vertices) {
        next_i := (i + 1) % len(bottom_vertices)

        // Bottom loop
        edge := new(extrude.Edge)
        edge.v0 = bottom_vertices[i]
        edge.v1 = bottom_vertices[next_i]
        append(&solid.edges, edge)

        // Top loop
        edge_top := new(extrude.Edge)
        edge_top.v0 = top_vertices[i]
        edge_top.v1 = top_vertices[next_i]
        append(&solid.edges, edge_top)

        // Vertical edge
        edge_vert := new(extrude.Edge)
        edge_vert.v0 = bottom_vertices[i]
        edge_vert.v1 = top_vertices[i]
        append(&solid.edges, edge_vert)
    }

    return solid
}

// Calculate cut offset vector
calculate_cut_offset :: proc(plane: ^sketch.SketchPlane, params: CutParams) -> m.Vec3 {
    depth := params.depth

    // Adjust depth based on direction
    switch params.direction {
    case .Forward:
        // Use normal direction as-is
    case .Backward:
        depth = -depth
    case .Symmetric:
        depth = depth / 2.0
    }

    // Cut vector is normal * depth
    offset := plane.normal * depth

    return offset
}

// Get profile points in order
get_profile_points_ordered :: proc(sk: ^sketch.Sketch2D, profile: sketch.Profile) -> [dynamic]m.Vec2 {
    points := make([dynamic]m.Vec2, 0, len(profile.points))

    for point_id in profile.points {
        if point_id >= 0 && point_id < len(sk.points) {
            point := sk.points[point_id]
            append(&points, m.Vec2{point.x, point.y})
        }
    }

    return points
}

// =============================================================================
// Geometric Helpers
// =============================================================================

// Bounding box
BoundingBox :: struct {
    min: m.Vec3,
    max: m.Vec3,
}

// Compute bounding box of a solid
compute_bounding_box :: proc(solid: ^extrude.SimpleSolid) -> BoundingBox {
    if len(solid.vertices) == 0 {
        return BoundingBox{}
    }

    bbox := BoundingBox{
        min = solid.vertices[0].position,
        max = solid.vertices[0].position,
    }

    for vertex in solid.vertices {
        bbox.min.x = math.min(bbox.min.x, vertex.position.x)
        bbox.min.y = math.min(bbox.min.y, vertex.position.y)
        bbox.min.z = math.min(bbox.min.z, vertex.position.z)

        bbox.max.x = math.max(bbox.max.x, vertex.position.x)
        bbox.max.y = math.max(bbox.max.y, vertex.position.y)
        bbox.max.z = math.max(bbox.max.z, vertex.position.z)
    }

    return bbox
}

// Check if point is inside bounding box
point_in_bbox :: proc(point: m.Vec3, bbox: BoundingBox) -> bool {
    eps :: 0.001  // Small tolerance

    return point.x >= (bbox.min.x - eps) && point.x <= (bbox.max.x + eps) &&
           point.y >= (bbox.min.y - eps) && point.y <= (bbox.max.y + eps) &&
           point.z >= (bbox.min.z - eps) && point.z <= (bbox.max.z + eps)
}

// Check if point is inside cut volume
// Simplified: project point to sketch plane and check if inside 2D profile
point_inside_cut_volume :: proc(
    point: m.Vec3,
    sk: ^sketch.Sketch2D,
    profile: sketch.Profile,
    params: CutParams,
) -> bool {

    // Project point to sketch plane
    point_2d := sketch.world_to_sketch(&sk.plane, point)

    // Check if point is inside 2D profile using ray casting
    return point_inside_polygon_2d(point_2d, sk, profile)
}

// Ray casting algorithm to check if point is inside 2D polygon
point_inside_polygon_2d :: proc(
    point: m.Vec2,
    sk: ^sketch.Sketch2D,
    profile: sketch.Profile,
) -> bool {

    // Get profile points
    profile_points := get_profile_points_ordered(sk, profile)
    defer delete(profile_points)

    if len(profile_points) < 3 {
        return false
    }

    // Ray casting: count intersections with horizontal ray from point
    inside := false
    n := len(profile_points)

    for i in 0..<n {
        j := (i + 1) % n

        p1 := profile_points[i]
        p2 := profile_points[j]

        // Check if horizontal ray intersects edge
        if ((p1.y > point.y) != (p2.y > point.y)) &&
           (point.x < (p2.x - p1.x) * (point.y - p1.y) / (p2.y - p1.y) + p1.x) {
            inside = !inside
        }
    }

    return inside
}

// Copy a solid (deep copy)
copy_solid :: proc(solid: ^extrude.SimpleSolid) -> ^extrude.SimpleSolid {
    result := new(extrude.SimpleSolid)
    result.vertices = make([dynamic]^extrude.Vertex, 0, len(solid.vertices))
    result.edges = make([dynamic]^extrude.Edge, 0, len(solid.edges))

    // Copy vertices and create mapping
    vertex_map := make(map[rawptr]^extrude.Vertex)
    defer delete(vertex_map)

    for old_vertex in solid.vertices {
        new_vertex := new(extrude.Vertex)
        new_vertex.position = old_vertex.position
        append(&result.vertices, new_vertex)
        vertex_map[old_vertex] = new_vertex
    }

    // Copy edges with updated vertex references
    for old_edge in solid.edges {
        new_edge := new(extrude.Edge)
        new_edge.v0 = vertex_map[old_edge.v0]
        new_edge.v1 = vertex_map[old_edge.v1]
        append(&result.edges, new_edge)
    }

    return result
}

// Add cut boundary edges to result solid
add_cut_boundary_edges :: proc(
    result: ^extrude.SimpleSolid,
    cut_volume: ^extrude.SimpleSolid,
    params: CutParams,
) {

    // For MVP: Add the bottom loop of the cut volume (where it intersects the base)
    // In a full implementation, this would compute actual intersection curves

    // Count vertices at the bottom of cut volume
    n := len(cut_volume.vertices) / 2

    // Add bottom vertices of cut volume to result
    vertex_map := make(map[rawptr]^extrude.Vertex)
    defer delete(vertex_map)

    for i in 0..<n {
        old_vertex := cut_volume.vertices[i]
        new_vertex := new(extrude.Vertex)
        new_vertex.position = old_vertex.position
        append(&result.vertices, new_vertex)
        vertex_map[old_vertex] = new_vertex
    }

    // Add bottom edges of cut volume
    for i in 0..<n {
        next_i := (i + 1) % n

        v0 := cut_volume.vertices[i]
        v1 := cut_volume.vertices[next_i]

        new_edge := new(extrude.Edge)
        new_edge.v0 = vertex_map[v0]
        new_edge.v1 = vertex_map[v1]
        append(&result.edges, new_edge)
    }
}

// =============================================================================
// Cut Helpers
// =============================================================================

// Print cut result
cut_result_print :: proc(result: CutResult) {
    fmt.printf("\n=== Cut Result ===\n")
    fmt.printf("Success: %v\n", result.success)
    fmt.printf("Message: %s\n", result.message)

    if result.solid != nil {
        fmt.printf("Solid Info:\n")
        fmt.printf("  Vertices: %d\n", len(result.solid.vertices))
        fmt.printf("  Edges: %d\n", len(result.solid.edges))
    }
}

// Destroy cut result (cleanup)
cut_result_destroy :: proc(result: ^CutResult) {
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
