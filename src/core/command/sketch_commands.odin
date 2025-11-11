// core/command/sketch_commands - Commands for sketch operations
package ohcad_command

import "core:fmt"
import sketch "../../features/sketch"
import m "../../core/math"

// =============================================================================
// Sketch Commands
// =============================================================================

// AddPointCommand - adds a point to a sketch
AddPointCommand :: struct {
    sketch_ref: ^sketch.Sketch2D,  // Reference to sketch
    x: f64,                        // Point X coordinate
    y: f64,                        // Point Y coordinate
    fixed: bool,                   // Is point fixed
    point_id: int,                 // ID of created point (set during execute)
}

// AddLineCommand - adds a line to a sketch
AddLineCommand :: struct {
    sketch_ref: ^sketch.Sketch2D,  // Reference to sketch
    start_id: int,                 // Start point ID
    end_id: int,                   // End point ID
    line_id: int,                  // ID of created line (set during execute)
    entity_index: int,             // Index in entities array (set during execute)
}

// AddCircleCommand - adds a circle to a sketch
AddCircleCommand :: struct {
    sketch_ref: ^sketch.Sketch2D,  // Reference to sketch
    center_id: int,                // Center point ID
    radius: f64,                   // Circle radius
    circle_id: int,                // ID of created circle (set during execute)
    entity_index: int,             // Index in entities array (set during execute)
}

// AddArcCommand - adds an arc to a sketch
AddArcCommand :: struct {
    sketch_ref: ^sketch.Sketch2D,  // Reference to sketch
    center_id: int,                // Center point ID
    start_id: int,                 // Start point ID
    end_id: int,                   // End point ID
    radius: f64,                   // Arc radius
    arc_id: int,                   // ID of created arc (set during execute)
    entity_index: int,             // Index in entities array (set during execute)
}

// DeleteEntityCommand - deletes an entity from a sketch
DeleteEntityCommand :: struct {
    sketch_ref: ^sketch.Sketch2D,  // Reference to sketch
    entity_index: int,             // Index of entity to delete
    deleted_entity: sketch.SketchEntity,  // Stored entity data for restoration
}

// =============================================================================
// AddPointCommand Operations
// =============================================================================

add_point_command_execute :: proc(cmd: AddPointCommand) -> bool {
    // Modify the command to store the created point ID
    cmd_mut := cmd
    cmd_mut.point_id = sketch.sketch_add_point(cmd.sketch_ref, cmd.x, cmd.y, cmd.fixed)
    return true
}

add_point_command_undo :: proc(cmd: AddPointCommand) -> bool {
    // Find and remove the point
    for i := 0; i < len(cmd.sketch_ref.points); i += 1 {
        if cmd.sketch_ref.points[i].id == cmd.point_id {
            ordered_remove(&cmd.sketch_ref.points, i)
            return true
        }
    }
    fmt.println("⚠️  Warning: Point not found for undo")
    return false
}

add_point_command_redo :: proc(cmd: AddPointCommand) -> bool {
    // Re-add the point with the same ID
    point := sketch.SketchPoint{
        id = cmd.point_id,
        x = cmd.x,
        y = cmd.y,
        fixed = cmd.fixed,
    }
    append(&cmd.sketch_ref.points, point)

    // Update next_point_id if needed
    if cmd.point_id >= cmd.sketch_ref.next_point_id {
        cmd.sketch_ref.next_point_id = cmd.point_id + 1
    }

    return true
}

add_point_command_destroy :: proc(cmd: AddPointCommand) {
    // No dynamic memory to free
}

// =============================================================================
// AddLineCommand Operations
// =============================================================================

add_line_command_execute :: proc(cmd: AddLineCommand) -> bool {
    cmd_mut := cmd
    cmd_mut.line_id = sketch.sketch_add_line(cmd.sketch_ref, cmd.start_id, cmd.end_id)
    cmd_mut.entity_index = len(cmd.sketch_ref.entities) - 1
    return true
}

