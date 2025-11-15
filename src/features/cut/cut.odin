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
import manifold "../../core/geometry/manifold"

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
// Boolean Subtract Implementation (ManifoldCAD-based)
// =============================================================================

// Boolean subtract - removes cut volume from base solid using ManifoldCAD
// NEW APPROACH:
// 1. Create cut volume (extrude the cut profile)
// 2. Use ManifoldCAD to perform proper boolean difference: base - cut
// 3. Convert result back to SimpleSolid format
boolean_subtract :: proc(
    sk: ^sketch.Sketch2D,
    profile: sketch.Profile,
    params: CutParams,
) -> ^extrude.SimpleSolid {

    fmt.println("\n🔧 Starting boolean subtract with ManifoldCAD...")

    // Step 1: Create the cut volume (similar to extrude)
    cut_volume := create_cut_volume(sk, profile, params)
    if cut_volume == nil {
        fmt.println("❌ Error: Failed to create cut volume")
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
        delete(cut_volume.faces)
        delete(cut_volume.triangles)
        free(cut_volume)
    }

    // Ensure cut volume has triangles
    if len(cut_volume.triangles) == 0 {
        fmt.println("🔧 Generating triangles for cut volume...")
        cut_volume.triangles = extrude.generate_face_triangles(cut_volume)
    }

    fmt.printf("✅ Cut volume created: %d vertices, %d triangles\n",
               len(cut_volume.vertices), len(cut_volume.triangles))

    // Step 2: Perform ManifoldCAD boolean subtraction
    result_triangles, success := manifold.boolean_subtract_solids(params.base_solid, cut_volume)
    if !success {
        fmt.println("❌ ManifoldCAD boolean subtraction failed")
        return nil
    }

    // Step 3: Create result solid with new triangles
    // We need to generate vertices and edges from the ManifoldCAD triangle mesh
    result := build_solid_from_triangles(result_triangles)
    if result == nil {
        fmt.println("❌ Error: Failed to build solid from triangles")
        delete(result_triangles)
        return nil
    }

    fmt.printf("✅ Boolean subtraction complete: %d vertices, %d edges, %d triangles\n",
                len(result.vertices), len(result.edges), len(result.triangles))

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

    // Create faces for the cut volume (needed for triangle generation)
    solid.faces = make([dynamic]extrude.SimpleFace, 0, 2 + len(profile_points))

    // Bottom face (on sketch plane)
    bottom_face := create_cut_bottom_face(bottom_vertices[:], sk.plane.normal)
    append(&solid.faces, bottom_face)

    // Top face (offset from sketch plane)
    top_face := create_cut_top_face(top_vertices[:], sk.plane.normal, cut_offset)
    append(&solid.faces, top_face)

    // Side faces
    for i in 0..<len(bottom_vertices) {
        next_i := (i + 1) % len(bottom_vertices)
        side_face := create_cut_side_face(
            bottom_vertices[i], bottom_vertices[next_i],
            top_vertices[i], top_vertices[next_i],
            i,
        )
        append(&solid.faces, side_face)
    }

    return solid
}

// Create bottom face for cut volume
create_cut_bottom_face :: proc(vertices: []^extrude.Vertex, sketch_normal: m.Vec3) -> extrude.SimpleFace {
    face: extrude.SimpleFace
    face.vertices = make([dynamic]^extrude.Vertex, len(vertices))

    // Reverse vertices for correct winding
    for i in 0..<len(vertices) {
        face.vertices[len(vertices) - 1 - i] = vertices[i]
    }

    face.normal = -sketch_normal
    face.center = calculate_face_center_from_vertices(face.vertices[:])
    face.name = "CutBottom"

    return face
}

// Create top face for cut volume
create_cut_top_face :: proc(vertices: []^extrude.Vertex, sketch_normal: m.Vec3, offset: m.Vec3) -> extrude.SimpleFace {
    face: extrude.SimpleFace
    face.vertices = make([dynamic]^extrude.Vertex, len(vertices))

    for i in 0..<len(vertices) {
        face.vertices[i] = vertices[i]
    }

    face.normal = sketch_normal
    face.center = calculate_face_center_from_vertices(face.vertices[:])
    face.name = "CutTop"

    return face
}

