# OpenCascade Technology (OCCT) Integration Plan for OhCAD

## Overview

Migrating from mesh-based geometry (Manifold) to B-Rep-based CAD kernel (OCCT).

**Goal:** Professional parametric CAD with exact geometry, robust boolean operations, and standard CAD file support.

---

## Why OCCT?

- ✅ **B-Rep modeling** - Exact curves/surfaces (NURBS), not triangle approximations
- ✅ **Parametric features** - Proper feature regeneration with history
- ✅ **Industry standard** - Used in FreeCAD, Salome, commercial CAD
- ✅ **Complete CAD toolkit** - Extrude, revolve, fillet, chamfer, shell, loft, sweep
- ✅ **Robust booleans** - Union, difference, intersection that actually work
- ✅ **STEP/IGES import/export** - Standard CAD file formats
- ✅ **Topology management** - Proper face/edge/vertex relationships
- ✅ **LGPL license** - Free for commercial use

---

## Architecture Changes

### Current Architecture (Mesh-based)
```
Sketch2D → SimpleSolid (vertices, edges, faces) → Triangle Mesh → Render
                ↓
         Manifold Boolean Ops (BROKEN for pentagon)
```

### New Architecture (B-Rep-based)
```
Sketch2D → OCCT Wire (2D) → OCCT Shape (B-Rep) → Tessellate → Render
              ↓                    ↓
         OCCT Extrude         OCCT Boolean Ops
              ↓                    ↓
         OCCT TopoDS_Shape (exact geometry)
```

**Key Difference:**
- **Old:** Triangle mesh all the way (lossy)
- **New:** Exact B-Rep geometry → tessellate only for rendering

---

## OCCT Modules We'll Use

OCCT has **30+ modules**. We'll focus on these essentials:

### 1. **Foundation Classes** (Always needed)
- `TKernel` - Base types, collections
- `TKMath` - Math utilities, transformations
- `TKBRep` - B-Rep topology (TopoDS)

### 2. **Modeling** (Core CAD operations)
- `TKTopAlgo` - Topology algorithms
- `TKPrim` - Primitive shapes (box, cylinder, sphere)
- `TKBool` - Boolean operations (union, difference, intersection)
- `TKFeat` - Feature modeling (extrude, revolve, fillet, etc.)
- `TKOffset` - Offset operations (shell, thick solid)

### 3. **Data Exchange** (Import/Export)
- `TKSTEP` - STEP format (ISO 10303)
- `TKIGES` - IGES format
- `TKSTL` - STL export

### 4. **Visualization** (Rendering)
- `TKMesh` - Mesh generation from B-Rep (for GPU rendering)
- `TKService` - Visualization services

---

## Implementation Phases

### **Phase 1: Core B-Rep Foundation** (Week 1)
**Goal:** Replace SimpleSolid with OCCT B-Rep

1. **Install & Configure OCCT**
   - [x] Install via Homebrew: `brew install opencascade`
   - [ ] Find library paths: `/opt/homebrew/lib/`
   - [ ] Find headers: `/opt/homebrew/include/opencascade/`

2. **Create Odin FFI Bindings**
   - [ ] `src/core/geometry/occt/occt_types.odin` - Core types (TopoDS_Shape, etc.)
   - [ ] `src/core/geometry/occt/occt_modeling.odin` - Extrude, revolve, boolean ops
   - [ ] `src/core/geometry/occt/occt_mesh.odin` - Tessellation for rendering

3. **Key OCCT Types to Wrap**
   ```cpp
   // Topology (TopoDS)
   TopoDS_Shape      // Base shape type
   TopoDS_Solid      // 3D solid body
   TopoDS_Face       // Surface
   TopoDS_Edge       // Curve
   TopoDS_Vertex     // Point
   TopoDS_Wire       // Connected edges (2D profile)

   // Geometry (Geom)
   gp_Pnt            // 3D point
   gp_Vec            // 3D vector
   gp_Dir            // 3D direction
   gp_Ax2            // Axis system (origin + direction)

   // Modeling Operations
   BRepPrimAPI_MakePrism    // Extrusion
   BRepPrimAPI_MakeRevol    // Revolution
   BRepAlgoAPI_Cut          // Boolean difference
   BRepAlgoAPI_Fuse         // Boolean union
   BRepAlgoAPI_Common       // Boolean intersection
   ```

