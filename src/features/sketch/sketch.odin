// features/sketch - 2D parametric sketching system
package ohcad_sketch

import "core:fmt"
import "core:math"
import m "../../core/math"
import geom "../../core/geometry"
import glsl "core:math/linalg/glsl"

// Sketch plane - defines the 2D coordinate system in 3D space
SketchPlane :: struct {
    origin: m.Vec3,      // Point on the plane
    x_axis: m.Vec3,      // Local X direction (normalized)
    y_axis: m.Vec3,      // Local Y direction (normalized)
    normal: m.Vec3,      // Plane normal (normalized)
}

// 2D point in sketch coordinates
SketchPoint :: struct {
    id: int,
    x: f64,
    y: f64,
    fixed: bool,  // True if position is fixed (not solved by constraints)
}

// Sketch entity types
SketchEntityType :: enum {
    Line,
    Circle,
    Arc,
    Point,
}

// Sketch line (between two points)
SketchLine :: struct {
    id: int,
    start_id: int,  // ID of start point
    end_id: int,    // ID of end point
}

// Sketch circle (center + radius)
SketchCircle :: struct {
    id: int,
    center_id: int,  // ID of center point
    radius: f64,
}

// Sketch arc (center + start/end angles + radius)
SketchArc :: struct {
    id: int,
    center_id: int,   // ID of center point
    start_id: int,    // ID of start point
    end_id: int,      // ID of end point
    radius: f64,
}

// Union type for sketch entities
SketchEntity :: union {
    SketchLine,
    SketchCircle,
    SketchArc,
}

// Sketch tool types
SketchTool :: enum {
    Select,
    Line,
    Circle,
    Arc,
}

// 2D Sketch data structure
Sketch2D :: struct {
    name: string,
    plane: SketchPlane,

    // Geometry
    points: [dynamic]SketchPoint,
    entities: [dynamic]SketchEntity,

    // Constraints
    constraints: [dynamic]Constraint,

    // ID counters
    next_point_id: int,
    next_entity_id: int,
    next_constraint_id: int,

    // Selection state
    selected_entity: int,  // -1 if nothing selected

    // Tool state
    current_tool: SketchTool,
    temp_point: m.Vec2,          // Temporary point for preview
    temp_point_valid: bool,      // Is temp point valid?
    first_point_id: int,         // First point in line tool (-1 if none)
}

// =============================================================================
// Sketch Plane Operations
// =============================================================================

// Create a sketch plane from origin and normal
sketch_plane_from_normal :: proc(origin, normal: m.Vec3) -> SketchPlane {
    plane: SketchPlane
    plane.origin = origin
    plane.normal = glsl.normalize(normal)

    // Generate orthonormal basis
    // Choose an arbitrary perpendicular vector
    up := m.Vec3{0, 1, 0}
    if math.abs(glsl.dot(plane.normal, up)) > 0.9 {
        up = m.Vec3{1, 0, 0}
    }

    plane.x_axis = glsl.normalize(glsl.cross(up, plane.normal))
    plane.y_axis = glsl.normalize(glsl.cross(plane.normal, plane.x_axis))

    return plane
}

// Create XY plane at origin
sketch_plane_xy :: proc() -> SketchPlane {
    return SketchPlane{
        origin = m.Vec3{0, 0, 0},
        x_axis = m.Vec3{1, 0, 0},
        y_axis = m.Vec3{0, 1, 0},
        normal = m.Vec3{0, 0, 1},
    }
}

// Create XZ plane at origin
sketch_plane_xz :: proc() -> SketchPlane {
    return SketchPlane{
        origin = m.Vec3{0, 0, 0},
        x_axis = m.Vec3{1, 0, 0},
        y_axis = m.Vec3{0, 0, 1},
        normal = m.Vec3{0, 1, 0},
    }
}

// Create YZ plane at origin
sketch_plane_yz :: proc() -> SketchPlane {
    return SketchPlane{
        origin = m.Vec3{0, 0, 0},
        x_axis = m.Vec3{0, 1, 0},
        y_axis = m.Vec3{0, 0, 1},
        normal = m.Vec3{1, 0, 0},
    }
}

// Convert 2D sketch coordinates to 3D world coordinates
sketch_to_world :: proc(plane: ^SketchPlane, point: m.Vec2) -> m.Vec3 {
    return plane.origin + plane.x_axis * point.x + plane.y_axis * point.y
}

