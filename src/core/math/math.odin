// core/math - CAD-specific mathematical utilities
// This module provides CAD-specific geometric operations and tolerance management
// It builds upon Odin's core:math/linalg/glsl package

package ohcad_math

import glsl "core:math/linalg/glsl"
import "core:math"

// Type aliases for double precision (CAD requires high precision)
Vec2 :: glsl.dvec2
Vec3 :: glsl.dvec3
Vec4 :: glsl.dvec4
Mat3 :: glsl.dmat3
Mat4 :: glsl.dmat4
Quat :: glsl.dquat

// CAD-specific constants
DEFAULT_TOLERANCE :: 1e-9
MIN_TOLERANCE :: 1e-12
MAX_TOLERANCE :: 1e-6

// Tolerance for CAD operations (configurable per model)
Tolerance :: struct {
    linear: f64,  // For distance comparisons
    angular: f64, // For angle comparisons (radians)
}

// Default tolerance settings
default_tolerance :: proc() -> Tolerance {
    return Tolerance{
        linear = DEFAULT_TOLERANCE,
        angular = 1e-6, // ~0.0000573 degrees
    }
}

// Robust floating-point comparison with tolerance
is_near :: proc{is_near_f64, is_near_vec2, is_near_vec3}

is_near_f64 :: proc(a, b: f64, eps: f64 = DEFAULT_TOLERANCE) -> bool {
    return math.abs(a - b) <= eps
}

is_near_vec2 :: proc(a, b: Vec2, eps: f64 = DEFAULT_TOLERANCE) -> bool {
    return glsl.length(a - b) <= eps
}

is_near_vec3 :: proc(a, b: Vec3, eps: f64 = DEFAULT_TOLERANCE) -> bool {
    return glsl.length(a - b) <= eps
}

// Check if a value is effectively zero
is_zero :: proc{is_zero_f64, is_zero_vec2, is_zero_vec3}

is_zero_f64 :: proc(val: f64, eps: f64 = DEFAULT_TOLERANCE) -> bool {
    return math.abs(val) <= eps
}

is_zero_vec2 :: proc(v: Vec2, eps: f64 = DEFAULT_TOLERANCE) -> bool {
    return glsl.length(v) <= eps
}

is_zero_vec3 :: proc(v: Vec3, eps: f64 = DEFAULT_TOLERANCE) -> bool {
    return glsl.length(v) <= eps
}

// Safe normalize that handles zero-length vectors
safe_normalize :: proc{safe_normalize_vec2, safe_normalize_vec3}

safe_normalize_vec2 :: proc(v: Vec2, eps: f64 = DEFAULT_TOLERANCE) -> (Vec2, bool) {
    len := glsl.length(v)
    if len <= eps {
        return Vec2{}, false
    }
    return v / len, true
}

safe_normalize_vec3 :: proc(v: Vec3, eps: f64 = DEFAULT_TOLERANCE) -> (Vec3, bool) {
    len := glsl.length(v)
    if len <= eps {
        return Vec3{}, false
    }
    return v / len, true
}

// =============================================================================
// Geometric Predicates and Utilities
// =============================================================================

// Project a 3D point onto a plane
// Returns the closest point on the plane to the given point
project_point_on_plane :: proc(point: Vec3, plane_origin: Vec3, plane_normal: Vec3) -> Vec3 {
    // Distance from point to plane (signed)
    dist := glsl.dot(point - plane_origin, plane_normal)
    // Project along normal
    return point - plane_normal * dist
}

// Construct a plane from three points
// Returns (origin, normal, success)
plane_from_three_points :: proc(p0, p1, p2: Vec3, eps: f64 = DEFAULT_TOLERANCE) -> (Vec3, Vec3, bool) {
    v1 := p1 - p0
    v2 := p2 - p0

    normal := glsl.cross(v1, v2)
    normalized, ok := safe_normalize(normal, eps)

    if !ok {
        // Points are collinear
        return Vec3{}, Vec3{}, false
    }

    return p0, normalized, true
}

// Construct a plane from a point and a normal
// Normalizes the normal vector
plane_from_point_normal :: proc(origin: Vec3, normal: Vec3, eps: f64 = DEFAULT_TOLERANCE) -> (Vec3, Vec3, bool) {
    normalized, ok := safe_normalize(normal, eps)
    if !ok {
        return Vec3{}, Vec3{}, false
    }
    return origin, normalized, true
}

// Signed distance from a point to a plane
signed_distance_to_plane :: proc(point: Vec3, plane_origin: Vec3, plane_normal: Vec3) -> f64 {
    return glsl.dot(point - plane_origin, plane_normal)
}

// Absolute distance from a point to a plane
distance_to_plane :: proc(point: Vec3, plane_origin: Vec3, plane_normal: Vec3) -> f64 {
    return math.abs(signed_distance_to_plane(point, plane_origin, plane_normal))
}

