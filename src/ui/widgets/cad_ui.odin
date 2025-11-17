// OhCAD - Real CAD UI Panels and Layout
package widgets

import "core:fmt"
import "core:math"
import doc "../../core/document"
import sketch "../../features/sketch"
import ftree "../../features/feature_tree"
import extrude "../../features/extrude"

// =============================================================================
// CAD UI State - Holds state for CAD-specific UI panels
// =============================================================================

CADUIState :: struct {
    // Panel visibility
    show_toolbar: bool,
    show_properties: bool,
    show_feature_tree: bool,

    // Panel sizes/positions
    toolbar_width: f32,
    properties_width: f32,
    feature_tree_width: f32,

    // Feature parameter editing (for properties panel)
    temp_extrude_depth: f32,
    temp_revolve_angle: f32,
    temp_cut_depth: f32,
    temp_constraint_value: f32,  // For constraint editing

    // Solid toolbar state
    show_plane_selector: bool,  // For New Sketch button plane selection

    // Selected face info (for sketch-on-face workflow)
    selected_feature_id: int,  // -1 if no face selected
    selected_face_index: int,  // Face index within feature
    create_sketch_on_face: bool,  // Flag to signal main loop to create sketch on selected face
}

cad_ui_state_init :: proc() -> CADUIState {
    return CADUIState{
        show_toolbar = true,
        show_properties = true,
        show_feature_tree = true,
        toolbar_width = 250,
        properties_width = 250,
        feature_tree_width = 250,
        temp_extrude_depth = 1.0,
        temp_revolve_angle = 360.0,
        temp_cut_depth = 0.3,
        selected_feature_id = -1,  // No face selected initially
        selected_face_index = -1,
    }
}

// =============================================================================
// Toolbar Panel - Tool Selection
// =============================================================================

ui_toolbar_panel :: proc(
    ctx: ^UIContext,
    cad_state: ^CADUIState,
    sk: ^sketch.Sketch2D,
    x, y, width: f32,
) -> f32 {
    if !cad_state.show_toolbar do return 0

    // If no active sketch, don't show sketch tools
    if sk == nil do return 0

    current_y := y
    spacing: f32 = 10

    // Section: SKETCH TOOLS
    ui_section_box(
        ctx,
        x, current_y,
        width, 40,
        "SKETCH TOOLS",
        {0, 200, 200, 255},  // Cyan
        {0, 200, 200, 255},
    )
    current_y += 50

    // Tool Icons - 4 across
    icon_size: f32 = 56
    icon_spacing: f32 = 4
    icons_per_row := 4
    icon_x_start := x + spacing

    tools := []struct{
        name: string,
        abbrev: string,
        tool: sketch.SketchTool,
        color: [4]u8,
    }{
        {"Select", "SL", .Select, {100, 150, 255, 255}},    // Blue
        {"Line", "LN", .Line, {0, 255, 100, 255}},          // Green
        {"Circle", "CR", .Circle, {255, 180, 0, 255}},      // Orange
        {"Arc", "AR", .Arc, {255, 100, 200, 255}},          // Pink
        {"Dimension", "DM", .Dimension, {200, 200, 0, 255}}, // Yellow
    }

    row := 0
    col := 0

    for tool in tools {
        icon_x := icon_x_start + f32(col) * (icon_size + icon_spacing)
        icon_y := current_y + f32(row) * (icon_size + icon_spacing)

        if ui_tool_icon(
            ctx,
            icon_x, icon_y,
            icon_size,
            tool.abbrev,
            tool.color,
            sk.current_tool == tool.tool,
        ) {
            sketch.sketch_set_tool(sk, tool.tool)
            fmt.printf("Tool: %s\n", tool.name)
        }

        col += 1
        if col >= icons_per_row {
            col = 0
            row += 1
        }
    }

    // Calculate total height used
    total_rows := (len(tools) + icons_per_row - 1) / icons_per_row
    current_y += f32(total_rows) * (icon_size + icon_spacing) + spacing

    return current_y - y  // Return total height used
}

// =============================================================================
// Solid Toolbar Panel - Tool Selection for Solid Mode
// =============================================================================

