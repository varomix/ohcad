// features/sketch - Sketch save/load to JSON
package ohcad_sketch

import "core:fmt"
import "core:os"
import "core:encoding/json"
import m "../../core/math"

// JSON-serializable structures for sketch export
SketchPointJSON :: struct {
    id: int,
    x: f64,
    y: f64,
}

SketchLineJSON :: struct {
    start_id: int,
    end_id: int,
}

SketchCircleJSON :: struct {
    center_id: int,
    radius: f64,
}

SketchArcJSON :: struct {
    center_id: int,
    start_id: int,
    end_id: int,
    radius: f64,
}

SketchPlaneJSON :: struct {
    origin: [3]f64,
    x_axis: [3]f64,
    y_axis: [3]f64,
    normal: [3]f64,
}

SketchJSON :: struct {
    name: string,
    plane: SketchPlaneJSON,
    points: []SketchPointJSON,
    lines: []SketchLineJSON,
    circles: []SketchCircleJSON,
    arcs: []SketchArcJSON,
}

// Convert Sketch2D to JSON-serializable structure
sketch_to_json :: proc(sketch: ^Sketch2D, allocator := context.allocator) -> SketchJSON {
    result: SketchJSON

    result.name = sketch.name

    // Convert plane
    result.plane = SketchPlaneJSON{
        origin = [3]f64{sketch.plane.origin.x, sketch.plane.origin.y, sketch.plane.origin.z},
        x_axis = [3]f64{sketch.plane.x_axis.x, sketch.plane.x_axis.y, sketch.plane.x_axis.z},
        y_axis = [3]f64{sketch.plane.y_axis.x, sketch.plane.y_axis.y, sketch.plane.y_axis.z},
        normal = [3]f64{sketch.plane.normal.x, sketch.plane.normal.y, sketch.plane.normal.z},
    }

    // Convert points
    points := make([]SketchPointJSON, len(sketch.points), allocator)
    for pt, i in sketch.points {
        points[i] = SketchPointJSON{
            id = pt.id,
            x = pt.x,
            y = pt.y,
        }
    }
    result.points = points

    // Separate entities by type
    lines := make([dynamic]SketchLineJSON, 0, len(sketch.entities), allocator)
    circles := make([dynamic]SketchCircleJSON, 0, len(sketch.entities), allocator)
    arcs := make([dynamic]SketchArcJSON, 0, len(sketch.entities), allocator)

    for entity in sketch.entities {
        switch e in entity {
        case SketchLine:
            append(&lines, SketchLineJSON{
                start_id = e.start_id,
                end_id = e.end_id,
            })
        case SketchCircle:
            append(&circles, SketchCircleJSON{
                center_id = e.center_id,
                radius = e.radius,
            })
        case SketchArc:
            append(&arcs, SketchArcJSON{
                center_id = e.center_id,
                start_id = e.start_id,
                end_id = e.end_id,
                radius = e.radius,
            })
        }
    }

    result.lines = lines[:]
    result.circles = circles[:]
    result.arcs = arcs[:]

    return result
}

// Convert JSON structure back to Sketch2D
sketch_from_json :: proc(sketch_json: SketchJSON) -> Sketch2D {
    sketch: Sketch2D

    sketch.name = sketch_json.name

    // Convert plane
    sketch.plane = SketchPlane{
        origin = m.Vec3{sketch_json.plane.origin.x, sketch_json.plane.origin.y, sketch_json.plane.origin.z},
        x_axis = m.Vec3{sketch_json.plane.x_axis.x, sketch_json.plane.x_axis.y, sketch_json.plane.x_axis.z},
        y_axis = m.Vec3{sketch_json.plane.y_axis.x, sketch_json.plane.y_axis.y, sketch_json.plane.y_axis.z},
        normal = m.Vec3{sketch_json.plane.normal.x, sketch_json.plane.normal.y, sketch_json.plane.normal.z},
    }

    // Initialize dynamic arrays
    sketch.points = make([dynamic]SketchPoint)
    sketch.entities = make([dynamic]SketchEntity)

    // Convert points
    for pt_json in sketch_json.points {
        append(&sketch.points, SketchPoint{
            id = pt_json.id,
            x = pt_json.x,
            y = pt_json.y,
        })
    }

    // Update next_point_id
    sketch.next_point_id = 0
    for pt in sketch.points {
        if pt.id >= sketch.next_point_id {
            sketch.next_point_id = pt.id + 1
        }
    }

    // Convert lines
    for line_json in sketch_json.lines {
        append(&sketch.entities, SketchEntity(SketchLine{
            start_id = line_json.start_id,
            end_id = line_json.end_id,
        }))
    }

    // Convert circles
    for circle_json in sketch_json.circles {
        append(&sketch.entities, SketchEntity(SketchCircle{
            center_id = circle_json.center_id,
            radius = circle_json.radius,
        }))
    }

    // Convert arcs
    for arc_json in sketch_json.arcs {
        append(&sketch.entities, SketchEntity(SketchArc{
            center_id = arc_json.center_id,
            start_id = arc_json.start_id,
            end_id = arc_json.end_id,
            radius = arc_json.radius,
        }))
    }

    // Initialize tool state
    sketch.current_tool = .Select
    sketch.temp_point_valid = false
    sketch.first_point_id = -1
    sketch.selected_entity = -1

    return sketch
}

// Save sketch to JSON file
sketch_save_to_file :: proc(sketch: ^Sketch2D, filename: string) -> bool {
    // Convert to JSON structure
    sketch_json := sketch_to_json(sketch)
    defer {
        delete(sketch_json.points)
        delete(sketch_json.lines)
        delete(sketch_json.circles)
        delete(sketch_json.arcs)
    }

    // Marshal to JSON with indentation
    data, marshal_err := json.marshal(sketch_json, {pretty = true, use_spaces = true, spaces = 2})
    if marshal_err != nil {
        fmt.eprintln("ERROR: Failed to marshal sketch to JSON:", marshal_err)
        return false
    }
    defer delete(data)

    // Write to file
    write_ok := os.write_entire_file(filename, data)
    if !write_ok {
        fmt.eprintln("ERROR: Failed to write file:", filename)
        return false
    }

    fmt.printf("Sketch saved to: %s\n", filename)
    return true
}

// Load sketch from JSON file
sketch_load_from_file :: proc(filename: string) -> (Sketch2D, bool) {
    // Read file
    data, read_ok := os.read_entire_file(filename)
    if !read_ok {
        fmt.eprintln("ERROR: Failed to read file:", filename)
        return Sketch2D{}, false
    }
    defer delete(data)

    // Unmarshal JSON
    sketch_json: SketchJSON
    unmarshal_err := json.unmarshal(data, &sketch_json)
    if unmarshal_err != nil {
        fmt.eprintln("ERROR: Failed to unmarshal JSON:", unmarshal_err)
        return Sketch2D{}, false
    }
    defer {
        delete(sketch_json.points)
        delete(sketch_json.lines)
        delete(sketch_json.circles)
        delete(sketch_json.arcs)
    }

    // Convert to Sketch2D
    sketch := sketch_from_json(sketch_json)

    fmt.printf("Sketch loaded from: %s\n", filename)
    return sketch, true
}