// Check if a point lies on a plane (within tolerance)
point_on_plane :: proc(point: Vec3, plane_origin: Vec3, plane_normal: Vec3, eps: f64 = DEFAULT_TOLERANCE) -> bool {
    return is_zero(signed_distance_to_plane(point, plane_origin, plane_normal), eps)
}

// =============================================================================
// 2D Line Intersection
// =============================================================================

// Line-line intersection in 2D
// Returns (intersection_point, success)
// Uses parametric form: P = P0 + t * (P1 - P0)
line_line_intersect_2d :: proc(
    a0, a1: Vec2,  // Line A endpoints
    b0, b1: Vec2,  // Line B endpoints
    eps: f64 = DEFAULT_TOLERANCE,
) -> (Vec2, bool) {
    // Direction vectors
    da := a1 - a0
    db := b1 - b0

    // Vector from a0 to b0
    diff := b0 - a0

    // Solve: a0 + t*da = b0 + s*db
    // Using cross product in 2D: da.x * db.y - da.y * db.x
    cross_d := da.x * db.y - da.y * db.x

    if is_zero(cross_d, eps) {
        // Lines are parallel or coincident
        return Vec2{}, false
    }

    // Solve for parameter t on line A
    t := (diff.x * db.y - diff.y * db.x) / cross_d

    // Intersection point
    intersection := a0 + da * t

    return intersection, true
}

// Line segment intersection in 2D (checks if intersection is within segments)
// Returns (intersection_point, success)
segment_segment_intersect_2d :: proc(
    a0, a1: Vec2,
    b0, b1: Vec2,
    eps: f64 = DEFAULT_TOLERANCE,
) -> (Vec2, bool) {
    da := a1 - a0
    db := b1 - b0
    diff := b0 - a0

    cross_d := da.x * db.y - da.y * db.x

    if is_zero(cross_d, eps) {
        return Vec2{}, false
    }

    t := (diff.x * db.y - diff.y * db.x) / cross_d
    s := (diff.x * da.y - diff.y * da.x) / cross_d

    // Check if intersection is within both segments [0, 1]
    if t >= -eps && t <= 1.0 + eps && s >= -eps && s <= 1.0 + eps {
        return a0 + da * t, true
    }

    return Vec2{}, false
}

// =============================================================================
// 3D Line Operations
// =============================================================================

// Closest point on an infinite 3D line to a given point
// Line defined by origin and direction (must be normalized)
closest_point_on_line :: proc(point: Vec3, line_origin: Vec3, line_dir: Vec3) -> Vec3 {
    // Project point onto line
    v := point - line_origin
    t := glsl.dot(v, line_dir)
    return line_origin + line_dir * t
}

// Closest point on a 3D line segment to a given point
// Returns (closest_point, parameter_t)
// If t in [0,1], point is on segment; otherwise it's on extended line
closest_point_on_segment :: proc(point: Vec3, seg_start: Vec3, seg_end: Vec3) -> (Vec3, f64) {
    dir := seg_end - seg_start
    len_sq := glsl.dot(dir, dir)

    if is_zero(len_sq) {
        // Degenerate segment (point)
        return seg_start, 0.0
    }

    // Project point onto line
    v := point - seg_start
    t := glsl.dot(v, dir) / len_sq

    // Clamp to segment
    t_clamped := glsl.clamp(t, 0.0, 1.0)

    return seg_start + dir * t_clamped, t_clamped
}

// Distance from a point to a 3D line segment
distance_point_to_segment :: proc(point: Vec3, seg_start: Vec3, seg_end: Vec3) -> f64 {
    closest, _ := closest_point_on_segment(point, seg_start, seg_end)
    return glsl.length(point - closest)
}

// Closest approach between two 3D lines
// Returns (point_on_line_a, point_on_line_b, distance)
// Lines defined by origin and direction (directions must be normalized)
closest_approach_lines :: proc(
    a_origin, a_dir: Vec3,
    b_origin, b_dir: Vec3,
    eps: f64 = DEFAULT_TOLERANCE,
) -> (Vec3, Vec3, f64) {
    // Vector between line origins
    w := a_origin - b_origin

    a := glsl.dot(a_dir, a_dir)  // Should be 1 if normalized
    b := glsl.dot(a_dir, b_dir)
    c := glsl.dot(b_dir, b_dir)  // Should be 1 if normalized
    d := glsl.dot(a_dir, w)
    e := glsl.dot(b_dir, w)

    denom := a * c - b * b

    // Check if lines are parallel
    if is_zero(denom, eps) {
        // Lines are parallel - use arbitrary point on line A
        t_a := 0.0
        point_a := a_origin

        // Find closest point on line B to this point
        point_b := closest_point_on_line(point_a, b_origin, b_dir)

        dist := glsl.length(point_a - point_b)
        return point_a, point_b, dist
    }

    // Solve for parameters
    t_a := (b * e - c * d) / denom
    t_b := (a * e - b * d) / denom

    point_a := a_origin + a_dir * t_a
    point_b := b_origin + b_dir * t_b

    dist := glsl.length(point_a - point_b)

    return point_a, point_b, dist
}

