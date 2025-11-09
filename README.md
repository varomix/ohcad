# OhCAD - Odin CAD System

A focused Part-Design style CAD kernel and 2D technical drawing system implemented in **Odin**.

## Project Status

🚧 **Early Development - Week 1** 🚧

Currently implementing the foundational architecture. See [Development Plan](docs/development_plan_weekly.md) for details.

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
- OpenGL 3.3+ capable graphics driver
- macOS, Linux, or Windows

### Quick Start

```bash
# Build the project
make

# Run the application
make run

# Run tests
make test

# Clean build artifacts
make clean
```

### Manual Build

```bash
# Build release version
odin build src -out:ohcad -o:speed

# Build debug version
odin build src -out:ohcad_debug -debug

# Run tests
odin test tests -all-packages
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

### Phase 1: Foundation (Weeks 1-4) ✅ In Progress
- [x] Project setup
- [ ] Core math library
- [ ] Geometry primitives
- [ ] B-rep topology
- [ ] Basic 3D viewer

### Phase 2: 2D Sketcher (Weeks 5-8)
- [ ] Sketch data model
- [ ] Constraint system
- [ ] 2D solver
- [ ] Sketch UI

### Phase 3: 3D Features (Weeks 9-12)
- [ ] Extrude/pad
- [ ] Boolean operations
- [ ] Revolve
- [ ] STL export

### Phase 4: Technical Drawing (Weeks 13-16) - **MVP Complete**
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
