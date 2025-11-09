// tests/math - Unit tests for CAD math utilities
package test_math

import "core:testing"
import "core:math"
import m "../../src/core/math"
import glsl "core:math/linalg/glsl"

@(test)
test_is_near_f64 :: proc(t: ^testing.T) {
    testing.expect(t, m.is_near(1.0, 1.0 + 1e-10), "Should be near with default tolerance")
    testing.expect(t, !m.is_near(1.0, 1.0 + 1e-5), "Should not be near with default tolerance")
    testing.expect(t, m.is_near(1.0, 1.0 + 1e-5, 1e-4), "Should be near with custom tolerance")
}

@(test)
test_is_near_vec3 :: proc(t: ^testing.T) {
    a := m.Vec3{1.0, 2.0, 3.0}
    b := m.Vec3{1.0 + 1e-10, 2.0, 3.0}
    c := m.Vec3{1.1, 2.0, 3.0}

    testing.expect(t, m.is_near(a, b), "Vectors should be near")
    testing.expect(t, !m.is_near(a, c), "Vectors should not be near")
}

@(test)
test_is_zero_f64 :: proc(t: ^testing.T) {
    testing.expect(t, m.is_zero(0.0), "Zero should be zero")
    testing.expect(t, m.is_zero(1e-10), "Small value should be zero with default tolerance")
    testing.expect(t, !m.is_zero(1e-5), "Larger value should not be zero")
}

@(test)
test_is_zero_vec3 :: proc(t: ^testing.T) {
    zero := m.Vec3{0, 0, 0}
    tiny := m.Vec3{1e-10, 1e-10, 1e-10}
    small := m.Vec3{1e-5, 0, 0}

    testing.expect(t, m.is_zero(zero), "Zero vector should be zero")
    testing.expect(t, m.is_zero(tiny), "Tiny vector should be zero")
    testing.expect(t, !m.is_zero(small), "Small vector should not be zero")
}

@(test)
test_safe_normalize :: proc(t: ^testing.T) {
    // Normal case
    v1 := m.Vec3{3, 4, 0}
    n1, ok1 := m.safe_normalize(v1)
    testing.expect(t, ok1, "Should normalize non-zero vector")
    testing.expect(t, m.is_near(glsl.length(n1), 1.0), "Normalized vector should have length 1")

    // Zero vector case
    v2 := m.Vec3{0, 0, 0}
    _, ok2 := m.safe_normalize(v2)
    testing.expect(t, !ok2, "Should fail to normalize zero vector")

    // Tiny vector case
    v3 := m.Vec3{1e-10, 1e-10, 1e-10}
    _, ok3 := m.safe_normalize(v3)
    testing.expect(t, !ok3, "Should fail to normalize tiny vector")
}

@(test)
test_tolerance_struct :: proc(t: ^testing.T) {
    tol := m.default_tolerance()
    testing.expect(t, tol.linear == m.DEFAULT_TOLERANCE, "Default linear tolerance should be set")
    testing.expect(t, tol.angular > 0, "Angular tolerance should be positive")
}

// =============================================================================
// Plane Operations Tests
// =============================================================================

@(test)
test_project_point_on_plane :: proc(t: ^testing.T) {
    // Horizontal plane at z=0
    plane_origin := m.Vec3{0, 0, 0}
    plane_normal := m.Vec3{0, 0, 1}

    // Point above the plane
    point := m.Vec3{5, 3, 10}
    projected := m.project_point_on_plane(point, plane_origin, plane_normal)

    testing.expect(t, m.is_near(projected.z, 0.0), "Projected point should be on plane (z=0)")
    testing.expect(t, m.is_near(projected.x, point.x), "X coordinate should be preserved")
    testing.expect(t, m.is_near(projected.y, point.y), "Y coordinate should be preserved")
}

