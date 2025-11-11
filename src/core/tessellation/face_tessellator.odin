// core/tessellation/face_tessellator.odin
// Tessellates SimpleFace polygons into triangles using libtess2
package tessellation

import "core:fmt"
import "core:c"
import m "../../core/math"

// Intermediate triangle structure (to avoid circular dependency with extrude.odin)
FaceTri :: struct {
    v0, v1, v2: m.Vec3,
    normal: m.Vec3,
    face_id: int,
}

// Tessellate a face (list of 3D vertices) into triangles
// Returns array of FaceTri which can be converted to Triangle3D by caller
tessellate_face :: proc(vertices: []m.Vec3, face_normal: m.Vec3, face_id: int) -> [dynamic]FaceTri {
    triangles := make([dynamic]FaceTri, 0, len(vertices))

    if len(vertices) < 3 {
        fmt.println("Error: Face must have at least 3 vertices")
        return triangles
    }

    // Special case: Triangle - no tessellation needed
    if len(vertices) == 3 {
        tri := FaceTri {
            v0 = vertices[0],
            v1 = vertices[1],
            v2 = vertices[2],
            normal = face_normal,
            face_id = face_id,
        }
        append(&triangles, tri)
        return triangles
    }

    // Special case: Quad - split into 2 triangles
    if len(vertices) == 4 {
        // Triangle 1: v0, v1, v2
        tri1 := FaceTri {
            v0 = vertices[0],
            v1 = vertices[1],
            v2 = vertices[2],
            normal = face_normal,
            face_id = face_id,
        }
        append(&triangles, tri1)

        // Triangle 2: v0, v2, v3
        tri2 := FaceTri {
            v0 = vertices[0],
            v1 = vertices[2],
            v2 = vertices[3],
            normal = face_normal,
            face_id = face_id,
        }
        append(&triangles, tri2)

        return triangles
    }

    // Complex polygon: Use libtess2
    triangles_from_libtess2 := tessellate_polygon_3d(vertices, face_normal, face_id)
    return triangles_from_libtess2
}

// Tessellate complex polygon using libtess2
tessellate_polygon_3d :: proc(vertices: []m.Vec3, face_normal: m.Vec3, face_id: int) -> [dynamic]FaceTri {
    triangles := make([dynamic]FaceTri, 0, len(vertices))

    // Create tesselator
    tess := NewTess(nil)
    if tess == nil {
        fmt.println("Error: Failed to create tesselator")
        return triangles
    }
    defer DeleteTess(tess)

    // Project 3D polygon to 2D plane for tessellation
    vertices_2d := project_vertices_to_2d(vertices, face_normal)
    defer delete(vertices_2d)

    // Add contour to tesselator
    AddContour(tess, 2, &vertices_2d[0], size_of(TESSreal) * 2, c.int(len(vertices_2d) / 2))

    // Check status
    status := GetStatus(tess)
    if status != .OK {
        fmt.println("Error: Failed to add contour, status:", status)
        return triangles
    }

    // Tesselate into triangles
    result := Tesselate(tess,
        c.int(TessWindingRule.NONZERO),   // NONZERO winding rule
        c.int(TessElementType.POLYGONS),  // Output polygons (triangles)
        3,                                 // polySize = 3 (triangles)
        2,                                 // vertexSize = 2D
        nil)                              // auto-calculate normal

    if result == 0 {
        fmt.println("Error: Tessellation failed")
        return triangles
    }

    // Get tessellation results
    tri_count := GetElementCount(tess)
    elements := GetElements(tess)

    if elements == nil {
        fmt.println("Error: No triangles generated")
        return triangles
    }

    // Build FaceTri from tessellation results
    for i in 0..<tri_count {
        idx0 := elements[i * 3 + 0]
        idx1 := elements[i * 3 + 1]
        idx2 := elements[i * 3 + 2]

        // Map back to 3D vertices
        if idx0 >= 0 && idx0 < c.int(len(vertices)) &&
           idx1 >= 0 && idx1 < c.int(len(vertices)) &&
           idx2 >= 0 && idx2 < c.int(len(vertices)) {

            tri := FaceTri {
                v0 = vertices[idx0],
                v1 = vertices[idx1],
                v2 = vertices[idx2],
                normal = face_normal,
                face_id = face_id,
            }
            append(&triangles, tri)
        }
    }

    return triangles
}

// Project 3D vertices to 2D plane for tessellation
// Returns flat array of 2D coordinates: [x0, y0, x1, y1, ...]
project_vertices_to_2d :: proc(vertices: []m.Vec3, normal: m.Vec3) -> [dynamic]TESSreal {
    coords := make([dynamic]TESSreal, 0, len(vertices) * 2)

    // Choose projection plane based on dominant normal component
    abs_x := abs(normal.x)
    abs_y := abs(normal.y)
    abs_z := abs(normal.z)

    // Project onto plane with largest normal component
    if abs_z >= abs_x && abs_z >= abs_y {
        // XY plane (drop Z)
        for v in vertices {
            append(&coords, TESSreal(v.x))
            append(&coords, TESSreal(v.y))
        }
    } else if abs_x >= abs_y && abs_x >= abs_z {
        // YZ plane (drop X)
        for v in vertices {
            append(&coords, TESSreal(v.y))
            append(&coords, TESSreal(v.z))
        }
    } else {
        // XZ plane (drop Y)
        for v in vertices {
            append(&coords, TESSreal(v.x))
            append(&coords, TESSreal(v.z))
        }
    }

    return coords
}
