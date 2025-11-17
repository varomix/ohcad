// features/sketch - Constraint solver for OhCAD sketches
//
// This module provides a high-level interface to solve 2D sketches using libslvs.
// It converts OhCAD sketch data structures to libslvs format, solves constraints,
// and updates point positions.

package ohcad_sketch

import "core:fmt"
import "core:math"
import m "../../core/math"
import glsl "core:math/linalg/glsl"
import solver "../../core/solver"

// Solver result information
SolveResult :: struct {
    success: bool,            // True if solve succeeded
    result_code: int,         // libslvs result code
    dof: int,                 // Degrees of freedom (0 = fully constrained)
    error_message: string,    // Human-readable error message
    failed_constraints: [dynamic]int,  // IDs of constraints that failed (if any)
}

// Internal mapping from OhCAD to libslvs
SketchMapping :: struct {
    group: u32,                                 // libslvs group handle
    workplane: solver.Slvs_Entity,              // libslvs workplane entity
    workplane_normal: solver.Slvs_Entity,       // libslvs normal entity for the workplane (needed for circles/arcs)
    point_map: map[int]solver.Slvs_Entity,      // OhCAD point ID → libslvs point entity
    entity_map: map[int]solver.Slvs_Entity,     // OhCAD entity ID → libslvs entity
    distance_map: map[int]solver.Slvs_Entity,   // OhCAD circle ID → libslvs distance entity (for radius)
}

// =============================================================================
// Public API
// =============================================================================

// Solve a 2D sketch using libslvs
// Updates point positions in the sketch if successful
solve_sketch_2d :: proc(s: ^Sketch2D) -> SolveResult {
    result := SolveResult{}

    // Clear previous solver state
    solver.Slvs_ClearSketch()

    // Create libslvs entities from sketch
    mapping, mapping_ok := convert_sketch_to_slvs(s)
    if !mapping_ok {
        result.success = false
        result.error_message = "Failed to convert sketch to solver format"
        return result
    }
    defer cleanup_mapping(&mapping)

    // Solve
    solve_res := solver.Slvs_SolveSketch(mapping.group, nil)

    // Process result
    result.result_code = int(solve_res.result)
    result.dof = int(solve_res.dof)

    switch solve_res.result {
    case solver.SLVS_RESULT_OKAY, solver.SLVS_RESULT_REDUNDANT_OKAY:
        // Success! Update sketch points with solved positions
        update_sketch_from_slvs(s, &mapping)
        result.success = true
        if solve_res.result == solver.SLVS_RESULT_REDUNDANT_OKAY {
            result.error_message = "Solved (some redundant constraints)"
        } else {
            result.error_message = "Solved successfully"
        }

    case solver.SLVS_RESULT_INCONSISTENT:
        result.success = false
        result.error_message = "Constraints are inconsistent (impossible to satisfy)"

    case solver.SLVS_RESULT_DIDNT_CONVERGE:
        result.success = false
        result.error_message = "Solver did not converge (try adjusting initial positions)"

    case solver.SLVS_RESULT_TOO_MANY_UNKNOWNS:
        result.success = false
        result.error_message = "Too many unknowns for solver"

    case:
        result.success = false
        result.error_message = fmt.tprintf("Unknown solver result: %d", solve_res.result)
    }

    return result
}

// =============================================================================
// Quaternion Utilities
// =============================================================================

// Simple quaternion for 3D rotations (w, x, y, z)
Quaternion :: struct {
    w, x, y, z: f64,
}

