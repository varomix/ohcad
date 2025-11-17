// features/extrude - Extrude Feature (Sketch → 3D Solid)
// Takes a closed 2D sketch profile and extrudes it along the sketch plane normal
package ohcad_extrude

import "core:fmt"
import "core:slice"
import "core:math"
import sketch "../../features/sketch"
import topo "../../core/topology"
import m "../../core/math"
import glsl "core:math/linalg/glsl"
import tess "../../core/tessellation"
import occt "../../core/geometry/occt"

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
    occt_shape: occt.Shape,      // NEW: Exact B-Rep geometry for boolean/fillet/chamfer operations
    solid:      ^SimpleSolid,    // Tessellated mesh for rendering
    success:    bool,            // Operation success flag
    message:    string,          // Error/status message
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

    // Create solid from profile (returns both OCCT shape and SimpleSolid)
    occt_shape, solid := extrude_profile(sk, closed_profile, params)

    if occt_shape == nil || solid == nil {
        result.message = "Failed to create solid from profile"
        // Clean up if partial result
        if occt_shape != nil {
            occt.delete_shape(occt_shape)
        }
        if solid != nil {
            extrude_result_destroy(&ExtrudeResult{solid = solid})
        }
        return result
    }

    // Store both exact geometry and tessellated mesh
    result.occt_shape = occt_shape
    result.solid = solid
    result.success = true
    result.message = "Extrude successful"

    return result
}

// Extrude a single closed profile using OCCT
extrude_profile :: proc(
    sk: ^sketch.Sketch2D,
    profile: sketch.Profile,
    params: ExtrudeParams,
) -> (occt.Shape, ^SimpleSolid) {

    // Calculate extrusion vector
    extrude_offset := calculate_extrude_offset(&sk.plane, params)

    // Get profile points in order (with tessellation for circles/arcs)
    profile_points := get_profile_points_tessellated(sk, profile)
    defer delete(profile_points)

    if len(profile_points) < 3 {
        fmt.println("Error: Profile must have at least 3 points")
        return nil, nil
    }

    fmt.printf("🔧 Extruding %d-point profile using OCCT...\n", len(profile_points))

    // Use OCCT to perform extrusion and get both shape and mesh
    occt_result := occt.extrude_profile_2d(profile_points[:], extrude_offset)

    if occt_result.shape == nil || occt_result.mesh == nil {
        fmt.println("❌ OCCT extrusion failed")
        // Clean up if partial result
        if occt_result.shape != nil {
            occt.delete_shape(occt_result.shape)
        }
        if occt_result.mesh != nil {
            occt.delete_mesh(occt_result.mesh)
        }
        return nil, nil
    }
    defer occt.delete_mesh(occt_result.mesh)  // Clean up mesh after conversion

    // Convert OCCT mesh to SimpleSolid
    solid := occt_mesh_to_simple_solid(occt_result.mesh)

    if solid == nil {
        fmt.println("❌ Failed to convert OCCT mesh to SimpleSolid")
        occt.delete_shape(occt_result.shape)
        return nil, nil
    }

    // Create faces for selection/sketching (OCCT doesn't provide face metadata)
    // We'll generate simplified face data for top/bottom planes
    add_face_metadata(solid, sk, profile_points[:], extrude_offset)

    fmt.printf("✅ Created OCCT-extruded solid: %d vertices, %d edges, %d triangles\n",
        len(solid.vertices), len(solid.edges), len(solid.triangles))

    // Return both OCCT shape (exact geometry) and SimpleSolid (tessellated mesh)
    return occt_result.shape, solid
}

// =============================================================================
// Face Generation Helpers
// =============================================================================

