// OpenCascade Technology (OCCT) bindings for Odin
// Provides B-Rep modeling, boolean operations, and CAD features
//
// This wraps the C wrapper layer (occt_c_wrapper.h) which provides
// a C interface to the C++ OCCT library.
//
// Architecture:
//   Odin (this file) → C wrapper → C++ OCCT
//
package occt

import "core:c"

// =============================================================================
// Opaque Handle Types
// =============================================================================

Shape :: distinct rawptr   // TopoDS_Shape
Wire :: distinct rawptr    // TopoDS_Wire
Face :: distinct rawptr    // TopoDS_Face
Solid :: distinct rawptr   // TopoDS_Solid
Edge :: distinct rawptr    // TopoDS_Edge

Pnt :: distinct rawptr     // gp_Pnt (3D point)
Vec :: distinct rawptr     // gp_Vec (3D vector)
Dir :: distinct rawptr     // gp_Dir (3D direction)
Ax2 :: distinct rawptr     // gp_Ax2 (axis system)

// =============================================================================
// Shape Type Enumeration
// =============================================================================

ShapeType :: enum c.int {
    VERTEX   = 0,
    EDGE     = 1,
    WIRE     = 2,
    FACE     = 3,
    SHELL    = 4,
    SOLID    = 5,
    COMPOUND = 6,
}

// =============================================================================
// Tessellation Parameters
// =============================================================================

TessellationParams :: struct {
    linear_deflection: f64,   // Maximum distance from curve to mesh (e.g., 0.1mm)
    angular_deflection: f64,  // Maximum angle between normals (e.g., 0.5° = 0.0087 rad)
    relative: bool,           // If true, deflection is relative to shape size
}

// Default tessellation parameters (good quality for small CAD parts)
DEFAULT_TESSELLATION :: TessellationParams{
    linear_deflection = 1.0,        // 1.0mm precision (coarser, faster)
    angular_deflection = 0.1,       // ~5.7° in radians (coarser, faster)
    relative = false,
}

// =============================================================================
// Tessellated Mesh (Triangle Soup)
// =============================================================================

Mesh :: struct {
    vertices: [^]f32,      // Array of x,y,z triples
    num_vertices: c.int,   // Number of vertices

    normals: [^]f32,       // Array of nx,ny,nz triples

    triangles: [^]c.int,   // Array of vertex indices (3 per triangle)
    num_triangles: c.int,  // Number of triangles
}

// =============================================================================
// Foreign Library Import
// =============================================================================

// This will link against the C wrapper shared library
// Built using build_occt_wrapper.sh
// Path is relative to the .odin file location
when ODIN_OS == .Darwin {
    foreign import occt_lib "libocct_wrapper.dylib"
} else when ODIN_OS == .Linux {
    foreign import occt_lib "libocct_wrapper.so"
} else when ODIN_OS == .Windows {
    foreign import occt_lib "occt_wrapper.dll"
}

// =============================================================================
// Foreign Function Bindings
// =============================================================================

@(default_calling_convention="c")
foreign occt_lib {
    // Memory Management
    OCCT_Shape_Delete :: proc(shape: Shape) ---
    OCCT_Shape_IsValid :: proc(shape: Shape) -> bool ---
    OCCT_Shape_Type :: proc(shape: Shape) -> c.int ---

    // Geometry Primitives
    OCCT_Pnt_Create :: proc(x, y, z: f64) -> Pnt ---
    OCCT_Pnt_Delete :: proc(pnt: Pnt) ---

    OCCT_Vec_Create :: proc(x, y, z: f64) -> Vec ---
    OCCT_Vec_Delete :: proc(vec: Vec) ---

    OCCT_Dir_Create :: proc(x, y, z: f64) -> Dir ---
    OCCT_Dir_Delete :: proc(dir: Dir) ---

    OCCT_Ax2_Create :: proc(origin: Pnt, direction: Dir) -> Ax2 ---
    OCCT_Ax2_Delete :: proc(ax2: Ax2) ---

    // Wire Creation
    OCCT_Wire_FromPoints2D :: proc(points: [^]f64, num_points: c.int, closed: bool) -> Wire ---
    OCCT_Wire_FromPoints3D :: proc(points: [^]f64, num_points: c.int, closed: bool) -> Wire ---
    OCCT_Wire_Delete :: proc(wire: Wire) ---

    // Extrusion
    OCCT_Extrude_Wire :: proc(wire: Wire, vx, vy, vz: f64) -> Shape ---
    OCCT_Extrude_Face :: proc(face: Face, vx, vy, vz: f64) -> Shape ---

    // Revolution
    OCCT_Revolve_Wire :: proc(wire: Wire, axis: Ax2, angle: f64) -> Shape ---

    // Boolean Operations
    OCCT_Boolean_Union :: proc(shape1, shape2: Shape) -> Shape ---
    OCCT_Boolean_Difference :: proc(base, tool: Shape) -> Shape ---
    OCCT_Boolean_Intersection :: proc(shape1, shape2: Shape) -> Shape ---

    // Primitive Shapes
    OCCT_Primitive_Box :: proc(dx, dy, dz: f64) -> Shape ---
    OCCT_Primitive_Box_TwoCorners :: proc(x1, y1, z1, x2, y2, z2: f64) -> Shape ---
    OCCT_Primitive_Cylinder :: proc(radius, height: f64) -> Shape ---
    OCCT_Primitive_Cylinder_Axis :: proc(base: Pnt, axis: Dir, radius, height: f64) -> Shape ---
    OCCT_Primitive_Sphere :: proc(radius: f64) -> Shape ---
    OCCT_Primitive_Sphere_Center :: proc(center: Pnt, radius: f64) -> Shape ---
    OCCT_Primitive_Cone :: proc(radius1, radius2, height: f64) -> Shape ---
    OCCT_Primitive_Torus :: proc(major_radius, minor_radius: f64) -> Shape ---

    // Tessellation
    OCCT_Tessellate :: proc(shape: Shape, params: TessellationParams) -> ^Mesh ---
    OCCT_Mesh_Delete :: proc(mesh: ^Mesh) ---

    // Utility
    OCCT_Version :: proc() -> cstring ---
    OCCT_Initialize :: proc() ---
    OCCT_Cleanup :: proc() ---
}

// =============================================================================
// High-Level Odin Wrappers (Memory-Safe)
// =============================================================================

// Initialize OCCT library (call once at startup)
initialize :: proc() {
    OCCT_Initialize()
}

// Cleanup OCCT library (call once at shutdown)
cleanup :: proc() {
    OCCT_Cleanup()
}

// Get OCCT version string
version :: proc() -> string {
    return string(OCCT_Version())
}

// Check if shape is valid
is_valid :: proc(shape: Shape) -> bool {
    if shape == nil do return false
    return OCCT_Shape_IsValid(shape)
}

// Get shape type
get_type :: proc(shape: Shape) -> ShapeType {
    return ShapeType(OCCT_Shape_Type(shape))
}

// Delete shape (manual memory management)
delete_shape :: proc(shape: Shape) {
    if shape != nil {
        OCCT_Shape_Delete(shape)
    }
}

// Delete mesh (manual memory management)
delete_mesh :: proc(mesh: ^Mesh) {
    if mesh != nil {
        OCCT_Mesh_Delete(mesh)
    }
}
