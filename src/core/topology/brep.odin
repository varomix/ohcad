// core/topology - B-rep topology data structures
// This module provides the boundary representation (B-rep) topology system

package ohcad_topology

import m "../../core/math"
import glsl "core:math/linalg/glsl"

// Handle-based ID system for stable references
Handle :: distinct int

INVALID_HANDLE :: Handle(-1)

// Vertex - geometric point in 3D space
Vertex :: struct {
    position: m.Vec3,
    valid: bool,  // Track if this vertex is active
}

// Edge - connects two vertices, may have associated curve geometry
Edge :: struct {
    v0, v1: Handle,      // Vertex handles
    curve_id: int,       // Reference to curve geometry (if any)
}

// Face - bounded surface with oriented edge loops
Face :: struct {
    surface_id: int,                 // Reference to surface geometry
    outer_loop: []Handle,            // Outer boundary edge handles
    inner_loops: [dynamic][]Handle,  // Inner boundaries (holes) - dynamic array
}

// Shell - collection of connected faces
Shell :: struct {
    faces: [dynamic]Handle,  // Face handles
}

// Solid - closed volume bounded by shells
Solid :: struct {
    outer_shell: Handle,           // Main outer shell
    inner_shells: [dynamic]Handle, // Void shells (cavities)
}

// B-rep container - holds all topology entities
BRep :: struct {
    vertices: [dynamic]Vertex,
    edges: [dynamic]Edge,
    faces: [dynamic]Face,
    shells: [dynamic]Shell,
    solids: [dynamic]Solid,
}

// Handle allocator for managing stable integer IDs
HandleAllocator :: struct {
    next_id: int,
    free_ids: [dynamic]Handle,
}

// Initialize a new handle allocator
handle_allocator_init :: proc(alloc: ^HandleAllocator) {
    alloc.next_id = 0
    alloc.free_ids = make([dynamic]Handle)
}

// Destroy handle allocator
handle_allocator_destroy :: proc(alloc: ^HandleAllocator) {
    delete(alloc.free_ids)
}

// Allocate a new handle
handle_allocate :: proc(alloc: ^HandleAllocator) -> Handle {
    if len(alloc.free_ids) > 0 {
        handle := pop(&alloc.free_ids)
        return handle
    }
    handle := Handle(alloc.next_id)
    alloc.next_id += 1
    return handle
}

// Free a handle for reuse
handle_free :: proc(alloc: ^HandleAllocator, handle: Handle) {
    append(&alloc.free_ids, handle)
}

// Initialize an empty B-rep
brep_init :: proc(brep: ^BRep) {
    brep.vertices = make([dynamic]Vertex)
    brep.edges = make([dynamic]Edge)
    brep.faces = make([dynamic]Face)
    brep.shells = make([dynamic]Shell)
    brep.solids = make([dynamic]Solid)
}

// Destroy B-rep and free all memory
brep_destroy :: proc(brep: ^BRep) {
    delete(brep.vertices)
    delete(brep.edges)

    // Free face loops
    for &face in brep.faces {
        delete(face.outer_loop)
        for &inner in face.inner_loops {
            delete(inner)
        }
        delete(face.inner_loops)
    }
    delete(brep.faces)

    // Free shells
    for &shell in brep.shells {
        delete(shell.faces)
    }
    delete(brep.shells)

    // Free solids
    for &solid in brep.solids {
        delete(solid.inner_shells)
    }
    delete(brep.solids)
}

// =============================================================================
// Euler Operators - Fundamental topology manipulation operations
// =============================================================================

// Make a vertex at a position
make_vertex :: proc(brep: ^BRep, alloc: ^HandleAllocator, position: m.Vec3) -> Handle {
    handle := handle_allocate(alloc)

    // Expand vertices array if needed
    for int(handle) >= len(brep.vertices) {
        append(&brep.vertices, Vertex{})
    }

    brep.vertices[handle] = Vertex{position = position, valid = true}
    return handle
}

