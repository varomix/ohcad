# OhCAD - Odin CAD System

A focused Part-Design style CAD kernel and 2D technical drawing system implemented in **Odin**.

## Project Status

🎉 **Week 12.2 Complete - Constraint Editing with Inline Text Widget!** 🎉

Full parametric CAD workflow with editable constraints and live solver updates!

**Current Features:**
- ✅ 2D parametric sketching (lines, circles, arcs)
- ✅ Constraint solver (12 constraint types with visual feedback)
- ✅ **Constraint editing** - Double-click dimensions to edit values inline
- ✅ 3D extrusion and revolution with parametric updates
- ✅ **Boolean operations** (cut/pocket with OCCT - OpenCascade Technology)
- ✅ Face selection and sketch-on-face workflow
- ✅ SDL3 GPU rendering (Metal on macOS)
- ✅ Multi-touch gestures (trackpad support)
- ✅ Feature tree with dependency tracking
- ✅ Undo/redo system (50 command history)
- ✅ Professional UI with toolbar, properties panel, feature tree, and status bar
- ✅ Text rendering with fontstash (BigShoulders font)
- ✅ Shaded rendering with Phong lighting
- ✅ STL export for 3D printing
- ✅ Hover highlights and closed shape visualization

See [Development Plan](docs/development_plan_weekly.md) for complete roadmap and [SDL3 GPU Migration Summary](docs/sdl3_gpu_migration_summary.md) for technical details.

---

## Features (Target MVP)

- **2D Parametric Sketcher** with constraint solving
- **3D Features**: Extrude (pad), pocket (cut), revolve, basic fillet/chamfer
- **Parametric Feature Tree** with replay/regeneration
- **B-rep Topology** for robust solid modeling
- **Technical Drawing**: Orthographic views, hidden line removal, dimensions
- **File Export**: STL, SVG, PDF

## Why Odin?

- Explicit memory layout, no GC pauses
- Easy C interop for reusing libraries
- Simple syntax for systems programming
- Excellent built-in packages (math, graphics, testing, etc.)

---

## Project Structure

```
mix_OhCAD/
├── src/
│   ├── main.odin              # Main entry point
│   ├── core/
│   │   ├── math/              # CAD-specific math utilities
│   │   ├── geometry/          # 2D/3D geometric primitives
│   │   ├── topology/          # B-rep data structures
│   │   └── kernel/            # CSG/B-rep operations (future)
│   ├── features/
│   │   ├── sketch/            # 2D sketching system
│   │   ├── extrude/           # Extrude feature (future)
│   │   ├── revolve/           # Revolve feature (future)
│   │   └── constraints/       # Constraint solver (future)
│   ├── io/
│   │   ├── stl/               # STL import/export
│   │   ├── svg/               # SVG export (future)
│   │   └── step/              # STEP I/O (future)
│   └── ui/
│       ├── viewer/            # 3D OpenGL viewer (future)
│       └── drawing/           # Technical drawing (future)
├── tests/                     # Unit and integration tests
├── docs/                      # Documentation
├── examples/                  # Example models (future)
└── Makefile                   # Build system
```

---

## Building

### Prerequisites

- [Odin Compiler](https://odin-lang.org/docs/install/) (latest version)
- SDL3 (for GPU-accelerated rendering)
- Metal-capable macOS system (for Metal backend)
- OpenGL 3.3+ (for legacy GLFW version)

### Quick Start

```bash
# Build SDL3 GPU version (recommended)
make gpu

# Run SDL3 GPU application
make run-gpu

# Build GLFW version (legacy backup)
make

# Run GLFW application
make run

# Run tests
make test

# Clean build artifacts
make clean
```

### Manual Build

```bash
# SDL3 GPU version (recommended)
odin build src/main_gpu.odin -file -out:bin/ohcad_gpu -debug

# GLFW version (legacy)
odin build src/main.odin -file -out:bin/ohcad -debug

# Run tests
odin test tests -all-packages
```

### Shader Compilation (SDL3 GPU)

```bash
cd src/ui/viewer/shaders
./build_shaders.sh
# Generates line_shader.metallib (~15KB)
```

---

## Development

### Week-by-Week Plan

See the [Development Plan](docs/development_plan_weekly.md) for the complete 16-week MVP roadmap.

**Current Week:** Week 1 - Project Setup & Core Math

### Architecture

See the [High-Level Design](docs/odin_cad_high_level_design.md) for detailed architecture and design decisions.

### Built-in Packages Reference

See [Odin Built-in Packages](docs/odin_builtin_packages.md) for a catalog of Odin packages we're leveraging.

---

## Contributing

This is an educational project focused on learning CAD system architecture and Odin programming.

### Code Style

- Follow Odin naming conventions (`snake_case` for functions, `PascalCase` for types)
- Use `f64` for all geometric calculations (CAD precision)
- Document complex algorithms and geometric predicates
- Write unit tests for all math and geometry functions

### Testing

```bash
# Run all tests
make test

# Run specific test package
odin test tests/math -all-packages
```

---

## License

MIT License - See LICENSE file for details.

---

## Roadmap

### Phase 1: Foundation (Weeks 1-4) ✅ COMPLETE
- [x] Project setup
- [x] Core math library (57/57 tests passing)
- [x] Geometry primitives (2D/3D)
- [x] B-rep topology (handle-based system)
- [x] Basic 3D viewer (GLFW + OpenGL)

### Phase 2: 2D Sketcher (Weeks 5-8) ✅ COMPLETE
- [x] Sketch data model with coordinate transforms
- [x] Interactive sketch tools (line, circle, select)
- [x] Constraint system (16 constraint types)
- [x] Levenberg-Marquardt constraint solver
- [x] Visual constraint feedback (icons + dimensions)
- [x] Profile detection for extrusion

### Phase 3: 3D Features (Weeks 9-12) 🔄 IN PROGRESS
- [x] **Week 9:** Extrude/pad feature with parametric updates ✅
- [x] **Week 9.5:** SDL3 GPU migration + multi-touch gestures ✅
- [x] **Week 9.6:** UI framework & toolbar integration ✅
- [ ] **Week 10.5:** Boolean operations (cut/pocket)
- [ ] **Week 11:** Revolve feature
- [ ] **Week 12:** STL export & basic fillet

### Phase 4: Technical Drawing (Weeks 13-16) - **MVP Target**
- [ ] Orthographic projection
- [ ] Hidden line removal
- [ ] Dimensioning
- [ ] SVG/PDF export

### Phase 5: Polish (Weeks 17+)
- [ ] Boolean robustness
- [ ] Advanced fillets
- [ ] STEP I/O
- [ ] NURBS surfaces

---

## References

- **SolveSpace** - Constraint solver reference
- **BRL-CAD** - CSG concepts
- **Open CASCADE** - B-rep algorithms
- **Odin Documentation** - https://odin-lang.org/docs/

---

Built with ❤️ and Odin
