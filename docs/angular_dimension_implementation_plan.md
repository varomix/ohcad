# Angular Dimension Implementation Plan
**Feature:** Week 12.38 - Angular Dimension Tool
**Date:** 2025-11-14
**Status:** 📋 Planning Phase

---

## 1. Feature Overview

### Goal
Implement a professional angular dimension tool that allows users to:
1. Select two lines by clicking on them
2. Position the dimension arc by clicking where they want it displayed
3. See the angle between lines with the degree symbol (°)
4. Edit the angle value by double-clicking the dimension (driving constraint)
5. Have the constraint solver maintain the specified angle

### User Workflow
```
1. Press [A] → Activate Angular tool
2. Click first line → Line highlights in yellow
3. Click second line → Both lines highlighted, preview arc appears at cursor
4. Move mouse → Arc preview follows cursor, shows which angle quadrant
5. Click position → Creates angular constraint with arc at that position
6. Result: "45°" dimension with arc between lines
7. Double-click dimension → Edit angle value (e.g., change 45° to 90°)
```

### Visual Design
```
        Line 1 (v1)
            /
           /  ) 45°    ← Arc with angle text
          /  )
         /__)
        Line 2 (v2)
```

---

## 2. Technical Architecture

### 2.1 Tool System Changes

#### Current State
- `SketchTool` enum has: Select, Line, Circle, Arc, Dimension
- Dimension tool only handles distance between points (2-click workflow)

#### Required Changes
- Add `Angular` tool to `SketchTool` enum
- Support multi-entity selection workflow:
  - Click 1: Select first line (store `first_line_id`)
  - Click 2: Select second line (store `second_line_id`)
  - Click 3: Position arc (store `offset` position)

#### Tool State Fields (add to Sketch2D)
```odin
// Add to Sketch2D struct:
first_line_id: int,      // -1 if none, line ID if selected
second_line_id: int,     // -1 if none, line ID if selected
angular_offset: m.Vec2,  // Where user wants arc positioned
```

### 2.2 Constraint System Changes

#### AngleData Struct (ALREADY UPDATED ✅)
```odin
AngleData :: struct {
    line1_id: int,    // Entity ID of first line
    line2_id: int,    // Entity ID of second line
    angle: f64,       // Angle in degrees (0-360)
    offset: m.Vec2,   // Offset position for arc placement
}
```

### 2.3 Rendering System Changes

#### New Rendering Function
**Location:** `/src/ui/viewer/viewer_gpu.odin`

**Function:** `viewer_gpu_render_angular_dimension()`
```odin
viewer_gpu_render_angular_dimension :: proc(
    viewer: ^ViewerGPU,
    cmd: ^GPUCommandBuffer,
    pass: ^GPURenderPass,
    text_renderer: ^TextRendererGPU,
    sketch: ^Sketch2D,
    constraint: ^Constraint,
    mvp: matrix[4,4]f32,
    view: matrix[4,4]f32,
    proj: matrix[4,4]f32,
) {
    // 1. Get angle data
    // 2. Get both lines and calculate vectors
    // 3. Calculate arc center (intersection point or offset from it)
    // 4. Calculate arc radius (distance from center to offset)
    // 5. Calculate start/end angles for arc
    // 6. Render arc (tessellate into line segments)
    // 7. Render angle text with ° symbol at arc midpoint
    // 8. Render extension lines if needed
}
```

#### Arc Tessellation
- Generate arc as series of line segments (12-24 segments depending on angle)
- Arc radius: distance from intersection point to offset position
- Arc sweep: determined by angle value and which quadrant user clicked

---

## 3. Step-by-Step Implementation

### Phase 1: Tool System Setup (Files: sketch.odin, tool_handlers.odin)

#### Task 1.1: Add Angular Tool Enum
**File:** `/src/features/sketch/sketch.odin`
```odin
SketchTool :: enum {
    Select,
    Line,
    Circle,
    Arc,
    Dimension,
    Angular,     // NEW: Angular dimension tool
}
```