@(test)
test_plane_from_three_points :: proc(t: ^testing.T) {
    // Three points forming a horizontal plane
    p0 := m.Vec3{0, 0, 0}
    p1 := m.Vec3{1, 0, 0}
    p2 := m.Vec3{0, 1, 0}

    origin, normal, ok := m.plane_from_three_points(p0, p1, p2)

    testing.expect(t, ok, "Should successfully create plane from non-collinear points")
    testing.expect(t, m.is_near(glsl.length(normal), 1.0), "Normal should be unit length")
    testing.expect(t, m.is_near(normal.z, 1.0) || m.is_near(normal.z, -1.0), "Normal should point along Z axis")

    // Test collinear points (should fail)
    p3 := m.Vec3{2, 0, 0}
    _, _, ok2 := m.plane_from_three_points(p0, p1, p3)
    testing.expect(t, !ok2, "Should fail for collinear points")
}

@(test)
test_plane_from_point_normal :: proc(t: ^testing.T) {
    origin := m.Vec3{1, 2, 3}
    normal := m.Vec3{0, 0, 5}  // Non-normalized

    result_origin, result_normal, ok := m.plane_from_point_normal(origin, normal)

    testing.expect(t, ok, "Should create plane successfully")
    testing.expect(t, m.is_near(result_origin, origin), "Origin should match")
    testing.expect(t, m.is_near(glsl.length(result_normal), 1.0), "Normal should be normalized")
}

@(test)
test_signed_distance_to_plane :: proc(t: ^testing.T) {
    plane_origin := m.Vec3{0, 0, 0}
    plane_normal := m.Vec3{0, 0, 1}

    point_above := m.Vec3{0, 0, 5}
    point_below := m.Vec3{0, 0, -3}
    point_on := m.Vec3{1, 2, 0}

    dist_above := m.signed_distance_to_plane(point_above, plane_origin, plane_normal)
    dist_below := m.signed_distance_to_plane(point_below, plane_origin, plane_normal)
    dist_on := m.signed_distance_to_plane(point_on, plane_origin, plane_normal)

    testing.expect(t, m.is_near(dist_above, 5.0), "Distance above should be +5")
    testing.expect(t, m.is_near(dist_below, -3.0), "Distance below should be -3")
    testing.expect(t, m.is_zero(dist_on), "Distance on plane should be 0")
}

@(test)
test_point_on_plane :: proc(t: ^testing.T) {
    plane_origin := m.Vec3{0, 0, 0}
    plane_normal := m.Vec3{0, 1, 0}

    point_on := m.Vec3{5, 0, 3}
    point_off := m.Vec3{0, 0.1, 0}

    testing.expect(t, m.point_on_plane(point_on, plane_origin, plane_normal), "Point should be on plane")
    testing.expect(t, !m.point_on_plane(point_off, plane_origin, plane_normal), "Point should not be on plane")
}

// =============================================================================
// 2D Line Intersection Tests
// =============================================================================

@(test)
test_line_line_intersect_2d :: proc(t: ^testing.T) {
    // Intersecting lines
    a0 := m.Vec2{0, 0}
    a1 := m.Vec2{2, 2}
    b0 := m.Vec2{0, 2}
    b1 := m.Vec2{2, 0}

    intersection, ok := m.line_line_intersect_2d(a0, a1, b0, b1)

    testing.expect(t, ok, "Lines should intersect")
    testing.expect(t, m.is_near(intersection, m.Vec2{1, 1}), "Intersection should be at (1, 1)")

    // Parallel lines (should fail)
    c0 := m.Vec2{0, 0}
    c1 := m.Vec2{1, 1}
    d0 := m.Vec2{0, 1}
    d1 := m.Vec2{1, 2}

    _, ok2 := m.line_line_intersect_2d(c0, c1, d0, d1)
    testing.expect(t, !ok2, "Parallel lines should not intersect")
}

@(test)
test_segment_segment_intersect_2d :: proc(t: ^testing.T) {
    // Intersecting segments
    a0 := m.Vec2{0, 0}
    a1 := m.Vec2{2, 2}
    b0 := m.Vec2{0, 2}
    b1 := m.Vec2{2, 0}

    intersection, ok := m.segment_segment_intersect_2d(a0, a1, b0, b1)

    testing.expect(t, ok, "Segments should intersect")
    testing.expect(t, m.is_near(intersection, m.Vec2{1, 1}), "Intersection should be at (1, 1)")

    // Non-intersecting segments (lines would intersect but not segments)
    c0 := m.Vec2{0, 0}
    c1 := m.Vec2{1, 1}
    d0 := m.Vec2{2, 0}
    d1 := m.Vec2{3, 1}

    _, ok2 := m.segment_segment_intersect_2d(c0, c1, d0, d1)
    testing.expect(t, !ok2, "Segments should not intersect (only extended lines would)")
}

