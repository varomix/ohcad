// OCCT Primitives - High-level wrappers for primitive shapes
package occt

import "core:fmt"

// =============================================================================
// Box Primitives
// =============================================================================

// Create box from origin with given dimensions
create_box :: proc(width, height, depth: f64) -> Shape {
    if width <= 0 || height <= 0 || depth <= 0 {
        fmt.println("Error: Box dimensions must be positive")
        return nil
    }

    return OCCT_Primitive_Box(width, height, depth)
}

// Create box between two corner points
create_box_corners :: proc(x1, y1, z1, x2, y2, z2: f64) -> Shape {
    return OCCT_Primitive_Box_TwoCorners(x1, y1, z1, x2, y2, z2)
}

// =============================================================================
// Cylinder Primitives
// =============================================================================

// Create cylinder along Z axis, centered at origin
create_cylinder :: proc(radius, height: f64) -> Shape {
    if radius <= 0 || height <= 0 {
        fmt.println("Error: Cylinder radius and height must be positive")
        return nil
    }

    return OCCT_Primitive_Cylinder(radius, height)
}

// Create cylinder with custom base point and axis
create_cylinder_axis :: proc(base_x, base_y, base_z: f64,
                              axis_x, axis_y, axis_z: f64,
                              radius, height: f64) -> Shape {
    if radius <= 0 || height <= 0 {
        fmt.println("Error: Cylinder radius and height must be positive")
        return nil
    }

    base := OCCT_Pnt_Create(base_x, base_y, base_z)
    defer OCCT_Pnt_Delete(base)

    axis := OCCT_Dir_Create(axis_x, axis_y, axis_z)
    defer OCCT_Dir_Delete(axis)

    return OCCT_Primitive_Cylinder_Axis(base, axis, radius, height)
}

// =============================================================================
// Sphere Primitives
// =============================================================================

// Create sphere at origin
create_sphere :: proc(radius: f64) -> Shape {
    if radius <= 0 {
        fmt.println("Error: Sphere radius must be positive")
        return nil
    }

    return OCCT_Primitive_Sphere(radius)
}

// Create sphere at specific center point
create_sphere_at :: proc(center_x, center_y, center_z, radius: f64) -> Shape {
    if radius <= 0 {
        fmt.println("Error: Sphere radius must be positive")
        return nil
    }

    center := OCCT_Pnt_Create(center_x, center_y, center_z)
    defer OCCT_Pnt_Delete(center)

    return OCCT_Primitive_Sphere_Center(center, radius)
}

// =============================================================================
// Cone Primitives
// =============================================================================

// Create cone along Z axis
// radius1 = bottom radius, radius2 = top radius
create_cone :: proc(bottom_radius, top_radius, height: f64) -> Shape {
    if bottom_radius < 0 || top_radius < 0 || height <= 0 {
        fmt.println("Error: Cone dimensions invalid")
        return nil
    }

    if bottom_radius == 0 && top_radius == 0 {
        fmt.println("Error: Both cone radii cannot be zero")
        return nil
    }

    return OCCT_Primitive_Cone(bottom_radius, top_radius, height)
}

// =============================================================================
// Torus Primitives
// =============================================================================

// Create torus in XY plane, centered at origin
create_torus :: proc(major_radius, minor_radius: f64) -> Shape {
    if major_radius <= 0 || minor_radius <= 0 {
        fmt.println("Error: Torus radii must be positive")
        return nil
    }

    if minor_radius >= major_radius {
        fmt.println("Error: Torus minor radius must be less than major radius")
        return nil
    }

    return OCCT_Primitive_Torus(major_radius, minor_radius)
}