// Delete a vertex (only if not referenced by edges)
kill_vertex :: proc(brep: ^BRep, alloc: ^HandleAllocator, v_handle: Handle) -> bool {
    if int(v_handle) >= len(brep.vertices) {
        return false
    }

    // Check if vertex is used by any edges
    for edge in brep.edges {
        if edge.v0 == v_handle || edge.v1 == v_handle {
            return false  // Cannot delete - vertex in use
        }
    }

    // Clear vertex data and mark as invalid
    brep.vertices[v_handle] = Vertex{valid = false}
    handle_free(alloc, v_handle)
    return true
}

// Make an edge between two vertices
make_edge :: proc(brep: ^BRep, alloc: ^HandleAllocator, v0, v1: Handle, curve_id: int = -1) -> (Handle, bool) {
    // Validate vertices exist
    if int(v0) >= len(brep.vertices) || int(v1) >= len(brep.vertices) {
        return INVALID_HANDLE, false
    }

    handle := handle_allocate(alloc)

    // Expand edges array if needed
    for int(handle) >= len(brep.edges) {
        append(&brep.edges, Edge{v0 = INVALID_HANDLE, v1 = INVALID_HANDLE, curve_id = -1})
    }

    brep.edges[handle] = Edge{
        v0 = v0,
        v1 = v1,
        curve_id = curve_id,
    }

    return handle, true
}

// Delete an edge (only if not referenced by faces)
kill_edge :: proc(brep: ^BRep, alloc: ^HandleAllocator, e_handle: Handle) -> bool {
    if int(e_handle) >= len(brep.edges) {
        return false
    }

    // Check if edge is used by any faces
    for face in brep.faces {
        // Check outer loop
        for edge_h in face.outer_loop {
            if edge_h == e_handle {
                return false  // Cannot delete - edge in use
            }
        }
        // Check inner loops
        for inner in face.inner_loops {
            for edge_h in inner {
                if edge_h == e_handle {
                    return false
                }
            }
        }
    }

    // Clear edge data
    brep.edges[e_handle] = Edge{}
    handle_free(alloc, e_handle)
    return true
}

// Make a face from an edge loop
make_face :: proc(brep: ^BRep, alloc: ^HandleAllocator, edge_loop: []Handle, surface_id: int = -1) -> (Handle, bool) {
    // Validate all edges exist
    for edge_h in edge_loop {
        if int(edge_h) >= len(brep.edges) {
            return INVALID_HANDLE, false
        }
    }

    handle := handle_allocate(alloc)

    // Expand faces array if needed
    for int(handle) >= len(brep.faces) {
        append(&brep.faces, Face{})
    }

    // Copy edge loop
    outer_loop := make([]Handle, len(edge_loop))
    copy(outer_loop, edge_loop)

    brep.faces[handle] = Face{
        surface_id = surface_id,
        outer_loop = outer_loop,
        inner_loops = make([dynamic][]Handle),
    }

    return handle, true
}

// Delete a face (only if not referenced by shells)
kill_face :: proc(brep: ^BRep, alloc: ^HandleAllocator, f_handle: Handle) -> bool {
    if int(f_handle) >= len(brep.faces) {
        return false
    }

    // Check if face is used by any shells
    for shell in brep.shells {
        for face_h in shell.faces {
            if face_h == f_handle {
                return false  // Cannot delete - face in use
            }
        }
    }

    // Free face loops
    delete(brep.faces[f_handle].outer_loop)
    for inner in brep.faces[f_handle].inner_loops {
        delete(inner)
    }
    delete(brep.faces[f_handle].inner_loops)

    // Clear face data
    brep.faces[f_handle] = Face{}
    handle_free(alloc, f_handle)
    return true
}