// =============================================================================
// 3D Line Operations Tests
// =============================================================================

@(test)
test_closest_point_on_line :: proc(t: ^testing.T) {
    line_origin := m.Vec3{0, 0, 0}
    line_dir := m.Vec3{1, 0, 0}  // Along X axis

    point := m.Vec3{5, 3, 2}
    closest := m.closest_point_on_line(point, line_origin, line_dir)

    testing.expect(t, m.is_near(closest, m.Vec3{5, 0, 0}), "Closest point should be (5, 0, 0)")
}

@(test)
test_closest_point_on_segment :: proc(t: ^testing.T) {
    seg_start := m.Vec3{0, 0, 0}
    seg_end := m.Vec3{10, 0, 0}

    // Point projects onto segment
    point1 := m.Vec3{5, 5, 0}
    closest1, t1 := m.closest_point_on_segment(point1, seg_start, seg_end)
    testing.expect(t, m.is_near(closest1, m.Vec3{5, 0, 0}), "Closest should be (5, 0, 0)")
    testing.expect(t, t1 >= 0.0 && t1 <= 1.0, "Parameter should be within [0, 1]")

    // Point projects before segment start
    point2 := m.Vec3{-5, 0, 0}
    closest2, t2 := m.closest_point_on_segment(point2, seg_start, seg_end)
    testing.expect(t, m.is_near(closest2, seg_start), "Closest should be segment start")
    testing.expect(t, m.is_near(t2, 0.0), "Parameter should be 0")

    // Point projects after segment end
    point3 := m.Vec3{15, 0, 0}
    closest3, t3 := m.closest_point_on_segment(point3, seg_start, seg_end)
    testing.expect(t, m.is_near(closest3, seg_end), "Closest should be segment end")
    testing.expect(t, m.is_near(t3, 1.0), "Parameter should be 1")
}

@(test)
test_distance_point_to_segment :: proc(t: ^testing.T) {
    seg_start := m.Vec3{0, 0, 0}
    seg_end := m.Vec3{10, 0, 0}
    point := m.Vec3{5, 3, 4}

    dist := m.distance_point_to_segment(point, seg_start, seg_end)
    expected_dist := glsl.length(m.Vec3{0, 3, 4})  // Distance to (5, 0, 0)

    testing.expect(t, m.is_near(dist, expected_dist), "Distance should match expected")
}

@(test)
test_closest_approach_lines :: proc(t: ^testing.T) {
    // Skew lines (non-intersecting, non-parallel)
    a_origin := m.Vec3{0, 0, 0}
    a_dir := m.Vec3{1, 0, 0}  // Along X

    b_origin := m.Vec3{5, 5, 5}
    b_dir := m.Vec3{0, 1, 0}  // Along Y

    point_a, point_b, dist := m.closest_approach_lines(a_origin, a_dir, b_origin, b_dir)

    testing.expect(t, m.is_near(point_a, m.Vec3{5, 0, 0}), "Closest point on line A")
    testing.expect(t, m.is_near(point_b, m.Vec3{5, 0, 5}), "Closest point on line B should be (5, 0, 5)")
    expected_dist := glsl.length(m.Vec3{0, 0, 5})  // Distance between (5,0,0) and (5,0,5)
    testing.expect(t, m.is_near(dist, expected_dist), "Distance should be 5")

    // Parallel lines
    c_origin := m.Vec3{0, 0, 0}
    c_dir := m.Vec3{1, 0, 0}
    d_origin := m.Vec3{0, 1, 0}
    d_dir := m.Vec3{1, 0, 0}

    _, _, dist2 := m.closest_approach_lines(c_origin, c_dir, d_origin, d_dir)
    testing.expect(t, m.is_near(dist2, 1.0), "Distance between parallel lines")
}

