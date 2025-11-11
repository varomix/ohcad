// features/revolve - Revolve Feature (Sketch → 3D Solid by Revolution)
// Takes a closed 2D sketch profile and revolves it around an axis
package ohcad_revolve

import "core:fmt"
import "core:math"
import sketch "../../features/sketch"
import extrude "../../features/extrude"
import m "../../core/math"
import glsl "core:math/linalg/glsl"
import tess "../../core/tessellation"

// Revolve axis type
RevolveAxis :: enum {
    SketchX,    // Revolve around sketch X-axis (horizontal)
    SketchY,    // Revolve around sketch Y-axis (vertical)
    Custom,     // Custom axis (point + direction)
}

// Revolve parameters
RevolveParams :: struct {
    angle:      f64,           // Revolution angle in degrees (0-360)
    segments:   int,           // Number of rotation steps (more = smoother)
    axis_type:  RevolveAxis,   // Which axis to revolve around
    axis_point: m.Vec3,        // Axis origin point (for Custom axis)
    axis_dir:   m.Vec3,        // Axis direction (for Custom axis)
}

// Revolve result
RevolveResult :: struct {
    solid:   ^extrude.SimpleSolid,  // Resulting 3D solid (simplified wireframe)
    success: bool,                   // Operation success flag
    message: string,                 // Error/status message
}

// =============================================================================
// Default Parameters
// =============================================================================

// Create default revolve parameters (360° around Y-axis, 32 segments)
revolve_params_default :: proc() -> RevolveParams {
    return RevolveParams{
        angle = 360.0,
        segments = 32,
        axis_type = .SketchY,
        axis_point = m.Vec3{0, 0, 0},
        axis_dir = m.Vec3{0, 1, 0},
    }
}

// =============================================================================
// Revolve Operation
// =============================================================================

