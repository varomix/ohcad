// OhCAD Interactive Sketcher Application (SDL3 GPU Version)
package main

import "base:runtime"


import cmd "core/command" // NEW: For f64 parsing
import doc "core/document"
import m "core/math"
import "core:fmt"
import "core:math"
import glsl "core:math/linalg/glsl"
import "core:os"
import "core:strconv"
import cut "features/cut"
import extrude "features/extrude"
import ftree "features/feature_tree"
import revolve "features/revolve"
import sketch "features/sketch"
import stl "io/stl"
import v "ui/viewer"
import ui "ui/widgets"
import sdl "vendor:sdl3"

// Constants
DOUBLE_CLICK_THRESHOLD :: 0.5 // 500ms for double-click detection

// Application modes
ApplicationMode :: enum {
	Solid, // 3D modeling mode (default) - select faces, extrude, cut
	Sketch, // 2D sketching mode - draw lines, circles, constrain
}

// Sketch plane types for creation
SketchPlaneType :: enum {
	XY, // Front view (Z up)
	YZ, // Right view (X forward)
	ZX, // Top view (Y up)
	Face, // On a selected face
}

// Face selection (for sketch-on-face)
SelectedFace :: struct {
	feature_id: int, // ID of the feature containing the solid
	face_index: int, // Index of the face within the solid
}

// Application state
AppStateGPU :: struct {
	viewer:                     ^v.ViewerGPU,
	text_renderer:              v.TextRendererGPU,
	ui_context:                 ui.UIContext, // UI framework context
	cad_ui_state:               ui.CADUIState, // CAD-specific UI state
	document_settings:          doc.DocumentSettings, // Document settings (units, precision, etc.)

	// DEPRECATED: Will be removed - use get_active_sketch() instead
	_sketch:                    ^sketch.Sketch2D,
	wireframe:                  v.WireframeMeshGPU,
	wireframe_selected:         v.WireframeMeshGPU,

	// NEW: Modal system
	mode:                       ApplicationMode, // Current mode (Solid or Sketch)
	active_sketch_id:           int, // ID of sketch being edited (-1 if none)
	selected_sketch_id:         int, // ID of sketch selected for operations (extrude/cut) (-1 if none)

	// NEW: Face selection (for sketch-on-face)
	selected_face:              Maybe(SelectedFace), // Currently selected face (-1 if none)

	// Feature tree (parametric system)
	feature_tree:               ftree.FeatureTree,
	sketch_feature_id:          int, // DEPRECATED: Will be removed
	extrude_feature_id:         int,
	cut_feature_id:             int,

	// Wireframe cache for all solids
	solid_wireframes:           [dynamic]v.WireframeMeshGPU,

	// Update flags
	needs_wireframe_update:     bool,
	needs_selection_update:     bool,
	needs_solid_update:         bool,

	// Status message (for status bar feedback)
	status_message:             string,

	// Input state for sketch interaction
	mouse_x:                    f64,
	mouse_y:                    f64,
	mouse_down_left:            bool, // Track left mouse button separately
	ctrl_held:                  bool,

	// Hover state for sketch entities
	hover_state:                sketch.HoverState,

	// Sketch visualization settings
	show_profile_fill:          bool, // Toggle for closed shape visualization

	// Command history (undo/redo system)
	command_history:            cmd.CommandHistory,
	shift_held:                 bool, // Track shift key for Ctrl+Shift+Z

	// Double-click detection for dimension editing
	last_click_time:            f64,
	last_click_constraint_id:   int,

	// Dimension value editing (using widget)
	editing_constraint_id:      int, // -1 if not editing, constraint ID if editing
	text_input_widget:          ui.TextInputWidget, // Reusable text input widget

	// Point dragging state (Week 12.3 - Task 1)
	dragging_point:             bool, // True if currently dragging a point
	dragging_point_id:          int, // ID of point being dragged (-1 if none)
	drag_start_pos:             m.Vec2, // Original position when drag started (for ghost preview)
	drag_snap_to_grid:          bool, // Enable grid snapping during drag

	// Circle radius editing state (Week 12.3 - Task 2)
	dragging_radius:            bool, // True if currently dragging a circle radius handle
	dragging_circle_id:         int, // Index of circle being resized (-1 if none)
	drag_start_radius:          f64, // Original radius when drag started

	// Dimension dragging state (Week 12.3 - Exercise 1)
	dragging_dimension:         bool, // True if currently dragging a dimension to reposition it
	dragging_dimension_constraint_id: int, // ID of constraint being repositioned (-1 if none)
	dimension_drag_pending:     bool, // True if mouse down on dimension but not yet dragging (wait for movement)
	dimension_drag_start_pos:   m.Vec2, // Position where mouse button was pressed (for drag threshold)

	// Feature tree editing state (Week 12.36)
	editing_feature_id:         int, // ID of feature being edited (-1 if none)
	last_tree_click_time:       f64, // Time of last feature tree click (for double-click detection)
	last_tree_click_feature_id: int, // Feature ID of last feature tree click (-1 if none)
}

// Apply horizontal constraint to selected line
apply_horizontal_constraint :: proc(app: ^AppStateGPU) {
	active_sketch := get_active_sketch(app)
	if active_sketch == nil {
		fmt.println("❌ No active sketch")
		return
	}

	if active_sketch.selected_entity < 0 {
		fmt.println("❌ No entity selected - select a line first")
		return
	}

	entity := active_sketch.entities[active_sketch.selected_entity]

	_, is_line := entity.(sketch.SketchLine)
	if !is_line {
		fmt.println("❌ Selected entity is not a line - horizontal constraint requires a line")
		return
	}

	sketch.sketch_add_constraint(
		active_sketch,
		.Horizontal,
		sketch.HorizontalData{line_id = active_sketch.selected_entity},
	)

	fmt.printf("✅ Horizontal constraint added to line %d\n", active_sketch.selected_entity)
}

// Apply vertical constraint to selected line
apply_vertical_constraint :: proc(app: ^AppStateGPU) {
	active_sketch := get_active_sketch(app)
	if active_sketch == nil {
		fmt.println("❌ No active sketch")
		return
	}

	if active_sketch.selected_entity < 0 {
		fmt.println("❌ No entity selected - select a line first")
		return
	}

	entity := active_sketch.entities[active_sketch.selected_entity]

	_, is_line := entity.(sketch.SketchLine)
	if !is_line {
		fmt.println("❌ Selected entity is not a line - vertical constraint requires a line")
		return
	}

	sketch.sketch_add_constraint(
		active_sketch,
		.Vertical,
		sketch.VerticalData{line_id = active_sketch.selected_entity},
	)

	fmt.printf("✅ Vertical constraint added to line %d\n", active_sketch.selected_entity)
}

// Solve all constraints
solve_constraints :: proc(app: ^AppStateGPU) {
	active_sketch := get_active_sketch(app)
	if active_sketch == nil {
		fmt.println("❌ No active sketch")
		return
	}

	fmt.println("\n=== Running Constraint Solver ===")

	result := sketch.sketch_solve_constraints(active_sketch)
	sketch.solver_result_print(result)

	if result.status == .Success {
		fmt.println("✅ Constraints solved! Geometry updated.")
		app.needs_wireframe_update = true
		app.needs_selection_update = true
	} else if result.status == .Underconstrained {
		fmt.println("⚠️  Sketch needs more constraints to be fully defined")
	} else if result.status == .Overconstrained {
		fmt.println("❌ Sketch has conflicting constraints")
	} else if result.status == .MaxIterations {
		fmt.println("⚠️  Solver reached maximum iterations without converging")
	} else if result.status == .MaxIterations {
		fmt.println("❌ Numerical error during solving")
	}
}

main :: proc() {
	fmt.println("=== OhCAD Interactive Sketcher (SDL3 GPU) ===")

	// Initialize SDL3 GPU viewer
	viewer_inst, ok := v.viewer_gpu_init()
	if !ok {
		fmt.eprintln("Failed to initialize SDL3 GPU viewer")
		return
	}
	defer v.viewer_gpu_destroy(viewer_inst)

	// Load shader data for text renderer
	shader_data, shader_ok := read_entire_file_or_exit(
		"src/ui/viewer/shaders/line_shader.metallib",
	)
	if !shader_ok {
		return
	}
	defer delete(shader_data)

	// Initialize text renderer
	text_renderer, text_ok := v.text_renderer_gpu_init(
		viewer_inst.gpu_device,
		viewer_inst.window,
		shader_data,
	)
	if !text_ok {
		fmt.eprintln("Failed to initialize text renderer")
		return
	}
	defer v.text_renderer_gpu_destroy(&text_renderer)

	// Initialize feature tree (empty - no initial sketch)
	feature_tree := ftree.feature_tree_init()
	defer ftree.feature_tree_destroy(&feature_tree)

	// Empty wireframes (will be created when user creates first sketch)
	wireframe := v.WireframeMeshGPU{}
	defer v.wireframe_mesh_gpu_destroy(&wireframe)

	wireframe_selected := v.WireframeMeshGPU{}
	defer v.wireframe_mesh_gpu_destroy(&wireframe_selected)

	// Create app state
	app := new(AppStateGPU)
	app.viewer = viewer_inst
	app.text_renderer = text_renderer
	app.ui_context = ui.ui_context_init(viewer_inst, &text_renderer)
	app.cad_ui_state = ui.cad_ui_state_init()
	app.document_settings = doc.document_settings_default() // Initialize document settings
	app._sketch = nil // No global sketch anymore
	app.wireframe = wireframe
	app.wireframe_selected = wireframe_selected

	// NEW: Start in Solid mode with no active sketch (proper CAD workflow)
	app.mode = .Solid
	app.active_sketch_id = -1 // No active sketch
	app.selected_sketch_id = -1 // No selected sketch

	// Enable profile fill visualization by default
	app.show_profile_fill = true

	// Initialize command history (undo/redo system)
	app.command_history = cmd.command_history_init(50) // Max 50 commands
	defer cmd.command_history_destroy(&app.command_history)

	// Initialize double-click and editing state (CRITICAL: must be -1 to indicate "not editing")
	app.last_click_constraint_id = -1
	app.editing_constraint_id = -1

	// Initialize point dragging state (Week 12.3 - Task 1)
	app.dragging_point = false
	app.dragging_point_id = -1
	app.drag_start_pos = m.Vec2{0, 0}
	app.drag_snap_to_grid = true // Enable grid snapping by default

	// Initialize circle radius dragging state (Week 12.3 - Task 2)
	app.dragging_radius = false
	app.dragging_circle_id = -1
	app.drag_start_radius = 0.0

	app.feature_tree = feature_tree
	app.sketch_feature_id = -1 // No sketch
	app.extrude_feature_id = -1
	app.cut_feature_id = -1
	app.solid_wireframes = make([dynamic]v.WireframeMeshGPU)
	app.needs_wireframe_update = false
	app.needs_selection_update = false

	defer {
		for &mesh in app.solid_wireframes {
			v.wireframe_mesh_gpu_destroy(&mesh)
		}
		delete(app.solid_wireframes)
		free(app)
	}

	fmt.println("\n🎉 Welcome to OhCAD!")
	fmt.println("Starting in SOLID MODE (empty scene)")
	fmt.println("Press [1]/[2]/[3] to create a new sketch on XY/YZ/XZ plane")

	fmt.println("\nControls:")
	fmt.println("=== Solid Mode (3D) ===")
	fmt.println("  [N] New sketch (show plane selector)")
	fmt.println("  [1] New sketch on XY plane")
	fmt.println("  [2] New sketch on YZ plane")
	fmt.println("  [3] New sketch on ZX plane")
	fmt.println("  [E] Extrude sketch")
	fmt.println("  [O] Revolve sketch")
	fmt.println("  [T] Cut/Pocket from sketch")
	fmt.println("  [+]/[-] Change extrude/revolve depth/angle")
	fmt.println("")
	fmt.println("=== Sketch Mode (2D) ===")
	fmt.println("  [ESC] Exit sketch mode")
	fmt.println("  [S] Select tool")
	fmt.println("  [L] Line tool")
	fmt.println("  [C] Circle tool")
	fmt.println("  [D] Dimension tool")
	fmt.println("  [H] Horizontal constraint")
	fmt.println("  [V] Vertical constraint")
	fmt.println("  [X] Solve constraints")
	fmt.println("  [P] Print profile detection")
	fmt.println("  [DELETE] Delete selected")
	fmt.println("")
	fmt.println("=== Global ===")
	fmt.println("  [Ctrl+Shift+E] Export to STL")
	fmt.println("  [Ctrl+Z] Undo")
	fmt.println("  [Ctrl+Shift+Z] / [Ctrl+Y] Redo")
	fmt.println("  [R] Regenerate all features")
	fmt.println("  [F] Print feature tree")
	fmt.println("  [W] Wireframe mode / [Shift+W] Shaded mode")
	fmt.println("  [HOME] Reset camera")
	fmt.println("  [Q] Quit\n")

	// Main render loop
	for v.viewer_gpu_should_continue(viewer_inst) {
		// Poll events and handle input
		handle_events_gpu(app)

		// Update wireframe if needed (use active sketch)
		active_sketch := get_active_sketch(app)
		if app.needs_wireframe_update && active_sketch != nil {
			v.wireframe_mesh_gpu_destroy(&app.wireframe)
			app.wireframe = v.sketch_to_wireframe_gpu(active_sketch)
			app.needs_wireframe_update = false
		}

		// Update selection wireframe if needed (use active sketch)
		if app.needs_selection_update && active_sketch != nil {
			v.wireframe_mesh_gpu_destroy(&app.wireframe_selected)
			app.wireframe_selected = v.sketch_to_wireframe_selected_gpu(active_sketch)
			app.needs_selection_update = false
		}

		// Render frame
		render_frame_gpu(app)
	}

	fmt.println("Viewer closed successfully")
}

