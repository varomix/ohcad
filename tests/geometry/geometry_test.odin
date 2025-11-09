// tests/geometry - Unit tests for geometry primitives and evaluation functions
package test_geometry

import "core:testing"
import "core:math"
import g "../../src/core/geometry"
import m "../../src/core/math"
import glsl "core:math/linalg/glsl"

// =============================================================================
// 2D Line Tests
// =============================================================================

@(test)
test_point_on_line_2d :: proc(t: ^testing.T) {
    line := g.Line2{p0 = {0, 0}, p1 = {10, 10}}

    // Test at various parameters
    p0 := g.point_on_line_2d(line, 0.0)
    p_mid := g.point_on_line_2d(line, 0.5)
    p1 := g.point_on_line_2d(line, 1.0)

    testing.expect(t, m.is_near(p0, line.p0), "t=0 should give p0")
    testing.expect(t, m.is_near(p_mid, m.Vec2{5, 5}), "t=0.5 should give midpoint")
    testing.expect(t, m.is_near(p1, line.p1), "t=1 should give p1")
}

@(test)
test_line_direction_and_length_2d :: proc(t: ^testing.T) {
    line := g.Line2{p0 = {0, 0}, p1 = {3, 4}}

    dir := g.line_direction_2d(line)
    length := g.line_length_2d(line)

    testing.expect(t, m.is_near(dir, m.Vec2{3, 4}), "Direction should match")
    testing.expect(t, m.is_near(length, 5.0), "Length should be 5 (3-4-5 triangle)")
}

@(test)
test_closest_point_on_line_2d :: proc(t: ^testing.T) {
    line := g.Line2{p0 = {0, 0}, p1 = {10, 0}}

    // Point above line
    point := m.Vec2{5, 3}
    closest, t_param := g.closest_point_on_line_2d(point, line)

    testing.expect(t, m.is_near(closest, m.Vec2{5, 0}), "Closest should be (5, 0)")
    testing.expect(t, m.is_near(t_param, 0.5), "Parameter should be 0.5")

    // Point off the line segment
    point2 := m.Vec2{15, 0}
    closest2, t_param2 := g.closest_point_on_line_2d(point2, line)

    testing.expect(t, m.is_near(closest2, m.Vec2{15, 0}), "Closest should be (15, 0)")
    testing.expect(t, m.is_near(t_param2, 1.5), "Parameter should be 1.5")
}

@(test)
test_distance_point_to_line_2d :: proc(t: ^testing.T) {
    line := g.Line2{p0 = {0, 0}, p1 = {10, 0}}

    point := m.Vec2{5, 3}
    dist := g.distance_point_to_line_2d(point, line)

    testing.expect(t, m.is_near(dist, 3.0), "Distance should be 3")
}

@(test)
test_distance_point_to_segment_2d :: proc(t: ^testing.T) {
    line := g.Line2{p0 = {0, 0}, p1 = {10, 0}}

    // Point projects onto segment
    point1 := m.Vec2{5, 3}
    dist1 := g.distance_point_to_segment_2d(point1, line)
    testing.expect(t, m.is_near(dist1, 3.0), "Distance should be 3")

    // Point projects beyond segment
    point2 := m.Vec2{15, 0}
    dist2 := g.distance_point_to_segment_2d(point2, line)
    testing.expect(t, m.is_near(dist2, 5.0), "Distance should be 5")
}

// =============================================================================
// 2D Circle Tests
// =============================================================================

@(test)
test_point_on_circle_2d :: proc(t: ^testing.T) {
    circle := g.Circle2{center = {0, 0}, radius = 5.0}

    // Test at various angles
    p0 := g.point_on_circle_2d(circle, 0.0)
    p90 := g.point_on_circle_2d(circle, math.PI / 2.0)
    p180 := g.point_on_circle_2d(circle, math.PI)

    testing.expect(t, m.is_near(p0, m.Vec2{5, 0}), "Angle 0 should give (5, 0)")
    testing.expect(t, m.is_near(p90, m.Vec2{0, 5}), "Angle π/2 should give (0, 5)")
    testing.expect(t, m.is_near(p180, m.Vec2{-5, 0}), "Angle π should give (-5, 0)")
}

