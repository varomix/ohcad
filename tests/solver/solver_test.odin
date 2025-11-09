// tests/solver - Constraint Solver Tests
package solver_test

import "core:fmt"
import "core:math"
import sketch "../../src/features/sketch"

main :: proc() {
    fmt.println("=== Constraint Solver Tests ===\n")

    // Run all tests
    test_distance_constraint()
    test_horizontal_constraint()
    test_perpendicular_constraint()
    test_rectangle_constraints()
    test_overconstrained()
    test_underconstrained()

    fmt.println("\n=== All Tests Complete ===")
}

// =============================================================================
// Test 1: Simple Distance Constraint
// =============================================================================

test_distance_constraint :: proc() {
    fmt.println("Test 1: Distance Constraint")
    fmt.println("----------------------------")

    // Create sketch
    sk := new(sketch.Sketch2D)
    sk^ = sketch.sketch_init("DistanceTest", sketch.sketch_plane_xy())
    defer sketch.sketch_destroy(sk)
    defer free(sk)

    // Add two points at arbitrary positions
    // Fix first point to eliminate rigid body motion
    p1_id := sketch.sketch_add_point(sk, 0.0, 0.0, true)  // Fixed
    p2_id := sketch.sketch_add_point(sk, 1.5, 2.3, false)

    // Add distance constraint: points must be 2.0 units apart
    target_distance := 2.0
    sketch.sketch_add_constraint(sk, .Distance, sketch.DistanceData{
        point1_id = p1_id,
        point2_id = p2_id,
        distance = target_distance,
    })

    // Also fix the angle to fully constrain (otherwise p2 can rotate around p1)
    sketch.sketch_add_constraint(sk, .DistanceX, sketch.DistanceXData{
        point1_id = p1_id,
        point2_id = p2_id,
        distance = target_distance,  // Makes it horizontal at distance 2.0
    })

    fmt.println("Before solving:")
    p1 := sketch.sketch_get_point(sk, p1_id)
    p2 := sketch.sketch_get_point(sk, p2_id)
    dx := p2.x - p1.x
    dy := p2.y - p1.y
    initial_dist := math.sqrt(dx*dx + dy*dy)
    fmt.printf("  Point 1: (%.3f, %.3f) [FIXED]\n", p1.x, p1.y)
    fmt.printf("  Point 2: (%.3f, %.3f)\n", p2.x, p2.y)
    fmt.printf("  Actual distance: %.6f\n", initial_dist)
    fmt.printf("  Target: horizontal line at distance %.6f\n", target_distance)

    // Solve constraints
    result := sketch.sketch_solve_constraints(sk)
    sketch.solver_result_print(result)

    // Verify result
    p1 = sketch.sketch_get_point(sk, p1_id)
    p2 = sketch.sketch_get_point(sk, p2_id)
    dx = p2.x - p1.x
    dy = p2.y - p1.y
    final_dist := math.sqrt(dx*dx + dy*dy)

    fmt.println("\nAfter solving:")
    fmt.printf("  Point 1: (%.6f, %.6f)\n", p1.x, p1.y)
    fmt.printf("  Point 2: (%.6f, %.6f)\n", p2.x, p2.y)
    fmt.printf("  Final distance: %.6f\n", final_dist)
    fmt.printf("  dx: %.6f, dy: %.6e\n", dx, dy)
    fmt.printf("  Error: %.6e\n", math.abs(final_dist - target_distance))

    // Check success (solver tolerance is 1e-6 for residuals, so we use 1e-3 for measurements)
    if result.status == .Success {
        if math.abs(final_dist - target_distance) < 1e-3 && math.abs(dy) < 2e-3 {
            fmt.println("✅ PASS: Distance constraint satisfied")
        } else {
            fmt.println("❌ FAIL: Distance constraint not satisfied")
        }
    } else {
        fmt.println("❌ FAIL: Solver did not converge")
    }

    fmt.println()
}

// =============================================================================
// Test 2: Horizontal Constraint
// =============================================================================