add_line_command_undo :: proc(cmd: AddLineCommand) -> bool {
    // Remove the line entity
    if cmd.entity_index >= 0 && cmd.entity_index < len(cmd.sketch_ref.entities) {
        ordered_remove(&cmd.sketch_ref.entities, cmd.entity_index)

        // Update selected entity if needed
        if cmd.sketch_ref.selected_entity == cmd.entity_index {
            cmd.sketch_ref.selected_entity = -1
        } else if cmd.sketch_ref.selected_entity > cmd.entity_index {
            cmd.sketch_ref.selected_entity -= 1
        }

        return true
    }
    fmt.println("⚠️  Warning: Line entity not found for undo")
    return false
}

add_line_command_redo :: proc(cmd: AddLineCommand) -> bool {
    // Re-add the line with the same ID
    line := sketch.SketchLine{
        id = cmd.line_id,
        start_id = cmd.start_id,
        end_id = cmd.end_id,
    }

    // Insert at the original index if possible
    if cmd.entity_index >= len(cmd.sketch_ref.entities) {
        append(&cmd.sketch_ref.entities, line)
    } else {
        inject_at(&cmd.sketch_ref.entities, cmd.entity_index, line)
    }

    // Update next_entity_id if needed
    if cmd.line_id >= cmd.sketch_ref.next_entity_id {
        cmd.sketch_ref.next_entity_id = cmd.line_id + 1
    }

    return true
}

add_line_command_destroy :: proc(cmd: AddLineCommand) {
    // No dynamic memory to free
}

// =============================================================================
// AddCircleCommand Operations
// =============================================================================

add_circle_command_execute :: proc(cmd: AddCircleCommand) -> bool {
    cmd_mut := cmd
    cmd_mut.circle_id = sketch.sketch_add_circle(cmd.sketch_ref, cmd.center_id, cmd.radius)
    cmd_mut.entity_index = len(cmd.sketch_ref.entities) - 1
    return true
}

add_circle_command_undo :: proc(cmd: AddCircleCommand) -> bool {
    // Remove the circle entity
    if cmd.entity_index >= 0 && cmd.entity_index < len(cmd.sketch_ref.entities) {
        ordered_remove(&cmd.sketch_ref.entities, cmd.entity_index)

        // Update selected entity if needed
        if cmd.sketch_ref.selected_entity == cmd.entity_index {
            cmd.sketch_ref.selected_entity = -1
        } else if cmd.sketch_ref.selected_entity > cmd.entity_index {
            cmd.sketch_ref.selected_entity -= 1
        }

        return true
    }
    fmt.println("⚠️  Warning: Circle entity not found for undo")
    return false
}

add_circle_command_redo :: proc(cmd: AddCircleCommand) -> bool {
    // Re-add the circle with the same ID
    circle := sketch.SketchCircle{
        id = cmd.circle_id,
        center_id = cmd.center_id,
        radius = cmd.radius,
    }

    // Insert at the original index if possible
    if cmd.entity_index >= len(cmd.sketch_ref.entities) {
        append(&cmd.sketch_ref.entities, circle)
    } else {
        inject_at(&cmd.sketch_ref.entities, cmd.entity_index, circle)
    }

    // Update next_entity_id if needed
    if cmd.circle_id >= cmd.sketch_ref.next_entity_id {
        cmd.sketch_ref.next_entity_id = cmd.circle_id + 1
    }

    return true
}

add_circle_command_destroy :: proc(cmd: AddCircleCommand) {
    // No dynamic memory to free
}

// =============================================================================
// AddArcCommand Operations
// =============================================================================

add_arc_command_execute :: proc(cmd: AddArcCommand) -> bool {
    cmd_mut := cmd
    cmd_mut.arc_id = sketch.sketch_add_arc(cmd.sketch_ref, cmd.center_id, cmd.start_id, cmd.end_id, cmd.radius)
    cmd_mut.entity_index = len(cmd.sketch_ref.entities) - 1
    return true
}

