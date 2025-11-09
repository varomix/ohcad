// ui/viewer - Sketch rendering utilities
package ohcad_viewer

import "core:fmt"
import "core:math"
import sketch "../../features/sketch"
import m "../../core/math"
import glsl "core:math/linalg/glsl"

// Convert sketch to wireframe mesh for rendering (EXCLUDING selected entity)
sketch_to_wireframe :: proc(sk: ^sketch.Sketch2D) -> WireframeMesh {
    mesh := wireframe_mesh_init()

    // Render all entities EXCEPT the selected one
    for entity, idx in sk.entities {
        // Skip selected entity - it will be rendered separately in green
        if idx == sk.selected_entity {
            continue
        }

        switch e in entity {
        case sketch.SketchLine:
            // Get start and end points
            start := sketch.sketch_get_point(sk, e.start_id)
            end := sketch.sketch_get_point(sk, e.end_id)

            if start != nil && end != nil {
                // Convert 2D sketch coordinates to 3D world coordinates
                start_2d := m.Vec2{start.x, start.y}
                end_2d := m.Vec2{end.x, end.y}

                start_3d := sketch.sketch_to_world(&sk.plane, start_2d)
                end_3d := sketch.sketch_to_world(&sk.plane, end_2d)

                wireframe_mesh_add_edge(&mesh, start_3d, end_3d)
            }

        case sketch.SketchCircle:
            // Tessellate circle into line segments
            center_pt := sketch.sketch_get_point(sk, e.center_id)
            if center_pt != nil {
                center_2d := m.Vec2{center_pt.x, center_pt.y}
                center_3d := sketch.sketch_to_world(&sk.plane, center_2d)

                // Draw circle with 64 segments (smoother for thick lines)
                segments := 64
                for i in 0..<segments {
                    angle0 := f64(i) * (2.0 * 3.14159265359) / f64(segments)
                    angle1 := f64((i + 1) % segments) * (2.0 * 3.14159265359) / f64(segments)

                    p0_2d := m.Vec2{
                        center_pt.x + e.radius * math.cos(angle0),
                        center_pt.y + e.radius * math.sin(angle0),
                    }
                    p1_2d := m.Vec2{
                        center_pt.x + e.radius * math.cos(angle1),
                        center_pt.y + e.radius * math.sin(angle1),
                    }

                    p0_3d := sketch.sketch_to_world(&sk.plane, p0_2d)
                    p1_3d := sketch.sketch_to_world(&sk.plane, p1_2d)

                    wireframe_mesh_add_edge(&mesh, p0_3d, p1_3d)
                }
            }

        case sketch.SketchArc:
            // TODO: Implement arc rendering
            fmt.println("Arc rendering not yet implemented")
        }
    }

    return mesh
}

// Convert ONLY selected entity to wireframe (for highlighting)
sketch_to_wireframe_selected :: proc(sk: ^sketch.Sketch2D) -> WireframeMesh {
    mesh := wireframe_mesh_init()

    if sk.selected_entity < 0 || sk.selected_entity >= len(sk.entities) {
        return mesh // No selection
    }

    entity := sk.entities[sk.selected_entity]

    switch e in entity {
    case sketch.SketchLine:
        start := sketch.sketch_get_point(sk, e.start_id)
        end := sketch.sketch_get_point(sk, e.end_id)

        if start != nil && end != nil {
            start_2d := m.Vec2{start.x, start.y}
            end_2d := m.Vec2{end.x, end.y}

            start_3d := sketch.sketch_to_world(&sk.plane, start_2d)
            end_3d := sketch.sketch_to_world(&sk.plane, end_2d)

            wireframe_mesh_add_edge(&mesh, start_3d, end_3d)
        }

    case sketch.SketchCircle:
        center_pt := sketch.sketch_get_point(sk, e.center_id)
        if center_pt != nil {
            segments := 64  // Smoother circles
            for i in 0..<segments {
                angle0 := f64(i) * (2.0 * 3.14159265359) / f64(segments)
                angle1 := f64((i + 1) % segments) * (2.0 * 3.14159265359) / f64(segments)

                p0_2d := m.Vec2{
                    center_pt.x + e.radius * math.cos(angle0),
                    center_pt.y + e.radius * math.sin(angle0),
                }
                p1_2d := m.Vec2{
                    center_pt.x + e.radius * math.cos(angle1),
                    center_pt.y + e.radius * math.sin(angle1),
                }

                p0_3d := sketch.sketch_to_world(&sk.plane, p0_2d)
                p1_3d := sketch.sketch_to_world(&sk.plane, p1_2d)

                wireframe_mesh_add_edge(&mesh, p0_3d, p1_3d)
            }
        }

    case sketch.SketchArc:
        // TODO: Arc rendering
    }

    return mesh
}