test_horizontal_constraint :: proc() {
    fmt.println("Test 2: Horizontal Constraint")
    fmt.println("------------------------------")

    // Create sketch
    sk := new(sketch.Sketch2D)
    sk^ = sketch.sketch_init("HorizontalTest", sketch.sketch_plane_xy())
    defer sketch.sketch_destroy(sk)
    defer free(sk)

    // Add two points and a line (fix first point to avoid rigid body motion)
    p1_id := sketch.sketch_add_point(sk, 0.0, 0.0, true)  // Fixed
    p2_id := sketch.sketch_add_point(sk, 1.0, 0.7, false)  // Not horizontal initially
    line_id := sketch.sketch_add_line(sk, p1_id, p2_id)

    // Add horizontal constraint
    sketch.sketch_add_constraint(sk, .Horizontal, sketch.HorizontalData{
        line_id = line_id,
    })

    fmt.println("Before solving:")
    p1 := sketch.sketch_get_point(sk, p1_id)
    p2 := sketch.sketch_get_point(sk, p2_id)
    fmt.printf("  Point 1: (%.3f, %.3f)\n", p1.x, p1.y)
    fmt.printf("  Point 2: (%.3f, %.3f)\n", p2.x, p2.y)
    fmt.printf("  dy = %.6f\n", p2.y - p1.y)

    // Solve constraints
    result := sketch.sketch_solve_constraints(sk)
    sketch.solver_result_print(result)

    // Verify result
    p1 = sketch.sketch_get_point(sk, p1_id)
    p2 = sketch.sketch_get_point(sk, p2_id)
    dy := p2.y - p1.y

    fmt.println("\nAfter solving:")
    fmt.printf("  Point 1: (%.6f, %.6f)\n", p1.x, p1.y)
    fmt.printf("  Point 2: (%.6f, %.6f)\n", p2.x, p2.y)
    fmt.printf("  dy = %.6e\n", dy)

    // Check success
    if result.status == .Success {
        if math.abs(dy) < 1e-5 {
            fmt.println("✅ PASS: Horizontal constraint satisfied")
        } else {
            fmt.println("❌ FAIL: Horizontal constraint not satisfied")
        }
    } else {
        fmt.println("❌ FAIL: Solver did not converge")
    }

    fmt.println()
}

// =============================================================================
// Test 3: Perpendicular Constraint
// =============================================================================

test_perpendicular_constraint :: proc() {
    fmt.println("Test 3: Perpendicular Constraint")
    fmt.println("---------------------------------")

    // Create sketch
    sk := new(sketch.Sketch2D)
    sk^ = sketch.sketch_init("PerpendicularTest", sketch.sketch_plane_xy())
    defer sketch.sketch_destroy(sk)
    defer free(sk)

    // Add four points and two lines (fix some to avoid rigid body motion)
    p1_id := sketch.sketch_add_point(sk, 0.0, 0.0, true)  // Fixed
    p2_id := sketch.sketch_add_point(sk, 1.0, 0.0, true)  // Fixed (line 1 horizontal)
    p3_id := sketch.sketch_add_point(sk, 0.0, 0.0, true)  // Fixed (shared start)
    p4_id := sketch.sketch_add_point(sk, 0.5, 0.8, false)  // Free - will be solved

    line1_id := sketch.sketch_add_line(sk, p1_id, p2_id)
    line2_id := sketch.sketch_add_line(sk, p3_id, p4_id)

    // Add perpendicular constraint
    sketch.sketch_add_constraint(sk, .Perpendicular, sketch.PerpendicularData{
        line1_id = line1_id,
        line2_id = line2_id,
    })

    fmt.println("Before solving:")
    p1 := sketch.sketch_get_point(sk, p1_id)
    p2 := sketch.sketch_get_point(sk, p2_id)
    p3 := sketch.sketch_get_point(sk, p3_id)
    p4 := sketch.sketch_get_point(sk, p4_id)

    v1x := p2.x - p1.x
    v1y := p2.y - p1.y
    v2x := p4.x - p3.x
    v2y := p4.y - p3.y
    dot := v1x*v2x + v1y*v2y

    fmt.printf("  Line 1: (%.3f,%.3f) → (%.3f,%.3f)\n", p1.x, p1.y, p2.x, p2.y)
    fmt.printf("  Line 2: (%.3f,%.3f) → (%.3f,%.3f)\n", p3.x, p3.y, p4.x, p4.y)
    fmt.printf("  Dot product: %.6f\n", dot)

    // Solve constraints
    result := sketch.sketch_solve_constraints(sk)
    sketch.solver_result_print(result)

    // Verify result
    p1 = sketch.sketch_get_point(sk, p1_id)
    p2 = sketch.sketch_get_point(sk, p2_id)
    p3 = sketch.sketch_get_point(sk, p3_id)
    p4 = sketch.sketch_get_point(sk, p4_id)

    v1x = p2.x - p1.x
    v1y = p2.y - p1.y
    v2x = p4.x - p3.x
    v2y = p4.y - p3.y
    dot = v1x*v2x + v1y*v2y

    fmt.println("\nAfter solving:")
    fmt.printf("  Line 1: (%.6f,%.6f) → (%.6f,%.6f)\n", p1.x, p1.y, p2.x, p2.y)
    fmt.printf("  Line 2: (%.6f,%.6f) → (%.6f,%.6f)\n", p3.x, p3.y, p4.x, p4.y)
    fmt.printf("  Dot product: %.6e\n", dot)

    // Check success
    if result.status == .Success {
        if math.abs(dot) < 1e-5 {
            fmt.println("✅ PASS: Perpendicular constraint satisfied")
        } else {
            fmt.println("❌ FAIL: Perpendicular constraint not satisfied")
        }
    } else {
        fmt.println("❌ FAIL: Solver did not converge")
    }

    fmt.println()
}

