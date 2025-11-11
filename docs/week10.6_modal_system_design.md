# Week 10.6: Modal System & Multiple Sketches - Design Document

**Critical Architectural Change:** Implement proper CAD modal system with Sketch Mode and Solid Mode

---

## Problem Statement

**Current Architecture:**
- ❌ Always in sketch mode from startup
- ❌ One global sketch (can't have multiple independent sketches)
- ❌ All tools available at all times (confusing)
- ❌ No way to create new sketch on a face
- ❌ Cut operation reuses original sketch

**Why This is Wrong:**
Professional CAD software has clear modal separation:
- **Sketch Mode:** Draw 2D geometry, apply constraints
- **Solid Mode:** Select faces, extrude, cut, modify 3D geometry

---

## Proposed Architecture

### Application Modes

```odin
ApplicationMode :: enum {
    Solid,   // 3D modeling mode (default)
    Sketch,  // 2D sketching mode (explicit entry/exit)
}
```

### Mode-Specific Tools

**Solid Mode Tools:**
- **Select** - Select faces, edges, vertices (for operations)
- **Extrude** - Extrude selected sketch
- **Cut/Pocket** - Cut using selected sketch
- **Revolve** - (Future)
- **Fillet** - (Future)
- **Chamfer** - (Future)

**Sketch Mode Tools:**
- **Select** - Select sketch entities
- **Line** - Draw lines
- **Circle** - Draw circles
- **Arc** - Draw arcs
- **Dimension** - Add dimensions
- **Constraints** - H, V, Perpendicular, etc.

### Workflow Model

```
APPLICATION START
    ↓
[SOLID MODE] - No sketches, empty 3D view
    ↓
User: Press [N] "New Sketch" or click toolbar
    ↓
System: Show plane/face selector
    ↓
User: Select XY / YZ / ZX plane (or face)
    ↓
[SKETCH MODE] - Drawing on selected plane
    ↓
User: Draw lines, circles, constrain
    ↓
User: Press [ESC] "Exit Sketch" or click "Finish Sketch"
    ↓
[SOLID MODE] - Sketch visible in feature tree
    ↓
User: Select sketch in tree, press [E] "Extrude"
    ↓
[SOLID MODE] - 3D solid created
    ↓
User: Click on top face, press [N] "New Sketch"
    ↓
[SKETCH MODE] - Drawing on top face
    ↓
User: Draw pocket profile
    ↓
User: Press [ESC] "Exit Sketch"
    ↓
[SOLID MODE] - New sketch visible
    ↓
User: Select new sketch, press [T] "Cut"
    ↓
[SOLID MODE] - Pocket created
```

---

## Implementation Plan

### Phase 1: Core Modal System (4-6 hours)

**Data Structures:**
```odin
ApplicationMode :: enum {
    Solid,   // 3D modeling mode
    Sketch,  // 2D sketching mode
}

AppStateGPU :: struct {
    // ... existing fields ...

    // NEW: Modal system
    mode: ApplicationMode,            // Current mode
    active_sketch_id: int,            // ID of sketch being edited (-1 if none)

    // REMOVE: Global sketch
    // sketch: ^sketch.Sketch2D,  // DELETE THIS
}
```

**Functions:**
```odin
// Enter sketch mode
enter_sketch_mode :: proc(app: ^AppStateGPU, sketch_id: int) {
    app.mode = .Sketch
    app.active_sketch_id = sketch_id
    fmt.println("=== ENTERED SKETCH MODE ===")
}

// Exit sketch mode
exit_sketch_mode :: proc(app: ^AppStateGPU) {
    app.mode = .Solid
    app.active_sketch_id = -1
    fmt.println("=== EXITED TO SOLID MODE ===")
}

// Get active sketch (from feature tree)
get_active_sketch :: proc(app: ^AppStateGPU) -> ^sketch.Sketch2D {
    if app.active_sketch_id < 0 do return nil

    feature := ftree.feature_tree_get_feature(&app.feature_tree, app.active_sketch_id)
    if feature == nil do return nil
    if feature.type != .Sketch do return nil

    params, ok := feature.params.(ftree.SketchParams)
    if !ok do return nil

    return params.sketch_ref
}
```

**Tasks:**
- [x] Add `ApplicationMode` enum
- [ ] Add `mode` and `active_sketch_id` to `AppStateGPU`
- [ ] Remove global `app.sketch` field
- [ ] Implement `enter_sketch_mode()` and `exit_sketch_mode()`
- [ ] Implement `get_active_sketch()` helper
- [ ] Update all code that references `app.sketch` to use `get_active_sketch()`

---

### Phase 2: Sketch Creation Workflow (6-8 hours)

**Plane Selection:**
```odin
SketchPlaneType :: enum {
    XY,    // Front view
    YZ,    // Right view
    ZX,    // Top view
    Face,  // On a selected face
}

// Create new sketch on standard plane
create_sketch_on_plane :: proc(
    app: ^AppStateGPU,
    plane_type: SketchPlaneType,
) -> int {
    plane: sketch.SketchPlane

    switch plane_type {
    case .XY:
        plane = sketch.sketch_plane_xy()
    case .YZ:
        plane = sketch.sketch_plane_yz()
    case .ZX:
        plane = sketch.sketch_plane_zx()
    case .Face:
        // Extract plane from selected face
        assert(false, "Face selection not implemented yet")
    }

    // Create new sketch
    sketch_count := ftree.feature_tree_count_type(&app.feature_tree, .Sketch)
    sketch_name := fmt.aprintf("Sketch%03d", sketch_count + 1)

    new_sketch := new(sketch.Sketch2D)
    new_sketch^ = sketch.sketch_init(sketch_name, plane)

    // Add to feature tree
    sketch_id := ftree.feature_tree_add_sketch(&app.feature_tree, new_sketch, sketch_name)

    // Enter sketch mode
    enter_sketch_mode(app, sketch_id)

    fmt.printf("✅ Created %s on %v plane\n", sketch_name, plane_type)

    return sketch_id
}
```

**Tasks:**
- [ ] Implement `SketchPlaneType` enum
- [ ] Implement `create_sketch_on_plane()` function
- [ ] Add keyboard shortcuts:
  - **[N]** → Show plane selector menu
  - **[1]** → Create sketch on XY plane
  - **[2]** → Create sketch on YZ plane
  - **[3]** → Create sketch on ZX plane
- [ ] Add "New Sketch" button to toolbar (Solid Mode only)

---

### Phase 3: Tool Context Filtering (4-6 hours)

**Mode-Aware Tool Availability:**
```odin
is_tool_available :: proc(tool: sketch.SketchTool, mode: ApplicationMode) -> bool {
    switch mode {
    case .Solid:
        // Only Select tool available in Solid mode
        return tool == .Select

    case .Sketch:
        // All sketch tools available
        return true
    }

    return false
}
```

**Keyboard Shortcut Filtering:**
```odin
handle_key_down_gpu :: proc(app: ^AppStateGPU, key: sdl.Keycode, mods: sdl.Keymod) {
    // Mode-independent shortcuts
    switch key {
    case sdl.K_Q: app.viewer.should_close = true; return
    case sdl.K_HOME: v.camera_init(&app.viewer.camera, app.viewer.camera.aspect_ratio); return
    case sdl.K_F: ftree.feature_tree_print(&app.feature_tree); return
    }

    // Mode-specific shortcuts
    switch app.mode {
    case .Solid:
        handle_solid_mode_keys(app, key, mods)
    case .Sketch:
        handle_sketch_mode_keys(app, key, mods)
    }
}

handle_solid_mode_keys :: proc(app: ^AppStateGPU, key: sdl.Keycode, mods: sdl.Keymod) {
    switch key {
    case sdl.K_N:
        // New sketch - show plane selector
        fmt.println("New Sketch - Select plane: [1] XY, [2] YZ, [3] ZX")

    case sdl.K_1:
        create_sketch_on_plane(app, .XY)

    case sdl.K_2:
        create_sketch_on_plane(app, .YZ)

    case sdl.K_3:
        create_sketch_on_plane(app, .ZX)

    case sdl.K_E:
        // Extrude selected sketch
        perform_extrude(app)

    case sdl.K_T:
        // Cut using selected sketch
        perform_cut(app)
    }
}

handle_sketch_mode_keys :: proc(app: ^AppStateGPU, key: sdl.Keycode, mods: sdl.Keymod) {
    active_sketch := get_active_sketch(app)
    if active_sketch == nil do return

    switch key {
    case sdl.K_ESCAPE:
        // Exit sketch mode
        exit_sketch_mode(app)

    case sdl.K_S:
        sketch.sketch_set_tool(active_sketch, .Select)

    case sdl.K_L:
        sketch.sketch_set_tool(active_sketch, .Line)

    case sdl.K_C:
        sketch.sketch_set_tool(active_sketch, .Circle)

    case sdl.K_D:
        sketch.sketch_set_tool(active_sketch, .Dimension)

    case sdl.K_H:
        apply_horizontal_constraint(active_sketch)

    case sdl.K_V:
        apply_vertical_constraint(active_sketch)

    case sdl.K_X:
        solve_constraints(active_sketch)

    case sdl.K_DELETE:
        if sketch.sketch_delete_selected(active_sketch) {
            app.needs_wireframe_update = true
        }
    }
}
```

**Tasks:**
- [ ] Implement `is_tool_available()` for context filtering
- [ ] Split keyboard handlers into `handle_solid_mode_keys()` and `handle_sketch_mode_keys()`
- [ ] Update toolbar to show only context-appropriate tools
- [ ] Gray out unavailable tools in toolbar

---

### Phase 4: UI Updates (4-6 hours)

**Mode Indicator:**
```
┌─────────────────────────────────────────────┐
│  MODE: ■ SKETCH  [Sketch002 on XY plane]   │ ← Prominent mode banner
│                                             │
│  [Esc] Exit Sketch    Tools: L C A D H V   │
└─────────────────────────────────────────────┘
```

**Toolbar Updates:**
```odin
ui_render_toolbar :: proc(ctx: ^UIContext, state: ^CADUIState, mode: ApplicationMode) {
    if mode == .Solid {
        // Solid mode toolbar
        if ui.button(ctx, "New Sketch", btn_x, btn_y) {
            // Show plane selector
        }
        if ui.button(ctx, "Extrude", btn_x, btn_y) {
            // Extrude selected sketch
        }
        if ui.button(ctx, "Cut", btn_x, btn_y) {
            // Cut using selected sketch
        }
    } else {
        // Sketch mode toolbar
        if ui.button(ctx, "Exit Sketch", btn_x, btn_y) {
            // Exit to solid mode
        }
        if ui.button(ctx, "Line", btn_x, btn_y) {
            // Line tool
        }
        if ui.button(ctx, "Circle", btn_x, btn_y) {
            // Circle tool
        }
        // ... more sketch tools
    }
}
```

**Tasks:**
- [ ] Add prominent mode indicator banner at top
- [ ] Show active sketch name in mode banner
- [ ] Context-sensitive toolbar (changes based on mode)
- [ ] Update status bar to show mode
- [ ] Visual indication when in Sketch mode (e.g., sketch plane highlight)

---

### Phase 5: Face Selection (8-10 hours)

**Face Representation in SimpleSolid:**
```odin
SimpleFace :: struct {
    vertices: [dynamic]^extrude.Vertex,  // Ordered vertices forming face
    normal: m.Vec3,                       // Face normal
    center: m.Vec3,                       // Face center
}

SimpleSolid :: struct {
    vertices: [dynamic]^Vertex,
    edges: [dynamic]^Edge,
    faces: [dynamic]SimpleFace,  // NEW
}
```

**Face Selection:**
```odin
SelectedFace :: struct {
    solid_feature_id: int,
    face_index: int,
}

AppStateGPU :: struct {
    // ... existing fields ...
    selected_face: Maybe(SelectedFace),  // Currently selected face
}

// Ray-cast to select face
select_face_at_cursor :: proc(app: ^AppStateGPU, screen_x, screen_y: f64) -> bool {
    // Cast ray from screen to 3D
    ray_origin, ray_dir := screen_to_world_ray(app, screen_x, screen_y)

    closest_dist := max(f64)
    closest_face: Maybe(SelectedFace)

    // Test each solid
    for feature in app.feature_tree.features {
        if feature.result_solid == nil do continue

        // Test each face
        for face, face_idx in feature.result_solid.faces {
            // Ray-plane intersection
            t, hit := ray_plane_intersection(ray_origin, ray_dir, face.center, face.normal)
            if !hit || t >= closest_dist do continue

            hit_point := ray_origin + ray_dir * t

            // Point-in-polygon test
            if point_inside_face(hit_point, &face) {
                closest_dist = t
                closest_face = SelectedFace{
                    solid_feature_id = feature.id,
                    face_index = face_idx,
                }
            }
        }
    }

    app.selected_face = closest_face
    return closest_face != nil
}
```

**Create Sketch on Face:**
```odin
create_sketch_on_face :: proc(app: ^AppStateGPU, selected_face: SelectedFace) -> int {
    // Get face
    feature := ftree.feature_tree_get_feature(&app.feature_tree, selected_face.solid_feature_id)
    face := &feature.result_solid.faces[selected_face.face_index]

    // Create sketch plane from face
    plane := sketch.SketchPlane{
        origin = face.center,
        normal = face.normal,
        x_axis = compute_face_x_axis(face),
        y_axis = glsl.cross(face.normal, x_axis),
    }

    // Create sketch
    sketch_count := ftree.feature_tree_count_type(&app.feature_tree, .Sketch)
    sketch_name := fmt.aprintf("Sketch%03d", sketch_count + 1)

    new_sketch := new(sketch.Sketch2D)
    new_sketch^ = sketch.sketch_init(sketch_name, plane)

    sketch_id := ftree.feature_tree_add_sketch(&app.feature_tree, new_sketch, sketch_name)
    enter_sketch_mode(app, sketch_id)

    return sketch_id
}
```

**Tasks:**
- [ ] Add `SimpleFace` structure to SimpleSolid
- [ ] Update extrude to generate faces (top, bottom, sides)
- [ ] Implement face hit testing (ray-cast + point-in-polygon)
- [ ] Add face selection state to AppState
- [ ] Implement face highlighting (yellow overlay)
- [ ] Implement `create_sketch_on_face()`
- [ ] Wire up: Click face → Press [N] → Create sketch on face

---

### Phase 6: Multiple Sketch Rendering (2-4 hours)

**Current:** Only one global sketch rendered

**New:** Render all sketches from feature tree
```odin
render_all_sketches :: proc(app: ^AppStateGPU, cmd, pass, mvp) {
    for feature in app.feature_tree.features {
        if feature.type != .Sketch do continue
        if !feature.visible do continue

        params, ok := feature.params.(ftree.SketchParams)
        if !ok || params.sketch_ref == nil do continue

        // Render sketch
        wireframe := v.sketch_to_wireframe_gpu(params.sketch_ref)
        defer v.wireframe_mesh_gpu_destroy(&wireframe)

        // Active sketch in bright cyan, others in dark cyan
        color := app.active_sketch_id == feature.id ?
            [4]f32{0.0, 1.0, 1.0, 1.0} :
            [4]f32{0.0, 0.4, 0.5, 1.0}

        v.viewer_gpu_render_wireframe(app.viewer, cmd, pass, &wireframe, color, mvp, 3.0)
    }
}
```

**Tasks:**
- [ ] Implement `render_all_sketches()` function
- [ ] Render active sketch in bright color, others in muted color
- [ ] Show sketch plane indicator for active sketch
- [ ] Cache sketch wireframes for performance

---

## Updated Keyboard Shortcuts

### Global (Any Mode)
- **[Q]** - Quit
- **[HOME]** - Reset camera
- **[F]** - Print feature tree

### Solid Mode
- **[N]** - New sketch (shows plane selector)
- **[1]** - New sketch on XY plane
- **[2]** - New sketch on YZ plane
- **[3]** - New sketch on ZX plane
- **[E]** - Extrude selected sketch
- **[T]** - Cut using selected sketch
- **[+]/[-]** - Adjust selected feature parameter
- **[R]** - Regenerate all features
- **Click Face** - Select face for operations

### Sketch Mode
- **[ESC]** - Exit sketch mode (back to Solid)
- **[S]** - Select tool
- **[L]** - Line tool
- **[C]** - Circle tool
- **[A]** - Arc tool
- **[D]** - Dimension tool
- **[H]** - Horizontal constraint
- **[V]** - Vertical constraint
- **[X]** - Solve constraints
- **[DELETE]** - Delete selected
- **[P]** - Print profile detection

---

## Implementation Phases

### Week 10.6: Modal System Foundation (20-24 hours)
- **Phase 1:** Core modal system (4-6 hours)
- **Phase 2:** Sketch creation workflow (6-8 hours)
- **Phase 3:** Tool context filtering (4-6 hours)
- **Phase 4:** UI updates (4-6 hours)

**Deliverable:** Can create multiple sketches on XY/YZ/ZX planes, enter/exit sketch mode, context-sensitive tools

### Week 10.7: Face Selection (10-12 hours)
- **Phase 5:** Face selection and sketch-on-face (8-10 hours)
- **Phase 6:** Multiple sketch rendering (2-4 hours)

**Deliverable:** Can select faces, create sketches on faces, full pocket workflow

---

## Success Criteria

### Week 10.6 Complete:
✅ Application starts in Solid Mode (no sketch active)
✅ Press [1] creates new sketch on XY plane, enters Sketch Mode
✅ Can draw lines/circles in Sketch Mode
✅ Press [ESC] exits to Solid Mode
✅ Can create 2nd sketch on YZ plane
✅ Can select sketch from feature tree
✅ Press [E] extrudes selected sketch
✅ Mode indicator clearly shows current mode
✅ Toolbar changes based on mode

### Week 10.7 Complete:
✅ Click on top face of box → Face highlights
✅ Press [N] → Creates new sketch on face
✅ Draw pocket profile on face
✅ Exit sketch, select it, press [T] → Creates pocket
✅ Full professional CAD workflow operational

---

## Migration Strategy

**Breaking Changes:**
- Remove global `app.sketch` field
- All sketch access must go through `get_active_sketch()`
- Sketch tools only work in Sketch Mode

**Migration Path:**
1. Add modal system alongside existing code
2. Default to Sketch Mode on startup (temporary)
3. Migrate all `app.sketch` references to `get_active_sketch()`
4. Change default to Solid Mode
5. Remove old code

**Testing:**
- Existing Week 9 workflow should still work
- Existing Week 10.5 Cut should work with new system

---

## Timeline

**Week 10.6 (Current):** Modal system + multiple sketches + plane selection
**Week 10.7 (Next):** Face selection + sketch-on-face

**Total Time:** 30-36 hours (4-5 days of full-time work)

---

**Status:** Ready to begin implementation
**Next Action:** Phase 1 - Implement core modal system