// Render sketch points (vertices) as actual filled circular dots with screen-space constant size
render_sketch_points :: proc(shader: ^LineShader, sk: ^sketch.Sketch2D, mvp: glsl.mat4, color: [4]f32, point_size_pixels: f32, viewport_height: f32, fov: f32, camera_distance: f32) {
    // Calculate screen-space to world-space conversion
    // Formula: pixel_size_world = (2 * distance * tan(fov/2)) / viewport_height
    pixel_size_world := f64((2.0 * camera_distance * glsl.tan(fov * 0.5)) / viewport_height)

    // Calculate radius in world units for the desired pixel size
    radius := pixel_size_world * f64(point_size_pixels)

    // Render each point as a filled circle using triangle fan
    for point in sk.points {
        pt_2d := m.Vec2{point.x, point.y}
        center_3d := sketch.sketch_to_world(&sk.plane, pt_2d)

        segments := 16  // Number of segments for smooth circle

        // Create triangle fan vertices for filled circle
        circle_verts := make([dynamic]m.Vec3, 0, segments + 2)
        defer delete(circle_verts)

        // Center vertex
        append(&circle_verts, center_3d)

        // Perimeter vertices
        for i in 0..=segments {
            angle := f64(i) * (2.0 * 3.14159265359) / f64(segments)

            edge_2d := m.Vec2{
                point.x + radius * math.cos(angle),
                point.y + radius * math.sin(angle),
            }
            edge_3d := sketch.sketch_to_world(&sk.plane, edge_2d)
            append(&circle_verts, edge_3d)
        }

        // Draw filled circle as triangle fan
        line_shader_draw_filled_circle(shader, circle_verts[:], color, mvp)
    }
}

// Render sketch plane indicator (outline rectangle)
render_sketch_plane :: proc(shader: ^LineShader, sk: ^sketch.Sketch2D, mvp: glsl.mat4, size: f32 = 5.0) {
    // Draw rectangle on sketch plane
    half := f64(size) * 0.5

    corners := []m.Vec2{
        {-half, -half},
        { half, -half},
        { half,  half},
        {-half,  half},
    }

    // Convert corners to 3D and create edges
    edges := make([dynamic]m.Vec3, 0, 8)
    defer delete(edges)

    for i in 0..<4 {
        c0 := sketch.sketch_to_world(&sk.plane, corners[i])
        c1 := sketch.sketch_to_world(&sk.plane, corners[(i + 1) % 4])
        append(&edges, c0)
        append(&edges, c1)
    }

    // Draw in subtle cyan
    line_shader_draw(shader, edges[:], {0.0, 0.2, 0.3, 0.3}, mvp)
}