4. **Data Structure Changes**
   - Replace `SimpleSolid` with `OCCTShape` wrapper:
   ```odin
   OCCTShape :: struct {
       handle: rawptr,              // TopoDS_Shape* (opaque pointer)
       feature_id: int,             // Which feature created this
       is_valid: bool,              // Shape validity check
   }
   ```

5. **Test Basic Operations**
   - [ ] Create 2D wire from sketch
   - [ ] Extrude wire to solid
   - [ ] Tessellate solid to mesh for rendering
   - [ ] Verify pentagon works!

---

### **Phase 2: Boolean Operations** (Week 2)
**Goal:** Robust pocket/cut operations

1. **Implement Boolean Difference**
   - [ ] Wrapper for `BRepAlgoAPI_Cut`
   - [ ] Test: Box with rectangular pocket
   - [ ] Test: Box with circular pocket

2. **Implement Boolean Union**
   - [ ] Wrapper for `BRepAlgoAPI_Fuse`
   - [ ] Test: Combine multiple solids

3. **Implement Boolean Intersection**
   - [ ] Wrapper for `BRepAlgoAPI_Common`

4. **Update Feature Tree**
   - [ ] Pocket feature uses OCCT boolean difference
   - [ ] Multiple extrudes combine via boolean union

---

### **Phase 3: Rendering Integration** (Week 2-3)
**Goal:** Render OCCT shapes with existing GPU pipeline

1. **Tessellation to Triangle Mesh**
   - [ ] Use `BRepMesh_IncrementalMesh` to generate mesh
   - [ ] Extract triangles, vertices, normals
   - [ ] Convert to existing `TriangleMeshGPU` format

2. **Adaptive Mesh Quality**
   - [ ] Linear deflection parameter (0.1mm for precision)
   - [ ] Angular deflection parameter (0.5° for smooth curves)

3. **Preserve Existing Rendering**
   - [ ] Keep `viewer_gpu_render_triangle_mesh()` unchanged
   - [ ] OCCT → TriangleMeshGPU conversion layer

---

### **Phase 4: Advanced Features** (Future)

1. **Fillet & Chamfer**
   - `BRepFilletAPI_MakeFillet` - Rounded edges
   - `BRepFilletAPI_MakeChamfer` - Beveled edges

2. **Shell & Offset**
   - `BRepOffsetAPI_MakeThickSolid` - Hollow parts

3. **STEP Import/Export**
   - `STEPControl_Reader` - Import .step files
   - `STEPControl_Writer` - Export .step files

4. **Constraint-Based Modeling**
   - Integrate OCCT constraints with existing sketch solver

---

## File Structure

```
src/core/geometry/occt/
├── occt_types.odin           # Base types, handles, opaque pointers
├── occt_modeling.odin        # Extrude, revolve, boolean ops
├── occt_mesh.odin            # B-Rep → triangle mesh conversion
├── occt_sketch.odin          # Sketch2D → OCCT Wire conversion
└── occt_io.odin              # STEP/IGES import/export (future)

src/features/
├── extrude/extrude_occt.odin    # Extrude using OCCT
├── pocket/pocket_occt.odin      # Pocket using OCCT booleans
└── revolve/revolve_occt.odin    # Revolve using OCCT
```

---

## OCCT FFI Example (Pseudo-code)