add_arc_command_undo :: proc(cmd: AddArcCommand) -> bool {
    // Remove the arc entity
    if cmd.entity_index >= 0 && cmd.entity_index < len(cmd.sketch_ref.entities) {
        ordered_remove(&cmd.sketch_ref.entities, cmd.entity_index)

        // Update selected entity if needed
        if cmd.sketch_ref.selected_entity == cmd.entity_index {
            cmd.sketch_ref.selected_entity = -1
        } else if cmd.sketch_ref.selected_entity > cmd.entity_index {
            cmd.sketch_ref.selected_entity -= 1
        }

        return true
    }
    fmt.println("⚠️  Warning: Arc entity not found for undo")
    return false
}

add_arc_command_redo :: proc(cmd: AddArcCommand) -> bool {
    // Re-add the arc with the same ID
    arc := sketch.SketchArc{
        id = cmd.arc_id,
        center_id = cmd.center_id,
        start_id = cmd.start_id,
        end_id = cmd.end_id,
        radius = cmd.radius,
    }

    // Insert at the original index if possible
    if cmd.entity_index >= len(cmd.sketch_ref.entities) {
        append(&cmd.sketch_ref.entities, arc)
    } else {
        inject_at(&cmd.sketch_ref.entities, cmd.entity_index, arc)
    }

    // Update next_entity_id if needed
    if cmd.arc_id >= cmd.sketch_ref.next_entity_id {
        cmd.sketch_ref.next_entity_id = cmd.arc_id + 1
    }

    return true
}

add_arc_command_destroy :: proc(cmd: AddArcCommand) {
    // No dynamic memory to free
}

// =============================================================================
// DeleteEntityCommand Operations
// =============================================================================

delete_entity_command_execute :: proc(cmd: DeleteEntityCommand) -> bool {
    // Store the entity before deleting
    if cmd.entity_index >= 0 && cmd.entity_index < len(cmd.sketch_ref.entities) {
        cmd_mut := cmd
        cmd_mut.deleted_entity = cmd.sketch_ref.entities[cmd.entity_index]

        // Delete the entity
        ordered_remove(&cmd.sketch_ref.entities, cmd.entity_index)

        // Update selected entity if needed
        if cmd.sketch_ref.selected_entity == cmd.entity_index {
            cmd.sketch_ref.selected_entity = -1
        } else if cmd.sketch_ref.selected_entity > cmd.entity_index {
            cmd.sketch_ref.selected_entity -= 1
        }

        return true
    }
    fmt.println("❌ Entity index out of range")
    return false
}

delete_entity_command_undo :: proc(cmd: DeleteEntityCommand) -> bool {
    // Restore the entity at the original index
    if cmd.entity_index >= len(cmd.sketch_ref.entities) {
        append(&cmd.sketch_ref.entities, cmd.deleted_entity)
    } else {
        inject_at(&cmd.sketch_ref.entities, cmd.entity_index, cmd.deleted_entity)
    }

    return true
}

delete_entity_command_redo :: proc(cmd: DeleteEntityCommand) -> bool {
    // Delete the entity again
    if cmd.entity_index >= 0 && cmd.entity_index < len(cmd.sketch_ref.entities) {
        ordered_remove(&cmd.sketch_ref.entities, cmd.entity_index)

        // Update selected entity if needed
        if cmd.sketch_ref.selected_entity == cmd.entity_index {
            cmd.sketch_ref.selected_entity = -1
        } else if cmd.sketch_ref.selected_entity > cmd.entity_index {
            cmd.sketch_ref.selected_entity -= 1
        }

        return true
    }
    return false
}

delete_entity_command_destroy :: proc(cmd: DeleteEntityCommand) {
    // No dynamic memory to free
}
