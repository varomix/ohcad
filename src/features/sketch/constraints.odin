// features/sketch - 2D Sketch Constraint System
package ohcad_sketch

import "core:fmt"
import "core:math"
import m "../../core/math"

// Constraint types for parametric sketching
ConstraintType :: enum {
    // Point-to-point constraints
    Coincident,        // Two points must be at same location

    // Distance constraints
    Distance,          // Distance between two points
    DistanceX,         // Horizontal distance between two points
    DistanceY,         // Vertical distance between two points

    // Angle constraints
    Angle,             // Angle between two lines
    Perpendicular,     // Two lines must be perpendicular (90 degrees)
    Parallel,          // Two lines must be parallel (0 or 180 degrees)

    // Orientation constraints
    Horizontal,        // Line must be horizontal (parallel to X-axis)
    Vertical,          // Line must be vertical (parallel to Y-axis)

    // Geometric constraints
    Tangent,           // Line/circle or circle/circle tangency
    Equal,             // Equal length (lines) or equal radius (circles)

    // Point-on-entity constraints
    PointOnLine,       // Point lies on a line
    PointOnCircle,     // Point lies on a circle

    // Fixed constraints
    FixedPoint,        // Point position is fixed (not solved)
    FixedDistance,     // Distance value is fixed
    FixedAngle,        // Angle value is fixed
}

// Constraint data union - each constraint type has specific data
ConstraintData :: union {
    CoincidentData,
    DistanceData,
    DistanceXData,
    DistanceYData,
    AngleData,
    PerpendicularData,
    ParallelData,
    HorizontalData,
    VerticalData,
    TangentData,
    EqualData,
    PointOnLineData,
    PointOnCircleData,
    FixedPointData,
}

// Coincident: Two points must be at same location
CoincidentData :: struct {
    point1_id: int,
    point2_id: int,
}

// Distance: Distance between two points
DistanceData :: struct {
    point1_id: int,
    point2_id: int,
    distance: f64,
}

// DistanceX: Horizontal distance between two points
DistanceXData :: struct {
    point1_id: int,
    point2_id: int,
    distance: f64,  // Signed distance (can be negative)
}

// DistanceY: Vertical distance between two points
DistanceYData :: struct {
    point1_id: int,
    point2_id: int,
    distance: f64,  // Signed distance (can be negative)
}

// Angle: Angle between two lines
AngleData :: struct {
    line1_id: int,  // Entity ID of first line
    line2_id: int,  // Entity ID of second line
    angle: f64,     // Angle in radians
}

// Perpendicular: Two lines must be perpendicular
PerpendicularData :: struct {
    line1_id: int,
    line2_id: int,
}

// Parallel: Two lines must be parallel
ParallelData :: struct {
    line1_id: int,
    line2_id: int,
}

// Horizontal: Line must be horizontal
HorizontalData :: struct {
    line_id: int,
}

// Vertical: Line must be vertical
VerticalData :: struct {
    line_id: int,
}

// Tangent: Line/circle or circle/circle tangency
TangentData :: struct {
    entity1_id: int,
    entity2_id: int,
}

// Equal: Equal length (lines) or equal radius (circles)
EqualData :: struct {
    entity1_id: int,
    entity2_id: int,
}

// PointOnLine: Point lies on a line
PointOnLineData :: struct {
    point_id: int,
    line_id: int,
}

// PointOnCircle: Point lies on a circle
PointOnCircleData :: struct {
    point_id: int,
    circle_id: int,
}

// FixedPoint: Point position is fixed
FixedPointData :: struct {
    point_id: int,
    x: f64,
    y: f64,
}

// Main constraint structure
Constraint :: struct {
    id: int,
    type: ConstraintType,
    data: ConstraintData,
    enabled: bool,  // Can temporarily disable constraints
}

// Constraint error value - how much a constraint is violated
ConstraintError :: struct {
    constraint_id: int,
    error: f64,  // Magnitude of violation (0 = satisfied)
}

// Degrees of Freedom (DOF) information
DOFInfo :: struct {
    total_variables: int,     // Total number of variables (2 * num_points for 2D)
    num_constraints: int,     // Number of constraint equations
    dof: int,                 // Degrees of freedom (variables - constraints)
    status: DOFStatus,        // Under/well/over constrained status
}

DOFStatus :: enum {
    Underconstrained,   // DOF > 0 (needs more constraints)
    Wellconstrained,    // DOF == 0 (fully constrained)
    Overconstrained,    // DOF < 0 (conflicting constraints)
}

