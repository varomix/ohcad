package manifold

// ManifoldCAD C API FFI Bindings
// Based on ManifoldCAD 3.2.1 C API (Apache 2.0 License)
// Library: libmanifoldc.dylib (installed via Homebrew at /opt/homebrew/lib)

import "core:c"

// Library linking
when ODIN_OS == .Darwin {
    foreign import manifoldc "system:manifoldc"
}

// Foreign block - C API function declarations
@(default_calling_convention="c")
foreign manifoldc {
    // ========================================
    // Mesh Construction
    // ========================================

    // Create a MeshGL from vertex properties and triangle indices
    // vert_props: interleaved vertex data [x,y,z, x,y,z, ...] as f32
    // n_verts: number of vertices
    // n_props: properties per vertex (3 for position only: x,y,z)
    // tri_verts: triangle indices as u32 [v0,v1,v2, v0,v1,v2, ...]
    // n_tris: number of triangles
    @(link_name="manifold_meshgl")
    meshgl :: proc(mem: rawptr, vert_props: [^]f32, n_verts: c.size_t,
                   n_props: c.size_t, tri_verts: [^]u32, n_tris: c.size_t) -> MeshGL ---

    // Get MeshGL from a Manifold
    @(link_name="manifold_get_meshgl")
    get_meshgl :: proc(mem: rawptr, m: Manifold) -> MeshGL ---

    // Copy a MeshGL
    @(link_name="manifold_meshgl_copy")
    meshgl_copy :: proc(mem: rawptr, m: MeshGL) -> MeshGL ---

    // Merge vertices that are within epsilon distance
    @(link_name="manifold_meshgl_merge")
    meshgl_merge :: proc(mem: rawptr, m: MeshGL) -> MeshGL ---

    // ========================================
    // MeshGL Accessors
    // ========================================

    // Get number of properties per vertex (should be 3 for position-only meshes)
    @(link_name="manifold_meshgl_num_prop")
    meshgl_num_prop :: proc(m: MeshGL) -> c.size_t ---

    // Get number of vertices
    @(link_name="manifold_meshgl_num_vert")
    meshgl_num_vert :: proc(m: MeshGL) -> c.size_t ---

    // Get number of triangles
    @(link_name="manifold_meshgl_num_tri")
    meshgl_num_tri :: proc(m: MeshGL) -> c.size_t ---

    // Get total length of vertex properties array (n_verts * n_props)
    @(link_name="manifold_meshgl_vert_properties_length")
    meshgl_vert_properties_length :: proc(m: MeshGL) -> c.size_t ---

    // Get length of triangle indices array (n_tris * 3)
    @(link_name="manifold_meshgl_tri_length")
    meshgl_tri_length :: proc(m: MeshGL) -> c.size_t ---

    // Get vertex properties array (interleaved: [x,y,z, x,y,z, ...])
    @(link_name="manifold_meshgl_vert_properties")
    meshgl_vert_properties :: proc(mem: rawptr, m: MeshGL) -> [^]f32 ---

    // Get triangle vertex indices array
    @(link_name="manifold_meshgl_tri_verts")
    meshgl_tri_verts :: proc(mem: rawptr, m: MeshGL) -> [^]u32 ---

    // ========================================
    // MeshGL Memory Management
    // ========================================

    // Allocate a new MeshGL object (required before using meshgl constructor)
    @(link_name="manifold_alloc_meshgl")
    alloc_meshgl :: proc() -> MeshGL ---

    // Delete (free) a MeshGL object
    @(link_name="manifold_delete_meshgl")
    delete_meshgl :: proc(m: MeshGL) ---

    // ========================================
    // Manifold Construction
    // ========================================

    // Allocate a new Manifold object (required before using manifold constructors)
    @(link_name="manifold_alloc_manifold")
    alloc_manifold :: proc() -> Manifold ---

    // Delete (free) a Manifold object
    @(link_name="manifold_delete_manifold")
    delete_manifold :: proc(m: Manifold) ---

    // Create a Manifold from a MeshGL
    @(link_name="manifold_of_meshgl")
    of_meshgl :: proc(mem: rawptr, mesh: MeshGL) -> Manifold ---

    // Create an empty Manifold
    @(link_name="manifold_empty")
    empty :: proc(mem: rawptr) -> Manifold ---

    // Copy a Manifold
    @(link_name="manifold_copy")
    copy :: proc(mem: rawptr, m: Manifold) -> Manifold ---

    // ========================================
    // Boolean Operations
    // ========================================

    // Generic boolean operation
    @(link_name="manifold_boolean")
    boolean :: proc(mem: rawptr, a: Manifold, b: Manifold, op: OpType) -> Manifold ---

    // Union (A + B)
    @(link_name="manifold_union")
    union_op :: proc(mem: rawptr, a: Manifold, b: Manifold) -> Manifold ---

    // Difference (A - B)
    @(link_name="manifold_difference")
    difference :: proc(mem: rawptr, a: Manifold, b: Manifold) -> Manifold ---

    // Intersection (A ∩ B)
    @(link_name="manifold_intersection")
    intersection :: proc(mem: rawptr, a: Manifold, b: Manifold) -> Manifold ---

    // Split a manifold by another manifold
    @(link_name="manifold_split")
    split :: proc(mem_first: rawptr, mem_second: rawptr, a: Manifold, b: Manifold) -> ManifoldPair ---

    // Split a manifold by a plane
    @(link_name="manifold_split_by_plane")
    split_by_plane :: proc(mem_first: rawptr, mem_second: rawptr, m: Manifold,
                           normal_x: f64, normal_y: f64, normal_z: f64, offset: f64) -> ManifoldPair ---

    // Trim a manifold by a plane
    @(link_name="manifold_trim_by_plane")
    trim_by_plane :: proc(mem: rawptr, m: Manifold,
                          normal_x: f64, normal_y: f64, normal_z: f64, offset: f64) -> Manifold ---

    // ========================================
    // Transformations
    // ========================================

    // Translate a Manifold
    @(link_name="manifold_translate")
    translate :: proc(mem: rawptr, m: Manifold, x: f64, y: f64, z: f64) -> Manifold ---

    // Rotate a Manifold (degrees)
    @(link_name="manifold_rotate")
    rotate :: proc(mem: rawptr, m: Manifold, x: f64, y: f64, z: f64) -> Manifold ---

    // Scale a Manifold
    @(link_name="manifold_scale")
    scale :: proc(mem: rawptr, m: Manifold, x: f64, y: f64, z: f64) -> Manifold ---

    // Transform a Manifold with a 4x3 matrix (row-major)
    @(link_name="manifold_transform")
    transform :: proc(mem: rawptr, m: Manifold,
                      x1: f64, y1: f64, z1: f64, x2: f64, y2: f64, z2: f64,
                      x3: f64, y3: f64, z3: f64, x4: f64, y4: f64, z4: f64) -> Manifold ---

    // Mirror a Manifold across a plane
    @(link_name="manifold_mirror")
    mirror :: proc(mem: rawptr, m: Manifold, nx: f64, ny: f64, nz: f64) -> Manifold ---

    // ========================================
    // Primitives
    // ========================================

    // Create a cube
    @(link_name="manifold_cube")
    cube :: proc(mem: rawptr, x: f64, y: f64, z: f64, center: c.int) -> Manifold ---

    // Create a sphere
    @(link_name="manifold_sphere")
    sphere :: proc(mem: rawptr, radius: f64, circular_segments: c.int) -> Manifold ---

    // Create a cylinder
    @(link_name="manifold_cylinder")
    cylinder :: proc(mem: rawptr, height: f64, radius_low: f64, radius_high: f64,
                     circular_segments: c.int, center: c.int) -> Manifold ---

    // ========================================
    // Mesh Analysis
    // ========================================

    // Get volume of a Manifold
    @(link_name="manifold_volume")
    volume :: proc(m: Manifold) -> f64 ---

    // Get surface area of a Manifold
    @(link_name="manifold_surface_area")
    surface_area :: proc(m: Manifold) -> f64 ---

    // Check if a Manifold is empty
    @(link_name="manifold_is_empty")
    is_empty :: proc(m: Manifold) -> c.int ---

    // Get the status (error code) of a Manifold
    @(link_name="manifold_status")
    status :: proc(m: Manifold) -> Error ---

    // Get the number of vertices in a Manifold
    @(link_name="manifold_num_vert")
    num_vert :: proc(m: Manifold) -> c.int ---

    // Get the number of edges in a Manifold
    @(link_name="manifold_num_edge")
    num_edge :: proc(m: Manifold) -> c.int ---

    // Get the number of triangles in a Manifold
    @(link_name="manifold_num_tri")
    num_tri :: proc(m: Manifold) -> c.int ---

    // ========================================
    // Memory Management
    // ========================================

    // Destroy a Manifold
    @(link_name="manifold_destruct_manifold")
    destruct_manifold :: proc(m: Manifold) ---

    // Destroy a ManifoldVec
    @(link_name="manifold_destruct_manifold_vec")
    destruct_manifold_vec :: proc(ms: ManifoldVec) ---

    // Destroy a MeshGL
    @(link_name="manifold_destruct_meshgl")
    destruct_meshgl :: proc(m: MeshGL) ---

    // Destroy a MeshGL64
    @(link_name="manifold_destruct_meshgl64")
    destruct_meshgl64 :: proc(m: MeshGL64) ---

    // Destroy a Box
    @(link_name="manifold_destruct_box")
    destruct_box :: proc(b: Box) ---

    // Destroy Polygons
    @(link_name="manifold_destruct_polygons")
    destruct_polygons :: proc(p: Polygons) ---
}

// ========================================
// High-level convenience functions
// ========================================

// Check if a manifold operation resulted in an error
is_valid :: proc(m: Manifold) -> bool {
    return status(m) == .NoError && is_empty(m) == 0
}

// Get human-readable error message
error_string :: proc(err: Error) -> string {
    switch err {
    case .NoError: return "No error"
    case .NonFiniteVertex: return "Non-finite vertex"
    case .NotManifold: return "Not manifold"
    case .VertexIndexOutOfBounds: return "Vertex index out of bounds"
    case .PropertiesWrongLength: return "Properties wrong length"
    case .MissingPositionProperties: return "Missing position properties"
    case .MergeVectorsDifferentLengths: return "Merge vectors different lengths"
    case .MergeIndexOutOfBounds: return "Merge index out of bounds"
    case .TransformWrongLength: return "Transform wrong length"
    case .RunIndexWrongLength: return "Run index wrong length"
    case .FaceIdWrongLength: return "Face ID wrong length"
    case .InvalidConstruction: return "Invalid construction"
    case .ResultTooLarge: return "Result too large"
    }
    return "Unknown error"
}