// Calculate quaternion for shortest arc rotation from vector 'from' to vector 'to'
// Both vectors should be normalized
quaternion_from_vectors :: proc(from: m.Vec3, to: m.Vec3) -> Quaternion {
    // Normalize input vectors to be safe
    from_norm := glsl.normalize(from)
    to_norm := glsl.normalize(to)

    // Calculate dot product
    dot := glsl.dot(from_norm, to_norm)

    // Vectors are already aligned (or very close)
    if dot >= 0.999999 {
        return Quaternion{1, 0, 0, 0}  // Identity quaternion
    }

    // Vectors are opposite - need to pick an arbitrary perpendicular axis
    if dot <= -0.999999 {
        // Find a perpendicular axis
        // Try X axis first, if that's too parallel, use Y axis
        perp: m.Vec3
        if math.abs(from_norm.x) < 0.9 {
            perp = glsl.normalize(glsl.cross(m.Vec3{1, 0, 0}, from_norm))
        } else {
            perp = glsl.normalize(glsl.cross(m.Vec3{0, 1, 0}, from_norm))
        }
        // 180 degree rotation around perpendicular axis
        return Quaternion{0, perp.x, perp.y, perp.z}
    }

    // Standard case: shortest arc rotation
    // Using numerically stable formula that avoids arccos
    axis := glsl.cross(from_norm, to_norm)

    // w = sqrt((1 + dot) / 2)
    // xyz = axis / (2 * w)
    w := math.sqrt((1.0 + dot) / 2.0)
    inv_2w := 1.0 / (2.0 * w)

    return Quaternion{
        w = w,
        x = axis.x * inv_2w,
        y = axis.y * inv_2w,
        z = axis.z * inv_2w,
    }
}

// Create quaternion from rotation matrix (3x3)
// Matrix columns are the rotated X, Y, Z axes
quaternion_from_axes :: proc(x_axis: m.Vec3, y_axis: m.Vec3, z_axis: m.Vec3) -> Quaternion {
    // Build rotation matrix from axes (column vectors)
    // libslvs expects quaternion that transforms FROM default coords TO sketch coords
    // Matrix columns are where the default axes (X, Y, Z) end up

    m00 := x_axis.x; m01 := y_axis.x; m02 := z_axis.x
    m10 := x_axis.y; m11 := y_axis.y; m12 := z_axis.y
    m20 := x_axis.z; m21 := y_axis.z; m22 := z_axis.z

    // Convert rotation matrix to quaternion using standard algorithm
    trace := m00 + m11 + m22

    if trace > 0.0 {
        s := math.sqrt(trace + 1.0) * 2.0  // s = 4 * w
        w := 0.25 * s
        x := (m21 - m12) / s
        y := (m02 - m20) / s
        z := (m10 - m01) / s
        return Quaternion{w, x, y, z}
    } else if m00 > m11 && m00 > m22 {
        s := math.sqrt(1.0 + m00 - m11 - m22) * 2.0  // s = 4 * x
        w := (m21 - m12) / s
        x := 0.25 * s
        y := (m01 + m10) / s
        z := (m02 + m20) / s
        return Quaternion{w, x, y, z}
    } else if m11 > m22 {
        s := math.sqrt(1.0 + m11 - m00 - m22) * 2.0  // s = 4 * y
        w := (m02 - m20) / s
        x := (m01 + m10) / s
        y := 0.25 * s
        z := (m12 + m21) / s
        return Quaternion{w, x, y, z}
    } else {
        s := math.sqrt(1.0 + m22 - m00 - m11) * 2.0  // s = 4 * z
        w := (m10 - m01) / s
        x := (m02 + m20) / s
        y := (m12 + m21) / s
        z := 0.25 * s
        return Quaternion{w, x, y, z}
    }
}

// =============================================================================
// Internal Conversion: OhCAD → libslvs
// =============================================================================