#### Task 1.2: Add Tool State Fields
**File:** `/src/features/sketch/sketch.odin`
```odin
Sketch2D :: struct {
    // ... existing fields ...

    // Tool state (existing)
    first_point_id: int,
    second_point_id: int,
    chain_start_point_id: int,

    // NEW: Angular tool state
    first_line_id: int,      // -1 if none
    second_line_id: int,     // -1 if none
    angular_offset: m.Vec2,  // Arc position
}
```

Initialize in `sketch_init()`:
```odin
first_line_id = -1,
second_line_id = -1,
```

#### Task 1.3: Reset Tool State Helper
**File:** `/src/features/sketch/tool_handlers.odin`
```odin
sketch_reset_angular_tool :: proc(sketch: ^Sketch2D) {
    sketch.first_line_id = -1
    sketch.second_line_id = -1
    sketch.angular_offset = m.Vec2{0, 0}
}
```

### Phase 2: Click Handler (File: tool_handlers.odin)

#### Task 2.1: Angular Tool Click Handler
**File:** `/src/features/sketch/tool_handlers.odin`
```odin
handle_angular_tool_click :: proc(sketch: ^Sketch2D, click_pos: m.Vec2) {
    // State machine: 3 clicks required

    if sketch.first_line_id < 0 {
        // CLICK 1: Select first line
        clicked_line := find_line_at_position(sketch, click_pos, SELECTION_TOLERANCE)
        if clicked_line >= 0 {
            sketch.first_line_id = clicked_line
            fmt.println("✓ First line selected (click second line)")
        } else {
            fmt.println("⚠️  Click on a line")
        }
    } else if sketch.second_line_id < 0 {
        // CLICK 2: Select second line
        clicked_line := find_line_at_position(sketch, click_pos, SELECTION_TOLERANCE)
        if clicked_line >= 0 && clicked_line != sketch.first_line_id {
            sketch.second_line_id = clicked_line
            fmt.println("✓ Second line selected (position dimension arc)")
        } else if clicked_line == sketch.first_line_id {
            fmt.println("⚠️  Select a different line")
        } else {
            fmt.println("⚠️  Click on a line")
        }
    } else {
        // CLICK 3: Position arc
        sketch.angular_offset = click_pos

        // Create angular constraint
        line1 := sketch.entities[sketch.first_line_id].(SketchLine)
        line2 := sketch.entities[sketch.second_line_id].(SketchLine)

        // Calculate actual angle between lines
        angle := calculate_angle_between_lines(sketch, line1, line2)

        // Add constraint
        sketch_add_constraint(sketch, .Angle, AngleData{
            line1_id = sketch.first_line_id,
            line2_id = sketch.second_line_id,
            angle = angle,
            offset = sketch.angular_offset,
        })

        fmt.printf("✓ Angular dimension created: %.1f°\n", angle)

        // Reset tool for next dimension
        sketch_reset_angular_tool(sketch)
    }
}
```

#### Task 2.2: Helper Functions
```odin
// Find line entity at position (within tolerance)
find_line_at_position :: proc(sketch: ^Sketch2D, pos: m.Vec2, tolerance: f64) -> int {
    for entity, i in sketch.entities {
        if line, ok := entity.(SketchLine); ok {
            p1 := sketch_get_point(sketch, line.start_id)
            p2 := sketch_get_point(sketch, line.end_id)
            if p1 == nil || p2 == nil do continue

            // Point-to-line distance check
            dist := point_to_line_distance(pos, m.Vec2{p1.x, p1.y}, m.Vec2{p2.x, p2.y})
            if dist < tolerance {
                return i
            }
        }
    }
    return -1
}

// Calculate angle between two lines (in degrees)
calculate_angle_between_lines :: proc(sketch: ^Sketch2D, line1: SketchLine, line2: SketchLine) -> f64 {
    p1_start := sketch_get_point(sketch, line1.start_id)
    p1_end := sketch_get_point(sketch, line1.end_id)
    p2_start := sketch_get_point(sketch, line2.start_id)
    p2_end := sketch_get_point(sketch, line2.end_id)

    if p1_start == nil || p1_end == nil || p2_start == nil || p2_end == nil {
        return 0
    }

    // Direction vectors
    v1 := m.Vec2{p1_end.x - p1_start.x, p1_end.y - p1_start.y}
    v2 := m.Vec2{p2_end.x - p2_start.x, p2_end.y - p2_start.y}

    // Normalize
    v1 = glsl.normalize(v1)
    v2 = glsl.normalize(v2)

    // Calculate angle using atan2 for full 360° range
    dot := v1.x * v2.x + v1.y * v2.y
    cross := v1.x * v2.y - v1.y * v2.x
    angle_rad := math.atan2(cross, dot)

    // Convert to degrees (0-360 range)
    angle_deg := angle_rad * 180.0 / math.PI
    if angle_deg < 0 {
        angle_deg += 360.0
    }

    return angle_deg
}
```