// Add an inner loop (hole) to a face
add_inner_loop :: proc(brep: ^BRep, f_handle: Handle, edge_loop: []Handle) -> bool {
    if int(f_handle) >= len(brep.faces) {
        return false
    }

    // Validate all edges exist
    for edge_h in edge_loop {
        if int(edge_h) >= len(brep.edges) {
            return false
        }
    }

    // Copy edge loop
    inner_loop := make([]Handle, len(edge_loop))
    copy(inner_loop, edge_loop)

    append(&brep.faces[f_handle].inner_loops, inner_loop)
    return true
}

// Make a shell from a set of faces
make_shell :: proc(brep: ^BRep, alloc: ^HandleAllocator, face_handles: []Handle) -> (Handle, bool) {
    // Validate all faces exist
    for face_h in face_handles {
        if int(face_h) >= len(brep.faces) {
            return INVALID_HANDLE, false
        }
    }

    handle := handle_allocate(alloc)

    // Expand shells array if needed
    for int(handle) >= len(brep.shells) {
        append(&brep.shells, Shell{})
    }

    // Create shell with faces
    brep.shells[handle] = Shell{
        faces = make([dynamic]Handle),
    }

    for face_h in face_handles {
        append(&brep.shells[handle].faces, face_h)
    }

    return handle, true
}

// Make a solid from a shell (and optional inner shells for voids)
make_solid :: proc(brep: ^BRep, alloc: ^HandleAllocator, outer_shell: Handle, inner_shells: []Handle = nil) -> (Handle, bool) {
    // Validate outer shell exists
    if int(outer_shell) >= len(brep.shells) {
        return INVALID_HANDLE, false
    }

    // Validate inner shells exist
    if inner_shells != nil {
        for shell_h in inner_shells {
            if int(shell_h) >= len(brep.shells) {
                return INVALID_HANDLE, false
            }
        }
    }

    handle := handle_allocate(alloc)

    // Expand solids array if needed
    for int(handle) >= len(brep.solids) {
        append(&brep.solids, Solid{})
    }

    brep.solids[handle] = Solid{
        outer_shell = outer_shell,
        inner_shells = make([dynamic]Handle),
    }

    // Add inner shells
    if inner_shells != nil {
        for shell_h in inner_shells {
            append(&brep.solids[handle].inner_shells, shell_h)
        }
    }

    return handle, true
}

// =============================================================================
// Topology Query Operations
// =============================================================================

// Get all edges connected to a vertex
edges_of_vertex :: proc(brep: ^BRep, v_handle: Handle) -> [dynamic]Handle {
    edges := make([dynamic]Handle)

    for i in 0..<len(brep.edges) {
        edge := brep.edges[i]
        // Only consider edges with both valid handles (not killed edges)
        if edge.v0 == INVALID_HANDLE || edge.v1 == INVALID_HANDLE {
            continue
        }
        if edge.v0 == v_handle || edge.v1 == v_handle {
            append(&edges, Handle(i))
        }
    }

    return edges
}

// Get all faces that use an edge
faces_of_edge :: proc(brep: ^BRep, e_handle: Handle) -> [dynamic]Handle {
    faces := make([dynamic]Handle)

    for i in 0..<len(brep.faces) {
        face := brep.faces[i]

        // Check outer loop
        for edge_h in face.outer_loop {
            if edge_h == e_handle {
                append(&faces, Handle(i))
                break
            }
        }

        // Check inner loops
        for inner in face.inner_loops {
            for edge_h in inner {
                if edge_h == e_handle {
                    append(&faces, Handle(i))
                    break
                }
            }
        }
    }

    return faces
}

// Count topology entities (for Euler characteristic verification)
count_entities :: proc(brep: ^BRep) -> (vertices, edges, faces: int) {
    // Count valid vertices
    for v in brep.vertices {
        if v.valid {
            vertices += 1
        }
    }

    // Count edges that have valid vertex handles
    for e in brep.edges {
        if e.v0 != INVALID_HANDLE && e.v1 != INVALID_HANDLE {
            edges += 1
        }
    }

    // Count faces with outer loops
    for f in brep.faces {
        if len(f.outer_loop) > 0 {
            faces += 1
        }
    }

    return
}