convert_sketch_to_slvs :: proc(s: ^Sketch2D) -> (SketchMapping, bool) {
    mapping := SketchMapping{
        group = 1,  // Use group 1 for sketch
        point_map = make(map[int]solver.Slvs_Entity),
        entity_map = make(map[int]solver.Slvs_Entity),
        distance_map = make(map[int]solver.Slvs_Entity),
    }

    // Create workplane oriented to match the sketch plane
    // We need to align ALL axes (X, Y, Z) to ensure H/V constraints work correctly
    // libslvs workplane U/V axes must match our sketch X/Y axes

    // CRITICAL FIX: libslvs appears to use a different axis convention
    // After testing, it seems we need to SWAP X and Y axes (90° rotation around normal)
    // This aligns libslvs's U/V with our sketch's X/Y correctly

    // Create 3D origin point for workplane
    origin_3d := solver.Slvs_AddPoint3D(
        mapping.group,
        s.plane.origin.x,
        s.plane.origin.y,
        s.plane.origin.z,
    )

    // Calculate rotation quaternion with SWAPPED axes to match libslvs convention:
    // libslvs U-axis (horizontal) → our Y-axis
    // libslvs V-axis (vertical) → our X-axis
    // libslvs W-axis (normal) → our normal
    quat := quaternion_from_axes(s.plane.y_axis, s.plane.x_axis, s.plane.normal)

    // fmt.printf("DEBUG SOLVER: Sketch plane axes:\n")
    // fmt.printf("  X-axis (our horiz): (%.2f, %.2f, %.2f)\n", s.plane.x_axis.x, s.plane.x_axis.y, s.plane.x_axis.z)
    // fmt.printf("  Y-axis (our vert):  (%.2f, %.2f, %.2f)\n", s.plane.y_axis.x, s.plane.y_axis.y, s.plane.y_axis.z)
    // fmt.printf("  Normal:             (%.2f, %.2f, %.2f)\n", s.plane.normal.x, s.plane.normal.y, s.plane.normal.z)
    // fmt.printf("DEBUG SOLVER: Quaternion (swapped): w=%.3f, x=%.3f, y=%.3f, z=%.3f\n\n", quat.w, quat.x, quat.y, quat.z)

    // Create 3D normal with full orientation quaternion
    normal_3d := solver.Slvs_AddNormal3D(
        mapping.group,
        quat.w, quat.x, quat.y, quat.z,
    )

    // Create workplane with origin and fully oriented normal
    mapping.workplane = solver.Slvs_AddWorkplane(mapping.group, origin_3d, normal_3d)

    // Extract the workplane's normal entity (needed for circles/arcs)
    // The workplane has a .normal field containing the handle to the 3D normal
    // We need to wrap it in a Slvs_Entity struct to pass to AddCircle/AddArc
    mapping.workplane_normal = solver.Slvs_Entity{
        h = mapping.workplane.normal,
        group = mapping.group,
        type = solver.SLVS_E_NORMAL_IN_3D,
        wrkpl = 0,  // Normal is not in a workplane
        point = [4]solver.Slvs_hEntity{0, 0, 0, 0},
        normal = 0,
        distance = 0,
        param = [4]solver.Slvs_hParam{0, 0, 0, 0},
    }

    // Add all points
    for point in s.points {
        slvs_point := solver.Slvs_AddPoint2D(mapping.group, point.x, point.y, mapping.workplane)
        mapping.point_map[point.id] = slvs_point

        // If point is fixed, add a dragged constraint
        if point.fixed {
            solver.Slvs_Dragged(mapping.group, slvs_point, mapping.workplane)
        }
    }

    // Add all entities (lines, circles, arcs)
    for entity in s.entities {
        slvs_entity, ok := convert_entity_to_slvs(entity, &mapping)
        if ok {
            // Extract ID from entity
            entity_id := get_entity_id(entity)
            if entity_id >= 0 {
                mapping.entity_map[entity_id] = slvs_entity
            }
        }
    }

    // Add all constraints
    for constraint in s.constraints {
        if !constraint.enabled {
            continue  // Skip disabled constraints
        }

        convert_constraint_to_slvs(constraint, &mapping)
    }

    return mapping, true
}

// Convert a single OhCAD entity to libslvs entity
convert_entity_to_slvs :: proc(entity: SketchEntity, mapping: ^SketchMapping) -> (solver.Slvs_Entity, bool) {
    switch e in entity {
    case SketchLine:
        p1, p1_ok := mapping.point_map[e.start_id]
        p2, p2_ok := mapping.point_map[e.end_id]
        if p1_ok && p2_ok {
            return solver.Slvs_AddLine2D(mapping.group, p1, p2, mapping.workplane), true
        }

    case SketchCircle:
        center, center_ok := mapping.point_map[e.center_id]
        if center_ok {
            // Use the workplane's 3D normal (circles require 3D normals, not 2D)
            // Create radius distance entity
            radius_entity := solver.Slvs_AddDistance(mapping.group, e.radius, mapping.workplane)

            // Store distance entity for later radius readback
            mapping.distance_map[e.id] = radius_entity

            // Create circle
            return solver.Slvs_AddCircle(mapping.group, mapping.workplane_normal, center, radius_entity, mapping.workplane), true
        }

    case SketchArc:
        center, center_ok := mapping.point_map[e.center_id]
        start, start_ok := mapping.point_map[e.start_id]
        end, end_ok := mapping.point_map[e.end_id]
        if center_ok && start_ok && end_ok {
            // Use the workplane's 3D normal (arcs require 3D normals, not 2D)
            return solver.Slvs_AddArc(mapping.group, mapping.workplane_normal, center, start, end, mapping.workplane), true
        }
    }

    return solver.SLVS_E_NONE, false
}