// =============================================================================
// Constraint Management
// =============================================================================

// Add constraint to sketch
sketch_add_constraint :: proc(sketch: ^Sketch2D, type: ConstraintType, data: ConstraintData) -> int {
    if sketch.constraints == nil {
        sketch.constraints = make([dynamic]Constraint)
    }

    constraint := Constraint{
        id = sketch.next_constraint_id,
        type = type,
        data = data,
        enabled = true,
    }

    append(&sketch.constraints, constraint)
    sketch.next_constraint_id += 1

    return constraint.id
}

// Remove constraint by ID
sketch_remove_constraint :: proc(sketch: ^Sketch2D, constraint_id: int) -> bool {
    if sketch.constraints == nil do return false

    for c, i in sketch.constraints {
        if c.id == constraint_id {
            ordered_remove(&sketch.constraints, i)
            return true
        }
    }
    return false
}

// Get constraint by ID
sketch_get_constraint :: proc(sketch: ^Sketch2D, constraint_id: int) -> ^Constraint {
    if sketch.constraints == nil do return nil

    for &c in sketch.constraints {
        if c.id == constraint_id {
            return &c
        }
    }
    return nil
}

// Enable/disable constraint
sketch_set_constraint_enabled :: proc(sketch: ^Sketch2D, constraint_id: int, enabled: bool) -> bool {
    c := sketch_get_constraint(sketch, constraint_id)
    if c == nil do return false

    c.enabled = enabled
    return true
}

// =============================================================================
// Degrees of Freedom (DOF) Calculation
// =============================================================================

// Calculate degrees of freedom for the sketch
sketch_calculate_dof :: proc(sketch: ^Sketch2D) -> DOFInfo {
    info: DOFInfo

    // Count total variables: each non-fixed point contributes 2 DOF (x, y)
    num_free_points := 0
    for point in sketch.points {
        if !point.fixed {
            num_free_points += 1
        }
    }
    info.total_variables = num_free_points * 2

    // Count constraint equations
    info.num_constraints = 0
    if sketch.constraints != nil {
        for c in sketch.constraints {
            if c.enabled {
                info.num_constraints += constraint_equation_count(c.type)
            }
        }
    }

    // Calculate DOF
    info.dof = info.total_variables - info.num_constraints

    // Determine status
    if info.dof > 0 {
        info.status = .Underconstrained
    } else if info.dof == 0 {
        info.status = .Wellconstrained
    } else {
        info.status = .Overconstrained
    }

    return info
}

// Get number of constraint equations for each constraint type
constraint_equation_count :: proc(type: ConstraintType) -> int {
    switch type {
    case .Coincident:
        return 2  // Two equations: dx = 0, dy = 0

    case .Distance:
        return 1  // One equation: |p1 - p2| = d

    case .DistanceX, .DistanceY:
        return 1  // One equation: (p1.x - p2.x) = d or (p1.y - p2.y) = d

    case .Angle:
        return 1  // One equation: angle(v1, v2) = theta

    case .Perpendicular:
        return 1  // One equation: dot(v1, v2) = 0

    case .Parallel:
        return 1  // One equation: cross(v1, v2) = 0 (in 2D: v1.x*v2.y - v1.y*v2.x = 0)

    case .Horizontal:
        return 1  // One equation: dy = 0

    case .Vertical:
        return 1  // One equation: dx = 0

    case .Tangent:
        return 1  // One equation (varies by entity types)

    case .Equal:
        return 1  // One equation: len1 = len2 or r1 = r2

    case .PointOnLine:
        return 1  // One equation: distance to line = 0

    case .PointOnCircle:
        return 1  // One equation: distance to center = radius

    case .FixedPoint:
        return 2  // Two equations: x = x0, y = y0

    case .FixedDistance, .FixedAngle:
        return 0  // These just fix parameter values, not point positions
    }

    return 0
}

// =============================================================================
// Constraint Equation Generation (for solver)
// =============================================================================

