// OhCAD - Real CAD UI Panels and Layout
package widgets

import "core:fmt"
import "core:math"
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
// Properties Panel - Selected Entity Info
// =============================================================================

ui_properties_panel :: proc(
    ctx: ^UIContext,
    cad_state: ^CADUIState,
    sk: ^sketch.Sketch2D,
    feature_tree: ^ftree.FeatureTree,
    extrude_feature_id: int,
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
    if sk != nil && sk.selected_entity >= 0 && sk.selected_entity < len(sk.entities) {
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
    } else {
        // No selection - show most recent feature properties
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
// Feature Tree Panel - Parametric History
// =============================================================================

ui_feature_tree_panel :: proc(
    ctx: ^UIContext,
    cad_state: ^CADUIState,
    feature_tree: ^ftree.FeatureTree,
    x, y, width: f32,
) -> f32 {
    if !cad_state.show_feature_tree do return 0

    current_y := y
    spacing: f32 = 10
    item_height: f32 = 28

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

        // Draw feature item as a button-like widget
        is_hot := ui_point_in_rect(ctx.mouse_x, ctx.mouse_y, x + spacing, current_y, width - spacing * 2, item_height)

        if is_hot {
            ctx.mouse_over_ui = true
        }

        bg_color := is_hot ? ctx.style.bg_medium : ctx.style.bg_dark
        ui_render_rect(ctx, x + spacing, current_y, width - spacing * 2, item_height, bg_color)

        // Border
        border_color := ctx.style.bg_light
        border_width: f32 = 1.0
        ui_render_rect(ctx, x + spacing, current_y, width - spacing * 2, border_width, border_color)
        ui_render_rect(ctx, x + spacing, current_y + item_height - border_width, width - spacing * 2, border_width, border_color)
        ui_render_rect(ctx, x + spacing, current_y, border_width, item_height, border_color)
        ui_render_rect(ctx, x + spacing + width - spacing * 2 - border_width, current_y, border_width, item_height, border_color)

        // Icon
        icon_size: f32 = 24
        icon_x := x + spacing + 4
        icon_y := current_y + (item_height - icon_size) * 0.5

        ui_render_rect(ctx, icon_x, icon_y, icon_size, icon_size, ctx.style.bg_medium)

        // Icon text
        icon_text_width, icon_text_height := ui_measure_text(ctx, icon_text, ctx.style.font_size_small)
        icon_text_x := icon_x + (icon_size - icon_text_width) * 0.5
        icon_text_y := icon_y + (icon_size - icon_text_height) * 0.5
        ui_render_text(ctx, icon_text, icon_text_x, icon_text_y, ctx.style.font_size_small, icon_color)

        // Feature name
        name_x := icon_x + icon_size + 8
        name_y := current_y + (item_height - ctx.style.font_size_small) * 0.5
        ui_render_text(ctx, feature.name, name_x, name_y, ctx.style.font_size_small, ctx.style.text_primary)

        // Visibility toggle (small indicator)
        if feature.visible {
            vis_size: f32 = 8
            vis_x := x + width - spacing - vis_size - 8
            vis_y := current_y + (item_height - vis_size) * 0.5
            ui_render_rect(ctx, vis_x, vis_y, vis_size, vis_size, {0, 255, 100, 255})
        }

        current_y += item_height + 4
    }

    return current_y - y  // Return total height used
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

ui_status_bar :: proc(
    ctx: ^UIContext,
    is_sketch_mode: bool,
    sk: ^sketch.Sketch2D,
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

        status_text = fmt.tprintf("Tool: %s  |  Entities: %d  |  Constraints: %d  |  [L] Line [C] Circle [H] Horizontal [V] Vertical",
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
    ui_render_text(ctx, status_text, status_x, status_y, ctx.style.font_size_small, ctx.style.text_secondary)
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
    screen_width: u32,
    screen_height: u32,
) -> bool {
    needs_update := false

    // Note: Mode indicator banner removed - status bar at bottom is sufficient
    // ui_mode_indicator_banner function kept in code for future use if needed

    panel_x := f32(screen_width) - cad_state.toolbar_width - 20
    panel_y: f32 = 20  // Standard top margin

    // Draw toolbar
    toolbar_height := ui_toolbar_panel(
        ctx,
        cad_state,
        sk,
        panel_x, panel_y,
        cad_state.toolbar_width,
    )

    // Draw properties panel below toolbar
    properties_y := panel_y + toolbar_height + 20
    properties_height, props_updated := ui_properties_panel(
        ctx,
        cad_state,
        sk,
        feature_tree,
        extrude_feature_id,
        panel_x, properties_y,
        cad_state.properties_width,
    )

    if props_updated {
        needs_update = true
    }

    // Draw feature tree below properties
    feature_tree_y := properties_y + properties_height + 20
    _ = ui_feature_tree_panel(
        ctx,
        cad_state,
        feature_tree,
        panel_x, feature_tree_y,
        cad_state.feature_tree_width,
    )

    // Draw status bar at bottom
    ui_status_bar(ctx, is_sketch_mode, sk, screen_width, screen_height)

    return needs_update
}
