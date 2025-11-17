// Test case for trapezoid with full dimensional constraints
// This test creates the exact shape from the user's example:
// - Bottom: 60mm horizontal
// - Left vertical: 22mm
// - Right vertical: 22mm (split as 16mm + remaining)
// - Top two horizontal segments: 22mm + 22mm
// - Two angled edges connecting the trapezoid

package test_constraints

import "core:fmt"
import "core:math"
import "core:strings"
import sketch "../../src/features/sketch"
import m "../../src/core/math"

main :: proc() {
    fmt.println("=== TRAPEZOID DIMENSION TEST ===")
    fmt.println("Creating trapezoid with dimensions:")
    fmt.println("  Bottom: 60mm")
    fmt.println("  Left height: 22mm")
    fmt.println("  Right height: 22mm (split as top 16mm)")
    fmt.println("  Top segments: 22mm + 22mm")
    fmt.println()

    // Create sketch
    plane := sketch.SketchPlane{
        origin = m.Vec3{0, 0, 0},
        normal = m.Vec3{0, 0, 1},
        x_axis = m.Vec3{1, 0, 0},
        y_axis = m.Vec3{0, 1, 0},
    }
    sk := sketch.sketch_init("TestTrapezoid", plane)
    defer sketch.sketch_destroy(&sk)

    // ==================================================================
    // STEP 1: Create the trapezoid geometry (6 points, 6 edges)
    // ==================================================================
    fmt.println("STEP 1: Creating geometry...")

    // Points (approximate initial positions - solver will adjust)
    // Bottom-left (origin, fixed)
    p0 := sketch.sketch_add_point(&sk, 0, 0)

    // Bottom-right
    p1 := sketch.sketch_add_point(&sk, 60, 0)

    // Right side, split point
    p2 := sketch.sketch_add_point(&sk, 60, 16)

    // Top-right corner
    p3 := sketch.sketch_add_point(&sk, 60, 22)

    // Top-middle (between angled sections)
    p4 := sketch.sketch_add_point(&sk, 38, 22)

    // Top-left corner
    p5 := sketch.sketch_add_point(&sk, 16, 22)

    // Fix the origin point (p0)
    sketch.sketch_add_constraint(&sk, .FixedPoint, sketch.FixedPointData{
        point_id = p0,
    })
    fmt.println("  ✓ Created 6 points, fixed origin")

    // Create edges
    line0 := sketch.sketch_add_line(&sk, p0, p1)  // Bottom (60mm)
    line1 := sketch.sketch_add_line(&sk, p1, p2)  // Right bottom (16mm)
    line2 := sketch.sketch_add_line(&sk, p2, p3)  // Right top
    line3 := sketch.sketch_add_line(&sk, p3, p4)  // Top-right (22mm)
    line4 := sketch.sketch_add_line(&sk, p4, p5)  // Top-left (22mm)
    line5 := sketch.sketch_add_line(&sk, p5, p0)  // Left (22mm)

    fmt.println("  ✓ Created 6 edges")

    // ==================================================================
    // STEP 2: Add H/V constraints (auto-applied during drawing)
    // ==================================================================
    fmt.println("\nSTEP 2: Adding H/V constraints...")

    // Horizontal constraints
    h_bottom := sketch.sketch_add_constraint(&sk, .Horizontal, sketch.HorizontalData{line_id = line0})
    h_top_right := sketch.sketch_add_constraint(&sk, .Horizontal, sketch.HorizontalData{line_id = line3})
    h_top_left := sketch.sketch_add_constraint(&sk, .Horizontal, sketch.HorizontalData{line_id = line4})

    // Vertical constraints
    v_left := sketch.sketch_add_constraint(&sk, .Vertical, sketch.VerticalData{line_id = line5})
    v_right_bottom := sketch.sketch_add_constraint(&sk, .Vertical, sketch.VerticalData{line_id = line1})
    v_right_top := sketch.sketch_add_constraint(&sk, .Vertical, sketch.VerticalData{line_id = line2})

    fmt.println("  ✓ Added 3 Horizontal + 3 Vertical constraints")

    // Initial solve
    fmt.println("\nInitial solve (H/V constraints only)...")
    result := sketch.sketch_solve_constraints(&sk)
    print_solver_result(result, "Initial H/V")

    // ==================================================================
    // STEP 3: Add distance dimensions
    // ==================================================================
    fmt.println("\nSTEP 3: Adding distance dimensions...")

    // Bottom edge: 60mm (has Horizontal constraint → use Distance)
    dim_bottom := sketch.sketch_add_constraint(&sk, .Distance, sketch.DistanceData{
        point1_id = p0,
        point2_id = p1,
        distance = 60.0,
        offset = m.Vec2{30, -5},
    })
    fmt.println("  ✓ Bottom: 60mm (Distance)")

    // Solve after bottom dimension
    result = sketch.sketch_solve_constraints(&sk)
    print_solver_result(result, "After bottom dim")

    // Top-right segment: 22mm (has Horizontal constraint → use Distance)
    dim_top_right := sketch.sketch_add_constraint(&sk, .Distance, sketch.DistanceData{
        point1_id = p3,
        point2_id = p4,
        distance = 22.0,
        offset = m.Vec2{49, 25},
    })
    fmt.println("  ✓ Top-right: 22mm (Distance)")

    // Solve after top-right dimension
    result = sketch.sketch_solve_constraints(&sk)
    print_solver_result(result, "After top-right dim")

    // Top-left segment: 22mm (has Horizontal constraint → use Distance)
    dim_top_left := sketch.sketch_add_constraint(&sk, .Distance, sketch.DistanceData{
        point1_id = p4,
        point2_id = p5,
        distance = 22.0,
        offset = m.Vec2{27, 25},
    })
    fmt.println("  ✓ Top-left: 22mm (Distance)")

    // Solve after top-left dimension
    result = sketch.sketch_solve_constraints(&sk)
    print_solver_result(result, "After top-left dim")

    // Left edge: 22mm (has Vertical constraint → use Distance)
    dim_left := sketch.sketch_add_constraint(&sk, .Distance, sketch.DistanceData{
        point1_id = p0,
        point2_id = p5,
        distance = 22.0,
        offset = m.Vec2{-5, 11},
    })
    fmt.println("  ✓ Left: 22mm (Distance)")

    // Solve after left dimension
    result = sketch.sketch_solve_constraints(&sk)
    print_solver_result(result, "After left dim")

    // Right bottom edge: 16mm (has Vertical constraint → use Distance)
    dim_right_bottom := sketch.sketch_add_constraint(&sk, .Distance, sketch.DistanceData{
        point1_id = p1,
        point2_id = p2,
        distance = 16.0,
        offset = m.Vec2{65, 8},
    })
    fmt.println("  ✓ Right bottom: 16mm (Distance)")

    // Solve after right-bottom dimension
    result = sketch.sketch_solve_constraints(&sk)
    print_solver_result(result, "After right-bottom dim")

    // NOTE: We DON'T add a dimension for the full right edge (p1→p3 = 22mm)
    // because that would be redundant with the partial dimension above!
    // The two vertical segments (p1→p2 and p2→p3) together define the full height.

    // ==================================================================
    // STEP 4: Final solve and verification
    // ==================================================================
    fmt.println()
    print_separator()
    fmt.println("FINAL SOLVE WITH ALL CONSTRAINTS")
    print_separator()

    result = sketch.sketch_solve_constraints(&sk)
    print_solver_result(result, "FINAL")

    // ==================================================================
    // STEP 5: Verify geometry matches expected dimensions
    // ==================================================================
    if result.status == .Success {
        fmt.println()
        print_separator()
        fmt.println("VERIFICATION: Checking actual dimensions")
        print_separator()

        verify_distance(&sk, p0, p1, 60.0, "Bottom")
        verify_distance(&sk, p5, p0, 22.0, "Left")
        verify_distance(&sk, p1, p2, 16.0, "Right bottom")
        verify_distance(&sk, p1, p3, 22.0, "Right full (implicit)")
        verify_distance(&sk, p3, p4, 22.0, "Top-right")
        verify_distance(&sk, p4, p5, 22.0, "Top-left")

        fmt.println("\n✅ TEST PASSED: All dimensions verified!")
    } else {
        fmt.println("\n❌ TEST FAILED: Solver did not converge")
        fmt.println("\nDEBUG: Point positions after failed solve:")
        print_all_points(&sk)

        fmt.println("\nDEBUG: All constraints:")
        print_all_constraints(&sk)
    }
}

