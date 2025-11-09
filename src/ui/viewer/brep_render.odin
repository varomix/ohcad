// ui/viewer - B-rep to wireframe conversion utilities
package ohcad_viewer

import m "../../core/math"
import t "../../core/topology"

// Extract wireframe mesh from B-rep topology
brep_to_wireframe :: proc(brep: ^t.BRep) -> WireframeMesh {
    mesh := wireframe_mesh_init()

    // Iterate through all edges in the B-rep
    for i in 0..<len(brep.edges) {
        edge := brep.edges[i]

        // Skip invalid edges (deleted or uninitialized)
        if edge.v0 == t.INVALID_HANDLE || edge.v1 == t.INVALID_HANDLE {
            continue
        }

        // Check if vertices are valid
        if int(edge.v0) >= len(brep.vertices) || int(edge.v1) >= len(brep.vertices) {
            continue
        }

        v0 := brep.vertices[edge.v0]
        v1 := brep.vertices[edge.v1]

        // Skip if vertices are not valid
        if !v0.valid || !v1.valid {
            continue
        }

        // Add edge to wireframe mesh
        wireframe_mesh_add_edge(&mesh, v0.position, v1.position)
    }

    return mesh
}
