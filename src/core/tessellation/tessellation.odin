package tessellation

import "core:c"

// libtess2 Odin bindings
// Foreign function interface to libtess2 for polygon tessellation

when ODIN_OS == .Darwin {
    foreign import libtess2 "../../../libs/libtess2.a"
} else {
    foreign import libtess2 "system:tess2"
}

// Enums
TessWindingRule :: enum c.int {
    ODD,
    NONZERO,
    POSITIVE,
    NEGATIVE,
    ABS_GEQ_TWO,
}

TessElementType :: enum c.int {
    POLYGONS,
    CONNECTED_POLYGONS,
    BOUNDARY_CONTOURS,
}

TessOption :: enum c.int {
    CONSTRAINED_DELAUNAY_TRIANGULATION,
    REVERSE_CONTOURS,
}

TESSstatus :: enum c.int {
    OK,
    OUT_OF_MEMORY,
    INVALID_INPUT,
}

// Types
TESSreal :: f32
TESSindex :: c.int
TESStesselator :: struct {}

TESS_UNDEF : TESSindex : ~TESSindex(0)

// Foreign function declarations
@(default_calling_convention="c", link_prefix="tess")
foreign libtess2 {
    // Create/destroy tesselator
    NewTess :: proc(alloc: rawptr) -> ^TESStesselator ---
    DeleteTess :: proc(tess: ^TESStesselator) ---

    // Add contours to tesselate
    AddContour :: proc(tess: ^TESStesselator, size: c.int, pointer: rawptr, stride: c.int, count: c.int) ---

    // Set options
    SetOption :: proc(tess: ^TESStesselator, option: c.int, value: c.int) ---

    // Tesselate
    Tesselate :: proc(tess: ^TESStesselator, windingRule: c.int, elementType: c.int, polySize: c.int, vertexSize: c.int, normal: [^]TESSreal) -> c.int ---

    // Get results
    GetVertexCount :: proc(tess: ^TESStesselator) -> c.int ---
    GetVertices :: proc(tess: ^TESStesselator) -> [^]TESSreal ---
    GetVertexIndices :: proc(tess: ^TESStesselator) -> [^]TESSindex ---
    GetElementCount :: proc(tess: ^TESStesselator) -> c.int ---
    GetElements :: proc(tess: ^TESStesselator) -> [^]TESSindex ---
    GetStatus :: proc(tess: ^TESStesselator) -> TESSstatus ---
}