// Convert 3D world coordinates to 2D sketch coordinates
world_to_sketch :: proc(plane: ^SketchPlane, point: m.Vec3) -> m.Vec2 {
    offset := point - plane.origin
    return m.Vec2{
        glsl.dot(offset, plane.x_axis),
        glsl.dot(offset, plane.y_axis),
    }
}

// =============================================================================
// Sketch Operations
// =============================================================================

// Initialize a new sketch
sketch_init :: proc(name: string, plane: SketchPlane) -> Sketch2D {
    return Sketch2D{
        name = name,
        plane = plane,
        points = make([dynamic]SketchPoint),
        entities = make([dynamic]SketchEntity),
        constraints = make([dynamic]Constraint),
        next_point_id = 0,
        next_entity_id = 0,
        next_constraint_id = 0,
        selected_entity = -1,
        current_tool = .Select,
        temp_point = m.Vec2{0, 0},
        temp_point_valid = false,
        first_point_id = -1,
    }
}

// Destroy sketch and free memory
sketch_destroy :: proc(sketch: ^Sketch2D) {
    delete(sketch.points)
    delete(sketch.entities)
    delete(sketch.constraints)
}

// Add a point to the sketch
sketch_add_point :: proc(sketch: ^Sketch2D, x, y: f64, fixed := false) -> int {
    point := SketchPoint{
        id = sketch.next_point_id,
        x = x,
        y = y,
        fixed = fixed,
    }
    append(&sketch.points, point)
    sketch.next_point_id += 1
    return point.id
}

// Get point by ID
sketch_get_point :: proc(sketch: ^Sketch2D, id: int) -> ^SketchPoint {
    for &point in sketch.points {
        if point.id == id {
            return &point
        }
    }
    return nil
}

// Add a line to the sketch
sketch_add_line :: proc(sketch: ^Sketch2D, start_id, end_id: int) -> int {
    line := SketchLine{
        id = sketch.next_entity_id,
        start_id = start_id,
        end_id = end_id,
    }
    append(&sketch.entities, line)
    sketch.next_entity_id += 1
    return line.id
}

// Add a circle to the sketch
sketch_add_circle :: proc(sketch: ^Sketch2D, center_id: int, radius: f64) -> int {
    circle := SketchCircle{
        id = sketch.next_entity_id,
        center_id = center_id,
        radius = radius,
    }
    append(&sketch.entities, circle)
    sketch.next_entity_id += 1
    return circle.id
}

// Add an arc to the sketch
sketch_add_arc :: proc(sketch: ^Sketch2D, center_id, start_id, end_id: int, radius: f64) -> int {
    arc := SketchArc{
        id = sketch.next_entity_id,
        center_id = center_id,
        start_id = start_id,
        end_id = end_id,
        radius = radius,
    }
    append(&sketch.entities, arc)
    sketch.next_entity_id += 1
    return arc.id
}

// Delete entity by index
sketch_delete_entity :: proc(sketch: ^Sketch2D, index: int) {
    if index >= 0 && index < len(sketch.entities) {
        ordered_remove(&sketch.entities, index)
        if sketch.selected_entity == index {
            sketch.selected_entity = -1
        }
    }
}

// Get entity count
sketch_entity_count :: proc(sketch: ^Sketch2D) -> int {
    return len(sketch.entities)
}

// Get point count
sketch_point_count :: proc(sketch: ^Sketch2D) -> int {
    return len(sketch.points)
}

// Print sketch summary
sketch_print_info :: proc(sketch: ^Sketch2D) {
    fmt.printf("Sketch '%s':\n", sketch.name)
    fmt.printf("  Points: %d\n", len(sketch.points))
    fmt.printf("  Entities: %d\n", len(sketch.entities))

    line_count := 0
    circle_count := 0
    arc_count := 0

    for entity in sketch.entities {
        switch _ in entity {
        case SketchLine:
            line_count += 1
        case SketchCircle:
            circle_count += 1
        case SketchArc:
            arc_count += 1
        }
    }

    fmt.printf("    Lines: %d\n", line_count)
    fmt.printf("    Circles: %d\n", circle_count)
    fmt.printf("    Arcs: %d\n", arc_count)
}