ui_solid_toolbar_panel :: proc(
    ctx: ^UIContext,
    cad_state: ^CADUIState,
    x, y, width: f32,
) -> f32 {
    if !cad_state.show_toolbar do return 0

    current_y := y
    spacing: f32 = 10

    // Section: SOLID TOOLS
    ui_section_box(
        ctx,
        x, current_y,
        width, 40,
        "SOLID TOOLS",
        {100, 150, 255, 255},  // Blue
        {100, 150, 255, 255},
    )
    current_y += 50

    // Tool Icons - 4 across (same layout as sketch toolbar)
    icon_size: f32 = 56
    icon_spacing: f32 = 4
    icons_per_row := 4
    icon_x_start := x + spacing

    // Main solid mode tools
    tools := []struct{
        name: string,
        abbrev: string,
        id: int,  // 1=NewSketch, 2=Extrude, 3=Fillet, 4=Chamfer, 5=Box, 6=Cylinder, 7=Sphere, 8=Cone, 9=Torus
        color: [4]u8,
        enabled: bool,
    }{
        {"New Sketch", "NS", 1, {0, 200, 220, 255}, true},      // Cyan
        {"Extrude", "EX", 2, {0, 200, 100, 255}, true},         // Green
        {"Fillet", "FT", 3, {150, 150, 150, 255}, false},       // Gray (disabled)
        {"Chamfer", "CH", 4, {150, 150, 150, 255}, false},      // Gray (disabled)
        {"Box", "BX", 5, {255, 180, 50, 255}, true},            // Orange - PRIMITIVE
        {"Cylinder", "CY", 6, {255, 120, 180, 255}, true},      // Pink - PRIMITIVE
        {"Sphere", "SP", 7, {120, 200, 255, 255}, true},        // Light Blue - PRIMITIVE
        {"Cone", "CN", 8, {200, 150, 255, 255}, true},          // Purple - PRIMITIVE
        {"Torus", "TR", 9, {255, 220, 100, 255}, true},         // Yellow - PRIMITIVE
    }

    row := 0
    col := 0

    for tool in tools {
        icon_x := icon_x_start + f32(col) * (icon_size + icon_spacing)
        icon_y := current_y + f32(row) * (icon_size + icon_spacing)

        // Check if this is New Sketch and plane selector is active
        is_selected := (tool.id == 1 && cad_state.show_plane_selector)

        if ui_tool_icon(
            ctx,
            icon_x, icon_y,
            icon_size,
            tool.abbrev,
            tool.color,
            is_selected,
        ) {
            if tool.enabled {
                if tool.id == 1 {
                    // New Sketch - check if face is selected first
                    if cad_state.selected_feature_id >= 0 {
                        // Face is selected → create sketch on that face
                        cad_state.create_sketch_on_face = true
                        fmt.println("New Sketch on selected face")
                    } else {
                        // No face selected → show plane selector
                        cad_state.show_plane_selector = !cad_state.show_plane_selector
                        fmt.printf("New Sketch clicked - plane selector: %v\n", cad_state.show_plane_selector)
                    }
                } else if tool.id == 2 {
                    fmt.printf("Extrude clicked (TODO: implement handler)\n")
                } else if tool.id >= 5 && tool.id <= 9 {
                    // Primitives: Box, Cylinder, Sphere, Cone, Torus
                    ctx.clicked_primitive_id = tool.id
                    fmt.printf("Primitive clicked: %s (ID: %d)\n", tool.name, tool.id)
                } else {
                    fmt.printf("Tool: %s\n", tool.name)
                }
            } else {
                fmt.printf("Tool: %s (not yet implemented)\n", tool.name)
            }
        }

        col += 1
        if col >= icons_per_row {
            col = 0
            row += 1
        }
    }

    // Calculate total height used by icons
    total_rows := (len(tools) + icons_per_row - 1) / icons_per_row
    current_y += f32(total_rows) * (icon_size + icon_spacing) + spacing

    // Plane selection buttons (show when New Sketch is active)
    if cad_state.show_plane_selector {
        // Small indented plane selector icons (3 in a row)
        plane_icon_size: f32 = 52
        plane_icon_spacing: f32 = 4
        plane_x_start := x + spacing * 2  // Indent slightly

        planes := []struct{
            name: string,
            abbrev: string,
            plane_id: int,
            color: [4]u8,
        }{
            {"XY", "XY", 1, {0, 200, 100, 255}},      // Green
            {"YZ", "YZ", 2, {200, 150, 0, 255}},      // Orange
            {"ZX", "ZX", 3, {150, 100, 255, 255}},    // Purple
        }

        plane_col := 0
        for plane in planes {
            plane_icon_x := plane_x_start + f32(plane_col) * (plane_icon_size + plane_icon_spacing)

            if ui_tool_icon(
                ctx,
                plane_icon_x, current_y,
                plane_icon_size,
                plane.abbrev,
                plane.color,
                false,
            ) {
                // Store selected plane in UI context
                ctx.selected_sketch_plane = plane.plane_id
                cad_state.show_plane_selector = false  // Close selector after selection
                fmt.printf("Selected plane: %s (ID: %d)\n", plane.name, plane.plane_id)
            }

            plane_col += 1
        }

        current_y += plane_icon_size + spacing
    }

    return current_y - y  // Return total height used
}

// =============================================================================
// Properties Panel - Selected Entity Info
// =============================================================================

