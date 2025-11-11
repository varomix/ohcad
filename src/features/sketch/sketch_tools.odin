// features/sketch - Interactive sketch tool operations
package ohcad_sketch

import "core:fmt"
import m "../../core/math"
import glfw "vendor:glfw"
import glsl "core:math/linalg/glsl"

// Set the current tool
sketch_set_tool :: proc(sketch: ^Sketch2D, tool: SketchTool) {
    sketch.current_tool = tool
    sketch.temp_point_valid = false
    sketch.first_point_id = -1
}

// Update temporary cursor position in sketch coordinates
sketch_update_cursor :: proc(sketch: ^Sketch2D, cursor_world: m.Vec3) {
    sketch.temp_point = world_to_sketch(&sketch.plane, cursor_world)
    sketch.temp_point_valid = true
}

// Handle mouse click for sketch tools
sketch_handle_click :: proc(sketch: ^Sketch2D, click_pos: m.Vec2) {
    switch sketch.current_tool {
    case .Select:
        sketch_select_at(sketch, click_pos)

    case .Line:
        handle_line_tool_click(sketch, click_pos)

    case .Circle:
        handle_circle_tool_click(sketch, click_pos)

    case .Arc:
        // TODO: Arc tool
        fmt.println("Arc tool - not yet implemented")

    case .Dimension:
        handle_dimension_tool_click(sketch, click_pos)
    }
}

// Handle line tool clicks
handle_line_tool_click :: proc(sketch: ^Sketch2D, click_pos: m.Vec2) {
    // Snap threshold - if clicking within 0.2 units of existing point, snap to it
    SNAP_THRESHOLD :: 0.2
    // Auto-close threshold - if clicking within 0.15 units of start point, auto-close shape
    AUTO_CLOSE_THRESHOLD :: 0.15

    if sketch.first_point_id == -1 {
        // First click - try to snap to existing point, or create new one
        snapped_id, found := sketch_find_nearest_point(sketch, click_pos, SNAP_THRESHOLD)

        if found {
            sketch.first_point_id = snapped_id
            sketch.chain_start_point_id = snapped_id  // Remember the original start point
            pt := sketch_get_point(sketch, snapped_id)
            fmt.printf("Line tool: Snapped to existing point %d at (%.3f, %.3f)\n", snapped_id, pt.x, pt.y)
        } else {
            sketch.first_point_id = sketch_add_point(sketch, click_pos.x, click_pos.y)
            sketch.chain_start_point_id = sketch.first_point_id  // Remember the original start point
            fmt.printf("Line tool: Start point created at (%.3f, %.3f)\n", click_pos.x, click_pos.y)
        }
    } else {
        // Second+ click - try to snap to existing point, or create new one
        snapped_id, found := sketch_find_nearest_point(sketch, click_pos, SNAP_THRESHOLD)

        // Check if we're close to the ORIGINAL start point (auto-close detection)
        start_pt := sketch_get_point(sketch, sketch.chain_start_point_id)
        if start_pt != nil {
            start_pos := m.Vec2{start_pt.x, start_pt.y}
            dist_to_start := glsl.length(click_pos - start_pos)

            // Auto-close: If clicking near original start point, snap to it and close the shape
            if dist_to_start < AUTO_CLOSE_THRESHOLD {
                // Close the shape by connecting current endpoint to the original start point
                sketch_add_line(sketch, sketch.first_point_id, sketch.chain_start_point_id)

                fmt.println("✅ Shape closed! Auto-exiting line tool → Select tool")

                // Reset line tool state
                sketch.first_point_id = -1
                sketch.chain_start_point_id = -1

                // Auto-exit to Select tool
                sketch.current_tool = .Select

                return
            }
        }

        end_point_id: int
        if found {
            end_point_id = snapped_id
            pt := sketch_get_point(sketch, snapped_id)
            fmt.printf("Line tool: Snapped to existing point %d at (%.3f, %.3f)\n", snapped_id, pt.x, pt.y)
        } else {
            end_point_id = sketch_add_point(sketch, click_pos.x, click_pos.y)
        }

        // Don't create line if start and end are the same point
        if sketch.first_point_id != end_point_id {
            sketch_add_line(sketch, sketch.first_point_id, end_point_id)
            fmt.printf("Line tool: Line created from point %d to %d\n", sketch.first_point_id, end_point_id)

            // CHAIN: Continue from this endpoint (like OnShape)
            // Set the endpoint as the new start point for the next line
            sketch.first_point_id = end_point_id
            fmt.println("  → Continuing from endpoint (press ESC to finish)")
        } else {
            // Snapped back to a previous point - check if it's the original start
            if end_point_id == sketch.chain_start_point_id {
                fmt.println("✅ Shape closed! Auto-exiting line tool → Select tool")
            } else {
                fmt.println("✅ Connected to existing point! Auto-exiting line tool → Select tool")
            }

            // Reset line tool state
            sketch.first_point_id = -1
            sketch.chain_start_point_id = -1

            // Auto-exit to Select tool
            sketch.current_tool = .Select
        }
    }
}

