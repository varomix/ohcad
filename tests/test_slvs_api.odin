// Test harness for libslvs (SolveSpace constraint solver) C API
// Similar to test_manifold_api.odin

package tests

import "core:fmt"
import "core:c"

// Type definitions from slvs.h
Slvs_hParam :: u32
Slvs_hEntity :: u32
Slvs_hConstraint :: u32
Slvs_hGroup :: u32

SLVS_FREE_IN_3D :: 0

// Result codes
SLVS_RESULT_OKAY :: 0
SLVS_RESULT_INCONSISTENT :: 1
SLVS_RESULT_DIDNT_CONVERGE :: 2
SLVS_RESULT_TOO_MANY_UNKNOWNS :: 3
SLVS_RESULT_REDUNDANT_OKAY :: 4

// Entity types
SLVS_E_POINT_IN_3D :: 50000
SLVS_E_POINT_IN_2D :: 50001
SLVS_E_NORMAL_IN_3D :: 60000
SLVS_E_NORMAL_IN_2D :: 60001
SLVS_E_DISTANCE :: 70000
SLVS_E_WORKPLANE :: 80000
SLVS_E_LINE_SEGMENT :: 80001
SLVS_E_CIRCLE :: 80003
SLVS_E_ARC_OF_CIRCLE :: 80004

// Constraint types
SLVS_C_POINTS_COINCIDENT :: 100000
SLVS_C_PT_PT_DISTANCE :: 100001
SLVS_C_HORIZONTAL :: 100019
SLVS_C_VERTICAL :: 100020
SLVS_C_PARALLEL :: 100025
SLVS_C_PERPENDICULAR :: 100026

// Structs
Slvs_Param :: struct {
    h: Slvs_hParam,
    group: Slvs_hGroup,
    val: f64,
}

Slvs_Entity :: struct {
    h: Slvs_hEntity,
    group: Slvs_hGroup,
    type: c.int,
    wrkpl: Slvs_hEntity,
    point: [4]Slvs_hEntity,
    normal: Slvs_hEntity,
    distance: Slvs_hEntity,
    param: [4]Slvs_hParam,
}

Slvs_Constraint :: struct {
    h: Slvs_hConstraint,
    group: Slvs_hGroup,
    type: c.int,
    wrkpl: Slvs_hEntity,
    valA: f64,
    ptA: Slvs_hEntity,
    ptB: Slvs_hEntity,
    entityA: Slvs_hEntity,
    entityB: Slvs_hEntity,
    entityC: Slvs_hEntity,
    entityD: Slvs_hEntity,
    other: c.int,
    other2: c.int,
}

Slvs_SolveResult :: struct {
    result: c.int,
    dof: c.int,
    nbad: c.int,
}

// FFI bindings (stateful API - simpler to use)
foreign import slvs "../libs/libslvs.3.2.dylib"

@(default_calling_convention="c")
foreign slvs {
    // Add entities
    Slvs_AddBase2D :: proc(grouph: u32) -> Slvs_Entity ---
    Slvs_AddPoint2D :: proc(grouph: u32, u: f64, v: f64, workplane: Slvs_Entity) -> Slvs_Entity ---
    Slvs_AddPoint3D :: proc(grouph: u32, x: f64, y: f64, z: f64) -> Slvs_Entity ---
    Slvs_AddLine2D :: proc(grouph: u32, ptA: Slvs_Entity, ptB: Slvs_Entity, workplane: Slvs_Entity) -> Slvs_Entity ---

    // Add constraints
    Slvs_Distance :: proc(grouph: u32, entityA: Slvs_Entity, entityB: Slvs_Entity, value: f64, workplane: Slvs_Entity) -> Slvs_Constraint ---
    Slvs_Vertical :: proc(grouph: u32, entityA: Slvs_Entity, workplane: Slvs_Entity, entityB: Slvs_Entity) -> Slvs_Constraint ---
    Slvs_Horizontal :: proc(grouph: u32, entityA: Slvs_Entity, workplane: Slvs_Entity, entityB: Slvs_Entity) -> Slvs_Constraint ---
    Slvs_Coincident :: proc(grouph: u32, entityA: Slvs_Entity, entityB: Slvs_Entity, workplane: Slvs_Entity) -> Slvs_Constraint ---

    // Solve and query
    Slvs_SolveSketch :: proc(hg: u32, bad: ^^Slvs_hConstraint) -> Slvs_SolveResult ---
    Slvs_GetParamValue :: proc(ph: u32) -> f64 ---
    Slvs_SetParamValue :: proc(ph: u32, value: f64) ---
    Slvs_ClearSketch :: proc() ---
}