@(test)
test_tangent_on_circle_2d :: proc(t: ^testing.T) {
    circle := g.Circle2{center = {0, 0}, radius = 5.0}

    tan0 := g.tangent_on_circle_2d(circle, 0.0)
    tan90 := g.tangent_on_circle_2d(circle, math.PI / 2.0)

    testing.expect(t, m.is_near(tan0, m.Vec2{0, 1}), "Tangent at 0 should be (0, 1)")
    testing.expect(t, m.is_near(tan90, m.Vec2{-1, 0}), "Tangent at π/2 should be (-1, 0)")
}

@(test)
test_closest_point_on_circle_2d :: proc(t: ^testing.T) {
    circle := g.Circle2{center = {0, 0}, radius = 5.0}

    // Point outside circle
    point := m.Vec2{10, 0}
    closest, angle := g.closest_point_on_circle_2d(point, circle)

    testing.expect(t, m.is_near(closest, m.Vec2{5, 0}), "Closest should be (5, 0)")
    testing.expect(t, m.is_near(angle, 0.0), "Angle should be 0")
}

@(test)
test_distance_to_circle_2d :: proc(t: ^testing.T) {
    circle := g.Circle2{center = {0, 0}, radius = 5.0}

    // Point outside
    point_outside := m.Vec2{10, 0}
    dist_outside := g.distance_to_circle_2d(point_outside, circle)
    testing.expect(t, m.is_near(dist_outside, 5.0), "Distance should be 5")

    // Point inside
    point_inside := m.Vec2{2, 0}
    dist_inside := g.distance_to_circle_2d(point_inside, circle)
    testing.expect(t, m.is_near(dist_inside, 3.0), "Distance should be 3")

    // Point on circle
    point_on := m.Vec2{5, 0}
    dist_on := g.distance_to_circle_2d(point_on, circle)
    testing.expect(t, m.is_zero(dist_on), "Distance should be 0")
}

// =============================================================================
// 2D Arc Tests
// =============================================================================

@(test)
test_point_on_arc_2d :: proc(t: ^testing.T) {
    arc := g.Arc2{
        center = {0, 0},
        radius = 5.0,
        start_angle = 0.0,
        end_angle = math.PI / 2.0,
    }

    p_start := g.point_on_arc_2d(arc, 0.0)
    p_mid := g.point_on_arc_2d(arc, 0.5)
    p_end := g.point_on_arc_2d(arc, 1.0)

    testing.expect(t, m.is_near(p_start, m.Vec2{5, 0}), "Start should be (5, 0)")
    testing.expect(t, m.is_near(p_end, m.Vec2{0, 5}), "End should be (0, 5)")

    // Mid should be at 45 degrees
    expected_mid := m.Vec2{5.0 * math.cos(f64(math.PI / 4.0)), 5.0 * math.sin(f64(math.PI / 4.0))}
    testing.expect(t, m.is_near(p_mid, expected_mid), "Mid should be at 45 degrees")
}

@(test)
test_arc_length_2d :: proc(t: ^testing.T) {
    // Quarter circle
    arc := g.Arc2{
        center = {0, 0},
        radius = 10.0,
        start_angle = 0.0,
        end_angle = math.PI / 2.0,
    }

    length := g.arc_length_2d(arc)
    expected := 10.0 * (math.PI / 2.0)  // radius * angle

    testing.expect(t, m.is_near(length, expected), "Arc length should be radius * angle")
}

@(test)
test_arc_angle_span :: proc(t: ^testing.T) {
    arc1 := g.Arc2{start_angle = 0.0, end_angle = math.PI / 2.0}
    span1 := g.arc_angle_span(arc1)
    testing.expect(t, m.is_near(span1, math.PI / 2.0), "Span should be π/2")

    // Wraparound arc
    arc2 := g.Arc2{start_angle = 3.0 * math.PI / 2.0, end_angle = math.PI / 2.0}
    span2 := g.arc_angle_span(arc2)
    testing.expect(t, span2 > 0 && span2 <= math.TAU, "Span should be positive and <= 2π")
}