// Handle SDL3 events
handle_events_gpu :: proc(app: ^AppStateGPU) {
	event: sdl.Event

	for sdl.PollEvent(&event) {
		#partial switch event.type {
		case .QUIT:
			app.viewer.should_close = true

		case .KEY_DOWN:
			// Special handling for text editing mode
			if app.editing_constraint_id >= 0 {
				if event.key.key == sdl.K_RETURN || event.key.key == sdl.K_KP_ENTER {
					// ENTER: Commit the edit
					stop_constraint_editing(app, true)
					return
				} else if event.key.key == sdl.K_ESCAPE {
					// ESC: Cancel the edit
					stop_constraint_editing(app, false)
					return
				} else if event.key.key == sdl.K_BACKSPACE {
					// Backspace: Delete character using widget
					ui.text_input_widget_handle_backspace(&app.text_input_widget)
					return
				} else if event.key.key == sdl.K_LEFT ||
				   event.key.key == sdl.K_RIGHT ||
				   event.key.key == sdl.K_HOME ||
				   event.key.key == sdl.K_END {
					// Arrow keys: Move cursor or deselect text using widget
					ui.text_input_widget_handle_arrow(&app.text_input_widget, event.key.key)
					return
				}
				// Let other keys fall through to TEXT_INPUT handler
				return
			}

			// Normal key handling (not in text edit mode)
			handle_key_down_gpu(app, event.key.key, event.key.mod)

		case .TEXT_INPUT:
			// Handle text input during constraint editing
			if app.editing_constraint_id >= 0 {
				// SDL TEXT_INPUT event text field is a cstring
				text_cstr := event.text.text

				// Convert cstring to string
				text_str := string(text_cstr)

				// Process each character using widget
				for ch in text_str {
					ui.text_input_widget_handle_char(&app.text_input_widget, ch)
				}
			}

		case .KEY_UP:
			handle_key_up_gpu(app, event.key.key, event.key.mod)

		case .MOUSE_MOTION:
			app.mouse_x = f64(event.motion.x)
			app.mouse_y = f64(event.motion.y)

			// Update cursor preview and hover state (use active sketch)
			active_sketch := get_active_sketch(app)
			if active_sketch != nil {
				sketch_pos, ok := screen_to_sketch_gpu(
					app,
					app.mouse_x,
					app.mouse_y,
					active_sketch,
				)
				if ok {
					world_pos := sketch.sketch_to_world(&active_sketch.plane, sketch_pos)
					sketch.sketch_update_cursor(active_sketch, world_pos)

					// RADIUS DRAGGING: If dragging a circle radius handle, update radius
					if app.dragging_radius && app.dragging_circle_id >= 0 {
						if app.dragging_circle_id < len(active_sketch.entities) {
							if circle, ok_circle := &active_sketch.entities[app.dragging_circle_id].(sketch.SketchCircle);
							   ok_circle {
								// Calculate center point
								center_pt := sketch.sketch_get_point(
									active_sketch,
									circle.center_id,
								)
								if center_pt != nil {
									center_pos := m.Vec2{center_pt.x, center_pt.y}

									// Calculate new radius from center to cursor
									new_radius := glsl.length(sketch_pos - center_pos)

									// Apply grid snapping to radius if Ctrl is held
									if app.ctrl_held {
										GRID_SIZE :: 0.1
										new_radius = math.round(new_radius / GRID_SIZE) * GRID_SIZE
									}

									// Update circle radius (minimum 0.1)
									if new_radius >= 0.1 {
										circle.radius = new_radius

										// Mark sketch for update
										app.needs_wireframe_update = true
										app.needs_selection_update = true
									}
								}
							}
						}
					} else if app.dragging_point && app.dragging_point_id >= 0 {
						// POINT DRAGGING: If dragging a point, update its position
						point := sketch.sketch_get_point(active_sketch, app.dragging_point_id)
						if point != nil && !point.fixed {
							// Apply grid snapping only when Ctrl is held
							new_pos := sketch_pos
							if app.ctrl_held {
								GRID_SIZE :: 0.1
								new_pos.x = math.round(new_pos.x / GRID_SIZE) * GRID_SIZE
								new_pos.y = math.round(new_pos.y / GRID_SIZE) * GRID_SIZE
							}

							// Update point position
							point.x = new_pos.x
							point.y = new_pos.y

							// Mark sketch for update
							app.needs_wireframe_update = true
							app.needs_selection_update = true
						}
					} else if app.dragging_dimension && app.dragging_dimension_constraint_id >= 0 {
						// DIMENSION DRAGGING: If dragging a dimension, update its offset
						sketch.sketch_update_drag_dimension(active_sketch, sketch_pos)

						// Mark sketch for update
						app.needs_wireframe_update = true
					} else if app.dimension_drag_pending && app.dragging_dimension_constraint_id >= 0 {
						// DIMENSION DRAG PENDING: Check if mouse moved beyond threshold to start actual drag
						DRAG_THRESHOLD :: 0.05 // Minimum distance to start drag (in sketch units)
						delta := glsl.length(sketch_pos - app.dimension_drag_start_pos)

						if delta >= DRAG_THRESHOLD {
							// Start actual drag
							app.dimension_drag_pending = false
							app.dragging_dimension = true
							sketch.sketch_start_drag_dimension(
								active_sketch,
								app.dragging_dimension_constraint_id,
								app.dimension_drag_start_pos,
							)
							fmt.printf(
								"🖱️  Drag threshold exceeded (%.3f) - started dragging constraint #%d\n",
								delta,
								app.dragging_dimension_constraint_id,
							)
						}
					} else {
						// Update hover state for sketch entities (only when not dragging)
						app.hover_state = sketch.sketch_update_hover(active_sketch, sketch_pos)
					}
				}
			}

			// Handle camera movement via viewer (only when not dragging)
			if !app.dragging_point && !app.dragging_radius {
				v.viewer_gpu_handle_mouse_motion(app.viewer, &event.motion)
			}

		case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP:
			// Track left button state for UI
			if event.button.button == u8(sdl.BUTTON_LEFT) {
				app.mouse_down_left = event.button.down

				// RADIUS DRAGGING: Finish drag on mouse button up
				if !event.button.down && app.dragging_radius {
					active_sketch := get_active_sketch(app)
					if active_sketch != nil && app.dragging_circle_id >= 0 {
						if app.dragging_circle_id < len(active_sketch.entities) {
							if circle, ok_circle := active_sketch.entities[app.dragging_circle_id].(sketch.SketchCircle);
							   ok_circle {
								fmt.printf(
									"🏁 Finished dragging radius for circle #%d (new radius: %.2f)\n",
									app.dragging_circle_id,
									circle.radius,
								)

								// Check if there are constraints - if so, run the solver
								// Note: Radius constraints might need updating
								if len(active_sketch.constraints) > 0 {
									fmt.println(
										"🔄 Re-solving constraints after radius change...",
									)
									result := sketch.sketch_solve_constraints(active_sketch)
									if result.status == .Success {
										fmt.println("✅ Constraints solved!")
									} else {
										fmt.println(
											"⚠️  Constraint solving status:",
											result.status,
										)
									}
								}
							}
						}
					}

					// Reset dragging state
					app.dragging_radius = false
					app.dragging_circle_id = -1
					app.needs_wireframe_update = true
					app.needs_selection_update = true
				}

				// POINT DRAGGING: Finish drag on mouse button up
				if !event.button.down && app.dragging_point {
					active_sketch := get_active_sketch(app)
					if active_sketch != nil && app.dragging_point_id >= 0 {
						point := sketch.sketch_get_point(active_sketch, app.dragging_point_id)
						if point != nil {
							fmt.printf(
								"🏁 Finished dragging point #%d (new pos: %.2f, %.2f)\n",
								point.id,
								point.x,
								point.y,
							)

							// Check if there are constraints - if so, run the solver
							if len(active_sketch.constraints) > 0 {
								fmt.println("🔄 Re-solving constraints after point move...")
								result := sketch.sketch_solve_constraints(active_sketch)
								if result.status == .Success {
									fmt.println("✅ Constraints solved!")
								} else {
									fmt.println(
										"⚠️  Constraint solving status:",
										result.status,
									)
								}
							}
						}
					}

					// Reset dragging state
					app.dragging_point = false
					app.dragging_point_id = -1
					app.needs_wireframe_update = true
					app.needs_selection_update = true
				}

				// DIMENSION DRAGGING: Finish drag on mouse button up
				if !event.button.down && app.dragging_dimension {
					active_sketch := get_active_sketch(app)
					if active_sketch != nil {
						sketch.sketch_stop_drag_dimension(active_sketch)
					}

					// Reset dragging state
					app.dragging_dimension = false
					app.dragging_dimension_constraint_id = -1
					app.needs_wireframe_update = true
				}

				// DIMENSION DRAG PENDING: Cancel pending drag on mouse button up (if didn't move enough)
				if !event.button.down && app.dimension_drag_pending {
					// Click without drag - reset pending state
					app.dimension_drag_pending = false
					app.dragging_dimension_constraint_id = -1
				}
			}

			handle_mouse_button_gpu(app, &event.button)
			v.viewer_gpu_handle_mouse_button(app.viewer, &event.button)

		case .MOUSE_WHEEL:
			v.viewer_gpu_handle_mouse_wheel(app.viewer, &event.wheel)

		case .FINGER_DOWN, .FINGER_UP, .FINGER_MOTION:
			v.viewer_gpu_handle_finger(app.viewer, &event)
		}
	}
}

// Handle key down events (mode-independent and routing)
handle_key_down_gpu :: proc(app: ^AppStateGPU, key: sdl.Keycode, mods: sdl.Keymod) {
	// Track modifiers
	if key == sdl.K_LCTRL || key == sdl.K_RCTRL {
		app.ctrl_held = true
	}
	if key == sdl.K_LSHIFT || key == sdl.K_RSHIFT {
		app.shift_held = true
	}

	// Undo/Redo shortcuts (global - available in any mode)
	if app.ctrl_held && key == sdl.K_Z {
		if app.shift_held {
			// Ctrl+Shift+Z = Redo
			if cmd.command_history_redo(&app.command_history) {
				// Trigger updates based on what was redone
				app.needs_wireframe_update = true
				app.needs_selection_update = true
				app.needs_solid_update = true
				update_solid_wireframes_gpu(app)
			}
		} else {
			// Ctrl+Z = Undo
			if cmd.command_history_undo(&app.command_history) {
				// Trigger updates based on what was undone
				app.needs_wireframe_update = true
				app.needs_selection_update = true
				app.needs_solid_update = true
				update_solid_wireframes_gpu(app)
			}
		}
		return
	}

	// Ctrl+Y = Redo (alternative shortcut)
	if app.ctrl_held && key == sdl.K_Y {
		if cmd.command_history_redo(&app.command_history) {
			app.needs_wireframe_update = true
			app.needs_selection_update = true
			app.needs_solid_update = true
			update_solid_wireframes_gpu(app)
		}
		return
	}

	// STL EXPORT: [Ctrl+Shift+E] Export all solids to STL
	if app.ctrl_held && app.shift_held && key == sdl.K_E {
		export_to_stl_gpu(app)
		return
	}

	// TEST COMMAND: [Ctrl+T] Add a test line command to verify undo/redo works
	if app.ctrl_held && key == sdl.K_T {
		active_sketch := get_active_sketch(app)
		if active_sketch != nil {
			// Create a simple test line command
			test_cmd := cmd.AddLineCommand {
				sketch_ref   = active_sketch,
				start_id     = 0, // Assume we have at least 2 points
				end_id       = 1,
				line_id      = -1, // Will be set during execute
				entity_index = -1,
			}

			if cmd.command_history_execute(&app.command_history, test_cmd) {
				app.needs_wireframe_update = true
				app.needs_selection_update = true
				fmt.println("🧪 TEST: Added line command (use Ctrl+Z to undo)")
			}
		} else {
			fmt.println("❌ No active sketch for test command")
		}
		return
	}

	// Global shortcuts (available in any mode)
	switch key {
	case sdl.K_Q:
		app.viewer.should_close = true
		return

	case sdl.K_HOME:
		v.camera_init(&app.viewer.camera, app.viewer.camera.aspect_ratio)
		fmt.println("🏠 Camera reset")
		return

	case sdl.K_W:
		// Toggle render mode: W (no shift) = wireframe, Shift+W = shaded
		if .LSHIFT in mods || .RSHIFT in mods {
			// Shift+W: Toggle to shaded mode
			app.viewer.render_mode = .Shaded
			fmt.println("🎨 Switched to SHADED rendering mode")
		} else {
			// W: Toggle to wireframe mode
			app.viewer.render_mode = .Wireframe
			fmt.println("📐 Switched to WIREFRAME rendering mode")
		}
		return

	case sdl.K_F:
		ftree.feature_tree_print(&app.feature_tree)
		return

	case sdl.K_R:
		ftree.feature_tree_regenerate_all(&app.feature_tree)
		update_solid_wireframes_gpu(app)
		fmt.println("🔄 Regenerated all features")
		return

	case sdl.K_G:
		// Toggle profile fill visualization in sketch mode
		if app.mode == .Sketch {
			app.show_profile_fill = !app.show_profile_fill
			if app.show_profile_fill {
				fmt.println("✅ Profile fill visualization: ON")
			} else {
				fmt.println("⭕ Profile fill visualization: OFF")
			}
			return
		}

		// In Solid mode, [G] is for face selection test (existing functionality)
		for feature in app.feature_tree.features {
			if feature.result_solid != nil && len(feature.result_solid.faces) > 0 {
				app.selected_face = SelectedFace {
					feature_id = feature.id,
					face_index = 0, // Select first face
				}
				fmt.printf(
					"🧪 TEST: Selected face 0 of feature %d ('%s')\n",
					feature.id,
					feature.result_solid.faces[0].name,
				)
				return
			}
		}
		fmt.println("❌ No faces available for testing")
		return
	}

	// Mode-specific shortcuts
	switch app.mode {
	case .Solid:
		handle_solid_mode_keys(app, key, mods)
	case .Sketch:
		handle_sketch_mode_keys(app, key, mods)
	}
}

// Handle Solid Mode keyboard shortcuts
handle_solid_mode_keys :: proc(app: ^AppStateGPU, key: sdl.Keycode, mods: sdl.Keymod) {
	switch key {
	case sdl.K_ESCAPE:
		fmt.println("Already in SOLID MODE")

	case sdl.K_N:
		// Check if a face is selected - if so, create sketch on that face
		if _, has_selection := app.selected_face.?; has_selection {
			create_sketch_on_plane(app, .Face) // This will call create_sketch_on_face()
			app.needs_wireframe_update = true
		} else {
			// No face selected - show plane selection menu
			fmt.println("\n=== NEW SKETCH ===")
			fmt.println("Select plane:")
			fmt.println("  [1] XY plane (Front)")
			fmt.println("  [2] YZ plane (Right)")
			fmt.println("  [3] ZX plane (Top)")
		}

	case sdl.K_1:
		create_sketch_on_plane(app, .XY)
		app.needs_wireframe_update = true

	case sdl.K_2:
		create_sketch_on_plane(app, .YZ)
		app.needs_wireframe_update = true

	case sdl.K_3:
		create_sketch_on_plane(app, .ZX)
		app.needs_wireframe_update = true

	case sdl.K_E:
		test_extrude_gpu(app)

	case sdl.K_O:
		test_revolve_gpu(app)

	case sdl.K_T:
		test_cut_gpu(app)

	case sdl.K_EQUALS, sdl.K_KP_PLUS:
		change_active_feature_parameter(app, 0.1)

	case sdl.K_MINUS, sdl.K_KP_MINUS:
		change_active_feature_parameter(app, -0.1)

	case:
		// Tool shortcuts are not available in Solid mode
		if key == sdl.K_L ||
		   key == sdl.K_C ||
		   key == sdl.K_D ||
		   key == sdl.K_S ||
		   key == sdl.K_H ||
		   key == sdl.K_V ||
		   key == sdl.K_X ||
		   key == sdl.K_P {
			fmt.println("⚠️  Sketch tools not available - Create/enter a sketch first")
		}
	}
}

