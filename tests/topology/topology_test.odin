// tests/topology - Integration tests for topology handle system and Euler operators
package test_topology

import "core:testing"
import t "../../src/core/topology"
import m "../../src/core/math"
import glsl "core:math/linalg/glsl"

// =============================================================================
// Handle Allocator Tests
// =============================================================================

@(test)
test_handle_allocator_init :: proc(test: ^testing.T) {
    alloc: t.HandleAllocator
    t.handle_allocator_init(&alloc)
    defer t.handle_allocator_destroy(&alloc)

    testing.expect(test, alloc.next_id == 0, "Initial next_id should be 0")
    testing.expect(test, len(alloc.free_ids) == 0, "Initial free_ids should be empty")
}

@(test)
test_handle_allocation :: proc(test: ^testing.T) {
    alloc: t.HandleAllocator
    t.handle_allocator_init(&alloc)
    defer t.handle_allocator_destroy(&alloc)

    // Allocate sequential handles
    h0 := t.handle_allocate(&alloc)
    h1 := t.handle_allocate(&alloc)
    h2 := t.handle_allocate(&alloc)

    testing.expect(test, h0 == t.Handle(0), "First handle should be 0")
    testing.expect(test, h1 == t.Handle(1), "Second handle should be 1")
    testing.expect(test, h2 == t.Handle(2), "Third handle should be 2")
}

@(test)
test_handle_reuse :: proc(test: ^testing.T) {
    alloc: t.HandleAllocator
    t.handle_allocator_init(&alloc)
    defer t.handle_allocator_destroy(&alloc)

    // Allocate handles
    h0 := t.handle_allocate(&alloc)
    h1 := t.handle_allocate(&alloc)
    h2 := t.handle_allocate(&alloc)

    // Free h1
    t.handle_free(&alloc, h1)

    // Next allocation should reuse h1
    h3 := t.handle_allocate(&alloc)
    testing.expect(test, h3 == h1, "Freed handle should be reused")

    // Next allocation should be new
    h4 := t.handle_allocate(&alloc)
    testing.expect(test, h4 == t.Handle(3), "New handle should continue sequence")
}

// =============================================================================
// B-rep Initialization Tests
// =============================================================================

@(test)
test_brep_init :: proc(test: ^testing.T) {
    brep: t.BRep
    t.brep_init(&brep)
    defer t.brep_destroy(&brep)

    testing.expect(test, len(brep.vertices) == 0, "Initial vertices should be empty")
    testing.expect(test, len(brep.edges) == 0, "Initial edges should be empty")
    testing.expect(test, len(brep.faces) == 0, "Initial faces should be empty")
    testing.expect(test, len(brep.shells) == 0, "Initial shells should be empty")
    testing.expect(test, len(brep.solids) == 0, "Initial solids should be empty")
}

// =============================================================================
// Vertex Operations Tests
// =============================================================================

@(test)
test_make_vertex :: proc(test: ^testing.T) {
    brep: t.BRep
    alloc: t.HandleAllocator
    t.brep_init(&brep)
    t.handle_allocator_init(&alloc)
    defer t.brep_destroy(&brep)
    defer t.handle_allocator_destroy(&alloc)

    pos := m.Vec3{1, 2, 3}
    v_handle := t.make_vertex(&brep, &alloc, pos)

    testing.expect(test, v_handle == t.Handle(0), "First vertex should have handle 0")
    testing.expect(test, len(brep.vertices) > 0, "Vertices array should not be empty")
    testing.expect(test, m.is_near(brep.vertices[v_handle].position, pos), "Vertex position should match")
}

@(test)
test_kill_vertex :: proc(test: ^testing.T) {
    brep: t.BRep
    alloc: t.HandleAllocator
    t.brep_init(&brep)
    t.handle_allocator_init(&alloc)
    defer t.brep_destroy(&brep)
    defer t.handle_allocator_destroy(&alloc)

    v_handle := t.make_vertex(&brep, &alloc, m.Vec3{1, 2, 3})

    // Should be able to delete unused vertex
    ok := t.kill_vertex(&brep, &alloc, v_handle)
    testing.expect(test, ok, "Should successfully delete unused vertex")
}