// Handle circle tool clicks
handle_circle_tool_click :: proc(sketch: ^Sketch2D, click_pos: m.Vec2) {
    if sketch.first_point_id == -1 {
        // First click - create center point
        sketch.first_point_id = sketch_add_point(sketch, click_pos.x, click_pos.y)
        fmt.printf("Circle tool: Center point created at (%.3f, %.3f)\n", click_pos.x, click_pos.y)
    } else {
        // Second click - calculate radius and create circle
        center_pt := sketch_get_point(sketch, sketch.first_point_id)
        if center_pt != nil {
            center_2d := m.Vec2{center_pt.x, center_pt.y}
            radius := glsl.length(click_pos - center_2d)

            sketch_add_circle(sketch, sketch.first_point_id, radius)
            fmt.printf("Circle tool: Circle created with center %d, radius %.3f\n", sketch.first_point_id, radius)
        }

        // Reset for next circle
        sketch.first_point_id = -1
    }
}

// Cancel current tool operation
sketch_cancel_tool :: proc(sketch: ^Sketch2D) {
    sketch.first_point_id = -1
    sketch.second_point_id = -1
    sketch.temp_point_valid = false
}

// Find nearest point to given position (for snapping)
sketch_find_nearest_point :: proc(sketch: ^Sketch2D, pos: m.Vec2, threshold: f64 = 0.1) -> (int, bool) {
    min_dist := threshold
    nearest_id := -1

    for point in sketch.points {
        p := m.Vec2{point.x, point.y}
        dist := glsl.length(pos - p)
        if dist < min_dist {
            min_dist = dist
            nearest_id = point.id
        }
    }

    return nearest_id, nearest_id != -1
}

// Snap position to grid
sketch_snap_to_grid :: proc(pos: m.Vec2, grid_size: f64 = 0.1) -> m.Vec2 {
    return m.Vec2{
        f64(int(pos.x / grid_size + 0.5)) * grid_size,
        f64(int(pos.y / grid_size + 0.5)) * grid_size,
    }
}

// =============================================================================
// Selection and Hit Testing
// =============================================================================

// Test if a point is near a line segment
point_near_line :: proc(point: m.Vec2, line_start: m.Vec2, line_end: m.Vec2, threshold: f64 = 0.1) -> bool {
    // Vector from start to end
    line_vec := line_end - line_start
    line_len := glsl.length(line_vec)

    if line_len < 0.0001 {
        return glsl.length(point - line_start) < threshold
    }

    // Vector from start to point
    point_vec := point - line_start

    // Project point onto line
    t := glsl.dot(point_vec, line_vec) / (line_len * line_len)

    // Clamp t to [0, 1] to stay within line segment
    t = glsl.clamp(t, 0.0, 1.0)

    // Find closest point on line segment
    closest := line_start + line_vec * t

    // Check distance
    dist := glsl.length(point - closest)
    return dist < threshold
}

// Test if a point is near a circle
point_near_circle :: proc(point: m.Vec2, center: m.Vec2, radius: f64, threshold: f64 = 0.1) -> bool {
    dist := glsl.length(point - center)
    return glsl.abs(dist - radius) < threshold
}

// Find entity at given position (for selection)
sketch_find_entity_at :: proc(sketch: ^Sketch2D, pos: m.Vec2, threshold: f64 = 0.15) -> int {
    // Check entities in reverse order (last drawn = topmost)
    for i := len(sketch.entities) - 1; i >= 0; i -= 1 {
        entity := sketch.entities[i]

        switch e in entity {
        case SketchLine:
            start_pt := sketch_get_point(sketch, e.start_id)
            end_pt := sketch_get_point(sketch, e.end_id)

            if start_pt != nil && end_pt != nil {
                start_2d := m.Vec2{start_pt.x, start_pt.y}
                end_2d := m.Vec2{end_pt.x, end_pt.y}

                if point_near_line(pos, start_2d, end_2d, threshold) {
                    return i
                }
            }

        case SketchCircle:
            center_pt := sketch_get_point(sketch, e.center_id)

            if center_pt != nil {
                center_2d := m.Vec2{center_pt.x, center_pt.y}

                if point_near_circle(pos, center_2d, e.radius, threshold) {
                    return i
                }
            }

        case SketchArc:
            // TODO: Arc hit testing
            continue
        }
    }

    return -1 // No entity found
}

// Select entity at position
sketch_select_at :: proc(sketch: ^Sketch2D, pos: m.Vec2) -> bool {
    entity_idx := sketch_find_entity_at(sketch, pos, 0.15)

    if entity_idx != -1 {
        sketch.selected_entity = entity_idx
        fmt.printf("Selected entity %d\n", entity_idx)
        return true
    } else {
        sketch.selected_entity = -1
        fmt.println("No entity selected")
        return false
    }
}

