// features/primitives - Primitive Solid Creation
// Creates basic 3D primitives (Box, Cylinder, Sphere, Cone, Torus) using OCCT
package ohcad_primitives

import "core:fmt"
import m "../../core/math"
import occt "../../core/geometry/occt"
import extrude "../../features/extrude"  // For SimpleSolid structure

// =============================================================================
// Primitive Types
// =============================================================================

PrimitiveType :: enum {
    Box,
    Cylinder,
    Sphere,
    Cone,
    Torus,
}

// =============================================================================
// Primitive Parameters
// =============================================================================

BoxParams :: struct {
    width:  f64,  // X dimension
    height: f64,  // Y dimension
    depth:  f64,  // Z dimension
}

CylinderParams :: struct {
    radius: f64,
    height: f64,
}

SphereParams :: struct {
    radius: f64,
}

ConeParams :: struct {
    bottom_radius: f64,
    top_radius:    f64,
    height:        f64,
}

TorusParams :: struct {
    major_radius: f64,
    minor_radius: f64,
}

// Union of all primitive parameters
PrimitiveParams :: union {
    BoxParams,
    CylinderParams,
    SphereParams,
    ConeParams,
    TorusParams,
}

// =============================================================================
// Primitive Creation Result
// =============================================================================

PrimitiveResult :: struct {
    occt_shape: occt.Shape,          // NEW: Exact B-Rep geometry for boolean/fillet/chamfer operations
    solid:      ^extrude.SimpleSolid,  // Tessellated mesh for rendering
    success:    bool,                   // Operation success flag
    message:    string,                 // Error/status message
}

// =============================================================================
// Main Primitive Creation Function
// =============================================================================

create_primitive :: proc(params: PrimitiveParams) -> PrimitiveResult {
    result: PrimitiveResult

    // Create OCCT shape based on primitive type
    shape: occt.Shape = nil

    fmt.println("🔍 DEBUG: Starting primitive creation...")

    switch p in params {
    case BoxParams:
        fmt.printf("🔍 DEBUG: Creating Box (%.1f x %.1f x %.1f)\n", p.width, p.height, p.depth)
        if p.width <= 0 || p.height <= 0 || p.depth <= 0 {
            result.message = "Box dimensions must be positive"
            return result
        }
        fmt.println("🔍 DEBUG: Calling occt.create_box()...")
        shape = occt.create_box(p.width, p.height, p.depth)
        fmt.printf("🔍 DEBUG: occt.create_box() returned: %v\n", shape)

    case CylinderParams:
        fmt.printf("🔍 DEBUG: Creating Cylinder (r=%.1f, h=%.1f)\n", p.radius, p.height)
        if p.radius <= 0 || p.height <= 0 {
            result.message = "Cylinder radius and height must be positive"
            return result
        }
        fmt.println("🔍 DEBUG: Calling occt.create_cylinder()...")
        shape = occt.create_cylinder(p.radius, p.height)
        fmt.printf("🔍 DEBUG: occt.create_cylinder() returned: %v\n", shape)

    case SphereParams:
        fmt.printf("🔍 DEBUG: Creating Sphere (r=%.1f)\n", p.radius)
        if p.radius <= 0 {
            result.message = "Sphere radius must be positive"
            return result
        }
        fmt.println("🔍 DEBUG: Calling occt.create_sphere()...")
        shape = occt.create_sphere(p.radius)
        fmt.printf("🔍 DEBUG: occt.create_sphere() returned: %v\n", shape)

    case ConeParams:
        fmt.printf("🔍 DEBUG: Creating Cone (r1=%.1f, r2=%.1f, h=%.1f)\n", p.bottom_radius, p.top_radius, p.height)
        if p.bottom_radius < 0 || p.top_radius < 0 || p.height <= 0 {
            result.message = "Cone dimensions invalid"
            return result
        }
        if p.bottom_radius == 0 && p.top_radius == 0 {
            result.message = "Both cone radii cannot be zero"
            return result
        }
        fmt.println("🔍 DEBUG: Calling occt.create_cone()...")
        shape = occt.create_cone(p.bottom_radius, p.top_radius, p.height)
        fmt.printf("🔍 DEBUG: occt.create_cone() returned: %v\n", shape)

    case TorusParams:
        fmt.printf("🔍 DEBUG: Creating Torus (major=%.1f, minor=%.1f)\n", p.major_radius, p.minor_radius)
        if p.major_radius <= 0 || p.minor_radius <= 0 {
            result.message = "Torus radii must be positive"
            return result
        }
        if p.minor_radius >= p.major_radius {
            result.message = "Torus minor radius must be less than major radius"
            return result
        }
        fmt.println("🔍 DEBUG: Calling occt.create_torus()...")
        shape = occt.create_torus(p.major_radius, p.minor_radius)
        fmt.printf("🔍 DEBUG: occt.create_torus() returned: %v\n", shape)
    }

    if shape == nil {
        fmt.println("🔍 DEBUG: ❌ Shape is nil - OCCT creation failed!")
        result.message = "Failed to create OCCT shape"
        return result
    }
    fmt.println("🔍 DEBUG: ✓ Shape created successfully")

    // Validate shape
    fmt.println("🔍 DEBUG: Validating shape...")
    if !occt.is_valid(shape) {
        fmt.println("🔍 DEBUG: ❌ Shape validation failed!")
        // Clean up invalid shape
        occt.delete_shape(shape)
        result.message = "OCCT shape is invalid"
        return result
    }
    fmt.println("🔍 DEBUG: ✓ Shape is valid")

    // Tessellate to triangle mesh
    fmt.println("🔍 DEBUG: Tessellating shape to mesh...")
    mesh := occt.OCCT_Tessellate(shape, occt.DEFAULT_TESSELLATION)
    if mesh == nil {
        fmt.println("🔍 DEBUG: ❌ Tessellation failed!")
        // Clean up shape on failure
        occt.delete_shape(shape)
        result.message = "Failed to tessellate primitive"
        return result
    }
    fmt.printf("🔍 DEBUG: ✓ Tessellation successful: %d vertices, %d triangles\n",
        mesh.num_vertices, mesh.num_triangles)
    defer occt.delete_mesh(mesh)

    // Convert OCCT mesh to SimpleSolid
    fmt.println("🔍 DEBUG: Converting mesh to SimpleSolid...")
    solid := occt_mesh_to_simple_solid(mesh)
    if solid == nil {
        fmt.println("🔍 DEBUG: ❌ Mesh conversion failed!")
        // Clean up shape on failure
        occt.delete_shape(shape)
        result.message = "Failed to convert mesh to solid"
        return result
    }
    fmt.println("🔍 DEBUG: ✓ Mesh conversion successful")

    // Store both exact geometry and tessellated mesh
    result.occt_shape = shape  // IMPORTANT: Shape is NOT deleted - stored for boolean ops
    result.solid = solid
    result.success = true
    result.message = "Primitive created successfully"

    fmt.printf("✓ Primitive created: %d vertices, %d triangles\n",
        len(solid.vertices), len(solid.triangles))

    return result
}

