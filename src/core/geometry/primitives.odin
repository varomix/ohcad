// core/geometry - 2D and 3D geometric primitives
// This module defines analytic geometry primitives and evaluation routines

package ohcad_geometry

import m "../../core/math"
import glsl "core:math/linalg/glsl"
import "core:math"

// 2D Primitives

Line2 :: struct {
    p0, p1: m.Vec2,
}

Circle2 :: struct {
    center: m.Vec2,
    radius: f64,
}

Arc2 :: struct {
    center: m.Vec2,
    radius: f64,
    start_angle: f64,  // radians
    end_angle: f64,    // radians
}

// 3D Primitives

Plane :: struct {
    origin: m.Vec3,
    normal: m.Vec3,  // Must be normalized
}

Sphere :: struct {
    center: m.Vec3,
    radius: f64,
}

Cylinder :: struct {
    axis_origin: m.Vec3,
    axis_dir: m.Vec3,  // Must be normalized
    radius: f64,
}

// Parametric curve (example - for later NURBS/Bezier)
Bezier3 :: struct {
    control_points: [4]m.Vec3,
}

// =============================================================================
// 2D Geometry Evaluation Functions
// =============================================================================

// Evaluate a point on a 2D line using parameter t in [0, 1]
point_on_line_2d :: proc(line: Line2, t: f64) -> m.Vec2 {
    return line.p0 + (line.p1 - line.p0) * t
}

// Get the direction vector of a 2D line (not normalized)
line_direction_2d :: proc(line: Line2) -> m.Vec2 {
    return line.p1 - line.p0
}

// Get the length of a 2D line
line_length_2d :: proc(line: Line2) -> f64 {
    return glsl.length(line.p1 - line.p0)
}

// Project a point onto a 2D line and return (closest_point, parameter_t)
closest_point_on_line_2d :: proc(point: m.Vec2, line: Line2) -> (m.Vec2, f64) {
    dir := line.p1 - line.p0
    len_sq := glsl.dot(dir, dir)

    if m.is_zero(len_sq) {
        // Degenerate line (point)
        return line.p0, 0.0
    }

    v := point - line.p0
    t := glsl.dot(v, dir) / len_sq

    return line.p0 + dir * t, t
}

// Distance from a point to a 2D line (infinite)
distance_point_to_line_2d :: proc(point: m.Vec2, line: Line2) -> f64 {
    closest, _ := closest_point_on_line_2d(point, line)
    return glsl.length(point - closest)
}

// Distance from a point to a 2D line segment (clamped to [0,1])
distance_point_to_segment_2d :: proc(point: m.Vec2, line: Line2) -> f64 {
    closest, t := closest_point_on_line_2d(point, line)
    t_clamped := glsl.clamp(t, 0.0, 1.0)
    closest_clamped := line.p0 + (line.p1 - line.p0) * t_clamped
    return glsl.length(point - closest_clamped)
}

// Evaluate a point on a 2D circle using angle (radians)
point_on_circle_2d :: proc(circle: Circle2, angle: f64) -> m.Vec2 {
    return m.Vec2{
        circle.center.x + circle.radius * math.cos(angle),
        circle.center.y + circle.radius * math.sin(angle),
    }
}

// Get the tangent direction at a point on a circle (given angle)
tangent_on_circle_2d :: proc(circle: Circle2, angle: f64) -> m.Vec2 {
    // Tangent is perpendicular to radius
    return m.Vec2{
        -math.sin(angle),
        math.cos(angle),
    }
}

// Project a point onto a circle (returns closest point on circle)
closest_point_on_circle_2d :: proc(point: m.Vec2, circle: Circle2) -> (m.Vec2, f64) {
    to_point := point - circle.center
    dist := glsl.length(to_point)

    if m.is_zero(dist) {
        // Point is at center - return arbitrary point
        return m.Vec2{circle.center.x + circle.radius, circle.center.y}, 0.0
    }

    dir := to_point / dist
    closest := circle.center + dir * circle.radius
    angle := math.atan2(dir.y, dir.x)

    return closest, angle
}

// Distance from a point to a circle (positive outside, negative inside)
signed_distance_to_circle_2d :: proc(point: m.Vec2, circle: Circle2) -> f64 {
    dist_to_center := glsl.length(point - circle.center)
    return dist_to_center - circle.radius
}

// Absolute distance from a point to a circle
distance_to_circle_2d :: proc(point: m.Vec2, circle: Circle2) -> f64 {
    return math.abs(signed_distance_to_circle_2d(point, circle))
}

// Evaluate a point on a 2D arc using parameter t in [0, 1]
// t = 0 gives start of arc, t = 1 gives end of arc
point_on_arc_2d :: proc(arc: Arc2, t: f64) -> m.Vec2 {
    angle := arc.start_angle + (arc.end_angle - arc.start_angle) * t
    return m.Vec2{
        arc.center.x + arc.radius * math.cos(angle),
        arc.center.y + arc.radius * math.sin(angle),
    }
}

// Get the tangent direction at a point on an arc (parameter t in [0, 1])
tangent_on_arc_2d :: proc(arc: Arc2, t: f64) -> m.Vec2 {
    angle := arc.start_angle + (arc.end_angle - arc.start_angle) * t
    return m.Vec2{
        -math.sin(angle),
        math.cos(angle),
    }
}

// Get the arc angle span (always positive)
arc_angle_span :: proc(arc: Arc2) -> f64 {
    span := arc.end_angle - arc.start_angle
    // Normalize to [0, 2π]
    for span < 0 {
        span += math.TAU
    }
    for span > math.TAU {
        span -= math.TAU
    }
    return span
}