// =============================================================================
// 3D Sphere Tests
// =============================================================================

@(test)
test_point_on_sphere :: proc(t: ^testing.T) {
    sphere := g.Sphere{center = {0, 0, 0}, radius = 10.0}

    // North pole (phi = 0)
    p_north := g.point_on_sphere(sphere, 0.0, 0.0)
    testing.expect(t, m.is_near(p_north, m.Vec3{0, 0, 10}), "North pole should be (0, 0, 10)")

    // South pole (phi = π)
    p_south := g.point_on_sphere(sphere, 0.0, math.PI)
    testing.expect(t, m.is_near(p_south, m.Vec3{0, 0, -10}), "South pole should be (0, 0, -10)")

    // Equator at theta = 0, phi = π/2
    p_equator := g.point_on_sphere(sphere, 0.0, math.PI / 2.0)
    testing.expect(t, m.is_near(p_equator, m.Vec3{10, 0, 0}), "Equator point should be (10, 0, 0)")
}

@(test)
test_closest_point_on_sphere :: proc(t: ^testing.T) {
    sphere := g.Sphere{center = {0, 0, 0}, radius = 5.0}

    point := m.Vec3{10, 0, 0}
    closest := g.closest_point_on_sphere(point, sphere)

    testing.expect(t, m.is_near(closest, m.Vec3{5, 0, 0}), "Closest should be (5, 0, 0)")
    testing.expect(t, m.is_near(glsl.length(closest), 5.0), "Closest should be on sphere surface")
}

@(test)
test_distance_to_sphere :: proc(t: ^testing.T) {
    sphere := g.Sphere{center = {0, 0, 0}, radius = 5.0}

    // Point outside
    point_outside := m.Vec3{10, 0, 0}
    dist_outside := g.distance_to_sphere(point_outside, sphere)
    testing.expect(t, m.is_near(dist_outside, 5.0), "Distance should be 5")

    // Point inside
    point_inside := m.Vec3{2, 0, 0}
    dist_inside := g.distance_to_sphere(point_inside, sphere)
    testing.expect(t, m.is_near(dist_inside, 3.0), "Distance should be 3")
}

// =============================================================================
// 3D Cylinder Tests
// =============================================================================

@(test)
test_point_on_cylinder :: proc(t: ^testing.T) {
    cylinder := g.Cylinder{
        axis_origin = {0, 0, 0},
        axis_dir = {0, 0, 1},
        radius = 5.0,
    }

    // Point at theta=0, z=0
    p := g.point_on_cylinder(cylinder, 0.0, 0.0)

    // Should be on XY circle at z=0
    testing.expect(t, m.is_near(p.z, 0.0), "Z should be 0")
    testing.expect(t, m.is_near(glsl.length(m.Vec2{p.x, p.y}), 5.0), "Should be on circle of radius 5")
}

@(test)
test_closest_point_on_cylinder :: proc(t: ^testing.T) {
    cylinder := g.Cylinder{
        axis_origin = {0, 0, 0},
        axis_dir = {0, 0, 1},
        radius = 5.0,
    }

    point := m.Vec3{10, 0, 5}
    closest := g.closest_point_on_cylinder(point, cylinder)

    // Closest should be at same z, on circle
    testing.expect(t, m.is_near(closest.z, 5.0), "Z should match point")
    testing.expect(t, m.is_near(glsl.length(m.Vec2{closest.x, closest.y}), 5.0), "Should be on cylinder surface")
}

@(test)
test_distance_to_cylinder :: proc(t: ^testing.T) {
    cylinder := g.Cylinder{
        axis_origin = {0, 0, 0},
        axis_dir = {0, 0, 1},
        radius = 5.0,
    }

    // Point outside cylinder
    point_outside := m.Vec3{10, 0, 0}
    dist := g.distance_to_cylinder(point_outside, cylinder)

    testing.expect(t, m.is_near(dist, 5.0), "Distance should be 5")
}