// Convert a single OhCAD constraint to libslvs constraint
convert_constraint_to_slvs :: proc(c: Constraint, mapping: ^SketchMapping) {
    #partial switch c.type {
    case .Coincident:
        if data, ok := c.data.(CoincidentData); ok {
            p1, p1_ok := mapping.point_map[data.point1_id]
            p2, p2_ok := mapping.point_map[data.point2_id]
            if p1_ok && p2_ok {
                solver.Slvs_Coincident(mapping.group, p1, p2, mapping.workplane)
            }
        }

    case .Distance:
        if data, ok := c.data.(DistanceData); ok {
            p1, p1_ok := mapping.point_map[data.point1_id]
            p2, p2_ok := mapping.point_map[data.point2_id]
            if p1_ok && p2_ok {
                solver.Slvs_Distance(mapping.group, p1, p2, data.distance, mapping.workplane)
            }
        }

    case .DistanceX:
        if data, ok := c.data.(DistanceXData); ok {
            p1, p1_ok := mapping.point_map[data.point1_id]
            p2, p2_ok := mapping.point_map[data.point2_id]
            if p1_ok && p2_ok {
                // Add horizontal distance constraint
                // Note: libslvs doesn't have direct X/Y distance, so we use projected distance
                // TODO: Implement proper X/Y distance using custom constraint combination
                solver.Slvs_Distance(mapping.group, p1, p2, data.distance, mapping.workplane)
            }
        }

    case .DistanceY:
        if data, ok := c.data.(DistanceYData); ok {
            p1, p1_ok := mapping.point_map[data.point1_id]
            p2, p2_ok := mapping.point_map[data.point2_id]
            if p1_ok && p2_ok {
                // Add vertical distance constraint
                // TODO: Implement proper X/Y distance
                solver.Slvs_Distance(mapping.group, p1, p2, data.distance, mapping.workplane)
            }
        }

    case .Diameter:
        if data, ok := c.data.(DiameterData); ok {
            circle, circle_ok := mapping.entity_map[data.circle_id]
            if circle_ok {
                solver.Slvs_Diameter(mapping.group, circle, data.diameter)
            }
        }

    case .Angle:
        if data, ok := c.data.(AngleData); ok {
            line1, line1_ok := mapping.entity_map[data.line1_id]
            line2, line2_ok := mapping.entity_map[data.line2_id]
            if line1_ok && line2_ok {
                solver.Slvs_Angle(mapping.group, line1, line2, data.angle, mapping.workplane, 0)
            }
        }

    case .Perpendicular:
        if data, ok := c.data.(PerpendicularData); ok {
            line1, line1_ok := mapping.entity_map[data.line1_id]
            line2, line2_ok := mapping.entity_map[data.line2_id]
            if line1_ok && line2_ok {
                solver.Slvs_Perpendicular(mapping.group, line1, line2, mapping.workplane, 0)
            }
        }

    case .Parallel:
        if data, ok := c.data.(ParallelData); ok {
            line1, line1_ok := mapping.entity_map[data.line1_id]
            line2, line2_ok := mapping.entity_map[data.line2_id]
            if line1_ok && line2_ok {
                solver.Slvs_Parallel(mapping.group, line1, line2, mapping.workplane)
            }
        }

    case .Horizontal:
        if data, ok := c.data.(HorizontalData); ok {
            line, line_ok := mapping.entity_map[data.line_id]
            if line_ok {
                solver.Slvs_Horizontal(mapping.group, line, mapping.workplane, solver.SLVS_E_NONE)
            }
        }

    case .Vertical:
        if data, ok := c.data.(VerticalData); ok {
            line, line_ok := mapping.entity_map[data.line_id]
            if line_ok {
                solver.Slvs_Vertical(mapping.group, line, mapping.workplane, solver.SLVS_E_NONE)
            }
        }

    case .Equal:
        if data, ok := c.data.(EqualData); ok {
            e1, e1_ok := mapping.entity_map[data.entity1_id]
            e2, e2_ok := mapping.entity_map[data.entity2_id]
            if e1_ok && e2_ok {
                solver.Slvs_Equal(mapping.group, e1, e2, mapping.workplane)
            }
        }

    case .Tangent:
        if data, ok := c.data.(TangentData); ok {
            e1, e1_ok := mapping.entity_map[data.entity1_id]
            e2, e2_ok := mapping.entity_map[data.entity2_id]
            if e1_ok && e2_ok {
                solver.Slvs_Tangent(mapping.group, e1, e2, mapping.workplane)
            }
        }

    case .PointOnLine:
        if data, ok := c.data.(PointOnLineData); ok {
            point, point_ok := mapping.point_map[data.point_id]
            line, line_ok := mapping.entity_map[data.line_id]
            if point_ok && line_ok {
                // Use AddConstraint for PT_ON_LINE
                solver.Slvs_AddConstraint(mapping.group, solver.SLVS_C_PT_ON_LINE, mapping.workplane, 0.0,
                                  point, solver.SLVS_E_NONE, line, solver.SLVS_E_NONE, solver.SLVS_E_NONE, solver.SLVS_E_NONE,
                                  0, 0)
            }
        }

    case .PointOnCircle:
        if data, ok := c.data.(PointOnCircleData); ok {
            point, point_ok := mapping.point_map[data.point_id]
            circle, circle_ok := mapping.entity_map[data.circle_id]
            if point_ok && circle_ok {
                // Use AddConstraint for PT_ON_CIRCLE
                solver.Slvs_AddConstraint(mapping.group, solver.SLVS_C_PT_ON_CIRCLE, mapping.workplane, 0.0,
                                  point, solver.SLVS_E_NONE, circle, solver.SLVS_E_NONE, solver.SLVS_E_NONE, solver.SLVS_E_NONE,
                                  0, 0)
            }
        }

    case .FixedPoint:
        if data, ok := c.data.(FixedPointData); ok {
            point, point_ok := mapping.point_map[data.point_id]
            if point_ok {
                solver.Slvs_Dragged(mapping.group, point, mapping.workplane)
            }
        }

    // TODO: Implement remaining constraint types as needed
    case: // Unsupported constraint types
        // fmt.printf("Warning: Constraint type %v not yet supported\n", c.type)
    }
}