// Get the arc length
arc_length_2d :: proc(arc: Arc2) -> f64 {
    return arc.radius * arc_angle_span(arc)
}

// Check if an angle is within an arc's angular range
angle_in_arc_range :: proc(arc: Arc2, angle: f64, eps: f64 = m.DEFAULT_TOLERANCE) -> bool {
    // Normalize angle to [0, 2π]
    norm_angle := angle
    for norm_angle < 0 {
        norm_angle += math.TAU
    }
    for norm_angle >= math.TAU {
        norm_angle -= math.TAU
    }

    norm_start := arc.start_angle
    for norm_start < 0 {
        norm_start += math.TAU
    }
    for norm_start >= math.TAU {
        norm_start -= math.TAU
    }

    norm_end := arc.end_angle
    for norm_end < 0 {
        norm_end += math.TAU
    }
    for norm_end >= math.TAU {
        norm_end -= math.TAU
    }

    // Handle wraparound
    if norm_start <= norm_end {
        return norm_angle >= norm_start - eps && norm_angle <= norm_end + eps
    } else {
        return norm_angle >= norm_start - eps || norm_angle <= norm_end + eps
    }
}

// =============================================================================
// 3D Geometry Evaluation Functions
// =============================================================================

// Evaluate a point on a sphere using spherical coordinates (theta, phi)
// theta: azimuthal angle [0, 2π], phi: polar angle [0, π]
point_on_sphere :: proc(sphere: Sphere, theta: f64, phi: f64) -> m.Vec3 {
    return m.Vec3{
        sphere.center.x + sphere.radius * math.sin(phi) * math.cos(theta),
        sphere.center.y + sphere.radius * math.sin(phi) * math.sin(theta),
        sphere.center.z + sphere.radius * math.cos(phi),
    }
}

// Get the normal at a point on a sphere (given theta, phi)
normal_on_sphere :: proc(sphere: Sphere, theta: f64, phi: f64) -> m.Vec3 {
    return m.Vec3{
        math.sin(phi) * math.cos(theta),
        math.sin(phi) * math.sin(theta),
        math.cos(phi),
    }
}

// Project a point onto a sphere (returns closest point on sphere surface)
closest_point_on_sphere :: proc(point: m.Vec3, sphere: Sphere) -> m.Vec3 {
    to_point := point - sphere.center
    dist := glsl.length(to_point)

    if m.is_zero(dist) {
        // Point is at center - return arbitrary point
        return m.Vec3{sphere.center.x + sphere.radius, sphere.center.y, sphere.center.z}
    }

    dir := to_point / dist
    return sphere.center + dir * sphere.radius
}

// Signed distance to sphere (positive outside, negative inside)
signed_distance_to_sphere :: proc(point: m.Vec3, sphere: Sphere) -> f64 {
    dist_to_center := glsl.length(point - sphere.center)
    return dist_to_center - sphere.radius
}

// Absolute distance to sphere surface
distance_to_sphere :: proc(point: m.Vec3, sphere: Sphere) -> f64 {
    return math.abs(signed_distance_to_sphere(point, sphere))
}

// Evaluate a point on a cylinder surface using cylindrical coordinates
// theta: angle around axis [0, 2π], z: position along axis
point_on_cylinder :: proc(cylinder: Cylinder, theta: f64, z: f64) -> m.Vec3 {
    // Build local coordinate system
    up := cylinder.axis_dir

    // Get perpendicular vectors
    right: m.Vec3
    if math.abs(up.z) < 0.9 {
        right = glsl.normalize(glsl.cross(up, m.Vec3{0, 0, 1}))
    } else {
        right = glsl.normalize(glsl.cross(up, m.Vec3{1, 0, 0}))
    }
    forward := glsl.cross(right, up)

    // Point on circle at height z
    circle_point := right * cylinder.radius * math.cos(theta) +
                    forward * cylinder.radius * math.sin(theta)

    return cylinder.axis_origin + up * z + circle_point
}

// Project a point onto a cylinder surface
closest_point_on_cylinder :: proc(point: m.Vec3, cylinder: Cylinder) -> m.Vec3 {
    // Project onto axis
    to_point := point - cylinder.axis_origin
    z := glsl.dot(to_point, cylinder.axis_dir)

    // Point on axis at this height
    axis_point := cylinder.axis_origin + cylinder.axis_dir * z

    // Radial direction
    radial := point - axis_point
    radial_dist := glsl.length(radial)

    if m.is_zero(radial_dist) {
        // Point is on axis - return arbitrary point on circle
        // Get perpendicular vector
        perp: m.Vec3
        if math.abs(cylinder.axis_dir.z) < 0.9 {
            perp = glsl.normalize(glsl.cross(cylinder.axis_dir, m.Vec3{0, 0, 1}))
        } else {
            perp = glsl.normalize(glsl.cross(cylinder.axis_dir, m.Vec3{1, 0, 0}))
        }
        return axis_point + perp * cylinder.radius
    }

    radial_dir := radial / radial_dist
    return axis_point + radial_dir * cylinder.radius
}

// Distance from point to cylinder surface
distance_to_cylinder :: proc(point: m.Vec3, cylinder: Cylinder) -> f64 {
    // Project onto axis
    to_point := point - cylinder.axis_origin
    z := glsl.dot(to_point, cylinder.axis_dir)

    // Point on axis
    axis_point := cylinder.axis_origin + cylinder.axis_dir * z

    // Radial distance
    radial_dist := glsl.length(point - axis_point)

    return math.abs(radial_dist - cylinder.radius)
}