// Add face metadata to OCCT-generated solid for selection/sketching
add_face_metadata :: proc(
    solid: ^SimpleSolid,
    sk: ^sketch.Sketch2D,
    profile_points: []m.Vec2,
    extrude_offset: m.Vec3,
) {
    solid.faces = make([dynamic]SimpleFace, 0, 2)

    // Create bottom face with actual vertices from profile
    bottom_face: SimpleFace
    bottom_face.vertices = make([dynamic]^Vertex, 0, len(profile_points))
    bottom_face.normal = -sk.plane.normal
    bottom_face.center = sk.plane.origin
    bottom_face.name = "Bottom"

    // Populate bottom face vertices (on sketch plane, reversed winding for downward normal)
    for i := len(profile_points) - 1; i >= 0; i -= 1 {
        point_2d := profile_points[i]
        point_3d := sketch.sketch_to_world(&sk.plane, point_2d)

        // Find or create vertex in solid
        vertex := find_or_create_vertex(solid, point_3d)
        append(&bottom_face.vertices, vertex)
    }

    append(&solid.faces, bottom_face)

    // Create top face with actual vertices
    top_face: SimpleFace
    top_face.vertices = make([dynamic]^Vertex, 0, len(profile_points))
    top_face.normal = sk.plane.normal
    top_face.center = sk.plane.origin + extrude_offset
    top_face.name = "Top"

    // Populate top face vertices (offset by extrude_offset)
    for point_2d in profile_points {
        point_3d := sketch.sketch_to_world(&sk.plane, point_2d)
        top_point := point_3d + extrude_offset

        // Find or create vertex in solid
        vertex := find_or_create_vertex(solid, top_point)
        append(&top_face.vertices, vertex)
    }

    append(&solid.faces, top_face)

    fmt.printf("✅ Added face metadata: %d faces (%d vertices each)\n",
        len(solid.faces), len(profile_points))
}

// Find existing vertex or create new one
find_or_create_vertex :: proc(solid: ^SimpleSolid, position: m.Vec3) -> ^Vertex {
    EPSILON :: 0.0001

    // Search for existing vertex at this position
    for vertex in solid.vertices {
        diff := vertex.position - position
        dist_sq := diff.x*diff.x + diff.y*diff.y + diff.z*diff.z
        if dist_sq < EPSILON * EPSILON {
            return vertex
        }
    }

    // Create new vertex
    vertex := new(Vertex)
    vertex.position = position
    append(&solid.vertices, vertex)
    return vertex
}

// Convert OCCT tessellated mesh to SimpleSolid format
occt_mesh_to_simple_solid :: proc(mesh: ^occt.Mesh) -> ^SimpleSolid {
    if mesh == nil || mesh.num_vertices == 0 || mesh.num_triangles == 0 {
        return nil
    }

    solid := new(SimpleSolid)

    // Extract triangles from OCCT mesh
    solid.triangles = make([dynamic]Triangle3D, 0, int(mesh.num_triangles))

    for i in 0..<int(mesh.num_triangles) {
        // Get triangle vertex indices
        idx0 := mesh.triangles[i*3 + 0]
        idx1 := mesh.triangles[i*3 + 1]
        idx2 := mesh.triangles[i*3 + 2]

        // Get vertex positions
        v0 := m.Vec3{
            f64(mesh.vertices[idx0*3 + 0]),
            f64(mesh.vertices[idx0*3 + 1]),
            f64(mesh.vertices[idx0*3 + 2]),
        }

        v1 := m.Vec3{
            f64(mesh.vertices[idx1*3 + 0]),
            f64(mesh.vertices[idx1*3 + 1]),
            f64(mesh.vertices[idx1*3 + 2]),
        }

        v2 := m.Vec3{
            f64(mesh.vertices[idx2*3 + 0]),
            f64(mesh.vertices[idx2*3 + 1]),
            f64(mesh.vertices[idx2*3 + 2]),
        }

        // Get vertex normals (OCCT provides per-vertex normals for smooth shading)
        n0 := m.Vec3{
            f64(mesh.normals[idx0*3 + 0]),
            f64(mesh.normals[idx0*3 + 1]),
            f64(mesh.normals[idx0*3 + 2]),
        }

        n1 := m.Vec3{
            f64(mesh.normals[idx1*3 + 0]),
            f64(mesh.normals[idx1*3 + 1]),
            f64(mesh.normals[idx1*3 + 2]),
        }

        n2 := m.Vec3{
            f64(mesh.normals[idx2*3 + 0]),
            f64(mesh.normals[idx2*3 + 1]),
            f64(mesh.normals[idx2*3 + 2]),
        }

        // Calculate face normal (average of vertex normals)
        face_normal := (n0 + n1 + n2) / 3.0

        // Create triangle
        tri := Triangle3D{
            v0 = v0,
            v1 = v1,
            v2 = v2,
            normal = face_normal,
            face_id = 0,  // OCCT doesn't distinguish faces in tessellation
        }

        append(&solid.triangles, tri)
    }

    // Extract feature edges from triangles
    extract_feature_edges_from_mesh(solid)

    return solid
}