// Render preview geometry (temporary line being drawn)
render_sketch_preview :: proc(shader: ^LineShader, sk: ^sketch.Sketch2D, mvp: glsl.mat4, camera_pos: m.Vec3) {
    if !sk.temp_point_valid {
        return
    }

    // Draw temporary cursor point
    cursor_3d := sketch.sketch_to_world(&sk.plane, sk.temp_point)
    size := 0.05

    // Draw cursor cross in bright cyan
    h_line := []m.Vec3{
        cursor_3d - m.Vec3{size, 0, 0},
        cursor_3d + m.Vec3{size, 0, 0},
    }
    line_shader_draw(shader, h_line, {0, 1, 1, 1}, mvp, 2.0)

    v_line := []m.Vec3{
        cursor_3d - m.Vec3{0, size, 0},
        cursor_3d + m.Vec3{0, size, 0},
    }
    line_shader_draw(shader, v_line, {0, 1, 1, 1}, mvp, 2.0)

    // If line tool has first point, draw preview line
    if sk.current_tool == .Line && sk.first_point_id != -1 {
        first_pt := sketch.sketch_get_point(sk, sk.first_point_id)
        if first_pt != nil {
            start_2d := m.Vec2{first_pt.x, first_pt.y}
            start_3d := sketch.sketch_to_world(&sk.plane, start_2d)

            preview_verts := []m.Vec3{start_3d, cursor_3d}
            line_shader_draw(shader, preview_verts, {0, 1, 1, 0.7}, mvp, 2.0)
        }
    }

    // If circle tool has center point, draw preview circle
    if sk.current_tool == .Circle && sk.first_point_id != -1 {
        center_pt := sketch.sketch_get_point(sk, sk.first_point_id)
        if center_pt != nil {
            center_2d := m.Vec2{center_pt.x, center_pt.y}
            center_3d := sketch.sketch_to_world(&sk.plane, center_2d)

            // Calculate preview radius
            radius := glsl.length(sk.temp_point - center_2d)

            // Draw preview circle with 32 segments
            segments := 32
            circle_verts := make([dynamic]m.Vec3, 0, segments * 2)
            defer delete(circle_verts)

            for i in 0..<segments {
                angle0 := f64(i) * (2.0 * 3.14159265359) / f64(segments)
                angle1 := f64((i + 1) % segments) * (2.0 * 3.14159265359) / f64(segments)

                p0_2d := m.Vec2{
                    center_pt.x + radius * math.cos(angle0),
                    center_pt.y + radius * math.sin(angle0),
                }
                p1_2d := m.Vec2{
                    center_pt.x + radius * math.cos(angle1),
                    center_pt.y + radius * math.sin(angle1),
                }

                p0_3d := sketch.sketch_to_world(&sk.plane, p0_2d)
                p1_3d := sketch.sketch_to_world(&sk.plane, p1_2d)

                append(&circle_verts, p0_3d)
                append(&circle_verts, p1_3d)
            }

            // Draw preview circle in bright cyan
            line_shader_draw(shader, circle_verts[:], {0, 1, 1, 0.7}, mvp, 2.0)

            // Draw radius line from center to cursor
            radius_line := []m.Vec3{center_3d, cursor_3d}
            line_shader_draw(shader, radius_line, {0, 1, 1, 0.5}, mvp, 1.0)
        }
    }
}

// Render constraint icons/indicators
render_sketch_constraints :: proc(shader: ^LineShader, sk: ^sketch.Sketch2D, mvp: glsl.mat4) {
    if sk == nil do return
    if sk.constraints == nil do return
    if len(sk.constraints) == 0 do return

    icon_size := 0.15  // Size of constraint icons in world units

    for constraint in sk.constraints {
        if !constraint.enabled do continue

        switch data in constraint.data {
        case sketch.HorizontalData:
            render_horizontal_icon(shader, sk, data, mvp, icon_size)

        case sketch.VerticalData:
            render_vertical_icon(shader, sk, data, mvp, icon_size)

        case sketch.PerpendicularData:
            render_perpendicular_icon(shader, sk, data, mvp, icon_size)

        case sketch.ParallelData:
            render_parallel_icon(shader, sk, data, mvp, icon_size)

        case sketch.DistanceData:
            render_distance_dimension(shader, sk, data, mvp)

        case sketch.DistanceXData:
            render_distance_x_dimension(shader, sk, data, mvp)

        case sketch.DistanceYData:
            render_distance_y_dimension(shader, sk, data, mvp)

        case sketch.CoincidentData:
            render_coincident_icon(shader, sk, data, mvp, icon_size)

        case sketch.EqualData:
            render_equal_icon(shader, sk, data, mvp, icon_size)

        case sketch.AngleData, sketch.TangentData, sketch.PointOnLineData, sketch.PointOnCircleData, sketch.FixedPointData:
            // These constraint types don't have visual indicators yet
            // Will be added in future iterations
        }
    }
}