@(test)
test_kill_vertex_in_use :: proc(test: ^testing.T) {
    brep: t.BRep
    alloc: t.HandleAllocator
    t.brep_init(&brep)
    t.handle_allocator_init(&alloc)
    defer t.brep_destroy(&brep)
    defer t.handle_allocator_destroy(&alloc)

    v0 := t.make_vertex(&brep, &alloc, m.Vec3{0, 0, 0})
    v1 := t.make_vertex(&brep, &alloc, m.Vec3{1, 0, 0})

    // Create edge using vertices
    _, ok := t.make_edge(&brep, &alloc, v0, v1)
    testing.expect(test, ok, "Edge creation should succeed")

    // Should not be able to delete vertex in use
    ok = t.kill_vertex(&brep, &alloc, v0)
    testing.expect(test, !ok, "Should not delete vertex in use by edge")
}

// =============================================================================
// Edge Operations Tests
// =============================================================================

@(test)
test_make_edge :: proc(test: ^testing.T) {
    brep: t.BRep
    alloc: t.HandleAllocator
    t.brep_init(&brep)
    t.handle_allocator_init(&alloc)
    defer t.brep_destroy(&brep)
    defer t.handle_allocator_destroy(&alloc)

    v0 := t.make_vertex(&brep, &alloc, m.Vec3{0, 0, 0})
    v1 := t.make_vertex(&brep, &alloc, m.Vec3{1, 0, 0})

    e_handle, ok := t.make_edge(&brep, &alloc, v0, v1)

    testing.expect(test, ok, "Edge creation should succeed")
    testing.expect(test, e_handle != t.INVALID_HANDLE, "Edge handle should be valid")
    testing.expect(test, brep.edges[e_handle].v0 == v0, "Edge v0 should match")
    testing.expect(test, brep.edges[e_handle].v1 == v1, "Edge v1 should match")
}

@(test)
test_make_edge_invalid_vertices :: proc(test: ^testing.T) {
    brep: t.BRep
    alloc: t.HandleAllocator
    t.brep_init(&brep)
    t.handle_allocator_init(&alloc)
    defer t.brep_destroy(&brep)
    defer t.handle_allocator_destroy(&alloc)

    // Try to create edge with invalid vertices
    _, ok := t.make_edge(&brep, &alloc, t.Handle(99), t.Handle(100))
    testing.expect(test, !ok, "Edge creation with invalid vertices should fail")
}

@(test)
test_kill_edge :: proc(test: ^testing.T) {
    brep: t.BRep
    alloc: t.HandleAllocator
    t.brep_init(&brep)
    t.handle_allocator_init(&alloc)
    defer t.brep_destroy(&brep)
    defer t.handle_allocator_destroy(&alloc)

    v0 := t.make_vertex(&brep, &alloc, m.Vec3{0, 0, 0})
    v1 := t.make_vertex(&brep, &alloc, m.Vec3{1, 0, 0})
    e_handle, _ := t.make_edge(&brep, &alloc, v0, v1)

    // Should be able to delete unused edge
    ok := t.kill_edge(&brep, &alloc, e_handle)
    testing.expect(test, ok, "Should successfully delete unused edge")
}

// =============================================================================
// Face Operations Tests
// =============================================================================

@(test)
test_make_face :: proc(test: ^testing.T) {
    brep: t.BRep
    alloc: t.HandleAllocator
    t.brep_init(&brep)
    t.handle_allocator_init(&alloc)
    defer t.brep_destroy(&brep)
    defer t.handle_allocator_destroy(&alloc)

    // Create a triangle
    v0 := t.make_vertex(&brep, &alloc, m.Vec3{0, 0, 0})
    v1 := t.make_vertex(&brep, &alloc, m.Vec3{1, 0, 0})
    v2 := t.make_vertex(&brep, &alloc, m.Vec3{0, 1, 0})

    e0, _ := t.make_edge(&brep, &alloc, v0, v1)
    e1, _ := t.make_edge(&brep, &alloc, v1, v2)
    e2, _ := t.make_edge(&brep, &alloc, v2, v0)

    edge_loop := []t.Handle{e0, e1, e2}
    f_handle, ok := t.make_face(&brep, &alloc, edge_loop)

    testing.expect(test, ok, "Face creation should succeed")
    testing.expect(test, f_handle != t.INVALID_HANDLE, "Face handle should be valid")
    testing.expect(test, len(brep.faces[f_handle].outer_loop) == 3, "Face should have 3 edges")
}