// Test 1: Simple 2D constraint - Two points with distance
test_simple_2d_distance :: proc() -> bool {
    fmt.println("\n=== Test 1: Simple 2D Distance Constraint ===")

    g: u32 = 1

    // Create workplane (XY plane)
    wp := Slvs_AddBase2D(g)
    fmt.printf("Workplane created: handle=%d\n", wp.h)

    // Create two points
    p1 := Slvs_AddPoint2D(g, 0.0, 10.0, wp)
    p2 := Slvs_AddPoint2D(g, 5.0, 20.0, wp)
    fmt.printf("Point 1: handle=%d, params=[%d, %d]\n", p1.h, p1.param[0], p1.param[1])
    fmt.printf("Point 2: handle=%d, params=[%d, %d]\n", p2.h, p2.param[0], p2.param[1])

    // Add vertical constraint (points should align vertically)
    c1 := Slvs_Vertical(g, p1, wp, p2)
    fmt.printf("Vertical constraint added: handle=%d\n", c1.h)

    // Solve
    res := Slvs_SolveSketch(g, nil)
    fmt.printf("Solve result: %d (0=OK, 1=inconsistent, 2=no converge)\n", res.result)
    fmt.printf("Degrees of freedom: %d\n", res.dof)

    if res.result != SLVS_RESULT_OKAY && res.result != SLVS_RESULT_REDUNDANT_OKAY {
        fmt.printf("ERROR: Solver failed!\n")
        Slvs_ClearSketch()
        return false
    }

    // Get solved positions
    p1x := Slvs_GetParamValue(p1.param[0])
    p1y := Slvs_GetParamValue(p1.param[1])
    p2x := Slvs_GetParamValue(p2.param[0])
    p2y := Slvs_GetParamValue(p2.param[1])

    fmt.printf("Solved positions:\n")
    fmt.printf("  P1: (%.3f, %.3f)\n", p1x, p1y)
    fmt.printf("  P2: (%.3f, %.3f)\n", p2x, p2y)

    // Verify: X coordinates should be equal (vertical constraint)
    tolerance :: 0.001
    if abs(p1x - p2x) > tolerance {
        fmt.printf("ERROR: Points not vertically aligned! diff=%.6f\n", abs(p1x - p2x))
        Slvs_ClearSketch()
        return false
    }

    fmt.println("✓ Test passed: Points are vertically aligned")
    Slvs_ClearSketch()
    return true
}

// Test 2: Rectangle with constraints
test_constrained_rectangle :: proc() -> bool {
    fmt.println("\n=== Test 2: Constrained Rectangle ===")

    g: u32 = 1

    // Create workplane
    wp := Slvs_AddBase2D(g)

    // Create 4 points for rectangle (initial guess)
    p1 := Slvs_AddPoint2D(g, 0.0, 0.0, wp)
    p2 := Slvs_AddPoint2D(g, 10.0, 0.0, wp)
    p3 := Slvs_AddPoint2D(g, 10.0, 5.0, wp)
    p4 := Slvs_AddPoint2D(g, 0.0, 5.0, wp)

    // Create lines
    line1 := Slvs_AddLine2D(g, p1, p2, wp)
    line2 := Slvs_AddLine2D(g, p2, p3, wp)
    line3 := Slvs_AddLine2D(g, p3, p4, wp)
    line4 := Slvs_AddLine2D(g, p4, p1, wp)

    // Add constraints
    // Horizontal bottom and top
    Slvs_Horizontal(g, line1, wp, Slvs_Entity{})
    Slvs_Horizontal(g, line3, wp, Slvs_Entity{})

    // Vertical left and right
    Slvs_Vertical(g, line4, wp, Slvs_Entity{})
    Slvs_Vertical(g, line2, wp, Slvs_Entity{})

    // Fixed distances
    Slvs_Distance(g, p1, p2, 20.0, wp)  // Width = 20
    Slvs_Distance(g, p2, p3, 10.0, wp)  // Height = 10

    // Solve
    res := Slvs_SolveSketch(g, nil)
    fmt.printf("Solve result: %d, DOF: %d\n", res.result, res.dof)

    if res.result != SLVS_RESULT_OKAY && res.result != SLVS_RESULT_REDUNDANT_OKAY {
        fmt.printf("ERROR: Solver failed!\n")
        Slvs_ClearSketch()
        return false
    }

    // Get solved positions
    p1x := Slvs_GetParamValue(p1.param[0])
    p1y := Slvs_GetParamValue(p1.param[1])
    p2x := Slvs_GetParamValue(p2.param[0])
    p2y := Slvs_GetParamValue(p2.param[1])
    p3x := Slvs_GetParamValue(p3.param[0])
    p3y := Slvs_GetParamValue(p3.param[1])
    p4x := Slvs_GetParamValue(p4.param[0])
    p4y := Slvs_GetParamValue(p4.param[1])

    fmt.printf("Rectangle corners:\n")
    fmt.printf("  P1: (%.3f, %.3f)\n", p1x, p1y)
    fmt.printf("  P2: (%.3f, %.3f)\n", p2x, p2y)
    fmt.printf("  P3: (%.3f, %.3f)\n", p3x, p3y)
    fmt.printf("  P4: (%.3f, %.3f)\n", p4x, p4y)

    // Verify width and height
    width := abs(p2x - p1x)
    height := abs(p3y - p2y)

    fmt.printf("Width: %.3f (expected 20.0)\n", width)
    fmt.printf("Height: %.3f (expected 10.0)\n", height)

    tolerance :: 0.001
    if abs(width - 20.0) > tolerance || abs(height - 10.0) > tolerance {
        fmt.printf("ERROR: Rectangle dimensions incorrect!\n")
        Slvs_ClearSketch()
        return false
    }

    fmt.println("✓ Test passed: Rectangle correctly constrained")
    Slvs_ClearSketch()
    return true
}

main :: proc() {
    fmt.println("libslvs (SolveSpace Solver) API Test")
    fmt.println("=====================================")

    test1_passed := test_simple_2d_distance()
    test2_passed := test_constrained_rectangle()

    fmt.println("\n=== Test Summary ===")
    fmt.printf("Test 1 (Simple 2D Distance): %s\n", test1_passed ? "PASS" : "FAIL")
    fmt.printf("Test 2 (Constrained Rectangle): %s\n", test2_passed ? "PASS" : "FAIL")

    if test1_passed && test2_passed {
        fmt.println("\n✓ All tests passed!")
    } else {
        fmt.println("\n✗ Some tests failed")
    }
}
