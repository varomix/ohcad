// core/command/feature_commands - Commands for feature operations
package ohcad_command

import "core:fmt"
import ftree "../../features/feature_tree"
import sketch "../../features/sketch"
import extrude "../../features/extrude"

// =============================================================================
// Feature Commands
// =============================================================================

// AddFeatureCommand - adds a feature to the feature tree
AddFeatureCommand :: struct {
    tree_ref: ^ftree.FeatureTree,    // Reference to feature tree
    feature_type: ftree.FeatureType,  // Type of feature to add
    params: ftree.FeatureParams,      // Feature parameters
    feature_id: int,                  // ID of created feature (set during execute)
    feature_index: int,               // Index in features array (set during execute)
}

// DeleteFeatureCommand - deletes a feature from the feature tree
DeleteFeatureCommand :: struct {
    tree_ref: ^ftree.FeatureTree,    // Reference to feature tree
    feature_index: int,               // Index of feature to delete
    deleted_feature: ftree.FeatureNode,  // Stored feature data for restoration
}

// ModifyFeatureCommand - modifies feature parameters
ModifyFeatureCommand :: struct {
    tree_ref: ^ftree.FeatureTree,    // Reference to feature tree
    feature_index: int,               // Index of feature to modify
    old_params: ftree.FeatureParams,  // Old parameter values
    new_params: ftree.FeatureParams,  // New parameter values
}

// =============================================================================
// AddFeatureCommand Operations
// =============================================================================

add_feature_command_execute :: proc(cmd: AddFeatureCommand) -> bool {
    cmd_mut := cmd

    // Add feature based on type
    switch cmd.feature_type {
    case .Sketch:
        #partial switch params in cmd.params {
        case ftree.SketchParams:
            cmd_mut.feature_id = ftree.feature_tree_add_sketch(cmd.tree_ref, params.sketch_ref, params.name)
            cmd_mut.feature_index = len(cmd.tree_ref.features) - 1
            return true
        }

    case .Extrude:
        #partial switch params in cmd.params {
        case ftree.ExtrudeParams:
            // Generate a default name
            extrude_count := ftree.feature_tree_count_type(cmd.tree_ref, .Extrude)
            name := fmt.aprintf("Extrude%03d", extrude_count + 1)

            cmd_mut.feature_id = ftree.feature_tree_add_extrude(cmd.tree_ref, params.sketch_feature_id, params.depth, params.direction, name)
            cmd_mut.feature_index = len(cmd.tree_ref.features) - 1
            return true
        }

    case .Cut:
        #partial switch params in cmd.params {
        case ftree.CutParams:
            // Generate a default name
            cut_count := ftree.feature_tree_count_type(cmd.tree_ref, .Cut)
            name := fmt.aprintf("Cut%03d", cut_count + 1)

            cmd_mut.feature_id = ftree.feature_tree_add_cut(cmd.tree_ref, params.sketch_feature_id, params.base_feature_id, params.depth, params.direction, name)
            cmd_mut.feature_index = len(cmd.tree_ref.features) - 1
            return true
        }

    case .Revolve:
        #partial switch params in cmd.params {
        case ftree.RevolveParams:
            // Generate a default name
            revolve_count := ftree.feature_tree_count_type(cmd.tree_ref, .Revolve)
            name := fmt.aprintf("Revolve%03d", revolve_count + 1)

            cmd_mut.feature_id = ftree.feature_tree_add_revolve(cmd.tree_ref, params.sketch_feature_id, params.angle, params.segments, params.axis_type, name)
            cmd_mut.feature_index = len(cmd.tree_ref.features) - 1
            return true
        }

    case .Fillet, .Chamfer:
        fmt.println("⚠️  Feature type not yet implemented")
        return false
    }

    return false
}

add_feature_command_undo :: proc(cmd: AddFeatureCommand) -> bool {
    // Remove the feature from the tree
    if cmd.feature_index >= 0 && cmd.feature_index < len(cmd.tree_ref.features) {
        // Get reference to the feature before removing
        feature := &cmd.tree_ref.features[cmd.feature_index]

        // Clean up feature resources
        ftree.feature_node_destroy(feature)

        // Remove from array
        ordered_remove(&cmd.tree_ref.features, cmd.feature_index)

        // Update active feature if needed
        if cmd.tree_ref.active_feature_id == cmd.feature_id {
            cmd.tree_ref.active_feature_id = -1
        }

        return true
    }
    fmt.println("⚠️  Warning: Feature not found for undo")
    return false
}

