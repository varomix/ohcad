// features/sketch - Interactive sketch tool operations
package ohcad_sketch

import "core:fmt"
import "core:math"
import m "../../core/math"
import glfw "vendor:glfw"
import glsl "core:math/linalg/glsl"

// Set the current tool
sketch_set_tool :: proc(sketch: ^Sketch2D, tool: SketchTool) {
    sketch.current_tool = tool
    sketch.temp_point_valid = false
    sketch.first_point_id = -1
    sketch.second_point_id = -1

    // Reset angular dimension state (used by unified Dimension tool)
    sketch.first_line_id = -1
    sketch.second_line_id = -1
    sketch.angular_offset = m.Vec2{0, 0}

    // Clear all selection state when switching tools
    sketch.selected_entity = -1
    sketch.selected_constraint_id = -1
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

            // 🔧 FIX: Auto-fix the FIRST point ever created in the sketch (like SolidWorks/OnShape)
            // This anchors the sketch in space so the solver has a reference point
            if len(sketch.points) == 1 && len(sketch.constraints) == 0 {
                sketch_add_constraint(sketch, .FixedPoint, FixedPointData{
                    point_id = sketch.first_point_id,
                })
                fmt.println("🔒 Auto-fixed first point (origin anchor)")
            }

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
            line_id := sketch_add_line(sketch, sketch.first_point_id, end_point_id)
            fmt.printf("Line tool: Line created from point %d to %d\n", sketch.first_point_id, end_point_id)

            // AUTO-APPLY CONSTRAINTS: If the preview was snapped to horizontal/vertical, apply the constraint
            constraint_applied := false
            if sketch.preview_snap_horizontal {
                // Find the entity index for the line we just created
                line_entity_index := len(sketch.entities) - 1
                sketch_add_constraint(sketch, .Horizontal, HorizontalData{
                    line_id = line_entity_index,
                })
                fmt.println("  ✅ Auto-applied Horizontal constraint")
                constraint_applied = true
            } else if sketch.preview_snap_vertical {
                // Find the entity index for the line we just created
                line_entity_index := len(sketch.entities) - 1
                sketch_add_constraint(sketch, .Vertical, VerticalData{
                    line_id = line_entity_index,
                })
                fmt.println("  ✅ Auto-applied Vertical constraint")
                constraint_applied = true
            }

            // SOLVE CONSTRAINTS: If we applied a constraint, solve immediately to snap the line
            if constraint_applied {
                result := sketch_solve_constraints(sketch)
                if result.status == .Success {
                    fmt.println("  🔧 Constraint solved - line snapped to position")
                } else {
                    fmt.printf("  ⚠️  Solver status: %v (constraint added but geometry may not be exact)\n", result.status)
                }
            }

            // Reset snap state after creating line
            sketch.preview_snap_horizontal = false
            sketch.preview_snap_vertical = false

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

// Find nearest point with PRIORITY for circle centers (larger tolerance for centers)
// This makes it easier to dimension from circle centers even when near the circle edge
sketch_find_nearest_point_prioritize_centers :: proc(sketch: ^Sketch2D, pos: m.Vec2, point_threshold: f64 = 0.1, center_threshold: f64 = 0.5) -> (int, bool) {
    // First pass: check circle centers with larger threshold
    min_dist := center_threshold
    nearest_id := -1

    // Check all circle centers first (with larger tolerance)
    for entity in sketch.entities {
        if circle, is_circle := entity.(SketchCircle); is_circle {
            center_pt := sketch_get_point(sketch, circle.center_id)
            if center_pt != nil {
                p := m.Vec2{center_pt.x, center_pt.y}
                dist := glsl.length(pos - p)
                if dist < min_dist {
                    min_dist = dist
                    nearest_id = circle.center_id
                }
            }
        }
    }

    // If we found a circle center, return it
    if nearest_id != -1 {
        return nearest_id, true
    }

    // Second pass: check all other points with normal threshold
    min_dist = point_threshold
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

// Find nearest line entity to given position (for edge selection)
sketch_find_nearest_line :: proc(sketch: ^Sketch2D, pos: m.Vec2, threshold: f64 = 0.15) -> (entity_id: int, start_pt_id: int, end_pt_id: int, found: bool) {
    min_dist := threshold
    nearest_entity := -1
    nearest_start := -1
    nearest_end := -1

    for entity, idx in sketch.entities {
        #partial switch e in entity {
        case SketchLine:
            start_pt := sketch_get_point(sketch, e.start_id)
            end_pt := sketch_get_point(sketch, e.end_id)

            if start_pt != nil && end_pt != nil {
                start_2d := m.Vec2{start_pt.x, start_pt.y}
                end_2d := m.Vec2{end_pt.x, end_pt.y}

                if point_near_line(pos, start_2d, end_2d, threshold) {
                    // Calculate actual distance to line
                    line_vec := end_2d - start_2d
                    line_len := glsl.length(line_vec)

                    if line_len > 0.0001 {
                        point_vec := pos - start_2d
                        t := glsl.dot(point_vec, line_vec) / (line_len * line_len)
                        t = glsl.clamp(t, 0.0, 1.0)
                        closest := start_2d + line_vec * t
                        dist := glsl.length(pos - closest)

                        if dist < min_dist {
                            min_dist = dist
                            nearest_entity = idx
                            nearest_start = e.start_id
                            nearest_end = e.end_id
                        }
                    }
                }
            }
        }
    }

    return nearest_entity, nearest_start, nearest_end, nearest_entity != -1
}

// Find nearest circle entity to given position (for diameter dimension)
sketch_find_nearest_circle :: proc(sketch: ^Sketch2D, pos: m.Vec2, threshold: f64 = 0.15) -> (entity_id: int, center_pt_id: int, found: bool) {
    // Use a larger detection band for better UX (3x threshold on each side of circle edge)
    detection_band := threshold * 3.0
    min_dist := detection_band
    nearest_entity := -1
    nearest_center := -1

    for entity, idx in sketch.entities {
        #partial switch e in entity {
        case SketchCircle:
            center_pt := sketch_get_point(sketch, e.center_id)

            if center_pt != nil {
                center_2d := m.Vec2{center_pt.x, center_pt.y}

                // Calculate distance from click position to circle edge
                dist_to_center := glsl.length(pos - center_2d)
                dist_to_edge := math.abs(dist_to_center - e.radius)

                if dist_to_edge < min_dist {
                    min_dist = dist_to_edge
                    nearest_entity = idx
                    nearest_center = e.center_id
                }
            }
        }
    }

    return nearest_entity, nearest_center, nearest_entity != -1
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

// Handle dimension tool clicks - SMART UNIFIED TOOL
// Supports:
// - Distance: Click point → point → placement
// - Distance from edge: Click edge → placement
// - Angular: Click line → line → placement
// - Diameter: Click circle → placement
handle_dimension_tool_click :: proc(sketch: ^Sketch2D, click_pos: m.Vec2) {
    // Snap threshold - if clicking within 0.2 units of existing point, snap to it
    SNAP_THRESHOLD :: 0.2
    EDGE_SELECT_THRESHOLD :: 0.15
    CIRCLE_SELECT_THRESHOLD :: 0.15

    // DEBUG: Print current state
    fmt.printf("🐛 DEBUG: first_point_id=%d, second_point_id=%d, first_line_id=%d, second_line_id=%d\n",
        sketch.first_point_id, sketch.second_point_id, sketch.first_line_id, sketch.second_line_id)

    // ==========================================================================
    // CLICK 1: Select first point OR first edge/line
    // ==========================================================================
    if sketch.first_point_id == -1 && sketch.first_line_id == -1 {
        // Try point selection first (points have priority)
        // Use center-prioritized search to make circle centers easier to select
        snapped_id, point_found := sketch_find_nearest_point_prioritize_centers(sketch, click_pos, SNAP_THRESHOLD, SNAP_THRESHOLD * 2.5)

        if point_found {
            // DISTANCE DIMENSION MODE: Point selected
            sketch.first_point_id = snapped_id
            pt := sketch_get_point(sketch, snapped_id)
            fmt.printf("Dimension: Point 1 selected (ID=%d) at (%.3f, %.3f)\n", snapped_id, pt.x, pt.y)
            fmt.println("  → Click second point or edge")
            return
        }

        // No point found, try to find a nearby LINE/EDGE
        entity_id, start_pt, end_pt, line_found := sketch_find_nearest_line(sketch, click_pos, EDGE_SELECT_THRESHOLD)

        if line_found {
            entity := sketch.entities[entity_id]
            if _, is_line := entity.(SketchLine); is_line {
                // EDGE SELECTED (ambiguous - could be distance OR angular)
                // Store BOTH the edge endpoints AND the line ID
                sketch.first_point_id = start_pt
                sketch.second_point_id = end_pt
                sketch.first_line_id = entity_id  // Also track the line for potential angular mode

                pt1 := sketch_get_point(sketch, start_pt)
                pt2 := sketch_get_point(sketch, end_pt)

                fmt.printf("Dimension: Edge selected (Entity ID=%d)\n", entity_id)
                fmt.printf("  → Points: %d at (%.3f, %.3f) to %d at (%.3f, %.3f)\n",
                    start_pt, pt1.x, pt1.y, end_pt, pt2.x, pt2.y)
                fmt.println("  → Click to place dimension OR click second edge for angular")
                return
            }
        }

        // No line found, try to find a nearby CIRCLE
        circle_entity_id, circle_center_id, circle_found := sketch_find_nearest_circle(sketch, click_pos, CIRCLE_SELECT_THRESHOLD)

        if circle_found {
            entity := sketch.entities[circle_entity_id]
            if circle, is_circle := entity.(SketchCircle); is_circle {
                // CIRCLE SELECTED - enter diameter dimension mode
                // Store circle entity ID in first_line_id (reusing existing state variable)
                // This signals we're in diameter mode, not distance/angular mode
                sketch.first_line_id = circle_entity_id
                // Mark as diameter mode by setting first_point_id to a special value
                // (we'll check for this pattern: first_line_id >= 0 && first_point_id == -1 && second_point_id == -1)

                center_pt := sketch_get_point(sketch, circle_center_id)
                fmt.printf("Dimension: Circle selected (Entity ID=%d)\n", circle_entity_id)
                fmt.printf("  → Center: (%.3f, %.3f), Radius: %.3f, Diameter: %.3f\n",
                    center_pt.x, center_pt.y, circle.radius, circle.radius * 2.0)
                fmt.println("  → Click to place diameter dimension")
                return
            }
        }

        // Nothing found
        fmt.println("❌ No point, edge, or circle found - click near existing geometry")
        return
    }

    // ==========================================================================
    // CLICK 2a: ANGULAR MODE - Detect second edge/line selection
    // ==========================================================================
    // If we have first_line_id set AND first/second_point_id set (from edge selection),
    // check if user is clicking another edge to switch to angular mode
    if sketch.first_line_id >= 0 && sketch.second_line_id == -1 &&
       sketch.first_point_id >= 0 && sketch.second_point_id >= 0 {

        // Try to find another line
        entity_id, _, _, line_found := sketch_find_nearest_line(sketch, click_pos, EDGE_SELECT_THRESHOLD)

        if line_found {
            entity := sketch.entities[entity_id]
            if _, is_line := entity.(SketchLine); is_line {
                if entity_id == sketch.first_line_id {
                    // Clicked same line - treat as placement for distance dimension
                    // Fall through to distance placement logic
                } else {
                    // SWITCH TO ANGULAR MODE: Second line selected
                    sketch.second_line_id = entity_id
                    // Clear point IDs since we're now in angular mode
                    sketch.first_point_id = -1
                    sketch.second_point_id = -1
                    fmt.printf("Dimension (Angular): Second line selected (Entity ID=%d)\n", entity_id)
                    fmt.println("  → Click to position angular dimension arc")
                    return
                }
            }
        }

        // If we didn't find a second line, treat click as placement position for distance dimension
        // Fall through to distance placement logic below
    }

    // ==========================================================================
    // CLICK 2b: ANGULAR MODE - Select second line (pure angular path)
    // ==========================================================================
    if sketch.first_line_id >= 0 && sketch.second_line_id == -1 &&
       sketch.first_point_id == -1 && sketch.second_point_id == -1 {

        // Verify first_line_id is actually a LINE, not a circle
        // (If it's a circle, this is diameter mode, not angular mode)
        if sketch.first_line_id < len(sketch.entities) {
            entity := sketch.entities[sketch.first_line_id]
            if _, is_circle := entity.(SketchCircle); is_circle {
                // This is a circle, not a line - fall through to diameter mode
                // (handled later in CLICK 2b: DIAMETER MODE)
            } else if _, is_line := entity.(SketchLine); is_line {
                // This is a line - proceed with angular dimension logic
                // Try to find another line
                entity_id, _, _, line_found := sketch_find_nearest_line(sketch, click_pos, EDGE_SELECT_THRESHOLD)

                if line_found {
                    entity2 := sketch.entities[entity_id]
                    if _, is_line2 := entity2.(SketchLine); is_line2 {
                        if entity_id == sketch.first_line_id {
                            fmt.println("❌ Cannot measure angle of the same line - select a different line")
                            return
                        }

                        sketch.second_line_id = entity_id
                        fmt.printf("Dimension (Angular): Second line selected (Entity ID=%d)\n", entity_id)
                        fmt.println("  → Click to position angular dimension arc")
                        return
                    }
                }

                // No line found
                fmt.println("❌ No line found - click on a line")
                return
            }
        }
    }

    // ==========================================================================
    // CLICK 2b: DISTANCE MODE - Select second point
    // ==========================================================================
    if sketch.first_point_id >= 0 && sketch.second_point_id == -1 {
        // Try POINT selection first (points have priority)
        // Use center-prioritized search to make circle centers easier to select
        snapped_id, point_found := sketch_find_nearest_point_prioritize_centers(sketch, click_pos, SNAP_THRESHOLD, SNAP_THRESHOLD * 2.5)

        if point_found {
            if snapped_id == sketch.first_point_id {
                fmt.println("❌ Cannot dimension between the same point")
                sketch.first_point_id = -1
                return
            }

            sketch.second_point_id = snapped_id
            pt := sketch_get_point(sketch, snapped_id)
            fmt.printf("Dimension (Distance): Point 2 selected (ID=%d) at (%.3f, %.3f)\n", snapped_id, pt.x, pt.y)
            fmt.println("  → Click to place dimension line")
            return
        }

        // No point found, try edge selection
        entity_id, start_pt, end_pt, edge_found := sketch_find_nearest_line(sketch, click_pos, EDGE_SELECT_THRESHOLD)

        if edge_found {
            // Choose endpoint based on which one is NOT the first point
            if start_pt != sketch.first_point_id {
                sketch.second_point_id = start_pt
            } else if end_pt != sketch.first_point_id {
                sketch.second_point_id = end_pt
            } else {
                fmt.println("❌ Cannot dimension from a point to an edge containing that point")
                sketch.first_point_id = -1
                return
            }

            pt := sketch_get_point(sketch, sketch.second_point_id)
            fmt.printf("Dimension (Distance): Edge endpoint selected (ID=%d) at (%.3f, %.3f)\n",
                sketch.second_point_id, pt.x, pt.y)
            fmt.println("  → Click to place dimension line")
            return
        }

        // Nothing found
        fmt.println("❌ No point or edge found - click near an existing point or edge")
        return
    }

    // ==========================================================================
    // CLICK 3a: ANGULAR MODE - Position arc
    // ==========================================================================
    if sketch.first_line_id >= 0 && sketch.second_line_id >= 0 {
        sketch.angular_offset = click_pos

        // Get both line entities
        line1 := sketch.entities[sketch.first_line_id].(SketchLine)
        line2 := sketch.entities[sketch.second_line_id].(SketchLine)

        // Calculate angle between lines
        angle := calculate_angle_between_lines(sketch, line1, line2)

        // Add angular constraint
        constraint_id := sketch_add_constraint(sketch, .Angle, AngleData{
            line1_id = sketch.first_line_id,
            line2_id = sketch.second_line_id,
            angle = angle,
            offset = sketch.angular_offset,
        })

        fmt.printf("✅ Angular dimension created: %.1f° between lines %d and %d\n",
            angle, sketch.first_line_id, sketch.second_line_id)
        fmt.printf("   Placed at offset (%.3f, %.3f)\n", click_pos.x, click_pos.y)
        fmt.printf("   Constraint ID: %d\n", constraint_id)

        // Reset for next dimension (stay in Dimension tool)
        sketch.first_line_id = -1
        sketch.second_line_id = -1
        sketch.angular_offset = m.Vec2{0, 0}
        fmt.println("  → Ready for next dimension (or press ESC to finish)")
        return
    }

    // ==========================================================================
    // CLICK 2b: DIAMETER MODE - Place diameter dimension
    // ==========================================================================
    // Pattern: first_line_id >= 0 (circle entity ID), no points selected, no second line
    if sketch.first_line_id >= 0 && sketch.second_line_id == -1 &&
       sketch.first_point_id == -1 && sketch.second_point_id == -1 {

        // Verify the entity is still a circle
        if sketch.first_line_id < 0 || sketch.first_line_id >= len(sketch.entities) {
            fmt.println("❌ Invalid circle entity ID")
            sketch.first_line_id = -1
            return
        }

        entity := sketch.entities[sketch.first_line_id]
        circle, ok := entity.(SketchCircle)
        if !ok {
            fmt.println("❌ Entity is not a circle")
            sketch.first_line_id = -1
            return
        }

        // Get circle center point
        center_pt := sketch_get_point(sketch, circle.center_id)
        if center_pt == nil {
            fmt.println("❌ Invalid circle center point")
            sketch.first_line_id = -1
            return
        }

        // Calculate diameter
        diameter := circle.radius * 2.0

        // Create diameter constraint
        constraint_id := sketch_add_constraint(sketch, .Diameter, DiameterData{
            circle_id = sketch.first_line_id,
            diameter = diameter,
            offset = click_pos,
        })

        fmt.printf("✅ Diameter dimension created: Ø%.3f for circle %d\n",
            diameter, sketch.first_line_id)
        fmt.printf("   Center: (%.3f, %.3f), Radius: %.3f\n",
            center_pt.x, center_pt.y, circle.radius)
        fmt.printf("   Placed at offset (%.3f, %.3f)\n", click_pos.x, click_pos.y)
        fmt.printf("   Constraint ID: %d\n", constraint_id)

        // Reset for next dimension (stay in Dimension tool)
        sketch.first_line_id = -1
        fmt.println("  → Ready for next dimension (or press ESC to finish)")
        return
    }

    // ==========================================================================
    // CLICK 3b: DISTANCE MODE - Place dimension (SMART: horizontal/vertical/diagonal)
    // ==========================================================================
    if sketch.first_point_id >= 0 && sketch.second_point_id >= 0 {
        // Get both points
        pt1 := sketch_get_point(sketch, sketch.first_point_id)
        pt2 := sketch_get_point(sketch, sketch.second_point_id)

        if pt1 == nil || pt2 == nil {
            fmt.println("❌ Invalid points")
            sketch.first_point_id = -1
            sketch.second_point_id = -1
            return
        }

        p1 := m.Vec2{pt1.x, pt1.y}
        p2 := m.Vec2{pt2.x, pt2.y}

        // Calculate vector from point 1 to point 2
        edge_vec := p2 - p1
        edge_midpoint := (p1 + p2) * 0.5

        // Calculate vector from midpoint to cursor
        cursor_vec := click_pos - edge_midpoint

        dimension_type: ConstraintType
        dimension_value: f64
        dimension_name: string

        // CASE 1: Edge dimension (selected edge directly with first_line_id set)
        // → Detect if edge is H/V and use appropriate dimension type
        if sketch.first_line_id >= 0 {
            // Calculate edge angle to determine if it's horizontal or vertical
            dx := p2.x - p1.x
            dy := p2.y - p1.y
            edge_length := glsl.length(edge_vec)

            // Check if edge is horizontal or vertical (within tolerance)
            ALIGNMENT_TOLERANCE :: 0.01  // Tolerance for detecting H/V alignment

            if edge_length > 0.001 {
                // Normalize to check alignment
                norm_dx := glsl.abs(dx) / edge_length
                norm_dy := glsl.abs(dy) / edge_length

                if norm_dy < ALIGNMENT_TOLERANCE {
                    // Edge is horizontal - check if it has a Horizontal constraint
                    has_horizontal_constraint := false
                    if entity, ok := sketch.entities[sketch.first_line_id].(SketchLine); ok {
                        for c in sketch.constraints {
                            if h_data, is_h := c.data.(HorizontalData); is_h {
                                if h_data.line_id == sketch.first_line_id {
                                    has_horizontal_constraint = true
                                    break
                                }
                            }
                        }
                    }

                    if has_horizontal_constraint {
                        // Has Horizontal constraint → use simple Distance
                        dimension_type = .Distance
                        dimension_value = glsl.abs(dx)  // Unsigned distance
                        dimension_name = "Distance"
                        fmt.println("📏 Edge dimension mode (horizontal edge with H constraint → using Distance)")
                    } else {
                        // No Horizontal constraint → use DistanceX
                        dimension_type = .DistanceX
                        dimension_value = dx  // Signed horizontal distance
                        dimension_name = "Horizontal"
                        fmt.println("📏 Edge dimension mode (horizontal edge)")
                    }
                } else if norm_dx < ALIGNMENT_TOLERANCE {
                    // Edge is vertical - check if it has a Vertical constraint
                    has_vertical_constraint := false
                    if entity, ok := sketch.entities[sketch.first_line_id].(SketchLine); ok {
                        for c in sketch.constraints {
                            if v_data, is_v := c.data.(VerticalData); is_v {
                                if v_data.line_id == sketch.first_line_id {
                                    has_vertical_constraint = true
                                    break
                                }
                            }
                        }
                    }

                    if has_vertical_constraint {
                        // Has Vertical constraint → use simple Distance
                        dimension_type = .Distance
                        dimension_value = glsl.abs(dy)  // Unsigned distance
                        dimension_name = "Distance"
                        fmt.println("📏 Edge dimension mode (vertical edge with V constraint → using Distance)")
                    } else {
                        // No Vertical constraint → use DistanceY
                        dimension_type = .DistanceY
                        dimension_value = dy  // Signed vertical distance
                        dimension_name = "Vertical"
                        fmt.println("📏 Edge dimension mode (vertical edge)")
                    }
                } else {
                    // Edge is angled - use regular Distance
                    dimension_type = .Distance
                    dimension_value = edge_length
                    dimension_name = "Distance"
                    fmt.println("📏 Edge dimension mode (angled edge)")
                }
            } else {
                // Degenerate edge - fallback to Distance
                dimension_type = .Distance
                dimension_value = edge_length
                dimension_name = "Distance"
                fmt.println("📏 Edge dimension mode (parallel to edge)")
            }
        } else {
            // CASE 2: Point-to-point dimension
            // → Smart detection based on cursor position
            abs_cursor_x := glsl.abs(cursor_vec.x)
            abs_cursor_y := glsl.abs(cursor_vec.y)

            // Thresholds for determining dimension type
            HORIZONTAL_THRESHOLD :: 0.3
            VERTICAL_THRESHOLD :: 0.3

            // Determine dimension type based on cursor position
            // CAD LOGIC:
            // - Cursor offset UP/DOWN (Y direction) → Horizontal dimension (measures X distance)
            // - Cursor offset LEFT/RIGHT (X direction) → Vertical dimension (measures Y distance)
            // - Otherwise → Diagonal distance dimension
            if abs_cursor_y > abs_cursor_x * (1.0 + HORIZONTAL_THRESHOLD) {
                // Cursor is predominantly vertical offset → Horizontal dimension (DistanceX)
                dimension_type = .DistanceX
                dimension_value = p2.x - p1.x  // SIGNED distance (can be negative)
                dimension_name = "Horizontal"
            } else if abs_cursor_x > abs_cursor_y * (1.0 + VERTICAL_THRESHOLD) {
                // Cursor is predominantly horizontal offset → Vertical dimension (DistanceY)
                dimension_type = .DistanceY
                dimension_value = p2.y - p1.y  // SIGNED distance (can be negative)
                dimension_name = "Vertical"
            } else {
                // Cursor is diagonal → Diagonal distance dimension
                dimension_type = .Distance
                dimension_value = glsl.length(p2 - p1)
                dimension_name = "Distance"
            }
        }

        // Create the appropriate constraint
        constraint_id: int
        #partial switch dimension_type {
        case .DistanceX:
            // Calculate locked Y-difference to maintain angle
            locked_dy := p2.y - p1.y
            constraint_id = sketch_add_constraint(sketch, .DistanceX, DistanceXData{
                point1_id = sketch.first_point_id,
                point2_id = sketch.second_point_id,
                distance = dimension_value,
                offset = click_pos,
                locked_dy = locked_dy,
            })

        case .DistanceY:
            // Calculate locked X-difference to maintain angle
            locked_dx := p2.x - p1.x
            constraint_id = sketch_add_constraint(sketch, .DistanceY, DistanceYData{
                point1_id = sketch.first_point_id,
                point2_id = sketch.second_point_id,
                distance = dimension_value,
                offset = click_pos,
                locked_dx = locked_dx,
            })

        case .Distance:
            constraint_id = sketch_add_constraint(sketch, .Distance, DistanceData{
                point1_id = sketch.first_point_id,
                point2_id = sketch.second_point_id,
                distance = dimension_value,
                offset = click_pos,
            })
        }

        fmt.printf("✅ %s dimension created: %.3f units between points %d and %d\n",
            dimension_name, dimension_value, sketch.first_point_id, sketch.second_point_id)
        fmt.printf("   Placed at offset (%.3f, %.3f)\n", click_pos.x, click_pos.y)
        fmt.printf("   Constraint ID: %d\n", constraint_id)

        // Reset for next dimension (stay in Dimension tool)
        sketch.first_point_id = -1
        sketch.second_point_id = -1
        sketch.first_line_id = -1  // IMPORTANT: Also reset line ID to avoid angular mode confusion
        fmt.println("  → Ready for next dimension (or press ESC to finish)")
        return
    }
}

