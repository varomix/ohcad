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

    // Extrude depth editing (for properties panel)
    editing_extrude_depth: bool,
    temp_extrude_depth: f32,
}

cad_ui_state_init :: proc() -> CADUIState {
    return CADUIState{
        show_toolbar = true,
        show_properties = true,
        show_feature_tree = true,
        toolbar_width = 250,
        properties_width = 250,
        feature_tree_width = 250,
        editing_extrude_depth = false,
        temp_extrude_depth = 1.0,
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

    // Show selected entity info
    if sk.selected_entity >= 0 && sk.selected_entity < len(sk.entities) {
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
        // No selection - show extrude properties if available
        if extrude_feature_id >= 0 {
            feature := ftree.feature_tree_get_feature(feature_tree, extrude_feature_id)
            if feature != nil {
                params, ok := feature.params.(ftree.ExtrudeParams)
                if ok {
                    ui_text_input(
                        ctx,
                        x + spacing, current_y,
                        width - spacing * 2, widget_height,
                        "FEATURE",
                        "Extrude",
                    )
                    current_y += widget_height + spacing

                    // Editable extrude depth
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
                        feature.params = params
                        ftree.feature_tree_mark_dirty(feature_tree, extrude_feature_id)
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
                }
            }
        } else {
            // Nothing selected
            ui_text_input(
                ctx,
                x + spacing, current_y,
                width - spacing * 2, widget_height,
                "",
                "No selection",
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
        case .Cut, .Revolve, .Fillet, .Chamfer:
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
// Status Bar - Bottom info bar
// =============================================================================

ui_status_bar :: proc(
    ctx: ^UIContext,
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

    // Current tool
    tool_name := ""
    switch sk.current_tool {
    case .Select: tool_name = "Select"
    case .Line: tool_name = "Line"
    case .Circle: tool_name = "Circle"
    case .Arc: tool_name = "Arc"
    case .Dimension: tool_name = "Dimension"
    }

    status_text := fmt.tprintf("Tool: %s  |  Entities: %d  |  Constraints: %d",
        tool_name, len(sk.entities), len(sk.constraints))

    text_x: f32 = 10
    text_y := bar_y + (bar_height - ctx.style.font_size_small) * 0.5
    ui_render_text(ctx, status_text, text_x, text_y, ctx.style.font_size_small, ctx.style.text_secondary)
}

// =============================================================================
// Main CAD UI Layout - Combines all panels
// =============================================================================

ui_cad_layout :: proc(
    ctx: ^UIContext,
    cad_state: ^CADUIState,
    sk: ^sketch.Sketch2D,
    feature_tree: ^ftree.FeatureTree,
    extrude_feature_id: int,
    screen_width: u32,
    screen_height: u32,
) -> bool {
    needs_update := false

    panel_x := f32(screen_width) - cad_state.toolbar_width - 20
    panel_y: f32 = 20

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
    ui_status_bar(ctx, sk, screen_width, screen_height)

    return needs_update
}
