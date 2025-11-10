// features/feature_tree - Parametric Feature Tree System
// Manages the history of design operations and dependencies
package ohcad_feature_tree

import "core:fmt"
import sketch "../../features/sketch"
import extrude "../../features/extrude"
import m "../../core/math"

// Feature types
FeatureType :: enum {
    Sketch,   // 2D sketch feature
    Extrude,  // Extrude/Pad operation
    Cut,      // Pocket/Cut operation (future)
    Revolve,  // Revolve operation (future)
    Fillet,   // Fillet operation (future)
    Chamfer,  // Chamfer operation (future)
}

// Feature status
FeatureStatus :: enum {
    Valid,          // Feature is up-to-date and valid
    NeedsUpdate,    // Parameters changed, needs regeneration
    Failed,         // Regeneration failed
    Suppressed,     // Feature is temporarily disabled
}

// Feature parameters (union of all feature types)
FeatureParams :: union {
    SketchParams,
    ExtrudeParams,
}

// Sketch feature parameters
SketchParams :: struct {
    sketch_ref: ^sketch.Sketch2D,  // Reference to sketch data
    name: string,                   // Sketch name
}

// Extrude feature parameters
ExtrudeParams :: struct {
    depth: f64,                            // Extrusion depth
    direction: extrude.ExtrudeDirection,   // Extrusion direction
    sketch_feature_id: int,                // ID of sketch to extrude
}

// Feature node - represents a single operation in the design history
FeatureNode :: struct {
    id: int,                        // Unique feature ID
    type: FeatureType,              // Feature type
    name: string,                   // User-friendly name
    params: FeatureParams,          // Feature parameters
    status: FeatureStatus,          // Current status

    // Dependencies
    parent_features: [dynamic]int,  // IDs of features this depends on

    // Result data
    result_solid: ^extrude.SimpleSolid,  // Resulting 3D solid (if applicable)

    // Metadata
    enabled: bool,                  // Is feature enabled?
    visible: bool,                  // Should result be visible?
}

// Feature tree - manages all features in order
FeatureTree :: struct {
    features: [dynamic]FeatureNode,  // All features in chronological order
    next_id: int,                    // Next available feature ID
    active_feature_id: int,          // Currently selected/active feature
}

// =============================================================================
// Feature Tree Management
// =============================================================================

// Initialize empty feature tree
feature_tree_init :: proc() -> FeatureTree {
    return FeatureTree{
        features = make([dynamic]FeatureNode),
        next_id = 0,
        active_feature_id = -1,
    }
}

// Destroy feature tree
feature_tree_destroy :: proc(tree: ^FeatureTree) {
    // Clean up each feature
    for &feature in tree.features {
        feature_node_destroy(&feature)
    }

    delete(tree.features)
}

// Destroy a single feature node
feature_node_destroy :: proc(node: ^FeatureNode) {
    // Clean up dependencies array
    delete(node.parent_features)

    // Clean up result data
    if node.result_solid != nil {
        result := extrude.ExtrudeResult{solid = node.result_solid}
        extrude.extrude_result_destroy(&result)
        node.result_solid = nil
    }

    // Clean up parameters
    switch &params in node.params {
    case SketchParams:
        // Sketch is owned by the feature
        if params.sketch_ref != nil {
            sketch.sketch_destroy(params.sketch_ref)
            free(params.sketch_ref)
            params.sketch_ref = nil
        }
    case ExtrudeParams:
        // No cleanup needed for extrude params
    }
}

// =============================================================================
// Adding Features
// =============================================================================

// Add sketch feature to tree
feature_tree_add_sketch :: proc(tree: ^FeatureTree, sk: ^sketch.Sketch2D, name: string) -> int {
    feature := FeatureNode{
        id = tree.next_id,
        type = .Sketch,
        name = name,
        params = SketchParams{
            sketch_ref = sk,
            name = name,
        },
        status = .Valid,
        parent_features = make([dynamic]int),
        result_solid = nil,
        enabled = true,
        visible = true,
    }

    tree.next_id += 1
    append(&tree.features, feature)
    tree.active_feature_id = feature.id

    fmt.printf("✅ Added sketch feature '%s' (ID=%d)\n", name, feature.id)

    return feature.id
}