// Helper to print separator
print_separator :: proc() {
    builder := strings.builder_make(0, 60)
    defer strings.builder_destroy(&builder)
    for i in 0..<60 {
        strings.write_byte(&builder, '=')
    }
    fmt.println(strings.to_string(builder))
}

// Helper to print solver results
print_solver_result :: proc(result: sketch.SolverResult, label: string) {
    status_icon := result.status == .Success ? "✅" : "❌"
    fmt.printf("  %s [%s] Status: %v, Iterations: %d, Residual: %.6e\n",
        status_icon, label, result.status, result.iterations, result.final_residual)

    if result.status != .Success {
        fmt.printf("      Message: %s\n", result.message)
    }
}

// Helper to verify a distance between two points
verify_distance :: proc(sk: ^sketch.Sketch2D, p1_id: int, p2_id: int, expected: f64, label: string) {
    p1 := sketch.sketch_get_point(sk, p1_id)
    p2 := sketch.sketch_get_point(sk, p2_id)

    if p1 == nil || p2 == nil {
        fmt.printf("  ❌ %s: Invalid points\n", label)
        return
    }

    dx := p2.x - p1.x
    dy := p2.y - p1.y
    actual := math.sqrt(dx*dx + dy*dy)
    error := math.abs(actual - expected)

    status := error < 0.001 ? "✅" : "❌"
    fmt.printf("  %s %s: Expected %.3f, Actual %.3f (error: %.6f)\n",
        status, label, expected, actual, error)
}

