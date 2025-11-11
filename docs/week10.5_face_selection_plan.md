# Face Selection & Sketch-on-Face Feature Plan

**Issue:** Current Cut implementation reuses the original sketch instead of allowing sketching on arbitrary faces of extruded solids.

**Proper CAD Workflow:**
1. Extrude a solid
2. Select a face of the solid (e.g., top face)
3. Create a new sketch on that face
4. Draw pocket profile on the face
5. Cut into the solid from that face

---

## Current Workaround

Until face selection is implemented, you can work around this limitation:

### Method 1: Pre-plan Both Profiles
```
1. Draw outer rectangle (e.g., 2×2) on XY plane
2. Draw inner rectangle (e.g., 1×1) on XY plane (pocket profile)
3. Press [E] → Extrude outer profile (depth 1.0)
4. Select inner rectangle
5. Press [T] → Cut from XY plane (depth 0.5)
```

This works because both sketches are on the same plane (XY), so the cut projects correctly.

### Method 2: Multiple Sketches (Future)
Once we support multiple independent sketches:
```
1. Sketch001: Draw outer rectangle on XY
2. Press [E] → Extrude
3. Create Sketch002 on top face (offset Z = 1.0)
4. Draw pocket profile on Sketch002
5. Press [T] → Cut using Sketch002
```

---

## Implementation Plan

### Phase 1: Face Representation (Week 10.6)
**Goal:** Represent faces in SimpleSolid

**Tasks:**
- [ ] Add `SimpleFace` structure (list of edges forming a loop)
- [ ] Add faces array to `SimpleSolid`
- [ ] Update extrude to generate faces (top, bottom, sides)
- [ ] Face-to-plane conversion (extract face normal and origin)

**Data Structures:**
```odin
SimpleFace :: struct {
    edges: [dynamic]int,  // Indices into solid.edges array
    normal: m.Vec3,       // Face normal (computed from edges)
    center: m.Vec3,       // Face center point
}

SimpleSolid :: struct {
    vertices: [dynamic]^Vertex,
    edges: [dynamic]^Edge,
    faces: [dynamic]SimpleFace,  // NEW
}
```

**Estimated Time:** 4-6 hours

---

### Phase 2: Face Hit Testing (Week 10.6)
**Goal:** Click to select a face of a solid

**Tasks:**
- [ ] Ray-face intersection test
- [ ] Face selection state in AppState
- [ ] Visual highlighting of selected face (render with fill color)
- [ ] Keyboard shortcut [N] = "New sketch on selected face"

**Algorithm:**
```
1. Cast ray from mouse click
2. For each face in each solid:
   a. Test ray-plane intersection
   b. Check if intersection point is inside face polygon (2D test)
   c. If inside, record hit distance
3. Return closest hit face
```

**Estimated Time:** 6-8 hours

---

### Phase 3: Multiple Sketch Support (Week 10.7)
**Goal:** Support multiple independent sketches in feature tree

**Current Limitation:** Only one global sketch

**Tasks:**
- [ ] Remove global `app.sketch` field
- [ ] Each Sketch feature owns its own Sketch2D
- [ ] UI for switching active sketch (select from feature tree)
- [ ] Keyboard shortcut [1]/[2]/[3] to switch between sketches
- [ ] Visual indication of active sketch

**Changes Required:**
```odin
// BEFORE:
app.sketch: ^sketch.Sketch2D  // Global sketch

// AFTER:
app.active_sketch_id: int  // ID of active sketch feature
// Get sketch from feature tree
active_sketch := get_active_sketch(&app.feature_tree)
```

**Estimated Time:** 6-8 hours

---

### Phase 4: Sketch-on-Face Creation (Week 10.7)
**Goal:** Create new sketch on a selected face

**Tasks:**
- [ ] Extract plane from selected face
- [ ] Create new Sketch2D with face plane
- [ ] Add sketch to feature tree
- [ ] Set as active sketch
- [ ] UI workflow: Select face → Press [N] → New sketch on face

**Workflow:**
```
User Action:                    System Response:
1. Click on top face         → Highlight face in yellow
2. Press [N]                 → Create Sketch002 on face plane
                               Set Sketch002 as active
                               Show sketch plane indicator
3. Draw rectangle [L]        → Draw on face plane (not XY)
4. Press [T]                 → Cut from face into solid
```

**Estimated Time:** 4-6 hours

---

### Phase 5: UI Polish (Week 10.8)
**Goal:** Professional face selection UX