// =============================================================================
// Angular Dimension Helper
// =============================================================================

// Calculate angle between two lines (in degrees, 0-360)
calculate_angle_between_lines :: proc(sketch: ^Sketch2D, line1: SketchLine, line2: SketchLine) -> f64 {
    // Get endpoints of both lines
    p1_start := sketch_get_point(sketch, line1.start_id)
    p1_end := sketch_get_point(sketch, line1.end_id)
    p2_start := sketch_get_point(sketch, line2.start_id)
    p2_end := sketch_get_point(sketch, line2.end_id)

    if p1_start == nil || p1_end == nil || p2_start == nil || p2_end == nil {
        return 0
    }

    // Direction vectors
    v1 := m.Vec2{p1_end.x - p1_start.x, p1_end.y - p1_start.y}
    v2 := m.Vec2{p2_end.x - p2_start.x, p2_end.y - p2_start.y}

    // Normalize vectors
    len1 := glsl.length(v1)
    len2 := glsl.length(v2)

    if len1 < 0.0001 || len2 < 0.0001 {
        return 0  // Degenerate line
    }

    v1 = v1 / len1
    v2 = v2 / len2

    // Calculate angle using atan2 for full 360° range
    dot := v1.x * v2.x + v1.y * v2.y
    cross := v1.x * v2.y - v1.y * v2.x
    angle_rad := math.atan2(cross, dot)

    // Convert to degrees (0-360 range)
    angle_deg := angle_rad * 180.0 / math.PI
    if angle_deg < 0 {
        angle_deg += 360.0
    }

    // For typical usage, we want the acute or obtuse angle, not reflex
    // If angle > 180, return the complement
    if angle_deg > 180.0 {
        angle_deg = 360.0 - angle_deg
    }

    return angle_deg
}