// =============================================================================
// Plane-Plane Intersection Tests
// =============================================================================

@(test)
test_plane_plane_intersect :: proc(t: ^testing.T) {
    // Two perpendicular planes
    // Plane 1: XY plane (z=0)
    p1_origin := m.Vec3{0, 0, 0}
    p1_normal := m.Vec3{0, 0, 1}

    // Plane 2: YZ plane (x=0)
    p2_origin := m.Vec3{0, 0, 0}
    p2_normal := m.Vec3{1, 0, 0}

    line_origin, line_dir, ok := m.plane_plane_intersect(p1_origin, p1_normal, p2_origin, p2_normal)

    testing.expect(t, ok, "Planes should intersect")
    testing.expect(t, m.is_near(glsl.length(line_dir), 1.0), "Direction should be normalized")

    // Intersection line should be along Y axis
    testing.expect(t, m.is_near(math.abs(line_dir.y), 1.0), "Direction should be along Y axis")

    // Check that line_origin is on both planes
    testing.expect(t, m.point_on_plane(line_origin, p1_origin, p1_normal), "Origin should be on plane 1")
    testing.expect(t, m.point_on_plane(line_origin, p2_origin, p2_normal), "Origin should be on plane 2")

    // Parallel planes (should fail)
    p3_origin := m.Vec3{0, 0, 1}
    p3_normal := m.Vec3{0, 0, 1}

    _, _, ok2 := m.plane_plane_intersect(p1_origin, p1_normal, p3_origin, p3_normal)
    testing.expect(t, !ok2, "Parallel planes should not intersect")
}

// =============================================================================
// 2D Polygon Operations Tests
// =============================================================================

@(test)
test_point_in_polygon_2d :: proc(t: ^testing.T) {
    // Square polygon
    square := []m.Vec2{
        {0, 0},
        {10, 0},
        {10, 10},
        {0, 10},
    }

    // Points inside
    inside1 := m.Vec2{5, 5}
    inside2 := m.Vec2{1, 1}

    testing.expect(t, m.point_in_polygon_2d(inside1, square), "Center point should be inside")
    testing.expect(t, m.point_in_polygon_2d(inside2, square), "Corner-near point should be inside")

    // Points outside
    outside1 := m.Vec2{-1, 5}
    outside2 := m.Vec2{15, 5}
    outside3 := m.Vec2{5, 15}

    testing.expect(t, !m.point_in_polygon_2d(outside1, square), "Point to the left should be outside")
    testing.expect(t, !m.point_in_polygon_2d(outside2, square), "Point to the right should be outside")
    testing.expect(t, !m.point_in_polygon_2d(outside3, square), "Point above should be outside")
}

@(test)
test_polygon_signed_area_2d :: proc(t: ^testing.T) {
    // CCW square (area should be positive)
    ccw_square := []m.Vec2{
        {0, 0},
        {10, 0},
        {10, 10},
        {0, 10},
    }

    area_ccw := m.polygon_signed_area_2d(ccw_square)
    testing.expect(t, m.is_near(area_ccw, 100.0), "CCW square area should be +100")

    // CW square (area should be negative)
    cw_square := []m.Vec2{
        {0, 0},
        {0, 10},
        {10, 10},
        {10, 0},
    }

    area_cw := m.polygon_signed_area_2d(cw_square)
    testing.expect(t, m.is_near(area_cw, -100.0), "CW square area should be -100")
}

@(test)
test_is_polygon_ccw :: proc(t: ^testing.T) {
    // CCW square
    ccw_square := []m.Vec2{
        {0, 0},
        {10, 0},
        {10, 10},
        {0, 10},
    }

    testing.expect(t, m.is_polygon_ccw(ccw_square), "CCW square should be detected as CCW")

    // CW square
    cw_square := []m.Vec2{
        {0, 0},
        {0, 10},
        {10, 10},
        {10, 0},
    }

    testing.expect(t, !m.is_polygon_ccw(cw_square), "CW square should not be detected as CCW")
}