// Handle Sketch Mode keyboard shortcuts
handle_sketch_mode_keys :: proc(app: ^AppStateGPU, key: sdl.Keycode, mods: sdl.Keymod) {
	active_sketch := get_active_sketch(app)
	if active_sketch == nil {
		fmt.println("❌ Error: No active sketch in Sketch mode!")
		return
	}

	switch key {
	case sdl.K_ESCAPE:
		// ESC now only cancels current tool and returns to Select tool
		// (User must click the checkmark button in feature tree to finish sketch)
		if active_sketch.current_tool != .Select {
			sketch.sketch_set_tool(active_sketch, .Select)
			fmt.println("🔧 Tool cancelled → Select tool")
		} else {
			fmt.println(
				"ℹ️  Already in Select tool (click ✓ button in History panel to finish sketch)",
			)
		}

	case sdl.K_S:
		sketch.sketch_set_tool(active_sketch, .Select)
		fmt.println("🔧 Tool: Select")

	case sdl.K_L:
		sketch.sketch_set_tool(active_sketch, .Line)
		fmt.println("🔧 Tool: Line")

	case sdl.K_C:
		sketch.sketch_set_tool(active_sketch, .Circle)
		fmt.println("🔧 Tool: Circle")

	case sdl.K_D:
		sketch.sketch_set_tool(active_sketch, .Dimension)
		fmt.println("🔧 Tool: Dimension (smart: distance/angular/diameter)")

	case sdl.K_H:
		apply_horizontal_constraint(app)

	case sdl.K_V:
		apply_vertical_constraint(app)

	case sdl.K_TAB:
		// Cycle through constraints for selection
		if len(active_sketch.constraints) > 0 {
			if active_sketch.selected_constraint_id == -1 {
				// No constraint selected - select first one
				sketch.sketch_select_constraint(active_sketch, active_sketch.constraints[0].id)
				app.cad_ui_state.temp_constraint_value = 0 // Reset temp value
				fmt.printf("📐 Selected constraint #%d\n", active_sketch.constraints[0].id)
			} else {
				// Find currently selected constraint index
				current_idx := -1
				for c, i in active_sketch.constraints {
					if c.id == active_sketch.selected_constraint_id {
						current_idx = i
						break
					}
				}

				if current_idx >= 0 {
					// Move to next constraint (wrap around)
					next_idx := (current_idx + 1) % len(active_sketch.constraints)
					sketch.sketch_select_constraint(
						active_sketch,
						active_sketch.constraints[next_idx].id,
					)
					app.cad_ui_state.temp_constraint_value = 0 // Reset temp value
					fmt.printf(
						"📐 Selected constraint #%d\n",
						active_sketch.constraints[next_idx].id,
					)
				} else {
					// Current selection not found - select first one
					sketch.sketch_select_constraint(active_sketch, active_sketch.constraints[0].id)
					app.cad_ui_state.temp_constraint_value = 0
					fmt.printf("📐 Selected constraint #%d\n", active_sketch.constraints[0].id)
				}
			}

			// Deselect entity when selecting constraint
			active_sketch.selected_entity = -1
		} else {
			fmt.println("ℹ️  No constraints to select")
		}

	case sdl.K_X:
		solve_constraints(app)

	case sdl.K_P:
		sketch.sketch_print_profiles(active_sketch)

	case sdl.K_DELETE, sdl.K_BACKSPACE:
		if sketch.sketch_delete_selected(active_sketch) {
			app.needs_wireframe_update = true
			app.needs_selection_update = true
			fmt.println("🗑️  Deleted selected entity")
		}

	case:
		// Solid mode tools are not available in Sketch mode
		if key == sdl.K_E ||
		   key == sdl.K_T ||
		   key == sdl.K_EQUALS ||
		   key == sdl.K_KP_PLUS ||
		   key == sdl.K_MINUS ||
		   key == sdl.K_KP_MINUS {
			fmt.println(
				"⚠️  Solid operations not available in Sketch mode - Press [ESC] to exit sketch first",
			)
		}
	}
}

// Handle key up events
handle_key_up_gpu :: proc(app: ^AppStateGPU, key: sdl.Keycode, mods: sdl.Keymod) {
	if key == sdl.K_LCTRL || key == sdl.K_RCTRL {
		app.ctrl_held = false
	}
	if key == sdl.K_LSHIFT || key == sdl.K_RSHIFT {
		app.shift_held = false
	}
}

// Handle mouse button events
handle_mouse_button_gpu :: proc(app: ^AppStateGPU, button: ^sdl.MouseButtonEvent) {
	if button.button == u8(sdl.BUTTON_LEFT) && button.down {
		// Check if mouse is over UI - if so, don't process sketch tools or face selection
		if app.ui_context.mouse_over_ui {
			return
		}

		// Mode-specific click handling
		switch app.mode {
		case .Solid:
			// Solid Mode: Click to select faces
			select_face_at_cursor(app, app.mouse_x, app.mouse_y)

		case .Sketch:
			// Sketch Mode: Click to use sketch tools
			active_sketch := get_active_sketch(app)
			if active_sketch == nil {
				return
			}

			// Left click - sketch tools
			sketch_pos, ok := screen_to_sketch_gpu(app, app.mouse_x, app.mouse_y, active_sketch)
			if !ok {
				fmt.println("Failed to raycast to sketch plane")
				return
			}

			// RADIUS HANDLE DRAGGING: If in Select tool and hovering over radius handle, start dragging
			if active_sketch.current_tool == .Select &&
			   app.hover_state.entity_type == .RadiusHandle {
				entity := active_sketch.entities[app.hover_state.entity_id]
				if circle, ok := entity.(sketch.SketchCircle); ok {
					// Start dragging the radius handle
					app.dragging_radius = true
					app.dragging_circle_id = app.hover_state.entity_id
					app.drag_start_radius = circle.radius
					fmt.printf(
						"🎯 Started dragging radius handle for circle #%d (radius: %.2f)\n",
						app.hover_state.entity_id,
						circle.radius,
					)
					return
				}
			}

			// LINE ENDPOINT DRAGGING: If in Select tool and hovering over line endpoint handle, start dragging
			if active_sketch.current_tool == .Select &&
			   app.hover_state.entity_type == .LineEndpointHandle {
				// The hover_state.point_id contains the ID of the endpoint point to drag
				point := sketch.sketch_get_point(active_sketch, app.hover_state.point_id)
				if point != nil && !point.fixed {
					// Start dragging the endpoint point (reuses point dragging system)
					app.dragging_point = true
					app.dragging_point_id = app.hover_state.point_id
					app.drag_start_pos = m.Vec2{point.x, point.y}
					fmt.printf(
						"🎯 Started dragging line endpoint (point #%d at pos: %.2f, %.2f)\n",
						point.id,
						point.x,
						point.y,
					)
					return
				} else if point != nil && point.fixed {
					fmt.printf(
						"⚠️  Cannot drag fixed endpoint (point #%d)\n",
						app.hover_state.point_id,
					)
					return
				}
			}

			// DIMENSION DRAGGING: If in Select or Dimension tool and hovering over a constraint, prepare to drag
			// Don't start dragging immediately - wait for mouse movement (allows selection and double-click)
			if (active_sketch.current_tool == .Select ||
				   active_sketch.current_tool == .Dimension) &&
			   app.hover_state.entity_type == .Constraint {
				// Mark as "pending drag" - will start actual drag on mouse move
				app.dimension_drag_pending = true
				app.dragging_dimension_constraint_id = app.hover_state.constraint_id
				app.dimension_drag_start_pos = sketch_pos
				// Don't return yet - let the selection/double-click logic below run
			}

			// POINT DRAGGING: If in Select tool and hovering over a point, start dragging
			if active_sketch.current_tool == .Select && app.hover_state.entity_type == .Point {
				point := sketch.sketch_get_point(active_sketch, app.hover_state.point_id)
				if point != nil && !point.fixed {
					// Start dragging this point
					app.dragging_point = true
					app.dragging_point_id = app.hover_state.point_id
					app.drag_start_pos = m.Vec2{point.x, point.y}
					fmt.printf(
						"🎯 Started dragging point #%d (pos: %.2f, %.2f)\n",
						point.id,
						point.x,
						point.y,
					)
					return
				} else if point != nil && point.fixed {
					fmt.printf("⚠️  Cannot drag fixed point #%d\n", app.hover_state.point_id)
					return
				}
			}

			// Check for double-click on constraint (dimension editing)
			if app.hover_state.entity_type == .Constraint {
				current_time := f64(sdl.GetTicks()) / 1000.0 // Convert to seconds
				time_since_last_click := current_time - app.last_click_time

				// Double-click detected on same constraint
				if time_since_last_click < DOUBLE_CLICK_THRESHOLD &&
				   app.last_click_constraint_id == app.hover_state.constraint_id {
					// Start editing this constraint
					start_constraint_editing(app, app.hover_state.constraint_id)
					return
				}

				// Update double-click tracking
				app.last_click_time = current_time
				app.last_click_constraint_id = app.hover_state.constraint_id
			}

			// If hovering over a constraint in Select or Dimension tool, select it
			if (active_sketch.current_tool == .Select ||
				   active_sketch.current_tool == .Dimension) &&
			   app.hover_state.entity_type == .Constraint {
				sketch.sketch_select_constraint(active_sketch, app.hover_state.constraint_id)
				active_sketch.selected_entity = -1 // Deselect entity when selecting constraint
				app.cad_ui_state.temp_constraint_value = 0 // Reset temp value
				fmt.printf(
					"📐 Selected constraint #%d (tool: %v)\n",
					app.hover_state.constraint_id,
					active_sketch.current_tool,
				)
				app.needs_wireframe_update = true
				app.needs_selection_update = true

				// If in Dimension tool, cancel any active dimension creation
				if active_sketch.current_tool == .Dimension {
					// Reset dimension tool state to allow starting fresh
					active_sketch.first_point_id = -1
					active_sketch.second_point_id = -1
				}
				return
			}

			// DEBUG: Print hover state when clicking
			if active_sketch.current_tool == .Select {
				fmt.printf(
					"🐛 Select tool click - hover state: %v, entity_type: %v\n",
					app.hover_state,
					app.hover_state.entity_type,
				)
			}

			// Count constraints before click
			constraint_count_before := len(active_sketch.constraints)

			sketch.sketch_handle_click(active_sketch, sketch_pos)
			app.needs_wireframe_update = true
			app.needs_selection_update = true

			// AUTO-OPEN EDITING: Check if a new constraint was created
			if len(active_sketch.constraints) > constraint_count_before {
				// A new constraint was created - auto-open editing
				new_constraint := &active_sketch.constraints[len(active_sketch.constraints) - 1]
				fmt.printf(
					"📏 New constraint created (ID: %d) - auto-opening editor\n",
					new_constraint.id,
				)
				start_constraint_editing(app, new_constraint.id)
			}
		}
	}
}

// Raycast from screen coordinates to sketch plane
screen_to_sketch_gpu :: proc(
	app: ^AppStateGPU,
	screen_x, screen_y: f64,
	sk: ^sketch.Sketch2D,
) -> (
	m.Vec2,
	bool,
) {
	width := f64(app.viewer.window_width)
	height := f64(app.viewer.window_height)

	// Convert screen coordinates to NDC [-1, 1]
	ndc_x := (2.0 * screen_x) / width - 1.0
	ndc_y := 1.0 - (2.0 * screen_y) / height

	// Get view and projection matrices
	view := v.camera_get_view_matrix(&app.viewer.camera)
	projection := v.camera_get_projection_matrix(&app.viewer.camera)

	// Inverse matrices
	inv_proj := glsl.inverse(projection)
	inv_view := glsl.inverse(view)

	// Ray in view space
	ray_clip := glsl.vec4{f32(ndc_x), f32(ndc_y), -1.0, 1.0}
	ray_eye := inv_proj * ray_clip
	ray_eye = glsl.vec4{ray_eye.x, ray_eye.y, -1.0, 0.0}

	// Ray in world space
	ray_world_4 := inv_view * ray_eye
	ray_world := glsl.vec3{ray_world_4.x, ray_world_4.y, ray_world_4.z}
	ray_dir := glsl.normalize(ray_world)

	// Convert to double precision
	ray_origin := m.Vec3 {
		f64(app.viewer.camera.position.x),
		f64(app.viewer.camera.position.y),
		f64(app.viewer.camera.position.z),
	}
	ray_direction := m.Vec3{f64(ray_dir.x), f64(ray_dir.y), f64(ray_dir.z)}

	// Intersect ray with sketch plane
	plane_normal := sk.plane.normal
	plane_origin := sk.plane.origin

	denom := glsl.dot(ray_direction, plane_normal)
	if glsl.abs(denom) < 1e-6 {
		return m.Vec2{}, false
	}

	diff := plane_origin - ray_origin
	t := glsl.dot(diff, plane_normal) / denom

	if t < 0 {
		return m.Vec2{}, false
	}

	intersection_world := ray_origin + ray_direction * t
	sketch_pos := sketch.world_to_sketch(&sk.plane, intersection_world)

	return sketch_pos, true
}

// Render hover highlight for the currently hovered entity
render_hover_highlight_gpu :: proc(
	app: ^AppStateGPU,
	cmd: ^sdl.GPUCommandBuffer,
	pass: ^sdl.GPURenderPass,
	sk: ^sketch.Sketch2D,
	mvp: matrix[4, 4]f32,
) {
	// Hover color: bright yellow
	hover_color := [4]f32{1.0, 1.0, 0.0, 1.0}

	#partial switch app.hover_state.entity_type {
	case .Point:
		// Render hovered point with larger size (6px vs normal 4px)
		point := sketch.sketch_get_point(sk, app.hover_state.point_id)
		if point == nil do return

		v.viewer_gpu_render_single_point(app.viewer, cmd, pass, sk, point, mvp, hover_color, 6.0)

	case .Line, .Circle, .Arc:
		// Render hovered entity wireframe with thicker line
		if app.hover_state.entity_id < 0 || app.hover_state.entity_id >= len(sk.entities) {
			return
		}

		// Create wireframe for just this entity
		hover_mesh := v.sketch_entity_to_wireframe_gpu(sk, app.hover_state.entity_id)
		defer v.wireframe_mesh_gpu_destroy(&hover_mesh)

		// Render with thick yellow line
		v.viewer_gpu_render_wireframe(app.viewer, cmd, pass, &hover_mesh, hover_color, mvp, 4.0)

	case .Constraint:
		// Constraint is hovered - already highlighted by is_selected state in render_distance_dimension_gpu
		// We don't need additional rendering here, just set the selected_constraint_id temporarily
		// (actual highlighting will be shown during normal constraint rendering)
		return

	case .None:
		// Nothing to render
		return
	}
}

