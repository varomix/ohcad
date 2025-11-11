// features/sketch - Profile Detection for Extrusion
// Detects closed vs open profiles in sketches
package ohcad_sketch

import "core:fmt"
import "core:slice"

// Profile type classification
ProfileType :: enum {
    None,      // No profile detected
    Open,      // Has endpoints (cannot extrude)
    Closed,    // Forms complete loop (can extrude)
}

// Profile information
Profile :: struct {
    type: ProfileType,
    entities: [dynamic]int,  // Entity IDs forming the profile
    points: [dynamic]int,    // Point IDs in the profile (ordered for closed profiles)
}

// Edge in connectivity graph
Edge :: struct {
    entity_id: int,
    start_point: int,
    end_point: int,
}

// =============================================================================
// Profile Detection
// =============================================================================

// Detect all profiles in the sketch
sketch_detect_profiles :: proc(sketch: ^Sketch2D) -> [dynamic]Profile {
    profiles := make([dynamic]Profile, 0)

    // First, detect standalone circles (they are closed profiles on their own)
    for entity, idx in sketch.entities {
        if circle, is_circle := entity.(SketchCircle); is_circle {
            profile := Profile{
                type = .Closed,
                entities = make([dynamic]int, 1),
                points = make([dynamic]int, 1),
            }
            profile.entities[0] = idx
            profile.points[0] = circle.center_id  // Store center point ID
            append(&profiles, profile)
        }
    }

    // Build connectivity graph for line-based entities
    edges := build_edge_graph(sketch)
    defer delete(edges)

    if len(edges) == 0 {
        return profiles
    }

    // Track which entities have been assigned to profiles
    used_entities := make(map[int]bool)
    defer delete(used_entities)

    // Find connected components (line-based profiles)
    for edge, idx in edges {
        if used_entities[edge.entity_id] {
            continue
        }

        // Start a new profile from this edge
        profile := trace_profile(sketch, edges, edge.entity_id, &used_entities)

        if profile.type != .None {
            append(&profiles, profile)
        }
    }

    return profiles
}

// Build edge connectivity graph from sketch entities
build_edge_graph :: proc(sketch: ^Sketch2D) -> [dynamic]Edge {
    edges := make([dynamic]Edge, 0)

    for entity, idx in sketch.entities {
        switch e in entity {
        case SketchLine:
            // Line connects two points
            edge := Edge{
                entity_id = idx,
                start_point = e.start_id,
                end_point = e.end_id,
            }
            append(&edges, edge)

        case SketchCircle:
            // Circle is a special closed profile on its own
            // We'll handle this separately
            // For now, skip circles in connectivity graph

        case SketchArc:
            // Arc connects two endpoints
            // TODO: Implement arc support
        }
    }

    return edges
}

// Trace a profile starting from a given entity
trace_profile :: proc(
    sketch: ^Sketch2D,
    edges: [dynamic]Edge,
    start_entity: int,
    used: ^map[int]bool,
) -> Profile {
    profile: Profile
    profile.entities = make([dynamic]int, 0)
    profile.points = make([dynamic]int, 0)

    // Mark starting entity as used
    used[start_entity] = true
    append(&profile.entities, start_entity)

    // Find the starting edge
    start_edge: Edge
    start_edge_found := false
    for edge in edges {
        if edge.entity_id == start_entity {
            start_edge = edge
            start_edge_found = true
            break
        }
    }

    if !start_edge_found {
        profile.type = .None
        return profile
    }

    // Start tracing from the start point
    current_point := start_edge.start_point
    append(&profile.points, current_point)

    // Trace forward
    next_point := start_edge.end_point
    append(&profile.points, next_point)

    // Keep tracing until we hit an endpoint or return to start
    for {
        // Find next connected edge
        next_entity, found := find_next_edge(edges, next_point, used^)

        if !found {
            // Hit an endpoint - open profile
            profile.type = .Open
            return profile
        }

        // Get the edge
        next_edge: Edge
        for edge in edges {
            if edge.entity_id == next_entity {
                next_edge = edge
                break
            }
        }

        // Mark as used
        used[next_entity] = true
        append(&profile.entities, next_entity)

        // Determine which endpoint is the continuation
        if next_edge.start_point == next_point {
            next_point = next_edge.end_point
        } else if next_edge.end_point == next_point {
            next_point = next_edge.start_point
        } else {
            // Shouldn't happen
            profile.type = .None
            return profile
        }

        // Check if we've returned to start (closed loop)
        if next_point == current_point {
            profile.type = .Closed
            return profile
        }

        // Add point to trace
        append(&profile.points, next_point)

        // Safety check - prevent infinite loops
        if len(profile.entities) > len(edges) {
            fmt.println("⚠️  Profile tracing infinite loop detected")
            profile.type = .None
            return profile
        }
    }
}