@(test)
test_add_inner_loop :: proc(test: ^testing.T) {
    brep: t.BRep
    alloc: t.HandleAllocator
    t.brep_init(&brep)
    t.handle_allocator_init(&alloc)
    defer t.brep_destroy(&brep)
    defer t.handle_allocator_destroy(&alloc)

    // Create outer square
    v0 := t.make_vertex(&brep, &alloc, m.Vec3{0, 0, 0})
    v1 := t.make_vertex(&brep, &alloc, m.Vec3{10, 0, 0})
    v2 := t.make_vertex(&brep, &alloc, m.Vec3{10, 10, 0})
    v3 := t.make_vertex(&brep, &alloc, m.Vec3{0, 10, 0})

    e0, _ := t.make_edge(&brep, &alloc, v0, v1)
    e1, _ := t.make_edge(&brep, &alloc, v1, v2)
    e2, _ := t.make_edge(&brep, &alloc, v2, v3)
    e3, _ := t.make_edge(&brep, &alloc, v3, v0)

    outer_loop := []t.Handle{e0, e1, e2, e3}
    f_handle, _ := t.make_face(&brep, &alloc, outer_loop)

    // Create inner hole
    v4 := t.make_vertex(&brep, &alloc, m.Vec3{3, 3, 0})
    v5 := t.make_vertex(&brep, &alloc, m.Vec3{7, 3, 0})
    v6 := t.make_vertex(&brep, &alloc, m.Vec3{7, 7, 0})
    v7 := t.make_vertex(&brep, &alloc, m.Vec3{3, 7, 0})

    e4, _ := t.make_edge(&brep, &alloc, v4, v5)
    e5, _ := t.make_edge(&brep, &alloc, v5, v6)
    e6, _ := t.make_edge(&brep, &alloc, v6, v7)
    e7, _ := t.make_edge(&brep, &alloc, v7, v4)

    inner_loop := []t.Handle{e4, e5, e6, e7}
    ok := t.add_inner_loop(&brep, f_handle, inner_loop)

    testing.expect(test, ok, "Adding inner loop should succeed")
    testing.expect(test, len(brep.faces[f_handle].inner_loops) == 1, "Face should have 1 inner loop")
    testing.expect(test, len(brep.faces[f_handle].inner_loops[0]) == 4, "Inner loop should have 4 edges")
}

// =============================================================================
// Shell and Solid Operations Tests
// =============================================================================

@(test)
test_make_shell :: proc(test: ^testing.T) {
    brep: t.BRep
    alloc: t.HandleAllocator
    t.brep_init(&brep)
    t.handle_allocator_init(&alloc)
    defer t.brep_destroy(&brep)
    defer t.handle_allocator_destroy(&alloc)

    // Create two triangular faces
    v0 := t.make_vertex(&brep, &alloc, m.Vec3{0, 0, 0})
    v1 := t.make_vertex(&brep, &alloc, m.Vec3{1, 0, 0})
    v2 := t.make_vertex(&brep, &alloc, m.Vec3{0, 1, 0})

    e0, _ := t.make_edge(&brep, &alloc, v0, v1)
    e1, _ := t.make_edge(&brep, &alloc, v1, v2)
    e2, _ := t.make_edge(&brep, &alloc, v2, v0)

    f0, _ := t.make_face(&brep, &alloc, []t.Handle{e0, e1, e2})

    // Create shell
    face_list := []t.Handle{f0}
    s_handle, ok := t.make_shell(&brep, &alloc, face_list)

    testing.expect(test, ok, "Shell creation should succeed")
    testing.expect(test, s_handle != t.INVALID_HANDLE, "Shell handle should be valid")
    testing.expect(test, len(brep.shells[s_handle].faces) == 1, "Shell should have 1 face")
}