// Render frame with SDL3 GPU
render_frame_gpu :: proc(app: ^AppStateGPU) {
	// Acquire command buffer
	cmd := sdl.AcquireGPUCommandBuffer(app.viewer.gpu_device)
	if cmd == nil do return

	// Acquire swapchain texture
	swapchain: ^sdl.GPUTexture
	w, h: u32
	if !sdl.AcquireGPUSwapchainTexture(cmd, app.viewer.window, &swapchain, &w, &h) {
		return
	}

	// Update window size if changed
	if w != app.viewer.window_width || h != app.viewer.window_height {
		app.viewer.window_width = w
		app.viewer.window_height = h
		app.viewer.camera.aspect_ratio = f32(w) / f32(h)
	}

	if swapchain != nil {
		// Create depth texture for this frame (matches swapchain size)
		depth_texture_info := sdl.GPUTextureCreateInfo {
			type                 = .D2,
			format               = .D16_UNORM,
			usage                = {.DEPTH_STENCIL_TARGET},
			width                = w,
			height               = h,
			layer_count_or_depth = 1,
			num_levels           = 1,
		}

		depth_texture := sdl.CreateGPUTexture(app.viewer.gpu_device, depth_texture_info)
		if depth_texture == nil {
			fmt.eprintln("ERROR: Failed to create depth texture")
			return
		}
		defer sdl.ReleaseGPUTexture(app.viewer.gpu_device, depth_texture)

		// Begin render pass with depth buffer
		color_target := sdl.GPUColorTargetInfo {
			texture     = swapchain,
			load_op     = .CLEAR,
			store_op    = .STORE,
			clear_color = {0.08, 0.08, 0.08, 1.0},
		}

		depth_stencil_target := sdl.GPUDepthStencilTargetInfo {
			texture     = depth_texture,
			load_op     = .CLEAR,
			store_op    = .DONT_CARE, // We don't need to preserve depth between frames
			clear_depth = 1.0, // Clear to far plane
			cycle       = true, // Allow GPU to discard previous contents
		}

		pass := sdl.BeginGPURenderPass(cmd, &color_target, 1, &depth_stencil_target)

		// Bind pipeline
		sdl.BindGPUGraphicsPipeline(pass, app.viewer.pipeline)

		// Set viewport
		viewport := sdl.GPUViewport {
			x         = 0,
			y         = 0,
			w         = f32(w),
			h         = f32(h),
			min_depth = 0.0,
			max_depth = 1.0,
		}
		sdl.SetGPUViewport(pass, viewport)

		// Set scissor
		scissor := sdl.Rect {
			x = 0,
			y = 0,
			w = i32(w),
			h = i32(h),
		}
		sdl.SetGPUScissor(pass, scissor)

		// Calculate MVP matrix
		view := v.camera_get_view_matrix(&app.viewer.camera)
		proj := v.camera_get_projection_matrix(&app.viewer.camera)
		mvp := proj * view

		// Render grid (behind everything)
		v.viewer_gpu_render_grid(app.viewer, cmd, pass, mvp)

		// Render coordinate axes
		v.viewer_gpu_render_axes(app.viewer, cmd, pass, mvp)

		// Render ALL sketches from feature tree
		active_sketch := get_active_sketch(app)

		for feature in app.feature_tree.features {
			if feature.type != .Sketch do continue
			if !feature.visible do continue

			params, ok := feature.params.(ftree.SketchParams)
			if !ok || params.sketch_ref == nil do continue

			sk := params.sketch_ref
			is_active := (feature.id == app.active_sketch_id)

			// Choose color based on whether sketch is active
			sketch_color := is_active ? [4]f32{0.0, 1.0, 1.0, 1.0} : [4]f32{0.0, 0.3, 0.4, 0.7} // Active: bright cyan, Inactive: dark cyan

			// Generate wireframe for this sketch
			sketch_wireframe := v.sketch_to_wireframe_gpu(sk)
			defer v.wireframe_mesh_gpu_destroy(&sketch_wireframe)

			// Render sketch wireframe
			v.viewer_gpu_render_wireframe(
				app.viewer,
				cmd,
				pass,
				&sketch_wireframe,
				sketch_color,
				mvp,
				2.0,
			)

			// Render sketch points (darker for inactive sketches)
			point_color := is_active ? [4]f32{0.0, 0.8, 0.9, 1.0} : [4]f32{0.0, 0.2, 0.3, 0.5}
			v.viewer_gpu_render_sketch_points(app.viewer, cmd, pass, sk, mvp, point_color, 4.0)

			// Only render selection, preview, and constraints for ACTIVE sketch
			if is_active && active_sketch != nil {
				// Render hovered entity in bright yellow (before selection for proper layering)
				if app.hover_state.entity_type != .None {
					render_hover_highlight_gpu(app, cmd, pass, active_sketch, mvp)
				}

				// Render selected entity in bright yellow
				if active_sketch.selected_entity >= 0 {
					sketch_selected := v.sketch_to_wireframe_selected_gpu(active_sketch)
					defer v.wireframe_mesh_gpu_destroy(&sketch_selected)
					v.viewer_gpu_render_wireframe(
						app.viewer,
						cmd,
						pass,
						&sketch_selected,
						{1.0, 1.0, 0.0, 1},
						mvp,
						3.0,
					)

					// Render radius handle if selected entity is a circle (Week 12.3 - Task 2)
					render_radius_handle_gpu(app, cmd, pass, active_sketch, mvp)

					// Render line endpoint handles if selected entity is a line (Week 12.3 - Task 3)
					render_line_endpoint_handles_gpu(app, cmd, pass, active_sketch, mvp)
				}

				// Render preview geometry (cursor + temp line/circle)
				v.viewer_gpu_render_sketch_preview(app.viewer, cmd, pass, active_sketch, mvp)

				// Render constraints (dimensions, icons)
				v.viewer_gpu_render_sketch_constraints(
					app.viewer,
					cmd,
					pass,
					&app.text_renderer,
					active_sketch,
					mvp,
					view,
					proj,
					&app.document_settings,  // NEW: Pass document settings for unit formatting
				)

				// Render closed profile fills if visualization is enabled
				if app.show_profile_fill {
					render_profile_fills_gpu(app, cmd, pass, active_sketch, mvp)
				}
			}
		}

		// Render 3D solids based on render mode
		#partial switch app.viewer.render_mode {
		case .Wireframe:
			// Wireframe mode: Render edges only
			for &solid_mesh in app.solid_wireframes {
				v.viewer_gpu_render_wireframe(
					app.viewer,
					cmd,
					pass,
					&solid_mesh,
					{1.0, 1.0, 1.0, 1},
					mvp,
					2.0,
				)
			}

		case .Shaded:
			// Shaded mode: Render lit triangles
			for feature in app.feature_tree.features {
				if !feature.visible || !feature.enabled do continue
				if feature.result_solid == nil do continue

				// Convert solid to triangle mesh
				tri_mesh := v.solid_to_triangle_mesh_gpu(feature.result_solid)
				defer v.triangle_mesh_gpu_destroy(&tri_mesh)

				// Render with lighting (light gray material)
				v.viewer_gpu_render_triangle_mesh(
					app.viewer,
					cmd,
					pass,
					&tri_mesh,
					{0.7, 0.7, 0.7, 1.0},
					mvp,
				)
			}

		case .Both:
			// Both mode: Render shaded triangles + wireframe edges
			for feature in app.feature_tree.features {
				if !feature.visible || !feature.enabled do continue
				if feature.result_solid == nil do continue

				// Render triangles first (shaded)
				tri_mesh := v.solid_to_triangle_mesh_gpu(feature.result_solid)
				defer v.triangle_mesh_gpu_destroy(&tri_mesh)
				v.viewer_gpu_render_triangle_mesh(
					app.viewer,
					cmd,
					pass,
					&tri_mesh,
					{0.7, 0.7, 0.7, 1.0},
					mvp,
				)
			}

			// Then render wireframe on top (darker for contrast)
			for &solid_mesh in app.solid_wireframes {
				v.viewer_gpu_render_wireframe(
					app.viewer,
					cmd,
					pass,
					&solid_mesh,
					{0.2, 0.2, 0.2, 1},
					mvp,
					1.5,
				)
			}
		}

		// Render selected face highlight (yellow semi-transparent overlay)
		if selected_face, has_selection := app.selected_face.?; has_selection {
			feature := ftree.feature_tree_get_feature(&app.feature_tree, selected_face.feature_id)
			if feature != nil && feature.result_solid != nil {
				if selected_face.face_index >= 0 &&
				   selected_face.face_index < len(feature.result_solid.faces) {
					face := &feature.result_solid.faces[selected_face.face_index]
					v.viewer_gpu_render_face_highlight(
						app.viewer,
						cmd,
						pass,
						face,
						{1.0, 1.0, 0.0, 0.4},
						mvp,
					)
				}
			}
		}

		// Render text overlay
		v.text_render_2d_gpu(
			&app.text_renderer,
			cmd,
			pass,
			"OhCAD v0.2 - SDL3 GPU",
			20,
			20,
			44,
			{0, 255, 255, 255},
			w,
			h,
		)

		// Render hover tooltip if hovering over an entity
		if app.hover_state.entity_type != .None && active_sketch != nil {
			hover_info := sketch.get_hover_info(active_sketch, app.hover_state)
			if len(hover_info) > 0 {
				// Position tooltip offset from cursor (10px right, 10px down)
				tooltip_x := f32(app.mouse_x) + 10
				tooltip_y := f32(app.mouse_y) + 10

				// Render tooltip text in bright yellow to match hover color
				v.text_render_2d_gpu(
					&app.text_renderer,
					cmd,
					pass,
					hover_info,
					tooltip_x,
					tooltip_y,
					18,
					{255, 255, 0, 255},
					w,
					h,
				)
			}
		}

		// ========== Real CAD UI ==========
		// Begin UI frame
		ui.ui_begin_frame(
			&app.ui_context,
			cmd,
			pass,
			w,
			h,
			f32(app.mouse_x),
			f32(app.mouse_y),
			app.mouse_down_left,
		)

		// Render text input widget for dimension editing (AFTER ui_begin_frame)
		if app.editing_constraint_id >= 0 && active_sketch != nil {
			// Find the constraint being edited
			constraint: ^sketch.Constraint
			for &c in active_sketch.constraints {
				if c.id == app.editing_constraint_id {
					constraint = &c
					break
				}
			}

			if constraint != nil {
				// Get dimension screen position (only for distance constraints)
				#partial switch data in constraint.data {
				case sketch.DistanceData:
					// Get the two points
					p1 := sketch.sketch_get_point(active_sketch, data.point1_id)
					p2 := sketch.sketch_get_point(active_sketch, data.point2_id)

					if p1 != nil && p2 != nil {
						// Calculate dimension midpoint in 2D
						p1_2d := m.Vec2{p1.x, p1.y}
						p2_2d := m.Vec2{p2.x, p2.y}
						mid := (p1_2d + p2_2d) * 0.5

						// Calculate offset direction
						edge_vec := p2_2d - p1_2d
						edge_len := glsl.length(edge_vec)
						if edge_len > 1e-10 {
							edge_dir := edge_vec / edge_len
							perp_dir := m.Vec2{-edge_dir.y, edge_dir.x}
							to_offset := data.offset - mid
							offset_distance := glsl.dot(to_offset, perp_dir)

							// Ensure minimum offset
							MIN_OFFSET :: 0.3
							if glsl.abs(offset_distance) < MIN_OFFSET {
								offset_distance = MIN_OFFSET * glsl.sign(offset_distance)
								if offset_distance == 0 {
									offset_distance = MIN_OFFSET
								}
							}

							// Calculate dimension line midpoint (where text is)
							mid_dim_2d := mid + perp_dir * offset_distance
							mid_dim_3d := sketch.sketch_to_world(&active_sketch.plane, mid_dim_2d)

							// Project to screen space
							clip_pos :=
								proj *
								view *
								glsl.vec4 {
										f32(mid_dim_3d.x),
										f32(mid_dim_3d.y),
										f32(mid_dim_3d.z),
										1.0,
									}

							if clip_pos.w != 0.0 {
								// Convert from clip space to screen space
								ndc := clip_pos.xyz / clip_pos.w
								screen_x := (ndc.x + 1.0) * 0.5 * f32(w)
								screen_y := (1.0 - ndc.y) * 0.5 * f32(h)

								// Measure text size for widget sizing
								text_size: f32 = 28

								// Estimate widget size (we need this before rendering)
								sample_text := "000.00|" // Sample for sizing
								text_width, text_height := v.text_measure_gpu(
									&app.text_renderer,
									sample_text,
									text_size,
								)

								// Add padding around text
								padding: f32 = 8
								box_width := text_width + padding * 2
								box_height := text_height + padding * 2

								// Center the box on the dimension location
								box_x := screen_x - box_width * 0.5
								box_y := screen_y - box_height * 0.5

								// Update widget position and size
								app.text_input_widget.x = box_x
								app.text_input_widget.y = box_y
								app.text_input_widget.width = box_width
								app.text_input_widget.height = box_height
								app.text_input_widget.text_size = text_size

								// Render widget (handles background, border, text with cursor)
								ui.text_input_widget_render_3d(
									&app.text_input_widget,
									app.viewer,
									&app.text_renderer,
									cmd,
									pass,
									w,
									h,
								)
							}
						}
					}

				case sketch.DistanceXData:
					// Get the two points
					p1 := sketch.sketch_get_point(active_sketch, data.point1_id)
					p2 := sketch.sketch_get_point(active_sketch, data.point2_id)

					if p1 != nil && p2 != nil {
						// Calculate dimension midpoint in 2D
						p1_2d := m.Vec2{p1.x, p1.y}
						p2_2d := m.Vec2{p2.x, p2.y}
						mid := (p1_2d + p2_2d) * 0.5

						// For DistanceX, the dimension line is at data.offset.y
						mid_dim_2d := m.Vec2{mid.x, data.offset.y}
						mid_dim_3d := sketch.sketch_to_world(&active_sketch.plane, mid_dim_2d)

						// Project to screen space
						clip_pos :=
							proj *
							view *
							glsl.vec4 {
									f32(mid_dim_3d.x),
									f32(mid_dim_3d.y),
									f32(mid_dim_3d.z),
									1.0,
								}

						if clip_pos.w != 0.0 {
							// Convert from clip space to screen space
							ndc := clip_pos.xyz / clip_pos.w
							screen_x := (ndc.x + 1.0) * 0.5 * f32(w)
							screen_y := (1.0 - ndc.y) * 0.5 * f32(h)

							// Measure text size for widget sizing
							text_size: f32 = 28

							// Estimate widget size (we need this before rendering)
							sample_text := "000.00|" // Sample for sizing
							text_width, text_height := v.text_measure_gpu(
								&app.text_renderer,
								sample_text,
								text_size,
							)

							// Add padding around text
							padding: f32 = 8
							box_width := text_width + padding * 2
							box_height := text_height + padding * 2

							// Center the box on the dimension location
							box_x := screen_x - box_width * 0.5
							box_y := screen_y - box_height * 0.5

							// Update widget position and size
							app.text_input_widget.x = box_x
							app.text_input_widget.y = box_y
							app.text_input_widget.width = box_width
							app.text_input_widget.height = box_height
							app.text_input_widget.text_size = text_size

							// Render widget (handles background, border, text with cursor)
							ui.text_input_widget_render_3d(
								&app.text_input_widget,
								app.viewer,
								&app.text_renderer,
								cmd,
								pass,
								w,
								h,
							)
						}
					}

				case sketch.DistanceYData:
					// Get the two points
					p1 := sketch.sketch_get_point(active_sketch, data.point1_id)
					p2 := sketch.sketch_get_point(active_sketch, data.point2_id)

					if p1 != nil && p2 != nil {
						// Calculate dimension midpoint in 2D
						p1_2d := m.Vec2{p1.x, p1.y}
						p2_2d := m.Vec2{p2.x, p2.y}
						mid := (p1_2d + p2_2d) * 0.5

						// For DistanceY, the dimension line is at data.offset.x
						mid_dim_2d := m.Vec2{data.offset.x, mid.y}
						mid_dim_3d := sketch.sketch_to_world(&active_sketch.plane, mid_dim_2d)

						// Project to screen space
						clip_pos :=
							proj *
							view *
							glsl.vec4 {
									f32(mid_dim_3d.x),
									f32(mid_dim_3d.y),
									f32(mid_dim_3d.z),
									1.0,
								}

						if clip_pos.w != 0.0 {
							// Convert from clip space to screen space
							ndc := clip_pos.xyz / clip_pos.w
							screen_x := (ndc.x + 1.0) * 0.5 * f32(w)
							screen_y := (1.0 - ndc.y) * 0.5 * f32(h)

							// Measure text size for widget sizing
							text_size: f32 = 28

							// Estimate widget size (we need this before rendering)
							sample_text := "000.00|" // Sample for sizing
							text_width, text_height := v.text_measure_gpu(
								&app.text_renderer,
								sample_text,
								text_size,
							)

							// Add padding around text
							padding: f32 = 8
							box_width := text_width + padding * 2
							box_height := text_height + padding * 2

							// Center the box on the dimension location
							box_x := screen_x - box_width * 0.5
							box_y := screen_y - box_height * 0.5

							// Update widget position and size
							app.text_input_widget.x = box_x
							app.text_input_widget.y = box_y
							app.text_input_widget.width = box_width
							app.text_input_widget.height = box_height
							app.text_input_widget.text_size = text_size

							// Render widget (handles background, border, text with cursor)
							ui.text_input_widget_render_3d(
								&app.text_input_widget,
								app.viewer,
								&app.text_renderer,
								cmd,
								pass,
								w,
								h,
							)
						}
					}
				}
			}
		}

		// Render CAD UI layout (toolbar, properties, feature tree, status bar)
		// Pass active sketch (can be nil if no sketch is active) and current mode
		active_sketch_for_ui := get_active_sketch(app)
		is_sketch_mode := (app.mode == .Sketch)
		needs_update := ui.ui_cad_layout(
			&app.ui_context,
			&app.cad_ui_state,
			is_sketch_mode,
			active_sketch_for_ui,
			&app.feature_tree,
			app.extrude_feature_id,
			app.editing_constraint_id, // NEW: Pass editing state to UI
			app.editing_feature_id, // NEW: Pass feature edit mode state
			&app.document_settings,  // NEW: Pass document settings
			w,
			h,
		)

		// Handle feature tree double-click (Week 12.36 - History Navigation)
		if app.ui_context.feature_tree_click_id >= 0 {
			// Get current time for double-click detection
			current_time := f64(sdl.GetTicks()) / 1000.0 // Convert to seconds
			time_since_last_click := current_time - app.last_tree_click_time

			// DEBUG: Print click info
			fmt.printf(
				"🖱️  Feature tree click detected: feature_id=%d, time_since_last=%.3f\n",
				app.ui_context.feature_tree_click_id,
				time_since_last_click,
			)

			// Check for double-click on same feature OR checkmark button click
			if time_since_last_click < DOUBLE_CLICK_THRESHOLD &&
			   app.last_tree_click_feature_id == app.ui_context.feature_tree_click_id {
				// Double-click detected! Enter edit mode for this feature
				clicked_feature_id := app.ui_context.feature_tree_click_id
				feature := ftree.feature_tree_get_feature(&app.feature_tree, clicked_feature_id)

				fmt.printf("🎯 Double-click detected on feature #%d\n", clicked_feature_id)

				if feature != nil && feature.type == .Sketch {
					// Enter sketch edit mode
					enter_sketch_edit_mode(app, clicked_feature_id)
					app.needs_wireframe_update = true
					app.needs_selection_update = true
				} else {
					fmt.printf(
						"⚠️  Feature #%d is not a sketch - cannot edit\n",
						clicked_feature_id,
					)
				}

				// Reset double-click tracking to avoid triple-click
				app.last_tree_click_time = 0.0
				app.last_tree_click_feature_id = -1
			} else {
				// Single click - update tracking for next potential double-click
				fmt.printf(
					"📌 Single click recorded (waiting for second click within %.1fs)\n",
					DOUBLE_CLICK_THRESHOLD,
				)
				app.last_tree_click_time = current_time
				app.last_tree_click_feature_id = app.ui_context.feature_tree_click_id
			}

			// Clear the click ID for next frame
			app.ui_context.feature_tree_click_id = -1
		}

		// Handle checkmark button click (finish editing sketch) - Week 12.36
		// The UI signals this by setting the checkmark_clicked field
		if app.ui_context.checkmark_clicked {
			// Exit sketch edit mode and regenerate
			if app.editing_feature_id >= 0 {
				exit_sketch_edit_mode(app)
			}
			app.ui_context.checkmark_clicked = false
		}

		// If properties changed (e.g., extrude depth), regenerate and update solids
		if needs_update {
			// Regenerate all features to update geometry
			ftree.feature_tree_regenerate_all(&app.feature_tree)
			// Update wireframe display
			update_solid_wireframes_gpu(app)
		}

		// End UI frame
		ui.ui_end_frame(&app.ui_context)

		sdl.EndGPURenderPass(pass)
	}

	// Submit command buffer
	_ = sdl.SubmitGPUCommandBuffer(cmd)
}