// Create side face for cut volume
create_cut_side_face :: proc(
    bottom_v0, bottom_v1: ^extrude.Vertex,
    top_v0, top_v1: ^extrude.Vertex,
    index: int,
) -> extrude.SimpleFace {
    face: extrude.SimpleFace
    face.vertices = make([dynamic]^extrude.Vertex, 4)

    face.vertices[0] = bottom_v0
    face.vertices[1] = bottom_v1
    face.vertices[2] = top_v1
    face.vertices[3] = top_v0

    edge1 := bottom_v1.position - bottom_v0.position
    edge2 := top_v0.position - bottom_v0.position
    calculated_cross := glsl.cross(edge2, edge1)
    face.normal = -glsl.normalize(calculated_cross)

    face.center = calculate_face_center_from_vertices(face.vertices[:])
    face.name = fmt.aprintf("CutSide%d", index)

    return face
}

// Calculate center of a face from vertex pointers
calculate_face_center_from_vertices :: proc(vertices: []^extrude.Vertex) -> m.Vec3 {
    if len(vertices) == 0 {
        return m.Vec3{0, 0, 0}
    }

    sum := m.Vec3{0, 0, 0}
    for vertex in vertices {
        sum += vertex.position
    }

    return sum / f64(len(vertices))
}

// Calculate cut offset vector
calculate_cut_offset :: proc(plane: ^sketch.SketchPlane, params: CutParams) -> m.Vec3 {
    depth := params.depth

    // For cuts/pockets, we want to remove material by going AGAINST the normal
    // (the opposite of extrude which goes WITH the normal)
    // So for Forward cut: offset = -normal * depth (dig into the solid)
    switch params.direction {
    case .Forward:
        // Cut AGAINST normal direction (into the solid)
        depth = -depth
    case .Backward:
        // Cut WITH normal direction (away from solid)
        // Use depth as-is
    case .Symmetric:
        // Cut equally in both directions
        depth = depth / 2.0
    }

    // Cut vector is normal * depth (depth is already negated for Forward)
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

    // Project point to sketch plane to get 2D coordinates
    point_2d := sketch.world_to_sketch(&sk.plane, point)

    // Check if point is inside 2D profile using ray casting
    if !point_inside_polygon_2d(point_2d, sk, profile) {
        return false
    }

    // Also check depth: point must be within the cut depth range
    // Calculate distance from point to sketch plane
    plane_to_point := point - sk.plane.origin
    distance_along_normal := glsl.dot(plane_to_point, sk.plane.normal)

    // For Forward cut: check if point is between 0 and depth (going INTO the solid)
    // The cut should remove material BELOW the sketch plane (negative normal direction)
    switch params.direction {
    case .Forward:
        // Cut goes in negative normal direction (into the solid)
        // Point is inside if it's between 0 and -depth
        return distance_along_normal <= 0.001 && distance_along_normal >= -params.depth

    case .Backward:
        // Cut goes in positive normal direction
        return distance_along_normal >= -0.001 && distance_along_normal <= params.depth

    case .Symmetric:
        // Cut goes in both directions
        half_depth := params.depth / 2.0
        return distance_along_normal >= -half_depth && distance_along_normal <= half_depth
    }

    return false
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

// Build a SimpleSolid from a triangle mesh (extract vertices and edges)
build_solid_from_triangles :: proc(triangles: [dynamic]extrude.Triangle3D) -> ^extrude.SimpleSolid {
    if len(triangles) == 0 {
        fmt.println("❌ Error: No triangles to build solid from")
        return nil
    }

    solid := new(extrude.SimpleSolid)
    solid.triangles = triangles  // Transfer ownership

    // Extract unique vertices from triangles
    vertex_map := make(map[[3]f64]^extrude.Vertex)  // Map position -> vertex pointer
    defer delete(vertex_map)

    solid.vertices = make([dynamic]^extrude.Vertex, 0, len(triangles) * 3)

    // Helper to get or create vertex
    get_or_create_vertex :: proc(
        pos: m.Vec3,
        vertex_map: ^map[[3]f64]^extrude.Vertex,
        vertices: ^[dynamic]^extrude.Vertex,
    ) -> ^extrude.Vertex {
        // Use position as key (with small epsilon tolerance)
        key := [3]f64{pos.x, pos.y, pos.z}

        // Check if vertex already exists (exact match)
        if v, exists := vertex_map[key]; exists {
            return v
        }

        // Create new vertex
        v := new(extrude.Vertex)
        v.position = pos
        append(vertices, v)
        vertex_map[key] = v
        return v
    }

    // Extract vertices from all triangles
    for tri in triangles {
        get_or_create_vertex(tri.v0, &vertex_map, &solid.vertices)
        get_or_create_vertex(tri.v1, &vertex_map, &solid.vertices)
        get_or_create_vertex(tri.v2, &vertex_map, &solid.vertices)
    }

    // Extract FEATURE EDGES ONLY (not all tessellation edges)
    // Feature edges are:
    //   1. Boundary edges (appear in only 1 triangle)
    //   2. Sharp edges (angle between adjacent triangle normals > threshold)
    // This gives clean CAD-style wireframes without tessellation clutter

    SHARP_EDGE_THRESHOLD :: 30.0  // degrees - edges sharper than this are shown

    // Build edge adjacency map: edge -> list of triangles that share it
    EdgeKey :: struct {
        v0, v1: rawptr,  // Ordered pair (smaller pointer first)
    }

    EdgeInfo :: struct {
        v0, v1: ^extrude.Vertex,
        triangles: [dynamic]int,  // Indices of triangles sharing this edge
    }

    edge_map := make(map[EdgeKey]EdgeInfo)
    defer {
        for _, info in edge_map {
            delete(info.triangles)
        }
        delete(edge_map)
    }

    // Build adjacency map
    for tri, tri_idx in triangles {
        v0 := get_or_create_vertex(tri.v0, &vertex_map, &solid.vertices)
        v1 := get_or_create_vertex(tri.v1, &vertex_map, &solid.vertices)
        v2 := get_or_create_vertex(tri.v2, &vertex_map, &solid.vertices)

        // Add three edges of the triangle
        add_triangle_edge :: proc(
            edge_map: ^map[EdgeKey]EdgeInfo,
            v0, v1: ^extrude.Vertex,
            tri_idx: int,
        ) {
            // Create ordered key
            v0_ptr := rawptr(v0)
            v1_ptr := rawptr(v1)

            key: EdgeKey
            if uintptr(v0_ptr) < uintptr(v1_ptr) {
                key = EdgeKey{v0_ptr, v1_ptr}
            } else {
                key = EdgeKey{v1_ptr, v0_ptr}
            }

            // Get or create edge info
            if info, exists := &edge_map[key]; exists {
                append(&info.triangles, tri_idx)
            } else {
                info := EdgeInfo{
                    v0 = v0,
                    v1 = v1,
                    triangles = make([dynamic]int, 0, 2),
                }
                append(&info.triangles, tri_idx)
                edge_map[key] = info
            }
        }

        add_triangle_edge(&edge_map, v0, v1, tri_idx)
        add_triangle_edge(&edge_map, v1, v2, tri_idx)
        add_triangle_edge(&edge_map, v2, v0, tri_idx)
    }

    // Extract feature edges
    solid.edges = make([dynamic]^extrude.Edge, 0, len(edge_map))

    for _, info in edge_map {
        is_feature_edge := false

        // Boundary edge (only 1 triangle) - always a feature edge
        if len(info.triangles) == 1 {
            is_feature_edge = true
        } else if len(info.triangles) == 2 {
            // Sharp edge (angle between normals > threshold)
            tri0 := triangles[info.triangles[0]]
            tri1 := triangles[info.triangles[1]]

            // Calculate angle between normals
            dot := glsl.dot(tri0.normal, tri1.normal)
            angle_rad := math.acos(glsl.clamp(dot, -1.0, 1.0))
            angle_deg := angle_rad * 180.0 / math.PI

            // If angle is large (> threshold), it's a sharp edge
            if angle_deg > SHARP_EDGE_THRESHOLD {
                is_feature_edge = true
            }
        } else if len(info.triangles) > 2 {
            // Non-manifold edge (>2 triangles) - keep for debugging
            is_feature_edge = true
            fmt.printf("⚠️  Non-manifold edge detected (%d triangles)\n", len(info.triangles))
        }

        // Add feature edge to solid
        if is_feature_edge {
            edge := new(extrude.Edge)
            edge.v0 = info.v0
            edge.v1 = info.v1
            append(&solid.edges, edge)
        }
    }

    fmt.printf("🔧 Built solid from triangles: %d vertices, %d edges, %d triangles\n",
        len(solid.vertices), len(solid.edges), len(triangles))

    return solid
}

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

// Generate proper pocket geometry with bottom face and side walls
generate_pocket_geometry :: proc(
    base_solid: ^extrude.SimpleSolid,
    sk: ^sketch.Sketch2D,
    profile: sketch.Profile,
    params: CutParams,
) -> [dynamic]extrude.Triangle3D {
    result := make([dynamic]extrude.Triangle3D)

    // Ensure base solid has triangles
    base_triangles: [dynamic]extrude.Triangle3D
    if len(base_solid.triangles) == 0 {
        fmt.println("⚠️  Base solid has no triangles, generating...")
        base_triangles = extrude.generate_face_triangles(base_solid)
    } else {
        // Copy existing triangles
        base_triangles = make([dynamic]extrude.Triangle3D, len(base_solid.triangles))
        copy(base_triangles[:], base_solid.triangles[:])
    }
    defer delete(base_triangles)

    // Get profile points for pocket geometry
    profile_points := get_profile_points_ordered(sk, profile)
    defer delete(profile_points)

    if len(profile_points) < 3 {
        fmt.println("❌ Error: Profile must have at least 3 points")
        return result
    }

    // Calculate cut offset (depth into the solid)
    cut_offset := calculate_cut_offset(&sk.plane, params)

    // 1. Filter triangles from base solid that intersect the cut region
    //    Check ALL triangles, not just top face
    for tri in base_triangles {
        // Calculate triangle centroid
        centroid := (tri.v0 + tri.v1 + tri.v2) / 3.0

        // Keep triangle only if it's NOT inside the cut volume
        if !point_inside_cut_volume(centroid, sk, profile, params) {
            append(&result, tri)
        }
    }

    // 2. Generate pocket bottom face using libtess2 for proper triangulation
    // Convert 2D profile points to 3D bottom vertices
    bottom_vertices := make([dynamic]m.Vec3, len(profile_points))
    defer delete(bottom_vertices)

    fmt.printf("  DEBUG: Sketch plane normal = (%.3f, %.3f, %.3f)\n",
        sk.plane.normal.x, sk.plane.normal.y, sk.plane.normal.z)
    fmt.printf("  DEBUG: Cut offset = (%.3f, %.3f, %.3f)\n",
        cut_offset.x, cut_offset.y, cut_offset.z)

    for point_2d in profile_points {
        point_3d := sketch.sketch_to_world(&sk.plane, point_2d)
        bottom_point := point_3d + cut_offset
        append(&bottom_vertices, bottom_point)

        fmt.printf("  DEBUG: Bottom vertex: (%.3f, %.3f, %.3f)\n",
            bottom_point.x, bottom_point.y, bottom_point.z)
    }

    // Use libtess2 to triangulate the pocket bottom (same as extrude face tessellation)
    if len(bottom_vertices) >= 3 {
        // For rectangular pockets (4 vertices), create simple quad triangulation
        if len(bottom_vertices) == 4 {
            // Simple quad split: 2 triangles
            tri1 := extrude.Triangle3D{
                v0 = bottom_vertices[0],
                v1 = bottom_vertices[1],
                v2 = bottom_vertices[2],
                normal = -sk.plane.normal,  // Faces down into pocket
                face_id = -1,
            }
            tri2 := extrude.Triangle3D{
                v0 = bottom_vertices[0],
                v1 = bottom_vertices[2],
                v2 = bottom_vertices[3],
                normal = -sk.plane.normal,
                face_id = -1,
            }
            append(&result, tri1)
            append(&result, tri2)

            fmt.printf("  DEBUG: Created 2 triangles for rectangular pocket bottom\n")
        } else {
            // For complex profiles, use simple fan triangulation
            // (libtess2 integration would go here for production)
            for i in 1..<len(bottom_vertices) - 1 {
                tri := extrude.Triangle3D{
                    v0 = bottom_vertices[0],
                    v1 = bottom_vertices[i],
                    v2 = bottom_vertices[i + 1],
                    normal = -sk.plane.normal,
                    face_id = -1,
                }
                append(&result, tri)
            }

            fmt.printf("  DEBUG: Created %d triangles for pocket bottom (fan)\n",
                len(bottom_vertices) - 2)
        }
    } else {
        fmt.printf("  ERROR: Not enough bottom vertices (%d) for pocket bottom!\n", len(bottom_vertices))
    }

    // 3. Generate pocket side walls (connect top edge to bottom edge)
    for i in 0..<len(profile_points) {
        j := (i + 1) % len(profile_points)

        // Top edge points (on sketch plane)
        top_p0 := sketch.sketch_to_world(&sk.plane, profile_points[i])
        top_p1 := sketch.sketch_to_world(&sk.plane, profile_points[j])

        // Bottom edge points (offset by cut depth)
        bottom_p0 := top_p0 + cut_offset
        bottom_p1 := top_p1 + cut_offset

        // Create two triangles for this wall quad
        // Triangle 1: top_p0, bottom_p0, bottom_p1
        edge_vec := top_p1 - top_p0
        depth_vec := bottom_p0 - top_p0
        wall_normal := glsl.normalize(glsl.cross(depth_vec, edge_vec))

        tri1 := extrude.Triangle3D{
            v0 = top_p0,
            v1 = bottom_p0,
            v2 = bottom_p1,
            normal = wall_normal,
            face_id = -1,
        }
        append(&result, tri1)

        // Triangle 2: top_p0, bottom_p1, top_p1
        tri2 := extrude.Triangle3D{
            v0 = top_p0,
            v1 = bottom_p1,
            v2 = top_p1,
            normal = wall_normal,
            face_id = -1,
        }
        append(&result, tri2)
    }

    fmt.printf("  Generated pocket geometry: %d triangles\n", len(result))
    fmt.printf("    - Base solid (excluding top): ~%d triangles\n", len(result) - 2*len(profile_points) - len(profile_points))
    fmt.printf("    - Pocket bottom: %d triangles\n", len(profile_points))
    fmt.printf("    - Pocket walls: %d triangles\n", 2*len(profile_points))

    return result
}
copy_triangles_excluding_cut_region :: proc(
    base_solid: ^extrude.SimpleSolid,
    sk: ^sketch.Sketch2D,
    profile: sketch.Profile,
    params: CutParams,
) -> [dynamic]extrude.Triangle3D {
    result := make([dynamic]extrude.Triangle3D, 0, len(base_solid.triangles))

    if len(base_solid.triangles) == 0 {
        // No triangles in base solid - try to generate them first
        fmt.println("⚠️  Base solid has no triangles, generating...")
        triangles := extrude.generate_face_triangles(base_solid)
        defer delete(triangles)

        // Filter triangles that are in the cut region
        for tri in triangles {
            if !triangle_in_cut_region(tri, sk, profile, params) {
                append(&result, tri)
            }
        }
    } else {
        // Filter existing triangles
        for tri in base_solid.triangles {
            if !triangle_in_cut_region(tri, sk, profile, params) {
                append(&result, tri)
            }
        }
    }

    fmt.printf("  Filtered %d → %d triangles (removed %d in cut region)\n",
        len(base_solid.triangles), len(result), len(base_solid.triangles) - len(result))

    return result
}

// Check if triangle is inside the cut region
triangle_in_cut_region :: proc(
    tri: extrude.Triangle3D,
    sk: ^sketch.Sketch2D,
    profile: sketch.Profile,
    params: CutParams,
) -> bool {
    // Calculate triangle centroid
    centroid := (tri.v0 + tri.v1 + tri.v2) / 3.0

    // Check if centroid is inside cut volume
    return point_inside_cut_volume(centroid, sk, profile, params)
}