@(test)
test_make_solid :: proc(test: ^testing.T) {
    brep: t.BRep
    alloc: t.HandleAllocator
    t.brep_init(&brep)
    t.handle_allocator_init(&alloc)
    defer t.brep_destroy(&brep)
    defer t.handle_allocator_destroy(&alloc)

    // Create simple face
    v0 := t.make_vertex(&brep, &alloc, m.Vec3{0, 0, 0})
    v1 := t.make_vertex(&brep, &alloc, m.Vec3{1, 0, 0})
    v2 := t.make_vertex(&brep, &alloc, m.Vec3{0, 1, 0})

    e0, _ := t.make_edge(&brep, &alloc, v0, v1)
    e1, _ := t.make_edge(&brep, &alloc, v1, v2)
    e2, _ := t.make_edge(&brep, &alloc, v2, v0)

    f0, _ := t.make_face(&brep, &alloc, []t.Handle{e0, e1, e2})

    // Create shell and solid
    s_handle, _ := t.make_shell(&brep, &alloc, []t.Handle{f0})
    solid_handle, ok := t.make_solid(&brep, &alloc, s_handle)

    testing.expect(test, ok, "Solid creation should succeed")
    testing.expect(test, solid_handle != t.INVALID_HANDLE, "Solid handle should be valid")
    testing.expect(test, brep.solids[solid_handle].outer_shell == s_handle, "Solid should reference shell")
}

// =============================================================================
// Topology Query Tests
// =============================================================================

@(test)
test_edges_of_vertex :: proc(test: ^testing.T) {
    brep: t.BRep
    alloc: t.HandleAllocator
    t.brep_init(&brep)
    t.handle_allocator_init(&alloc)
    defer t.brep_destroy(&brep)
    defer t.handle_allocator_destroy(&alloc)

    // Create star pattern: one center vertex with 4 edges
    v_center := t.make_vertex(&brep, &alloc, m.Vec3{0, 0, 0})
    v1 := t.make_vertex(&brep, &alloc, m.Vec3{1, 0, 0})
    v2 := t.make_vertex(&brep, &alloc, m.Vec3{0, 1, 0})
    v3 := t.make_vertex(&brep, &alloc, m.Vec3{-1, 0, 0})
    v4 := t.make_vertex(&brep, &alloc, m.Vec3{0, -1, 0})

    t.make_edge(&brep, &alloc, v_center, v1)
    t.make_edge(&brep, &alloc, v_center, v2)
    t.make_edge(&brep, &alloc, v_center, v3)
    t.make_edge(&brep, &alloc, v_center, v4)

    edges := t.edges_of_vertex(&brep, v_center)
    defer delete(edges)

    testing.expect(test, len(edges) == 4, "Center vertex should have 4 edges")
}

@(test)
test_faces_of_edge :: proc(test: ^testing.T) {
    brep: t.BRep
    alloc: t.HandleAllocator
    t.brep_init(&brep)
    t.handle_allocator_init(&alloc)
    defer t.brep_destroy(&brep)
    defer t.handle_allocator_destroy(&alloc)

    // Create two triangles sharing an edge
    v0 := t.make_vertex(&brep, &alloc, m.Vec3{0, 0, 0})
    v1 := t.make_vertex(&brep, &alloc, m.Vec3{1, 0, 0})
    v2 := t.make_vertex(&brep, &alloc, m.Vec3{0, 1, 0})
    v3 := t.make_vertex(&brep, &alloc, m.Vec3{1, 1, 0})

    e_shared, _ := t.make_edge(&brep, &alloc, v0, v1)
    e1, _ := t.make_edge(&brep, &alloc, v1, v2)
    e2, _ := t.make_edge(&brep, &alloc, v2, v0)
    e3, _ := t.make_edge(&brep, &alloc, v1, v3)
    e4, _ := t.make_edge(&brep, &alloc, v3, v0)

    t.make_face(&brep, &alloc, []t.Handle{e_shared, e1, e2})
    t.make_face(&brep, &alloc, []t.Handle{e_shared, e3, e4})

    faces := t.faces_of_edge(&brep, e_shared)
    defer delete(faces)

    testing.expect(test, len(faces) == 2, "Shared edge should be used by 2 faces")
}