// =============================================================================
// OCCT Mesh → SimpleSolid Conversion
// =============================================================================

occt_mesh_to_simple_solid :: proc(mesh: ^occt.Mesh) -> ^extrude.SimpleSolid {
    solid := new(extrude.SimpleSolid)

    // Convert vertices
    for i in 0..<int(mesh.num_vertices) {
        v := new(extrude.Vertex)
        v.position = m.Vec3{
            f64(mesh.vertices[i*3 + 0]),
            f64(mesh.vertices[i*3 + 1]),
            f64(mesh.vertices[i*3 + 2]),
        }
        append(&solid.vertices, v)
    }

    // Convert triangles
    for i in 0..<int(mesh.num_triangles) {
        i0 := mesh.triangles[i*3 + 0]
        i1 := mesh.triangles[i*3 + 1]
        i2 := mesh.triangles[i*3 + 2]

        tri := extrude.Triangle3D{
            v0 = solid.vertices[i0].position,
            v1 = solid.vertices[i1].position,
            v2 = solid.vertices[i2].position,
            normal = m.Vec3{
                f64(mesh.normals[i0*3 + 0]),
                f64(mesh.normals[i0*3 + 1]),
                f64(mesh.normals[i0*3 + 2]),
            },
            face_id = -1,  // Primitives don't have face selection yet
        }

        append(&solid.triangles, tri)
    }

    fmt.printf("Converted OCCT mesh: %d vertices → %d triangles\n",
        len(solid.vertices), len(solid.triangles))

    return solid
}

// =============================================================================
// Cleanup
// =============================================================================

destroy_primitive :: proc(solid: ^extrude.SimpleSolid) {
    if solid == nil do return

    // Free vertices
    for v in solid.vertices {
        free(v)
    }
    delete(solid.vertices)

    // Free edges
    for e in solid.edges {
        free(e)
    }
    delete(solid.edges)

    // Free faces
    for &face in solid.faces {
        delete(face.vertices)
    }
    delete(solid.faces)

    // Free triangles
    delete(solid.triangles)

    free(solid)
}
