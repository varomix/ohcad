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
    Constraint,  // NEW: Hovering over a constraint (dimension text/icon)
    RadiusHandle,  // NEW: Hovering over circle radius handle (Week 12.3 - Task 2)
    LineEndpointHandle,  // NEW: Hovering over line endpoint handle (Week 12.3 - Task 3)
}

// Hover state - tracks what entity is currently hovered
HoverState :: struct {
    entity_type: HoverEntityType,
    entity_id: int,       // ID of the hovered entity (-1 if none)
    point_id: int,        // For points, or specific point on line/arc (-1 if none)
    constraint_id: int,   // NEW: ID of hovered constraint (-1 if none)
    distance: f64,        // Distance from cursor to entity (for debugging)
}

// Hit testing tolerance (in screen pixels)
// These are multiplied by pixel_size_world to get world-space distance
HOVER_TOLERANCE_POINT_PIXELS :: 10.0    // Pixels for point hover detection
HOVER_TOLERANCE_EDGE_PIXELS :: 8.0      // Pixels for edge hover detection
HOVER_TOLERANCE_CONSTRAINT_PIXELS :: 15.0  // Pixels for constraint hover detection

// Detect hover for point under cursor
detect_hover_point :: proc(sketch: ^Sketch2D, cursor_pos: m.Vec2, tolerance: f64) -> (int, f64) {
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
detect_hover_line :: proc(sketch: ^Sketch2D, line: SketchLine, cursor_pos: m.Vec2, tolerance: f64) -> (bool, f64) {
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
detect_hover_circle :: proc(sketch: ^Sketch2D, circle: SketchCircle, cursor_pos: m.Vec2, tolerance: f64) -> (bool, f64) {
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
detect_hover_arc :: proc(sketch: ^Sketch2D, arc: SketchArc, cursor_pos: m.Vec2, tolerance: f64) -> (bool, f64) {
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

// Detect hover for constraint (dimension/icon) under cursor
detect_hover_constraint :: proc(sketch: ^Sketch2D, cursor_pos: m.Vec2, tolerance: f64, pixel_size_world: f64) -> (int, f64) {
    if sketch.constraints == nil || len(sketch.constraints) == 0 {
        return -1, 0.0
    }

    closest_id := -1
    closest_dist := tolerance

    // SCREEN-SPACE ICON SIZE: Match the rendering (24 pixels icon, 40 pixels offset)
    icon_size_pixels := 24.0
    offset_pixels := 40.0
    icon_size_world := pixel_size_world * icon_size_pixels
    offset_world := pixel_size_world * offset_pixels

    for constraint in sketch.constraints {
        if !constraint.enabled do continue

        switch data in constraint.data {
        case DistanceData:
            // Check distance to dimension line
            if data.point1_id < 0 || data.point1_id >= len(sketch.points) do continue
            if data.point2_id < 0 || data.point2_id >= len(sketch.points) do continue

            p1 := sketch_get_point(sketch, data.point1_id)
            p2 := sketch_get_point(sketch, data.point2_id)
            if p1 == nil || p2 == nil do continue

            p1_2d := m.Vec2{p1.x, p1.y}
            p2_2d := m.Vec2{p2.x, p2.y}

            // Calculate dimension line position
            edge_vec := p2_2d - p1_2d
            edge_len := glsl.length(edge_vec)
            if edge_len < 1e-10 do continue

            edge_dir := edge_vec / edge_len
            perp_dir := m.Vec2{-edge_dir.y, edge_dir.x}

            mid := (p1_2d + p2_2d) * 0.5
            to_offset := data.offset - mid
            offset_distance := glsl.dot(to_offset, perp_dir)

            MIN_OFFSET :: 0.3
            if glsl.abs(offset_distance) < MIN_OFFSET {
                offset_distance = MIN_OFFSET * glsl.sign(offset_distance)
                if offset_distance == 0 {
                    offset_distance = MIN_OFFSET
                }
            }

            dim1_2d := p1_2d + perp_dir * offset_distance
            dim2_2d := p2_2d + perp_dir * offset_distance

            // Check distance to dimension line
            dist := distance_point_to_line_segment(cursor_pos, dim1_2d, dim2_2d)

            if dist < closest_dist {
                closest_dist = dist
                closest_id = constraint.id
            }

        case AngleData:
            // Check distance to angular dimension arc
            if data.line1_id < 0 || data.line1_id >= len(sketch.entities) do continue
            if data.line2_id < 0 || data.line2_id >= len(sketch.entities) do continue

            line1 := sketch.entities[data.line1_id].(SketchLine)
            line2 := sketch.entities[data.line2_id].(SketchLine)

            // Get line endpoints
            p1_start := sketch_get_point(sketch, line1.start_id)
            p1_end := sketch_get_point(sketch, line1.end_id)
            p2_start := sketch_get_point(sketch, line2.start_id)
            p2_end := sketch_get_point(sketch, line2.end_id)

            if p1_start == nil || p1_end == nil || p2_start == nil || p2_end == nil do continue

            // Check distance to arc or text position (use offset as approximation)
            // For simplicity, check distance to the offset point (where the text is)
            dist := glsl.length(cursor_pos - data.offset)

            if dist < closest_dist {
                closest_dist = dist
                closest_id = constraint.id
            }

        case DistanceXData:
            // Check distance to horizontal dimension line
            if data.point1_id < 0 || data.point1_id >= len(sketch.points) do continue
            if data.point2_id < 0 || data.point2_id >= len(sketch.points) do continue

            p1 := sketch_get_point(sketch, data.point1_id)
            p2 := sketch_get_point(sketch, data.point2_id)
            if p1 == nil || p2 == nil do continue

            // Horizontal dimension - dimension line is at offset.y, extends from p1.x to p2.x
            dim_y := data.offset.y
            dim1_2d := m.Vec2{p1.x, dim_y}
            dim2_2d := m.Vec2{p2.x, dim_y}

            // Check distance to dimension line
            dist := distance_point_to_line_segment(cursor_pos, dim1_2d, dim2_2d)

            if dist < closest_dist {
                closest_dist = dist
                closest_id = constraint.id
            }

        case DistanceYData:
            // Check distance to vertical dimension line
            if data.point1_id < 0 || data.point1_id >= len(sketch.points) do continue
            if data.point2_id < 0 || data.point2_id >= len(sketch.points) do continue

            p1 := sketch_get_point(sketch, data.point1_id)
            p2 := sketch_get_point(sketch, data.point2_id)
            if p1 == nil || p2 == nil do continue

            // Vertical dimension - dimension line is at offset.x, extends from p1.y to p2.y
            dim_x := data.offset.x
            dim1_2d := m.Vec2{dim_x, p1.y}
            dim2_2d := m.Vec2{dim_x, p2.y}

            // Check distance to dimension line
            dist := distance_point_to_line_segment(cursor_pos, dim1_2d, dim2_2d)

            if dist < closest_dist {
                closest_dist = dist
                closest_id = constraint.id
            }

        case HorizontalData:
            // Check distance to horizontal constraint icon
            if data.line_id < 0 || data.line_id >= len(sketch.entities) do continue

            entity := sketch.entities[data.line_id]
            line, ok := entity.(SketchLine)
            if !ok do continue

            // Get line midpoint
            p1 := sketch_get_point(sketch, line.start_id)
            p2 := sketch_get_point(sketch, line.end_id)
            if p1 == nil || p2 == nil do continue

            mid_2d := m.Vec2{(p1.x + p2.x) * 0.5, (p1.y + p2.y) * 0.5}

            // Calculate line direction in sketch space
            line_dir := m.Vec2{p2.x - p1.x, p2.y - p1.y}
            line_len := glsl.length(line_dir)

            // Offset perpendicular to the line (same logic as rendering)
            perpendicular := m.Vec2{0, 1}
            if line_len > 0.001 {
                line_dir = line_dir / line_len
                // Perpendicular vector (rotate 90° CCW): (x,y) → (-y,x)
                perpendicular = m.Vec2{-line_dir.y, line_dir.x}
            }

            icon_center := mid_2d + perpendicular * offset_world

            // Check distance to icon center (circular hit area)
            dist := glsl.length(cursor_pos - icon_center)

            if dist < closest_dist {
                closest_dist = dist
                closest_id = constraint.id
            }

        case VerticalData:
            // Check distance to vertical constraint icon
            if data.line_id < 0 || data.line_id >= len(sketch.entities) do continue

            entity := sketch.entities[data.line_id]
            line, ok := entity.(SketchLine)
            if !ok do continue

            // Get line midpoint
            p1 := sketch_get_point(sketch, line.start_id)
            p2 := sketch_get_point(sketch, line.end_id)
            if p1 == nil || p2 == nil do continue

            mid_2d := m.Vec2{(p1.x + p2.x) * 0.5, (p1.y + p2.y) * 0.5}

            // Calculate line direction in sketch space
            line_dir := m.Vec2{p2.x - p1.x, p2.y - p1.y}
            line_len := glsl.length(line_dir)

            // Offset perpendicular to the line (same logic as rendering)
            perpendicular := m.Vec2{1, 0}
            if line_len > 0.001 {
                line_dir = line_dir / line_len
                // Perpendicular vector (rotate 90° CCW): (x,y) → (-y,x)
                perpendicular = m.Vec2{-line_dir.y, line_dir.x}
            }

            icon_center := mid_2d + perpendicular * offset_world

            // Check distance to icon center (circular hit area)
            dist := glsl.length(cursor_pos - icon_center)

            if dist < closest_dist {
                closest_dist = dist
                closest_id = constraint.id
            }

        case DiameterData:
            // Check distance to diameter dimension line
            if data.circle_id < 0 || data.circle_id >= len(sketch.entities) do continue

            entity := sketch.entities[data.circle_id]
            circle, ok := entity.(SketchCircle)
            if !ok do continue

            center_pt := sketch_get_point(sketch, circle.center_id)
            if center_pt == nil do continue

            center_2d := m.Vec2{center_pt.x, center_pt.y}

            // Calculate diameter line direction from center to offset position
            offset_vec := data.offset - center_2d
            offset_len := glsl.length(offset_vec)

            // Default to horizontal if offset is at center
            dim_dir: m.Vec2
            if offset_len < 1e-10 {
                dim_dir = m.Vec2{1, 0}
            } else {
                dim_dir = offset_vec / offset_len
            }

            // Calculate two points on circle edge along diameter line
            edge1_2d := center_2d - dim_dir * circle.radius
            edge2_2d := center_2d + dim_dir * circle.radius

            // Check distance to dimension line
            dist := distance_point_to_line_segment(cursor_pos, edge1_2d, edge2_2d)

            if dist < closest_dist {
                closest_dist = dist
                closest_id = constraint.id
            }

        case CoincidentData, PerpendicularData, ParallelData, TangentData, EqualData,
             PointOnLineData, PointOnCircleData, FixedPointData:
            // Could add hit testing for other constraint types here
            // For now, only distance, angular, horizontal, and vertical are clickable
        }
    }

    return closest_id, closest_dist
}

// Detect hover for circle radius handle (Week 12.3 - Task 2)
// Returns (entity_index, is_hovered, distance)
detect_hover_radius_handle :: proc(sketch: ^Sketch2D, cursor_pos: m.Vec2, tolerance: f64) -> (int, bool, f64) {
    closest_id := -1
    closest_dist := tolerance
    found := false

    // Only check selected circles (handle only visible on selected circles)
    if sketch.selected_entity < 0 || sketch.selected_entity >= len(sketch.entities) {
        return -1, false, 0.0
    }

    entity := sketch.entities[sketch.selected_entity]
    circle, ok := entity.(SketchCircle)
    if !ok {
        return -1, false, 0.0
    }

    // Check if circle has a diameter constraint - if so, don't show radius handle
    // (dimension takes precedence over manual scaling)
    if sketch.constraints != nil {
        for constraint in sketch.constraints {
            if constraint.enabled {
                if diameter_data, is_diameter := constraint.data.(DiameterData); is_diameter {
                    if diameter_data.circle_id == sketch.selected_entity {
                        // This circle has a diameter constraint - don't allow radius handle hover
                        return -1, false, 0.0
                    }
                }
            }
        }
    }

    // Calculate radius handle position (on the right side of circle)
    center_pt := sketch_get_point(sketch, circle.center_id)
    if center_pt == nil {
        return -1, false, 0.0
    }

    center_pos := m.Vec2{center_pt.x, center_pt.y}

    // Radius handle is at the rightmost point of the circle (angle = 0)
    handle_pos := m.Vec2{center_pos.x + circle.radius, center_pos.y}

    // Check distance to handle
    dist := glsl.length(cursor_pos - handle_pos)

    if dist < tolerance {
        return sketch.selected_entity, true, dist
    }

    return -1, false, dist
}

// Detect hover for line endpoint handles (Week 12.3 - Task 3)
// Returns (entity_index, point_id, is_hovered, distance)
detect_hover_line_endpoint_handle :: proc(sketch: ^Sketch2D, cursor_pos: m.Vec2, tolerance: f64) -> (int, int, bool, f64) {
    // Only check selected lines (handles only visible on selected lines)
    if sketch.selected_entity < 0 || sketch.selected_entity >= len(sketch.entities) {
        return -1, -1, false, 0.0
    }

    entity := sketch.entities[sketch.selected_entity]
    line, ok := entity.(SketchLine)
    if !ok {
        return -1, -1, false, 0.0
    }

    // Get both endpoint positions
    start_pt := sketch_get_point(sketch, line.start_id)
    end_pt := sketch_get_point(sketch, line.end_id)
    if start_pt == nil || end_pt == nil {
        return -1, -1, false, 0.0
    }

    start_pos := m.Vec2{start_pt.x, start_pt.y}
    end_pos := m.Vec2{end_pt.x, end_pt.y}

    // Check distance to both endpoints
    dist_to_start := glsl.length(cursor_pos - start_pos)
    dist_to_end := glsl.length(cursor_pos - end_pos)

    // Find closest endpoint
    if dist_to_start < tolerance && dist_to_start <= dist_to_end {
        // Hovering over start point
        return sketch.selected_entity, line.start_id, true, dist_to_start
    } else if dist_to_end < tolerance {
        // Hovering over end point
        return sketch.selected_entity, line.end_id, true, dist_to_end
    }

    return -1, -1, false, 0.0
}

// Update hover state based on cursor position
// pixel_size_world: size of one screen pixel in world units (for zoom-independent tolerances)
sketch_update_hover :: proc(sketch: ^Sketch2D, cursor_pos: m.Vec2, pixel_size_world: f64 = 0.01) -> HoverState {
    hover := HoverState{
        entity_type = .None,
        entity_id = -1,
        point_id = -1,
        constraint_id = -1,
        distance = 0.0,
    }

    // Calculate screen-space constant tolerances
    point_tolerance := pixel_size_world * HOVER_TOLERANCE_POINT_PIXELS
    edge_tolerance := pixel_size_world * HOVER_TOLERANCE_EDGE_PIXELS
    constraint_tolerance := pixel_size_world * HOVER_TOLERANCE_CONSTRAINT_PIXELS

    // First check for line endpoint handles (Week 12.3 - Task 3)
    // This has highest priority when a line is selected
    line_entity_id, endpoint_point_id, is_endpoint_hovered, endpoint_dist := detect_hover_line_endpoint_handle(sketch, cursor_pos, point_tolerance)
    if is_endpoint_hovered {
        hover.entity_type = .LineEndpointHandle
        hover.entity_id = line_entity_id // Line entity index
        hover.point_id = endpoint_point_id // Which endpoint (start_id or end_id)
        hover.distance = endpoint_dist
        return hover
    }

    // Then check for radius handle hover (Week 12.3 - Task 2)
    // This has high priority when a circle is selected
    radius_handle_id, is_handle_hovered, handle_dist := detect_hover_radius_handle(sketch, cursor_pos, point_tolerance)
    if is_handle_hovered {
        hover.entity_type = .RadiusHandle
        hover.entity_id = radius_handle_id // Circle entity index
        hover.distance = handle_dist
        return hover
    }

    // Then check for point hover (high priority - easier to select)
    point_id, point_dist := detect_hover_point(sketch, cursor_pos, point_tolerance)
    if point_id >= 0 {
        hover.entity_type = .Point
        hover.point_id = point_id
        hover.distance = point_dist
        return hover
    }

    // Then check for edge hover
    closest_edge_dist := edge_tolerance
    closest_edge_id := -1
    closest_edge_type := HoverEntityType.None

    for entity, idx in sketch.entities {
        switch e in entity {
        case SketchLine:
            is_hover, dist := detect_hover_line(sketch, e, cursor_pos, edge_tolerance)
            if is_hover && dist < closest_edge_dist {
                closest_edge_dist = dist
                closest_edge_id = idx
                closest_edge_type = .Line
            }

        case SketchCircle:
            is_hover, dist := detect_hover_circle(sketch, e, cursor_pos, edge_tolerance)
            if is_hover && dist < closest_edge_dist {
                closest_edge_dist = dist
                closest_edge_id = idx
                closest_edge_type = .Circle
            }

        case SketchArc:
            is_hover, dist := detect_hover_arc(sketch, e, cursor_pos, edge_tolerance)
            if is_hover && dist < closest_edge_dist {
                closest_edge_dist = dist
                closest_edge_id = idx
                closest_edge_type = .Arc
            }
        }
    }

    // Check for constraint hover (dimensions, icons, etc.)
    constraint_id, constraint_dist := detect_hover_constraint(sketch, cursor_pos, constraint_tolerance, pixel_size_world)

    // Choose the closest between edge and constraint
    // Edges have priority if they're closer
    if closest_edge_id >= 0 && (constraint_id < 0 || closest_edge_dist < constraint_dist) {
        hover.entity_type = closest_edge_type
        hover.entity_id = closest_edge_id
        hover.distance = closest_edge_dist
    } else if constraint_id >= 0 {
        hover.entity_type = .Constraint
        hover.constraint_id = constraint_id
        hover.distance = constraint_dist
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
    #partial switch hover.entity_type {
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