@(test)
test_count_entities :: proc(test: ^testing.T) {
    brep: t.BRep
    alloc: t.HandleAllocator
    t.brep_init(&brep)
    t.handle_allocator_init(&alloc)
    defer t.brep_destroy(&brep)
    defer t.handle_allocator_destroy(&alloc)

    // Create a triangle
    v0 := t.make_vertex(&brep, &alloc, m.Vec3{0, 0, 0})
    v1 := t.make_vertex(&brep, &alloc, m.Vec3{1, 0, 0})
    v2 := t.make_vertex(&brep, &alloc, m.Vec3{0, 1, 0})

    e0, _ := t.make_edge(&brep, &alloc, v0, v1)
    e1, _ := t.make_edge(&brep, &alloc, v1, v2)
    e2, _ := t.make_edge(&brep, &alloc, v2, v0)

    t.make_face(&brep, &alloc, []t.Handle{e0, e1, e2})

    v_count, e_count, f_count := t.count_entities(&brep)

    testing.expect(test, v_count == 3, "Should have 3 vertices")
    testing.expect(test, e_count == 3, "Should have 3 edges")
    testing.expect(test, f_count == 1, "Should have 1 face")

    // Verify Euler characteristic: V - E + F = 2 - 2g (for genus g=0)
    // For a single triangle on a plane: V - E + F = 3 - 3 + 1 = 1
    // (Not a closed surface, so characteristic is 1, not 2)
    euler_char := v_count - e_count + f_count
    testing.expect(test, euler_char == 1, "Euler characteristic should be 1 for open triangle")
}

// =============================================================================
// Integration Test: Build a Cube
// =============================================================================

@(test)
test_build_cube :: proc(test: ^testing.T) {
    brep: t.BRep
    alloc: t.HandleAllocator
    t.brep_init(&brep)
    t.handle_allocator_init(&alloc)
    defer t.brep_destroy(&brep)
    defer t.handle_allocator_destroy(&alloc)

    // Create 8 vertices of a unit cube
    v0 := t.make_vertex(&brep, &alloc, m.Vec3{0, 0, 0})
    v1 := t.make_vertex(&brep, &alloc, m.Vec3{1, 0, 0})
    v2 := t.make_vertex(&brep, &alloc, m.Vec3{1, 1, 0})
    v3 := t.make_vertex(&brep, &alloc, m.Vec3{0, 1, 0})
    v4 := t.make_vertex(&brep, &alloc, m.Vec3{0, 0, 1})
    v5 := t.make_vertex(&brep, &alloc, m.Vec3{1, 0, 1})
    v6 := t.make_vertex(&brep, &alloc, m.Vec3{1, 1, 1})
    v7 := t.make_vertex(&brep, &alloc, m.Vec3{0, 1, 1})

    // Create 12 edges
    // Bottom face edges
    e0, _ := t.make_edge(&brep, &alloc, v0, v1)
    e1, _ := t.make_edge(&brep, &alloc, v1, v2)
    e2, _ := t.make_edge(&brep, &alloc, v2, v3)
    e3, _ := t.make_edge(&brep, &alloc, v3, v0)

    // Top face edges
    e4, _ := t.make_edge(&brep, &alloc, v4, v5)
    e5, _ := t.make_edge(&brep, &alloc, v5, v6)
    e6, _ := t.make_edge(&brep, &alloc, v6, v7)
    e7, _ := t.make_edge(&brep, &alloc, v7, v4)

    // Vertical edges
    e8, _ := t.make_edge(&brep, &alloc, v0, v4)
    e9, _ := t.make_edge(&brep, &alloc, v1, v5)
    e10, _ := t.make_edge(&brep, &alloc, v2, v6)
    e11, _ := t.make_edge(&brep, &alloc, v3, v7)

    // Create 6 faces (one per cube side)
    // For a proper cube we'd need to define edge loops more carefully
    // This is simplified - just testing the creation succeeds
    f_bottom, _ := t.make_face(&brep, &alloc, []t.Handle{e0, e1, e2, e3})
    f_top, _ := t.make_face(&brep, &alloc, []t.Handle{e4, e5, e6, e7})

    // Create shell
    faces := []t.Handle{f_bottom, f_top}
    shell, _ := t.make_shell(&brep, &alloc, faces)

    // Create solid
    solid, ok := t.make_solid(&brep, &alloc, shell)

    testing.expect(test, ok, "Cube solid creation should succeed")
    testing.expect(test, solid != t.INVALID_HANDLE, "Cube solid should have valid handle")

    // Count entities
    v_count, e_count, f_count := t.count_entities(&brep)
    testing.expect(test, v_count == 8, "Cube should have 8 vertices")
    testing.expect(test, e_count == 12, "Cube should have 12 edges")
    testing.expect(test, f_count == 2, "Should have 2 faces (simplified cube)")
}