ui_properties_panel :: proc(
    ctx: ^UIContext,
    cad_state: ^CADUIState,
    sk: ^sketch.Sketch2D,
    feature_tree: ^ftree.FeatureTree,
    extrude_feature_id: int,
    document_settings: ^doc.DocumentSettings,  // NEW: Pass document settings for unit selection
    x, y, width: f32,
) -> (f32, bool) {
    if !cad_state.show_properties do return 0, false

    needs_update := false
    current_y := y
    spacing: f32 = 10
    widget_height: f32 = 28

    // Section: PROPERTIES
    ui_section_box(
        ctx,
        x, current_y,
        width, 40,
        "PROPERTIES",
        {255, 180, 0, 255},  // Orange
        {255, 180, 0, 255},
    )
    current_y += 50

    // Show selected entity info (if sketch exists)
    if sk != nil {
        // Priority 1: Show selected constraint (if any)
        if sk.selected_constraint_id >= 0 {
            constraint := sketch.sketch_get_constraint(sk, sk.selected_constraint_id)
            if constraint != nil {
                // Constraint type
                constraint_type_str := ""
                #partial switch constraint.type {
                case .Distance: constraint_type_str = "Distance"
                case .DistanceX: constraint_type_str = "Distance X"
                case .DistanceY: constraint_type_str = "Distance Y"
                case .Horizontal: constraint_type_str = "Horizontal"
                case .Vertical: constraint_type_str = "Vertical"
                case .Angle: constraint_type_str = "Angle"
                case .Perpendicular: constraint_type_str = "Perpendicular"
                case .Parallel: constraint_type_str = "Parallel"
                case .Coincident: constraint_type_str = "Coincident"
                case .Equal: constraint_type_str = "Equal"
                case .FixedPoint: constraint_type_str = "Fixed Point"
                case .FixedDistance: constraint_type_str = "Fixed Distance"
                case .FixedAngle: constraint_type_str = "Fixed Angle"
                case: constraint_type_str = "Unknown"
                }

                ui_text_input(
                    ctx,
                    x + spacing, current_y,
                    width - spacing * 2, widget_height,
                    "TYPE",
                    constraint_type_str,
                )
                current_y += widget_height + spacing

                // Show editable value for numeric constraints
                value, has_value := sketch.sketch_get_constraint_value(sk, sk.selected_constraint_id)
                if has_value {
                    // Use absolute value for DistanceX and DistanceY (since they use signed values internally)
                    display_value := value
                    if constraint.type == .DistanceX || constraint.type == .DistanceY {
                        display_value = math.abs(value)
                    }

                    // Initialize temp value if needed
                    if cad_state.temp_constraint_value == 0 {
                        cad_state.temp_constraint_value = f32(display_value)
                    }

                    label := "VALUE"
                    if constraint.type == .Angle || constraint.type == .FixedAngle {
                        label = "ANGLE"
                    } else {
                        label = "DISTANCE"
                    }

                    if ui_numeric_stepper(
                        ctx,
                        x + spacing, current_y,
                        width - spacing * 2, widget_height,
                        label,
                        &cad_state.temp_constraint_value,
                        0.1, 0.1, 999.0,
                    ) {
                        // Update constraint value
                        if sketch.sketch_modify_constraint_value(sk, sk.selected_constraint_id, f64(cad_state.temp_constraint_value)) {
                            // Re-solve constraints after modification
                            result := sketch.sketch_solve_constraints(sk)
                            if result.status == .Success {
                                fmt.printf("✓ Constraint value updated: %.2f (solver converged)\n", cad_state.temp_constraint_value)
                                needs_update = true
                            } else {
                                fmt.printf("⚠️  Constraint value updated: %.2f (solver: %v)\n", cad_state.temp_constraint_value, result.status)
                                needs_update = true  // Still update display even if solver didn't converge
                            }
                        } else {
                            fmt.printf("❌ Failed to update constraint value\n")
                        }
                    }
                    current_y += widget_height + spacing
                }

                // Delete constraint button
                if ui_button(
                    ctx,
                    x + spacing, current_y,
                    width - spacing * 2, widget_height,
                    "Delete Constraint",
                    {220, 50, 50, 255},  // Red
                    {255, 80, 80, 255},
                ) {
                    // Delete the constraint
                    if sketch.sketch_remove_constraint(sk, sk.selected_constraint_id) {
                        sketch.sketch_deselect_constraint(sk)
                        cad_state.temp_constraint_value = 0
                        needs_update = true
                        fmt.printf("✓ Constraint deleted\n")
                    }
                }
                current_y += widget_height + spacing
            }
        } else if sk.selected_entity >= 0 && sk.selected_entity < len(sk.entities) {
            // Priority 2: Show selected entity
            entity := sk.entities[sk.selected_entity]

        switch e in entity {
        case sketch.SketchLine:
            // Line properties
            ui_text_input(
                ctx,
                x + spacing, current_y,
                width - spacing * 2, widget_height,
                "TYPE",
                "Line",
            )
            current_y += widget_height + spacing

            // Line length (read-only for now)
            start_point := sketch.sketch_get_point(sk, e.start_id)
            end_point := sketch.sketch_get_point(sk, e.end_id)

            if start_point != nil && end_point != nil {
                dx := end_point.x - start_point.x
                dy := end_point.y - start_point.y
                length := fmt.tprintf("%.2f", math.sqrt(dx*dx + dy*dy))

                ui_text_input(
                    ctx,
                    x + spacing, current_y,
                    width - spacing * 2, widget_height,
                    "LENGTH",
                    length,
                )
            }
            current_y += widget_height + spacing

        case sketch.SketchCircle:
            // Circle properties
            ui_text_input(
                ctx,
                x + spacing, current_y,
                width - spacing * 2, widget_height,
                "TYPE",
                "Circle",
            )
            current_y += widget_height + spacing

            radius := fmt.tprintf("%.2f", e.radius)
            ui_text_input(
                ctx,
                x + spacing, current_y,
                width - spacing * 2, widget_height,
                "RADIUS",
                radius,
            )
            current_y += widget_height + spacing

        case sketch.SketchArc:
            // Arc properties
            ui_text_input(
                ctx,
                x + spacing, current_y,
                width - spacing * 2, widget_height,
                "TYPE",
                "Arc",
            )
            current_y += widget_height + spacing
        }
        }
    } else {
        // No selection - show document settings and most recent feature properties

        // Section 1: Document Settings (Unit Selection)
        ui_text_input(
            ctx,
            x + spacing, current_y,
            width - spacing * 2, widget_height,
            "",
            "DOCUMENT",
        )
        current_y += widget_height + spacing

        // Unit selection dropdown (for now, using button to toggle)
        unit_text := doc.unit_name(document_settings.units)

        if ui_button(
            ctx,
            x + spacing, current_y,
            width - spacing * 2, widget_height,
            fmt.tprintf("UNITS: %s", unit_text),
            {80, 120, 180, 255},  // Blue
            {100, 150, 220, 255},
        ) {
            // Toggle between millimeters and inches
            if document_settings.units == .Millimeters {
                doc.document_settings_set_units(document_settings, .Inches)
            } else {
                doc.document_settings_set_units(document_settings, .Millimeters)
            }
            needs_update = true
        }
        current_y += widget_height + spacing

        // Show units on dimensions toggle
        show_units_text := document_settings.show_units_on_dimensions ? "SHOW UNITS: ON" : "SHOW UNITS: OFF"
        show_units_color := document_settings.show_units_on_dimensions ? [4]u8{0, 150, 0, 255} : [4]u8{100, 100, 100, 255}

        if ui_button(
            ctx,
            x + spacing, current_y,
            width - spacing * 2, widget_height,
            show_units_text,
            show_units_color,
            {0, 200, 0, 255},
        ) {
            // Toggle show units on dimensions
            document_settings.show_units_on_dimensions = !document_settings.show_units_on_dimensions
            needs_update = true
            fmt.printf("✓ Show units on dimensions: %v\n", document_settings.show_units_on_dimensions)
        }
        current_y += widget_height + spacing * 2  // Extra spacing before feature properties

        // Section 2: Last Feature Properties (if any)
        last_feature: ^ftree.FeatureNode = nil

        // Find the most recent Extrude, Revolve, or Cut feature
        for i := len(feature_tree.features) - 1; i >= 0; i -= 1 {
            feature := &feature_tree.features[i]
            if feature.type == .Extrude || feature.type == .Revolve || feature.type == .Cut {
                last_feature = feature
                break
            }
        }

        if last_feature != nil {
            // Initialize temp values from feature parameters
            #partial switch params in last_feature.params {
            case ftree.ExtrudeParams:
                cad_state.temp_extrude_depth = f32(params.depth)
            case ftree.RevolveParams:
                cad_state.temp_revolve_angle = f32(params.angle)
            case ftree.CutParams:
                cad_state.temp_cut_depth = f32(params.depth)
            }

            // Display properties based on feature type
            #partial switch last_feature.type {
            case .Extrude:
                params := last_feature.params.(ftree.ExtrudeParams)

                ui_text_input(
                    ctx,
                    x + spacing, current_y,
                    width - spacing * 2, widget_height,
                    "FEATURE",
                    "Extrude",
                )
                current_y += widget_height + spacing

                // Editable extrude depth with numeric stepper
                if ui_numeric_stepper(
                    ctx,
                    x + spacing, current_y,
                    width - spacing * 2, widget_height,
                    "DEPTH",
                    &cad_state.temp_extrude_depth,
                    0.1, 0.1, 10.0,
                ) {
                    // Update extrude depth
                    params.depth = f64(cad_state.temp_extrude_depth)
                    last_feature.params = params
                    ftree.feature_tree_mark_dirty(feature_tree, last_feature.id)
                    needs_update = true
                    fmt.printf("Extrude depth: %.2f\n", cad_state.temp_extrude_depth)
                }
                current_y += widget_height + spacing

                // Extrude direction
                direction_str := ""
                switch params.direction {
                case .Forward: direction_str = "Forward"
                case .Backward: direction_str = "Backward"
                case .Symmetric: direction_str = "Symmetric"
                }

                ui_text_input(
                    ctx,
                    x + spacing, current_y,
                    width - spacing * 2, widget_height,
                    "DIRECTION",
                    direction_str,
                )
                current_y += widget_height + spacing

            case .Revolve:
                params := last_feature.params.(ftree.RevolveParams)

                ui_text_input(
                    ctx,
                    x + spacing, current_y,
                    width - spacing * 2, widget_height,
                    "FEATURE",
                    "Revolve",
                )
                current_y += widget_height + spacing

                // Revolve angle with slider (0-360°)
                // Show label
                ui_text_input(
                    ctx,
                    x + spacing, current_y,
                    width - spacing * 2, widget_height,
                    "ANGLE",
                    fmt.tprintf("%.0f°", cad_state.temp_revolve_angle),
                )
                current_y += widget_height + spacing

                // Slider control
                if ui_slider(
                    ctx,
                    x + spacing, current_y,
                    width - spacing * 2, widget_height,
                    &cad_state.temp_revolve_angle,
                    1.0, 360.0,
                ) {
                    // Update revolve angle
                    params.angle = f64(cad_state.temp_revolve_angle)
                    last_feature.params = params
                    ftree.feature_tree_mark_dirty(feature_tree, last_feature.id)
                    needs_update = true
                    fmt.printf("Revolve angle: %.0f°\n", cad_state.temp_revolve_angle)
                }
                current_y += widget_height + spacing

                // Revolve axis type
                axis_str := ""
                switch params.axis_type {
                case .SketchX: axis_str = "Sketch X-axis"
                case .SketchY: axis_str = "Sketch Y-axis"
                case .Custom: axis_str = "Custom"
                }

                ui_text_input(
                    ctx,
                    x + spacing, current_y,
                    width - spacing * 2, widget_height,
                    "AXIS",
                    axis_str,
                )
                current_y += widget_height + spacing

            case .Cut:
                params := last_feature.params.(ftree.CutParams)

                ui_text_input(
                    ctx,
                    x + spacing, current_y,
                    width - spacing * 2, widget_height,
                    "FEATURE",
                    "Cut",
                )
                current_y += widget_height + spacing

                // Editable cut depth with numeric stepper
                if ui_numeric_stepper(
                    ctx,
                    x + spacing, current_y,
                    width - spacing * 2, widget_height,
                    "DEPTH",
                    &cad_state.temp_cut_depth,
                    0.1, 0.05, 5.0,
                ) {
                    // Update cut depth
                    params.depth = f64(cad_state.temp_cut_depth)
                    last_feature.params = params
                    ftree.feature_tree_mark_dirty(feature_tree, last_feature.id)
                    needs_update = true
                    fmt.printf("Cut depth: %.2f\n", cad_state.temp_cut_depth)
                }
                current_y += widget_height + spacing

            case:
                // Other feature types
                ui_text_input(
                    ctx,
                    x + spacing, current_y,
                    width - spacing * 2, widget_height,
                    "",
                    "Feature properties unavailable",
                )
                current_y += widget_height + spacing
            }
        } else {
            // No features to show
            ui_text_input(
                ctx,
                x + spacing, current_y,
                width - spacing * 2, widget_height,
                "",
                "No features",
            )
            current_y += widget_height + spacing
        }
    }

    return current_y - y, needs_update  // Return total height used and update flag
}