// Test extrude feature
test_extrude_gpu :: proc(app: ^AppStateGPU) {
	fmt.println("\n=== Testing Extrude Feature ===")

	if app.extrude_feature_id >= 0 {
		fmt.println("⚠️  Sketch already extruded!")
		return
	}

	// Get selected sketch (or use last created sketch if none selected)
	sketch_id := app.selected_sketch_id
	if sketch_id < 0 {
		// No selection - find the last sketch
		for i := len(app.feature_tree.features) - 1; i >= 0; i -= 1 {
			feature := app.feature_tree.features[i]
			if feature.type == .Sketch {
				sketch_id = feature.id
				app.selected_sketch_id = sketch_id
				fmt.printf("📌 Auto-selected last sketch (ID: %d)\n", sketch_id)
				break
			}
		}
	}

	if sketch_id < 0 {
		fmt.println("❌ Cannot extrude - no sketch available")
		return
	}

	feature := ftree.feature_tree_get_feature(&app.feature_tree, sketch_id)
	if feature == nil || feature.type != .Sketch {
		fmt.println("❌ Cannot extrude - selected feature is not a sketch")
		return
	}

	params, ok := feature.params.(ftree.SketchParams)
	if !ok || params.sketch_ref == nil {
		fmt.println("❌ Cannot extrude - invalid sketch data")
		return
	}

	selected_sketch := params.sketch_ref

	if !sketch.sketch_has_closed_profile(selected_sketch) {
		fmt.println("❌ Cannot extrude - sketch does not contain a closed profile")
		return
	}

	fmt.println("✅ Closed profile detected!")

	extrude_id := ftree.feature_tree_add_extrude(
		&app.feature_tree,
		sketch_id,
		1.0,
		.Forward,
		"Extrude001",
	)

	if extrude_id < 0 {
		fmt.println("❌ Failed to add extrude feature")
		return
	}

	app.extrude_feature_id = extrude_id
	app.cad_ui_state.temp_extrude_depth = 1.0 // Initialize UI state

	if !ftree.feature_regenerate(&app.feature_tree, extrude_id) {
		fmt.println("❌ Failed to regenerate extrude")
		return
	}

	update_solid_wireframes_gpu(app)
	ftree.feature_tree_print(&app.feature_tree)

	fmt.println("\n✅ Extrude added!")
}

// Test cut feature
test_cut_gpu :: proc(app: ^AppStateGPU) {
	fmt.println("\n=== Testing Cut Feature ===")

	// Need an existing solid to cut from
	if app.extrude_feature_id < 0 {
		fmt.println("❌ Cannot cut - no base solid exists (extrude first)")
		return
	}

	// Get selected sketch (or use last created sketch if none selected)
	sketch_id := app.selected_sketch_id
	if sketch_id < 0 {
		// No selection - find the last sketch
		for i := len(app.feature_tree.features) - 1; i >= 0; i -= 1 {
			feature := app.feature_tree.features[i]
			if feature.type == .Sketch {
				sketch_id = feature.id
				app.selected_sketch_id = sketch_id
				fmt.printf("📌 Auto-selected last sketch (ID: %d)\n", sketch_id)
				break
			}
		}
	}

	if sketch_id < 0 {
		fmt.println("❌ Cannot cut - no sketch available")
		return
	}

	feature := ftree.feature_tree_get_feature(&app.feature_tree, sketch_id)
	if feature == nil || feature.type != .Sketch {
		fmt.println("❌ Cannot cut - selected feature is not a sketch")
		return
	}

	params, ok := feature.params.(ftree.SketchParams)
	if !ok || params.sketch_ref == nil {
		fmt.println("❌ Cannot cut - invalid sketch data")
		return
	}

	selected_sketch := params.sketch_ref

	// Need a closed profile in the sketch
	if !sketch.sketch_has_closed_profile(selected_sketch) {
		fmt.println("❌ Cannot cut - sketch does not contain a closed profile")
		return
	}

	fmt.println("✅ Closed profile detected!")

	// Get extrude depth to calculate appropriate cut depth
	extrude_feature := ftree.feature_tree_get_feature(&app.feature_tree, app.extrude_feature_id)
	if extrude_feature == nil {
		fmt.println("❌ Failed to get extrude feature")
		return
	}

	extrude_params, extrude_ok := extrude_feature.params.(ftree.ExtrudeParams)
	if !extrude_ok {
		fmt.println("❌ Failed to get extrude parameters")
		return
	}

	// Default cut depth is 50% of extrude depth (or max 0.3 for shallow extrudes)
	cut_depth := extrude_params.depth * 0.5
	if cut_depth > 0.3 {
		cut_depth = 0.3
	}

	fmt.printf(
		"🔧 Extrude depth: %.3f, Cut depth: %.3f (50%% of extrude)\n",
		extrude_params.depth,
		cut_depth,
	)

	cut_id := ftree.feature_tree_add_cut(
		&app.feature_tree,
		sketch_id,
		app.extrude_feature_id,
		cut_depth,
		.Forward,
		"Cut001",
	)

	if cut_id < 0 {
		fmt.println("❌ Failed to add cut feature")
		return
	}

	app.cut_feature_id = cut_id

	if !ftree.feature_regenerate(&app.feature_tree, cut_id) {
		fmt.println("❌ Failed to regenerate cut")
		return
	}

	update_solid_wireframes_gpu(app)
	ftree.feature_tree_print(&app.feature_tree)

	fmt.println("\n✅ Cut added!")
}

// Test revolve feature
test_revolve_gpu :: proc(app: ^AppStateGPU) {
	fmt.println("\n=== Testing Revolve Feature ===")

	// Get selected sketch (or use last created sketch if none selected)
	sketch_id := app.selected_sketch_id
	if sketch_id < 0 {
		// No selection - find the last sketch
		for i := len(app.feature_tree.features) - 1; i >= 0; i -= 1 {
			feature := app.feature_tree.features[i]
			if feature.type == .Sketch {
				sketch_id = feature.id
				app.selected_sketch_id = sketch_id
				fmt.printf("📌 Auto-selected last sketch (ID: %d)\n", sketch_id)
				break
			}
		}
	}

	if sketch_id < 0 {
		fmt.println("❌ Cannot revolve - no sketch available")
		return
	}

	feature := ftree.feature_tree_get_feature(&app.feature_tree, sketch_id)
	if feature == nil || feature.type != .Sketch {
		fmt.println("❌ Cannot revolve - selected feature is not a sketch")
		return
	}

	params, ok := feature.params.(ftree.SketchParams)
	if !ok || params.sketch_ref == nil {
		fmt.println("❌ Cannot revolve - invalid sketch data")
		return
	}

	selected_sketch := params.sketch_ref

	if !sketch.sketch_has_closed_profile(selected_sketch) {
		fmt.println("❌ Cannot revolve - sketch does not contain a closed profile")
		return
	}

	fmt.println("✅ Closed profile detected!")

	// Default parameters: 360° around Y-axis, 32 segments
	revolve_id := ftree.feature_tree_add_revolve(
		&app.feature_tree,
		sketch_id,
		360.0, // Full revolution
		32, // 32 segments (smooth)
		.SketchY, // Around Y-axis (vertical)
		"Revolve001",
	)

	if revolve_id < 0 {
		fmt.println("❌ Failed to add revolve feature")
		return
	}

	if !ftree.feature_regenerate(&app.feature_tree, revolve_id) {
		fmt.println("❌ Failed to regenerate revolve")
		return
	}

	update_solid_wireframes_gpu(app)
	ftree.feature_tree_print(&app.feature_tree)

	fmt.println("\n✅ Revolve added!")
}

// Export all solids to STL file
export_to_stl_gpu :: proc(app: ^AppStateGPU) {
	fmt.println("\n=== Exporting to STL ===")

	// Collect all visible solids from feature tree
	solids := make([dynamic]^extrude.SimpleSolid)
	defer delete(solids)

	// Build a set of feature IDs that are consumed by other features
	consumed_features := make(map[int]bool)
	defer delete(consumed_features)

	// Mark features that are used as base solids for Cut operations
	for feature in app.feature_tree.features {
		if feature.type == .Cut {
			if params, ok := feature.params.(ftree.CutParams); ok {
				consumed_features[params.base_feature_id] = true
			}
		}
	}

	// Export only the final solids (not consumed by other operations)
	for feature in app.feature_tree.features {
		if !feature.visible || !feature.enabled {
			continue
		}

		// Skip features that are consumed by other operations
		if consumed_features[feature.id] {
			continue
		}

		if feature.result_solid != nil {
			append(&solids, feature.result_solid)
		}
	}

	if len(solids) == 0 {
		fmt.println("❌ No solids to export (create some 3D features first)")
		app.status_message = "Export failed: No solids to export"
		return
	}

	// Generate filename with timestamp for uniqueness
	// Format: export_YYYYMMDD_HHMMSS.stl
	// For now, use simple counter or just "export.stl"
	filepath := "export.stl"

	fmt.printf("📦 Exporting %d solid(s) to STL...\n", len(solids))

	// Export to STL
	result := stl.export_feature_tree_to_stl(solids[:], filepath)

	if !result.success {
		fmt.println("❌", result.message)
		app.status_message = fmt.tprintf("Export failed: %s", result.message)
	} else {
		fmt.println("✅", result.message)
		fmt.println("   File saved to:", filepath)
		app.status_message = fmt.tprintf("Exported to %s successfully!", filepath)

		// Attempt to open the file in the default STL viewer
		open_file_in_viewer(filepath)
	}
}