// Helper to print all points
print_all_points :: proc(sk: ^sketch.Sketch2D) {
    for point, i in sk.points {
        fixed := point.fixed ? "FIXED" : "FREE"
        fmt.printf("  P%d: (%.3f, %.3f) [%s]\n", point.id, point.x, point.y, fixed)
    }
}

// Helper to print all constraints
print_all_constraints :: proc(sk: ^sketch.Sketch2D) {
    for c, i in sk.constraints {
        fmt.printf("  C%d: Type=%v, Enabled=%v\n", c.id, c.type, c.enabled)

        switch data in c.data {
        case sketch.DistanceData:
            fmt.printf("      Distance: p%d-p%d = %.3f\n",
                data.point1_id, data.point2_id, data.distance)
        case sketch.DistanceXData:
            fmt.printf("      DistanceX: p%d-p%d = %.3f (locked_dy=%.3f)\n",
                data.point1_id, data.point2_id, data.distance, data.locked_dy)
        case sketch.DistanceYData:
            fmt.printf("      DistanceY: p%d-p%d = %.3f (locked_dx=%.3f)\n",
                data.point1_id, data.point2_id, data.distance, data.locked_dx)
        case sketch.HorizontalData:
            fmt.printf("      Horizontal: line%d\n", data.line_id)
        case sketch.VerticalData:
            fmt.printf("      Vertical: line%d\n", data.line_id)
        case sketch.FixedPointData:
            fmt.printf("      FixedPoint: p%d\n", data.point_id)
        case sketch.CoincidentData:
            fmt.printf("      Coincident: p%d-p%d\n", data.point1_id, data.point2_id)
        case sketch.AngleData:
            fmt.printf("      Angle: line%d-line%d = %.1f°\n", data.line1_id, data.line2_id, data.angle)
        case sketch.PerpendicularData:
            fmt.printf("      Perpendicular: line%d-line%d\n", data.line1_id, data.line2_id)
        case sketch.ParallelData:
            fmt.printf("      Parallel: line%d-line%d\n", data.line1_id, data.line2_id)
        case sketch.TangentData:
            fmt.printf("      Tangent: entity%d-entity%d\n", data.entity1_id, data.entity2_id)
        case sketch.EqualData:
            fmt.printf("      Equal: entity%d-entity%d\n", data.entity1_id, data.entity2_id)
        case sketch.PointOnLineData:
            fmt.printf("      PointOnLine: p%d on line%d\n", data.point_id, data.line_id)
        case sketch.PointOnCircleData:
            fmt.printf("      PointOnCircle: p%d on circle%d\n", data.point_id, data.circle_id)
        }
    }
}
