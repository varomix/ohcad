// core/solver - libslvs (SolveSpace constraint solver) FFI bindings
//
// This file contains Odin FFI bindings to the libslvs C API from SolveSpace.
// libslvs is a 2D/3D geometric constraint solver used for parametric sketching.
//
// References:
// - SolveSpace: https://solvespace.com
// - API Docs: libs/Include/slvs.h

package ohcad_solver

import "core:c"

// =============================================================================
// Type Definitions
// =============================================================================

// Handles (32-bit unsigned integers)
Slvs_hParam      :: u32
Slvs_hEntity     :: u32
Slvs_hConstraint :: u32
Slvs_hGroup      :: u32

// Special values
SLVS_FREE_IN_3D :: 0

// Result codes
SLVS_RESULT_OKAY              :: 0
SLVS_RESULT_INCONSISTENT      :: 1
SLVS_RESULT_DIDNT_CONVERGE    :: 2
SLVS_RESULT_TOO_MANY_UNKNOWNS :: 3
SLVS_RESULT_REDUNDANT_OKAY    :: 4

// =============================================================================
// Entity Types
// =============================================================================

SLVS_E_POINT_IN_3D      :: 50000
SLVS_E_POINT_IN_2D      :: 50001
SLVS_E_NORMAL_IN_3D     :: 60000
SLVS_E_NORMAL_IN_2D     :: 60001
SLVS_E_DISTANCE         :: 70000
SLVS_E_WORKPLANE        :: 80000
SLVS_E_LINE_SEGMENT     :: 80001
SLVS_E_CUBIC            :: 80002
SLVS_E_CIRCLE           :: 80003
SLVS_E_ARC_OF_CIRCLE    :: 80004

// =============================================================================
// Constraint Types
// =============================================================================

SLVS_C_POINTS_COINCIDENT    :: 100000
SLVS_C_PT_PT_DISTANCE       :: 100001
SLVS_C_PT_PLANE_DISTANCE    :: 100002
SLVS_C_PT_LINE_DISTANCE     :: 100003
SLVS_C_PT_FACE_DISTANCE     :: 100004
SLVS_C_PT_IN_PLANE          :: 100005
SLVS_C_PT_ON_LINE           :: 100006
SLVS_C_PT_ON_FACE           :: 100007
SLVS_C_EQUAL_LENGTH_LINES   :: 100008
SLVS_C_LENGTH_RATIO         :: 100009
SLVS_C_EQ_LEN_PT_LINE_D     :: 100010
SLVS_C_EQ_PT_LN_DISTANCES   :: 100011
SLVS_C_EQUAL_ANGLE          :: 100012
SLVS_C_EQUAL_LINE_ARC_LEN   :: 100013
SLVS_C_SYMMETRIC            :: 100014
SLVS_C_SYMMETRIC_HORIZ      :: 100015
SLVS_C_SYMMETRIC_VERT       :: 100016
SLVS_C_SYMMETRIC_LINE       :: 100017
SLVS_C_AT_MIDPOINT          :: 100018
SLVS_C_HORIZONTAL           :: 100019
SLVS_C_VERTICAL             :: 100020
SLVS_C_DIAMETER             :: 100021
SLVS_C_PT_ON_CIRCLE         :: 100022
SLVS_C_SAME_ORIENTATION     :: 100023
SLVS_C_ANGLE                :: 100024
SLVS_C_PARALLEL             :: 100025
SLVS_C_PERPENDICULAR        :: 100026
SLVS_C_ARC_LINE_TANGENT     :: 100027
SLVS_C_CUBIC_LINE_TANGENT   :: 100028
SLVS_C_EQUAL_RADIUS         :: 100029
SLVS_C_PROJ_PT_DISTANCE     :: 100030
SLVS_C_WHERE_DRAGGED        :: 100031
SLVS_C_CURVE_CURVE_TANGENT  :: 100032
SLVS_C_LENGTH_DIFFERENCE    :: 100033
SLVS_C_ARC_ARC_LEN_RATIO    :: 100034
SLVS_C_ARC_LINE_LEN_RATIO   :: 100035
SLVS_C_ARC_ARC_DIFFERENCE   :: 100036
SLVS_C_ARC_LINE_DIFFERENCE  :: 100037

// =============================================================================
// Data Structures
// =============================================================================