// Helper: Render horizontal constraint icon (H symbol)
render_horizontal_icon :: proc(shader: ^LineShader, sk: ^sketch.Sketch2D, data: sketch.HorizontalData, mvp: glsl.mat4, size: f64) {
    if data.line_id < 0 || data.line_id >= len(sk.entities) do return

    entity := sk.entities[data.line_id]
    line, ok := entity.(sketch.SketchLine)
    if !ok do return

    // Get line midpoint
    p1 := sketch.sketch_get_point(sk, line.start_id)
    p2 := sketch.sketch_get_point(sk, line.end_id)
    if p1 == nil || p2 == nil do return

    mid_2d := m.Vec2{(p1.x + p2.x) * 0.5, (p1.y + p2.y) * 0.5}
    mid_3d := sketch.sketch_to_world(&sk.plane, mid_2d)

    // Offset upward slightly
    offset_2d := m.Vec2{mid_2d.x, mid_2d.y + size * 1.5}
    offset_3d := sketch.sketch_to_world(&sk.plane, offset_2d)

    // Draw 'H' shape
    h_verts := make([dynamic]m.Vec3, 0, 8)
    defer delete(h_verts)

    // Left vertical line
    left_2d := m.Vec2{offset_2d.x - size * 0.4, offset_2d.y}
    append(&h_verts, sketch.sketch_to_world(&sk.plane, m.Vec2{left_2d.x, left_2d.y - size * 0.4}))
    append(&h_verts, sketch.sketch_to_world(&sk.plane, m.Vec2{left_2d.x, left_2d.y + size * 0.4}))

    // Right vertical line
    right_2d := m.Vec2{offset_2d.x + size * 0.4, offset_2d.y}
    append(&h_verts, sketch.sketch_to_world(&sk.plane, m.Vec2{right_2d.x, right_2d.y - size * 0.4}))
    append(&h_verts, sketch.sketch_to_world(&sk.plane, m.Vec2{right_2d.x, right_2d.y + size * 0.4}))

    // Horizontal crossbar
    append(&h_verts, sketch.sketch_to_world(&sk.plane, m.Vec2{left_2d.x, offset_2d.y}))
    append(&h_verts, sketch.sketch_to_world(&sk.plane, m.Vec2{right_2d.x, offset_2d.y}))

    // Draw in orange/amber
    line_shader_draw(shader, h_verts[:], {1.0, 0.7, 0.0, 1.0}, mvp, 2.0)
}

// Helper: Render vertical constraint icon (V symbol)
render_vertical_icon :: proc(shader: ^LineShader, sk: ^sketch.Sketch2D, data: sketch.VerticalData, mvp: glsl.mat4, size: f64) {
    if data.line_id < 0 || data.line_id >= len(sk.entities) do return

    entity := sk.entities[data.line_id]
    line, ok := entity.(sketch.SketchLine)
    if !ok do return

    // Get line midpoint
    p1 := sketch.sketch_get_point(sk, line.start_id)
    p2 := sketch.sketch_get_point(sk, line.end_id)
    if p1 == nil || p2 == nil do return

    mid_2d := m.Vec2{(p1.x + p2.x) * 0.5, (p1.y + p2.y) * 0.5}

    // Offset to the side
    offset_2d := m.Vec2{mid_2d.x + size * 1.5, mid_2d.y}

    // Draw 'V' shape
    v_verts := make([dynamic]m.Vec3, 0, 4)
    defer delete(v_verts)

    // Left diagonal
    append(&v_verts, sketch.sketch_to_world(&sk.plane, m.Vec2{offset_2d.x - size * 0.3, offset_2d.y + size * 0.4}))
    append(&v_verts, sketch.sketch_to_world(&sk.plane, m.Vec2{offset_2d.x, offset_2d.y - size * 0.4}))

    // Right diagonal
    append(&v_verts, sketch.sketch_to_world(&sk.plane, m.Vec2{offset_2d.x, offset_2d.y - size * 0.4}))
    append(&v_verts, sketch.sketch_to_world(&sk.plane, m.Vec2{offset_2d.x + size * 0.3, offset_2d.y + size * 0.4}))

    // Draw in orange/amber
    line_shader_draw(shader, v_verts[:], {1.0, 0.7, 0.0, 1.0}, mvp, 2.0)
}