// Update solid wireframes from feature tree
update_solid_wireframes_gpu :: proc(app: ^AppStateGPU) {
	for &mesh in app.solid_wireframes {
		v.wireframe_mesh_gpu_destroy(&mesh)
	}
	clear(&app.solid_wireframes)

	// Build a set of feature IDs that are consumed by other features
	consumed_features := make(map[int]bool)
	defer delete(consumed_features)

	// Mark features that are used as base solids for Cut operations
	for feature in app.feature_tree.features {
		if feature.type == .Cut {
			if params, ok := feature.params.(ftree.CutParams); ok {
				consumed_features[params.base_feature_id] = true
			}
		}
	}

	// Render only the final solids (not consumed by other operations)
	for feature in app.feature_tree.features {
		if !feature.visible || !feature.enabled {
			continue
		}

		// Skip features that are consumed by other operations
		if consumed_features[feature.id] {
			continue
		}

		if feature.result_solid != nil {
			mesh := v.solid_to_wireframe_gpu(feature.result_solid)
			append(&app.solid_wireframes, mesh)
		}
	}

	fmt.printf("Updated %d solid wireframes\n", len(app.solid_wireframes))
}

// Change extrude depth
change_extrude_depth_gpu :: proc(app: ^AppStateGPU, delta: f64) {
	if app.extrude_feature_id < 0 {
		fmt.println("❌ No extrude feature")
		return
	}

	feature := ftree.feature_tree_get_feature(&app.feature_tree, app.extrude_feature_id)
	if feature == nil do return

	params, ok := feature.params.(ftree.ExtrudeParams)
	if !ok do return

	new_depth := params.depth + delta
	if new_depth < 0.1 {
		new_depth = 0.1
	}

	params.depth = new_depth
	feature.params = params

	fmt.printf("🔄 Extrude depth: %.2f\n", new_depth)

	ftree.feature_tree_mark_dirty(&app.feature_tree, app.extrude_feature_id)

	if ftree.feature_regenerate(&app.feature_tree, app.extrude_feature_id) {
		update_solid_wireframes_gpu(app)
		fmt.printf("✅ Depth updated: %.2f\n", new_depth)
	}
}

// Change active feature parameters (smart: extrude/revolve)
change_active_feature_parameter :: proc(app: ^AppStateGPU, delta: f64) {
	// Get the last feature in the tree (most recent operation)
	if len(app.feature_tree.features) == 0 {
		fmt.println("❌ No features to modify")
		return
	}

	// Find the most recent extrude or revolve feature
	last_feature_id := -1
	for i := len(app.feature_tree.features) - 1; i >= 0; i -= 1 {
		feature := app.feature_tree.features[i]
		if feature.type == .Extrude || feature.type == .Revolve {
			last_feature_id = feature.id
			break
		}
	}

	if last_feature_id < 0 {
		fmt.println("❌ No extrude or revolve feature to modify")
		return
	}

	feature := ftree.feature_tree_get_feature(&app.feature_tree, last_feature_id)
	if feature == nil do return

	#partial switch feature.type {
	case .Extrude:
		params, ok := &feature.params.(ftree.ExtrudeParams)
		if !ok do return

		new_depth := params.depth + delta
		if new_depth < 0.1 {
			new_depth = 0.1
		}

		params.depth = new_depth
		fmt.printf("🔄 Extrude depth: %.2f\n", new_depth)

		ftree.feature_tree_mark_dirty(&app.feature_tree, last_feature_id)

		if ftree.feature_regenerate(&app.feature_tree, last_feature_id) {
			update_solid_wireframes_gpu(app)
			fmt.printf("✅ Depth updated: %.2f\n", new_depth)
		}

	case .Revolve:
		params, ok := &feature.params.(ftree.RevolveParams)
		if !ok do return

		// For revolve, delta should be in degrees (10° per step)
		angle_delta := delta * 10.0 // Convert 0.1 to 10 degrees
		new_angle := params.angle + angle_delta

		// Clamp to valid range
		if new_angle < 1.0 {
			new_angle = 1.0
		}
		if new_angle > 360.0 {
			new_angle = 360.0
		}

		params.angle = new_angle
		fmt.printf("🔄 Revolve angle: %.1f°\n", new_angle)

		ftree.feature_tree_mark_dirty(&app.feature_tree, last_feature_id)

		if ftree.feature_regenerate(&app.feature_tree, last_feature_id) {
			update_solid_wireframes_gpu(app)
			fmt.printf("✅ Angle updated: %.1f°\n", new_angle)
		}

	case:
		fmt.println("❌ Feature type does not support parameter modification")
	}
}

// =============================================================================
// Modal System (NEW)
// =============================================================================

// Enter sketch mode (start editing a sketch)
enter_sketch_mode :: proc(app: ^AppStateGPU, sketch_id: int) {
	app.mode = .Sketch
	app.active_sketch_id = sketch_id
	fmt.printf("=== ENTERED SKETCH MODE (Sketch ID: %d) ===\n", sketch_id)
}

// Exit sketch mode (return to solid mode)
exit_sketch_mode :: proc(app: ^AppStateGPU) {
	app.mode = .Solid
	app.active_sketch_id = -1
	fmt.println("=== EXITED TO SOLID MODE ===")
}

// Enter sketch edit mode (Week 12.36 - History Navigation)
// Edit an existing sketch feature by double-clicking it in the feature tree
enter_sketch_edit_mode :: proc(app: ^AppStateGPU, sketch_feature_id: int) {
	// Get the feature from the tree
	feature := ftree.feature_tree_get_feature(&app.feature_tree, sketch_feature_id)
	if feature == nil {
		fmt.println("❌ Failed to get feature for editing")
		return
	}

	// Verify it's a sketch feature
	if feature.type != .Sketch {
		fmt.println("❌ Selected feature is not a sketch - cannot edit")
		return
	}

	// Get sketch reference
	params, ok := feature.params.(ftree.SketchParams)
	if !ok || params.sketch_ref == nil {
		fmt.println("❌ Invalid sketch data - cannot edit")
		return
	}

	// Enter sketch mode for this feature
	app.mode = .Sketch
	app.active_sketch_id = sketch_feature_id
	app.editing_feature_id = sketch_feature_id

	fmt.printf("✏️  ENTERED EDIT MODE for %s (ID: %d)\n", feature.name, sketch_feature_id)
	fmt.println("   Modify geometry/constraints, then press [ESC] to finish editing")
}

// Exit sketch edit mode and regenerate dependents (Week 12.36 - History Navigation)
exit_sketch_edit_mode :: proc(app: ^AppStateGPU) {
	if app.editing_feature_id < 0 {
		fmt.println("❌ Not in edit mode")
		return
	}

	edited_feature_id := app.editing_feature_id
	feature := ftree.feature_tree_get_feature(&app.feature_tree, edited_feature_id)
	feature_name := feature != nil ? feature.name : "Unknown"

	// Exit to Solid Mode
	app.mode = .Solid
	app.active_sketch_id = -1
	app.editing_feature_id = -1

	fmt.printf("⬅️  EXITED EDIT MODE for %s\n", feature_name)

	// Mark the edited feature and all dependents as dirty
	ftree.feature_tree_mark_dirty(&app.feature_tree, edited_feature_id)
	fmt.println("🔄 Marked feature tree as dirty - regenerating...")

	// Regenerate all features (this will rebuild the solid geometry)
	ftree.feature_tree_regenerate_all(&app.feature_tree)

	// Update visualization
	update_solid_wireframes_gpu(app)
	app.needs_wireframe_update = true
	app.needs_selection_update = true

	fmt.println("✅ Feature tree regenerated successfully!")
	fmt.println("=== RETURNED TO SOLID MODE ===")
}

// Get active sketch from feature tree (replaces app.sketch)
get_active_sketch :: proc(app: ^AppStateGPU) -> ^sketch.Sketch2D {
	if app.active_sketch_id < 0 {
		return nil
	}

	feature := ftree.feature_tree_get_feature(&app.feature_tree, app.active_sketch_id)
	if feature == nil {
		return nil
	}

	if feature.type != .Sketch {
		return nil
	}

	params, ok := feature.params.(ftree.SketchParams)
	if !ok || params.sketch_ref == nil {
		return nil
	}

	return params.sketch_ref
}

// Create new sketch on standard plane
create_sketch_on_plane :: proc(app: ^AppStateGPU, plane_type: SketchPlaneType) -> int {
	plane: sketch.SketchPlane

	switch plane_type {
	case .XY:
		plane = sketch.sketch_plane_xy()
		fmt.println("📐 Creating sketch on XY plane (Front view)")
	case .YZ:
		plane = sketch.sketch_plane_yz()
		fmt.println("📐 Creating sketch on YZ plane (Right view)")
	case .ZX:
		plane = sketch.sketch_plane_xz()
		fmt.println("📐 Creating sketch on XZ plane (Top view)")
	case .Face:
		// Create sketch on selected face
		return create_sketch_on_face(app)
	}

	// Count existing sketches for naming
	sketch_count := ftree.feature_tree_count_type(&app.feature_tree, .Sketch)
	sketch_name := fmt.aprintf("Sketch%03d", sketch_count + 1)

	// Create new sketch
	new_sketch := new(sketch.Sketch2D)
	new_sketch^ = sketch.sketch_init(sketch_name, plane)

	// Add to feature tree
	sketch_id := ftree.feature_tree_add_sketch(&app.feature_tree, new_sketch, sketch_name)

	if sketch_id < 0 {
		fmt.println("❌ Failed to add sketch to feature tree")
		free(new_sketch)
		return -1
	}

	// Enter sketch mode to edit the new sketch
	enter_sketch_mode(app, sketch_id)

	// Also mark as selected for operations (extrude/cut)
	app.selected_sketch_id = sketch_id

	// Set default tool
	sketch.sketch_set_tool(new_sketch, .Select)

	fmt.printf("✅ Created %s (ID: %d) - Now in SKETCH MODE\n", sketch_name, sketch_id)
	fmt.println("   Press [ESC] to exit sketch mode and return to SOLID MODE")

	return sketch_id
}

// Create sketch on selected face (NEW - Phase 5.7)
create_sketch_on_face :: proc(app: ^AppStateGPU) -> int {
	// Check if a face is selected
	selected_face, has_selection := app.selected_face.?
	if !has_selection {
		fmt.println("❌ No face selected - select a face first")
		return -1
	}

	// Get the feature containing the selected face
	feature := ftree.feature_tree_get_feature(&app.feature_tree, selected_face.feature_id)
	if feature == nil || feature.result_solid == nil {
		fmt.println("❌ Failed to get feature with selected face")
		return -1
	}

	// Get the face
	solid := feature.result_solid
	if selected_face.face_index < 0 || selected_face.face_index >= len(solid.faces) {
		fmt.println("❌ Invalid face index")
		return -1
	}

	face := &solid.faces[selected_face.face_index]

	fmt.printf("📐 Creating sketch on face: '%s'\n", face.name)

	// Extract plane from face
	// Use face center as origin and face normal as Z-axis
	plane_origin := face.center
	plane_normal := face.normal

	// Calculate U and V axes for the sketch plane
	// Choose U axis: prefer world X axis if not parallel to normal
	world_x := m.Vec3{1, 0, 0}
	world_y := m.Vec3{0, 1, 0}
	world_z := m.Vec3{0, 0, 1}

	// Find the world axis most perpendicular to the face normal
	dot_x := glsl.abs(glsl.dot(plane_normal, world_x))
	dot_y := glsl.abs(glsl.dot(plane_normal, world_y))
	dot_z := glsl.abs(glsl.dot(plane_normal, world_z))

	reference_axis: m.Vec3
	if dot_x < dot_y && dot_x < dot_z {
		reference_axis = world_x
	} else if dot_y < dot_z {
		reference_axis = world_y
	} else {
		reference_axis = world_z
	}

	// X axis = normalize(reference × normal)
	x_axis := glsl.normalize(glsl.cross(reference_axis, plane_normal))

	// Y axis = normal × X (ensures right-handed coordinate system)
	y_axis := glsl.cross(plane_normal, x_axis)

	// Create sketch plane
	plane := sketch.SketchPlane {
		origin = plane_origin,
		normal = plane_normal,
		x_axis = x_axis,
		y_axis = y_axis,
	}

	// Count existing sketches for naming
	sketch_count := ftree.feature_tree_count_type(&app.feature_tree, .Sketch)
	sketch_name := fmt.aprintf("Sketch%03d", sketch_count + 1)

	// Create new sketch
	new_sketch := new(sketch.Sketch2D)
	new_sketch^ = sketch.sketch_init(sketch_name, plane)

	// Add to feature tree
	sketch_id := ftree.feature_tree_add_sketch(&app.feature_tree, new_sketch, sketch_name)

	if sketch_id < 0 {
		fmt.println("❌ Failed to add sketch to feature tree")
		free(new_sketch)
		return -1
	}

	// Enter sketch mode to edit the new sketch
	enter_sketch_mode(app, sketch_id)

	// Also mark as selected for operations (extrude/cut)
	app.selected_sketch_id = sketch_id

	// Set default tool
	sketch.sketch_set_tool(new_sketch, .Select)

	fmt.printf(
		"✅ Created %s on face '%s' (ID: %d) - Now in SKETCH MODE\n",
		sketch_name,
		face.name,
		sketch_id,
	)
	fmt.println("   Plane origin:", plane_origin)
	fmt.println("   Plane normal:", plane_normal)
	fmt.println("   Press [ESC] to exit sketch mode and return to SOLID MODE")

	// Clear face selection after creating sketch
	app.selected_face = nil

	return sketch_id
}

// =============================================================================
// Face Selection System (NEW - Phase 5.4-5.5)
// =============================================================================

// Ray-plane intersection test
ray_plane_intersection :: proc(
	ray_origin: m.Vec3,
	ray_dir: m.Vec3,
	plane_origin: m.Vec3,
	plane_normal: m.Vec3,
) -> (
	t: f64,
	hit: bool,
) {
	denom := glsl.dot(ray_dir, plane_normal)

	// Ray is parallel to plane (or pointing away)
	if glsl.abs(denom) < 1e-6 {
		return 0.0, false
	}

	diff := plane_origin - ray_origin
	t = glsl.dot(diff, plane_normal) / denom

	// Intersection behind ray origin
	if t < 0 {
		return 0.0, false
	}

	return t, true
}

// Point-in-polygon test (2D projection onto face plane)
point_in_face_polygon :: proc(point: m.Vec3, face: ^extrude.SimpleFace) -> bool {
	if len(face.vertices) < 3 {
		return false
	}

	// Project point and vertices onto 2D plane using face normal
	// Use cross products to determine the major axis to drop
	abs_normal := m.Vec3{glsl.abs(face.normal.x), glsl.abs(face.normal.y), glsl.abs(face.normal.z)}

	// Choose projection plane (drop axis with largest normal component)
	project_to_2d :: proc(p: m.Vec3, drop_axis: int) -> m.Vec2 {
		switch drop_axis {
		case 0:
			// Drop X, use YZ
			return m.Vec2{p.y, p.z}
		case 1:
			// Drop Y, use XZ
			return m.Vec2{p.x, p.z}
		case 2:
			// Drop Z, use XY
			return m.Vec2{p.x, p.y}
		case:
			return m.Vec2{p.x, p.y}
		}
	}

	drop_axis := 2 // Default to Z
	if abs_normal.x > abs_normal.y && abs_normal.x > abs_normal.z {
		drop_axis = 0 // Drop X
	} else if abs_normal.y > abs_normal.z {
		drop_axis = 1 // Drop Y
	}

	// Project point to 2D
	point_2d := project_to_2d(point, drop_axis)

	// Ray casting algorithm for point-in-polygon
	inside := false
	n := len(face.vertices)

	for i in 0 ..< n {
		j := (i + 1) % n
		vi := project_to_2d(face.vertices[i].position, drop_axis)
		vj := project_to_2d(face.vertices[j].position, drop_axis)

		// Check if ray crosses edge
		if ((vi.y > point_2d.y) != (vj.y > point_2d.y)) &&
		   (point_2d.x < (vj.x - vi.x) * (point_2d.y - vi.y) / (vj.y - vi.y) + vi.x) {
			inside = !inside
		}
	}

	return inside
}