// =============================================================================
// Feature Tree Panel - Shows parametric history with double-click support
// =============================================================================

// Result from feature tree interaction
FeatureTreeInteraction :: struct {
    clicked_feature_id: int,  // -1 if no click, feature ID if clicked
    double_clicked: bool,      // true if double-click detected
}

ui_feature_tree_panel :: proc(
    ctx: ^UIContext,
    cad_state: ^CADUIState,
    feature_tree: ^ftree.FeatureTree,
    x, y, width: f32,
    editing_feature_id: int,  // NEW: ID of feature currently being edited (-1 if none)
) -> (height: f32, interaction: FeatureTreeInteraction) {
    spacing: f32 = 10
    current_y := y
    item_height: f32 = 28

    // Initialize interaction result
    interaction = FeatureTreeInteraction{clicked_feature_id = -1, double_clicked = false}

    // Section: FEATURE TREE
    ui_section_box(
        ctx,
        x, current_y,
        width, 40,
        "HISTORY",
        {0, 255, 100, 255},  // Green
        {0, 255, 100, 255},
    )
    current_y += 50

    // List all features
    for feature, i in feature_tree.features {
        if !feature.enabled do continue

        // Feature type icon
        icon_text := ""
        icon_color := [4]u8{150, 150, 150, 255}

        switch feature.type {
        case .Sketch:
            icon_text = "SK"
            icon_color = {0, 200, 200, 255}  // Cyan
        case .Extrude:
            icon_text = "EX"
            icon_color = {0, 255, 100, 255}  // Green
        case .Revolve:
            icon_text = "RV"
            icon_color = {255, 150, 0, 255}  // Orange
        case .Cut:
            icon_text = "CT"
            icon_color = {255, 100, 100, 255}  // Red
        case .Fillet, .Chamfer:
            icon_text = "??"
            icon_color = {150, 150, 150, 255}  // Gray
        }

        // Check if this feature is being edited
        is_editing := (editing_feature_id == feature.id)

        // Draw feature item as a button-like widget
        is_hot := ui_point_in_rect(ctx.mouse_x, ctx.mouse_y, x + spacing, current_y, width - spacing * 2, item_height)

        if is_hot {
            ctx.mouse_over_ui = true

            // Detect click on this feature (only on mouse button DOWN transition)
            if !ctx.mouse_down_prev && ctx.mouse_down {
                interaction.clicked_feature_id = feature.id
            }
        }

        // Background color: yellow if editing, highlight if hovering, dark otherwise
        bg_color: [4]u8
        if is_editing {
            bg_color = {100, 100, 0, 255}  // Dark yellow for editing
        } else if is_hot {
            bg_color = ctx.style.bg_medium
        } else {
            bg_color = ctx.style.bg_dark
        }

        ui_render_rect(ctx, x + spacing, current_y, width - spacing * 2, item_height, bg_color)

        // Border
        border_color := ctx.style.bg_light
        border_width: f32 = 1.0
        ui_render_rect(ctx, x + spacing, current_y, width - spacing * 2, border_width, border_color)
        ui_render_rect(ctx, x + spacing, current_y + item_height - border_width, width - spacing * 2, border_width, border_color)
        ui_render_rect(ctx, x + spacing, current_y, border_width, item_height, border_color)
        ui_render_rect(ctx, x + spacing + width - spacing * 2 - border_width, current_y, border_width, item_height, border_color)

        // Icon (with editing indicator)
        icon_size: f32 = 24
        icon_x := x + spacing + 4
        icon_y := current_y + (item_height - icon_size) * 0.5

        ui_render_rect(ctx, icon_x, icon_y, icon_size, icon_size, ctx.style.bg_medium)

        // Icon text - show "✏️" if editing, otherwise show feature type
        display_icon := is_editing ? "ED" : icon_text  // "ED" for "Editing"
        display_color := is_editing ? [4]u8{255, 255, 0, 255} : icon_color  // Yellow if editing

        icon_text_width, icon_text_height := ui_measure_text(ctx, display_icon, ctx.style.font_size_small)
        icon_text_x := icon_x + (icon_size - icon_text_width) * 0.5
        icon_text_y := icon_y + (icon_size - icon_text_height) * 0.5
        ui_render_text(ctx, display_icon, icon_text_x, icon_text_y, ctx.style.font_size_small, display_color)

        // Feature name
        name_x := icon_x + icon_size + 8
        name_y := current_y + (item_height - ctx.style.font_size_small) * 0.5
        ui_render_text(ctx, feature.name, name_x, name_y, ctx.style.font_size_small, ctx.style.text_primary)

        // Checkmark button (✓) for finishing sketch edit (only show when editing)
        if is_editing && feature.type == .Sketch {
            checkmark_size: f32 = 20
            checkmark_x := x + width - spacing - checkmark_size - 40  // Position before visibility indicator
            checkmark_y := current_y + (item_height - checkmark_size) * 0.5

            // Check if mouse is over checkmark button
            is_checkmark_hot := ui_point_in_rect(ctx.mouse_x, ctx.mouse_y, checkmark_x, checkmark_y, checkmark_size, checkmark_size)

            // Checkmark button background
            checkmark_bg_color := is_checkmark_hot ? [4]u8{0, 150, 0, 255} : [4]u8{0, 100, 0, 255}  // Green
            ui_render_rect(ctx, checkmark_x, checkmark_y, checkmark_size, checkmark_size, checkmark_bg_color)

            // Checkmark border
            border_width_check: f32 = 1.0
            ui_render_rect(ctx, checkmark_x, checkmark_y, checkmark_size, border_width_check, {0, 255, 0, 255})
            ui_render_rect(ctx, checkmark_x, checkmark_y + checkmark_size - border_width_check, checkmark_size, border_width_check, {0, 255, 0, 255})
            ui_render_rect(ctx, checkmark_x, checkmark_y, border_width_check, checkmark_size, {0, 255, 0, 255})
            ui_render_rect(ctx, checkmark_x + checkmark_size - border_width_check, checkmark_y, border_width_check, checkmark_size, {0, 255, 0, 255})

            // Checkmark text "✓"
            checkmark_text := "OK"  // Using "OK" since "✓" might not render well
            check_text_width, check_text_height := ui_measure_text(ctx, checkmark_text, ctx.style.font_size_small)
            check_text_x := checkmark_x + (checkmark_size - check_text_width) * 0.5
            check_text_y := checkmark_y + (checkmark_size - check_text_height) * 0.5
            ui_render_text(ctx, checkmark_text, check_text_x, check_text_y, ctx.style.font_size_small, {255, 255, 255, 255})

            // Detect click on checkmark button
            if is_checkmark_hot {
                ctx.mouse_over_ui = true
                if !ctx.mouse_down_prev && ctx.mouse_down {
                    // Trigger finish edit action
                    interaction.double_clicked = true  // Reuse this flag to signal "finish editing"
                    interaction.clicked_feature_id = feature.id
                }
            }
        }

        // Visibility toggle (small indicator)
        if feature.visible {
            vis_size: f32 = 8
            vis_x := x + width - spacing - vis_size - 8
            vis_y := current_y + (item_height - vis_size) * 0.5
            ui_render_rect(ctx, vis_x, vis_y, vis_size, vis_size, {0, 255, 100, 255})
        }

        current_y += item_height + 4
    }

    height = current_y - y  // Return total height used
    return
}

