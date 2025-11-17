# libslvs (SolveSpace) Integration Evaluation

**Date:** 2025-11-15
**Status:** ✅ Proof of Concept Complete

## Summary

libslvs is a **viable and recommended solution** for 2D sketch constraint solving in OhCAD.

## What We Accomplished

### 1. Built libslvs from Source ✅
- **Library:** `libs/libslvs.3.2.dylib` (396 KB, ARM64)
- **Header:** `libs/Include/slvs.h`
- **Build process:** CMake with mimalloc + Eigen dependencies
- **Complexity:** Medium (requires cmake, git submodules, but one-time setup)

### 2. Created Odin FFI Bindings ✅
- **File:** `tests/test_slvs_api.odin`
- **API Style:** High-level stateful API (much simpler than low-level)
- **Lines of code:** ~310 lines (including tests)
- **Bindings:** 12 core functions (add entities, constraints, solve, query)

### 3. Verified Functionality ✅
**Test 1: Simple 2D Constraints**
- Vertical constraint between two points
- Result: Points correctly aligned (5.0, 10.0) → (5.0, 20.0)

**Test 2: Constrained Rectangle**
- 4 points, 4 lines
- Horizontal/vertical constraints
- Fixed dimensions (20.0 x 10.0)
- Result: Perfect rectangle with correct dimensions

## Integration Complexity Assessment

### Difficulty Rating: ⭐⭐⭐ Medium (3/5)

| Aspect | Rating | Notes |
|--------|--------|-------|
| **API Quality** | ⭐⭐⭐⭐⭐ | Clean C API, excellent documentation |
| **Build Complexity** | ⭐⭐⭐ | Requires CMake + submodules (one-time) |
| **FFI Bindings** | ⭐⭐⭐⭐⭐ | Simple structs, no callback hell |
| **Runtime Integration** | ⭐⭐⭐⭐ | Needs DYLD_LIBRARY_PATH or install_name_tool |
| **Maintenance** | ⭐⭐⭐⭐ | Stable API, active project |

### Compared to Other Options

| Library | Language | C Bindings | Build | Difficulty | Scope |
|---------|----------|------------|-------|------------|-------|
| **libslvs** | C++ | ✅ Official | Medium | **⭐⭐⭐** | 2D/3D constraints |
| **PlaneGCS** | C++ | ❌ DIY | Medium | ⭐⭐⭐⭐ | 2D constraints only |
| **OpenCascade** | C++ | ⚠️ Partial | Hard | ⭐⭐⭐⭐⭐ | Full CAD kernel |
| **ManifoldCAD** | C++ | ✅ Official | Easy | ⭐⭐ | 3D booleans (you have this!) |

**Winner:** libslvs strikes the best balance for your use case.

## What libslvs Provides

### Entities
- ✅ Points (2D/3D)
- ✅ Lines, arcs, circles
- ✅ Workplanes
- ✅ Bezier curves

### Constraints (Partial List)
- ✅ Coincident, distance, angle
- ✅ Horizontal, vertical
- ✅ Parallel, perpendicular
- ✅ Tangent, equal radius
- ✅ Symmetric, midpoint
- ✅ And ~20 more!

