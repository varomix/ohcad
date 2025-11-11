// core/command - Command pattern for undo/redo system
package ohcad_command

import "core:fmt"
import sketch "../../features/sketch"
import ftree "../../features/feature_tree"

// Command interface - all commands must implement these methods
Command :: union {
    // Sketch commands
    AddPointCommand,
    AddLineCommand,
    AddCircleCommand,
    AddArcCommand,
    DeleteEntityCommand,

    // Feature commands
    AddFeatureCommand,
    DeleteFeatureCommand,
    ModifyFeatureCommand,

    // Constraint commands
    AddConstraintCommand,
    DeleteConstraintCommand,
}

// Command history manager
CommandHistory :: struct {
    undo_stack: [dynamic]Command,     // Commands that can be undone
    redo_stack: [dynamic]Command,     // Commands that can be redone
    max_history: int,                 // Maximum history depth
}

// =============================================================================
// Command History Management
// =============================================================================

// Initialize command history
command_history_init :: proc(max_history := 50) -> CommandHistory {
    return CommandHistory{
        undo_stack = make([dynamic]Command, 0, max_history),
        redo_stack = make([dynamic]Command, 0, max_history),
        max_history = max_history,
    }
}

// Destroy command history
command_history_destroy :: proc(history: ^CommandHistory) {
    // Clean up all commands
    for cmd in history.undo_stack {
        command_destroy(cmd)
    }
    for cmd in history.redo_stack {
        command_destroy(cmd)
    }

    delete(history.undo_stack)
    delete(history.redo_stack)
}

// Execute a command and add it to history
command_history_execute :: proc(history: ^CommandHistory, cmd: Command) -> bool {
    // Execute the command
    if !command_execute(cmd) {
        fmt.println("❌ Command execution failed")
        command_destroy(cmd)
        return false
    }

    // Add to undo stack
    append(&history.undo_stack, cmd)

    // Limit stack size
    if len(history.undo_stack) > history.max_history {
        // Remove oldest command
        old_cmd := history.undo_stack[0]
        command_destroy(old_cmd)
        ordered_remove(&history.undo_stack, 0)
    }

    // Clear redo stack when new command is executed
    for redo_cmd in history.redo_stack {
        command_destroy(redo_cmd)
    }
    clear(&history.redo_stack)

    return true
}

// Undo the last command
command_history_undo :: proc(history: ^CommandHistory) -> bool {
    if len(history.undo_stack) == 0 {
        fmt.println("Nothing to undo")
        return false
    }

    // Pop from undo stack
    cmd := pop(&history.undo_stack)

    // Undo the command
    if !command_undo(cmd) {
        fmt.println("❌ Command undo failed")
        command_destroy(cmd)
        return false
    }

    // Move to redo stack
    append(&history.redo_stack, cmd)

    fmt.printf("✅ Undone: %s\n", command_get_name(cmd))
    return true
}

// Redo the last undone command
command_history_redo :: proc(history: ^CommandHistory) -> bool {
    if len(history.redo_stack) == 0 {
        fmt.println("Nothing to redo")
        return false
    }

    // Pop from redo stack
    cmd := pop(&history.redo_stack)

    // Redo the command
    if !command_redo(cmd) {
        fmt.println("❌ Command redo failed")
        command_destroy(cmd)
        return false
    }

    // Move to undo stack
    append(&history.undo_stack, cmd)

    fmt.printf("✅ Redone: %s\n", command_get_name(cmd))
    return true
}

// Check if undo is available
command_history_can_undo :: proc(history: ^CommandHistory) -> bool {
    return len(history.undo_stack) > 0
}

// Check if redo is available
command_history_can_redo :: proc(history: ^CommandHistory) -> bool {
    return len(history.redo_stack) > 0
}

// Get name of next undo command
command_history_get_undo_name :: proc(history: ^CommandHistory) -> string {
    if len(history.undo_stack) == 0 {
        return ""
    }
    return command_get_name(history.undo_stack[len(history.undo_stack) - 1])
}

// Get name of next redo command
command_history_get_redo_name :: proc(history: ^CommandHistory) -> string {
    if len(history.redo_stack) == 0 {
        return ""
    }
    return command_get_name(history.redo_stack[len(history.redo_stack) - 1])
}