// =============================================================================
// Mode Indicator Banner - Prominent mode display at top
// =============================================================================

ui_mode_indicator_banner :: proc(
    ctx: ^UIContext,
    is_sketch_mode: bool,
    sketch_name: string,
    screen_width: u32,
) {
    banner_height: f32 = 50
    banner_y: f32 = 0

    // Background color based on mode
    bg_color: [4]u8
    if is_sketch_mode {
        bg_color = {0, 100, 120, 255}  // Dark teal for Sketch Mode
    } else {
        bg_color = {40, 40, 50, 255}   // Dark gray for Solid Mode
    }

    ui_render_rect(ctx, 0, banner_y, f32(screen_width), banner_height, bg_color)

    // Bottom border
    border_color: [4]u8
    if is_sketch_mode {
        border_color = {0, 200, 255, 255}  // Bright cyan for Sketch Mode
    } else {
        border_color = {100, 100, 120, 255}  // Gray for Solid Mode
    }

    ui_render_rect(ctx, 0, banner_y + banner_height - 2, f32(screen_width), 2, border_color)

    // Mode text
    mode_text: string
    if is_sketch_mode {
        mode_text = "■ SKETCH MODE"
    } else {
        mode_text = "■ SOLID MODE"
    }

    text_x: f32 = 20
    text_y := banner_y + 10

    text_color: [4]u8
    if is_sketch_mode {
        text_color = {0, 255, 255, 255}  // Bright cyan for Sketch Mode
    } else {
        text_color = {150, 150, 170, 255}  // Light gray for Solid Mode
    }

    ui_render_text(ctx, mode_text, text_x, text_y, ctx.style.font_size_normal, text_color)

    // Sketch name or instructions
    info_text: string
    if is_sketch_mode {
        info_text = fmt.tprintf("Editing: %s  |  Press [ESC] to exit", sketch_name)
    } else {
        info_text = "Press [1] XY  [2] YZ  [3] XZ to create sketch  |  [E] Extrude  [T] Cut"
    }

    info_y := text_y + ctx.style.font_size_normal + 2
    ui_render_text(ctx, info_text, text_x, info_y, ctx.style.font_size_small, ctx.style.text_secondary)
}