// Generate constraint equation residuals (how much each constraint is violated)
// This will be used by the numerical solver in Week 7
sketch_evaluate_constraints :: proc(sketch: ^Sketch2D) -> []f64 {
    if sketch.constraints == nil do return nil

    residuals := make([dynamic]f64, 0, len(sketch.constraints) * 2)

    for c in sketch.constraints {
        if !c.enabled do continue

        // Evaluate each constraint type
        switch data in c.data {
        case CoincidentData:
            residuals_coincident(sketch, data, &residuals)

        case DistanceData:
            residuals_distance(sketch, data, &residuals)

        case DistanceXData:
            residuals_distance_x(sketch, data, &residuals)

        case DistanceYData:
            residuals_distance_y(sketch, data, &residuals)

        case HorizontalData:
            residuals_horizontal(sketch, data, &residuals)

        case VerticalData:
            residuals_vertical(sketch, data, &residuals)

        case PerpendicularData:
            residuals_perpendicular(sketch, data, &residuals)

        case ParallelData:
            residuals_parallel(sketch, data, &residuals)

        case AngleData:
            residuals_angle(sketch, data, &residuals)

        case EqualData:
            residuals_equal(sketch, data, &residuals)

        case PointOnLineData:
            residuals_point_on_line(sketch, data, &residuals)

        case PointOnCircleData:
            residuals_point_on_circle(sketch, data, &residuals)

        case TangentData, FixedPointData:
            // These constraint types will be implemented later
            // For now, we skip them
        }
    }

    return residuals[:]
}

// Coincident constraint residuals: two points must be at same location
residuals_coincident :: proc(sketch: ^Sketch2D, data: CoincidentData, residuals: ^[dynamic]f64) {
    p1 := sketch_get_point(sketch, data.point1_id)
    p2 := sketch_get_point(sketch, data.point2_id)

    if p1 == nil || p2 == nil do return

    // Two equations: dx = 0, dy = 0
    append(residuals, p1.x - p2.x)
    append(residuals, p1.y - p2.y)
}

// Distance constraint residuals: distance between two points = d
residuals_distance :: proc(sketch: ^Sketch2D, data: DistanceData, residuals: ^[dynamic]f64) {
    p1 := sketch_get_point(sketch, data.point1_id)
    p2 := sketch_get_point(sketch, data.point2_id)

    if p1 == nil || p2 == nil do return

    dx := p1.x - p2.x
    dy := p1.y - p2.y
    dist := math.sqrt(dx*dx + dy*dy)

    // One equation: |p1 - p2| - d = 0
    append(residuals, dist - data.distance)
}

// DistanceX constraint residuals: horizontal distance = d
residuals_distance_x :: proc(sketch: ^Sketch2D, data: DistanceXData, residuals: ^[dynamic]f64) {
    p1 := sketch_get_point(sketch, data.point1_id)
    p2 := sketch_get_point(sketch, data.point2_id)

    if p1 == nil || p2 == nil do return

    // One equation: (p2.x - p1.x) - d = 0
    append(residuals, (p2.x - p1.x) - data.distance)
}

// DistanceY constraint residuals: vertical distance = d
residuals_distance_y :: proc(sketch: ^Sketch2D, data: DistanceYData, residuals: ^[dynamic]f64) {
    p1 := sketch_get_point(sketch, data.point1_id)
    p2 := sketch_get_point(sketch, data.point2_id)

    if p1 == nil || p2 == nil do return

    // One equation: (p2.y - p1.y) - d = 0
    append(residuals, (p2.y - p1.y) - data.distance)
}

// Horizontal constraint residuals: line must be horizontal
residuals_horizontal :: proc(sketch: ^Sketch2D, data: HorizontalData, residuals: ^[dynamic]f64) {
    // Get the line entity
    if data.line_id < 0 || data.line_id >= len(sketch.entities) do return

    entity := sketch.entities[data.line_id]
    line, ok := entity.(SketchLine)
    if !ok do return

    p1 := sketch_get_point(sketch, line.start_id)
    p2 := sketch_get_point(sketch, line.end_id)

    if p1 == nil || p2 == nil do return

    // One equation: dy = 0
    append(residuals, p2.y - p1.y)
}

// Vertical constraint residuals: line must be vertical
residuals_vertical :: proc(sketch: ^Sketch2D, data: VerticalData, residuals: ^[dynamic]f64) {
    // Get the line entity
    if data.line_id < 0 || data.line_id >= len(sketch.entities) do return

    entity := sketch.entities[data.line_id]
    line, ok := entity.(SketchLine)
    if !ok do return

    p1 := sketch_get_point(sketch, line.start_id)
    p2 := sketch_get_point(sketch, line.end_id)

    if p1 == nil || p2 == nil do return

    // One equation: dx = 0
    append(residuals, p2.x - p1.x)
}

