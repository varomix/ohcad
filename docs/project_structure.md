# OhCAD Project Structure

Generated: Week 1 - Initial Setup

## Directory Tree

```
mix_OhCAD/
├── .gitignore                          # Git ignore patterns
├── Makefile                            # Build system
├── README.md                           # Project documentation
│
├── bin/                                # Build outputs (gitignored)
│   └── ohcad                          # Compiled executable
│
├── docs/                               # Documentation
│   ├── odin_cad_high_level_design.md  # Architecture document
│   ├── development_plan_weekly.md      # 16-week development plan
│   └── odin_builtin_packages.md        # Odin packages reference
│
├── src/                                # Source code
│   ├── main.odin                      # Main entry point
│   │
│   ├── core/                          # Core modules
│   │   ├── math/                      # CAD-specific math utilities
│   │   │   └── math.odin             # Tolerance, is_near, safe_normalize
│   │   ├── geometry/                  # Geometric primitives
│   │   │   └── primitives.odin       # Line2, Circle2, Arc2, Plane, etc.
│   │   └── topology/                  # B-rep topology
│   │       └── brep.odin             # Vertex, Edge, Face, Shell, Solid
│   │
│   ├── features/                      # CAD features
│   │   └── sketch/                    # 2D sketching
│   │       └── sketch.odin           # Sketch2D, constraints
│   │
│   ├── io/                            # Import/Export
│   │   └── stl/                       # STL file format
│   │       └── stl.odin              # STL import/export (placeholder)
│   │
│   └── ui/                            # User interface (future)
│       ├── viewer/                    # 3D viewer (Week 3)
│       └── drawing/                   # Technical drawing (Week 13)
│
├── tests/                              # Unit tests
│   └── math/                          # Math utilities tests
│       └── math_test.odin            # Tests for is_near, is_zero, etc.
│
└── examples/                           # Example models (future)
    └── simple_part.json               # Example parametric part
```

## Module Dependencies

```
main.odin
  └─> core/math
  └─> core/geometry (→ core/math)
  └─> core/topology (→ core/math)
  └─> features/sketch (→ core/math, core/geometry)
  └─> io/stl (→ core/topology)
```

## Package Structure

### Core Packages

**`ohcad_math`** - `/src/core/math/`
- Type aliases for Odin's `dvec2`, `dvec3`, `dmat4`
- CAD tolerance management
- Robust floating-point comparisons
- Safe geometric operations

**`ohcad_geometry`** - `/src/core/geometry/`
- 2D primitives: Line2, Circle2, Arc2
- 3D primitives: Plane, Sphere, Cylinder
- Geometric evaluation functions

**`ohcad_topology`** - `/src/core/topology/`
- Handle-based ID system
- B-rep structures: Vertex, Edge, Face, Shell, Solid
- Memory management for topology

### Feature Packages

**`ohcad_sketch`** - `/src/features/sketch/`
- Sketch2D data structure
- Constraint types (Coincident, Distance, Angle, etc.)
- Sketch initialization and lifecycle

### I/O Packages

**`ohcad_io_stl`** - `/src/io/stl/`
- STL binary/ASCII export (Week 12)
- STL import

### Test Packages

**`test_math`** - `/tests/math/`
- Unit tests for tolerance functions
- Tests for geometric utilities
- Validation of math operations

## External Dependencies

### Odin Built-in Packages Used

1. **`core:math/linalg/glsl`** - Vector/matrix operations
2. **`core:testing`** - Unit testing framework
3. **`core:log`** - Structured logging
4. **`core:fmt`** - Formatted output
5. **`core:os`** - File I/O (future)
6. **`core:encoding/json`** - JSON serialization (future)
7. **`vendor:glfw`** - Windowing (Week 3)
8. **`vendor:OpenGL`** - 3D rendering (Week 3)

See `/docs/odin_builtin_packages.md` for complete reference.

## File Naming Conventions

- **Source files**: `snake_case.odin`
- **Package names**: `ohcad_module` (e.g., `ohcad_math`, `ohcad_geometry`)
- **Test files**: `module_test.odin` (e.g., `math_test.odin`)
- **Constants**: `SCREAMING_SNAKE_CASE`
- **Types**: `PascalCase`
- **Functions**: `snake_case`

## Build Outputs

- **Release**: `bin/ohcad` (optimized)
- **Debug**: `bin/ohcad_debug` (with symbols)
- **Tests**: Run in-place with `odin test`

## What's Implemented (Week 1)

✅ **Complete:**
- [x] Project directory structure
- [x] Build system (Makefile)
- [x] Main entry point
- [x] Core math module skeleton
- [x] Geometry primitives skeleton
- [x] Topology B-rep structures
- [x] Sketch data structures
- [x] Basic unit tests
- [x] Documentation (README, design docs)
- [x] Git configuration

⏳ **In Progress:**
- [ ] CAD-specific math utilities (Week 1 remaining tasks)
- [ ] Geometric predicates
- [ ] Test coverage

📋 **Planned:**
- [ ] 3D viewer (Week 3)
- [ ] Constraint solver (Weeks 6-7)
- [ ] Feature operations (Weeks 9-12)
- [ ] Technical drawing (Weeks 13-16)

## Next Steps (Week 1 Remaining)

1. ✅ Create project structure ← **DONE**
2. **Implement CAD-specific geometric utilities:**
   - `project_point_on_plane`
   - `line_line_intersect_2d`
   - `closest_point_on_line`
3. **Expand test coverage**
4. **Verify build and test system**

---

*Last updated: Week 1, Day 1*
*Status: Foundation phase - On track* ✓