```odin
package occt

import "core:c"

// Opaque pointer types (OCCT uses handles)
TopoDS_Shape :: distinct rawptr
gp_Pnt :: distinct rawptr
gp_Vec :: distinct rawptr
gp_Ax2 :: distinct rawptr

// Foreign bindings to OCCT C++ API
foreign import occt_lib {
    "/opt/homebrew/lib/libTKernel.dylib",
    "/opt/homebrew/lib/libTKBRep.dylib",
    "/opt/homebrew/lib/libTKPrim.dylib",
}

@(default_calling_convention="c")
foreign occt_lib {
    // Point creation
    gp_Pnt_new :: proc(x, y, z: f64) -> gp_Pnt ---

    // Extrusion
    BRepPrimAPI_MakePrism_new :: proc(
        shape: TopoDS_Shape,
        vec: gp_Vec,
    ) -> TopoDS_Shape ---

    // Boolean difference
    BRepAlgoAPI_Cut_new :: proc(
        base: TopoDS_Shape,
        tool: TopoDS_Shape,
    ) -> TopoDS_Shape ---

    // Tessellation
    BRepMesh_IncrementalMesh :: proc(
        shape: TopoDS_Shape,
        deflection: f64,
        is_relative: bool,
    ) ---
}
```

---

## Migration Strategy

### Option A: **Big Bang** (Replace all at once)
- **Pros:** Clean break, no legacy code
- **Cons:** Risky, long downtime

### Option B: **Gradual** (Feature by feature) ⭐ RECOMMENDED
- **Pros:** Lower risk, incremental testing
- **Cons:** Temporary dual code paths

**Recommended Approach:**
1. Keep `SimpleSolid` temporarily
2. Add OCCT alongside (new `OCCTShape` type)
3. Convert features one by one:
   - ✅ Extrude → OCCT first
   - ✅ Pocket → OCCT second (needs booleans)
   - ✅ Revolve → OCCT third
4. Remove `SimpleSolid` once all features use OCCT

---

## Testing Checklist

### Basic Shapes
- [ ] Pentagon extrusion (current failure case!)
- [ ] Rectangle extrusion
- [ ] Circle extrusion
- [ ] Complex profile (10+ sides)

### Boolean Operations
- [ ] Box - rectangular pocket
- [ ] Box - circular pocket
- [ ] Cylinder - side pocket
- [ ] Multiple pockets in same solid

### Rendering
- [ ] Wireframe mode (edges only)
- [ ] Shaded mode (triangles with lighting)
- [ ] Mixed polygons (tri, quad, pentagon, etc.)

---

## Known Challenges

### 1. **C++ Interop**
OCCT is C++ only, no official C API.

**Solutions:**
- Use Odin's C++ FFI support (experimental)
- Create thin C wrapper layer
- Use existing C bindings (pythonocc has some)

### 2. **Memory Management**
OCCT uses reference counting (handles).

**Solutions:**
- Wrap handles in Odin structs with destructors
- Use `defer` for cleanup
- Track handle refcounts carefully

### 3. **Library Size**
OCCT is ~100MB of libraries.

**Solutions:**
- Link only needed modules (not all 30+)
- Dynamic linking (`.dylib`) to share between runs

---

## Performance Considerations

### B-Rep vs Mesh
- **B-Rep:** Exact, compact, slower to compute
- **Mesh:** Approximate, large, fast to render

**Strategy:**
- Store geometry as B-Rep (exact)
- Tessellate to mesh only for rendering
- Cache tessellated mesh until B-Rep changes

### Tessellation Quality
- **Coarse:** Fast, blocky curves
- **Fine:** Slow, smooth curves

**Parameters:**
- Linear deflection: 0.1mm (good for small parts)
- Angular deflection: 0.5° (smooth circles)

---

## References

- **OCCT Documentation:** https://dev.opencascade.org/doc/overview/html/
- **OCCT GitHub:** https://github.com/Open-Cascade-SAS/OCCT
- **FreeCAD OCCT Usage:** https://github.com/FreeCAD/FreeCAD
- **pythonocc (Python bindings):** https://github.com/tpaviot/pythonocc-core

---

## Next Steps

1. **You:** Fix Homebrew permissions and install OCCT
2. **Me:** Create initial Odin FFI bindings for core types
3. **Test:** Convert extrude feature to use OCCT
4. **Verify:** Pentagon extrusion works correctly!

---

**Expected Timeline:** 2-3 weeks for core integration, then iterative feature additions.

**Risk Level:** Medium (C++ interop complexity, but OCCT is battle-tested)

**Reward:** Professional-grade CAD kernel with exact geometry! 🎯