### Phase 3: Preview Rendering (File: viewer_gpu.odin)

#### Task 3.1: Preview Arc During Positioning
**File:** `/src/ui/viewer/viewer_gpu.odin` (in `viewer_gpu_render_sketch_preview`)
```odin
// Add to viewer_gpu_render_sketch_preview():

// ANGULAR TOOL: Preview arc after selecting 2 lines
if sk.current_tool == .Angular &&
   sk.first_line_id >= 0 &&
   sk.second_line_id >= 0 &&
   sk.temp_point_valid {

    // Get both lines
    line1 := sk.entities[sk.first_line_id].(SketchLine)
    line2 := sk.entities[sk.second_line_id].(SketchLine)

    // Calculate angle
    angle := calculate_angle_between_lines(sk, line1, line2)

    // Calculate intersection point (or nearest point between lines)
    center := calculate_line_intersection(sk, line1, line2)

    // Arc radius from center to cursor
    radius := glsl.length(sk.temp_point - center)

    // Render preview arc
    render_arc_preview(viewer, cmd, pass, sk, center, radius, angle, mvp)

    // Render preview text
    text := fmt.tprintf("%.1f°", angle)
    // ... render at cursor position
}
```

### Phase 4: Final Dimension Rendering (File: viewer_gpu.odin)

#### Task 4.1: Angular Dimension Renderer
**File:** `/src/ui/viewer/viewer_gpu.odin`
```odin
viewer_gpu_render_angular_dimension :: proc(
    viewer: ^ViewerGPU,
    cmd: ^sdl.GPUCommandBuffer,
    pass: ^sdl.GPURenderPass,
    text_renderer: ^TextRendererGPU,
    sketch: ^Sketch2D,
    constraint: ^Constraint,
    mvp: matrix[4,4]f32,
    view: matrix[4,4]f32,
    proj: matrix[4,4]f32,
) {
    data, ok := constraint.data.(AngleData)
    if !ok do return

    // Get both lines
    if data.line1_id < 0 || data.line1_id >= len(sketch.entities) do return
    if data.line2_id < 0 || data.line2_id >= len(sketch.entities) do return

    line1 := sketch.entities[data.line1_id].(SketchLine)
    line2 := sketch.entities[data.line2_id].(SketchLine)

    // Get line endpoints
    p1_start := sketch_get_point(sketch, line1.start_id)
    p1_end := sketch_get_point(sketch, line1.end_id)
    p2_start := sketch_get_point(sketch, line2.start_id)
    p2_end := sketch_get_point(sketch, line2.end_id)

    if p1_start == nil || p1_end == nil || p2_start == nil || p2_end == nil do return

    // Calculate intersection point (or use offset as center)
    center := calculate_line_intersection_2d(
        m.Vec2{p1_start.x, p1_start.y}, m.Vec2{p1_end.x, p1_end.y},
        m.Vec2{p2_start.x, p2_start.y}, m.Vec2{p2_end.x, p2_end.y},
    )

    // Arc radius: distance from center to offset
    radius := glsl.length(data.offset - center)
    if radius < 0.1 {
        radius = 0.5  // Default radius if offset too close to intersection
    }

    // Calculate arc angles
    v1 := m.Vec2{p1_end.x - p1_start.x, p1_end.y - p1_start.y}
    v2 := m.Vec2{p2_end.x - p2_start.x, p2_end.y - p2_start.y}

    angle1 := math.atan2(v1.y, v1.x)
    angle2 := math.atan2(v2.y, v2.x)

    // Determine which arc to draw based on offset position
    // (Choose the arc that includes the offset point)
    start_angle, sweep_angle := determine_arc_sweep(angle1, angle2, data.angle, center, data.offset)

    // Tessellate arc into line segments
    arc_segments := tessellate_arc(center, radius, start_angle, sweep_angle, 24)

    // Render arc line
    render_line_segments(viewer, cmd, pass, sketch, arc_segments, mvp, {1, 1, 0, 1}, 2.0)

    // Render angle text with degree symbol
    text := fmt.tprintf("%.1f°", data.angle)

    // Position text at arc midpoint
    mid_angle := start_angle + sweep_angle * 0.5
    text_pos_2d := center + m.Vec2{
        radius * math.cos(mid_angle),
        radius * math.sin(mid_angle),
    }
    text_pos_3d := sketch_to_world(&sketch.plane, text_pos_2d)

    // Project to screen and render
    render_text_at_3d_position(text_renderer, cmd, pass, text, text_pos_3d, view, proj, ...)
}
```

