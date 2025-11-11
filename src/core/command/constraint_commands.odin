// core/command/constraint_commands - Commands for constraint operations
package ohcad_command

import "core:fmt"
import sketch "../../features/sketch"

// =============================================================================
// Constraint Commands
// =============================================================================

// AddConstraintCommand - adds a constraint to a sketch
AddConstraintCommand :: struct {
    sketch_ref: ^sketch.Sketch2D,      // Reference to sketch
    constraint: sketch.Constraint,     // Constraint to add
    constraint_id: int,                // ID of created constraint (set during execute)
    constraint_index: int,             // Index in constraints array (set during execute)
}

// DeleteConstraintCommand - deletes a constraint from a sketch
DeleteConstraintCommand :: struct {
    sketch_ref: ^sketch.Sketch2D,      // Reference to sketch
    constraint_index: int,             // Index of constraint to delete
    deleted_constraint: sketch.Constraint,  // Stored constraint data for restoration
}

// =============================================================================
// AddConstraintCommand Operations
// =============================================================================

add_constraint_command_execute :: proc(cmd: AddConstraintCommand) -> bool {
    cmd_mut := cmd

    // Create a new constraint with the provided data
    new_constraint := sketch.Constraint{
        id = cmd.sketch_ref.next_constraint_id,
        type = cmd.constraint.type,  // Use the type from the provided constraint
        data = cmd.constraint.data,
        enabled = true,
    }

    cmd.sketch_ref.next_constraint_id += 1
    cmd_mut.constraint_id = new_constraint.id

    // Add the constraint
    append(&cmd.sketch_ref.constraints, new_constraint)
    cmd_mut.constraint_index = len(cmd.sketch_ref.constraints) - 1

    return true
}

add_constraint_command_undo :: proc(cmd: AddConstraintCommand) -> bool {
    // Remove the constraint
    if cmd.constraint_index >= 0 && cmd.constraint_index < len(cmd.sketch_ref.constraints) {
        ordered_remove(&cmd.sketch_ref.constraints, cmd.constraint_index)
        return true
    }
    fmt.println("⚠️  Warning: Constraint not found for undo")
    return false
}

add_constraint_command_redo :: proc(cmd: AddConstraintCommand) -> bool {
    // Re-add the constraint with the stored data
    new_constraint := sketch.Constraint{
        id = cmd.constraint_id,
        type = cmd.constraint.type,
        data = cmd.constraint.data,
        enabled = true,
    }

    // Insert at the original index if possible
    if cmd.constraint_index >= len(cmd.sketch_ref.constraints) {
        append(&cmd.sketch_ref.constraints, new_constraint)
    } else {
        inject_at(&cmd.sketch_ref.constraints, cmd.constraint_index, new_constraint)
    }

    // Update next_constraint_id if needed
    if cmd.constraint_id >= cmd.sketch_ref.next_constraint_id {
        cmd.sketch_ref.next_constraint_id = cmd.constraint_id + 1
    }

    return true
}

add_constraint_command_destroy :: proc(cmd: AddConstraintCommand) {
    // No dynamic memory to free
}

add_constraint_command_get_name :: proc(cmd: AddConstraintCommand) -> string {
    #partial switch cmd.constraint.type {
    case .Distance:
        return "Add Distance Constraint"
    case .Horizontal:
        return "Add Horizontal Constraint"
    case .Vertical:
        return "Add Vertical Constraint"
    case .Parallel:
        return "Add Parallel Constraint"
    case .Perpendicular:
        return "Add Perpendicular Constraint"
    case .Coincident:
        return "Add Coincident Constraint"
    case .Equal:
        return "Add Equal Constraint"
    case:
        return "Add Constraint"
    }
}

// =============================================================================
// DeleteConstraintCommand Operations
// =============================================================================

delete_constraint_command_execute :: proc(cmd: DeleteConstraintCommand) -> bool {
    // Store the constraint before deleting
    if cmd.constraint_index >= 0 && cmd.constraint_index < len(cmd.sketch_ref.constraints) {
        cmd_mut := cmd
        cmd_mut.deleted_constraint = cmd.sketch_ref.constraints[cmd.constraint_index]

        // Delete the constraint
        ordered_remove(&cmd.sketch_ref.constraints, cmd.constraint_index)

        return true
    }
    fmt.println("❌ Constraint index out of range")
    return false
}

delete_constraint_command_undo :: proc(cmd: DeleteConstraintCommand) -> bool {
    // Restore the constraint at the original index
    if cmd.constraint_index >= len(cmd.sketch_ref.constraints) {
        append(&cmd.sketch_ref.constraints, cmd.deleted_constraint)
    } else {
        inject_at(&cmd.sketch_ref.constraints, cmd.constraint_index, cmd.deleted_constraint)
    }

    return true
}

delete_constraint_command_redo :: proc(cmd: DeleteConstraintCommand) -> bool {
    // Delete the constraint again
    if cmd.constraint_index >= 0 && cmd.constraint_index < len(cmd.sketch_ref.constraints) {
        ordered_remove(&cmd.sketch_ref.constraints, cmd.constraint_index)
        return true
    }
    return false
}

delete_constraint_command_destroy :: proc(cmd: DeleteConstraintCommand) {
    // No dynamic memory to free
}