// Select face at screen cursor position
select_face_at_cursor :: proc(app: ^AppStateGPU, screen_x, screen_y: f64) -> bool {
	// Only allow face selection in Solid Mode
	if app.mode != .Solid {
		return false
	}

	// Cast ray from screen to world
	width := f64(app.viewer.window_width)
	height := f64(app.viewer.window_height)

	// Convert screen coordinates to NDC [-1, 1]
	ndc_x := (2.0 * screen_x) / width - 1.0
	ndc_y := 1.0 - (2.0 * screen_y) / height

	// Get view and projection matrices
	view := v.camera_get_view_matrix(&app.viewer.camera)
	projection := v.camera_get_projection_matrix(&app.viewer.camera)

	// Inverse matrices
	inv_proj := glsl.inverse(projection)
	inv_view := glsl.inverse(view)

	// Ray in view space
	ray_clip := glsl.vec4{f32(ndc_x), f32(ndc_y), -1.0, 1.0}
	ray_eye := inv_proj * ray_clip
	ray_eye = glsl.vec4{ray_eye.x, ray_eye.y, -1.0, 0.0}

	// Ray in world space
	ray_world_4 := inv_view * ray_eye
	ray_world := glsl.vec3{ray_world_4.x, ray_world_4.y, ray_world_4.z}
	ray_dir_f32 := glsl.normalize(ray_world)

	// Convert to double precision
	ray_origin := m.Vec3 {
		f64(app.viewer.camera.position.x),
		f64(app.viewer.camera.position.y),
		f64(app.viewer.camera.position.z),
	}
	ray_dir := m.Vec3{f64(ray_dir_f32.x), f64(ray_dir_f32.y), f64(ray_dir_f32.z)}

	// Find closest face hit
	closest_t := max(f64)
	found_face := false
	selected := SelectedFace{}

	// Test all features with solids
	for feature in app.feature_tree.features {
		if feature.result_solid == nil do continue
		if !feature.visible || !feature.enabled do continue

		solid := feature.result_solid

		// Test each face in the solid
		for &face, face_idx in solid.faces {
			// Ray-plane intersection
			t, hit := ray_plane_intersection(ray_origin, ray_dir, face.center, face.normal)
			if !hit || t >= closest_t do continue

			// Calculate hit point
			hit_point := ray_origin + ray_dir * t

			// Point-in-polygon test
			if point_in_face_polygon(hit_point, &face) {
				closest_t = t
				found_face = true
				selected = SelectedFace {
					feature_id = feature.id,
					face_index = face_idx,
				}

				fmt.printf(
					"🎯 Hit face '%s' (Feature %d, Face %d) at t=%.3f\n",
					face.name,
					feature.id,
					face_idx,
					t,
				)
			}
		}
	}

	if found_face {
		app.selected_face = selected
		fmt.printf(
			"✅ Selected face: Feature %d, Face %d\n",
			selected.feature_id,
			selected.face_index,
		)
		return true
	} else {
		app.selected_face = nil
		fmt.println("❌ No face hit")
		return false
	}
}

// Helper to read file or exit
read_entire_file_or_exit :: proc(path: string) -> ([]byte, bool) {
	data, ok := os.read_entire_file(path)
	if !ok {
		fmt.eprintln("ERROR: Failed to read file:", path)
		return nil, false
	}
	return data, true
}

// Open file in system default viewer
open_file_in_viewer :: proc(filepath: string) {
	fmt.printf("🔍 Opening %s in default viewer...\n", filepath)

	// macOS: Use 'open' command via system()
	when ODIN_OS == .Darwin {
		// Note: In a production app, you'd want to use a proper subprocess library
		// For now, just print a message since system() isn't directly available
		fmt.println("💡 To view the exported STL file, run: open", filepath)
		fmt.println("   Or double-click the file in Finder to open in your default STL viewer")
	} else {
		fmt.println("⚠️  Auto-open not supported on this platform - open file manually")
	}
}

// =============================================================================
// Constraint Editing (NEW - Week 12.2)
// =============================================================================

// Start editing a constraint value (double-click handler)
start_constraint_editing :: proc(app: ^AppStateGPU, constraint_id: int) {
	active_sketch := get_active_sketch(app)
	if active_sketch == nil {
		return
	}

	// Find the constraint
	constraint: ^sketch.Constraint
	for &c in active_sketch.constraints {
		if c.id == constraint_id {
			constraint = &c
			break
		}
	}

	if constraint == nil {
		fmt.println("❌ Constraint not found")
		return
	}

	// Get current value based on constraint type
	current_value: f64 = 0.0
	is_editable := false

	#partial switch data in constraint.data {
	case sketch.DistanceData:
		current_value = data.distance
		is_editable = true

	case sketch.DistanceXData:
		current_value = math.abs(data.distance)  // Display absolute value
		is_editable = true

	case sketch.DistanceYData:
		current_value = math.abs(data.distance)  // Display absolute value
		is_editable = true

	case sketch.AngleData:
		// Convert angle from stored value to degrees for display
		current_value = data.angle // Already stored in degrees from creation
		is_editable = true

	case:
		fmt.println("⚠️  This constraint type is not editable yet")
		return
	}

	if !is_editable {
		return
	}

	// Convert value to text
	value_str := fmt.tprintf("%.2f", current_value)

	// Configure widget visual properties before starting
	app.text_input_widget.bg_color = {0.0, 0.0, 0.0, 0.9} // Dark background with 90% opacity
	app.text_input_widget.text_color = {255, 255, 0, 255} // Yellow text
	app.text_input_widget.text_size = 28

	// Start widget editing with initial text
	app.editing_constraint_id = constraint_id
	ui.text_input_widget_start(&app.text_input_widget, value_str)

	// Select the constraint for visual feedback
	sketch.sketch_select_constraint(active_sketch, constraint_id)
	active_sketch.selected_entity = -1

	// Enable SDL text input
	_ = sdl.StartTextInput(app.viewer.window)

	fmt.printf(
		"✏️  Editing constraint #%d (current value: %.2f) - text selected\n",
		constraint_id,
		current_value,
	)
	fmt.println("   Type new value, press ENTER to confirm, ESC to cancel")
}

// Stop editing constraint (commit or cancel)
stop_constraint_editing :: proc(app: ^AppStateGPU, commit: bool) {
	if app.editing_constraint_id < 0 {
		return
	}

	// Disable SDL text input
	_ = sdl.StopTextInput(app.viewer.window)

	if commit {
		// Get text from widget
		text_str := ui.text_input_widget_get_text(&app.text_input_widget)
		new_value, ok := parse_f64(text_str)

		if !ok {
			fmt.println("❌ Invalid number format - edit cancelled")
			app.editing_constraint_id = -1
			ui.text_input_widget_stop(&app.text_input_widget)
			return
		}

		if new_value <= 0.0 {
			fmt.println("❌ Value must be positive - edit cancelled")
			app.editing_constraint_id = -1
			ui.text_input_widget_stop(&app.text_input_widget)
			return
		}

		// Update the constraint value
		update_constraint_value(app, app.editing_constraint_id, new_value)
	} else {
		fmt.println("✖️  Edit cancelled")
	}

	app.editing_constraint_id = -1
	ui.text_input_widget_stop(&app.text_input_widget)
}

// Update constraint value and re-solve
update_constraint_value :: proc(app: ^AppStateGPU, constraint_id: int, new_value: f64) {
	active_sketch := get_active_sketch(app)
	if active_sketch == nil {
		return
	}

	// Find the constraint
	constraint: ^sketch.Constraint
	for &c in active_sketch.constraints {
		if c.id == constraint_id {
			constraint = &c
			break
		}
	}

	if constraint == nil {
		fmt.println("❌ Constraint not found")
		return
	}

	// Update value based on constraint type
	#partial switch &data in constraint.data {
	case sketch.DistanceData:
		old_value := data.distance
		data.distance = new_value
		fmt.printf(
			"✅ Updated constraint #%d: %.2f → %.2f\n",
			constraint_id,
			old_value,
			new_value,
		)

	case sketch.DistanceXData:
		old_value := data.distance

		// Get the actual points to determine the correct sign
		p1 := sketch.sketch_get_point(active_sketch, data.point1_id)
		p2 := sketch.sketch_get_point(active_sketch, data.point2_id)

		if p1 != nil && p2 != nil {
			// Calculate the current X-direction (p2.x - p1.x)
			current_dx := p2.x - p1.x

			// Apply the sign based on the current direction
			signed_value := new_value
			if current_dx < 0 {
				signed_value = -new_value
			}

			data.distance = signed_value
			fmt.printf(
				"✅ Updated horizontal constraint #%d: %.2f → %.2f (signed: %.2f)\n",
				constraint_id,
				math.abs(old_value),
				new_value,
				signed_value,
			)
		} else {
			fmt.println("❌ Failed to update constraint - invalid points")
			return
		}

	case sketch.DistanceYData:
		old_value := data.distance

		// Get the actual points to determine the correct sign
		p1 := sketch.sketch_get_point(active_sketch, data.point1_id)
		p2 := sketch.sketch_get_point(active_sketch, data.point2_id)

		if p1 != nil && p2 != nil {
			// Calculate the current Y-direction (p2.y - p1.y)
			current_dy := p2.y - p1.y

			// Apply the sign based on the current direction
			signed_value := new_value
			if current_dy < 0 {
				signed_value = -new_value
			}

			data.distance = signed_value
			fmt.printf(
				"✅ Updated vertical constraint #%d: %.2f → %.2f (signed: %.2f)\n",
				constraint_id,
				math.abs(old_value),
				new_value,
				signed_value,
			)
		} else {
			fmt.println("❌ Failed to update constraint - invalid points")
			return
		}

	case sketch.AngleData:
		old_value := data.angle
		data.angle = new_value
		fmt.printf(
			"✅ Updated constraint #%d: %.1f° → %.1f°\n",
			constraint_id,
			old_value,
			new_value,
		)

	case:
		fmt.println("❌ Cannot update this constraint type")
		return
	}

	// Only solve if constraint is driving (not a reference dimension)
	if constraint.driving {
		// Re-solve constraints
		fmt.println("🔄 Re-solving constraints...")
		result := sketch.sketch_solve_constraints(active_sketch)

		if result.status == .Success {
			fmt.println("✅ Constraints solved! Geometry updated.")
			app.needs_wireframe_update = true
			app.needs_selection_update = true
			app.status_message = fmt.tprintf("Updated constraint to %.2f", new_value)
		} else if result.status == .Underconstrained {
			fmt.println("⚠️  Sketch is underconstrained")
			app.needs_wireframe_update = true
			app.needs_selection_update = true
		} else {
			fmt.println("❌ Failed to solve constraints")
			app.status_message = "Failed to solve constraints"
		}
	} else {
		// Non-driving constraint (reference dimension) - just update the value
		fmt.println("📏 Updated reference dimension (non-driving)")
		app.needs_wireframe_update = true
		app.needs_selection_update = true
		app.status_message = fmt.tprintf("Updated dimension to %.2f", new_value)
	}
}

// Simple f64 parser (supports basic decimal format)
parse_f64 :: proc(s: string) -> (f64, bool) {
	// Remove whitespace
	s := s

	if len(s) == 0 {
		return 0.0, false
	}

	// Use Odin's strconv library to parse the number
	value, ok := strconv.parse_f64(s)
	return value, ok
}

// Render closed profile fills with transparency
render_profile_fills_gpu :: proc(
	app: ^AppStateGPU,
	cmd: ^sdl.GPUCommandBuffer,
	pass: ^sdl.GPURenderPass,
	sk: ^sketch.Sketch2D,
	mvp: matrix[4, 4]f32,
) {
	// Detect all profiles
	profiles := sketch.sketch_detect_profiles(sk)
	defer {
		for &profile in profiles {
			sketch.profile_destroy(&profile)
		}
		delete(profiles)
	}

	// Render only closed profiles
	for profile in profiles {
		if profile.type != .Closed {
			continue
		}

		// Check if profile is a circle (simpler rendering)
		if len(profile.entities) == 1 {
			entity := sk.entities[profile.entities[0]]
			if circle, is_circle := entity.(sketch.SketchCircle); is_circle {
				render_circle_fill_gpu(app, cmd, pass, sk, circle, mvp)
				continue
			}
		}

		// Line-based closed profile - tessellate as triangle fan
		if len(profile.points) >= 3 {
			render_polygon_fill_gpu(app, cmd, pass, sk, profile.points[:], mvp)
		}
	}
}

// Render filled circle with triangle fan
render_circle_fill_gpu :: proc(
	app: ^AppStateGPU,
	cmd: ^sdl.GPUCommandBuffer,
	pass: ^sdl.GPURenderPass,
	sk: ^sketch.Sketch2D,
	circle: sketch.SketchCircle,
	mvp: matrix[4, 4]f32,
) {
	center_pt := sketch.sketch_get_point(sk, circle.center_id)
	if center_pt == nil do return

	center_2d := m.Vec2{center_pt.x, center_pt.y}
	center_3d := sketch.sketch_to_world(&sk.plane, center_2d)

	// Generate triangle fan for circle fill
	segments := 32
	triangle_verts := make([dynamic]v.LineVertex, 0, segments * 3)
	defer delete(triangle_verts)

	center_f32 := [3]f32{f32(center_3d.x), f32(center_3d.y), f32(center_3d.z)}

	for i in 0 ..< segments {
		angle0 := f64(i) * (2.0 * math.PI) / f64(segments)
		angle1 := f64((i + 1) % segments) * (2.0 * math.PI) / f64(segments)

		p0_2d := m.Vec2 {
			center_pt.x + circle.radius * math.cos(angle0),
			center_pt.y + circle.radius * math.sin(angle0),
		}
		p1_2d := m.Vec2 {
			center_pt.x + circle.radius * math.cos(angle1),
			center_pt.y + circle.radius * math.sin(angle1),
		}

		p0_3d := sketch.sketch_to_world(&sk.plane, p0_2d)
		p1_3d := sketch.sketch_to_world(&sk.plane, p1_2d)

		p0_f32 := [3]f32{f32(p0_3d.x), f32(p0_3d.y), f32(p0_3d.z)}
		p1_f32 := [3]f32{f32(p1_3d.x), f32(p1_3d.y), f32(p1_3d.z)}

		// Triangle: center, p0, p1
		append(&triangle_verts, v.LineVertex{center_f32})
		append(&triangle_verts, v.LineVertex{p0_f32})
		append(&triangle_verts, v.LineVertex{p1_f32})
	}

	if len(triangle_verts) == 0 do return

	// Create vertex buffer and render with transparency
	render_filled_triangles_gpu(app, cmd, pass, triangle_verts[:], mvp, {0.0, 1.0, 1.0, 0.2}) // Dark cyan, 20% opacity
}

