// features/feature_tree - Parametric Feature Tree System
// Manages the history of design operations and dependencies
package ohcad_feature_tree

import "core:fmt"
import sketch "../../features/sketch"
import extrude "../../features/extrude"
import cut "../../features/cut"
import revolve "../../features/revolve"
import m "../../core/math"
import occt "../../core/geometry/occt"

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
    CutParams,
    RevolveParams,
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

// Cut feature parameters
CutParams :: struct {
    depth: f64,                        // Cut depth
    direction: cut.CutDirection,       // Cut direction
    sketch_feature_id: int,            // ID of sketch to cut with
    base_feature_id: int,              // ID of solid to cut from
}

// Revolve feature parameters
RevolveParams :: struct {
    angle: f64,                          // Revolution angle in degrees (0-360)
    segments: int,                       // Number of rotation steps
    axis_type: revolve.RevolveAxis,      // Which axis to revolve around
    sketch_feature_id: int,              // ID of sketch to revolve
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
    occt_shape: occt.Shape,                  // NEW: Exact B-Rep geometry for boolean/fillet/chamfer operations
    result_solid: ^extrude.SimpleSolid,      // Tessellated mesh for rendering

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

    // Clean up OCCT shape (exact geometry)
    if node.occt_shape != nil {
        occt.delete_shape(node.occt_shape)
        node.occt_shape = nil
    }

    // Clean up result data (tessellated mesh)
    if node.result_solid != nil {
        result := extrude.ExtrudeResult{solid = node.result_solid}
        extrude.extrude_result_destroy(&result)
        node.result_solid = nil
    }

    // Clean up parameters
    #partial switch &params in node.params {
    case SketchParams:
        // Sketch is owned by the feature
        if params.sketch_ref != nil {
            sketch.sketch_destroy(params.sketch_ref)
            free(params.sketch_ref)
            params.sketch_ref = nil
        }
    case ExtrudeParams:
        // No cleanup needed for extrude params
    case CutParams:
        // No cleanup needed for cut params
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

// Add cut feature to tree
feature_tree_add_cut :: proc(
    tree: ^FeatureTree,
    sketch_feature_id: int,
    base_feature_id: int,
    depth: f64,
    direction: cut.CutDirection,
    name: string,
) -> int {

    // Validate sketch feature exists
    sketch_feature := feature_tree_get_feature(tree, sketch_feature_id)
    if sketch_feature == nil {
        fmt.printf("❌ Cannot add cut: sketch feature %d not found\n", sketch_feature_id)
        return -1
    }

    if sketch_feature.type != .Sketch {
        fmt.printf("❌ Cannot add cut: feature %d is not a sketch\n", sketch_feature_id)
        return -1
    }

    // Validate base feature exists and has a solid
    base_feature := feature_tree_get_feature(tree, base_feature_id)
    if base_feature == nil {
        fmt.printf("❌ Cannot add cut: base feature %d not found\n", base_feature_id)
        return -1
    }

    if base_feature.result_solid == nil {
        fmt.printf("❌ Cannot add cut: base feature %d has no solid\n", base_feature_id)
        return -1
    }

    feature := FeatureNode{
        id = tree.next_id,
        type = .Cut,
        name = name,
        params = CutParams{
            depth = depth,
            direction = direction,
            sketch_feature_id = sketch_feature_id,
            base_feature_id = base_feature_id,
        },
        status = .NeedsUpdate,  // Needs initial generation
        parent_features = make([dynamic]int),
        result_solid = nil,
        enabled = true,
        visible = true,
    }

    // Add dependencies on sketch and base solid
    append(&feature.parent_features, sketch_feature_id)
    append(&feature.parent_features, base_feature_id)

    tree.next_id += 1
    append(&tree.features, feature)
    tree.active_feature_id = feature.id

    fmt.printf("✅ Added cut feature '%s' (ID=%d, parent_sketch=%d, base=%d)\n",
        name, feature.id, sketch_feature_id, base_feature_id)

    return feature.id
}

// Add revolve feature to tree
feature_tree_add_revolve :: proc(
    tree: ^FeatureTree,
    sketch_feature_id: int,
    angle: f64,
    segments: int,
    axis_type: revolve.RevolveAxis,
    name: string,
) -> int {

    // Validate sketch feature exists
    sketch_feature := feature_tree_get_feature(tree, sketch_feature_id)
    if sketch_feature == nil {
        fmt.printf("❌ Cannot add revolve: sketch feature %d not found\n", sketch_feature_id)
        return -1
    }

    if sketch_feature.type != .Sketch {
        fmt.printf("❌ Cannot add revolve: feature %d is not a sketch\n", sketch_feature_id)
        return -1
    }

    feature := FeatureNode{
        id = tree.next_id,
        type = .Revolve,
        name = name,
        params = RevolveParams{
            angle = angle,
            segments = segments,
            axis_type = axis_type,
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

    fmt.printf("✅ Added revolve feature '%s' (ID=%d, parent_sketch=%d, angle=%.1f°, segments=%d)\n",
        name, feature.id, sketch_feature_id, angle, segments)

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

    case .Cut:
        return feature_regenerate_cut(tree, feature)

    case .Revolve:
        return feature_regenerate_revolve(tree, feature)

    case .Fillet, .Chamfer:
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

    // Clean up old OCCT shape
    if feature.occt_shape != nil {
        occt.delete_shape(feature.occt_shape)
        feature.occt_shape = nil
    }

    // Clean up old result solid
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

    // Store both exact geometry and tessellated mesh
    feature.occt_shape = result.occt_shape    // Exact B-Rep result
    feature.result_solid = result.solid        // Tessellated mesh for rendering
    feature.status = .Valid

    fmt.printf("✅ Extrude regenerated successfully\n")

    return true
}

// Regenerate cut feature
feature_regenerate_cut :: proc(tree: ^FeatureTree, feature: ^FeatureNode) -> bool {
    params, ok := feature.params.(CutParams)
    if !ok {
        fmt.println("❌ Invalid cut parameters")
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

    // Get base feature
    base_feature := feature_tree_get_feature(tree, params.base_feature_id)
    if base_feature == nil {
        fmt.printf("❌ Base feature %d not found\n", params.base_feature_id)
        feature.status = .Failed
        return false
    }

    if base_feature.result_solid == nil {
        fmt.printf("❌ Base feature %d has no solid\n", params.base_feature_id)
        feature.status = .Failed
        return false
    }

    // Validate base feature has OCCT shape for exact boolean operations
    if base_feature.occt_shape == nil {
        fmt.printf("❌ Base feature %d has no OCCT shape (required for boolean operations)\n", params.base_feature_id)
        feature.status = .Failed
        return false
    }

    // Clean up old OCCT shape
    if feature.occt_shape != nil {
        occt.delete_shape(feature.occt_shape)
        feature.occt_shape = nil
    }

    // Clean up old result solid
    if feature.result_solid != nil {
        old_result := cut.CutResult{solid = feature.result_solid}
        cut.cut_result_destroy(&old_result)
        feature.result_solid = nil
    }

    // Perform cut with OCCT boolean operations
    cut_params := cut.CutParams{
        depth = params.depth,
        direction = params.direction,
        base_solid = base_feature.result_solid,  // For backward compatibility (will be deprecated)
        base_shape = base_feature.occt_shape,     // NEW: Exact B-Rep geometry for boolean operations
    }

    result := cut.cut_sketch(sketch_params.sketch_ref, cut_params)

    if !result.success {
        fmt.printf("❌ Cut failed: %s\n", result.message)
        feature.status = .Failed
        return false
    }

    // Store both exact geometry and tessellated mesh
    feature.occt_shape = result.occt_shape    // Exact B-Rep result
    feature.result_solid = result.solid        // Tessellated mesh for rendering
    feature.status = .Valid

    fmt.printf("✅ Cut regenerated successfully\n")

    return true
}

// Regenerate revolve feature
feature_regenerate_revolve :: proc(tree: ^FeatureTree, feature: ^FeatureNode) -> bool {
    params, ok := feature.params.(RevolveParams)
    if !ok {
        fmt.println("❌ Invalid revolve parameters")
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
        old_result := revolve.RevolveResult{solid = feature.result_solid}
        revolve.revolve_result_destroy(&old_result)
        feature.result_solid = nil
    }

    // Perform revolve
    revolve_params := revolve.RevolveParams{
        angle = params.angle,
        segments = params.segments,
        axis_type = params.axis_type,
        axis_point = m.Vec3{0, 0, 0},  // Will be calculated from sketch plane
        axis_dir = m.Vec3{0, 1, 0},    // Will be calculated from sketch plane
    }

    result := revolve.revolve_sketch(sketch_params.sketch_ref, revolve_params)

    if !result.success {
        fmt.printf("❌ Revolve failed: %s\n", result.message)
        feature.status = .Failed
        return false
    }

    // Store result
    feature.result_solid = result.solid
    feature.status = .Valid

    fmt.printf("✅ Revolve regenerated successfully\n")

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
// Feature Parameter Modification
// =============================================================================

// Change extrude depth
change_extrude_depth :: proc(tree: ^FeatureTree, feature_id: int, new_depth: f64) -> bool {
    feature := feature_tree_get_feature(tree, feature_id)
    if feature == nil {
        return false
    }

    if feature.type != .Extrude {
        fmt.println("❌ Feature is not an extrude")
        return false
    }

    params, ok := &feature.params.(ExtrudeParams)
    if !ok {
        return false
    }

    old_depth := params.depth
    params.depth = new_depth

    fmt.printf("📏 Changed extrude depth: %.3f → %.3f\n", old_depth, new_depth)

    // Mark feature as needing update
    feature_tree_mark_dirty(tree, feature_id)

    return true
}

// Change cut depth
change_cut_depth :: proc(tree: ^FeatureTree, feature_id: int, new_depth: f64) -> bool {
    feature := feature_tree_get_feature(tree, feature_id)
    if feature == nil {
        return false
    }

    if feature.type != .Cut {
        fmt.println("❌ Feature is not a cut")
        return false
    }

    params, ok := &feature.params.(CutParams)
    if !ok {
        return false
    }

    old_depth := params.depth
    params.depth = new_depth

    fmt.printf("📏 Changed cut depth: %.3f → %.3f\n", old_depth, new_depth)

    // Mark feature as needing update
    feature_tree_mark_dirty(tree, feature_id)

    return true
}

// Change revolve angle
change_revolve_angle :: proc(tree: ^FeatureTree, feature_id: int, new_angle: f64) -> bool {
    feature := feature_tree_get_feature(tree, feature_id)
    if feature == nil {
        return false
    }

    if feature.type != .Revolve {
        fmt.println("❌ Feature is not a revolve")
        return false
    }

    params, ok := &feature.params.(RevolveParams)
    if !ok {
        return false
    }

    old_angle := params.angle
    params.angle = new_angle

    // Clamp angle to valid range [1, 360]
    if params.angle < 1.0 {
        params.angle = 1.0
    }
    if params.angle > 360.0 {
        params.angle = 360.0
    }

    fmt.printf("📐 Changed revolve angle: %.1f° → %.1f°\n", old_angle, params.angle)

    // Mark feature as needing update
    feature_tree_mark_dirty(tree, feature_id)

    return true
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
        #partial switch params in feature.params {
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
        case CutParams:
            fmt.printf("      Depth: %.3f, Direction: %v, Base: %d\n",
                params.depth, params.direction, params.base_feature_id)
            if feature.result_solid != nil {
                fmt.printf("      Result: %d vertices, %d edges\n",
                    len(feature.result_solid.vertices),
                    len(feature.result_solid.edges))
            }
        }
    }

    fmt.println()
}