// Helper: Render perpendicular icon (⊥ symbol)
render_perpendicular_icon :: proc(shader: ^LineShader, sk: ^sketch.Sketch2D, data: sketch.PerpendicularData, mvp: glsl.mat4, size: f64) {
    if data.line1_id < 0 || data.line1_id >= len(sk.entities) do return
    if data.line2_id < 0 || data.line2_id >= len(sk.entities) do return

    entity1 := sk.entities[data.line1_id]
    entity2 := sk.entities[data.line2_id]

    line1, ok1 := entity1.(sketch.SketchLine)
    line2, ok2 := entity2.(sketch.SketchLine)
    if !ok1 || !ok2 do return

    // Find intersection or closest point between lines
    p1_start := sketch.sketch_get_point(sk, line1.start_id)
    p1_end := sketch.sketch_get_point(sk, line1.end_id)
    p2_start := sketch.sketch_get_point(sk, line2.start_id)
    p2_end := sketch.sketch_get_point(sk, line2.end_id)

    if p1_start == nil || p1_end == nil || p2_start == nil || p2_end == nil do return

    // Use midpoint of first line as icon location
    mid_2d := m.Vec2{(p1_start.x + p1_end.x) * 0.5, (p1_start.y + p1_end.y) * 0.5}

    // Draw perpendicular symbol (right angle marker)
    perp_verts := make([dynamic]m.Vec3, 0, 6)
    defer delete(perp_verts)

    half := size * 0.3

    // Three lines forming right angle
    append(&perp_verts, sketch.sketch_to_world(&sk.plane, m.Vec2{mid_2d.x - half, mid_2d.y}))
    append(&perp_verts, sketch.sketch_to_world(&sk.plane, m.Vec2{mid_2d.x, mid_2d.y}))

    append(&perp_verts, sketch.sketch_to_world(&sk.plane, m.Vec2{mid_2d.x, mid_2d.y}))
    append(&perp_verts, sketch.sketch_to_world(&sk.plane, m.Vec2{mid_2d.x, mid_2d.y + half}))

    append(&perp_verts, sketch.sketch_to_world(&sk.plane, m.Vec2{mid_2d.x - half * 0.5, mid_2d.y + half * 0.5}))
    append(&perp_verts, sketch.sketch_to_world(&sk.plane, m.Vec2{mid_2d.x, mid_2d.y}))

    // Draw in orange/amber
    line_shader_draw(shader, perp_verts[:], {1.0, 0.7, 0.0, 1.0}, mvp, 2.0)
}

// Helper: Render parallel icon (|| symbol)
render_parallel_icon :: proc(shader: ^LineShader, sk: ^sketch.Sketch2D, data: sketch.ParallelData, mvp: glsl.mat4, size: f64) {
    if data.line1_id < 0 || data.line1_id >= len(sk.entities) do return
    if data.line2_id < 0 || data.line2_id >= len(sk.entities) do return

    entity1 := sk.entities[data.line1_id]
    line1, ok1 := entity1.(sketch.SketchLine)
    if !ok1 do return

    // Get line midpoint
    p1 := sketch.sketch_get_point(sk, line1.start_id)
    p2 := sketch.sketch_get_point(sk, line1.end_id)
    if p1 == nil || p2 == nil do return

    mid_2d := m.Vec2{(p1.x + p2.x) * 0.5, (p1.y + p2.y) * 0.5}

    // Draw parallel symbol (two vertical lines)
    par_verts := make([dynamic]m.Vec3, 0, 4)
    defer delete(par_verts)

    offset := size * 0.2
    height := size * 0.6

    // Left line
    append(&par_verts, sketch.sketch_to_world(&sk.plane, m.Vec2{mid_2d.x - offset, mid_2d.y - height * 0.5}))
    append(&par_verts, sketch.sketch_to_world(&sk.plane, m.Vec2{mid_2d.x - offset, mid_2d.y + height * 0.5}))

    // Right line
    append(&par_verts, sketch.sketch_to_world(&sk.plane, m.Vec2{mid_2d.x + offset, mid_2d.y - height * 0.5}))
    append(&par_verts, sketch.sketch_to_world(&sk.plane, m.Vec2{mid_2d.x + offset, mid_2d.y + height * 0.5}))

    // Draw in orange/amber
    line_shader_draw(shader, par_verts[:], {1.0, 0.7, 0.0, 1.0}, mvp, 2.0)
}