// Add extrude feature to tree
feature_tree_add_extrude :: proc(
    tree: ^FeatureTree,
    sketch_feature_id: int,
    depth: f64,
    direction: extrude.ExtrudeDirection,
    name: string,
) -> int {

    // Validate sketch feature exists
    sketch_feature := feature_tree_get_feature(tree, sketch_feature_id)
    if sketch_feature == nil {
        fmt.printf("❌ Cannot add extrude: sketch feature %d not found\n", sketch_feature_id)
        return -1
    }

    if sketch_feature.type != .Sketch {
        fmt.printf("❌ Cannot add extrude: feature %d is not a sketch\n", sketch_feature_id)
        return -1
    }

    feature := FeatureNode{
        id = tree.next_id,
        type = .Extrude,
        name = name,
        params = ExtrudeParams{
            depth = depth,
            direction = direction,
            sketch_feature_id = sketch_feature_id,
        },
        status = .NeedsUpdate,  // Needs initial generation
        parent_features = make([dynamic]int),
        result_solid = nil,
        enabled = true,
        visible = true,
    }

    // Add dependency on sketch
    append(&feature.parent_features, sketch_feature_id)

    tree.next_id += 1
    append(&tree.features, feature)
    tree.active_feature_id = feature.id

    fmt.printf("✅ Added extrude feature '%s' (ID=%d, parent_sketch=%d)\n",
        name, feature.id, sketch_feature_id)

    return feature.id
}

// =============================================================================
// Feature Queries
// =============================================================================

// Get feature by ID
feature_tree_get_feature :: proc(tree: ^FeatureTree, feature_id: int) -> ^FeatureNode {
    for &feature in tree.features {
        if feature.id == feature_id {
            return &feature
        }
    }
    return nil
}

// Get active feature
feature_tree_get_active :: proc(tree: ^FeatureTree) -> ^FeatureNode {
    if tree.active_feature_id < 0 {
        return nil
    }
    return feature_tree_get_feature(tree, tree.active_feature_id)
}

// Set active feature
feature_tree_set_active :: proc(tree: ^FeatureTree, feature_id: int) {
    if feature_tree_get_feature(tree, feature_id) != nil {
        tree.active_feature_id = feature_id
        fmt.printf("Active feature: %d\n", feature_id)
    }
}

// Count features of a specific type
feature_tree_count_type :: proc(tree: ^FeatureTree, type: FeatureType) -> int {
    count := 0
    for feature in tree.features {
        if feature.type == type {
            count += 1
        }
    }
    return count
}

// =============================================================================
// Feature Regeneration
// =============================================================================

// Regenerate a single feature
feature_regenerate :: proc(tree: ^FeatureTree, feature_id: int) -> bool {
    feature := feature_tree_get_feature(tree, feature_id)
    if feature == nil {
        fmt.printf("❌ Cannot regenerate: feature %d not found\n", feature_id)
        return false
    }

    if !feature.enabled {
        fmt.printf("⏭️  Feature %d is disabled, skipping regeneration\n", feature_id)
        return true
    }

    fmt.printf("🔄 Regenerating feature %d (%s)...\n", feature_id, feature.name)

    switch feature.type {
    case .Sketch:
        // Sketch doesn't need regeneration - it's manually edited
        feature.status = .Valid
        return true

    case .Extrude:
        return feature_regenerate_extrude(tree, feature)

    case .Cut, .Revolve, .Fillet, .Chamfer:
        fmt.println("❌ Feature type not yet implemented")
        feature.status = .Failed
        return false
    }

    return false
}