// Delete selected entity
sketch_delete_selected :: proc(sketch: ^Sketch2D) -> bool {
    if sketch.selected_entity >= 0 && sketch.selected_entity < len(sketch.entities) {
        fmt.printf("Deleting entity %d\n", sketch.selected_entity)

        // Collect point IDs used by this entity
        points_to_check := make([dynamic]int, 0, 4)
        defer delete(points_to_check)

        entity := sketch.entities[sketch.selected_entity]
        switch e in entity {
        case SketchLine:
            append(&points_to_check, e.start_id)
            append(&points_to_check, e.end_id)
        case SketchCircle:
            append(&points_to_check, e.center_id)
        case SketchArc:
            append(&points_to_check, e.center_id)
            append(&points_to_check, e.start_id)
            append(&points_to_check, e.end_id)
        }

        // Delete the entity first
        sketch_delete_entity(sketch, sketch.selected_entity)
        sketch.selected_entity = -1

        // Check each point - delete if not used by any other entity
        for point_id in points_to_check {
            if !sketch_is_point_used(sketch, point_id) {
                sketch_delete_point(sketch, point_id)
                fmt.printf("  Deleted orphaned point %d\n", point_id)
            }
        }

        return true
    }
    return false
}

// Check if a point is used by any entity
sketch_is_point_used :: proc(sketch: ^Sketch2D, point_id: int) -> bool {
    for entity in sketch.entities {
        switch e in entity {
        case SketchLine:
            if e.start_id == point_id || e.end_id == point_id {
                return true
            }
        case SketchCircle:
            if e.center_id == point_id {
                return true
            }
        case SketchArc:
            if e.center_id == point_id || e.start_id == point_id || e.end_id == point_id {
                return true
            }
        }
    }
    return false
}

// Delete a point by ID
sketch_delete_point :: proc(sketch: ^Sketch2D, point_id: int) {
    for i := 0; i < len(sketch.points); i += 1 {
        if sketch.points[i].id == point_id {
            ordered_remove(&sketch.points, i)
            return
        }
    }
}

// =============================================================================
// Dimension Tool
// =============================================================================

// Handle dimension tool clicks (3-click workflow: point1, point2, placement)
handle_dimension_tool_click :: proc(sketch: ^Sketch2D, click_pos: m.Vec2) {
    // Snap threshold - if clicking within 0.2 units of existing point, snap to it
    SNAP_THRESHOLD :: 0.2

    if sketch.first_point_id == -1 {
        // CLICK 1: Select first point
        snapped_id, found := sketch_find_nearest_point(sketch, click_pos, SNAP_THRESHOLD)

        if found {
            sketch.first_point_id = snapped_id
            pt := sketch_get_point(sketch, snapped_id)
            fmt.printf("Dimension: Point 1 selected (ID=%d) at (%.3f, %.3f)\n", snapped_id, pt.x, pt.y)
            fmt.println("  → Click second point")
        } else {
            fmt.println("❌ No point found - click near an existing point")
        }
    } else if sketch.second_point_id == -1 {
        // CLICK 2: Select second point
        snapped_id, found := sketch_find_nearest_point(sketch, click_pos, SNAP_THRESHOLD)

        if !found {
            fmt.println("❌ No point found - click near an existing point")
            return
        }

        if snapped_id == sketch.first_point_id {
            fmt.println("❌ Cannot dimension between the same point")
            sketch.first_point_id = -1
            return
        }

        sketch.second_point_id = snapped_id
        pt := sketch_get_point(sketch, snapped_id)
        fmt.printf("Dimension: Point 2 selected (ID=%d) at (%.3f, %.3f)\n", snapped_id, pt.x, pt.y)
        fmt.println("  → Click to place dimension line (anywhere to confirm)")
    } else {
        // CLICK 3: Place dimension at offset position

        // Get both points
        pt1 := sketch_get_point(sketch, sketch.first_point_id)
        pt2 := sketch_get_point(sketch, sketch.second_point_id)

        if pt1 == nil || pt2 == nil {
            fmt.println("❌ Invalid points")
            sketch.first_point_id = -1
            sketch.second_point_id = -1
            return
        }

        // Calculate distance between points
        p1 := m.Vec2{pt1.x, pt1.y}
        p2 := m.Vec2{pt2.x, pt2.y}
        distance := glsl.length(p2 - p1)

        // Add distance constraint with current distance value AND offset position
        constraint_id := sketch_add_constraint(sketch, .Distance, DistanceData{
            point1_id = sketch.first_point_id,
            point2_id = sketch.second_point_id,
            distance = distance,
            offset = click_pos,  // Store where user clicked for placement
        })

        fmt.printf("✅ Dimension created: %.3f units between points %d and %d\n",
            distance, sketch.first_point_id, sketch.second_point_id)
        fmt.printf("   Placed at offset (%.3f, %.3f)\n", click_pos.x, click_pos.y)
        fmt.printf("   Constraint ID: %d\n", constraint_id)

        // Reset for next dimension (stay in Dimension tool)
        sketch.first_point_id = -1
        sketch.second_point_id = -1
        fmt.println("  → Ready for next dimension (or press ESC to finish)")
    }
}