// Extract wireframe edges from triangle mesh (feature edges only)
// This creates clean CAD-style wireframes without tessellation clutter
extract_feature_edges_from_mesh :: proc(solid: ^SimpleSolid) {
    if len(solid.triangles) == 0 {
        return
    }

    SHARP_EDGE_THRESHOLD :: 30.0  // degrees

    // Build vertex map and edge adjacency
    vertex_map := make(map[[3]f64]^Vertex)
    defer delete(vertex_map)

    solid.vertices = make([dynamic]^Vertex, 0, len(solid.triangles) * 3)

    // Helper to get or create vertex
    get_or_create_vertex :: proc(
        pos: m.Vec3,
        vertex_map: ^map[[3]f64]^Vertex,
        vertices: ^[dynamic]^Vertex,
    ) -> ^Vertex {
        key := [3]f64{pos.x, pos.y, pos.z}

        if v, exists := vertex_map[key]; exists {
            return v
        }

        v := new(Vertex)
        v.position = pos
        append(vertices, v)
        vertex_map[key] = v
        return v
    }

    // Edge adjacency tracking
    EdgeKey :: struct {
        v0, v1: rawptr,
    }

    EdgeInfo :: struct {
        v0, v1: ^Vertex,
        triangles: [dynamic]int,
    }

    edge_map := make(map[EdgeKey]EdgeInfo)
    defer {
        for _, info in edge_map {
            delete(info.triangles)
        }
        delete(edge_map)
    }

    // Build edge adjacency from triangles
    for tri, tri_idx in solid.triangles {
        v0 := get_or_create_vertex(tri.v0, &vertex_map, &solid.vertices)
        v1 := get_or_create_vertex(tri.v1, &vertex_map, &solid.vertices)
        v2 := get_or_create_vertex(tri.v2, &vertex_map, &solid.vertices)

        add_edge :: proc(
            edge_map: ^map[EdgeKey]EdgeInfo,
            v0, v1: ^Vertex,
            tri_idx: int,
        ) {
            v0_ptr := rawptr(v0)
            v1_ptr := rawptr(v1)

            key: EdgeKey
            if uintptr(v0_ptr) < uintptr(v1_ptr) {
                key = EdgeKey{v0_ptr, v1_ptr}
            } else {
                key = EdgeKey{v1_ptr, v0_ptr}
            }

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

        add_edge(&edge_map, v0, v1, tri_idx)
        add_edge(&edge_map, v1, v2, tri_idx)
        add_edge(&edge_map, v2, v0, tri_idx)
    }

    // Extract feature edges (boundary + sharp edges)
    solid.edges = make([dynamic]^Edge, 0, len(edge_map))

    for _, info in edge_map {
        is_feature := false

        if len(info.triangles) == 1 {
            // Boundary edge
            is_feature = true
        } else if len(info.triangles) == 2 {
            // Check if sharp edge
            tri0 := solid.triangles[info.triangles[0]]
            tri1 := solid.triangles[info.triangles[1]]

            dot := glsl.dot(tri0.normal, tri1.normal)
            angle_rad := math.acos(glsl.clamp(dot, -1.0, 1.0))
            angle_deg := angle_rad * 180.0 / math.PI

            if angle_deg > SHARP_EDGE_THRESHOLD {
                is_feature = true
            }
        } else if len(info.triangles) > 2 {
            // Non-manifold edge
            is_feature = true
        }

        if is_feature {
            edge := new(Edge)
            edge.v0 = info.v0
            edge.v1 = info.v1
            append(&solid.edges, edge)
        }
    }

    fmt.printf("🔧 Extracted %d feature edges from %d triangles\n",
        len(solid.edges), len(solid.triangles))
}



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