// =============================================================================
// Test 4: Rectangle with Multiple Constraints
// =============================================================================

test_rectangle_constraints :: proc() {
    fmt.println("Test 4: Rectangle (Multiple Constraints)")
    fmt.println("-----------------------------------------")

    // Create sketch
    sk := new(sketch.Sketch2D)
    sk^ = sketch.sketch_init("RectangleTest", sketch.sketch_plane_xy())
    defer sketch.sketch_destroy(sk)
    defer free(sk)

    // Add four points (rough rectangle)
    p1_id := sketch.sketch_add_point(sk, 0.0, 0.0, true)   // Fixed origin
    p2_id := sketch.sketch_add_point(sk, 3.2, 0.1, false)
    p3_id := sketch.sketch_add_point(sk, 3.1, 2.1, false)
    p4_id := sketch.sketch_add_point(sk, 0.1, 1.9, false)

    // Create lines
    line1_id := sketch.sketch_add_line(sk, p1_id, p2_id)  // Bottom
    line2_id := sketch.sketch_add_line(sk, p2_id, p3_id)  // Right
    line3_id := sketch.sketch_add_line(sk, p3_id, p4_id)  // Top
    line4_id := sketch.sketch_add_line(sk, p4_id, p1_id)  // Left

    // Add constraints for rectangle:
    // 1. Bottom horizontal
    sketch.sketch_add_constraint(sk, .Horizontal, sketch.HorizontalData{line_id = line1_id})

    // 2. Right vertical (perpendicular to bottom)
    sketch.sketch_add_constraint(sk, .Perpendicular, sketch.PerpendicularData{
        line1_id = line1_id,
        line2_id = line2_id,
    })

    // 3. Top horizontal
    sketch.sketch_add_constraint(sk, .Horizontal, sketch.HorizontalData{line_id = line3_id})

    // 4. Left vertical (perpendicular to bottom)
    sketch.sketch_add_constraint(sk, .Perpendicular, sketch.PerpendicularData{
        line1_id = line1_id,
        line2_id = line4_id,
    })

    // 5. Width = 3.0
    sketch.sketch_add_constraint(sk, .DistanceX, sketch.DistanceXData{
        point1_id = p1_id,
        point2_id = p2_id,
        distance = 3.0,
    })

    // 6. Height = 2.0
    sketch.sketch_add_constraint(sk, .DistanceY, sketch.DistanceYData{
        point1_id = p1_id,
        point2_id = p4_id,
        distance = 2.0,
    })

    fmt.println("Target: 3.0 × 2.0 rectangle with origin at (0,0)")

    // Check DOF
    dof_info := sketch.sketch_calculate_dof(sk)
    sketch.dof_print_info(dof_info)
    fmt.println()

    // Solve constraints
    result := sketch.sketch_solve_constraints(sk)
    sketch.solver_result_print(result)

    // Verify result
    p1 := sketch.sketch_get_point(sk, p1_id)
    p2 := sketch.sketch_get_point(sk, p2_id)
    p3 := sketch.sketch_get_point(sk, p3_id)
    p4 := sketch.sketch_get_point(sk, p4_id)

    fmt.println("\nFinal rectangle corners:")
    fmt.printf("  P1: (%.6f, %.6f)\n", p1.x, p1.y)
    fmt.printf("  P2: (%.6f, %.6f)\n", p2.x, p2.y)
    fmt.printf("  P3: (%.6f, %.6f)\n", p3.x, p3.y)
    fmt.printf("  P4: (%.6f, %.6f)\n", p4.x, p4.y)

    // Check if rectangle is correct
    width := p2.x - p1.x
    height := p4.y - p1.y

    fmt.printf("\nDimensions:\n")
    fmt.printf("  Width: %.6f (target: 3.0)\n", width)
    fmt.printf("  Height: %.6f (target: 2.0)\n", height)

    // Verify all corners
    success := true
    success = success && math.abs(p1.x - 0.0) < 1e-5
    success = success && math.abs(p1.y - 0.0) < 1e-5
    success = success && math.abs(p2.x - 3.0) < 1e-5
    success = success && math.abs(p2.y - 0.0) < 1e-5
    success = success && math.abs(p3.x - 3.0) < 1e-5
    success = success && math.abs(p3.y - 2.0) < 1e-5
    success = success && math.abs(p4.x - 0.0) < 1e-5
    success = success && math.abs(p4.y - 2.0) < 1e-5

    if result.status == .Success && success {
        fmt.println("✅ PASS: Rectangle constraints satisfied")
    } else {
        fmt.println("❌ FAIL: Rectangle constraints not satisfied")
    }

    fmt.println()
}