// Parameter - a single real number variable
Slvs_Param :: struct {
    h:     Slvs_hParam,
    group: Slvs_hGroup,
    val:   f64,
}

// Entity - geometric object (point, line, circle, etc.)
Slvs_Entity :: struct {
    h:        Slvs_hEntity,
    group:    Slvs_hGroup,
    type:     c.int,
    wrkpl:    Slvs_hEntity,
    point:    [4]Slvs_hEntity,
    normal:   Slvs_hEntity,
    distance: Slvs_hEntity,
    param:    [4]Slvs_hParam,
}

// Constraint - geometric constraint
Slvs_Constraint :: struct {
    h:       Slvs_hConstraint,
    group:   Slvs_hGroup,
    type:    c.int,
    wrkpl:   Slvs_hEntity,
    valA:    f64,
    ptA:     Slvs_hEntity,
    ptB:     Slvs_hEntity,
    entityA: Slvs_hEntity,
    entityB: Slvs_hEntity,
    entityC: Slvs_hEntity,
    entityD: Slvs_hEntity,
    other:   c.int,
    other2:  c.int,
}

// Solve result (stateful API)
Slvs_SolveResult :: struct {
    result: c.int,
    dof:    c.int,
    nbad:   c.int,
}

// Empty entity constant
SLVS_E_NONE :: Slvs_Entity{}

// =============================================================================
// FFI Bindings (Stateful API)
// =============================================================================

// Note: Using stateful API which manages internal state automatically.
// This is simpler than the low-level manual API.

foreign import slvs "system:slvs"