// =============================================================================
// Command Operations
// =============================================================================

// Execute a command
command_execute :: proc(cmd: Command) -> bool {
    switch c in cmd {
    case AddPointCommand:
        return add_point_command_execute(c)
    case AddLineCommand:
        return add_line_command_execute(c)
    case AddCircleCommand:
        return add_circle_command_execute(c)
    case AddArcCommand:
        return add_arc_command_execute(c)
    case DeleteEntityCommand:
        return delete_entity_command_execute(c)
    case AddFeatureCommand:
        return add_feature_command_execute(c)
    case DeleteFeatureCommand:
        return delete_feature_command_execute(c)
    case ModifyFeatureCommand:
        return modify_feature_command_execute(c)
    case AddConstraintCommand:
        return add_constraint_command_execute(c)
    case DeleteConstraintCommand:
        return delete_constraint_command_execute(c)
    }
    return false
}

// Undo a command
command_undo :: proc(cmd: Command) -> bool {
    switch c in cmd {
    case AddPointCommand:
        return add_point_command_undo(c)
    case AddLineCommand:
        return add_line_command_undo(c)
    case AddCircleCommand:
        return add_circle_command_undo(c)
    case AddArcCommand:
        return add_arc_command_undo(c)
    case DeleteEntityCommand:
        return delete_entity_command_undo(c)
    case AddFeatureCommand:
        return add_feature_command_undo(c)
    case DeleteFeatureCommand:
        return delete_feature_command_undo(c)
    case ModifyFeatureCommand:
        return modify_feature_command_undo(c)
    case AddConstraintCommand:
        return add_constraint_command_undo(c)
    case DeleteConstraintCommand:
        return delete_constraint_command_undo(c)
    }
    return false
}

// Redo a command
command_redo :: proc(cmd: Command) -> bool {
    switch c in cmd {
    case AddPointCommand:
        return add_point_command_redo(c)
    case AddLineCommand:
        return add_line_command_redo(c)
    case AddCircleCommand:
        return add_circle_command_redo(c)
    case AddArcCommand:
        return add_arc_command_redo(c)
    case DeleteEntityCommand:
        return delete_entity_command_redo(c)
    case AddFeatureCommand:
        return add_feature_command_redo(c)
    case DeleteFeatureCommand:
        return delete_feature_command_redo(c)
    case ModifyFeatureCommand:
        return modify_feature_command_redo(c)
    case AddConstraintCommand:
        return add_constraint_command_redo(c)
    case DeleteConstraintCommand:
        return delete_constraint_command_redo(c)
    }
    return false
}

// Get command name
command_get_name :: proc(cmd: Command) -> string {
    switch c in cmd {
    case AddPointCommand:
        return "Add Point"
    case AddLineCommand:
        return "Add Line"
    case AddCircleCommand:
        return "Add Circle"
    case AddArcCommand:
        return "Add Arc"
    case DeleteEntityCommand:
        return "Delete Entity"
    case AddFeatureCommand:
        return add_feature_command_get_name(c)
    case DeleteFeatureCommand:
        return "Delete Feature"
    case ModifyFeatureCommand:
        return "Modify Feature"
    case AddConstraintCommand:
        return add_constraint_command_get_name(c)
    case DeleteConstraintCommand:
        return "Delete Constraint"
    }
    return "Unknown Command"
}

// Destroy command and free memory
command_destroy :: proc(cmd: Command) {
    switch c in cmd {
    case AddPointCommand:
        add_point_command_destroy(c)
    case AddLineCommand:
        add_line_command_destroy(c)
    case AddCircleCommand:
        add_circle_command_destroy(c)
    case AddArcCommand:
        add_arc_command_destroy(c)
    case DeleteEntityCommand:
        delete_entity_command_destroy(c)
    case AddFeatureCommand:
        add_feature_command_destroy(c)
    case DeleteFeatureCommand:
        delete_feature_command_destroy(c)
    case ModifyFeatureCommand:
        modify_feature_command_destroy(c)
    case AddConstraintCommand:
        add_constraint_command_destroy(c)
    case DeleteConstraintCommand:
        delete_constraint_command_destroy(c)
    }
}
