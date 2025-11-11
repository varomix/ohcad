// features/sketch - Hover detection and highlighting system
package ohcad_sketch

import "core:fmt"
import "core:math"
import m "../../core/math"
import glsl "core:math/linalg/glsl"

// Hover entity types
HoverEntityType :: enum {
    None,
    Point,
    Line,
    Circle,
    Arc,
}

// Hover state - tracks what entity is currently hovered
HoverState :: struct {
    entity_type: HoverEntityType,
    entity_id: int,       // ID of the hovered entity (-1 if none)
    point_id: int,        // For points, or specific point on line/arc (-1 if none)
    distance: f64,        // Distance from cursor to entity (for debugging)
}

// Hit testing tolerance (in sketch units)
HOVER_TOLERANCE_POINT :: 0.15    // Distance to detect point hover
HOVER_TOLERANCE_EDGE :: 0.10     // Distance to detect edge hover

// Detect hover for point under cursor
detect_hover_point :: proc(sketch: ^Sketch2D, cursor_pos: m.Vec2, tolerance: f64 = HOVER_TOLERANCE_POINT) -> (int, f64) {
    closest_id := -1
    closest_dist := tolerance

    for point in sketch.points {
        point_pos := m.Vec2{point.x, point.y}
        dist := glsl.length(cursor_pos - point_pos)

        if dist < closest_dist {
            closest_dist = dist
            closest_id = point.id
        }
    }

    return closest_id, closest_dist
}

// Detect hover for line edge under cursor
detect_hover_line :: proc(sketch: ^Sketch2D, line: SketchLine, cursor_pos: m.Vec2, tolerance: f64 = HOVER_TOLERANCE_EDGE) -> (bool, f64) {
    start_pt := sketch_get_point(sketch, line.start_id)
    end_pt := sketch_get_point(sketch, line.end_id)

    if start_pt == nil || end_pt == nil {
        return false, 0.0
    }

    start_pos := m.Vec2{start_pt.x, start_pt.y}
    end_pos := m.Vec2{end_pt.x, end_pt.y}

    // Calculate distance from point to line segment
    dist := distance_point_to_line_segment(cursor_pos, start_pos, end_pos)

    return dist <= tolerance, dist
}

// Detect hover for circle edge under cursor
detect_hover_circle :: proc(sketch: ^Sketch2D, circle: SketchCircle, cursor_pos: m.Vec2, tolerance: f64 = HOVER_TOLERANCE_EDGE) -> (bool, f64) {
    center_pt := sketch_get_point(sketch, circle.center_id)
    if center_pt == nil {
        return false, 0.0
    }

    center_pos := m.Vec2{center_pt.x, center_pt.y}
    dist_to_center := glsl.length(cursor_pos - center_pos)

    // Distance from cursor to circle edge
    dist := math.abs(dist_to_center - circle.radius)

    return dist <= tolerance, dist
}

// Detect hover for arc edge under cursor
detect_hover_arc :: proc(sketch: ^Sketch2D, arc: SketchArc, cursor_pos: m.Vec2, tolerance: f64 = HOVER_TOLERANCE_EDGE) -> (bool, f64) {
    center_pt := sketch_get_point(sketch, arc.center_id)
    start_pt := sketch_get_point(sketch, arc.start_id)
    end_pt := sketch_get_point(sketch, arc.end_id)

    if center_pt == nil || start_pt == nil || end_pt == nil {
        return false, 0.0
    }

    center_pos := m.Vec2{center_pt.x, center_pt.y}
    start_pos := m.Vec2{start_pt.x, start_pt.y}
    end_pos := m.Vec2{end_pt.x, end_pt.y}

    // Check if cursor is near the arc radius
    dist_to_center := glsl.length(cursor_pos - center_pos)
    dist_to_edge := math.abs(dist_to_center - arc.radius)

    if dist_to_edge > tolerance {
        return false, dist_to_edge
    }

    // Check if cursor is within the arc's angular range
    cursor_angle := math.atan2(cursor_pos.y - center_pos.y, cursor_pos.x - center_pos.x)
    start_angle := math.atan2(start_pos.y - center_pos.y, start_pos.x - center_pos.x)
    end_angle := math.atan2(end_pos.y - center_pos.y, end_pos.x - center_pos.x)

    // Normalize angles to [0, 2π]
    normalize_angle :: proc(angle: f64) -> f64 {
        a := angle
        for a < 0 {
            a += 2.0 * math.PI
        }
        for a >= 2.0 * math.PI {
            a -= 2.0 * math.PI
        }
        return a
    }

    cursor_norm := normalize_angle(cursor_angle)
    start_norm := normalize_angle(start_angle)
    end_norm := normalize_angle(end_angle)

    // Check if angle is in range (handle wrap-around)
    in_range := false
    if start_norm <= end_norm {
        in_range = cursor_norm >= start_norm && cursor_norm <= end_norm
    } else {
        in_range = cursor_norm >= start_norm || cursor_norm <= end_norm
    }

    return in_range, dist_to_edge
}

