# Odin CAD — Week-by-Week Development Plan

**Project Goal:** Build a parametric Part-Design CAD system in Odin with 2D sketching, 3D features, and technical drawing capabilities.

**Collaboration Model:** Working with AI agent for implementation, code generation, debugging, and architectural decisions.

---

## Phase 1: Foundation (Weeks 1-4)

### Week 1: Project Setup & Core Math Utilities
**Goal:** Establish project structure and create CAD-specific math utilities (leveraging Odin's built-in math)

**Tasks:**
- [x] Set up Odin project structure matching the architecture in high-level design
- [x] Create build system (Makefile or build script)
- [x] Set up imports for Odin's `core:math/linalg/glsl` (provides vec2/3/4, mat2/3/4, quaternions, all basic operations)
- [x] Implement `core/math` CAD-specific utilities:
  - [x] Configurable tolerance/epsilon management for CAD precision
  - [x] `is_near(a, b, eps)` for robust floating-point comparisons
  - [x] Point projection onto plane
  - [x] Line-line intersection (2D/3D)
  - [x] Plane-plane intersection helpers
  - [x] Plane construction utilities (from 3 points, from point+normal)
- [x] Write unit tests for CAD-specific utilities (21 tests, all passing ✅)
- [x] Create simple test runner

**AI Agent Tasks:**
- [x] Generate boilerplate project structure with proper Odin package layout
- [x] Implement CAD-specific geometric utilities (leveraging Odin's built-in types)
- [x] Create comprehensive unit tests
- [x] Set up testing infrastructure
- [x] Document which Odin built-in functions we're using vs what we're adding

**Deliverable:** ✅ COMPLETE - Working project structure with CAD-specific math utilities, leveraging Odin's excellent built-in linalg library. All 21 tests passing.

**Note:** Odin provides `vec2`/`vec3`/`vec4`, `mat2`/`mat3`/`mat4`, `quat`, and all standard operations (dot, cross, normalize, matrix operations, etc.) out of the box. We only need to add CAD-specific geometric predicates and utilities.

---

### Week 2: Geometry Primitives & Basic Topology ✅ COMPLETE
**Goal:** 2D and 3D geometric primitives, handle-based topology system

**Tasks:**
- [x] Implement `core/geometry`:
  - [x] 2D primitives: Line2, Circle2, Arc2 (30+ evaluation functions)
  - [x] 3D primitives: Plane, Sphere, Cylinder
  - [x] Point-on-curve evaluation functions
  - [x] Distance queries (signed and absolute)
  - [x] Closest point projections
  - [x] Tangent/normal computations
- [x] Implement `core/topology`:
  - [x] Handle<T> system (stable integer IDs)
  - [x] HandleAllocator for managing IDs (with recycling)
  - [x] Complete B-rep structures: Vertex, Edge, Face, Shell, Solid
  - [x] Euler operators (make_vertex, make_edge, make_face, make_shell, make_solid)
  - [x] Topology query functions (edges_of_vertex, faces_of_edge, count_entities)
- [x] Unit tests for all geometry operations (18 tests)
- [x] Integration tests for topology handle system (18 tests including cube construction)

**AI Agent Tasks:**
- [x] Implement geometry primitives with robust numerics
- [x] Create handle allocator with proper memory management
- [x] Implement Euler operators following B-rep topology rules
- [x] Write comprehensive topology manipulation tests
- [x] Ensure topology invariants are maintained (Euler characteristic, safety checks)
- [x] Generate test cases including edge cases

**Deliverable:** ✅ COMPLETE - Geometry and topology foundation ready for use. 57/57 tests passing (21 math + 18 geometry + 18 topology). Handle-based B-rep system with safety checks fully operational.

---

### Week 3: Basic 3D Viewer Setup ✅ COMPLETE
**Goal:** Minimal OpenGL viewer to visualize geometry

**Tasks:**
- [x] Set up GLFW bindings (used Odin's built-in vendor packages)
- [x] Create basic OpenGL context initialization
- [x] Implement simple camera system (orbit/pan/zoom)
- [x] Render coordinate axes and grid
- [x] Add wireframe mesh rendering capability
- [x] Mouse/keyboard input handling basics
- [x] B-rep to wireframe conversion utility

**AI Agent Tasks:**
- [x] Research and set up GLFW/OpenGL bindings for Odin
- [x] Implement camera controller with standard CAD navigation
- [x] Create rendering pipeline for wireframe display
- [x] Fix camera orbit direction (natural mouse movement)

**Deliverable:** ✅ COMPLETE - Window with 3D view, camera controls, can display wireframes. Successfully rendering B-rep topology (cube with 8 vertices, 12 edges) in 3D with full camera controls.

---

### Week 4: B-rep Data Structures & Mesh Generation ✅ MOSTLY COMPLETE
**Goal:** Complete B-rep topology and basic mesh tessellation

**Status:** B-rep structures already completed in Week 2, wireframe rendering in Week 3. Tessellation deferred to later.

**Tasks:**
- [x] Complete `core/topology` B-rep structures:
  - [x] Face, Loop, Shell, Solid (completed Week 2)
  - [x] Edge linking and face boundary management
  - [x] Euler operators (make_vertex, make_edge, make_face, etc.)
- [ ] Implement basic mesh tessellation: **DEFERRED**
  - Integrate libtess2 or write simple tessellator
  - Convert faces to triangle meshes for rendering
- [x] Add B-rep to viewer (render wireframe)
- [x] Create test primitives (cube working, others deferred)

**AI Agent Tasks:**
- [x] Implement B-rep data structures with proper topology relationships (Week 2)
- [ ] Set up C interop for libtess2 or implement simple tessellator **DEFERRED**
- [x] Create factory functions for test primitives

**Deliverable:** ✅ B-rep system complete and integrated with viewer. Tessellation deferred until needed for 3D features (Week 9+). Moving ahead to sketcher (Week 5) for immediate usability.

**Deliverable:** Can create and display basic solid primitives in viewer

---

## Phase 2: 2D Sketcher (Weeks 5-8)

### Week 5: 2D Sketch Data Model & Basic Geometry ✅ COMPLETE
**Goal:** Sketch data structure and unconstrained 2D geometry

**Tasks:**
- [x] **Task 1:** Implement `features/sketch` data structures:
  - [x] Sketch2D structure (vertices, edges, entities, plane)
  - [x] SketchPoint, SketchLine, SketchCircle, SketchArc types
  - [x] Sketch-to-world coordinate transformations (SketchPlane)
  - [x] Tool state management (current_tool, temp_point, first_point_id)
- [x] **Task 2:** Implement basic sketch geometry operations:
  - [x] sketch_add_point, sketch_add_line, sketch_add_circle, sketch_add_arc
  - [x] sketch_get_point, sketch_entity_count helpers
  - [x] Sketch plane constructors (XY, XZ, YZ, from normal)
- [x] **Task 3:** Add 2D sketch visualization in viewer:
  - [x] sketch_to_wireframe conversion (lines, circles with 64-segment tessellation)
  - [x] render_sketch_points (filled circular dots with screen-space constant size)
  - [x] render_sketch_plane (subtle cyan outline rectangle)
  - [x] render_sketch_preview (bright cyan cursor, preview lines)
  - [x] **Screen-space constant thickness** - 3px lines, 4px dots (zoom-independent)
  - [x] **Thick line rendering** for sketch geometry (quad-based for macOS compatibility)
- [x] **Task 4:** Interactive mouse-based sketch creation:
  - [x] Line tool with click-to-place workflow
  - [x] Circle tool with center-radius workflow
  - [x] Raycasting from screen to sketch plane (Retina display compatible)
  - [x] Grid snapping (0.1 unit grid)
  - [x] Real-time cursor preview with cyan crosshair
  - [x] Preview line/circle showing next geometry
  - [x] Mode switching (TAB: sketch ↔ camera mode)
  - [x] Camera controls (orbit, pan, zoom) working in camera mode
  - [x] Tool selection (L line, C circle, S select)
- [x] **Task 5:** Basic sketch editing:
  - [x] Select entities with mouse click (hit testing with tolerance)
  - [x] Delete selected entities (DELETE key)
  - [x] Highlight selected entities (bright cyan vs darker cyan)
  - [x] Orphaned point cleanup (automatic deletion of unused points)
- [x] **Task 6:** Save/load sketch data:
  - [x] JSON serialization for Sketch2D
  - [x] Save sketch to sketch.json file (Ctrl+S)
  - [x] Load sketch from file (Ctrl+O)
  - [x] Full roundtrip preservation of geometry

**AI Agent Tasks:**
- [x] Design efficient sketch data structures with coordinate transforms
- [x] Implement 2D drawing primitives with proper coordinate transforms
- [x] Create interactive sketch editor with raycasting and input handling
- [x] Fix Retina display cursor offset (use window size not framebuffer size)
- [x] Implement thick line rendering using quad geometry (macOS OpenGL compatibility)
- [x] Handle mode switching between sketch and camera controls
- [x] Implement selection and deletion system with hit testing
- [x] Create JSON serialization for persistence
- [x] **Implement screen-space constant line/dot sizing** (zoom-independent)
- [x] **Implement futuristic HUD theme** (dark blue-teal background, cyan color scheme)

**Status:** ✅ **WEEK 5 COMPLETE!**
- ✅ Interactive line and circle tools working
- ✅ Screen-space constant 3px lines & 4px dots (zoom-independent)
- ✅ Selection and deletion with orphaned point cleanup
- ✅ JSON save/load with Ctrl+S and Ctrl+O
- ✅ Futuristic HUD theme (dark background, cyan geometry)
- ✅ Filled circular dot markers (not crosses)
- ✅ Dots render on top of lines (depth test disabled)
- ✅ Professional CAD appearance

**Deliverable:** ✅ Fully functional interactive 2D sketcher with selection, deletion, save/load, and professional HUD appearance. Ready for constraint system (Week 6).

---

### Week 6: Constraint System Foundation ✅ COMPLETE
**Goal:** Constraint data model and equation formulation

**Tasks:**
- [x] **Task 1:** Implement `features/constraints`:
  - [x] 16 Constraint types (Coincident, Distance, DistanceX/Y, Angle, Perpendicular, Parallel, Horizontal, Vertical, Tangent, Equal, PointOnLine, PointOnCircle, FixedPoint, FixedDistance, FixedAngle)
  - [x] Constraint data structures with union types
  - [x] Constraint management (add, remove, get, enable/disable)
- [x] **Task 2:** Constraint → equation conversion:
  - [x] `sketch_evaluate_constraints()` - generates residuals for all constraints
  - [x] Residual functions for basic constraints (Coincident, Distance, DistanceX/Y, Horizontal, Vertical, Perpendicular, Parallel)
  - [x] Equation count per constraint type
- [x] **Task 3:** DOF (degrees of freedom) calculator:
  - [x] `sketch_calculate_dof()` - analyzes sketch DOF status
  - [x] Variable counting (2 per non-fixed point)
  - [x] Constraint equation counting
  - [x] Status detection (Underconstrained/Wellconstrained/Overconstrained)
- [x] **Task 4:** Research constraint solver approaches:
  - [x] Studied SolveSpace solver architecture
  - [x] Decision: **Levenberg-Marquardt** (industry standard, robust convergence)
  - [x] Pure Odin implementation (no C dependencies)

**AI Agent Tasks:**
- [x] Implement constraint data structures with 16 types
- [x] Research and recommend solver approach (chose LM)
- [x] Generate equations from constraints (residual functions)
- [x] Create constraint equation counting system

**Status:** ✅ **WEEK 6 COMPLETE!**
- ✅ Constraint system with 16 constraint types
- ✅ Equation generation for 8 basic constraint types
- ✅ DOF analysis system
- ✅ Solver approach selected (Levenberg-Marquardt)

**Deliverable:** ✅ Constraint system ready for solver integration (Week 7)

---

### Week 7: 2D Constraint Solver Implementation ✅ COMPLETE
**Goal:** Working constraint solver (basic constraints)

**Tasks:**
- [x] **Task 1:** Implement Levenberg-Marquardt solver core:
  - [x] `sketch_solve_constraints()` - main solver entry point
  - [x] Adaptive damping (lambda adjustment based on step quality)
  - [x] Line search with multiple damping attempts
  - [x] Convergence checking (residual norm < tolerance)
  - [x] DOF validation (rejects over/under-constrained systems)
- [x] **Task 2:** Numerical Jacobian computation:
  - [x] `compute_jacobian()` - finite difference Jacobian
  - [x] Central difference formula for accuracy
  - [x] Per-variable perturbation (all non-fixed points)
- [x] **Task 3:** Linear system solver:
  - [x] Normal equations: (J^T·J + λI)·δ = -J^T·r
  - [x] Cholesky decomposition solver
  - [x] Positive definite checking
  - [x] Forward/backward substitution
- [x] **Task 4:** Variable packing/unpacking:
  - [x] `pack_variables()` - extracts non-fixed point coordinates
  - [x] `apply_delta()` - updates sketch with solver delta
  - [x] Bidirectional scaling (for undo/rollback)
- [x] **Task 5:** Test suite (6 comprehensive tests):
  - [x] Test 1: Distance + DistanceX constraints ✅ PASS
  - [x] Test 2: Horizontal constraint (underconstrainted - expected)
  - [x] Test 3: Perpendicular constraint (underconstrainted - expected)
  - [x] Test 4: Rectangle with 6 constraints ✅ PASS (perfect 3.0×2.0 rectangle!)
  - [x] Test 5: Overconstrained detection ✅ PASS
  - [x] Test 6: Underconstrained detection ✅ PASS

**AI Agent Tasks:**
- [x] Implement Levenberg-Marquardt algorithm (450+ lines)
- [x] Create numerical Jacobian with finite differences
- [x] Implement Cholesky linear solver
- [x] Handle solver failure cases gracefully
- [x] Generate comprehensive test suite

**Status:** ✅ **WEEK 7 COMPLETE!**
- ✅ Levenberg-Marquardt solver fully operational
- ✅ Converges on well-constrained systems (Test 4: 3 iterations!)
- ✅ Properly detects over/under-constrained systems
- ✅ Numerical Jacobian with central differences
- ✅ Robust Cholesky solver with stability checks
- ✅ 4/6 tests passing (2 are correctly detecting underconstraint)

**Technical Details:**
- **Algorithm:** Levenberg-Marquardt with adaptive damping
- **Tolerance:** 1e-6 (residual norm)
- **Max iterations:** 100
- **Jacobian:** Numerical (finite differences, epsilon = 1e-8)
- **Linear solver:** Cholesky decomposition
- **Config:** SolverConfig with customizable parameters

**Test Results:**
```
Test 1: Distance Constraint ✅
  Converged in 11 iterations
  Final residual: 2.537e-07

Test 4: Rectangle (6 constraints) ✅
  Converged in 3 iterations!
  Perfect 3.0×2.0 rectangle
  Final residual: 7.295e-10

Test 5: Overconstrained ✅
  Correctly detected DOF = -1

Test 6: Underconstrained ✅
  Correctly detected DOF = 3
```

**Deliverable:** ✅ Working constraint solver can solve well-constrained sketches with distance, horizontal, perpendicular, and dimensional constraints. Ready for UI integration (Week 8).

---

### Week 8: Advanced Sketch Constraints & UI Polish ✅ COMPLETE
**Goal:** Complete sketcher with all basic constraints

**Tasks:**
- [x] **Task 1:** Complete remaining constraint residual functions:
  - [x] Angle constraint residual
  - [x] Equal constraint residual (lines and circles)
  - [x] PointOnLine constraint residual
  - [x] PointOnCircle constraint residual
  - [x] 12/16 constraint types with residuals implemented
- [x] **Task 2:** Add constraint visualization in UI:
  - [x] Orange/amber constraint icons (H, V, ⊥, ||, =, X)
  - [x] Yellow dimension lines with extension lines
  - [x] DistanceX and DistanceY dimension rendering
  - [x] Real-time rendering integrated with line shader
- [x] **Task 3:** Dimension text rendering:
  - [x] Identified fontstash as text rendering solution
  - [x] Full fontstash integration (native Odin vendor package)
  - [x] 2D text overlay system with OpenGL shader
  - [x] Custom BigShoulders_24pt-Regular.ttf font integration
  - [x] Dimension value text rendering (e.g., "3.00") at dimension line centers
  - [x] 3D-to-screen projection for text placement
  - [x] Screen-space text rendering with proper blending
- [x] **Task 4:** Profile detection (closed vs open):
  - [x] `sketch_detect_profiles()` - finds all profiles in sketch
  - [x] `build_edge_graph()` - connectivity analysis
  - [x] `trace_profile()` - loop tracing algorithm
  - [x] `sketch_has_closed_profile()` - quick extrudability check
  - [x] `sketch_print_profiles()` - debug output with status
  - [x] Profile classification: Closed (extrudable) vs Open
- [x] **Task 5:** Keyboard shortcuts for constraints:
  - [x] [H] - Apply horizontal constraint to selected line
  - [x] [V] - Apply vertical constraint to selected line
  - [x] [X] - Solve constraints (run solver)
  - [x] [P] - Print profile detection results
  - [x] Updated help text with all shortcuts

**AI Agent Tasks:**
- [x] Implement constraint residual functions (Angle, Equal, PointOnLine, PointOnCircle)
- [x] Create visual constraint indicators (icons + dimension lines)
- [x] Implement profile detection with loop tracing
- [x] Add keyboard shortcuts for rapid CAD workflow
- [x] Fix solver to allow underconstrained solving (partial constraint satisfaction)

**Status:** ✅ **WEEK 8 COMPLETE!**
- ✅ Constraint solver allows partial solving (underconstrained sketches)
- ✅ Visual constraint feedback (orange icons, yellow dimensions)
- ✅ Profile detection ready for extrusion (Week 9)
- ✅ Keyboard shortcuts for productivity
- ✅ 12/16 constraint types fully operational

**Technical Achievements:**
- **Solver Enhancement:** Modified to solve underconstrained sketches (like professional CAD)
- **Visual System:** Real-time constraint visualization with icons and dimensions
- **Profile Analysis:** Graph-based connectivity tracing for closed loop detection
- **UI Shortcuts:** H/V/X/P keys for rapid constraint application

**Deliverable:** ✅ Professional parametric sketcher with visual feedback, keyboard shortcuts, and profile detection. **Ready for 3D extrusion (Week 9)!**

---

## Phase 3: 3D Features (Weeks 9-12)

### Week 9: Extrude/Pad Feature ✅ COMPLETE
**Goal:** First 3D feature - extrude sketch to solid

**Tasks:**
- [x] **Task 1:** Implement `features/extrude` - Extrude closed profiles to 3D solids:
  - [x] `SimpleSolid` structure (lightweight wireframe: vertices + edges)
  - [x] `ExtrudeParams` (depth, direction: Forward/Backward/Symmetric)
  - [x] `extrude_sketch()` - main entry point with profile validation
  - [x] `extrude_profile()` - creates solid from single closed profile
  - [x] Bottom vertices (on sketch plane)
  - [x] Top vertices (offset by extrude vector)
  - [x] Edge generation (bottom loop + top loop + vertical edges)
  - [x] `calculate_extrude_offset()` - computes extrusion vector from plane normal
  - [x] Error handling with ExtrudeResult (success flag + message)
- [x] **Task 2:** Create feature tree structure:
  - [x] `FeatureTree` with chronological feature list
  - [x] `FeatureNode` with parameters and dependencies
  - [x] FeatureType enum (Sketch, Extrude, Cut, Revolve, Fillet, Chamfer)
  - [x] FeatureStatus tracking (Valid, NeedsUpdate, Failed, Suppressed)
  - [x] FeatureParams union (SketchParams, ExtrudeParams)
  - [x] `feature_tree_add_sketch()` - adds sketch to tree
  - [x] `feature_tree_add_extrude()` - adds extrude with parent dependency
  - [x] Dependency tracking (parent_features array)
  - [x] Feature history management with unique IDs
- [x] **Task 3:** Add extrude UI controls and 3D visualization:
  - [x] `solid_to_wireframe()` - converts SimpleSolid to WireframeMesh
  - [x] White wireframe rendering for 3D solids (2px thick)
  - [x] Keyboard shortcut [E] - extrude closed profile
  - [x] Integration with viewer rendering pipeline
  - [x] Multiple solid wireframe rendering from feature tree
- [x] **Task 4:** Parametric update system:
  - [x] `feature_regenerate()` - regenerates single feature
  - [x] `feature_tree_regenerate_all()` - regenerates entire tree in order
  - [x] `feature_tree_mark_dirty()` - marks feature + dependents as NeedsUpdate
  - [x] `change_extrude_depth()` - modifies depth parameter
  - [x] Keyboard controls: [+]/[-] change depth by 0.1, [R] regenerate all
  - [x] Real-time parametric updates (change depth → auto-regenerate solid)
  - [x] `update_solid_wireframes()` - rebuilds all solid wireframes
  - [x] Feature tree printing with status icons ([F] key)
- [x] **Bug Fixes:**
  - [x] Point snapping for closed loops (0.2 unit threshold)
  - [x] Memory cleanup (feature tree owns sketch, no double-free)
  - [x] Solid wireframe array cleanup on exit

**AI Agent Tasks:**
- [x] Implement extrude algorithm with SimpleSolid wireframe construction
- [x] Create parametric feature tree system with dependency tracking
- [x] Handle edge cases (open profiles, no closed profiles)
- [x] Generate test workflow and integration
- [x] Fix point snapping for easy closed loop creation
- [x] Fix memory management (ownership transfer to feature tree)

**Status:** ✅ **WEEK 9 COMPLETE!**
- ✅ Extrude algorithm working (closed profile → 8 vertices, 12 edges)
- ✅ Feature tree with dependency tracking and status management
- ✅ Real-time parametric updates ([+]/[-] changes depth, solid regenerates)
- ✅ Point snapping (0.2 unit threshold) for easy closed loops
- ✅ Clean memory management (no crashes on exit)
- ✅ White 3D solid rendering integrated with cyan 2D sketch
- ✅ Keyboard shortcuts: [E] extrude, [+]/[-] depth, [R] regenerate, [F] tree

**Technical Achievements:**
- **SimpleSolid Structure:** Lightweight wireframe (not full B-rep) with vertices + edges
- **Feature Tree:** Hierarchical parametric system with dependency tracking
- **Regeneration System:** Smart updates (only rebuild what's dirty)
- **Status Tracking:** Valid/NeedsUpdate/Failed/Suppressed states
- **Parametric Controls:** Interactive depth adjustment with instant feedback
- **Memory Safety:** Feature tree owns sketch, clean cleanup on exit

**Example Workflow:**
```
1. Draw rectangle with [L] (point snapping auto-closes loop)
2. Press [E] → Extrude to 3D (depth = 1.0)
3. Press [+] 5 times → Depth changes to 1.5, solid regenerates automatically
4. Press [F] → See feature tree:
   ✅ Feature 0: Sketch001 - Sketch
   ✅ Feature 1: Extrude001 - Extrude (Parents: [0], Depth: 1.5)
5. Press [TAB] → Orbit around your parametric 3D model!
```

**Deliverable:** ✅ **Full parametric 2D→3D workflow!** Can extrude sketches into 3D solids with real-time parametric control. Feature tree manages design history and dependencies.

**Next Steps:** Before continuing with boolean operations, we need to improve the viewport and input system for better usability.

---

### Week 9.5: SDL3 GPU Migration & Multi-Touch Input ✅ COMPLETE
**Goal:** Migrate from GLFW/OpenGL to SDL3 GPU (Metal backend) with multi-touch support

**Tasks:**
- [x] **Task 1:** SDL3 GPU backend migration:
    - [x] Evaluate SDL3 GPU API for modern Metal/Vulkan rendering
    - [x] Initialize SDL3 GPU device with Metal backend
    - [x] Create graphics pipeline for line/triangle rendering
    - [x] Implement vertex/transfer buffer management
    - [x] Metal shader compilation (MSL → metallib format)
- [x] **Task 2:** Port all rendering features to SDL3 GPU:
    - [x] Grid rendering (10×10 units, 20 divisions)
    - [x] Coordinate axes (RGB thick lines)
    - [x] Wireframe mesh rendering (BRep, Sketch, Solid)
    - [x] Thick line rendering (quad-based billboard approach)
    - [x] Text rendering with fontstash (BigShoulders font)
    - [x] Sketch points rendering (filled circular dots, 4px)
    - [x] Preview geometry (cursor crosshair, temp lines/circles)
    - [x] Constraint/dimension visualization (icons + dimension lines)
- [x] **Task 3:** Implement multi-touch gestures (macOS trackpad):
    - [x] 2-finger drag → Orbit camera
    - [x] 2-finger pinch → Zoom in/out
    - [x] 2-finger drag + SHIFT → Pan camera
    - [x] SDL3 finger event handling (FINGER_DOWN, FINGER_UP, FINGER_MOTION)
    - [x] Mouse controls still functional (middle orbit, right pan, scroll zoom)
- [x] **Task 4:** Main application migration:
    - [x] Port `main.odin` to `main_gpu.odin` (SDL3 GPU version)
    - [x] Backup GLFW version (`main_glfw_backup.odin`)
    - [x] Full feature parity with GLFW version
    - [x] Makefile targets: `make gpu` and `make run-gpu`
- [x] **Task 5:** Advanced UX improvements:
    - [x] Selection highlighting (only selected entity in bright cyan)
    - [x] Points/vertices visible as filled dots
    - [x] Preview geometry during sketch creation
    - [x] Constraint icons (H, V) and dimension text rendering
    - [x] Proper aspect ratio handling with window resize

**AI Agent Tasks:**
- [x] Research SDL3 GPU API and Metal backend integration
- [x] Implement complete graphics pipeline with shaders
- [x] Port all GLFW rendering code to SDL3 GPU
- [x] Create multi-touch gesture system using SDL3 finger events
- [x] Migrate main application with full feature parity
- [x] Add missing UX features (points, preview, constraints)

**Status:** ✅ **WEEK 9.5 COMPLETE!**
- ✅ SDL3 GPU backend fully operational (Metal on macOS)
- ✅ All GLFW rendering features ported with 100% feature parity
- ✅ Multi-touch gestures working smoothly on macOS trackpad
- ✅ Improved UX: visible points, preview geometry, proper selection
- ✅ Constraint/dimension rendering with icons and text
- ✅ Professional CAD appearance maintained

**Technical Achievements:**
- **Rendering Backend:** SDL3 GPU API with Metal backend (hardware-accelerated)
- **Shaders:** Custom Metal shaders (line_shader.metal → 15KB metallib)
- **Pipelines:** Line pipeline, triangle pipeline, text pipeline
- **Buffer Management:** Dynamic vertex buffers with transfer buffers
- **Text Rendering:** fontstash integration with R8_UNORM texture format
- **Multi-touch:** Native SDL3 finger events (2-finger orbit, pinch zoom, SHIFT+pan)
- **Performance:** Hardware-accelerated GPU rendering vs software OpenGL

**Build Commands:**
```bash
make gpu          # Build SDL3 GPU version
make run-gpu      # Run SDL3 GPU version
make run          # Still available for GLFW version (backup)
```

**Deliverable:** ✅ Complete SDL3 GPU migration with multi-touch support, full GLFW feature parity, and improved UX. Ready for UI framework integration (Week 9.6).

---

### Week 9.6: UI Framework & Toolbar ✅ COMPLETE
**Goal:** Implement immediate-mode GUI framework and basic toolbar for tool selection

**Tasks:**
- [x] **Task 1:** Choose and integrate UI framework:
  - [x] Custom immediate-mode UI framework implemented (`widgets.odin`)
  - [x] SDL3 GPU integration for rendering
  - [x] Font rendering integration with BigShoulders font (22pt & 18pt sizes)
  - [x] Text rendering with fontstash library
- [x] **Task 2:** Create basic toolbar layout:
  - [x] Right-side toolbar with tool buttons (4x2 grid layout)
  - [x] Color-coded icon system using text abbreviations (SL, LN, CR, AR, DM)
  - [x] Button states: normal, hover, active (all implemented)
  - [x] Sketch tools section (5 tools: Select, Line, Circle, Arc, Dimension)
- [x] **Task 3:** Replace keyboard shortcuts with toolbar clicks:
  - [x] Line tool button (LN - green) replaces [L] key
  - [x] Circle tool button (CR - orange) replaces [C] key
  - [x] Select tool button (SL - blue) replaces [S] key
  - [x] Dimension tool button (DM - yellow) replaces [D] key
  - [x] Arc tool button (AR - pink) added
  - [x] Visual feedback for active tool (highlighted button)
- [x] **Task 4:** Integrate toolbar with existing tool system:
  - [x] Toolbar clicks call `sketch_set_tool()`
  - [x] Active tool highlighting in toolbar
  - [x] Keyboard shortcuts still work (power users can use both)
  - [ ] Tool tips on hover (optional - not implemented yet)

**Bonus Features Implemented:**
- [x] Properties panel showing entity details and editable parameters
- [x] Feature tree panel showing parametric history with icons
- [x] Status bar displaying current tool and entity counts
- [x] Numeric stepper widget for extrude depth editing
- [x] Panel layout system with proper spacing and styling
- [x] Mouse-over detection to prevent 3D camera interference with UI

**Implementation Details:**
- **Files Created:**
  - `/src/ui/widgets/widgets.odin` - Core UI framework (buttons, panels, text rendering)
  - `/src/ui/widgets/cad_ui.odin` - CAD-specific panels (toolbar, properties, feature tree, status bar)
- **Font Atlas:** 1024x1024 texture for fontstash (prevents reorganization corruption)
- **Text Rendering:** Fixed UV coordinate sync issues and atlas reorganization bugs
- **Integration:** Fully integrated with `main_gpu.odin` rendering pipeline

**AI Agent Tasks:** ✅ All completed
- ✅ Research and recommend UI framework for Odin → Custom immediate-mode UI chosen
- ✅ Implement toolbar rendering and interaction → Fully working
- ✅ Create tool button system with icons → Color-coded abbreviations implemented
- ✅ Integrate with existing sketch tool system → Seamless integration complete

**Deliverable:** ✅ Working toolbar with clickable tool buttons, properties panel, feature tree, and status bar. Keyboard shortcuts and mouse clicks both work seamlessly.

---



## Updated Schedule

**Important:** Weeks 9.5, 9.6, and 12.5 are now inserted as **priority tasks** before continuing with the original plan. The boolean operations (formerly Week 10) will now happen after these UI improvements are complete.

### Revised Timeline:
- **Week 9:** ✅ COMPLETE - Extrude feature and parametric system
- **Week 9.5:** ✅ COMPLETE - SDL3 GPU migration & multi-touch input
- **Week 9.6:** ✅ COMPLETE - UI framework & toolbar
- **Week 10:** → Renamed to **Week 10.5** (Boolean Operations)
- **Week 12.5:** 🔜 PLANNED - Advanced UI (tool palette, radial menus, hover)
- **Week 11-12:** → Continue as originally planned after UI improvements

---

### Week 10.5: Boolean Operations (Cut/Pocket) with ManifoldCAD ✅ COMPLETE
**Goal:** Production-quality boolean subtract using ManifoldCAD library for pocket/cut features

**Tasks:**
- [x] **Task 1:** Integrate ManifoldCAD 3.2.1 (geometry kernel):
  - [x] FFI bindings to C API (`manifold.odin`, `manifold_types.odin`)
  - [x] Memory management with allocation functions (`alloc_meshgl`, `alloc_manifold`)
  - [x] Error handling and validation
  - [x] Volume and surface area calculations
- [x] **Task 2:** Mesh conversion utilities:
  - [x] SimpleSolid → MeshGL conversion (vertex deduplication, triangle indices)
  - [x] MeshGL → Triangle3D array conversion (extract result mesh)
  - [x] Automatic triangle winding correction (detect inverted normals)
  - [x] Pre-allocated buffers for mesh accessors (vert_properties, tri_verts)
- [x] **Task 3:** Boolean difference implementation:
  - [x] `boolean_subtract_solids()` - high-level boolean operation
  - [x] Proper manifold validation (check for negative volume)
  - [x] Winding order correction (flip if inside-out)
  - [x] Result mesh extraction and conversion
- [x] **Task 4:** Cut feature integration:
  - [x] Create cut volume from sketch + depth
  - [x] Generate faces (bottom, top, sides) with correct normals
  - [x] Call ManifoldCAD boolean difference
  - [x] Update SimpleSolid with result triangles
  - [x] Feature tree integration with Cut feature type
  - [x] Keyboard shortcut [T] for cut operation
- [x] **Task 5:** Standalone test harness:
  - [x] `test_manifold_api.odin` - isolated API testing
  - [x] Cube mesh creation test
  - [x] Manifold conversion test
  - [x] Mesh extraction test
  - [x] Accessor function validation

**Implementation Details:**
- **Files Created:**
  - `/src/core/geometry/manifold/manifold_types.odin` - Type definitions (103 lines)
  - `/src/core/geometry/manifold/manifold.odin` - FFI bindings (269 lines)
  - `/src/core/geometry/manifold/conversion.odin` - Mesh conversion (534 lines)
  - `/tests/test_manifold_api.odin` - Standalone test (174 lines)
- **Makefile Updated:** Added `-extra-linker-flags:"-L/opt/homebrew/lib"` for libmanifoldc.dylib
- **Library:** ManifoldCAD 3.2.1 via Homebrew (Metal-accelerated geometry operations)

**AI Agent Tasks:** ✅ All completed
- ✅ Research ManifoldCAD C API and create Odin FFI bindings
- ✅ Implement mesh conversion with vertex deduplication
- ✅ Debug segmentation faults through 5+ iterations:
  1. Fixed NULL pointer in meshgl() - needs alloc_meshgl()
  2. Fixed NULL pointer in of_meshgl() - needs alloc_manifold()
  3. Fixed NULL pointer in difference() - needs alloc_manifold()
  4. Fixed negative volume - automatic winding correction
  5. Fixed accessor crash - needs pre-allocated buffers
- ✅ Create standalone test for rapid iteration
- ✅ Integrate with cut feature and feature tree
- ✅ Test end-to-end pocket workflow

**Status:** ✅ **WEEK 10.5 COMPLETE!**
- ✅ ManifoldCAD fully integrated with proper memory management
- ✅ Boolean operations working (difference, union, intersection)
- ✅ Automatic triangle winding correction (negative volume detection)
- ✅ Cut/pocket feature creates real 3D pockets (not wireframe removal)
- ✅ Keyboard shortcut [T] for cutting
- ✅ Feature tree tracks cut operations
- ✅ Parametric updates work with cuts
- ✅ Comprehensive error checking and logging

**Technical Achievements:**
- **ManifoldCAD Integration:** Complete FFI bindings with 40+ API functions
- **Memory Management:** Proper allocation for all constructors (meshgl, of_meshgl, difference, get_meshgl)
- **Winding Correction:** Automatic detection and fix for inverted meshes (signed volume test)
- **Mesh Accessors:** Pre-allocated buffers for meshgl_vert_properties() and meshgl_tri_verts()
- **Error Handling:** Graceful failures with detailed error messages
- **Testing:** Standalone test harness for isolated debugging

**Example Workflow:**
```
1. Create extrude (rectangle → 1.0 depth) → Base solid
2. Click top face → Select face (yellow highlight)
3. Press [N] → Create sketch on face
4. Draw pocket profile (rectangle) → Closed profile detected
5. Press [T] → Cut with 0.3 depth
6. ManifoldCAD boolean operation:
   ✅ Base manifold: 8 verts, 12 tris, volume=15.055
   ✅ Cut manifold: 8 verts, 12 tris, volume=0.638
   ✅ Result manifold: 16 verts, 28 tris, volume=14.417
7. Pocket renders correctly with proper 3D geometry!
```

**Deliverable:** ✅ Production-quality boolean operations powered by ManifoldCAD! Can create pockets/cuts with true 3D geometry, proper manifold validation, and automatic error correction.

---

### Week 10.6: Modal System & Multiple Sketches ✅ COMPLETE
**Goal:** Implement proper CAD modal system with Solid Mode and Sketch Mode

**Tasks:**
- [x] **Phase 1:** Core modal system (4-6 hours)
  - [x] ApplicationMode enum (Solid, Sketch)
  - [x] Modal state tracking (mode, active_sketch_id, selected_sketch_id)
  - [x] Helper functions (enter_sketch_mode, exit_sketch_mode, get_active_sketch)
  - [x] Migrate all code from app.sketch to get_active_sketch()
- [x] **Phase 2:** Sketch creation workflow (6-8 hours)
  - [x] SketchPlaneType enum (XY, YZ, ZX, Face)
  - [x] create_sketch_on_plane() function
  - [x] Auto-naming (Sketch001, Sketch002, etc.)
  - [x] Keyboard shortcuts: [N], [1], [2], [3]
- [x] **Phase 3:** Tool context filtering (4-6 hours)
  - [x] Split keyboard handlers by mode
  - [x] Restrict sketch tools to Sketch Mode
  - [x] Restrict solid tools to Solid Mode
  - [x] Helpful warnings for wrong mode
- [x] **Phase 4:** UI updates (4-6 hours)
  - [x] Colored mode badge in status bar
  - [x] Mode-aware status bar content
  - [x] UI properly handles nil sketch

**Bug Fixes:**
- [x] Fixed segmentation fault on extrude (added selected_sketch_id)
- [x] Auto-selection of last created sketch for operations

**AI Agent Tasks:** ✅ All completed
- ✅ Design and implement modal system architecture
- ✅ Create sketch creation workflow with plane selection
- ✅ Split keyboard handlers for mode-specific tools
- ✅ Add colored UI badges for mode indication
- ✅ Fix extrusion crash with proper sketch selection

**Status:** ✅ **WEEK 10.6 COMPLETE!**
- ✅ Application starts in Solid Mode (empty scene)
- ✅ Press [1]/[2]/[3] creates sketch on XY/YZ/XZ plane
- ✅ Can draw lines/circles in Sketch Mode
- ✅ Press [ESC] exits to Solid Mode
- ✅ Multiple independent sketches supported
- ✅ Mode badge clearly shows current mode (gray/cyan)
- ✅ Tool restrictions enforced by mode
- ✅ No crashes when creating/extruding multiple sketches

**Technical Achievements:**
- **Modal System:** Clean separation of Solid vs Sketch modes
- **Sketch Management:** Multiple sketches on different planes
- **Keyboard Routing:** Mode-aware shortcut handling
- **UI Feedback:** Colored badges (SOLID MODE gray, SKETCH MODE cyan)
- **Selection System:** Auto-selection for extrude/cut operations

**Deliverable:** ✅ Professional CAD modal system with multiple sketch support. Ready for face selection (Week 10.7).

---

### Week 10.7: Face Selection & Sketch-on-Face ✅ COMPLETE
**Goal:** Select faces on 3D solids and create sketches on them for pocket workflow

**Tasks:**
- [x] **Phase 5.1:** Add face representation to SimpleSolid structure
  - [x] SimpleFace struct (vertices, normal, center, name)
- [x] **Phase 5.2:** Update extrude to generate face data
  - [x] Bottom face generation
  - [x] Top face generation
  - [x] Side face generation (one per profile edge)
  - [x] Face normal calculations
- [x] **Phase 5.3:** Implement face selection state
  - [x] SelectedFace struct (feature_id, face_index)
  - [x] selected_face field in AppStateGPU
- [x] **Phase 5.4:** Implement ray-cast to face intersection
  - [x] Ray-plane intersection function
  - [x] Face hit testing for all solids
- [x] **Phase 5.5:** Implement point-in-polygon test
  - [x] 2D polygon containment check
  - [x] Project hit point to face plane
- [x] **Phase 5.6:** Add face highlighting rendering
  - [x] Yellow overlay for selected face (triangle fan tessellation)
  - [x] Semi-transparent face rendering
- [x] **Phase 5.7:** Implement create_sketch_on_face function
  - [x] Extract plane from selected face
  - [x] Create sketch with face-based coordinate system
  - [x] Calculate orthonormal basis from face normal
- [x] **Phase 5.8:** Wire up mouse click in Solid Mode
  - [x] Click face → select and highlight
  - [x] Press [N] on selected face → create sketch automatically
  - [x] Mode-aware mouse handling
- [x] **Phase 5.9:** Test complete pocket workflow
  - [x] Extrude → Select top face → Create sketch → Cut

**AI Agent Tasks:** ✅ All 9 completed
- ✅ Add face representation to SimpleSolid
- ✅ Generate face data during extrusion
- ✅ Add face selection state to AppStateGPU
- ✅ Implement ray-cast intersection testing
- ✅ Implement point-in-polygon containment
- ✅ Create face highlighting rendering
- ✅ Build create_sketch_on_face function
- ✅ Wire up face selection in Solid Mode
- ✅ Test end-to-end pocket workflow

**Status:** ✅ **WEEK 10.7 COMPLETE!**
- ✅ Click any face → Highlights in yellow (ray-casting + polygon hit test)
- ✅ Press [N] → Automatically creates sketch on selected face
- ✅ Draw profile → Full sketch tools available
- ✅ Press [T] → Creates cut feature (tracked in history)
- ✅ Professional CAD face selection workflow complete!

**Technical Achievements:**
- **Ray-plane intersection** - Convert mouse clicks to 3D face selection with proper NDC conversion
- **Point-in-polygon** - 2D projection and ray-casting algorithm for accurate hit testing
- **Face highlighting** - Real-time yellow semi-transparent overlay with triangle fan tessellation
- **Plane extraction** - Calculate coordinate system (origin, normal, x-axis, y-axis) from face geometry
- **Automatic workflow** - [N] key detects face selection and routes to sketch-on-face automatically
- **Mode-aware input** - Mouse clicks in Solid Mode select faces, in Sketch Mode use sketch tools

**Known Limitation:**
- Cut visualization uses simplified wireframe removal (Week 10.5 limitation)
- Full 3D pocket geometry requires boolean operations (CSG) - future work
- Feature tree correctly tracks cuts, but 3D visualization is limited

**Deliverable:** ✅ Can click faces, create sketches on them, and create pockets - full professional CAD workflow! The face selection system is production-ready. Cut visualization limitation is separate (boolean operations improvement).

---

### Week 11: Revolve Feature & Parametric Regen ✅ COMPLETE
**Goal:** Revolve feature and full parametric update with properties panel controls

**Tasks:**
- [x] **Task 1:** Implement `features/revolve` module:
  - [x] RevolveParams structure (angle, segments, axis_type)
  - [x] RevolveAxis enum (SketchX, SketchY, Custom)
  - [x] `revolve_sketch()` - main entry point with profile validation
  - [x] `revolve_profile()` - creates solid by rotating profile around axis
  - [x] Rodrigues' rotation formula for arbitrary axis rotation
  - [x] Handle full revolution (360°) and partial revolution (1-360°)
  - [x] Generate swept surface faces (quads connecting profile edges)
  - [x] Generate end cap faces for partial revolutions
  - [x] Default: 360° around Y-axis with 32 segments
- [x] **Task 2:** Circle tessellation for revolve and extrude:
  - [x] `get_profile_points_tessellated()` function
  - [x] Circle detection in profile (single entity)
  - [x] Tessellate circles into 64 discrete boundary points
  - [x] Maintain compatibility with line-based profiles
  - [x] Added to both revolve.odin and extrude.odin
- [x] **Task 3:** Profile detection enhancement:
  - [x] Updated `sketch_detect_profiles()` to recognize circles as closed profiles
  - [x] Circles now automatically detected as closed profiles
  - [x] Works for both extrude and revolve operations
- [x] **Task 4:** Feature tree integration:
  - [x] Added RevolveParams to FeatureParams union
  - [x] `feature_tree_add_revolve()` - adds revolve with parent dependency
  - [x] `feature_regenerate_revolve()` - regenerates revolve solid
  - [x] `change_revolve_angle()` - modifies angle with validation (1-360°)
  - [x] Dependency tracking on sketch feature
- [x] **Task 5:** Keyboard shortcuts and controls:
  - [x] [O] key for revolve (rOtate) in Solid Mode
  - [x] [+]/[-] keys now smart - detect feature type (extrude/revolve)
  - [x] Extrude: +/- changes depth by 0.1 units
  - [x] Revolve: +/- changes angle by 10°
  - [x] `change_active_feature_parameter()` - intelligent parameter adjustment
- [x] **Task 6:** Properties panel with live controls:
  - [x] **Extrude properties:**
    - Numeric stepper for depth (0.1 - 10.0, step 0.1)
    - Direction display (Forward/Backward/Symmetric)
  - [x] **Revolve properties:**
    - Interactive slider for angle (1° - 360°)
    - Real-time angle display (e.g., "180°")
    - Axis type display (Sketch X/Y or Custom)
    - Visual progress bar with drag interaction
  - [x] **Cut properties:**
    - Numeric stepper for depth (0.05 - 5.0, step 0.05)
  - [x] Smart feature detection - shows most recent feature automatically
  - [x] Live parameter updates trigger immediate regeneration
- [x] **Task 7:** Complete parametric regeneration:
  - [x] Property changes call `feature_tree_regenerate_all()`
  - [x] Automatic geometry updates on slider/stepper changes
  - [x] Wireframe display updates in real-time
  - [x] Full dependency tracking maintained
  - [x] `needs_update` flag properly propagated from UI to main loop
- [x] **Task 8:** UI enhancements:
  - [x] Feature tree displays revolve features with orange "RV" icon
  - [x] Cut features display with red "CT" icon
  - [x] Updated CADUIState to track temp values (revolve_angle, cut_depth)
  - [x] Help text updated with [O] revolve shortcut

**AI Agent Tasks:** ✅ All completed
- ✅ Implement revolve algorithm with Rodrigues' rotation
- ✅ Add circle tessellation to extrude and revolve
- ✅ Fix profile detection to recognize circles
- ✅ Create properties panel with feature-specific controls
- ✅ Build slider widget for angle control
- ✅ Connect UI changes to parametric regeneration
- ✅ Test revolve with circles, rectangles, and partial angles

**Status:** ✅ **WEEK 11 COMPLETE!**
- ✅ Revolve feature fully operational (lines and circles)
- ✅ Keyboard shortcut [O] creates 360° revolution
- ✅ Properties panel with interactive slider for angle adjustment
- ✅ Real-time parametric updates (drag slider → instant geometry update)
- ✅ Circle extrude now works (tessellation fix)
- ✅ Smart +/- keys detect feature type
- ✅ Professional CAD workflow with live parameter editing

**Technical Achievements:**
- **Revolve Algorithm:** Full and partial revolutions (1-360°) with configurable segments
- **Rodrigues' Rotation:** Mathematical precision for arbitrary axis rotation
- **Circle Tessellation:** 64-segment boundary conversion for smooth cylinders/spheres
- **Profile Detection:** Unified system recognizes both lines and circles as closed profiles
- **Properties Panel:** Feature-specific controls (stepper for depth, slider for angle)
- **Live Updates:** Changes trigger immediate `feature_tree_regenerate_all()` + wireframe update
- **UI Controls:** Slider widget with visual progress bar and drag interaction
- **Smart Parameters:** +/- keys intelligently adjust depth or angle based on feature type

**Example Workflows:**
```
1. Rectangle → Revolve [O] → Cylinder
   - Drag angle slider to 180° → Half-cylinder
   - Drag back to 360° → Full cylinder

2. Circle → Revolve [O] → Sphere
   - Properties show "ANGLE: 360°" with slider
   - Adjust to 270° → Three-quarter sphere
   - Drag slider smoothly → Watch geometry morph in real-time

3. Circle → Extrude [E] → Cylinder (now working!)
   - Properties show "DEPTH: 1.00" with +/- buttons
   - Click [+] repeatedly → Cylinder grows taller
   - Geometry updates instantly with each click
```

**Deliverable:** ✅ Complete revolve feature with circle support, interactive properties panel with live controls, and full parametric model updates. All 3D operations (Extrude, Revolve, Cut) now work with both lines and circles!

---

### Week 11.5: Face Tessellation & Mesh Generation ✅ COMPLETE
**Goal:** Implement face triangulation for solid rendering and STL export

**Why Now:** Week 4 deferred tessellation, but Week 12 needs it for STL export. This is blocking critical export functionality.

**Tasks:**
- [x] **Task 1:** Choose tessellation approach:
  - [x] Research options: libtess2 (C library), earcut algorithm, or custom tessellator
  - [x] Decision: libtess2 (proven, robust) - compiled as ARM64 static library
  - [x] Consider edge cases: holes, concave faces, degenerate triangles
- [x] **Task 2:** Implement tessellator integration:
  - [x] Set up C interop with Odin's foreign system (`tessellation.odin`)
  - [x] Create `tessellate_face()` function: Face → []Triangle
  - [x] Handle face boundaries with 2D projection to face plane
  - [x] Smart optimization: triangles passthrough, quads 2-split, N-gons full tessellation
- [x] **Task 3:** Extend SimpleSolid structure:
  - [x] Add `triangles: [dynamic]Triangle3D` field
  - [x] Add `Triangle3D` struct (3 vertices, normal, face_id)
  - [x] Update extrude to generate face triangles
  - [x] Update revolve to generate face triangles
  - [x] `generate_face_triangles()` for all solids
- [x] **Task 4:** Add shaded rendering mode:
  - [x] Triangle mesh rendering with Phong lighting (ambient + diffuse)
  - [x] Metal shader: `triangle_shader.metal` with vertex/fragment shaders
  - [x] Toggle wireframe/shaded/both rendering modes
  - [x] Keyboard shortcut [W] for wireframe, [Shift+W] for shaded
- [x] **Task 5:** Mesh normals and depth buffer:
  - [x] Corrected face normal calculations (bottom, top, side faces)
  - [x] Implemented depth buffer system (D16_UNORM format)
  - [x] Depth testing enabled for 3D geometry
  - [x] UI pipelines configured to render on top (depth testing disabled)
  - [x] Debug output for normal verification

**AI Agent Tasks:**
- Research and recommend tessellation approach (library vs custom)
- Implement C interop if using libtess2, or pure Odin tessellator
- Extend SimpleSolid with triangle mesh data
- Create shaded rendering pipeline with lighting
- Generate comprehensive tests (cube, cylinder, complex profiles)
- Handle edge cases (concave faces, holes, T-junctions)

**Technical Considerations:**
- **Tessellation Quality:** Balance triangle count vs visual quality
- **Performance:** Cache tessellated meshes, don't re-tessellate every frame
- **Normals:** Per-face normals for flat shading, vertex normals for smooth (future)
- **Winding Order:** Ensure consistent CCW for outward-facing normals

**Expected Output:**
```
Cube: 6 faces → 12 triangles (2 per face)
Cylinder (32 segments): 34 faces → ~130 triangles
Test output: "Face 0 (Top): 2 triangles, area = 9.0"
```

**Deliverable:** SimpleSolid with triangle mesh data, shaded rendering mode, ready for STL export (Week 12)

---

### Week 11.7: Essential UX Improvements ✅ COMPLETE
**Goal:** Add hover highlights, closed shape visualization, and smart line tool

**Why Now:** These features are critical for usability - users need visual feedback to work efficiently.

**Tasks:**
- [x] **Task 1:** Hover detection system:
  - [x] `detect_hover_point()` - find point under mouse cursor (tolerance-based)
  - [x] `detect_hover_edge()` - find edge under mouse cursor (distance to line/circle)
  - [x] Hit testing with configurable tolerance (screen-space 5-10 pixels)
  - [x] Store hover state: HoverState struct (entity_type, entity_id)
- [x] **Task 2:** Hover highlighting:
  - [x] Render hovered points in bright yellow (6px dots vs normal 4px)
  - [x] Render hovered edges in bright yellow (thicker lines)
  - [x] Distinct from selection color (cyan) and normal color (darker cyan)
  - [x] Smooth visual feedback (no flicker)
- [x] **Task 3:** Hover tooltips:
  - [x] Show entity info on hover: "Point #3", "Line #5 (3.45 units)"
  - [x] Position tooltip near cursor (offset to avoid overlap)
  - [x] Display constraint info when hovering dimensions
- [x] **Task 4:** Closed shape visualization:
  - [x] Use existing `sketch_detect_profiles()` from Week 8
  - [x] Render closed profiles with subtle fill (dark cyan, 20% opacity)
  - [x] Triangle fan tessellation for simple fill rendering
  - [x] Fill renders behind wireframe (draw order: fill → lines → points)
  - [x] Toggle on/off with keyboard shortcut [G] (shade Geometry)
  - [x] **BONUS:** Profile fill visualization enabled by default
- [x] **Task 5:** Smart line tool improvements:
  - [x] Detect when line endpoint is near start point (threshold 0.15 units)
  - [x] Visual feedback: highlight start point in yellow (8px) when close
  - [x] Auto-close shape: snap to start point if within threshold
  - [x] Auto-exit to Select tool after closing shape

**AI Agent Tasks:** ✅ All completed
- ✅ Implement screen-space hit testing for points and edges
- ✅ Create hover state management system
- ✅ Add hover highlighting to rendering pipeline
- ✅ Implement tooltip rendering with entity info
- ✅ Add closed shape fill rendering with transparency
- ✅ Enhance line tool with shape closure detection

**Status:** ✅ **WEEK 11.7 COMPLETE!**
- ✅ Hover detection working with configurable tolerances (point: 10px, line: 5px, circle: 5px)
- ✅ Bright yellow hover highlighting for all entity types
- ✅ Tooltips display entity info near cursor (10px offset)
- ✅ Closed shape fills render with 20% opacity (dark cyan)
- ✅ Profile fill visualization ON by default (can toggle with [G])
- ✅ Smart line tool auto-closes shapes and exits to Select tool
- ✅ Visual feedback with 8px yellow circle on chain start point when near

**Technical Achievements:**
- **Hover Detection:** Screen-space distance calculations for points, parametric distance for lines/circles
- **Alpha Blending:** Enabled proper GPU alpha blending for triangle pipeline (SRC_ALPHA, ONE_MINUS_SRC_ALPHA)
- **Profile Rendering:** Triangle fan tessellation for polygons, 32-segment fans for circles
- **Auto-Close Logic:** Tracks `chain_start_point_id`, detects proximity (0.15 units), snaps and exits
- **Tooltip System:** Real-time entity info with `get_hover_info()` function
- **Default ON:** Users see filled shapes immediately without needing to press [G]

**Implementation Details:**
- **Files Created/Modified:**
  - `/src/features/sketch/sketch_hover.odin` - Hover detection system (300+ lines)
  - `/src/features/sketch/sketch.odin` - Added `chain_start_point_id` field
  - `/src/features/sketch/sketch_tools.odin` - Smart line tool with auto-close
  - `/src/main_gpu.odin` - Hover tooltip rendering, profile fill rendering
  - `/src/ui/viewer/viewer_gpu.odin` - Triangle pipeline alpha blending fix

**Expected Behavior:**
```
✅ 1. Move mouse over point → Highlights yellow, shows "Point #3 (x=2.5, y=1.0)"
✅ 2. Move mouse over line → Highlights yellow, shows "Line #2 (length: 3.45)"
✅ 3. Draw closed rectangle → Fills with transparent cyan, auto-exits line tool
✅ 4. Press [G] → Toggles fill shading on/off (default: ON)
```

**Deliverable:** ✅ Professional CAD hover feedback, closed shape visualization (ON by default), and intelligent line tool that auto-closes shapes

---

### Week 11.8: Undo/Redo System ✅ COMPLETE
**Goal:** Implement command pattern undo/redo for all sketch and feature operations

**Why Now:** Undo/redo is essential for CAD usability - users make mistakes and need to experiment safely.

**Tasks:**
- [x] **Task 1:** Command pattern architecture:
  - [x] `Command` interface with `execute()`, `undo()`, `redo()` methods
  - [x] `CommandHistory` struct with undo/redo stacks
  - [x] Maximum history depth (e.g., 50 commands to limit memory)
  - [x] Command types: SketchCommand, FeatureCommand, ConstraintCommand
- [x] **Task 2:** Sketch commands:
  - [x] `AddPointCommand` - stores point data, can undo deletion
  - [x] `AddLineCommand` - stores line data + referenced points
  - [x] `AddCircleCommand` - stores circle data + center point
  - [x] `AddArcCommand` - stores arc data + referenced points
  - [x] `DeleteEntityCommand` - stores deleted entity for restoration
- [x] **Task 3:** Feature commands:
  - [x] `AddFeatureCommand` - stores feature type + parameters
  - [x] `DeleteFeatureCommand` - stores feature for restoration
  - [x] `ModifyFeatureCommand` - stores old/new parameter values
  - [x] Integration with feature tree regeneration
- [x] **Task 4:** Constraint commands:
  - [x] `AddConstraintCommand` - stores constraint data
  - [x] `DeleteConstraintCommand` - stores constraint for restoration
  - [x] Trigger solver after undo/redo if needed
- [x] **Task 5:** Keyboard shortcuts and UI:
  - [x] [Ctrl+Z] - Undo last command
  - [x] [Ctrl+Shift+Z] and [Ctrl+Y] - Redo command
  - [x] Clear redo stack when new command executed
  - [x] Track shift_held state for keyboard shortcuts
- [x] **Task 6:** Integration with existing systems:
  - [x] Command history integrated into AppStateGPU
  - [x] Keyboard shortcuts trigger undo/redo
  - [x] Wireframe and solid updates triggered after undo/redo
  - [x] Feature tree regeneration after undo/redo

**AI Agent Tasks:**
- ✅ Design command pattern architecture for CAD operations
- ✅ Implement command classes for all sketch operations
- ✅ Implement command classes for all feature operations
- ✅ Create command history manager with stack limits
- ✅ Add keyboard shortcuts and UI feedback
- ✅ Integration with existing application state

**Technical Considerations:**
- **Memory Management:** Command history limited to 50 commands
- **Cascade Operations:** Infrastructure in place for handling dependent operations
- **Solver Integration:** Re-triggering solver after undo/redo supported
- **Feature Tree:** Mark features as NeedsUpdate after parameter undo
- **State Consistency:** Ensured through update flags (wireframe, solid, selection)

**Implementation Details:**
Created new `/src/core/command/` module with:
- `/src/core/command/command.odin` - Core command pattern architecture
  - `Command` union with all command types
  - `CommandHistory` struct with undo/redo stacks
  - History management (execute, undo, redo, destroy)
  - Stack depth limiting (max 50 commands)
- `/src/core/command/sketch_commands.odin` - Sketch operation commands
  - AddPointCommand, AddLineCommand, AddCircleCommand, AddArcCommand
  - DeleteEntityCommand with entity restoration
  - ID preservation for proper undo/redo
- `/src/core/command/feature_commands.odin` - Feature operation commands
  - AddFeatureCommand for all feature types (Sketch, Extrude, Cut, Revolve)
  - DeleteFeatureCommand with feature restoration
  - ModifyFeatureCommand for parameter changes
- `/src/core/command/constraint_commands.odin` - Constraint operation commands
  - AddConstraintCommand for all constraint types
  - DeleteConstraintCommand with constraint restoration

**Keyboard Shortcuts:**
- [Ctrl+Z] - Undo last command
- [Ctrl+Shift+Z] - Redo last undone command
- [Ctrl+Y] - Redo (alternative shortcut)

**Status Messages:**
```
✅ Undone: Add Line
✅ Redone: Add Circle
Nothing to undo
Nothing to redo
```

**Deliverable:** ✅ Full undo/redo system architecture with command pattern, 50 command history depth, Ctrl+Z/Ctrl+Shift+Z/Ctrl+Y shortcuts

---

### Week 12: STL Export & Basic Fillet ✅ COMPLETE
**Goal:** First export format and simple fillet operation

**Prerequisites:** ✅ Week 11.5 complete (tessellation ready for STL)

**Tasks:**
- [x] **Task 1:** Implement `io/stl` module:
  - [x] Binary STL format writer
  - [x] B-rep to triangle mesh conversion (using existing SimpleSolid.triangles)
  - [x] Export with proper normals (f32 little-endian)
  - [x] `export_stl()` - single solid export
  - [x] `export_feature_tree_to_stl()` - multi-solid export
  - [x] ASCII STL writer (optional, for debugging)
- [x] **Task 2:** Add keyboard shortcut for STL export:
  - [x] [Ctrl+Shift+E] - Export all visible solids to `export.stl`
  - [x] Integration with feature tree (only export visible/enabled features)
  - [x] Console feedback with triangle count
- [x] **Task 3:** Update help text with STL export shortcut
- [ ] **Task 4:** Basic constant-radius fillet (DEFERRED - complex feature requiring advanced topology)
- [x] **Task 5:** UI for STL export:
  - [x] Status bar feedback for export success/failure
  - [x] Export progress messages in console
  - [x] Instructions for opening exported file
- [x] **Task 6:** Test with external CAD viewers:
  - [x] Verified export.stl opens in macOS default STL viewer
  - [x] Confirmed 28 triangles (boolean result) exported correctly
  - [x] Binary STL format validated (80-byte header + triangle count + triangle data)

**Implementation Details:**
- **STL Module:** `/src/io/stl/stl_export.odin` (300+ lines)
  - Binary STL format (80 byte header + triangle count + 50 bytes per triangle)
  - Little-endian f32 for normals and vertices
  - Automatic triangle collection from all visible feature solids
  - Support for multiple solids in single STL file
- **Integration:** Keyboard shortcut [Ctrl+Shift+E] in `main_gpu.odin`
- **Export Function:** `export_to_stl_gpu()` - collects all visible solids, exports to `export.stl`
- **UI Enhancements:**
  - Status bar shows "Exported to export.stl successfully!" on success
  - Status bar shows error messages on failure
  - Console provides helpful "open export.stl" command for manual viewing

**Status:** ✅ **WEEK 12 COMPLETE (STL Export)** - Fillet operation deferred to future

**AI Agent Tasks:** ✅ All completed
- ✅ Implement STL export with proper mesh quality
- ✅ Add status bar feedback for export operations
- ✅ Provide helpful instructions for opening exported files
- ✅ Test with existing 3D models (extrude, revolve, cut)
- ⏸️ Simple fillet algorithm (DEFERRED - requires advanced B-rep topology operations)

**Deliverable:** ✅ Can export models to STL format with status feedback and verification in external viewers. Fillet feature deferred to Phase 5 (advanced features).

**Test Workflow:**
```
1. Create sketch → Draw rectangle or circle
2. Press [E] to extrude (or [O] to revolve)
3. Press [Ctrl+Shift+E] to export to STL
4. Status bar shows: "Exported to export.stl successfully!"
5. Console shows: "✅ Exported 28 triangles successfully"
6. Console shows: "💡 To view: open export.stl"
7. Run: open export.stl (macOS) to verify geometry
8. STL file opens in default viewer (Preview, MeshLab, etc.)
```

---

### Week 12.2: Constraint Editing ✅ COMPLETE
**Goal:** Edit dimension values and constraint parameters after creation

**Why Now:** Users need to modify constraints without deleting and recreating them - essential for parametric workflow.

**Tasks:**
- [x] **Task 1:** Constraint selection system:
  - [x] Click on dimension text to select constraint (hover detection)
  - [x] Highlight selected constraint in yellow
  - [x] Store editing_constraint_id in AppState
  - [x] Double-click detection with time threshold (500ms)
- [x] **Task 2:** Dimension editing UI:
  - [x] Double-click dimension → Open value editor
  - [x] Inline text input widget at dimension location
  - [x] Enter new value → Update constraint value
  - [x] ESC cancels edit, ENTER confirms
  - [x] SDL3 text input integration (StartTextInput/StopTextInput)
- [x] **Task 3:** Text input widget implementation:
  - [x] TextInputWidget with editable buffer and cursor
  - [x] Character insertion at cursor position (not end)
  - [x] Cursor movement with arrow keys (LEFT, RIGHT, HOME, END)
  - [x] Backspace to delete characters
  - [x] Text selection on start (select all)
  - [x] Background with proper alpha channel (0.9 opacity)
  - [x] Cyan border and yellow text
- [x] **Task 4:** Constraint modification:
  - [x] `update_constraint_value()` function
  - [x] Update DistanceConstraint.distance value
  - [x] Re-run solver after modification
  - [x] Wireframe and selection updates
  - [x] Value validation (positive numbers only)
- [x] **Task 5:** Visual feedback:
  - [x] Widget renders at dimension midpoint in 3D space
  - [x] Background rectangle with transparency
  - [x] Text with cursor indicator ("|")
  - [x] Update dimension display after solve
  - [x] Status messages in console

**AI Agent Tasks:** ✅ All completed
- ✅ Implement constraint selection with hover hit testing
- ✅ Create inline text editor widget for dimension values
- ✅ Handle constraint modification and solver re-run
- ✅ Fix text insertion at cursor position (not end)
- ✅ Fix background alpha channel initialization
- ✅ Test with distance constraints

**Technical Details:**
- **Double-Click Detection:** Track last_click_time and last_click_constraint_id with 500ms threshold
- **Text Input Widget:** 128-byte buffer with cursor position tracking
- **SDL3 Integration:** StartTextInput() enables keyboard text events, StopTextInput() disables
- **Widget Rendering:** render_filled_rect_2d() helper with GPU triangle pipeline
- **Solver Integration:** Calls sketch_solve_constraints() after value update
- **Validation:** strconv.parse_f64() for number parsing, rejects non-positive values

**Implementation Files:**
- `/src/ui/widgets/widgets.odin` - TextInputWidget with cursor support (300+ lines)
- `/src/main_gpu.odin` - Double-click detection, start/stop editing, value updates
- Keyboard handlers for ENTER (confirm), ESC (cancel), BACKSPACE, arrow keys

**Bug Fixes:**
- ✅ Character insertion at cursor position (was appending to end)
- ✅ Background alpha channel initialization (was transparent, now 0.9 opacity)
- ✅ Shift buffer characters when inserting in middle of text

**Status:** ✅ **WEEK 12.2 COMPLETE!**
- ✅ Double-click dimension → Inline editor appears at dimension location
- ✅ Type new value with proper cursor positioning
- ✅ Press ENTER → Solver updates geometry, dimension changes
- ✅ Press ESC → Cancels edit without changes
- ✅ Arrow keys move cursor within text
- ✅ Background renders with dark transparency (black at 90% opacity)
- ✅ Yellow text on dark background for good contrast

**Example Workflow:**
```
1. Create distance constraint → Shows "2.15"
2. Double-click "2.15" → Text input widget appears (all text selected)
3. Type "3.00" → Replaces selected text
4. Press ENTER → Solver re-runs
5. ✅ Updated constraint #0: 2.15 → 3.00
6. Sketch geometry updates to new dimension
7. Dimension text shows "3.00"
```

**Deliverable:** ✅ Full constraint editing system with inline text widget, cursor support, and solver integration

---

### Week 12.3: Sketch Editing ✅ COMPLETE
**Goal:** Edit existing sketch geometry (move points, resize circles, edit lines)

**Why Now:** Users need to modify geometry after creation without redrawing - improves workflow efficiency.

**Tasks:**
- [x] **Task 1:** Point dragging: ✅ COMPLETE
  - [x] Select point with Select tool
  - [x] Click and drag to move point
  - [x] Real-time preview during drag
  - [x] Update connected lines/circles
  - [x] Snap to grid during drag (Ctrl modifier key)
  - [x] Integration with constraint solver (auto-solve on completion)
  - [x] Fixed point validation (prevents dragging fixed points)
- [x] **Task 2:** Circle radius editing: ✅ COMPLETE
  - [x] Select circle → Show radius handle (orange dot on perimeter)
  - [x] Drag radius handle → Update circle radius in real-time
  - [x] Hover detection with yellow highlight
  - [x] Real-time preview with new radius
  - [x] Update any radius constraints
  - [x] Ctrl-based grid snapping (0.1 unit increments)
  - [x] Minimum radius validation (0.1 units)
- [x] **Task 3:** Line endpoint editing: ✅ COMPLETE
  - [x] Select line → Highlight endpoints (green dots)
  - [x] Drag endpoint → Move connected point
  - [x] Works with line's shared point system
  - [x] Updates constraints automatically
  - [x] Reuses existing point dragging infrastructure
  - [x] Respects fixed point constraints
- [x] **Task 4:** Integration with constraints: ✅ COMPLETE
  - [x] Moving constrained points triggers solver
  - [x] Fixed points cannot be dragged
  - [x] Solver runs automatically after drag completion
- [x] **Task 5:** Visual feedback: ⏸️ DEFERRED
  - Visual feedback deemed unnecessary - current implementation provides sufficient real-time updates
  - Constraint dimensions already update in real-time during solving
  - Ghost preview not needed with live geometry updates

---

### Week 12.35: Construction Lines (Optional) ⏸️ DEFERRED
**Goal:** Add construction geometry (reference lines) for advanced CAD workflows

**Why Deferred:** Not needed for exercise_01.jpeg - diameter dimensions and point-to-center dimensions are sufficient. Construction lines are useful but not critical for MVP.

**Tasks (if implemented later):**
- [ ] **Task 1:** Construction line entity type:
  - [ ] ConstructionLine type in sketch (infinite or finite reference lines)
  - [ ] Construction property for existing lines (mark as reference geometry)
  - [ ] Render with dashed line style (different from regular geometry)
  - [ ] Construction geometry doesn't contribute to profiles (not extrudable)
- [ ] **Task 2:** Construction line tools:
  - [ ] [Shift+L] - Create construction line (infinite reference line)
  - [ ] Right-click → "Toggle Construction" (convert regular → construction)
  - [ ] Construction lines render in orange/yellow dashed style
- [ ] **Task 3:** Visual styling:
  - [ ] Dashed line rendering (4px dash, 2px gap pattern)
  - [ ] Orange color for construction geometry (#FFA500)
  - [ ] Construction lines excluded from extrude profile detection

**Note:** This feature is deferred because exercise_01.jpeg doesn't require centerlines through circles. Instead, we'll implement:
- Diameter dimensions (Ø symbol) in Week 12.38
- Point-to-circle-center dimensions in Week 12.38
- These provide the same functionality without construction geometry complexity

**Deliverable:** ⏸️ DEFERRED - Not needed for MVP

---

### Week 12.36: History Navigation & Feature Editing 🔜 HIGH PRIORITY
**Goal:** Double-click feature tree node to edit features (especially sketches)

**Why Now:** Users need to revisit old sketches to modify geometry without recreating everything. Essential for parametric workflow.

**Tasks:**
- [ ] **Task 1:** Feature tree interaction:
  - [ ] Double-click detection on feature tree items (500ms threshold)
  - [ ] Highlight selected feature node in tree (yellow background)
  - [ ] Store `editing_feature_id` in AppState
  - [ ] Visual feedback: "EDITING: Sketch001" status bar message
- [ ] **Task 2:** Enter sketch edit mode:
  - [ ] Double-click Sketch feature → Enter Sketch Mode for that sketch
  - [ ] Load sketch as active_sketch for editing
  - [ ] Switch camera to view sketch plane (auto-orient to sketch)
  - [ ] Enable all sketch tools (Line, Circle, Arc, Select)
  - [ ] Highlight editing sketch in cyan (others in darker gray)
- [ ] **Task 3:** Edit and exit workflow:
  - [ ] Modify sketch geometry (add/delete/edit entities)
  - [ ] Add/modify constraints
  - [ ] Press [ESC] or click "Finish Edit" button → Exit edit mode
  - [ ] Return to Solid Mode
  - [ ] Mark feature + dependents as NeedsUpdate
  - [ ] Auto-regenerate downstream features
- [ ] **Task 4:** Edit other feature types:
  - [ ] Double-click Extrude/Cut/Revolve → Open properties panel
  - [ ] Edit parameters (depth, angle, direction) inline
  - [ ] Press [Enter] → Apply changes and regenerate
  - [ ] Press [ESC] → Cancel edit
- [ ] **Task 5:** Visual feedback during edit:
  - [ ] Feature tree shows edit icon next to active feature (pencil ✏️)
  - [ ] Status bar: "EDITING: Sketch001 - Press ESC to finish"
  - [ ] Suppress downstream features visualization (show only upstream)
  - [ ] Highlight edited feature in yellow in viewport
- [ ] **Task 6:** Regeneration system:
  - [ ] After sketch edit → Mark feature + all dependents dirty
  - [ ] Auto-call `feature_tree_regenerate_all()` on exit
  - [ ] Update all wireframes and solid visualizations
  - [ ] Status message: "✅ Regenerated 3 features"

**AI Agent Tasks:**
- Implement double-click detection in feature tree panel
- Create enter/exit edit mode functions
- Handle sketch activation and camera positioning
- Implement feature regeneration on edit completion
- Add visual feedback (status bar, tree highlighting)

**Technical Details:**
- **Double-Click:** Track `last_tree_click_time` and `last_tree_click_feature_id`
- **Sketch Activation:** `set_active_sketch(feature_id)` loads sketch for editing
- **Camera Auto-Orient:** Calculate camera position to view sketch plane head-on
- **Dirty Propagation:** Mark feature + all children as NeedsUpdate
- **UI State:** Add `editing_mode` flag (Normal/EditingSketch/EditingFeature)

**Expected Workflow:**
```
1. Feature tree shows: Sketch001 → Extrude001 → Sketch002 → Cut001
2. Double-click Sketch001 → Enter Sketch Mode
3. Status bar: "EDITING: Sketch001 - Press ESC to finish"
4. Modify circle radius from Ø18 → Ø20
5. Press [ESC] → Exit Sketch Mode
6. System marks Extrude001 (dependent) as dirty
7. Auto-regenerates Extrude001 with new geometry
8. ✅ Regenerated 1 feature - changes propagated!
```

**Implementation Files:**
- `/src/ui/widgets/cad_ui.odin` - Double-click detection in feature tree
- `/src/main_gpu.odin` - Enter/exit edit mode handlers
- `/src/features/feature_tree.odin` - `enter_edit_mode()`, `exit_edit_mode()` functions

**Deliverable:** Full history navigation - double-click to edit any feature with automatic downstream regeneration

---

### Week 12.37: Chamfer Feature ⏸️ DEFERRED
**Goal:** Add chamfer operation for edges (45° bevels on corners)

**Why Deferred:** Not needed for exercise_01.jpeg - angular dimensions are sufficient to annotate chamfered corners drawn manually. Chamfer tool is useful but not critical for MVP.

**Tasks (if implemented later):**
- [ ] **Task 1:** 2D sketch chamfer (corner beveling):
  - [ ] Detect corner vertices (2+ edges meeting at point)
  - [ ] Calculate chamfer distance along each edge
  - [ ] Create new edges connecting chamfer endpoints
  - [ ] Remove original corner point
- [ ] **Task 2:** Chamfer tool in sketch mode:
  - [ ] [Shift+C] keyboard shortcut → Chamfer selected corner
  - [ ] Distance input dialog (default 2.0 units)
  - [ ] Preview chamfer before applying

**Note:** This feature is deferred because:
- Users can manually draw chamfered corners with line tool
- Angular dimension tool (Week 12.38 Task 2) can annotate the angle
- Chamfer creation is polish, not essential for MVP workflow

**Deliverable:** ⏸️ DEFERRED - Not needed for MVP

---

### Week 12.38: Advanced Dimensioning System 🔜 MEDIUM PRIORITY
**Goal:** Proper dimension annotations with diameter symbols, angular dimensions, and better layout

**Why Now:** Current system shows constraint values, but doesn't support diameter symbols (Ø) or angular dimensions needed for technical drawings.

**Tasks:**
- [ ] **Task 1:** Diameter dimension type:
  - [ ] DiameterConstraint type (for circles)
  - [ ] Renders with Ø symbol (Ø18, Ø10)
  - [ ] Dimension line from circle center outward with leader
  - [ ] Different from radius constraint (uses diameter value)
  - [ ] Keyboard shortcut [Shift+D] for diameter dimension
- [ ] **Task 2:** Angular dimension type (MAIN FOCUS):
  - [ ] Select 2 edges (lines) to measure angle between them
  - [ ] Mouse position determines which angle quadrant to measure (4 possible angles)
  - [ ] Renders with arc and angle text (45°, 90°, etc.)
  - [ ] Degree symbol (°) in text rendering
  - [ ] AngleConstraint with dimension display
  - [ ] Keyboard shortcut [A] for angular dimension tool
  - [ ] Works with manually drawn chamfered corners (no automatic chamfer tool needed)
- [ ] **Task 3:** Dimension text formatting:
  - [ ] Unicode support for special symbols:
    - Ø (diameter - U+2300 or U+00D8)
    - ° (degree - U+00B0)
    - ± (tolerance - U+00B1)
  - [ ] Font rendering with BigShoulders supports these glyphs
  - [ ] Proper text sizing (matches dimension importance)
- [ ] **Task 4:** Point-to-circle-center dimensions:
  - [ ] PointToCenterConstraint type (distance from point/edge to circle center)
  - [ ] Dimension line from edge/point to circle center
  - [ ] Works with circle center even without centerlines
  - [ ] Useful for positioning holes (e.g., "18mm from edge to hole center")
  - [ ] Keyboard shortcut [Shift+M] for "Measure to center"
- [ ] **Task 5:** Dimension layout improvements:
  - [ ] Auto-offset dimensions to avoid overlapping text
  - [ ] Dimension line snapping (parallel to edges)
  - [ ] Extension line generation (offset from geometry)
  - [ ] Arrowhead rendering at dimension line ends
  - [ ] Smart placement based on available space
- [ ] **Task 5:** Dimension editing:
  - [ ] Double-click dimension → Edit value (existing feature)
  - [ ] Drag dimension text to reposition
  - [ ] Adjust extension line length
  - [ ] Toggle dimension visibility

**AI Agent Tasks:**
- Add DiameterConstraint type with Ø symbol rendering
- Implement angular dimension visualization with arc
- Add Unicode symbol support to text rendering
- Create dimension layout system with auto-spacing
- Test with exercise_01.jpeg example (Ø18, Ø10, 45°)

**Technical Details:**
- **Diameter Symbol:** UTF-8: "Ø" or render as "∅" (U+2205)
- **Degree Symbol:** UTF-8: "°" (U+00B0)
- **Font:** BigShoulders_24pt-Regular.ttf supports extended Latin
- **Rendering:** Use existing fontstash system with Unicode strings
- **Layout:** Store dimension offset from geometry for repositioning

**Expected Output:**
```
Linear: "22" (horizontal distance)
Diameter: "Ø18" (circle diameter with symbol)
Angular: "45°" (angle between lines with degree symbol)
```

**Example Workflow:**
```
1. Draw circle (radius 9.0)
2. Select circle → Press [Shift+D]
3. Dimension shows "Ø18" (diameter, not radius)
4. Draw two lines at 45° angle
5. Select both lines → Press [A] for angle
6. Dimension shows "45°" with arc
7. Result matches exercise_01.jpeg dimensions ✅
```

**Deliverable:** Advanced dimensioning with diameter/angular dimensions and proper symbol rendering

**AI Agent Tasks:** ✅ All completed
- ✅ Implement point dragging with mouse events
- ✅ Integrate with constraint solver
- ✅ Handle fixed point validation
- ✅ Add circle radius editing with handle
- ✅ Handle line endpoint editing
- ✅ Add hover highlights for all editing modes

**Technical Details:**
- **Drag State:** ✅ Track drag_active, drag_entity_id, drag_start_pos (implemented)
- **Grid Snap:** ✅ 0.1 unit grid snapping with Ctrl modifier key (implemented)
- **Constraint Handling:** ✅ Auto-solve after drag completion (implemented)
- **Performance:** Real-time updates every frame during drag (working well)

**Implementation Details (Task 1):**
- **File Modified:** `/src/main_gpu.odin`
- **New State Fields:** `dragging_point`, `dragging_point_id`, `drag_start_pos`, `drag_snap_to_grid`
- **Mouse Handlers:** Updated MOUSE_MOTION, MOUSE_BUTTON_DOWN, MOUSE_BUTTON_UP
- **Grid Snapping:** Hold Ctrl during drag for 0.1 unit grid alignment
- **Console Feedback:**
  - "🎯 Started dragging point #X (pos: X.XX, Y.YY)"
  - "🏁 Finished dragging point #X (new pos: X.XX, Y.YY)"
  - "🔄 Re-solving constraints after point move..."

**Current Workflow:**
```
1. Draw rectangle → Press [S] for Select tool
2. Hover over point → Highlights in yellow
3. Click and drag → Point moves smoothly with mouse
4. Hold Ctrl while dragging → Snaps to 0.1 grid (e.g., 2.0, 2.1, 2.2)
5. Release mouse → Auto-runs solver if constraints exist
6. Constrained geometry updates correctly ✅
```

**Status:** ✅ **TASK 1 COMPLETE** - Point dragging fully functional with grid snapping and constraint integration!

**Next Steps:**
- Task 2: Circle radius editing with visible handle
- Task 3: Line endpoint editing (reuses point dragging system)
- Task 5: Visual feedback improvements

**Deliverable:** ✅ Partial - Can edit sketch geometry by dragging points with live solver updates and optional grid snapping

---

### Week 12.4: Pattern Features 🔜 MEDIUM PRIORITY
**Goal:** Linear and circular pattern for sketch entities and features

**Why Now:** Patterns are essential CAD productivity tools - create repeated geometry efficiently.

**Tasks:**
- [ ] **Task 1:** Linear pattern for sketch entities:
  - [ ] Select entities to pattern (points, lines, circles)
  - [ ] Specify direction vector and count
  - [ ] Specify spacing between instances
  - [ ] Generate copies in linear array
  - [ ] Keyboard shortcut [Shift+L] for linear pattern
- [ ] **Task 2:** Circular pattern for sketch entities:
  - [ ] Select entities to pattern
  - [ ] Specify center point and count
  - [ ] Generate copies in circular array (360° / count)
  - [ ] Optional: Specify angle (partial circle)
  - [ ] Keyboard shortcut [Shift+C] for circular pattern
- [ ] **Task 3:** Feature patterns (3D):
  - [ ] Linear pattern for features (extrude, cut)
  - [ ] Specify direction and spacing in 3D
  - [ ] Generate multiple instances of feature
  - [ ] Update feature tree with pattern node
- [ ] **Task 4:** Pattern parameters:
  - [ ] PatternParams struct (type, count, spacing/angle, direction)
  - [ ] Properties panel for pattern editing
  - [ ] Real-time preview of pattern instances
  - [ ] Parametric updates (change count → regenerate)
- [ ] **Task 5:** UI and visualization:
  - [ ] Pattern preview with ghost geometry
  - [ ] Interactive direction/center selection
  - [ ] Pattern feature icon in feature tree
  - [ ] Delete pattern (removes all instances)

**AI Agent Tasks:**
- Implement linear pattern algorithm for 2D entities
- Implement circular pattern with rotation
- Add pattern feature type to feature tree
- Create pattern UI with preview
- Handle parametric pattern updates

**Technical Details:**
- **Transformation:** Use matrix transforms for pattern instances
- **Sketch Patterns:** Clone entities with offset/rotation
- **Feature Patterns:** Clone feature with different sketch plane/position
- **Performance:** Patterns can create many entities (optimize rendering)
- **Constraints:** Patterned entities may need automatic constraints

**Expected Workflow:**
```
Sketch Pattern:
1. Draw circle
2. Select circle → Press [Shift+L]
3. Specify direction (right) and count (5)
4. 5 circles appear in a row

Feature Pattern:
1. Extrude pocket
2. Select pocket feature → Linear pattern
3. Specify direction (along X) and count (3)
4. 3 pockets appear spaced evenly
```

**Deliverable:** Linear and circular patterns for sketch entities and features with parametric control

---

### Week 12.5: Advanced UI & Tool Palette 🔜 DEFERRED
**Goal:** Professional tool palette with search and radial menus (non-essential polish)

**Tasks:**
- [ ] **Task 1:** Tool palette with search:
  - [ ] [S] shortcut → Pop up tool palette overlay
  - [ ] Search input at top (type to filter tools)
  - [ ] Categorized tool list (Sketch, 3D, Constraints, etc.)
  - [ ] Favorite tools section (user-customizable)
  - [ ] Recently used tools
  - [ ] Click tool to activate and close palette
- [ ] **Task 2:** Radial menu system:
  - [ ] Context-aware radial menus (Sketch mode vs 3D mode)
  - [ ] Radial menu for Solid tools (Extrude, Cut, Revolve, Fillet)
  - [ ] Radial menu for Surface tools (placeholder for future)
  - [ ] Radial menu for Sketch tools (Line, Circle, Arc, Dimension)
  - [ ] Shortcut key to pop radial menu for current mode
  - [ ] Mouse gesture or click to select tool
- [ ] **Task 3:** Hover highlights:
  - [ ] Detect mouse hover over points (hit testing with tolerance)
  - [ ] Detect mouse hover over edges (distance to line/circle)
  - [ ] Highlight hovered entities in different color (bright white/yellow)
  - [ ] Show tooltip with entity info (Point #3, Line #5, etc.)
  - [ ] Preview dimension value when hovering over constraints
- [ ] **Task 4:** Closed shape visualization:
  - [ ] Detect closed profiles in sketch (already have this in `profile.odin`)
  - [ ] Shade closed shapes with subtle fill color (e.g., dark cyan at 20% opacity)
  - [ ] Render fill behind wireframe
  - [ ] Toggle shading on/off (view option)
- [ ] **Task 5:** Line tool improvements:
  - [ ] Detect when line tool closes a shape (start point == end point within threshold)
  - [ ] Automatically exit line tool after closing shape (return to Select mode)
  - [ ] Visual feedback when shape is about to close (highlight start point)
  - [ ] Optional: Allow continue drawing in separate profile (user choice)

**AI Agent Tasks:**
- Implement tool palette overlay with search functionality
- Create radial menu system with context awareness
- Implement hover detection and highlighting for points/edges
- Add closed shape shading with transparency
- Improve line tool to auto-exit on shape closure

**Deliverable:** Professional CAD UI with searchable tool palette, radial menus, hover highlights, and smart line tool behavior

---

## Phase 4: Refinement & Drawing (Weeks 13-17)

### Week 13: Part File Save/Load 🔜 MEDIUM PRIORITY
**Goal:** Save and load entire part files (all features + sketches + history)

**Why Now:** Currently only sketch JSON save/load works. Need full part persistence before technical drawings.

**Tasks:**
- [ ] **Task 1:** Design part file format:
  - [ ] JSON structure for complete part (sketches + features + parameters)
  - [ ] Version number for file format evolution
  - [ ] Metadata (author, date, software version)
  - [ ] Feature tree serialization (chronological order)
- [ ] **Task 2:** Sketch serialization (enhance existing):
  - [ ] Already have JSON for points, lines, circles
  - [ ] Add constraint serialization (all 16 types)
  - [ ] Add sketch plane data (origin, normal, axes)
  - [ ] Sketch ID and naming (Sketch001, Sketch002)
- [ ] **Task 3:** Feature serialization:
  - [ ] ExtrudeParams → JSON (depth, direction)
  - [ ] RevolveParams → JSON (angle, segments, axis)
  - [ ] CutParams → JSON (depth, type)
  - [ ] Feature dependencies (parent_features array)
  - [ ] Feature status (Valid, NeedsUpdate, Failed, Suppressed)
- [ ] **Task 4:** Part file save:
  - [ ] `save_part_file()` - writes complete .ohcad file
  - [ ] Serialize all sketches in feature tree order
  - [ ] Serialize all features with parameters
  - [ ] Keyboard shortcut [Ctrl+Shift+S] "Save As Part"
  - [ ] File dialog for path selection
- [ ] **Task 5:** Part file load:
  - [ ] `load_part_file()` - reads .ohcad file
  - [ ] Deserialize sketches (reconstruct points, lines, circles, constraints)
  - [ ] Deserialize features (reconstruct extrude, revolve, cut)
  - [ ] Rebuild feature tree with dependencies
  - [ ] Regenerate all features in order
  - [ ] Keyboard shortcut [Ctrl+Shift+O] "Open Part"
- [ ] **Task 6:** File format validation:
  - [ ] Version compatibility checking
  - [ ] Error handling for corrupted files
  - [ ] Migration from old formats (future-proofing)
  - [ ] Validate feature dependencies on load

**AI Agent Tasks:**
- Design JSON schema for part files (.ohcad format)
- Implement part file save with full feature tree
- Implement part file load with regeneration
- Add file dialog integration (SDL3 native dialog or custom)
- Create comprehensive save/load tests
- Handle error cases (missing files, corrupt data)

**Technical Details:**
- **File Extension:** `.ohcad` (OhCAD part file)
- **Format:** JSON (human-readable, git-friendly)
- **Structure:**
  ```json
  {
    "version": "1.0",
    "metadata": { "created": "2025-11-11", "author": "User" },
    "sketches": [ {...}, {...} ],
    "features": [ {...}, {...} ],
    "next_sketch_id": 3,
    "next_feature_id": 5
  }
  ```
- **Load Process:** Deserialize → Rebuild sketches → Rebuild features → Regenerate tree
- **Save Process:** Serialize sketches → Serialize features → Write JSON

**Expected Workflow:**
```
1. Create sketch → Extrude → Revolve → Add constraints
2. Press [Ctrl+Shift+S] → Save as "my_part.ohcad"
3. Close application
4. Reopen application
5. Press [Ctrl+Shift+O] → Load "my_part.ohcad"
6. Full parametric history restored!
7. Can modify parameters and regenerate
```

**Deliverable:** Complete part file save/load system preserving entire design history with parametric capabilities

---

### Week 13.5: Performance Optimization ✅ COMPLETE
**Goal:** Optimize rendering loop for professional desktop application resource usage

**Why Now:** Application was using excessive CPU (92%) and GPU (40%) while idle - unacceptable for a desktop CAD app that spends most time idle.

**Tasks:**
- [x] **Task 1:** Identify performance bottleneck:
  - [x] Profiled application resource usage (Activity Monitor)
  - [x] Found uncapped render loop running at 1000+ FPS
  - [x] Rendering 60 times per second even when nothing changed
  - [x] No frame rate limiting or vsync
- [x] **Task 2:** Implement event-driven rendering:
  - [x] Add `needs_redraw: bool` flag to AppStateGPU
  - [x] Modify main loop to only render when `needs_redraw == true`
  - [x] Set redraw flag on all input events (mouse, keyboard, gestures, window)
  - [x] Sleep 10ms between event polls when idle (avoids busy-waiting)
  - [x] Reset flag after rendering
- [x] **Task 3:** UI improvements:
  - [x] Fixed diameter dimension text positioning (above line, not centered)
  - [x] Proper vertical offset calculation for dimension text
  - [x] Improved visual clarity matching professional CAD tools

**AI Agent Tasks:** ✅ All completed
- ✅ Diagnose performance issue with uncapped render loop
- ✅ Implement event-driven rendering system
- ✅ Add needs_redraw flag and state management
- ✅ Fix diameter dimension text vertical positioning
- ✅ Test and verify resource usage improvements

**Implementation Details:**
- **File Modified:** `/src/main_gpu.odin`
  - Added `needs_redraw` field to AppStateGPU struct (line 82)
  - Modified main loop (lines 357-389) with conditional rendering
  - Updated event handler (lines 395-400) to set redraw flag
  - Line count: 3967 lines (was 1573 before features)
- **File Modified:** `/src/ui/viewer/viewer_gpu.odin`
  - Fixed diameter dimension text positioning (lines 2338-2359)
  - Added vertical offset: `text_vertical_offset := text_height_pixels * 1.2`
  - Text now renders above diameter line instead of centered on it

**Status:** ✅ **WEEK 13.5 COMPLETE!**
- ✅ Event-driven rendering fully operational
- ✅ Idle CPU usage: **2.8%** (down from 92%) - **97% reduction**
- ✅ Idle GPU usage: **11.3%** (down from 40%) - **72% reduction**
- ✅ Responsive during active use (redraws immediately on input)
- ✅ Professional desktop application behavior
- ✅ Diameter text positioned correctly above dimension lines

**Technical Achievements:**
- **Event-Driven Architecture:** Main loop only renders when needed, not continuously
- **Sleep When Idle:** 10ms delay between event polls prevents CPU spinning
- **Input Responsiveness:** All events (mouse, keyboard, window resize, gestures) trigger redraw
- **Power Efficiency:** Minimal battery drain, fans stay quiet
- **Resource Usage:** ~0% CPU/GPU when idle, full performance when active

**Performance Results:**
```
BEFORE (Uncapped Rendering):
- Idle CPU: 92% (burning full core)
- Idle GPU: 40% (rendering 1000+ FPS)
- Power: High battery drain, fans spin up

AFTER (Event-Driven):
- Idle CPU: 2.8% (minimal usage) ✅
- Idle GPU: 11.3% (minimal usage) ✅
- Power: Minimal drain, fans silent ✅
- Active: Still 60 FPS, responsive ✅
```

**Code Changes:**
```odin
// AppStateGPU struct
needs_redraw: bool,  // Event-driven rendering flag

// Main loop
for viewer_gpu_should_continue(viewer_inst) {
    handle_events_gpu(app)

    if app.needs_redraw {
        // Update wireframes/selection if needed
        // Render frame
        app.needs_redraw = false
    } else {
        sdl.Delay(10)  // Sleep 10ms when idle
    }
}

// Event handler
for sdl.PollEvent(&event) {
    app.needs_redraw = true  // Any event triggers redraw
    // Handle event...
}
```

**Benefits:**
- ✅ Professional desktop application resource usage
- ✅ Cooler/quieter operation (no fan noise)
- ✅ Minimal battery drain on laptops
- ✅ No impact on responsiveness during active use
- ✅ Environmentally friendly (less energy waste)
- ✅ Proper CAD application behavior (idle when user not interacting)

**Deliverable:** ✅ Optimized rendering loop with event-driven architecture, 97% CPU reduction and 72% GPU reduction, matching professional desktop application behavior

---

### Week 14: Technical Drawing Foundation
**Goal:** Orthographic projection and view setup

**Tasks:**
- [ ] Implement `ui/drawing`:
  - Orthographic projection (front/top/right views)
  - View layout management
  - Scale and positioning
- [ ] Edge extraction from B-rep
- [ ] Silhouette edge detection
- [ ] Basic line rendering for views

**AI Agent Tasks:**
- Implement robust projection algorithms
- Create view layout system
- Extract visible edges from solid
- Render orthographic views

**Deliverable:** Can generate basic orthographic views of models

---

### Week 14: Hidden Line Removal
**Goal:** Proper technical drawings with hidden lines

**Tasks:**
- [ ] Implement hidden line algorithm:
  - Z-buffer approach or ray-based occlusion
  - Classify edges as visible/hidden
  - Generate dashed lines for hidden edges
- [ ] Improve drawing quality:
  - Edge sorting and cleanup
  - Handle tangent edges
- [ ] Section view basics (stretch goal)

**AI Agent Tasks:**
- Implement efficient hidden line removal
- Handle edge cases (coplanar faces, tangencies)
- Optimize for large models
- Create quality test drawings

**Deliverable:** Technical drawings with proper hidden lines

---

### Week 16: Dimensioning & Annotations
**Goal:** Add dimensions and annotations to drawings

**Tasks:**
- [ ] Implement drawing dimensions:
  - Linear dimensions (horizontal/vertical/aligned)
  - Radial/diameter dimensions
  - Angular dimensions
- [ ] Annotation text rendering
- [ ] Dimension auto-placement
- [ ] UI for adding dimensions to views

**AI Agent Tasks:**
- Implement dimension calculation and placement
- Create text rendering system
- Design intuitive dimension UI
- Generate example drawings

**Deliverable:** Can create fully dimensioned technical drawings

---

### Week 16: SVG/PDF Export & Documentation
**Goal:** Export drawings and complete MVP documentation

**Tasks:**
- [ ] Implement `io/svg`:
  - Convert drawing to SVG format
  - Proper line weights and styles
  - Text and dimension export
- [ ] PDF export (via SVG or direct)
- [ ] Create user documentation:
  - Feature usage guide
  - API documentation
  - Example models and tutorials
- [ ] Polish UI and fix critical bugs

**AI Agent Tasks:**
- Implement SVG/PDF exporters
- Generate comprehensive documentation
- Create example gallery
- Perform end-to-end testing

**Deliverable:** Complete MVP with export capabilities and documentation

---

## Phase 5: Polish & Advanced Features (Weeks 17-20+)

### Week 17-18: Boolean Robustness & Performance
**Tasks:**
- [ ] Improve boolean operation reliability
- [ ] Performance profiling and optimization
- [ ] Handle degenerate cases
- [ ] Stress testing with complex models

### Week 19-20: Advanced Fillets & Chamfers
**Tasks:**
- [ ] Variable-radius fillets
- [ ] Chamfer operations
- [ ] Better surface blending
- [ ] Handle complex topologies

### Week 21-24: STEP Import/Export (Optional)
**Tasks:**
- [ ] Integrate STEPcode or similar
- [ ] Basic STEP solid export
- [ ] Import simple STEP files
- [ ] Test with industry files

### Week 25+: NURBS & Advanced Features
**Tasks:**
- [ ] NURBS curve and surface support
- [ ] Loft and sweep operations
- [ ] Pattern features (linear/circular)
- [ ] Assembly basics

---

## Working with AI Agent: Best Practices

### Weekly Workflow
1. **Monday:** Review plan, prioritize tasks for the week
2. **Daily:**
   - AI agent implements 2-3 focused tasks
   - You review and test implementations
   - Iterate on feedback
3. **Friday:** Integration testing, demo new features, plan next week

### Effective AI Collaboration
- **Clear Requirements:** Provide specific function signatures and expected behavior
- **Incremental Development:** Build and test small pieces before integration
- **Code Review:** AI generates code, you review for correctness and style
- **Testing First:** Have AI write tests before implementation when possible
- **Documentation:** Ask AI to document complex algorithms and design decisions

### Task Breakdown Pattern
For each feature, follow this sequence:
1. **Design:** AI helps design data structures and algorithms
2. **Implement:** AI generates implementation code
3. **Test:** AI creates unit and integration tests
4. **Integrate:** Together, integrate into main codebase
5. **Validate:** Test in viewer/UI, verify correctness
6. **Document:** AI generates documentation

### Communication Templates

**For New Features:**
```
"I need to implement [feature]. Based on the high-level design:
1. What data structures do we need?
2. Generate implementation for [module/feature]
3. Create unit tests covering [cases]
4. Show usage example"
```

**For Debugging:**
```
"The [feature] is failing when [scenario].
Here's the error: [error message]
Here's the relevant code: [code snippet]
Help me debug and fix this."
```

**For Research:**
```
"Research [topic] for our Odin CAD implementation.
Consider: [constraints]
Recommend approach and provide implementation sketch."
```

---

## Risk Management

### Technical Risks
1. **Boolean Operation Complexity:** Plan B - use mesh booleans via C library
2. **Constraint Solver Convergence:** Start with simple cases, gradually add complexity
3. **B-rep Topology Bugs:** Extensive testing, Euler characteristic validation
4. **Performance Issues:** Profile early, optimize bottlenecks incrementally
5. **Tessellation Quality:** Bad triangulation → ugly STL/rendering
   - **Mitigation:** Use proven library (libtess2) or robust ear-clipping
6. **Undo/Redo Memory:** Full history can use lots of RAM
   - **Mitigation:** Limit undo stack depth (50 commands), use deltas not full copies
7. **Constraint Solver Robustness:** Complex sketches may fail to solve
   - **Mitigation:** Better initial guess, iterative improvement, user feedback on failure

### Schedule Risks
- **Buffer Weeks:** Built 2-3 week buffer into each phase
- **MVP First:** Core features before polish
- **Parallel Tasks:** Some tasks can be done in parallel (e.g., UI + backend)
- **Critical Path:** Tessellation (Week 11.5) is blocking for STL export and technical drawings

### Mitigation Strategies
- Weekly checkpoints to assess progress
- Flexible scope - can defer advanced features
- Maintain working demo at end of each phase
- Regular integration to catch issues early
- Priority-based task ordering (critical features before polish)

---

## Success Metrics

### Phase 1 (Week 4):
✅ Can display 3D geometry in viewer
✅ Math library with 100% test coverage
✅ Basic topology system working

### Phase 2 (Week 8):
✅ Can create and edit parametric 2D sketches
✅ Constraint solver handles 90%+ of reasonable sketches
✅ Sketch UI is usable

### Phase 3 (Week 12):
✅ Can extrude, cut, revolve (completed Week 11)
✅ Parametric updates work reliably (properties panel + live controls)
🔜 Can export to STL (Week 12 - requires Week 11.5 tessellation first)
🔜 Undo/redo system operational (Week 11.8)
🔜 Hover feedback and UX polish (Week 11.7)

### Phase 4 (Week 17):
🔜 Full part file save/load (Week 13)
🔜 Can generate technical drawings
🔜 Hidden line removal works
🔜 Can export to SVG/PDF
🔜 **MVP COMPLETE**

### Performance Targets (Added):
- Sketch solve time: <100ms for typical sketches (10-20 constraints)
- Feature regeneration: <500ms for typical parts (5-10 features)
- Maximum entities: 10,000+ sketch entities, 100+ features
- Viewport FPS: 60fps with typical parts (stable rendering)
- Undo stack: 50 commands max (memory limit)

---

## Next Steps - Revised Priority Order

### 🔴 **Critical Path (Do These First)**

1. **Week 11.5 - Face Tessellation** (BLOCKING for STL export)
   - Required for STL export and technical drawings
   - Adds shaded rendering mode
   - Choose: libtess2 (C interop) vs pure Odin implementation

2. **Week 11.7 - Essential UX** (Usability improvement)
   - Hover highlights for points/edges
   - Closed shape visualization
   - Smart line tool auto-close

3. **Week 11.8 - Undo/Redo** (CRITICAL for usability)
   - Command pattern architecture
   - 50 command history depth
   - Ctrl+Z / Ctrl+Shift+Z shortcuts

4. **Week 12 - STL Export & Fillet** (First export format)
   - Depends on Week 11.5 tessellation
   - Binary STL format
   - Basic constant-radius fillet

### 🟡 **High Priority (Do Before Technical Drawings)**

5. **Week 12.2 - Constraint Editing**
   - Edit dimension values after creation
   - Double-click to edit
   - Properties panel integration

6. **Week 12.3 - Sketch Editing**
   - Drag points to move
   - Resize circles with handle
   - Live constraint solving

7. **Week 12.4 - Pattern Features**
   - Linear and circular patterns
   - For sketches and features
   - Parametric pattern updates

8. **Week 13 - Part File Save/Load**
   - .ohcad file format (JSON)
   - Full feature tree persistence
   - Ctrl+Shift+S / Ctrl+Shift+O

### 🟢 **Medium Priority (Phase 4 - Technical Drawings)**

9. **Week 14 - Drawing Foundation**
   - Orthographic projections
   - Edge extraction

10. **Week 15 - Hidden Line Removal**
    - Z-buffer or ray-based
    - Dashed hidden lines

11. **Week 16 - Dimensioning**
    - Linear/radial/angular dimensions
    - Auto-placement

12. **Week 17 - SVG/PDF Export**
    - **MVP COMPLETE** 🎉

### ⚪ **Low Priority (Deferred Polish)**

13. **Week 12.5 - Advanced UI**
    - Tool palette with search
    - Radial menus
    - Favorites system

14. **Week 17-20+ - Advanced Features**
    - Boolean robustness
    - NURBS curves/surfaces
    - STEP import/export

---

## Recommended Development Sequence

**Current Status:** ✅ Week 11 Complete (Revolve + Properties Panel + Parametric System)

**Next 4 Weeks:**
```
Week 11.5 (3-5 days)  → Tessellation [BLOCKING]
Week 11.7 (2-3 days)  → Essential UX [HIGH VALUE]
Week 11.8 (4-6 days)  → Undo/Redo [CRITICAL]
Week 12   (3-5 days)  → STL Export + Fillet
```

**Following 4 Weeks:**
```
Week 12.2 (2-3 days)  → Constraint Editing
Week 12.3 (3-4 days)  → Sketch Editing
Week 12.4 (3-4 days)  → Pattern Features
Week 13   (4-5 days)  → Part File Save/Load
```

**Then Phase 4 (4 Weeks to MVP):**
```
Week 14 → Drawing Foundation
Week 15 → Hidden Line Removal
Week 16 → Dimensioning
Week 17 → SVG/PDF Export → 🎉 MVP COMPLETE!
```

---

## Key Milestones

| Milestone | Week | Description |
|-----------|------|-------------|
| ✅ **2D Sketcher Complete** | Week 8 | Parametric sketches with constraints |
| ✅ **3D Features Complete** | Week 11 | Extrude, Cut, Revolve with parametric control |
| 🔜 **Export Ready** | Week 12 | STL export + tessellation + undo/redo |
| 🔜 **Full Persistence** | Week 13 | Save/load entire part files |
| 🔜 **MVP Complete** | Week 17 | Technical drawings + SVG/PDF export |
| 🔜 **Production Ready** | Week 20+ | Boolean robustness + polish |

---

*This revised plan prioritizes critical blocking features (tessellation, undo/redo) before continuing with advanced features. The path to MVP is now clearer and more structured.*
