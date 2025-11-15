// features/extrude - Extrude Feature (Sketch → 3D Solid)
// Takes a closed 2D sketch profile and extrudes it along the sketch plane normal
package ohcad_extrude

import "core:fmt"
import "core:slice"
import sketch "../../features/sketch"
import topo "../../core/topology"
import m "../../core/math"
import glsl "core:math/linalg/glsl"
import tess "../../core/tessellation"

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

// Simple solid structure (wireframe + faces for selection + triangle mesh for rendering)
SimpleSolid :: struct {
    vertices: [dynamic]^Vertex,
    edges: [dynamic]^Edge,
    faces: [dynamic]SimpleFace,  // Face data for selection/sketching
    triangles: [dynamic]Triangle3D,  // NEW: Triangle mesh for shaded rendering & STL export
}

// Simple vertex (world space)
Vertex :: struct {
    position: m.Vec3,
}

// Simple edge (connects two vertices)
Edge :: struct {
    v0, v1: ^Vertex,
}

// Simple face (planar polygon for selection/sketching)
SimpleFace :: struct {
    vertices: [dynamic]^Vertex,  // Ordered vertices forming the face boundary
    normal: m.Vec3,               // Face normal (pointing outward)
    center: m.Vec3,               // Face center (for plane origin)
    name: string,                 // Debug name (e.g., "Top", "Bottom", "Side0")
}

// Triangle3D - Single triangle for mesh rendering and STL export
Triangle3D :: struct {
    v0, v1, v2: m.Vec3,  // Triangle vertices in world space
    normal: m.Vec3,       // Triangle normal (for flat shading)
    face_id: int,         // Which face this triangle belongs to
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

    // Get profile points in order (with tessellation for circles/arcs)
    profile_points := get_profile_points_tessellated(sk, profile)
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

    // NEW: Create faces for selection/sketching
    solid.faces = make([dynamic]SimpleFace, 0, 2 + len(profile_points))

    // Create bottom face
    bottom_face := create_bottom_face(bottom_vertices[:], sk.plane.normal)
    append(&solid.faces, bottom_face)

    // Create top face
    top_face := create_top_face(top_vertices[:], sk.plane.normal, extrude_offset)
    append(&solid.faces, top_face)

    // Create side faces (one for each edge of the profile)
    for i in 0..<len(bottom_vertices) {
        next_i := (i + 1) % len(bottom_vertices)
        side_face := create_side_face(
            bottom_vertices[i], bottom_vertices[next_i],
            top_vertices[i], top_vertices[next_i],
            i,
        )
        append(&solid.faces, side_face)
    }

    fmt.printf("✅ Created extruded solid: %d vertices, %d edges, %d faces\n",
        len(solid.vertices), len(solid.edges), len(solid.faces))

    // NEW: Generate triangle mesh for rendering
    solid.triangles = generate_face_triangles(solid)
    fmt.printf("✅ Generated %d triangles for shaded rendering\n", len(solid.triangles))

    return solid
}

// =============================================================================
// Face Generation Helpers
// =============================================================================

// Create bottom face (on original sketch plane)
create_bottom_face :: proc(vertices: []^Vertex, sketch_normal: m.Vec3) -> SimpleFace {
    face: SimpleFace
    face.vertices = make([dynamic]^Vertex, len(vertices))

    // Bottom face normal points opposite to sketch normal
    // Since we're flipping the normal, we must also reverse vertices to maintain winding
    for i in 0..<len(vertices) {
        face.vertices[len(vertices) - 1 - i] = vertices[i]
    }

    // Bottom face normal points outward (OPPOSITE to sketch normal - pointing down)
    face.normal = -sketch_normal

    // Calculate face center
    face.center = calculate_face_center(face.vertices[:])

    face.name = "Bottom"

    // DEBUG: Print bottom face normal
    fmt.printf("🔍 DEBUG Bottom Face: normal = (%.3f, %.3f, %.3f), center = (%.3f, %.3f, %.3f)\n",
        face.normal.x, face.normal.y, face.normal.z,
        face.center.x, face.center.y, face.center.z)

    return face
}