add_feature_command_redo :: proc(cmd: AddFeatureCommand) -> bool {
    // Re-execute the command
    return add_feature_command_execute(cmd)
}

add_feature_command_destroy :: proc(cmd: AddFeatureCommand) {
    // No dynamic memory to free - feature tree manages feature data
}

add_feature_command_get_name :: proc(cmd: AddFeatureCommand) -> string {
    switch cmd.feature_type {
    case .Sketch:
        return "Add Sketch"
    case .Extrude:
        return "Add Extrude"
    case .Cut:
        return "Add Cut"
    case .Revolve:
        return "Add Revolve"
    case .Fillet:
        return "Add Fillet"
    case .Chamfer:
        return "Add Chamfer"
    }
    return "Add Feature"
}

// =============================================================================
// DeleteFeatureCommand Operations
// =============================================================================

delete_feature_command_execute :: proc(cmd: DeleteFeatureCommand) -> bool {
    // Store the feature before deleting
    if cmd.feature_index >= 0 && cmd.feature_index < len(cmd.tree_ref.features) {
        cmd_mut := cmd

        // Copy the feature (shallow copy - we'll need to handle resources carefully)
        cmd_mut.deleted_feature = cmd.tree_ref.features[cmd.feature_index]

        // NOTE: We don't call feature_node_destroy here because we want to keep the data
        // for potential redo. The feature data will be freed when the command is destroyed.

        // Remove from array
        ordered_remove(&cmd.tree_ref.features, cmd.feature_index)

        // Update active feature if needed
        if cmd.tree_ref.active_feature_id == cmd.deleted_feature.id {
            cmd.tree_ref.active_feature_id = -1
        }

        return true
    }
    fmt.println("❌ Feature index out of range")
    return false
}

delete_feature_command_undo :: proc(cmd: DeleteFeatureCommand) -> bool {
    // Restore the feature at the original index
    if cmd.feature_index >= len(cmd.tree_ref.features) {
        append(&cmd.tree_ref.features, cmd.deleted_feature)
    } else {
        inject_at(&cmd.tree_ref.features, cmd.feature_index, cmd.deleted_feature)
    }

    // Mark feature as needing update
    cmd.tree_ref.features[cmd.feature_index].status = .NeedsUpdate

    return true
}

delete_feature_command_redo :: proc(cmd: DeleteFeatureCommand) -> bool {
    // Delete the feature again
    if cmd.feature_index >= 0 && cmd.feature_index < len(cmd.tree_ref.features) {
        ordered_remove(&cmd.tree_ref.features, cmd.feature_index)

        // Update active feature if needed
        if cmd.tree_ref.active_feature_id == cmd.deleted_feature.id {
            cmd.tree_ref.active_feature_id = -1
        }

        return true
    }
    return false
}

delete_feature_command_destroy :: proc(cmd: DeleteFeatureCommand) {
    // TODO: Clean up the stored feature data properly
    // Currently not implemented because we need mutable access to cmd
    // ftree.feature_node_destroy(&cmd.deleted_feature)
}

// =============================================================================
// ModifyFeatureCommand Operations
// =============================================================================

modify_feature_command_execute :: proc(cmd: ModifyFeatureCommand) -> bool {
    // Apply new parameters
    if cmd.feature_index >= 0 && cmd.feature_index < len(cmd.tree_ref.features) {
        cmd.tree_ref.features[cmd.feature_index].params = cmd.new_params
        cmd.tree_ref.features[cmd.feature_index].status = .NeedsUpdate
        return true
    }
    fmt.println("❌ Feature index out of range")
    return false
}

modify_feature_command_undo :: proc(cmd: ModifyFeatureCommand) -> bool {
    // Restore old parameters
    if cmd.feature_index >= 0 && cmd.feature_index < len(cmd.tree_ref.features) {
        cmd.tree_ref.features[cmd.feature_index].params = cmd.old_params
        cmd.tree_ref.features[cmd.feature_index].status = .NeedsUpdate
        return true
    }
    return false
}

modify_feature_command_redo :: proc(cmd: ModifyFeatureCommand) -> bool {
    // Re-apply new parameters
    return modify_feature_command_execute(cmd)
}

modify_feature_command_destroy :: proc(cmd: ModifyFeatureCommand) {
    // No dynamic memory to free
}