// Find the next connected edge at a point
find_next_edge :: proc(edges: [dynamic]Edge, point_id: int, used: map[int]bool) -> (int, bool) {
    for edge in edges {
        // Skip already used edges
        if used[edge.entity_id] {
            continue
        }

        // Check if this edge connects to the point
        if edge.start_point == point_id || edge.end_point == point_id {
            return edge.entity_id, true
        }
    }

    return -1, false
}

// =============================================================================
// Profile Queries
// =============================================================================

// Check if sketch contains any closed profiles
sketch_has_closed_profile :: proc(sketch: ^Sketch2D) -> bool {
    profiles := sketch_detect_profiles(sketch)
    defer {
        for &profile in profiles {
            delete(profile.entities)
            delete(profile.points)
        }
        delete(profiles)
    }

    for profile in profiles {
        if profile.type == .Closed {
            return true
        }
    }

    return false
}

// Get the first closed profile in the sketch
sketch_get_closed_profile :: proc(sketch: ^Sketch2D) -> (Profile, bool) {
    profiles := sketch_detect_profiles(sketch)
    defer {
        for &profile in profiles {
            if profile.type != .Closed {
                delete(profile.entities)
                delete(profile.points)
            }
        }
        delete(profiles)
    }

    for profile in profiles {
        if profile.type == .Closed {
            return profile, true
        }
    }

    return Profile{}, false
}

// =============================================================================
// Profile Printing/Debugging
// =============================================================================

// Print profile information
profile_print :: proc(profile: Profile, name: string = "Profile") {
    fmt.printf("%s:\n", name)
    fmt.printf("  Type: %v\n", profile.type)
    fmt.printf("  Entities: %d (", len(profile.entities))

    for entity_id, idx in profile.entities {
        if idx > 0 do fmt.printf(", ")
        fmt.printf("%d", entity_id)
    }
    fmt.printf(")\n")

    fmt.printf("  Points: %d (", len(profile.points))
    for point_id, idx in profile.points {
        if idx > 0 do fmt.printf(", ")
        fmt.printf("%d", point_id)
    }
    fmt.printf(")\n")
}

// Print all profiles in sketch
sketch_print_profiles :: proc(sketch: ^Sketch2D) {
    profiles := sketch_detect_profiles(sketch)
    defer {
        for &profile in profiles {
            delete(profile.entities)
            delete(profile.points)
        }
        delete(profiles)
    }

    fmt.printf("\n=== Profile Detection ===\n")
    fmt.printf("Found %d profile(s):\n\n", len(profiles))

    closed_count := 0
    open_count := 0

    for profile, idx in profiles {
        profile_print(profile, fmt.tprintf("Profile %d", idx))
        fmt.println()

        if profile.type == .Closed {
            closed_count += 1
        } else if profile.type == .Open {
            open_count += 1
        }
    }

    fmt.printf("Summary: %d closed, %d open\n", closed_count, open_count)

    if closed_count > 0 {
        fmt.println("✅ Sketch is ready for extrusion")
    } else if open_count > 0 {
        fmt.println("⚠️  Sketch contains open profiles - close them to enable extrusion")
    } else {
        fmt.println("ℹ️  No profiles detected")
    }
}

// Destroy/cleanup profile
profile_destroy :: proc(profile: ^Profile) {
    delete(profile.entities)
    delete(profile.points)
}