// Regenerate extrude feature
feature_regenerate_extrude :: proc(tree: ^FeatureTree, feature: ^FeatureNode) -> bool {
    params, ok := feature.params.(ExtrudeParams)
    if !ok {
        fmt.println("❌ Invalid extrude parameters")
        feature.status = .Failed
        return false
    }

    // Get sketch feature
    sketch_feature := feature_tree_get_feature(tree, params.sketch_feature_id)
    if sketch_feature == nil {
        fmt.printf("❌ Sketch feature %d not found\n", params.sketch_feature_id)
        feature.status = .Failed
        return false
    }

    // Get sketch data
    sketch_params, sketch_ok := sketch_feature.params.(SketchParams)
    if !sketch_ok || sketch_params.sketch_ref == nil {
        fmt.println("❌ Invalid sketch reference")
        feature.status = .Failed
        return false
    }

    // Clean up old result
    if feature.result_solid != nil {
        old_result := extrude.ExtrudeResult{solid = feature.result_solid}
        extrude.extrude_result_destroy(&old_result)
        feature.result_solid = nil
    }

    // Perform extrusion
    extrude_params := extrude.ExtrudeParams{
        depth = params.depth,
        direction = params.direction,
    }

    result := extrude.extrude_sketch(sketch_params.sketch_ref, extrude_params)

    if !result.success {
        fmt.printf("❌ Extrude failed: %s\n", result.message)
        feature.status = .Failed
        return false
    }

    // Store result
    feature.result_solid = result.solid
    feature.status = .Valid

    fmt.printf("✅ Extrude regenerated successfully\n")

    return true
}

// Regenerate all features in tree (in order)
feature_tree_regenerate_all :: proc(tree: ^FeatureTree) -> bool {
    fmt.println("\n=== Regenerating All Features ===")

    success := true

    for &feature in tree.features {
        if !feature_regenerate(tree, feature.id) {
            success = false
            fmt.printf("⚠️  Feature %d (%s) failed to regenerate\n", feature.id, feature.name)
        }
    }

    if success {
        fmt.println("✅ All features regenerated successfully")
    } else {
        fmt.println("⚠️  Some features failed to regenerate")
    }

    return success
}

// Mark feature and dependents as needing update
feature_tree_mark_dirty :: proc(tree: ^FeatureTree, feature_id: int) {
    feature := feature_tree_get_feature(tree, feature_id)
    if feature == nil {
        return
    }

    // Mark this feature
    if feature.status == .Valid {
        feature.status = .NeedsUpdate
        fmt.printf("🔄 Marked feature %d (%s) as needing update\n", feature.id, feature.name)
    }

    // Mark all dependent features
    for &dependent in tree.features {
        for parent_id in dependent.parent_features {
            if parent_id == feature_id {
                feature_tree_mark_dirty(tree, dependent.id)
                break
            }
        }
    }
}

// =============================================================================
// Debugging & Display
// =============================================================================

// Print feature tree structure
feature_tree_print :: proc(tree: ^FeatureTree) {
    fmt.println("\n=== Feature Tree ===")
    fmt.printf("Total features: %d\n", len(tree.features))
    fmt.printf("Active feature: %d\n", tree.active_feature_id)

    for feature in tree.features {
        status_icon := "✅"
        switch feature.status {
        case .Valid:         status_icon = "✅"
        case .NeedsUpdate:   status_icon = "🔄"
        case .Failed:        status_icon = "❌"
        case .Suppressed:    status_icon = "⏸️"
        }

        enabled_str := feature.enabled ? "" : " (disabled)"
        visible_str := feature.visible ? "" : " (hidden)"

        fmt.printf("  %s Feature %d: %s - %v%s%s\n",
            status_icon, feature.id, feature.name, feature.type, enabled_str, visible_str)

        if len(feature.parent_features) > 0 {
            fmt.printf("      Parents: %v\n", feature.parent_features)
        }

        // Print type-specific info
        switch params in feature.params {
        case SketchParams:
            if params.sketch_ref != nil {
                fmt.printf("      Points: %d, Entities: %d, Constraints: %d\n",
                    len(params.sketch_ref.points),
                    len(params.sketch_ref.entities),
                    len(params.sketch_ref.constraints))
            }
        case ExtrudeParams:
            fmt.printf("      Depth: %.3f, Direction: %v\n", params.depth, params.direction)
            if feature.result_solid != nil {
                fmt.printf("      Result: %d vertices, %d edges\n",
                    len(feature.result_solid.vertices),
                    len(feature.result_solid.edges))
            }
        }
    }

    fmt.println()
}