// =============================================================================
// Status Bar - Bottom info bar
// =============================================================================

ui_cad_status_bar :: proc(
    ctx: ^UIContext,
    is_sketch_mode: bool,
    sk: ^sketch.Sketch2D,
    editing_constraint_id: int,  // NEW: Pass editing state
    document_settings: ^doc.DocumentSettings,  // NEW: Pass document settings for unit display
    screen_width: u32,
    screen_height: u32,
) {
    bar_height: f32 = 30
    bar_y := f32(screen_height) - bar_height

    // Background
    ui_render_rect(ctx, 0, bar_y, f32(screen_width), bar_height, ctx.style.bg_dark)

    // Top border
    ui_render_rect(ctx, 0, bar_y, f32(screen_width), 1, ctx.style.bg_light)

    // Left padding for mode badge
    badge_margin: f32 = 8
    badge_x := badge_margin
    badge_y := bar_y + 4
    badge_height := bar_height - 8
    badge_padding: f32 = 12

    // Mode badge and status text based on mode
    mode_text: string
    badge_color: [4]u8
    status_text: string

    if is_sketch_mode && sk != nil {
        // Sketch Mode: Cyan badge
        mode_text = "SKETCH MODE"
        badge_color = {0, 150, 180, 255}  // Cyan/Teal

        // Show current tool and stats
        tool_name := ""
        switch sk.current_tool {
        case .Select: tool_name = "Select"
        case .Line: tool_name = "Line"
        case .Circle: tool_name = "Circle"
        case .Arc: tool_name = "Arc"
        case .Dimension: tool_name = "Dimension"
        }

        status_text = fmt.tprintf("Tool: %s  |  Entities: %d  |  Constraints: %d  |  [L] Line [C] Circle [D] Smart Dimension (distance/angular/Ø)",
            tool_name, len(sk.entities), len(sk.constraints))
    } else {
        // Solid Mode: Gray badge
        mode_text = "SOLID MODE"
        badge_color = {80, 85, 90, 255}  // Medium gray

        // Show available operations
        status_text = "[N] New Sketch  |  [E] Extrude  |  [T] Cut  |  [HOME] Reset View  |  [F] Feature Tree"
    }

    // Measure mode text to calculate badge width
    mode_text_width, mode_text_height := ui_measure_text(ctx, mode_text, ctx.style.font_size_small)
    badge_width := mode_text_width + badge_padding * 2

    // Draw mode badge background
    ui_render_rect(ctx, badge_x, badge_y, badge_width, badge_height, badge_color)

    // Draw mode text (centered in badge)
    mode_text_x := badge_x + badge_padding
    mode_text_y := badge_y + (badge_height - mode_text_height) * 0.5
    ui_render_text(ctx, mode_text, mode_text_x, mode_text_y, ctx.style.font_size_small, {255, 255, 255, 255})  // White text

    // Draw separator after mode badge
    separator_x := badge_x + badge_width + 12
    separator_height: f32 = badge_height * 0.6
    separator_y := badge_y + (badge_height - separator_height) * 0.5
    separator_width: f32 = 1
    ui_render_rect(ctx, separator_x, separator_y, separator_width, separator_height, ctx.style.bg_light)

    // Draw status text after separator
    status_x := separator_x + 12
    status_y := bar_y + (bar_height - ctx.style.font_size_small) * 0.5

    // If editing constraint, show instructions instead of normal status
    if editing_constraint_id >= 0 {
        status_text = "[ENTER] Confirm    [ESC] Cancel editing"
    }

    ui_render_text(ctx, status_text, status_x, status_y, ctx.style.font_size_small, ctx.style.text_secondary)

    // Display current unit system on the right side of status bar
    if document_settings != nil {
        unit_text := fmt.tprintf("Units: %s", doc.unit_name(document_settings.units))
        unit_text_width, _ := ui_measure_text(ctx, unit_text, ctx.style.font_size_small)
        unit_x := f32(screen_width) - unit_text_width - 16
        unit_y := status_y
        ui_render_text(ctx, unit_text, unit_x, unit_y, ctx.style.font_size_small, {150, 150, 150, 255})  // Gray text
    }
}