// Helper: Render coincident icon (small cross at point)
render_coincident_icon :: proc(shader: ^LineShader, sk: ^sketch.Sketch2D, data: sketch.CoincidentData, mvp: glsl.mat4, size: f64) {
    p1 := sketch.sketch_get_point(sk, data.point1_id)
    if p1 == nil do return

    pos_2d := m.Vec2{p1.x, p1.y}

    // Draw small X marker
    x_verts := make([dynamic]m.Vec3, 0, 4)
    defer delete(x_verts)

    half := size * 0.3

    // Diagonal lines
    append(&x_verts, sketch.sketch_to_world(&sk.plane, m.Vec2{pos_2d.x - half, pos_2d.y - half}))
    append(&x_verts, sketch.sketch_to_world(&sk.plane, m.Vec2{pos_2d.x + half, pos_2d.y + half}))

    append(&x_verts, sketch.sketch_to_world(&sk.plane, m.Vec2{pos_2d.x - half, pos_2d.y + half}))
    append(&x_verts, sketch.sketch_to_world(&sk.plane, m.Vec2{pos_2d.x + half, pos_2d.y - half}))

    // Draw in orange/amber
    line_shader_draw(shader, x_verts[:], {1.0, 0.7, 0.0, 1.0}, mvp, 2.0)
}

// Helper: Render equal icon (= symbol between entities)
render_equal_icon :: proc(shader: ^LineShader, sk: ^sketch.Sketch2D, data: sketch.EqualData, mvp: glsl.mat4, size: f64) {
    if data.entity1_id < 0 || data.entity1_id >= len(sk.entities) do return
    if data.entity2_id < 0 || data.entity2_id >= len(sk.entities) do return

    entity1 := sk.entities[data.entity1_id]

    // Get position based on entity type
    pos_2d: m.Vec2

    switch e in entity1 {
    case sketch.SketchLine:
        p1 := sketch.sketch_get_point(sk, e.start_id)
        p2 := sketch.sketch_get_point(sk, e.end_id)
        if p1 == nil || p2 == nil do return
        pos_2d = m.Vec2{(p1.x + p2.x) * 0.5, (p1.y + p2.y) * 0.5}
    case sketch.SketchCircle:
        center := sketch.sketch_get_point(sk, e.center_id)
        if center == nil do return
        pos_2d = m.Vec2{center.x, center.y}
    case sketch.SketchArc:
        // TODO: Arc support
        return
    }

    // Draw equal symbol (two horizontal lines)
    eq_verts := make([dynamic]m.Vec3, 0, 4)
    defer delete(eq_verts)

    width := size * 0.6
    spacing := size * 0.2

    // Top line
    append(&eq_verts, sketch.sketch_to_world(&sk.plane, m.Vec2{pos_2d.x - width * 0.5, pos_2d.y + spacing}))
    append(&eq_verts, sketch.sketch_to_world(&sk.plane, m.Vec2{pos_2d.x + width * 0.5, pos_2d.y + spacing}))

    // Bottom line
    append(&eq_verts, sketch.sketch_to_world(&sk.plane, m.Vec2{pos_2d.x - width * 0.5, pos_2d.y - spacing}))
    append(&eq_verts, sketch.sketch_to_world(&sk.plane, m.Vec2{pos_2d.x + width * 0.5, pos_2d.y - spacing}))

    // Draw in orange/amber
    line_shader_draw(shader, eq_verts[:], {1.0, 0.7, 0.0, 1.0}, mvp, 2.0)
}

// Helper: Render distance dimension
render_distance_dimension :: proc(shader: ^LineShader, sk: ^sketch.Sketch2D, data: sketch.DistanceData, mvp: glsl.mat4) {
    if data.point1_id < 0 || data.point1_id >= len(sk.points) do return
    if data.point2_id < 0 || data.point2_id >= len(sk.points) do return

    p1 := sketch.sketch_get_point(sk, data.point1_id)
    p2 := sketch.sketch_get_point(sk, data.point2_id)
    if p1 == nil || p2 == nil do return

    p1_3d := sketch.sketch_to_world(&sk.plane, m.Vec2{p1.x, p1.y})
    p2_3d := sketch.sketch_to_world(&sk.plane, m.Vec2{p2.x, p2.y})

    // Draw dimension line between points
    dim_verts := []m.Vec3{p1_3d, p2_3d}
    line_shader_draw(shader, dim_verts, {1.0, 1.0, 0.0, 1.0}, mvp, 2.5)  // Bright yellow, thicker

    // TODO: Add dimension text rendering (Week 8 Task 3)
}