#### Task 4.2: Arc Tessellation Helper
```odin
tessellate_arc :: proc(center: m.Vec2, radius: f64, start_angle: f64, sweep_angle: f64, segments: int) -> []m.Vec2 {
    points := make([dynamic]m.Vec2, 0, segments + 1)

    for i in 0..=segments {
        t := f64(i) / f64(segments)
        angle := start_angle + sweep_angle * t

        point := center + m.Vec2{
            radius * math.cos(angle),
            radius * math.sin(angle),
        }
        append(&points, point)
    }

    return points[:]
}
```

### Phase 5: Keyboard Shortcut (File: main_gpu.odin)

#### Task 5.1: Add [A] Key Handler
**File:** `/src/main_gpu.odin` in `handle_sketch_mode_keys()`
```odin
case sdl.K_A:
    sketch.sketch_set_tool(active_sketch, .Angular)
    fmt.println("🔧 Tool: Angular Dimension")
```

### Phase 6: Constraint Solver Integration (File: constraints.odin)

#### Task 6.1: Update Angle Constraint Residuals
**File:** `/src/features/sketch/constraints.odin`

The `residuals_angle()` function already exists and handles angle constraints. We need to verify it uses degrees correctly:

```odin
// VERIFY: This function should convert stored degrees to radians for solver
residuals_angle :: proc(sketch: ^Sketch2D, data: AngleData, residuals: ^[dynamic]f64) {
    // ... existing code ...

    // Convert stored angle from degrees to radians for comparison
    target_angle_rad := data.angle * math.PI / 180.0

    append(residuals, current_angle - target_angle_rad)
}
```

---

## 4. File Modifications Summary

### Files to Modify
1. **`/src/features/sketch/sketch.odin`**
   - Add `Angular` to `SketchTool` enum
   - Add `first_line_id`, `second_line_id`, `angular_offset` to `Sketch2D`
   - Initialize new fields in `sketch_init()`

2. **`/src/features/sketch/tool_handlers.odin`**
   - Add `handle_angular_tool_click()`
   - Add helper functions: `find_line_at_position()`, `calculate_angle_between_lines()`
   - Update `sketch_handle_click()` to route Angular tool clicks

3. **`/src/features/sketch/constraints.odin`**
   - ✅ Already updated `AngleData` struct with offset field
   - Verify `residuals_angle()` handles degrees correctly
   - Update `sketch_modify_constraint_value()` angle case (already done)

4. **`/src/ui/viewer/viewer_gpu.odin`**
   - Add `viewer_gpu_render_angular_dimension()`
   - Update `viewer_gpu_render_sketch_constraints()` to call angular renderer
   - Add arc tessellation helpers
   - Update `viewer_gpu_render_sketch_preview()` for angular preview

