package tessellation

import "core:fmt"
import "core:c"

// Test tessellation with a simple square
test_simple_square :: proc() -> bool {
    fmt.println("\n=== Testing libtess2 bindings with simple square ===")

    // Create tesselator
    tess := NewTess(nil)
    if tess == nil {
        fmt.println("ERROR: Failed to create tesselator")
        return false
    }
    defer DeleteTess(tess)

    // Define a simple square (CCW winding)
    vertices := [8]TESSreal{
        0.0, 0.0,  // bottom-left
        1.0, 0.0,  // bottom-right
        1.0, 1.0,  // top-right
        0.0, 1.0,  // top-left
    }

    // Add contour (2D coordinates, stride = 2 floats, 4 vertices)
    AddContour(tess, 2, &vertices[0], size_of(TESSreal) * 2, 4)

    // Check status after adding contour
    status := GetStatus(tess)
    if status != .OK {
        fmt.println("ERROR: Failed to add contour, status:", status)
        return false
    }

    // Tesselate as triangles (polySize=3, POLYGONS returns triangles)
    // Using NONZERO winding rule (standard for solid fills)
    result := Tesselate(tess,
        c.int(TessWindingRule.NONZERO),  // winding rule
        c.int(TessElementType.POLYGONS),  // element type
        3,                                 // polySize (3 = triangles)
        2,                                 // vertexSize (2D)
        nil)                              // normal (auto-calculate)

    if result == 0 {
        status = GetStatus(tess)
        fmt.println("ERROR: Tesselation failed, status:", status)
        return false
    }

    // Get results
    vertex_count := GetVertexCount(tess)
    element_count := GetElementCount(tess)

    fmt.println("Vertex count:", vertex_count)
    fmt.println("Triangle count:", element_count)

    // Get vertex data
    vertices_ptr := GetVertices(tess)
    elements_ptr := GetElements(tess)

    if vertices_ptr == nil || elements_ptr == nil {
        fmt.println("ERROR: Failed to get tesselation results")
        return false
    }

    // Print vertices
    fmt.println("\nVertices:")
    for i in 0..<vertex_count {
        x := vertices_ptr[i * 2 + 0]
        y := vertices_ptr[i * 2 + 1]
        fmt.printf("  v%d: (%.2f, %.2f)\n", i, x, y)
    }

    // Print triangles
    fmt.println("\nTriangles:")
    for i in 0..<element_count {
        v0 := elements_ptr[i * 3 + 0]
        v1 := elements_ptr[i * 3 + 1]
        v2 := elements_ptr[i * 3 + 2]
        fmt.printf("  t%d: [%d, %d, %d]\n", i, v0, v1, v2)
    }

    // Expected: 2 triangles for a square
    if element_count != 2 {
        fmt.println("ERROR: Expected 2 triangles, got", element_count)
        return false
    }

    fmt.println("\n✅ libtess2 bindings test PASSED!")
    return true
}