// Update hover state based on cursor position
sketch_update_hover :: proc(sketch: ^Sketch2D, cursor_pos: m.Vec2) -> HoverState {
    hover := HoverState{
        entity_type = .None,
        entity_id = -1,
        point_id = -1,
        distance = 0.0,
    }

    // First check for point hover (highest priority - easier to select)
    point_id, point_dist := detect_hover_point(sketch, cursor_pos)
    if point_id >= 0 {
        hover.entity_type = .Point
        hover.point_id = point_id
        hover.distance = point_dist
        return hover
    }

    // Then check for edge hover
    closest_edge_dist := HOVER_TOLERANCE_EDGE
    closest_edge_id := -1
    closest_edge_type := HoverEntityType.None

    for entity, idx in sketch.entities {
        switch e in entity {
        case SketchLine:
            is_hover, dist := detect_hover_line(sketch, e, cursor_pos)
            if is_hover && dist < closest_edge_dist {
                closest_edge_dist = dist
                closest_edge_id = idx
                closest_edge_type = .Line
            }

        case SketchCircle:
            is_hover, dist := detect_hover_circle(sketch, e, cursor_pos)
            if is_hover && dist < closest_edge_dist {
                closest_edge_dist = dist
                closest_edge_id = idx
                closest_edge_type = .Circle
            }

        case SketchArc:
            is_hover, dist := detect_hover_arc(sketch, e, cursor_pos)
            if is_hover && dist < closest_edge_dist {
                closest_edge_dist = dist
                closest_edge_id = idx
                closest_edge_type = .Arc
            }
        }
    }

    if closest_edge_id >= 0 {
        hover.entity_type = closest_edge_type
        hover.entity_id = closest_edge_id
        hover.distance = closest_edge_dist
    }

    return hover
}

// Helper: Calculate distance from point to line segment
distance_point_to_line_segment :: proc(point, line_start, line_end: m.Vec2) -> f64 {
    line_vec := line_end - line_start
    line_len_sq := glsl.dot(line_vec, line_vec)

    if line_len_sq < 1e-10 {
        // Line segment is a point
        return glsl.length(point - line_start)
    }

    // Project point onto line
    point_vec := point - line_start
    t := glsl.dot(point_vec, line_vec) / line_len_sq

    // Clamp t to [0, 1] to stay on segment
    t = glsl.clamp(t, 0.0, 1.0)

    // Find closest point on segment
    closest := line_start + line_vec * t

    return glsl.length(point - closest)
}

// Get hover info string for display
get_hover_info :: proc(sketch: ^Sketch2D, hover: HoverState) -> string {
    switch hover.entity_type {
    case .None:
        return ""

    case .Point:
        point := sketch_get_point(sketch, hover.point_id)
        if point == nil do return ""
        return fmt.tprintf("Point #%d (x=%.2f, y=%.2f)", hover.point_id, point.x, point.y)

    case .Line:
        if hover.entity_id < 0 || hover.entity_id >= len(sketch.entities) {
            return ""
        }
        line, ok := sketch.entities[hover.entity_id].(SketchLine)
        if !ok do return ""

        start_pt := sketch_get_point(sketch, line.start_id)
        end_pt := sketch_get_point(sketch, line.end_id)
        if start_pt == nil || end_pt == nil do return ""

        start_pos := m.Vec2{start_pt.x, start_pt.y}
        end_pos := m.Vec2{end_pt.x, end_pt.y}
        length := glsl.length(end_pos - start_pos)

        return fmt.tprintf("Line #%d (length: %.2f)", hover.entity_id, length)

    case .Circle:
        if hover.entity_id < 0 || hover.entity_id >= len(sketch.entities) {
            return ""
        }
        circle, ok := sketch.entities[hover.entity_id].(SketchCircle)
        if !ok do return ""

        return fmt.tprintf("Circle #%d (radius: %.2f)", hover.entity_id, circle.radius)

    case .Arc:
        if hover.entity_id < 0 || hover.entity_id >= len(sketch.entities) {
            return ""
        }
        arc, ok := sketch.entities[hover.entity_id].(SketchArc)
        if !ok do return ""

        return fmt.tprintf("Arc #%d (radius: %.2f)", hover.entity_id, arc.radius)
    }

    return ""
}