// =============================================================================
// Main CAD UI Layout - Combines all panels
// =============================================================================

ui_cad_layout :: proc(
    ctx: ^UIContext,
    cad_state: ^CADUIState,
    is_sketch_mode: bool,
    sk: ^sketch.Sketch2D,
    feature_tree: ^ftree.FeatureTree,
    extrude_feature_id: int,
    editing_constraint_id: int,  // NEW: Pass editing state
    editing_feature_id: int,     // NEW: ID of feature being edited (-1 if none)
    document_settings: ^doc.DocumentSettings,  // NEW: Pass document settings
    screen_width: u32,
    screen_height: u32,
) -> bool {
    needs_update := false

    // Note: Mode indicator banner removed - status bar at bottom is sufficient
    // ui_mode_indicator_banner function kept in code for future use if needed

    panel_x := f32(screen_width) - cad_state.toolbar_width - 20
    panel_y: f32 = 20  // Standard top margin

    // Draw appropriate toolbar based on mode
    toolbar_height: f32
    if is_sketch_mode && sk != nil {
        // SKETCH MODE: Show sketch tools (Select, Line, Circle, etc.)
        toolbar_height = ui_toolbar_panel(
            ctx,
            cad_state,
            sk,
            panel_x, panel_y,
            cad_state.toolbar_width,
        )
    } else {
        // SOLID MODE: Show solid tools (New Sketch, Extrude, etc.)
        toolbar_height = ui_solid_toolbar_panel(
            ctx,
            cad_state,
            panel_x, panel_y,
            cad_state.toolbar_width,
        )
    }

    // Draw properties panel below toolbar
    properties_y := panel_y + toolbar_height + 20
    properties_height, props_updated := ui_properties_panel(
        ctx,
        cad_state,
        sk,
        feature_tree,
        extrude_feature_id,
        document_settings,  // NEW: Pass document settings
        panel_x, properties_y,
        cad_state.properties_width,
    )

    if props_updated {
        needs_update = true
    }

    // Draw feature tree below properties - NOW returns interaction info
    feature_tree_y := properties_y + properties_height + 20
    feature_tree_height, tree_interaction := ui_feature_tree_panel(
        ctx,
        cad_state,
        feature_tree,
        panel_x, feature_tree_y,
        cad_state.feature_tree_width,
        editing_feature_id,  // NEW: Pass actual editing_feature_id from app state
    )

    // Store feature tree interaction for main app to handle
    // (caller will check ctx.feature_tree_click_id after this function returns)
    ctx.feature_tree_click_id = tree_interaction.clicked_feature_id

    // Store checkmark button click state (reuses double_clicked flag from UI)
    ctx.checkmark_clicked = tree_interaction.double_clicked

    // Draw status bar at bottom
    ui_cad_status_bar(ctx, is_sketch_mode, sk, editing_constraint_id, document_settings, screen_width, screen_height)

    return needs_update
}