// Perpendicular constraint residuals: two lines must be perpendicular
residuals_perpendicular :: proc(sketch: ^Sketch2D, data: PerpendicularData, residuals: ^[dynamic]f64) {
    // Get both line entities
    if data.line1_id < 0 || data.line1_id >= len(sketch.entities) do return
    if data.line2_id < 0 || data.line2_id >= len(sketch.entities) do return

    entity1 := sketch.entities[data.line1_id]
    entity2 := sketch.entities[data.line2_id]

    line1, ok1 := entity1.(SketchLine)
    line2, ok2 := entity2.(SketchLine)
    if !ok1 || !ok2 do return

    // Get line direction vectors
    p1_start := sketch_get_point(sketch, line1.start_id)
    p1_end := sketch_get_point(sketch, line1.end_id)
    p2_start := sketch_get_point(sketch, line2.start_id)
    p2_end := sketch_get_point(sketch, line2.end_id)

    if p1_start == nil || p1_end == nil || p2_start == nil || p2_end == nil do return

    v1x := p1_end.x - p1_start.x
    v1y := p1_end.y - p1_start.y
    v2x := p2_end.x - p2_start.x
    v2y := p2_end.y - p2_start.y

    // One equation: dot product = 0
    append(residuals, v1x*v2x + v1y*v2y)
}

// Parallel constraint residuals: two lines must be parallel
residuals_parallel :: proc(sketch: ^Sketch2D, data: ParallelData, residuals: ^[dynamic]f64) {
    // Get both line entities
    if data.line1_id < 0 || data.line1_id >= len(sketch.entities) do return
    if data.line2_id < 0 || data.line2_id >= len(sketch.entities) do return

    entity1 := sketch.entities[data.line1_id]
    entity2 := sketch.entities[data.line2_id]

    line1, ok1 := entity1.(SketchLine)
    line2, ok2 := entity2.(SketchLine)
    if !ok1 || !ok2 do return

    // Get line direction vectors
    p1_start := sketch_get_point(sketch, line1.start_id)
    p1_end := sketch_get_point(sketch, line1.end_id)
    p2_start := sketch_get_point(sketch, line2.start_id)
    p2_end := sketch_get_point(sketch, line2.end_id)

    if p1_start == nil || p1_end == nil || p2_start == nil || p2_end == nil do return

    v1x := p1_end.x - p1_start.x
    v1y := p1_end.y - p1_start.y
    v2x := p2_end.x - p2_start.x
    v2y := p2_end.y - p2_start.y

    // One equation: 2D cross product = 0 (v1.x*v2.y - v1.y*v2.x = 0)
    append(residuals, v1x*v2y - v1y*v2x)
}

// Angle constraint residuals: angle between two lines = theta
residuals_angle :: proc(sketch: ^Sketch2D, data: AngleData, residuals: ^[dynamic]f64) {
    // Get both line entities
    if data.line1_id < 0 || data.line1_id >= len(sketch.entities) do return
    if data.line2_id < 0 || data.line2_id >= len(sketch.entities) do return

    entity1 := sketch.entities[data.line1_id]
    entity2 := sketch.entities[data.line2_id]

    line1, ok1 := entity1.(SketchLine)
    line2, ok2 := entity2.(SketchLine)
    if !ok1 || !ok2 do return

    // Get line direction vectors
    p1_start := sketch_get_point(sketch, line1.start_id)
    p1_end := sketch_get_point(sketch, line1.end_id)
    p2_start := sketch_get_point(sketch, line2.start_id)
    p2_end := sketch_get_point(sketch, line2.end_id)

    if p1_start == nil || p1_end == nil || p2_start == nil || p2_end == nil do return

    v1x := p1_end.x - p1_start.x
    v1y := p1_end.y - p1_start.y
    v2x := p2_end.x - p2_start.x
    v2y := p2_end.y - p2_start.y

    // Normalize vectors
    len1 := math.sqrt(v1x*v1x + v1y*v1y)
    len2 := math.sqrt(v2x*v2x + v2y*v2y)

    if len1 < 1e-10 || len2 < 1e-10 do return  // Degenerate line

    v1x /= len1
    v1y /= len1
    v2x /= len2
    v2y /= len2

    // Compute current angle using atan2 for full range
    dot := v1x*v2x + v1y*v2y
    cross := v1x*v2y - v1y*v2x
    current_angle := math.atan2(cross, dot)

    // One equation: current_angle - target_angle = 0
    append(residuals, current_angle - data.angle)
}