5. **`/src/main_gpu.odin`**
   - Add [A] keyboard shortcut in `handle_sketch_mode_keys()`
   - Update toolbar UI to show Angular tool icon

6. **`/src/ui/widgets/cad_ui.odin`**
   - Add "AN" tool icon with orange accent in toolbar
   - Update tool display when Angular is active

---

## 5. Testing Strategy

### Test Cases

#### TC1: Basic Angular Dimension
1. Create two perpendicular lines (L shape)
2. Press [A]
3. Click first line → Should highlight yellow
4. Click second line → Both lines highlighted, preview arc at cursor
5. Click to position → Should show "90°"

#### TC2: Various Angles
- Test 45° angle
- Test 30° angle
- Test 135° angle (obtuse)
- Test 180° angle (straight line)

#### TC3: Arc Positioning
- Position arc on different quadrants
- Verify correct arc is drawn (acute vs obtuse angle)
- Test with small radius (near intersection)
- Test with large radius (far from intersection)

#### TC4: Double-Click Editing
1. Create angular dimension
2. Double-click the dimension text
3. Change angle from 45° to 60°
4. Press Enter → Lines should rotate to maintain 60°

#### TC5: Constraint Solver
1. Create two lines at 45°
2. Add angular constraint
3. Drag one line's endpoint
4. Verify angle is maintained at 45° during drag

#### TC6: Edge Cases
- Test with nearly parallel lines (0° or 180°)
- Test with coincident lines (0°)
- Test with very short lines
- Test angle > 180° (reflex angles)

---

## 6. Edge Cases & Considerations

### Geometric Edge Cases
1. **Non-intersecting lines**
   - Find closest points between lines
   - Draw arc at offset from midpoint

2. **Parallel lines**
   - Show 0° or 180° depending on direction
   - Draw arc at offset location

3. **Coincident lines**
   - Show error message: "Lines are coincident"
   - Don't create constraint

4. **Very short lines**
   - Still calculate angle from direction vectors
   - May have precision issues with zero-length lines

### UI/UX Considerations
1. **Arc direction (CW vs CCW)**
   - Determine from offset position
   - Always draw the smaller arc unless offset indicates otherwise
   - Mouse position determines which of 4 possible angles to measure

2. **Text placement**
   - Position at arc midpoint
   - Offset slightly outward from arc
   - Avoid overlapping with lines

3. **Selection tolerance**
   - Use existing hover system for line selection
   - Highlight hovered line before click

4. **Tool cancellation**
   - ESC cancels current angular dimension operation
   - Returns to Select tool
   - Clears first_line_id and second_line_id

### Performance Considerations
1. **Arc tessellation**
   - 24 segments provides smooth arc for most angles
   - Scale segment count with arc length (smaller arcs = fewer segments)

2. **Preview rendering**
   - Only render preview when tool is active
   - Efficient line rendering (batch render arc segments)

---

## 7. Implementation Order

### Recommended Sequence
1. **Phase 1: Tool System Setup** (30 min)
   - Safest changes, foundation for everything else

2. **Phase 5: Keyboard Shortcut** (5 min)
   - Quick win, enables testing tool activation

3. **Phase 2: Click Handler** (45 min)
   - Core logic, no rendering yet
   - Can test with console output

4. **Phase 3: Preview Rendering** (30 min)
   - Visual feedback during workflow
   - Shows arc as user positions it

5. **Phase 4: Final Dimension Rendering** (60 min)
   - Most complex part
   - Arc tessellation and text rendering

6. **Phase 6: Constraint Solver** (15 min)
   - Verify existing solver works
   - Minor tweaks if needed

**Total Estimated Time: 3 hours**

---

## 8. Success Criteria

### Feature is complete when:
- ✅ [A] key activates Angular tool
- ✅ 3-click workflow functions correctly (line, line, position)
- ✅ Arc renders with correct geometry
- ✅ Angle text displays with ° symbol
- ✅ Double-click editing changes angle value
- ✅ Constraint solver maintains specified angle
- ✅ Works with various angles (0-360°)
- ✅ Preview arc follows cursor during positioning
- ✅ Toolbar shows Angular tool with icon