// Helper: Render horizontal distance dimension
render_distance_x_dimension :: proc(shader: ^LineShader, sk: ^sketch.Sketch2D, data: sketch.DistanceXData, mvp: glsl.mat4) {
    if data.point1_id < 0 || data.point1_id >= len(sk.points) do return
    if data.point2_id < 0 || data.point2_id >= len(sk.points) do return

    p1 := sketch.sketch_get_point(sk, data.point1_id)
    p2 := sketch.sketch_get_point(sk, data.point2_id)
    if p1 == nil || p2 == nil do return

    // Draw horizontal dimension line
    offset_y := 0.3  // Offset from points

    p1_dim_2d := m.Vec2{p1.x, p1.y - offset_y}
    p2_dim_2d := m.Vec2{p2.x, p2.y - offset_y}

    p1_dim_3d := sketch.sketch_to_world(&sk.plane, p1_dim_2d)
    p2_dim_3d := sketch.sketch_to_world(&sk.plane, p2_dim_2d)

    // Extension lines
    ext_verts := make([dynamic]m.Vec3, 0, 4)
    defer delete(ext_verts)

    append(&ext_verts, sketch.sketch_to_world(&sk.plane, m.Vec2{p1.x, p1.y}))
    append(&ext_verts, p1_dim_3d)
    append(&ext_verts, sketch.sketch_to_world(&sk.plane, m.Vec2{p2.x, p2.y}))
    append(&ext_verts, p2_dim_3d)

    line_shader_draw(shader, ext_verts[:], {1.0, 1.0, 0.0, 0.6}, mvp, 1.5)  // Yellow extensions

    // Dimension line
    dim_verts := []m.Vec3{p1_dim_3d, p2_dim_3d}
    line_shader_draw(shader, dim_verts, {1.0, 1.0, 0.0, 1.0}, mvp, 2.5)  // Bright yellow, thicker
}

// Helper: Render vertical distance dimension
render_distance_y_dimension :: proc(shader: ^LineShader, sk: ^sketch.Sketch2D, data: sketch.DistanceYData, mvp: glsl.mat4) {
    if data.point1_id < 0 || data.point1_id >= len(sk.points) do return
    if data.point2_id < 0 || data.point2_id >= len(sk.points) do return

    p1 := sketch.sketch_get_point(sk, data.point1_id)
    p2 := sketch.sketch_get_point(sk, data.point2_id)
    if p1 == nil || p2 == nil do return

    // Draw vertical dimension line
    offset_x := 0.3  // Offset from points

    p1_dim_2d := m.Vec2{p1.x - offset_x, p1.y}
    p2_dim_2d := m.Vec2{p2.x - offset_x, p2.y}

    p1_dim_3d := sketch.sketch_to_world(&sk.plane, p1_dim_2d)
    p2_dim_3d := sketch.sketch_to_world(&sk.plane, p2_dim_2d)

    // Extension lines
    ext_verts := make([dynamic]m.Vec3, 0, 4)
    defer delete(ext_verts)

    append(&ext_verts, sketch.sketch_to_world(&sk.plane, m.Vec2{p1.x, p1.y}))
    append(&ext_verts, p1_dim_3d)
    append(&ext_verts, sketch.sketch_to_world(&sk.plane, m.Vec2{p2.x, p2.y}))
    append(&ext_verts, p2_dim_3d)

    line_shader_draw(shader, ext_verts[:], {1.0, 1.0, 0.0, 0.6}, mvp, 1.5)  // Yellow extensions

    // Dimension line
    dim_verts := []m.Vec3{p1_dim_3d, p2_dim_3d}
    line_shader_draw(shader, dim_verts, {1.0, 1.0, 0.0, 1.0}, mvp, 2.5)  // Bright yellow, thicker
}