// =============================================================================
// Update OhCAD sketch from solved libslvs state
// =============================================================================

update_sketch_from_slvs :: proc(s: ^Sketch2D, mapping: ^SketchMapping) {
    // Update all point positions from solved parameters
    for i in 0..<len(s.points) {
        point := &s.points[i]

        slvs_point, ok := mapping.point_map[point.id]
        if !ok {
            continue
        }

        // Get solved parameter values (u, v coordinates in workplane)
        point.x = solver.Slvs_GetParamValue(slvs_point.param[0])
        point.y = solver.Slvs_GetParamValue(slvs_point.param[1])
    }

    // Update circle radii from solved values
    for i in 0..<len(s.entities) {
        #partial switch &e in s.entities[i] {
        case SketchCircle:
            // Get the distance entity that holds the radius
            distance_entity, ok := mapping.distance_map[e.id]
            if ok && distance_entity.param[0] != 0 {
                // Get radius from the distance entity's first parameter
                e.radius = solver.Slvs_GetParamValue(distance_entity.param[0])
            }
        case:
            // Other entities update automatically via points
        }
    }
}

// =============================================================================
// Utilities
// =============================================================================

// Extract entity ID from union type
get_entity_id :: proc(entity: SketchEntity) -> int {
    #partial switch e in entity {
    case SketchLine:
        return e.id
    case SketchCircle:
        return e.id
    case SketchArc:
        return e.id
    }
    return -1
}

// Cleanup mapping resources
cleanup_mapping :: proc(mapping: ^SketchMapping) {
    delete(mapping.point_map)
    delete(mapping.entity_map)
    delete(mapping.distance_map)
}