// =============================================================================
// Plane-Plane Intersection
// =============================================================================

// Intersect two planes to get a line
// Returns (line_origin, line_direction, success)
plane_plane_intersect :: proc(
    p1_origin, p1_normal: Vec3,
    p2_origin, p2_normal: Vec3,
    eps: f64 = DEFAULT_TOLERANCE,
) -> (Vec3, Vec3, bool) {
    // Line direction is perpendicular to both normals
    line_dir := glsl.cross(p1_normal, p2_normal)

    normalized_dir, ok := safe_normalize(line_dir, eps)
    if !ok {
        // Planes are parallel
        return Vec3{}, Vec3{}, false
    }

    // Find a point on the intersection line
    // We need to solve for a point that satisfies both plane equations

    // Choose the coordinate with the largest component in line_dir
    // This gives us numerical stability
    abs_dir := Vec3{math.abs(normalized_dir.x), math.abs(normalized_dir.y), math.abs(normalized_dir.z)}

    // Find point by setting the coordinate with max line_dir component to 0
    // and solving the 2D system
    line_origin: Vec3

    if abs_dir.x >= abs_dir.y && abs_dir.x >= abs_dir.z {
        // X component is largest - set x = 0 and solve for y, z
        d1 := glsl.dot(p1_normal, p1_origin)
        d2 := glsl.dot(p2_normal, p2_origin)

        denom := p1_normal.y * p2_normal.z - p1_normal.z * p2_normal.y
        if is_zero(denom, eps) {
            return Vec3{}, Vec3{}, false
        }

        y := (d1 * p2_normal.z - d2 * p1_normal.z) / denom
        z := (d2 * p1_normal.y - d1 * p2_normal.y) / denom
        line_origin = Vec3{0, y, z}
    } else if abs_dir.y >= abs_dir.z {
        // Y component is largest
        d1 := glsl.dot(p1_normal, p1_origin)
        d2 := glsl.dot(p2_normal, p2_origin)

        denom := p1_normal.x * p2_normal.z - p1_normal.z * p2_normal.x
        if is_zero(denom, eps) {
            return Vec3{}, Vec3{}, false
        }

        x := (d1 * p2_normal.z - d2 * p1_normal.z) / denom
        z := (d2 * p1_normal.x - d1 * p2_normal.x) / denom
        line_origin = Vec3{x, 0, z}
    } else {
        // Z component is largest
        d1 := glsl.dot(p1_normal, p1_origin)
        d2 := glsl.dot(p2_normal, p2_origin)

        denom := p1_normal.x * p2_normal.y - p1_normal.y * p2_normal.x
        if is_zero(denom, eps) {
            return Vec3{}, Vec3{}, false
        }

        x := (d1 * p2_normal.y - d2 * p1_normal.y) / denom
        y := (d2 * p1_normal.x - d1 * p2_normal.x) / denom
        line_origin = Vec3{x, y, 0}
    }

    return line_origin, normalized_dir, true
}

// =============================================================================
// 2D Polygon Operations
// =============================================================================

// Check if a point is inside a 2D polygon using ray casting algorithm
// Polygon vertices should be ordered (clockwise or counter-clockwise)
point_in_polygon_2d :: proc(point: Vec2, polygon: []Vec2) -> bool {
    if len(polygon) < 3 {
        return false
    }

    // Ray casting algorithm - count intersections with edges
    intersections := 0

    for i in 0..<len(polygon) {
        v1 := polygon[i]
        v2 := polygon[(i + 1) % len(polygon)]

        // Check if ray from point going right intersects edge
        if (v1.y > point.y) != (v2.y > point.y) {
            // Edge crosses the horizontal line through point
            x_intersection := (v2.x - v1.x) * (point.y - v1.y) / (v2.y - v1.y) + v1.x

            if point.x < x_intersection {
                intersections += 1
            }
        }
    }

    // Odd number of intersections means inside
    return (intersections % 2) == 1
}

// Calculate the signed area of a 2D polygon
// Positive if counter-clockwise, negative if clockwise
polygon_signed_area_2d :: proc(polygon: []Vec2) -> f64 {
    if len(polygon) < 3 {
        return 0.0
    }

    area := 0.0
    for i in 0..<len(polygon) {
        v1 := polygon[i]
        v2 := polygon[(i + 1) % len(polygon)]
        area += v1.x * v2.y - v2.x * v1.y
    }

    return area * 0.5
}

// Check if a 2D polygon is counter-clockwise oriented
is_polygon_ccw :: proc(polygon: []Vec2) -> bool {
    return polygon_signed_area_2d(polygon) > 0.0
}