// Render filled polygon with triangle fan
render_polygon_fill_gpu :: proc(
	app: ^AppStateGPU,
	cmd: ^sdl.GPUCommandBuffer,
	pass: ^sdl.GPURenderPass,
	sk: ^sketch.Sketch2D,
	point_ids: []int,
	mvp: matrix[4, 4]f32,
) {
	if len(point_ids) < 3 do return

	// Calculate centroid for triangle fan center
	centroid := m.Vec2{0, 0}
	for point_id in point_ids {
		pt := sketch.sketch_get_point(sk, point_id)
		if pt == nil do return
		centroid.x += pt.x
		centroid.y += pt.y
	}
	centroid.x /= f64(len(point_ids))
	centroid.y /= f64(len(point_ids))

	centroid_3d := sketch.sketch_to_world(&sk.plane, centroid)
	centroid_f32 := [3]f32{f32(centroid_3d.x), f32(centroid_3d.y), f32(centroid_3d.z)}

	// Generate triangle fan from centroid
	triangle_verts := make([dynamic]v.LineVertex, 0, len(point_ids) * 3)
	defer delete(triangle_verts)

	for i in 0 ..< len(point_ids) {
		j := (i + 1) % len(point_ids)

		pt_i := sketch.sketch_get_point(sk, point_ids[i])
		pt_j := sketch.sketch_get_point(sk, point_ids[j])
		if pt_i == nil || pt_j == nil do continue

		pos_i_2d := m.Vec2{pt_i.x, pt_i.y}
		pos_j_2d := m.Vec2{pt_j.x, pt_j.y}

		pos_i_3d := sketch.sketch_to_world(&sk.plane, pos_i_2d)
		pos_j_3d := sketch.sketch_to_world(&sk.plane, pos_j_2d)

		pos_i_f32 := [3]f32{f32(pos_i_3d.x), f32(pos_i_3d.y), f32(pos_i_3d.z)}
		pos_j_f32 := [3]f32{f32(pos_j_3d.x), f32(pos_j_3d.y), f32(pos_j_3d.z)}

		// Triangle: centroid, pt_i, pt_j
		append(&triangle_verts, v.LineVertex{centroid_f32})
		append(&triangle_verts, v.LineVertex{pos_i_f32})
		append(&triangle_verts, v.LineVertex{pos_j_f32})
	}

	if len(triangle_verts) == 0 do return

	// Render with transparency
	render_filled_triangles_gpu(app, cmd, pass, triangle_verts[:], mvp, {0.0, 1.0, 1.0, 0.2}) // Dark cyan, 20% opacity
}

// Helper to render filled triangles with transparency
render_filled_triangles_gpu :: proc(
	app: ^AppStateGPU,
	cmd: ^sdl.GPUCommandBuffer,
	pass: ^sdl.GPURenderPass,
	vertices: []v.LineVertex,
	mvp: matrix[4, 4]f32,
	color: [4]f32,
) {
	if len(vertices) == 0 do return

	// Create temporary vertex buffer
	buffer_info := sdl.GPUBufferCreateInfo {
		usage = {.VERTEX},
		size  = u32(len(vertices) * size_of(v.LineVertex)),
	}

	temp_vertex_buffer := sdl.CreateGPUBuffer(app.viewer.gpu_device, buffer_info)
	if temp_vertex_buffer == nil {
		fmt.eprintln("ERROR: Failed to create profile fill vertex buffer")
		return
	}
	defer sdl.ReleaseGPUBuffer(app.viewer.gpu_device, temp_vertex_buffer)

	// Upload vertex data via transfer buffer
	transfer_info := sdl.GPUTransferBufferCreateInfo {
		usage = .UPLOAD,
		size  = u32(len(vertices) * size_of(v.LineVertex)),
	}

	transfer_buffer := sdl.CreateGPUTransferBuffer(app.viewer.gpu_device, transfer_info)
	if transfer_buffer == nil {
		fmt.eprintln("ERROR: Failed to create transfer buffer for profile fill")
		return
	}
	defer sdl.ReleaseGPUTransferBuffer(app.viewer.gpu_device, transfer_buffer)

	// Map and copy vertex data
	transfer_ptr := sdl.MapGPUTransferBuffer(app.viewer.gpu_device, transfer_buffer, false)
	if transfer_ptr == nil {
		fmt.eprintln("ERROR: Failed to map transfer buffer for profile fill")
		return
	}

	dest_slice := ([^]v.LineVertex)(transfer_ptr)[:len(vertices)]
	copy(dest_slice, vertices)
	sdl.UnmapGPUTransferBuffer(app.viewer.gpu_device, transfer_buffer)

	// Upload to GPU
	upload_cmd := sdl.AcquireGPUCommandBuffer(app.viewer.gpu_device)
	copy_pass := sdl.BeginGPUCopyPass(upload_cmd)

	src := sdl.GPUTransferBufferLocation {
		transfer_buffer = transfer_buffer,
		offset          = 0,
	}

	dst := sdl.GPUBufferRegion {
		buffer = temp_vertex_buffer,
		offset = 0,
		size   = u32(len(vertices) * size_of(v.LineVertex)),
	}

	sdl.UploadToGPUBuffer(copy_pass, src, dst, false)
	sdl.EndGPUCopyPass(copy_pass)
	_ = sdl.SubmitGPUCommandBuffer(upload_cmd)

	// Wait for upload to complete
	_ = sdl.WaitForGPUIdle(app.viewer.gpu_device)

	// Switch to triangle pipeline
	sdl.BindGPUGraphicsPipeline(pass, app.viewer.triangle_pipeline)

	// Bind vertex buffer
	binding := sdl.GPUBufferBinding {
		buffer = temp_vertex_buffer,
		offset = 0,
	}
	sdl.BindGPUVertexBuffers(pass, 0, &binding, 1)

	// Draw triangles with transparency
	uniforms := v.Uniforms {
		mvp   = mvp,
		color = color,
	}
	sdl.PushGPUVertexUniformData(cmd, 0, &uniforms, size_of(v.Uniforms))
	sdl.PushGPUFragmentUniformData(cmd, 0, &uniforms, size_of(v.Uniforms))
	sdl.DrawGPUPrimitives(pass, u32(len(vertices)), 1, 0, 0)

	// Switch back to line pipeline
	sdl.BindGPUGraphicsPipeline(pass, app.viewer.pipeline)
}

// Render radius handle for selected circle (Week 12.3 - Task 2)
render_radius_handle_gpu :: proc(
	app: ^AppStateGPU,
	cmd: ^sdl.GPUCommandBuffer,
	pass: ^sdl.GPURenderPass,
	sk: ^sketch.Sketch2D,
	mvp: matrix[4, 4]f32,
) {
	// Only render radius handle if selected entity is a circle
	if sk.selected_entity < 0 || sk.selected_entity >= len(sk.entities) {
		return
	}

	entity := sk.entities[sk.selected_entity]
	circle, ok := entity.(sketch.SketchCircle)
	if !ok {
		return
	}

	// Get center point
	center_pt := sketch.sketch_get_point(sk, circle.center_id)
	if center_pt == nil {
		return
	}

	// Calculate radius handle position (rightmost point on circle)
	center_2d := m.Vec2{center_pt.x, center_pt.y}
	handle_2d := m.Vec2{center_2d.x + circle.radius, center_2d.y}

	// Render handle as a filled dot (similar to point rendering, but with distinct color)
	handle_color: [4]f32
	if app.hover_state.entity_type == .RadiusHandle {
		handle_color = {1.0, 1.0, 0.0, 1.0} // Yellow when hovered
	} else {
		handle_color = {1.0, 0.5, 0.0, 1.0} // Orange when not hovered
	}

	// Create a temporary point for rendering
	handle_pt := sketch.SketchPoint {
		id    = -1,
		x     = handle_2d.x,
		y     = handle_2d.y,
		fixed = false,
	}

	// Render handle dot (size 6px - slightly larger for visibility)
	v.viewer_gpu_render_single_point(app.viewer, cmd, pass, sk, &handle_pt, mvp, handle_color, 6.0)
}

// Render line endpoint handles for selected line (Week 12.3 - Task 3)
render_line_endpoint_handles_gpu :: proc(
	app: ^AppStateGPU,
	cmd: ^sdl.GPUCommandBuffer,
	pass: ^sdl.GPURenderPass,
	sk: ^sketch.Sketch2D,
	mvp: matrix[4, 4]f32,
) {
	// Only render endpoint handles if selected entity is a line
	if sk.selected_entity < 0 || sk.selected_entity >= len(sk.entities) {
		return
	}

	entity := sk.entities[sk.selected_entity]
	line, ok := entity.(sketch.SketchLine)
	if !ok {
		return
	}

	// Get both endpoint points
	start_pt := sketch.sketch_get_point(sk, line.start_id)
	end_pt := sketch.sketch_get_point(sk, line.end_id)
	if start_pt == nil || end_pt == nil {
		return
	}

	// Determine handle colors based on hover state
	start_color: [4]f32
	end_color: [4]f32

	// Check if hovering over either endpoint handle
	if app.hover_state.entity_type == .LineEndpointHandle {
		if app.hover_state.point_id == line.start_id {
			start_color = {1.0, 1.0, 0.0, 1.0} // Yellow when hovered
			end_color = {0.0, 1.0, 0.0, 1.0} // Green when not hovered
		} else if app.hover_state.point_id == line.end_id {
			start_color = {0.0, 1.0, 0.0, 1.0} // Green when not hovered
			end_color = {1.0, 1.0, 0.0, 1.0} // Yellow when hovered
		} else {
			start_color = {0.0, 1.0, 0.0, 1.0} // Green default
			end_color = {0.0, 1.0, 0.0, 1.0} // Green default
		}
	} else {
		start_color = {0.0, 1.0, 0.0, 1.0} // Green default
		end_color = {0.0, 1.0, 0.0, 1.0} // Green default
	}

	// Render start endpoint handle (size 6px)
	v.viewer_gpu_render_single_point(app.viewer, cmd, pass, sk, start_pt, mvp, start_color, 6.0)

	// Render end endpoint handle (size 6px)
	v.viewer_gpu_render_single_point(app.viewer, cmd, pass, sk, end_pt, mvp, end_color, 6.0)
}

// Helper to render a filled rectangle in screen space (for UI overlays)
render_filled_rect_gpu :: proc(
	app: ^AppStateGPU,
	cmd: ^sdl.GPUCommandBuffer,
	pass: ^sdl.GPURenderPass,
	x, y, width, height: f32,
	color: [4]f32,
	screen_width, screen_height: u32,
) {
	// Convert screen space to NDC [-1, 1]
	x_ndc := (2.0 * x) / f32(screen_width) - 1.0
	y_ndc := 1.0 - (2.0 * y) / f32(screen_height)
	width_ndc := (2.0 * width) / f32(screen_width)
	height_ndc := (2.0 * height) / f32(screen_height)

	// Create rectangle vertices (2 triangles forming a quad)
	vertices := [6]v.LineVertex {
		// First triangle (top-left, bottom-left, bottom-right)
		{{x_ndc, y_ndc, 0}},
		{{x_ndc, y_ndc - height_ndc, 0}},
		{{x_ndc + width_ndc, y_ndc - height_ndc, 0}},
		// Second triangle (top-left, bottom-right, top-right)
		{{x_ndc, y_ndc, 0}},
		{{x_ndc + width_ndc, y_ndc - height_ndc, 0}},
		{{x_ndc + width_ndc, y_ndc, 0}},
	}

	// Create temporary vertex buffer
	buffer_info := sdl.GPUBufferCreateInfo {
		usage = {.VERTEX},
		size  = u32(len(vertices) * size_of(v.LineVertex)),
	}

	temp_vertex_buffer := sdl.CreateGPUBuffer(app.viewer.gpu_device, buffer_info)
	if temp_vertex_buffer == nil {
		fmt.eprintln("ERROR: Failed to create rect vertex buffer")
		return
	}
	defer sdl.ReleaseGPUBuffer(app.viewer.gpu_device, temp_vertex_buffer)

	// Upload vertex data
	transfer_info := sdl.GPUTransferBufferCreateInfo {
		usage = .UPLOAD,
		size  = u32(len(vertices) * size_of(v.LineVertex)),
	}

	transfer_buffer := sdl.CreateGPUTransferBuffer(app.viewer.gpu_device, transfer_info)
	if transfer_buffer == nil do return
	defer sdl.ReleaseGPUTransferBuffer(app.viewer.gpu_device, transfer_buffer)

	transfer_ptr := sdl.MapGPUTransferBuffer(app.viewer.gpu_device, transfer_buffer, false)
	if transfer_ptr == nil do return

	dest_slice := ([^]v.LineVertex)(transfer_ptr)[:len(vertices)]
	copy(dest_slice, vertices[:])
	sdl.UnmapGPUTransferBuffer(app.viewer.gpu_device, transfer_buffer)

	// Upload to GPU
	upload_cmd := sdl.AcquireGPUCommandBuffer(app.viewer.gpu_device)
	copy_pass := sdl.BeginGPUCopyPass(upload_cmd)

	src := sdl.GPUTransferBufferLocation {
		transfer_buffer = transfer_buffer,
		offset          = 0,
	}

	dst := sdl.GPUBufferRegion {
		buffer = temp_vertex_buffer,
		offset = 0,
		size   = u32(len(vertices) * size_of(v.LineVertex)),
	}

	sdl.UploadToGPUBuffer(copy_pass, src, dst, false)
	sdl.EndGPUCopyPass(copy_pass)
	_ = sdl.SubmitGPUCommandBuffer(upload_cmd)

	// Wait for upload
	_ = sdl.WaitForGPUIdle(app.viewer.gpu_device)

	// Switch to triangle pipeline
	sdl.BindGPUGraphicsPipeline(pass, app.viewer.triangle_pipeline)

	// Bind vertex buffer
	binding := sdl.GPUBufferBinding {
		buffer = temp_vertex_buffer,
		offset = 0,
	}
	sdl.BindGPUVertexBuffers(pass, 0, &binding, 1)

	// Use identity matrix since we're already in NDC
	identity := matrix[4, 4]f32{
		1, 0, 0, 0,
		0, 1, 0, 0,
		0, 0, 1, 0,
		0, 0, 0, 1,
	}

	// Draw rectangle with color
	uniforms := v.Uniforms {
		mvp   = identity,
		color = color,
	}
	sdl.PushGPUVertexUniformData(cmd, 0, &uniforms, size_of(v.Uniforms))
	sdl.PushGPUFragmentUniformData(cmd, 0, &uniforms, size_of(v.Uniforms))
	sdl.DrawGPUPrimitives(pass, u32(len(vertices)), 1, 0, 0)

	// Switch back to line pipeline
	sdl.BindGPUGraphicsPipeline(pass, app.viewer.pipeline)
}