// Equal constraint residuals: equal length (lines) or equal radius (circles)
residuals_equal :: proc(sketch: ^Sketch2D, data: EqualData, residuals: ^[dynamic]f64) {
    // Get both entities
    if data.entity1_id < 0 || data.entity1_id >= len(sketch.entities) do return
    if data.entity2_id < 0 || data.entity2_id >= len(sketch.entities) do return

    entity1 := sketch.entities[data.entity1_id]
    entity2 := sketch.entities[data.entity2_id]

    // Handle line-line equality (equal length)
    line1, ok1 := entity1.(SketchLine)
    line2, ok2 := entity2.(SketchLine)

    if ok1 && ok2 {
        // Both are lines - equal length constraint
        p1_start := sketch_get_point(sketch, line1.start_id)
        p1_end := sketch_get_point(sketch, line1.end_id)
        p2_start := sketch_get_point(sketch, line2.start_id)
        p2_end := sketch_get_point(sketch, line2.end_id)

        if p1_start == nil || p1_end == nil || p2_start == nil || p2_end == nil do return

        dx1 := p1_end.x - p1_start.x
        dy1 := p1_end.y - p1_start.y
        len1 := math.sqrt(dx1*dx1 + dy1*dy1)

        dx2 := p2_end.x - p2_start.x
        dy2 := p2_end.y - p2_start.y
        len2 := math.sqrt(dx2*dx2 + dy2*dy2)

        // One equation: len1 - len2 = 0
        append(residuals, len1 - len2)
        return
    }

    // Handle circle-circle equality (equal radius)
    circle1, ok1_c := entity1.(SketchCircle)
    circle2, ok2_c := entity2.(SketchCircle)

    if ok1_c && ok2_c {
        // Both are circles - equal radius constraint
        // One equation: r1 - r2 = 0
        append(residuals, circle1.radius - circle2.radius)
        return
    }
}

// PointOnLine constraint residuals: point must lie on line
residuals_point_on_line :: proc(sketch: ^Sketch2D, data: PointOnLineData, residuals: ^[dynamic]f64) {
    // Get point
    point := sketch_get_point(sketch, data.point_id)
    if point == nil do return

    // Get line entity
    if data.line_id < 0 || data.line_id >= len(sketch.entities) do return

    entity := sketch.entities[data.line_id]
    line, ok := entity.(SketchLine)
    if !ok do return

    p_start := sketch_get_point(sketch, line.start_id)
    p_end := sketch_get_point(sketch, line.end_id)

    if p_start == nil || p_end == nil do return

    // Vector from line start to point
    px := point.x - p_start.x
    py := point.y - p_start.y

    // Line direction vector
    lx := p_end.x - p_start.x
    ly := p_end.y - p_start.y

    // Distance from point to line (using cross product)
    // dist = |cross(p-start, direction)| / |direction|
    cross := px*ly - py*lx
    len_sq := lx*lx + ly*ly

    if len_sq < 1e-10 do return  // Degenerate line

    dist := cross / math.sqrt(len_sq)

    // One equation: distance = 0
    append(residuals, dist)
}

// PointOnCircle constraint residuals: point must lie on circle
residuals_point_on_circle :: proc(sketch: ^Sketch2D, data: PointOnCircleData, residuals: ^[dynamic]f64) {
    // Get point
    point := sketch_get_point(sketch, data.point_id)
    if point == nil do return

    // Get circle entity
    if data.circle_id < 0 || data.circle_id >= len(sketch.entities) do return

    entity := sketch.entities[data.circle_id]
    circle, ok := entity.(SketchCircle)
    if !ok do return

    center := sketch_get_point(sketch, circle.center_id)
    if center == nil do return

    // Distance from point to center
    dx := point.x - center.x
    dy := point.y - center.y
    dist := math.sqrt(dx*dx + dy*dy)

    // One equation: dist - radius = 0
    append(residuals, dist - circle.radius)
}

// Print constraint information
constraint_print_info :: proc(c: ^Constraint) {
    fmt.printf("Constraint %d: %v", c.id, c.type)
    if !c.enabled {
        fmt.print(" (DISABLED)")
    }
    fmt.println()
}

// Print DOF information
dof_print_info :: proc(info: DOFInfo) {
    fmt.printf("DOF Analysis:\n")
    fmt.printf("  Variables: %d\n", info.total_variables)
    fmt.printf("  Constraints: %d\n", info.num_constraints)
    fmt.printf("  DOF: %d\n", info.dof)
    fmt.printf("  Status: %v\n", info.status)
}
