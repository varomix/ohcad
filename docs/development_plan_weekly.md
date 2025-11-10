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

### Week 10.5: Boolean Operations (Cut/Pocket)
**Goal:** Boolean subtract for pocket/cut features

**Tasks:**
- [ ] Research boolean approaches:
  - Mesh boolean libraries (evaluate Cork, libigl bindings)
  - Simple CSG via mesh operations
- [ ] Implement pocket/cut feature:
  - Create cut solid from sketch + depth
  - Boolean subtract from base solid
  - Update B-rep topology
- [ ] Handle boolean failures gracefully
- [ ] UI for selecting face to sketch on

**AI Agent Tasks:**
- Integrate or implement mesh boolean operations
- Create robust boolean pipeline with error handling
- Implement face selection and sketch plane creation
- Test with various cut geometries

**Deliverable:** Can create pockets/cuts in existing solids

---

### Week 11: Revolve Feature & Parametric Regen
**Goal:** Revolve feature and full parametric update

**Tasks:**
- [ ] Implement `features/revolve`:
  - Revolve profile around axis
  - Handle revolution angles (partial/full)
  - Generate swept surfaces
- [ ] Complete parametric system:
  - Feature tree traversal and regeneration
  - Dependency tracking
  - Efficient partial updates
- [ ] UI for editing feature parameters
- [ ] Change sketch dimension → full model update

**AI Agent Tasks:**
- Implement revolve algorithm
- Create efficient feature regeneration system
- Build UI for parameter editing
- Test complex dependency chains

**Deliverable:** Working revolve feature with full parametric model updates

---

### Week 12: STL Export & Basic Fillet
**Goal:** First export format and simple fillet operation

**Tasks:**
- [ ] Implement `io/stl`:
  - B-rep to triangle mesh conversion
  - STL binary format writer
  - Export with proper normals
- [ ] Basic constant-radius fillet:
  - Select edges to fillet
  - Generate fillet surface (simple rolling ball)
  - Update topology
- [ ] UI for STL export and fillet selection
- [ ] Test with external CAD viewers (FreeCAD, Fusion 360)

**AI Agent Tasks:**
- Implement STL export with proper mesh quality
- Create simple fillet algorithm for basic cases
- Handle edge selection UI
- Generate test models for validation

**Deliverable:** Can export models to STL and apply basic fillets

---

### Week 12.5: Advanced UI & Tool Palette 🔜 PLANNED
**Goal:** Professional tool palette with search, radial menus, and hover highlights

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

## Phase 4: Refinement & Drawing (Weeks 13-16)

### Week 13: Technical Drawing Foundation
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

### Week 15: Dimensioning & Annotations
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

### Schedule Risks
- **Buffer Weeks:** Built 2-3 week buffer into each phase
- **MVP First:** Core features before polish
- **Parallel Tasks:** Some tasks can be done in parallel (e.g., UI + backend)

### Mitigation Strategies
- Weekly checkpoints to assess progress
- Flexible scope - can defer advanced features
- Maintain working demo at end of each phase
- Regular integration to catch issues early

---

## Success Metrics

### Phase 1 (Week 4):
✓ Can display 3D geometry in viewer
✓ Math library with 100% test coverage
✓ Basic topology system working

### Phase 2 (Week 8):
✓ Can create and edit parametric 2D sketches
✓ Constraint solver handles 90%+ of reasonable sketches
✓ Sketch UI is usable

### Phase 3 (Week 12):
✓ Can extrude, cut, revolve
✓ Parametric updates work reliably
✓ Can export to STL

### Phase 4 (Week 16):
✓ Can generate technical drawings
✓ Hidden line removal works
✓ Can export to SVG/PDF
✓ **MVP COMPLETE**

---

## Next Steps

1. **Review this plan** - Adjust timing based on your availability
2. **Start Week 1** - AI agent generates project structure
3. **Set up repository** - Git repo with proper .gitignore
4. **Create CLAUDE.md** - Document conventions for AI agent
5. **Begin implementation** - Start with core math module

**Ready to start?** Let me know and I'll begin with Week 1 tasks:
- Generate complete Odin project structure
- Implement core math library
- Set up test infrastructure
- Create build system

---

*This plan assumes ~20-30 hours per week of development time. Adjust pace as needed.*