### What It DOESN'T Provide
- ❌ 3D solid modeling (you have ManifoldCAD for this)
- ❌ Rendering (you have Metal shaders)
- ❌ UI widgets (you're building this)

**It's a perfect fit!** Constraint solving only, no overlap with your existing stack.

## Recommended Architecture

```
┌─────────────────────────────────────────────┐
│              OhCAD Application              │
└─────────────────────────────────────────────┘
                     │
        ┌────────────┼────────────┐
        │            │            │
        ▼            ▼            ▼
   ┌────────┐  ┌─────────┐  ┌──────────┐
   │ libslvs│  │Manifold │  │ Metal    │
   │ (2D)   │  │CAD (3D) │  │ Shaders  │
   └────────┘  └─────────┘  └──────────┘
   Constraints  Booleans    Rendering
```

**Your stack:**
1. **2D Sketching:** libslvs (constraint solving)
2. **3D Operations:** ManifoldCAD (booleans, extrude, revolve)
3. **Rendering:** Your existing Metal pipeline
4. **UI:** Your Odin code

Clean separation of concerns!

## Next Steps

### Immediate (To Use libslvs in OhCAD)

1. **Update Makefile** (add linker flags):
   ```makefile
   gpu: src/main_gpu.odin
       odin build src/main_gpu.odin \
           -file \
           -out:bin/ohcad_gpu \
           -extra-linker-flags:"-L/opt/homebrew/lib -Llibs -lslvs"
   ```

2. **Move bindings** from `tests/` to proper location:
   ```
   src/core/solver/slvs_bindings.odin  # FFI declarations
   src/core/solver/constraint_solver.odin  # High-level Odin wrapper
   ```

3. **Integrate with your Sketch type**:
   ```odin
   Sketch :: struct {
       entities: [dynamic]SketchEntity,
       constraints: [dynamic]Constraint,
       slvs_group: u32,  // NEW: libslvs group handle
       // ... existing fields
   }
   ```

4. **Add solve step** after user edits sketch:
   ```odin
   solve_sketch :: proc(sketch: ^Sketch) -> bool {
       // Convert your entities → libslvs entities
       // Convert your constraints → libslvs constraints
       // Call Slvs_SolveSketch()
       // Update your entity positions from solved params
   }
   ```

### Short Term (Week 13)

1. Implement constraint UI:
   - Right-click on entities → Add constraint menu
   - Visual feedback (dimension arrows, constraint icons)
   - Constraint list panel

2. Add common constraints:
   - Distance (point-point, point-line)
   - Angle
   - Parallel/perpendicular
   - Horizontal/vertical

3. Handle solver failures gracefully:
   - Display which constraints are conflicting
   - Allow user to delete problematic constraints

### Medium Term

1. Advanced constraints:
   - Tangency (line-arc, arc-arc)
   - Symmetry
   - Pattern constraints

2. Dimension driving:
   - Click dimension → Edit value → Re-solve

3. Fully-constrained detection:
   - Show DOF count to user
   - Visual indicator when sketch is fully constrained

## Comparison to Building Your Own

If you were to build a constraint solver from scratch:
- **Time:** 1-2 months minimum
- **Code:** 5,000+ lines
- **Complexity:** Numerical optimization (Levenberg-Marquardt, etc.)
- **Testing:** Weeks of debugging edge cases
- **Result:** Likely less robust than libslvs

**libslvs gives you 15 years of FreeCAD/SolveSpace battle-testing for free.**

## Final Recommendation

**✅ Proceed with libslvs integration**

**Reasons:**
1. Clean C API (proven to work with Odin)
2. Solves your exact problem (2D sketch constraints)
3. Doesn't overlap with your existing stack
4. One-time build complexity, then it "just works"
5. Much better than building your own solver
6. Much simpler than integrating OpenCascade

**Alternative considered but rejected:**
- OpenCascade: Too heavy, wrapper nightmare
- PlaneGCS: Would need custom C wrapper (more work than libslvs build)
- Custom solver: 1-2 months development time

**The libslvs route gives you professional constraint solving in days, not months.**

## Running the Tests

```bash
# Build
odin build tests/test_slvs_api.odin -file -out:tests/test_slvs

# Run
DYLD_LIBRARY_PATH=libs ./tests/test_slvs
```

**Output:**
```
✓ Test 1 (Simple 2D Distance): PASS
✓ Test 2 (Constrained Rectangle): PASS
✓ All tests passed!
```

## Files Added

```
libs/
├── libslvs.3.2.dylib       # 396 KB shared library (ARM64)
├── libslvs.1.dylib -> libslvs.3.2.dylib
├── libslvs.dylib -> libslvs.1.dylib
└── Include/
    └── slvs.h              # C API header

tests/
└── test_slvs_api.odin      # Test harness (310 lines)
```

## License

**libslvs:** GPL 3.0 (same as SolveSpace)

**Important:** If you distribute OhCAD, GPL requires you to:
- Open-source OhCAD, OR
- Contact SolveSpace team for commercial licensing

For personal/internal use: No restrictions.

## References

- **SolveSpace:** https://solvespace.com
- **GitHub:** https://github.com/solvespace/solvespace
- **C API Docs:** `/tmp/solvespace/exposed/DOC.txt`
- **C Example:** `/tmp/solvespace/exposed/CDemo.c`

---

**Conclusion:** libslvs is the right choice for OhCAD's 2D constraint solving needs.