**Tasks:**
- [ ] Face hover preview (semi-transparent highlight)
- [ ] Face info tooltip (Face #1, Type: Top, Area: 4.0)
- [ ] Sketch plane visualization (subtle grid on face)
- [ ] Mode indicator (Face Select / Sketch / 3D View)
- [ ] Face selection in toolbar (button + mode)

**Estimated Time:** 4-6 hours

---

## Total Estimated Time: 24-34 hours (3-4 weeks)

---

## Technical Challenges

### Challenge 1: Face Representation
**Problem:** SimpleSolid only has vertices and edges (no face topology)

**Solution:** Add faces as ordered edge loops:
```odin
SimpleFace :: struct {
    edges: [dynamic]int,    // Indices into solid.edges
    normal: m.Vec3,         // Precomputed normal
    center: m.Vec3,         // Precomputed center
}
```

### Challenge 2: Ray-Face Intersection
**Problem:** Faces are not triangulated (arbitrary polygons)

**Solution:** Two-step test:
1. Ray-plane intersection (using face normal)
2. Point-in-polygon 2D test (project to face plane)

### Challenge 3: Multiple Active Sketches
**Problem:** Current architecture assumes one global sketch

**Solution:** Store sketch in feature tree, retrieve by active ID:
```odin
get_active_sketch :: proc(tree: ^FeatureTree, active_id: int) -> ^Sketch2D {
    feature := feature_tree_get_feature(tree, active_id)
    if feature.type != .Sketch do return nil
    params := feature.params.(SketchParams)
    return params.sketch_ref
}
```

---

## Phased Rollout Strategy

### Week 10.6: Foundation
- Implement SimpleFace structure
- Update extrude to generate faces
- Basic face hit testing
- Visual face highlighting

**Deliverable:** Can click to select faces (no sketching yet)

### Week 10.7: Sketch Integration
- Multiple sketch support in feature tree
- Sketch-on-face creation
- Face plane extraction
- Cut from arbitrary sketch plane

**Deliverable:** Full sketch-on-face workflow working

### Week 10.8: Polish
- UI improvements (hover, tooltips, mode indicators)
- Keyboard shortcuts
- Face selection toolbar button

**Deliverable:** Professional face selection UX

---

## Alternative: Simpler MVP Approach

If full face selection is too complex, implement a **sketch offset** system:

```
1. Draw outer rectangle on XY
2. Press [E] → Extrude (depth 1.0)
3. Press [O] → Offset sketch to top face (Z += extrude depth)
4. Draw pocket profile (now on top face)
5. Press [T] → Cut
```

**Pros:**
- Much simpler (2-4 hours instead of 24-34 hours)
- No face picking UI needed
- Works for common case (sketch on top face)

**Cons:**
- Can't pocket side faces
- Can't pocket arbitrary face angles
- Less flexible than full face selection

**Implementation:**
```odin
// Offset active sketch to top of last extrude
offset_sketch_to_top :: proc(app: ^AppStateGPU) {
    if app.extrude_feature_id < 0 do return

    extrude_feature := feature_tree_get_feature(&app.feature_tree, app.extrude_feature_id)
    params := extrude_feature.params.(ExtrudeParams)

    // Calculate offset (extrude depth along sketch normal)
    offset := app.sketch.plane.normal * params.depth

    // Create new sketch on offset plane
    new_plane := SketchPlane{
        origin = app.sketch.plane.origin + offset,
        normal = app.sketch.plane.normal,
        x_axis = app.sketch.plane.x_axis,
        y_axis = app.sketch.plane.y_axis,
    }

    new_sketch := sketch_init("Sketch002", new_plane)
    sketch_id := feature_tree_add_sketch(&app.feature_tree, new_sketch, "Sketch002")
    app.active_sketch_id = sketch_id
}
```

---

## Recommendation

**For now:** Document the limitation and continue with Week 11

**Reason:** Face selection is a major feature (24-34 hours) that should be its own week (10.6-10.8)

**Current Status:** Week 10.5 boolean operation is functionally complete - it correctly removes geometry and creates pockets. The limitation is the workflow (need to pre-plan both profiles on same plane).

**Next Step:** Move to Week 11 (Revolve) or implement simpler offset-sketch approach as interim solution.

---

## Testing Current Implementation

**Current Workflow (Works):**
```
1. Draw outer 3×3 rectangle
2. Draw inner 1×1 rectangle (centered)
3. Press [E] → Extrude (creates box)
4. Select inner rectangle
5. Press [T] → Cut (creates pocket in top face)
```

**Verification:**
- Edges inside pocket should be removed
- Pocket boundary (inner rectangle) should be visible
- Depth should be 50% of extrude depth
- Feature tree shows Extrude001 and Cut001

**Expected Result:** Box with square hole/pocket going halfway through

---

**Status:** Week 10.5 core feature complete, face selection deferred to 10.6-10.8