@(default_calling_convention="c")
foreign slvs {
    // -------------------------------------------------------------------------
    // Add Entities
    // -------------------------------------------------------------------------

    // Create a base 2D workplane (XY plane at origin)
    Slvs_AddBase2D :: proc(grouph: u32) -> Slvs_Entity ---

    // Add a 2D point in a workplane
    Slvs_AddPoint2D :: proc(grouph: u32, u: f64, v: f64, workplane: Slvs_Entity) -> Slvs_Entity ---

    // Add a 3D point
    Slvs_AddPoint3D :: proc(grouph: u32, x: f64, y: f64, z: f64) -> Slvs_Entity ---

    // Add a 2D normal (same as workplane normal)
    Slvs_AddNormal2D :: proc(grouph: u32, workplane: Slvs_Entity) -> Slvs_Entity ---

    // Add a 3D normal (rotation quaternion)
    Slvs_AddNormal3D :: proc(grouph: u32, qw: f64, qx: f64, qy: f64, qz: f64) -> Slvs_Entity ---

    // Add a distance entity (for circle radius, etc.)
    Slvs_AddDistance :: proc(grouph: u32, value: f64, workplane: Slvs_Entity) -> Slvs_Entity ---

    // Add a 2D line segment
    Slvs_AddLine2D :: proc(grouph: u32, ptA: Slvs_Entity, ptB: Slvs_Entity, workplane: Slvs_Entity) -> Slvs_Entity ---

    // Add a 3D line segment
    Slvs_AddLine3D :: proc(grouph: u32, ptA: Slvs_Entity, ptB: Slvs_Entity) -> Slvs_Entity ---

    // Add a cubic Bezier curve
    Slvs_AddCubic :: proc(grouph: u32, ptA: Slvs_Entity, ptB: Slvs_Entity, ptC: Slvs_Entity, ptD: Slvs_Entity, workplane: Slvs_Entity) -> Slvs_Entity ---

    // Add an arc
    Slvs_AddArc :: proc(grouph: u32, normal: Slvs_Entity, center: Slvs_Entity, start: Slvs_Entity, end: Slvs_Entity, workplane: Slvs_Entity) -> Slvs_Entity ---

    // Add a circle
    Slvs_AddCircle :: proc(grouph: u32, normal: Slvs_Entity, center: Slvs_Entity, radius: Slvs_Entity, workplane: Slvs_Entity) -> Slvs_Entity ---

    // Add a workplane
    Slvs_AddWorkplane :: proc(grouph: u32, origin: Slvs_Entity, nm: Slvs_Entity) -> Slvs_Entity ---

    // -------------------------------------------------------------------------
    // Add Constraints
    // -------------------------------------------------------------------------

    // General constraint adder (rarely used directly)
    Slvs_AddConstraint :: proc(grouph: u32, type: c.int, workplane: Slvs_Entity, val: f64,
                               ptA: Slvs_Entity, ptB: Slvs_Entity,
                               entityA: Slvs_Entity, entityB: Slvs_Entity, entityC: Slvs_Entity, entityD: Slvs_Entity,
                               other: c.int, other2: c.int) -> Slvs_Constraint ---

    // Convenience: Points coincident
    Slvs_Coincident :: proc(grouph: u32, entityA: Slvs_Entity, entityB: Slvs_Entity, workplane: Slvs_Entity) -> Slvs_Constraint ---

    // Convenience: Distance between entities
    Slvs_Distance :: proc(grouph: u32, entityA: Slvs_Entity, entityB: Slvs_Entity, value: f64, workplane: Slvs_Entity) -> Slvs_Constraint ---

    // Convenience: Equal length/radius
    Slvs_Equal :: proc(grouph: u32, entityA: Slvs_Entity, entityB: Slvs_Entity, workplane: Slvs_Entity) -> Slvs_Constraint ---

    // Convenience: Equal angle
    Slvs_EqualAngle :: proc(grouph: u32, entityA: Slvs_Entity, entityB: Slvs_Entity, entityC: Slvs_Entity, entityD: Slvs_Entity, workplane: Slvs_Entity) -> Slvs_Constraint ---

    // Convenience: Equal point-to-line distances
    Slvs_EqualPointToLine :: proc(grouph: u32, entityA: Slvs_Entity, entityB: Slvs_Entity, entityC: Slvs_Entity, entityD: Slvs_Entity, workplane: Slvs_Entity) -> Slvs_Constraint ---

    // Convenience: Length ratio
    Slvs_Ratio :: proc(grouph: u32, entityA: Slvs_Entity, entityB: Slvs_Entity, value: f64, workplane: Slvs_Entity) -> Slvs_Constraint ---

    // Convenience: Symmetric about plane/line
    Slvs_Symmetric :: proc(grouph: u32, entityA: Slvs_Entity, entityB: Slvs_Entity, entityC: Slvs_Entity, workplane: Slvs_Entity) -> Slvs_Constraint ---

    // Convenience: Symmetric horizontal
    Slvs_SymmetricH :: proc(grouph: u32, ptA: Slvs_Entity, ptB: Slvs_Entity, workplane: Slvs_Entity) -> Slvs_Constraint ---

    // Convenience: Symmetric vertical
    Slvs_SymmetricV :: proc(grouph: u32, ptA: Slvs_Entity, ptB: Slvs_Entity, workplane: Slvs_Entity) -> Slvs_Constraint ---

    // Convenience: Midpoint
    Slvs_Midpoint :: proc(grouph: u32, ptA: Slvs_Entity, ptB: Slvs_Entity, workplane: Slvs_Entity) -> Slvs_Constraint ---

    // Convenience: Horizontal
    Slvs_Horizontal :: proc(grouph: u32, entityA: Slvs_Entity, workplane: Slvs_Entity, entityB: Slvs_Entity) -> Slvs_Constraint ---

    // Convenience: Vertical
    Slvs_Vertical :: proc(grouph: u32, entityA: Slvs_Entity, workplane: Slvs_Entity, entityB: Slvs_Entity) -> Slvs_Constraint ---

    // Convenience: Diameter
    Slvs_Diameter :: proc(grouph: u32, entityA: Slvs_Entity, value: f64) -> Slvs_Constraint ---

    // Convenience: Same orientation
    Slvs_SameOrientation :: proc(grouph: u32, entityA: Slvs_Entity, entityB: Slvs_Entity) -> Slvs_Constraint ---

    // Convenience: Angle
    Slvs_Angle :: proc(grouph: u32, entityA: Slvs_Entity, entityB: Slvs_Entity, value: f64, workplane: Slvs_Entity, inverse: c.int) -> Slvs_Constraint ---

    // Convenience: Perpendicular
    Slvs_Perpendicular :: proc(grouph: u32, entityA: Slvs_Entity, entityB: Slvs_Entity, workplane: Slvs_Entity, inverse: c.int) -> Slvs_Constraint ---

    // Convenience: Parallel
    Slvs_Parallel :: proc(grouph: u32, entityA: Slvs_Entity, entityB: Slvs_Entity, workplane: Slvs_Entity) -> Slvs_Constraint ---

    // Convenience: Tangent
    Slvs_Tangent :: proc(grouph: u32, entityA: Slvs_Entity, entityB: Slvs_Entity, workplane: Slvs_Entity) -> Slvs_Constraint ---

    // Convenience: Distance projection
    Slvs_DistanceProj :: proc(grouph: u32, ptA: Slvs_Entity, ptB: Slvs_Entity, value: f64) -> Slvs_Constraint ---

    // Convenience: Length difference
    Slvs_LengthDiff :: proc(grouph: u32, entityA: Slvs_Entity, entityB: Slvs_Entity, value: f64, workplane: Slvs_Entity) -> Slvs_Constraint ---

    // Convenience: Dragged (fixed position)
    Slvs_Dragged :: proc(grouph: u32, ptA: Slvs_Entity, workplane: Slvs_Entity) -> Slvs_Constraint ---

    // -------------------------------------------------------------------------
    // Parameter Access
    // -------------------------------------------------------------------------

    // Get parameter value
    Slvs_GetParamValue :: proc(ph: u32) -> f64 ---

    // Set parameter value
    Slvs_SetParamValue :: proc(ph: u32, value: f64) ---

    // -------------------------------------------------------------------------
    // Solving
    // -------------------------------------------------------------------------

    // Mark entity as being dragged (affects solver priority)
    Slvs_MarkDragged :: proc(ptA: Slvs_Entity) ---

    // Solve sketch (stateful API)
    // If bad != nil, failed constraints are returned in heap-allocated array
    // User must free() the array
    Slvs_SolveSketch :: proc(hg: u32, bad: ^^Slvs_hConstraint) -> Slvs_SolveResult ---

    // Clear all state (call before starting new sketch)
    Slvs_ClearSketch :: proc() ---

    // -------------------------------------------------------------------------
    // Quaternion Utilities
    // -------------------------------------------------------------------------

    // Convert quaternion to U basis vector
    Slvs_QuaternionU :: proc(qw: f64, qx: f64, qy: f64, qz: f64, x: ^f64, y: ^f64, z: ^f64) ---

    // Convert quaternion to V basis vector
    Slvs_QuaternionV :: proc(qw: f64, qx: f64, qy: f64, qz: f64, x: ^f64, y: ^f64, z: ^f64) ---

    // Convert quaternion to N basis vector (normal)
    Slvs_QuaternionN :: proc(qw: f64, qx: f64, qy: f64, qz: f64, x: ^f64, y: ^f64, z: ^f64) ---

    // Make quaternion from two basis vectors
    Slvs_MakeQuaternion :: proc(ux: f64, uy: f64, uz: f64, vx: f64, vy: f64, vz: f64,
                                qw: ^f64, qx: ^f64, qy: ^f64, qz: ^f64) ---

    // -------------------------------------------------------------------------
    // Entity Type Checks
    // -------------------------------------------------------------------------

    Slvs_IsFreeIn3D :: proc(e: Slvs_Entity) -> bool ---
    Slvs_Is3D :: proc(e: Slvs_Entity) -> bool ---
    Slvs_IsNone :: proc(e: Slvs_Entity) -> bool ---
    Slvs_IsPoint2D :: proc(e: Slvs_Entity) -> bool ---
    Slvs_IsPoint3D :: proc(e: Slvs_Entity) -> bool ---
    Slvs_IsNormal2D :: proc(e: Slvs_Entity) -> bool ---
    Slvs_IsNormal3D :: proc(e: Slvs_Entity) -> bool ---
    Slvs_IsLine :: proc(e: Slvs_Entity) -> bool ---
    Slvs_IsLine2D :: proc(e: Slvs_Entity) -> bool ---
    Slvs_IsLine3D :: proc(e: Slvs_Entity) -> bool ---
    Slvs_IsCubic :: proc(e: Slvs_Entity) -> bool ---
    Slvs_IsArc :: proc(e: Slvs_Entity) -> bool ---
    Slvs_IsWorkplane :: proc(e: Slvs_Entity) -> bool ---
    Slvs_IsDistance :: proc(e: Slvs_Entity) -> bool ---
    Slvs_IsPoint :: proc(e: Slvs_Entity) -> bool ---
    Slvs_IsCircle :: proc(e: Slvs_Entity) -> bool ---
}