// Revolve a sketch profile to create a 3D solid
revolve_sketch :: proc(sk: ^sketch.Sketch2D, params: RevolveParams) -> RevolveResult {
    result: RevolveResult

    // Validate parameters
    if params.angle <= 0 || params.angle > 360 {
        result.message = "Revolve angle must be between 0 and 360 degrees"
        return result
    }

    if params.segments < 3 {
        result.message = "Revolve segments must be at least 3"
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

    fmt.printf("Revolving closed profile with %d entities, %d points\n",
        len(closed_profile.entities), len(closed_profile.points))

    // Create solid from profile
    solid := revolve_profile(sk, closed_profile, params)

    if solid == nil {
        result.message = "Failed to create solid from profile"
        return result
    }

    result.solid = solid
    result.success = true
    result.message = "Revolve successful"

    return result
}

// Revolve a single closed profile
revolve_profile :: proc(
    sk: ^sketch.Sketch2D,
    profile: sketch.Profile,
    params: RevolveParams,
) -> ^extrude.SimpleSolid {

    // Calculate revolve axis in world space
    axis_origin, axis_dir := calculate_revolve_axis(&sk.plane, params)

    // Get profile points in order (with tessellation for circles/arcs)
    profile_points := get_profile_points_tessellated(sk, profile)
    defer delete(profile_points)

    if len(profile_points) < 3 {
        fmt.println("Error: Profile must have at least 3 points")
        return nil
    }

    // Check if this is a full revolution (360 degrees)
    is_full_revolution := abs(params.angle - 360.0) < 0.01

    // For full revolution, we don't duplicate the last segment
    // For partial revolution, we need segments+1 to get the end position
    num_rotations := params.segments if is_full_revolution else params.segments + 1

    // Create solid
    solid := new(extrude.SimpleSolid)
    solid.vertices = make([dynamic]^extrude.Vertex, 0, len(profile_points) * num_rotations)
    solid.edges = make([dynamic]^extrude.Edge, 0, len(profile_points) * params.segments * 2)

    // Convert profile points to world space
    profile_3d := make([dynamic]m.Vec3, len(profile_points))
    defer delete(profile_3d)

    for point_2d, i in profile_points {
        profile_3d[i] = sketch.sketch_to_world(&sk.plane, point_2d)
    }

    // Create vertices at each rotation step
    angle_step := params.angle / f64(params.segments)

    all_ring_vertices := make([dynamic][dynamic]^extrude.Vertex, num_rotations)
    defer {
        for ring in all_ring_vertices {
            delete(ring)
        }
        delete(all_ring_vertices)
    }

    for rotation in 0..<num_rotations {
        angle_rad := math.to_radians(f64(rotation) * angle_step)
        ring_vertices := make([dynamic]^extrude.Vertex, 0, len(profile_points))

        // Rotate each profile point around the axis
        for point_3d in profile_3d {
            rotated_point := rotate_point_around_axis(point_3d, axis_origin, axis_dir, angle_rad)
            vertex := new(extrude.Vertex)
            vertex.position = rotated_point
            append(&solid.vertices, vertex)
            append(&ring_vertices, vertex)
        }

        all_ring_vertices[rotation] = ring_vertices
    }

    // Create edges
    // 1. Profile edges (connecting points within each ring)
    for rotation in 0..<params.segments {
        ring := all_ring_vertices[rotation]
        for i in 0..<len(ring) {
            next_i := (i + 1) % len(ring)
            edge := new(extrude.Edge)
            edge.v0 = ring[i]
            edge.v1 = ring[next_i]
            append(&solid.edges, edge)
        }
    }

    // 2. Sweep edges (connecting corresponding points between rings)
    for rotation in 0..<params.segments {
        next_rotation := (rotation + 1) % num_rotations
        current_ring := all_ring_vertices[rotation]
        next_ring := all_ring_vertices[next_rotation]

        for i in 0..<len(current_ring) {
            edge := new(extrude.Edge)
            edge.v0 = current_ring[i]
            edge.v1 = next_ring[i]
            append(&solid.edges, edge)
        }
    }

    // For partial revolution, add closing edges on the end faces
    if !is_full_revolution {
        // Add edges for the first face (at 0 degrees)
        first_ring := all_ring_vertices[0]
        for i in 0..<len(first_ring) {
            next_i := (i + 1) % len(first_ring)
            edge := new(extrude.Edge)
            edge.v0 = first_ring[i]
            edge.v1 = first_ring[next_i]
            append(&solid.edges, edge)
        }

        // Add edges for the last face (at angle degrees)
        last_ring := all_ring_vertices[num_rotations - 1]
        for i in 0..<len(last_ring) {
            next_i := (i + 1) % len(last_ring)
            edge := new(extrude.Edge)
            edge.v0 = last_ring[i]
            edge.v1 = last_ring[next_i]
            append(&solid.edges, edge)
        }
    }

    // Create faces for selection/sketching
    solid.faces = make([dynamic]extrude.SimpleFace, 0, params.segments * len(profile_points) + 2)

    // Create swept surface faces (quads connecting profile edges across rotation)
    for rotation in 0..<params.segments {
        next_rotation := (rotation + 1) % num_rotations
        current_ring := all_ring_vertices[rotation]
        next_ring := all_ring_vertices[next_rotation]

        for i in 0..<len(current_ring) {
            next_i := (i + 1) % len(current_ring)

            face := create_revolve_face(
                current_ring[i], current_ring[next_i],
                next_ring[i], next_ring[next_i],
                rotation, i,
            )
            append(&solid.faces, face)
        }
    }

    // For partial revolution, add end cap faces
    if !is_full_revolution {
        // Start face (at 0 degrees)
        start_face := create_end_cap_face(
            all_ring_vertices[0][:],
            axis_dir,
            false,  // reverse for outward normal
            "StartCap",
        )
        append(&solid.faces, start_face)

        // End face (at angle degrees)
        end_face := create_end_cap_face(
            all_ring_vertices[num_rotations - 1][:],
            axis_dir,
            true,  // keep orientation for outward normal
            "EndCap",
        )
        append(&solid.faces, end_face)
    }

    fmt.printf("✅ Created revolved solid: %d vertices, %d edges, %d faces\n",
        len(solid.vertices), len(solid.edges), len(solid.faces))

    // NEW: Generate triangle mesh for rendering
    solid.triangles = generate_face_triangles(solid)
    fmt.printf("✅ Generated %d triangles for shaded rendering\n", len(solid.triangles))

    return solid
}

// =============================================================================
// Helper Functions
// =============================================================================

// Calculate revolve axis in world space
calculate_revolve_axis :: proc(
    plane: ^sketch.SketchPlane,
    params: RevolveParams,
) -> (origin: m.Vec3, direction: m.Vec3) {

    switch params.axis_type {
    case .SketchX:
        // Revolve around sketch X-axis (horizontal in sketch space)
        origin = plane.origin
        direction = plane.x_axis
    case .SketchY:
        // Revolve around sketch Y-axis (vertical in sketch space)
        origin = plane.origin
        direction = plane.y_axis
    case .Custom:
        // Use custom axis
        origin = params.axis_point
        direction = glsl.normalize(params.axis_dir)
    }

    return
}

// Rotate a point around an arbitrary axis
// Uses Rodrigues' rotation formula
rotate_point_around_axis :: proc(
    point: m.Vec3,
    axis_point: m.Vec3,
    axis_dir: m.Vec3,
    angle_rad: f64,
) -> m.Vec3 {

    // Translate point so axis passes through origin
    p := point - axis_point

    // Rodrigues' rotation formula:
    // v_rot = v*cos(θ) + (k × v)*sin(θ) + k*(k·v)*(1-cos(θ))
    // where k is the unit axis vector

    k := glsl.normalize(axis_dir)
    cos_theta := math.cos(angle_rad)
    sin_theta := math.sin(angle_rad)

    // Calculate components
    term1 := p * cos_theta
    term2 := glsl.cross(k, p) * sin_theta
    term3 := k * glsl.dot(k, p) * (1.0 - cos_theta)

    rotated := term1 + term2 + term3

    // Translate back
    return rotated + axis_point
}

// Create a face for the revolved surface (quad connecting profile edge across rotation)
create_revolve_face :: proc(
    v0_curr, v1_curr: ^extrude.Vertex,  // Current ring edge vertices
    v0_next, v1_next: ^extrude.Vertex,  // Next ring edge vertices
    rotation: int,
    edge_index: int,
) -> extrude.SimpleFace {
    face: extrude.SimpleFace
    face.vertices = make([dynamic]^extrude.Vertex, 4)

    // Quad vertices in counter-clockwise order (viewed from outside)
    // v0_curr -> v1_curr -> v1_next -> v0_next
    face.vertices[0] = v0_curr
    face.vertices[1] = v1_curr
    face.vertices[2] = v1_next
    face.vertices[3] = v0_next

    // Calculate normal using cross product
    // Edge 1: v0_curr -> v1_curr (along profile edge)
    // Edge 2: v0_curr -> v0_next (along rotation direction)
    // Negate cross product to get outward-pointing normal
    edge1 := v1_curr.position - v0_curr.position
    edge2 := v0_next.position - v0_curr.position
    face.normal = -glsl.normalize(glsl.cross(edge2, edge1))

    // Calculate face center
    face.center = extrude.calculate_face_center(face.vertices[:])

    face.name = fmt.aprintf("Surface_R%d_E%d", rotation, edge_index)
    return face
}

// Create an end cap face for partial revolution
create_end_cap_face :: proc(
    vertices: []^extrude.Vertex,
    axis_dir: m.Vec3,
    keep_orientation: bool,
    name: string,
) -> extrude.SimpleFace {
    face: extrude.SimpleFace
    face.vertices = make([dynamic]^extrude.Vertex, len(vertices))

    if keep_orientation {
        // Keep original vertex order
        for i in 0..<len(vertices) {
            face.vertices[i] = vertices[i]
        }
    } else {
        // Reverse vertex order for opposite normal direction
        for i in 0..<len(vertices) {
            face.vertices[len(vertices) - 1 - i] = vertices[i]
        }
    }

    // Calculate normal from first three vertices
    if len(vertices) >= 3 {
        v0 := vertices[0].position
        v1 := vertices[1].position
        v2 := vertices[2].position

        edge1 := v1 - v0
        edge2 := v2 - v0
        calculated_normal := glsl.cross(edge1, edge2)

        if keep_orientation {
            face.normal = glsl.normalize(calculated_normal)
        } else {
            face.normal = -glsl.normalize(calculated_normal)
        }
    } else {
        // Fallback to axis direction
        face.normal = glsl.normalize(axis_dir)
    }

    // Calculate face center
    face.center = extrude.calculate_face_center(face.vertices[:])

    face.name = name
    return face
}

// =============================================================================
// Profile Point Extraction (with Circle/Arc Tessellation)
// =============================================================================

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
                angle := f64(i) * 2.0 * math.PI / f64(tessellate_segments)
                x := center.x + circle.radius * math.cos(angle)
                y := center.y + circle.radius * math.sin(angle)
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
// Cleanup
// =============================================================================

// Destroy revolve result (cleanup)
revolve_result_destroy :: proc(result: ^RevolveResult) {
    if result.solid != nil {
        // Use extrude's cleanup since we're using SimpleSolid
        extrude_result := extrude.ExtrudeResult{solid = result.solid}
        extrude.extrude_result_destroy(&extrude_result)
        result.solid = nil
    }
}

// =============================================================================
// Tessellation - Convert faces to triangle mesh
// =============================================================================

// Generate triangle mesh from all faces in the solid
generate_face_triangles :: proc(solid: ^extrude.SimpleSolid) -> [dynamic]extrude.Triangle3D {
    all_triangles := make([dynamic]extrude.Triangle3D, 0, len(solid.faces) * 2)

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
            tri := extrude.Triangle3D {
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
