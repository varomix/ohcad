package manifold

// ManifoldCAD C API Type Definitions
// Based on ManifoldCAD 3.2.1 C API headers (Apache 2.0 License)

import "core:c"

// Opaque pointer types - these are handles to internal ManifoldCAD structures
Manifold :: distinct rawptr
ManifoldVec :: distinct rawptr
CrossSection :: distinct rawptr
CrossSectionVec :: distinct rawptr
SimplePolygon :: distinct rawptr
Polygons :: distinct rawptr
MeshGL :: distinct rawptr
MeshGL64 :: distinct rawptr
Box :: distinct rawptr
Rect :: distinct rawptr
Triangulation :: distinct rawptr

// 2D Vector
Vec2 :: struct {
    x: f64,
    y: f64,
}

// 3D Vector
Vec3 :: struct {
    x: f64,
    y: f64,
    z: f64,
}

// Integer 3D Vector
IVec3 :: struct {
    x: c.int,
    y: c.int,
    z: c.int,
}

// 4D Vector
Vec4 :: struct {
    x: f64,
    y: f64,
    z: f64,
    w: f64,
}

// Manifold Properties
Properties :: struct {
    surface_area: f64,
    volume: f64,
}

// Manifold Pair (for split operations)
ManifoldPair :: struct {
    first: Manifold,
    second: Manifold,
}

// Boolean Operation Types
OpType :: enum c.int {
    Add = 0,
    Subtract = 1,
    Intersect = 2,
}

// Error Codes
Error :: enum c.int {
    NoError = 0,
    NonFiniteVertex = 1,
    NotManifold = 2,
    VertexIndexOutOfBounds = 3,
    PropertiesWrongLength = 4,
    MissingPositionProperties = 5,
    MergeVectorsDifferentLengths = 6,
    MergeIndexOutOfBounds = 7,
    TransformWrongLength = 8,
    RunIndexWrongLength = 9,
    FaceIdWrongLength = 10,
    InvalidConstruction = 11,
    ResultTooLarge = 12,
}

// Fill Rule (for 2D polygons)
FillRule :: enum c.int {
    EvenOdd = 0,
    NonZero = 1,
    Positive = 2,
    Negative = 3,
}

// Join Type (for 2D offsets)
JoinType :: enum c.int {
    Square = 0,
    Round = 1,
    Miter = 2,
    Bevel = 3,
}

// Signed Distance Function callback type
Sdf :: #type proc "c" (x: f64, y: f64, z: f64, ctx: rawptr) -> f64