// =============================================================================
// Test 5: Overconstrained System
// =============================================================================

test_overconstrained :: proc() {
    fmt.println("Test 5: Overconstrained System")
    fmt.println("-------------------------------")

    // Create sketch
    sk := new(sketch.Sketch2D)
    sk^ = sketch.sketch_init("OverconstrainedTest", sketch.sketch_plane_xy())
    defer sketch.sketch_destroy(sk)
    defer free(sk)

    // Add ONE point (fix one coordinate)
    p1_id := sketch.sketch_add_point(sk, 0.0, 0.0, false)

    // Add THREE constraints on TWO variables (overconstrained)
    sketch.sketch_add_constraint(sk, .DistanceX, sketch.DistanceXData{
        point1_id = p1_id,
        point2_id = p1_id,  // Self-constraint
        distance = 1.0,  // x = 1.0
    })

    sketch.sketch_add_constraint(sk, .DistanceY, sketch.DistanceYData{
        point1_id = p1_id,
        point2_id = p1_id,  // Self-constraint
        distance = 2.0,  // y = 2.0
    })

    sketch.sketch_add_constraint(sk, .Distance, sketch.DistanceData{
        point1_id = p1_id,
        point2_id = p1_id,  // Self-constraint
        distance = 3.0,  // Conflicts: can't have x=1, y=2, and distance=3 from origin
    })

    // Check DOF
    dof_info := sketch.sketch_calculate_dof(sk)
    sketch.dof_print_info(dof_info)
    fmt.println()

    // Try to solve
    result := sketch.sketch_solve_constraints(sk)
    sketch.solver_result_print(result)

    if result.status == .Overconstrained {
        fmt.println("✅ PASS: Correctly detected overconstrained system")
    } else {
        fmt.println("❌ FAIL: Did not detect overconstraint")
    }

    fmt.println()
}

// =============================================================================
// Test 6: Underconstrained System
// =============================================================================

test_underconstrained :: proc() {
    fmt.println("Test 6: Underconstrained System")
    fmt.println("--------------------------------")

    // Create sketch
    sk := new(sketch.Sketch2D)
    sk^ = sketch.sketch_init("UnderconstrainedTest", sketch.sketch_plane_xy())
    defer sketch.sketch_destroy(sk)
    defer free(sk)

    // Add two points
    p1_id := sketch.sketch_add_point(sk, 0.0, 0.0, false)
    p2_id := sketch.sketch_add_point(sk, 1.0, 0.0, false)

    // Add only one constraint (2 variables, 1 equation = 1 DOF remaining)
    sketch.sketch_add_constraint(sk, .Distance, sketch.DistanceData{
        point1_id = p1_id,
        point2_id = p2_id,
        distance = 2.0,
    })

    // Check DOF
    dof_info := sketch.sketch_calculate_dof(sk)
    sketch.dof_print_info(dof_info)
    fmt.println()

    // Try to solve
    result := sketch.sketch_solve_constraints(sk)
    sketch.solver_result_print(result)

    if result.status == .Underconstrained {
        fmt.println("✅ PASS: Correctly detected underconstrained system")
    } else {
        fmt.println("❌ FAIL: Did not detect underconstraint")
    }

    fmt.println()
}