// Create top face (offset from sketch plane)
create_top_face :: proc(vertices: []^Vertex, sketch_normal: m.Vec3, extrude_offset: m.Vec3) -> SimpleFace {
    face: SimpleFace
    face.vertices = make([dynamic]^Vertex, len(vertices))

    // Copy vertices in same order (assuming sketch profile is counter-clockwise)
    for i in 0..<len(vertices) {
        face.vertices[i] = vertices[i]
    }

    // Top face normal points outward (SAME as sketch normal - pointing up)
    face.normal = sketch_normal

    // Calculate face center
    face.center = calculate_face_center(face.vertices[:])

    face.name = "Top"

    // DEBUG: Print top face normal
    fmt.printf("🔍 DEBUG Top Face: normal = (%.3f, %.3f, %.3f), center = (%.3f, %.3f, %.3f)\n",
        face.normal.x, face.normal.y, face.normal.z,
        face.center.x, face.center.y, face.center.z)

    return face
}

// Create side face (quad connecting bottom edge to top edge)
create_side_face :: proc(
    bottom_v0, bottom_v1: ^Vertex,
    top_v0, top_v1: ^Vertex,
    index: int,
) -> SimpleFace {
    face: SimpleFace
    face.vertices = make([dynamic]^Vertex, 4)

    // Quad vertices in order: bottom_v0, bottom_v1, top_v1, top_v0
    // This creates a counter-clockwise winding when viewed from outside
    face.vertices[0] = bottom_v0
    face.vertices[1] = bottom_v1
    face.vertices[2] = top_v1
    face.vertices[3] = top_v0

    // Calculate outward normal using cross product
    // Edge 1: bottom_v0 -> bottom_v1 (along bottom edge)
    // Edge 2: bottom_v0 -> top_v0 (vertical edge going up)
    // Cross product: edge1 × edge2 gives outward-pointing normal
    edge1 := bottom_v1.position - bottom_v0.position
    edge2 := top_v0.position - bottom_v0.position
    calculated_cross := glsl.cross(edge1, edge2)
    face.normal = glsl.normalize(calculated_cross)

    // Calculate face center
    face.center = calculate_face_center(face.vertices[:])

    face.name = fmt.aprintf("Side%d", index)

    return face
}

// Calculate center of a face (average of all vertices)
calculate_face_center :: proc(vertices: []^Vertex) -> m.Vec3 {
    if len(vertices) == 0 {
        return m.Vec3{0, 0, 0}
    }

    sum := m.Vec3{0, 0, 0}
    for vertex in vertices {
        sum += vertex.position
    }

    return sum / f64(len(vertices))
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

// Get profile points with tessellation for circles and arcs
get_profile_points_tessellated :: proc(sk: ^sketch.Sketch2D, profile: sketch.Profile) -> [dynamic]m.Vec2 {
    points := make([dynamic]m.Vec2, 0, 128)  // Reserve space for tessellation

    // Check if profile contains only a single circle
    if len(profile.entities) == 1 {
        entity := sk.entities[profile.entities[0]]

        // If it's a circle, tessellate it
        if circle, is_circle := entity.(sketch.SketchCircle); is_circle {
            // Get circle center from point ID
            center := sketch.sketch_get_point(sk, circle.center_id)
            if center == nil {
                fmt.println("Error: Circle center point not found")
                return points
            }

            tessellate_segments := 64  // Number of segments for circle

            for i in 0..<tessellate_segments {
                angle := f64(i) * 2.0 * 3.14159265359 / f64(tessellate_segments)
                x := center.x + circle.radius * glsl.cos(angle)
                y := center.y + circle.radius * glsl.sin(angle)
                append(&points, m.Vec2{x, y})
            }

            fmt.printf("🔵 Tessellated circle into %d points\n", tessellate_segments)
            return points
        }
    }

    // For line-based profiles, use the existing point extraction
    // Profile.points already contains the ordered point IDs
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

// =============================================================================
// Tessellation - Convert faces to triangle mesh
// =============================================================================

// Generate triangle mesh from all faces in the solid
generate_face_triangles :: proc(solid: ^SimpleSolid) -> [dynamic]Triangle3D {
    all_triangles := make([dynamic]Triangle3D, 0, len(solid.faces) * 2)

    // Tessellate each face
    for face, face_id in solid.faces {
        // Convert Vertex pointers to Vec3 array
        face_vertices := make([dynamic]m.Vec3, 0, len(face.vertices))
        defer delete(face_vertices)

        for vertex in face.vertices {
            append(&face_vertices, vertex.position)
        }

        // Tessellate this face (returns FaceTri)
        face_tris := tess.tessellate_face(face_vertices[:], face.normal, face_id)

        // Convert FaceTri to Triangle3D
        for ft in face_tris {
            tri := Triangle3D {
                v0 = ft.v0,
                v1 = ft.v1,
                v2 = ft.v2,
                normal = ft.normal,
                face_id = ft.face_id,
            }
            append(&all_triangles, tri)
        }

        delete(face_tris)
    }

    return all_triangles
}