---

## 9. Future Enhancements (Post-MVP)

### Nice-to-Have Features
1. **Smart angle selection**
   - Automatically choose acute vs obtuse based on context
   - Keyboard modifier (Shift) to toggle angle quadrant

2. **Reference angle dimensions**
   - Non-driving dimensions (display only, don't constrain)
   - Useful for verifying calculated angles

3. **Angle dimension styles**
   - Different arc styles (single line, double line, filled sector)
   - Customizable arrowhead styles

4. **Multiple arc radii**
   - Draw multiple arcs for same angle (different radii)
   - Useful for complex technical drawings

---

## 10. Risks & Mitigation

### Risk 1: Angle Ambiguity
**Problem:** Two lines can form 4 different angles (depending on direction and quadrant)
**Mitigation:** Use offset position to determine which angle user wants to measure

### Risk 2: Text Rendering Performance
**Problem:** Degree symbol (°) might not render correctly
**Mitigation:** Test early with existing text system, verify Unicode support

### Risk 3: Arc Tessellation Complexity
**Problem:** Generating smooth arcs with correct geometry
**Mitigation:** Start with simple tessellation (24 segments), refine later

### Risk 4: Constraint Solver Convergence
**Problem:** Angle constraints might cause solver to diverge
**Mitigation:** Use existing perpendicular constraint as reference (works with 90°)

---

## 11. Code Review Checklist

Before merging, verify:
- [ ] All tool state properly reset when changing tools
- [ ] ESC key cancels angular dimension workflow
- [ ] Preview renders correctly during positioning
- [ ] Degree symbol (°) displays correctly
- [ ] Arc geometry is mathematically correct
- [ ] Double-click editing works
- [ ] Constraint solver maintains angle
- [ ] No memory leaks in arc tessellation
- [ ] Keyboard shortcut doesn't conflict with others
- [ ] Toolbar UI updated with Angular tool icon

---

## 12. Documentation Requirements

### User-Facing
- Update keyboard shortcuts help text ([A] = Angular Dimension)
- Add to status bar: "Angular: Click 2 lines, then position arc"
- Tool tip: "Measure angle between two lines (0-360°)"

### Developer-Facing
- Document `AngleData` struct in constraints.odin
- Document `calculate_angle_between_lines()` helper
- Document arc tessellation algorithm

---

## Appendix A: Math Reference

### Angle Calculation
```
Given two lines with direction vectors v1 and v2:
1. Normalize both vectors: v1' = v1 / |v1|, v2' = v2 / |v2|
2. Calculate dot product: dot = v1' · v2'
3. Calculate cross product (2D): cross = v1'.x * v2'.y - v1'.y * v2'.x
4. Angle in radians: θ = atan2(cross, dot)
5. Convert to degrees: angle = θ * 180 / π
6. Normalize to 0-360°: if angle < 0, angle += 360
```

### Arc Geometry
```
Arc definition:
- Center: C (intersection point or offset)
- Radius: r = |offset - C|
- Start angle: θ1 (angle of line 1)
- Sweep angle: θ_sweep (measured angle)
- End angle: θ2 = θ1 + θ_sweep

Tessellation:
For i from 0 to n_segments:
    t = i / n_segments
    θ = θ1 + θ_sweep * t
    point = C + r * (cos(θ), sin(θ))
```

---

## Appendix B: ASCII Art Examples

### Example 1: 45° Angle
```
        ^
        |
        |  45°
       /|
      / |
     /  |
    /   |
   /_)__|_____________>
```

### Example 2: 90° Angle (Perpendicular)
```
        ^
        |
        |
        |  90°
        |_)_____________>
```

### Example 3: 135° Angle (Obtuse)
```
    \
     \
      \ 135°
       \___/
            \___________>
```

---

**END OF IMPLEMENTATION PLAN**

*Ready for review and approval before implementation begins.*
