/**
 * OCCT C Wrapper - Thin C interface to OpenCascade Technology
 *
 * This wrapper provides C bindings for core OCCT functionality needed by OhCAD.
 * It wraps essential TopoDS, BRepPrimAPI, and BRepAlgoAPI operations.
 *
 * Build as shared library: occt_c_wrapper.dylib
 */

#ifndef OCCT_C_WRAPPER_H
#define OCCT_C_WRAPPER_H

#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// Opaque Handle Types (C-safe pointers to C++ objects)
// =============================================================================

typedef void* OCCT_Shape;      // TopoDS_Shape
typedef void* OCCT_Wire;       // TopoDS_Wire
typedef void* OCCT_Face;       // TopoDS_Face
typedef void* OCCT_Solid;      // TopoDS_Solid
typedef void* OCCT_Edge;       // TopoDS_Edge

typedef void* OCCT_Pnt;        // gp_Pnt (3D point)
typedef void* OCCT_Vec;        // gp_Vec (3D vector)
typedef void* OCCT_Dir;        // gp_Dir (3D direction)
typedef void* OCCT_Ax2;        // gp_Ax2 (axis system)

// =============================================================================
// Memory Management
// =============================================================================

// Release/delete shape (decrements reference count)
void OCCT_Shape_Delete(OCCT_Shape shape);

// Check if shape is valid
bool OCCT_Shape_IsValid(OCCT_Shape shape);

// Get shape type (0=VERTEX, 1=EDGE, 2=WIRE, 3=FACE, 4=SHELL, 5=SOLID, 6=COMPOUND)
int OCCT_Shape_Type(OCCT_Shape shape);

// =============================================================================
// Geometry Primitives (gp package)
// =============================================================================

// Create 3D point
OCCT_Pnt OCCT_Pnt_Create(double x, double y, double z);
void OCCT_Pnt_Delete(OCCT_Pnt pnt);

// Create 3D vector
OCCT_Vec OCCT_Vec_Create(double x, double y, double z);
void OCCT_Vec_Delete(OCCT_Vec vec);

// Create 3D direction (normalized vector)
OCCT_Dir OCCT_Dir_Create(double x, double y, double z);
void OCCT_Dir_Delete(OCCT_Dir dir);

// Create axis system (origin + direction)
OCCT_Ax2 OCCT_Ax2_Create(OCCT_Pnt origin, OCCT_Dir direction);
void OCCT_Ax2_Delete(OCCT_Ax2 ax2);

// =============================================================================
// Wire Creation (2D Profile)
// =============================================================================

// Create wire from array of 2D points (on XY plane)
// points: array of [x, y] pairs
// num_points: number of points
// closed: whether to close the wire (connect last to first)
OCCT_Wire OCCT_Wire_FromPoints2D(const double* points, int num_points, bool closed);

// Create wire from array of 3D points
OCCT_Wire OCCT_Wire_FromPoints3D(const double* points, int num_points, bool closed);

void OCCT_Wire_Delete(OCCT_Wire wire);

// =============================================================================
// Extrusion (BRepPrimAPI_MakePrism)
// =============================================================================

// Extrude a wire to create a solid
// wire: 2D profile (must be closed)
// vx, vy, vz: extrusion vector
OCCT_Shape OCCT_Extrude_Wire(OCCT_Wire wire, double vx, double vy, double vz);

// Extrude a face to create a solid
OCCT_Shape OCCT_Extrude_Face(OCCT_Face face, double vx, double vy, double vz);

// =============================================================================
// Revolution (BRepPrimAPI_MakeRevol)
// =============================================================================

// Revolve a wire around an axis
// wire: 2D profile
// axis: rotation axis (origin + direction)
// angle: rotation angle in radians
OCCT_Shape OCCT_Revolve_Wire(OCCT_Wire wire, OCCT_Ax2 axis, double angle);

// =============================================================================
// Boolean Operations (BRepAlgoAPI)
// =============================================================================

// Boolean union (fuse)
OCCT_Shape OCCT_Boolean_Union(OCCT_Shape shape1, OCCT_Shape shape2);

// Boolean difference (cut)
OCCT_Shape OCCT_Boolean_Difference(OCCT_Shape base, OCCT_Shape tool);

// Boolean intersection (common)
OCCT_Shape OCCT_Boolean_Intersection(OCCT_Shape shape1, OCCT_Shape shape2);

// =============================================================================
// Primitive Shapes (BRepPrimAPI)
// =============================================================================

// Create box primitive (dimensions from origin)
OCCT_Shape OCCT_Primitive_Box(double dx, double dy, double dz);

// Create box primitive between two corner points
OCCT_Shape OCCT_Primitive_Box_TwoCorners(double x1, double y1, double z1,
                                          double x2, double y2, double z2);

// Create cylinder primitive (centered at origin, along Z axis)
OCCT_Shape OCCT_Primitive_Cylinder(double radius, double height);

// Create cylinder with custom axis
OCCT_Shape OCCT_Primitive_Cylinder_Axis(OCCT_Pnt base, OCCT_Dir axis,
                                         double radius, double height);

// Create sphere primitive (centered at origin)
OCCT_Shape OCCT_Primitive_Sphere(double radius);

// Create sphere at specific center point
OCCT_Shape OCCT_Primitive_Sphere_Center(OCCT_Pnt center, double radius);

// Create cone primitive (centered at origin, along Z axis)
OCCT_Shape OCCT_Primitive_Cone(double radius1, double radius2, double height);

// Create torus primitive (centered at origin, in XY plane)
OCCT_Shape OCCT_Primitive_Torus(double major_radius, double minor_radius);

// =============================================================================
// Tessellation (Mesh Generation for Rendering)
// =============================================================================

// Tessellation parameters
typedef struct {
    double linear_deflection;   // Maximum distance from curve to mesh (e.g., 0.1mm)
    double angular_deflection;  // Maximum angle between normals (e.g., 0.5° = 0.0087 rad)
    bool relative;              // If true, deflection is relative to shape size
} OCCT_TessellationParams;

// Tessellated mesh data (triangle soup)
typedef struct {
    // Vertices (array of x,y,z triples)
    float* vertices;
    int num_vertices;

    // Normals (array of nx,ny,nz triples, same count as vertices)
    float* normals;

    // Triangles (array of vertex indices, 3 per triangle)
    int* triangles;
    int num_triangles;
} OCCT_Mesh;

// Generate triangle mesh from shape
// Returns NULL if tessellation fails
OCCT_Mesh* OCCT_Tessellate(OCCT_Shape shape, OCCT_TessellationParams params);

// Free tessellated mesh
void OCCT_Mesh_Delete(OCCT_Mesh* mesh);

// =============================================================================
// Utility Functions
// =============================================================================

// Get OCCT version string (e.g., "7.9.2")
const char* OCCT_Version();

// Initialize OCCT (call once at startup)
void OCCT_Initialize();

// Cleanup OCCT (call once at shutdown)
void OCCT_Cleanup();

#ifdef __cplusplus
}
#endif

#endif // OCCT_C_WRAPPER_H
