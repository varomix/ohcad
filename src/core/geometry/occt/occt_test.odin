// OCCT Integration Test
// Tests basic OCCT functionality: pentagon extrusion (the shape Manifold failed on!)
//
// Run from project root:
//   odin run src/core/geometry/occt -file
//
package occt

import "core:fmt"
import "core:math"

main :: proc() {
    fmt.println("=== OCCT Integration Test ===\n")

    // Initialize OCCT
    initialize()
    defer cleanup()

    // Print version
    version := version()
    fmt.printf("✓ OCCT Version: %s\n\n", version)

    // =============================================================================
    // Test 1: Create Pentagon Wire (2D Profile)
    // =============================================================================

    fmt.println("Test 1: Creating pentagon wire...")

    // Generate pentagon points on XY plane
    // Center at origin, radius = 10mm
    radius := 10.0
    num_sides := 5
    points := make([]f64, num_sides * 2)  // x,y pairs
    defer delete(points)

    for i in 0..<num_sides {
        angle := f64(i) * (2.0 * math.PI) / f64(num_sides)
        points[i*2 + 0] = radius * math.cos(angle)  // x
        points[i*2 + 1] = radius * math.sin(angle)  // y
    }

    // Create wire from points (closed pentagon)
    wire := OCCT_Wire_FromPoints2D(
        raw_data(points),
        i32(num_sides),
        true,  // closed
    )

    if wire == nil {
        fmt.eprintln("❌ FAILED: Could not create pentagon wire")
        return
    }
    defer OCCT_Wire_Delete(wire)

    fmt.println("✓ Pentagon wire created successfully")

    // =============================================================================
    // Test 2: Extrude Pentagon to Solid
    // =============================================================================

    fmt.println("\nTest 2: Extruding pentagon...")

    // Extrude 20mm in +Z direction
    extrusion_height := 20.0
    solid := OCCT_Extrude_Wire(wire, 0, 0, extrusion_height)

    if solid == nil {
        fmt.eprintln("❌ FAILED: Could not extrude pentagon")
        return
    }
    defer delete_shape(solid)

    // Check if solid is valid
    if !is_valid(solid) {
        fmt.eprintln("❌ FAILED: Extruded shape is invalid")
        return
    }

    shape_type := get_type(solid)
    fmt.printf("✓ Pentagon extruded successfully (type: %v)\n", shape_type)

    // =============================================================================
    // Test 3: Tessellate to Triangle Mesh
    // =============================================================================

    fmt.println("\nTest 3: Tessellating solid to mesh...")

    // Use default tessellation parameters (0.1mm precision, 0.5° angular)
    mesh := OCCT_Tessellate(solid, DEFAULT_TESSELLATION)

    if mesh == nil {
        fmt.eprintln("❌ FAILED: Could not tessellate solid")
        return
    }
    defer delete_mesh(mesh)

    fmt.printf("✓ Mesh generated: %d vertices, %d triangles\n",
        mesh.num_vertices, mesh.num_triangles)

    // Verify mesh has reasonable data
    if mesh.num_vertices < 10 {
        fmt.eprintln("❌ FAILED: Too few vertices (expected at least 10 for pentagon)")
        return
    }

    if mesh.num_triangles < 10 {
        fmt.eprintln("❌ FAILED: Too few triangles (expected at least 10)")
        return
    }

    // Print first few vertices (for debugging)
    fmt.println("\nFirst 3 vertices:")
    for i in 0..<min(3, int(mesh.num_vertices)) {
        x := mesh.vertices[i*3 + 0]
        y := mesh.vertices[i*3 + 1]
        z := mesh.vertices[i*3 + 2]
        fmt.printf("  v%d: (%.2f, %.2f, %.2f)\n", i, x, y, z)
    }

    // =============================================================================
    // Test 4: Boolean Difference (Pocket)
    // =============================================================================

    fmt.println("\nTest 4: Testing boolean difference (pocket)...")

    // Create a smaller rectangle as cutting tool (on XY plane)
    rect_points := []f64{
        -5.0, -5.0,  // Bottom-left
         5.0, -5.0,  // Bottom-right
         5.0,  5.0,  // Top-right
        -5.0,  5.0,  // Top-left
    }

    rect_wire := OCCT_Wire_FromPoints2D(
        raw_data(rect_points),
        4,
        true,  // closed
    )

    if rect_wire == nil {
        fmt.eprintln("❌ FAILED: Could not create rectangle wire")
        return
    }
    defer OCCT_Wire_Delete(rect_wire)

    // Extrude rectangle through the pentagon
    cut_solid := OCCT_Extrude_Wire(rect_wire, 0, 0, extrusion_height * 1.5)
    if cut_solid == nil {
        fmt.eprintln("❌ FAILED: Could not extrude cutting tool")
        return
    }
    defer delete_shape(cut_solid)

    // Perform boolean difference (solid - cut_solid)
    result := OCCT_Boolean_Difference(solid, cut_solid)
    if result == nil {
        fmt.eprintln("❌ FAILED: Boolean difference failed")
        return
    }
    defer delete_shape(result)

    if !is_valid(result) {
        fmt.eprintln("❌ FAILED: Boolean result is invalid")
        return
    }

    fmt.println("✓ Boolean difference succeeded")

    // Tessellate result to verify it's renderable
    result_mesh := OCCT_Tessellate(result, DEFAULT_TESSELLATION)
    if result_mesh == nil {
        fmt.eprintln("❌ FAILED: Could not tessellate boolean result")
        return
    }
    defer delete_mesh(result_mesh)

    fmt.printf("✓ Result mesh: %d vertices, %d triangles\n",
        result_mesh.num_vertices, result_mesh.num_triangles)

    // =============================================================================
    // Summary
    // =============================================================================

    fmt.println("\n=== All Tests PASSED! ✅ ===")
    fmt.println("\nOCCT integration is working correctly!")
    fmt.println("Pentagon extrusion works (unlike Manifold)")
    fmt.println("Boolean operations work (pocket cut succeeded)")

    // =============================================================================
    // Test 5: Primitive Shapes
    // =============================================================================

    fmt.println("\n=== Test 5: Primitive Shapes ===")

    // Test Box
    fmt.println("\nTesting box primitive (20x30x40mm)...")
    box := create_box(20, 30, 40)
    if box == nil {
        fmt.eprintln("❌ FAILED: Could not create box")
        return
    }
    defer delete_shape(box)

    if !is_valid(box) {
        fmt.eprintln("❌ FAILED: Box is invalid")
        return
    }

    box_type := get_type(box)
    fmt.printf("✓ Box created successfully (type: %v)\n", box_type)

    // Tessellate box
    box_mesh := OCCT_Tessellate(box, DEFAULT_TESSELLATION)
    if box_mesh == nil {
        fmt.eprintln("❌ FAILED: Could not tessellate box")
        return
    }
    defer delete_mesh(box_mesh)

    fmt.printf("✓ Box mesh: %d vertices, %d triangles\n",
        box_mesh.num_vertices, box_mesh.num_triangles)

    // Test Cylinder
    fmt.println("\nTesting cylinder primitive (r=10mm, h=50mm)...")
    cylinder := create_cylinder(10, 50)
    if cylinder == nil {
        fmt.eprintln("❌ FAILED: Could not create cylinder")
        return
    }
    defer delete_shape(cylinder)

    if !is_valid(cylinder) {
        fmt.eprintln("❌ FAILED: Cylinder is invalid")
        return
    }

    cyl_type := get_type(cylinder)
    fmt.printf("✓ Cylinder created successfully (type: %v)\n", cyl_type)

    cyl_mesh := OCCT_Tessellate(cylinder, DEFAULT_TESSELLATION)
    if cyl_mesh == nil {
        fmt.eprintln("❌ FAILED: Could not tessellate cylinder")
        return
    }
    defer delete_mesh(cyl_mesh)

    fmt.printf("✓ Cylinder mesh: %d vertices, %d triangles\n",
        cyl_mesh.num_vertices, cyl_mesh.num_triangles)

    // Test Sphere
    fmt.println("\nTesting sphere primitive (r=15mm)...")
    sphere := create_sphere(15)
    if sphere == nil {
        fmt.eprintln("❌ FAILED: Could not create sphere")
        return
    }
    defer delete_shape(sphere)

    if !is_valid(sphere) {
        fmt.eprintln("❌ FAILED: Sphere is invalid")
        return
    }

    sphere_type := get_type(sphere)
    fmt.printf("✓ Sphere created successfully (type: %v)\n", sphere_type)

    sphere_mesh := OCCT_Tessellate(sphere, DEFAULT_TESSELLATION)
    if sphere_mesh == nil {
        fmt.eprintln("❌ FAILED: Could not tessellate sphere")
        return
    }
    defer delete_mesh(sphere_mesh)

    fmt.printf("✓ Sphere mesh: %d vertices, %d triangles\n",
        sphere_mesh.num_vertices, sphere_mesh.num_triangles)

    // Test Cone
    fmt.println("\nTesting cone primitive (r1=10mm, r2=5mm, h=30mm)...")
    cone := create_cone(10, 5, 30)
    if cone == nil {
        fmt.eprintln("❌ FAILED: Could not create cone")
        return
    }
    defer delete_shape(cone)

    if !is_valid(cone) {
        fmt.eprintln("❌ FAILED: Cone is invalid")
        return
    }

    cone_type := get_type(cone)
    fmt.printf("✓ Cone created successfully (type: %v)\n", cone_type)

    cone_mesh := OCCT_Tessellate(cone, DEFAULT_TESSELLATION)
    if cone_mesh == nil {
        fmt.eprintln("❌ FAILED: Could not tessellate cone")
        return
    }
    defer delete_mesh(cone_mesh)

    fmt.printf("✓ Cone mesh: %d vertices, %d triangles\n",
        cone_mesh.num_vertices, cone_mesh.num_triangles)

    // Test Torus
    fmt.println("\nTesting torus primitive (major=20mm, minor=5mm)...")
    torus := create_torus(20, 5)
    if torus == nil {
        fmt.eprintln("❌ FAILED: Could not create torus")
        return
    }
    defer delete_shape(torus)

    if !is_valid(torus) {
        fmt.eprintln("❌ FAILED: Torus is invalid")
        return
    }

    torus_type := get_type(torus)
    fmt.printf("✓ Torus created successfully (type: %v)\n", torus_type)

    torus_mesh := OCCT_Tessellate(torus, DEFAULT_TESSELLATION)
    if torus_mesh == nil {
        fmt.eprintln("❌ FAILED: Could not tessellate torus")
        return
    }
    defer delete_mesh(torus_mesh)

    fmt.printf("✓ Torus mesh: %d vertices, %d triangles\n",
        torus_mesh.num_vertices, torus_mesh.num_triangles)

    fmt.println("\n✅ All primitive tests passed!")

    // =============================================================================
    // Final Summary
    // =============================================================================

    fmt.println("\n=== ALL TESTS PASSED! ✅ ===")
    fmt.println("\nOCCT integration is fully operational!")
    fmt.println("✅ Pentagon extrusion works (unlike Manifold)")
    fmt.println("✅ Boolean operations work (pocket cut succeeded)")
    fmt.println("✅ All 5 primitives work (box, cylinder, sphere, cone, torus)")
}