// =============================================================================
// Dimension Dragging
// =============================================================================

// Start dragging a dimension (call when mouse button pressed on dimension)
sketch_start_drag_dimension :: proc(sketch: ^Sketch2D, constraint_id: int, start_pos: m.Vec2) {
    constraint := sketch_get_constraint(sketch, constraint_id)
    if constraint == nil do return

    // Store which constraint we're dragging
    sketch.dragging_constraint_id = constraint_id
    sketch.drag_start_pos = start_pos

    // Store the original offset
    #partial switch data in constraint.data {
    case DistanceData:
        sketch.drag_offset_start = data.offset
    case DistanceXData:
        sketch.drag_offset_start = data.offset
    case DistanceYData:
        sketch.drag_offset_start = data.offset
    case AngleData:
        sketch.drag_offset_start = data.offset
    case DiameterData:
        sketch.drag_offset_start = data.offset
    case:
        // Other constraints don't support dragging
        sketch.dragging_constraint_id = -1
        return
    }

    fmt.printf("🖱️  Started dragging constraint #%d\n", constraint_id)
}

// Update dimension position during drag (call on mouse move while dragging)
sketch_update_drag_dimension :: proc(sketch: ^Sketch2D, current_pos: m.Vec2) {
    if sketch.dragging_constraint_id < 0 do return

    constraint := sketch_get_constraint(sketch, sketch.dragging_constraint_id)
    if constraint == nil {
        sketch.dragging_constraint_id = -1
        return
    }

    // Calculate delta from drag start
    delta := current_pos - sketch.drag_start_pos

    // Update offset based on constraint type
    #partial switch &data in constraint.data {
    case DistanceData:
        // Update offset to new position
        data.offset = sketch.drag_offset_start + delta

    case DistanceXData:
        // Update offset to new position
        data.offset = sketch.drag_offset_start + delta

    case DistanceYData:
        // Update offset to new position
        data.offset = sketch.drag_offset_start + delta

    case AngleData:
        // Update offset to new position
        data.offset = sketch.drag_offset_start + delta

    case DiameterData:
        // Update offset to new position (for diameter dimension leader line)
        data.offset = sketch.drag_offset_start + delta
    }
}

// Stop dragging dimension (call on mouse button release)
sketch_stop_drag_dimension :: proc(sketch: ^Sketch2D) {
    if sketch.dragging_constraint_id >= 0 {
        fmt.printf("✓ Dimension #%d repositioned\n", sketch.dragging_constraint_id)
    }

    sketch.dragging_constraint_id = -1
    sketch.drag_start_pos = m.Vec2{0, 0}
    sketch.drag_offset_start = m.Vec2{0, 0}
}

// Check if currently dragging a dimension
sketch_is_dragging_dimension :: proc(sketch: ^Sketch2D) -> bool {
    return sketch.dragging_constraint_id >= 0
}
