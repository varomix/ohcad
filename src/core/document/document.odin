// OhCAD - Document Settings and Units
package document

import "core:fmt"
import "core:strconv"

// =============================================================================
// Unit System
// =============================================================================

// Unit types supported by the application
Unit :: enum {
	Millimeters,
	Inches,
}

// Get the display abbreviation for a unit
unit_abbreviation :: proc(unit: Unit) -> string {
	switch unit {
	case .Millimeters:
		return "mm"
	case .Inches:
		return "in"
	}
	return ""
}

// Get the full name of a unit
unit_name :: proc(unit: Unit) -> string {
	switch unit {
	case .Millimeters:
		return "Millimeters"
	case .Inches:
		return "Inches"
	}
	return ""
}

// =============================================================================
// Unit Conversion
// =============================================================================

// Conversion factor: 1 inch = 25.4 mm
MM_PER_INCH :: 25.4

// Convert a value from one unit to another
unit_convert :: proc(value: f64, from: Unit, to: Unit) -> f64 {
	if from == to do return value

	switch from {
	case .Millimeters:
		// MM to Inches
		return value / MM_PER_INCH
	case .Inches:
		// Inches to MM
		return value * MM_PER_INCH
	}

	return value
}

// Convert to internal units (we'll use millimeters as internal representation)
unit_to_internal :: proc(value: f64, from: Unit) -> f64 {
	return unit_convert(value, from, .Millimeters)
}

// Convert from internal units to display units
unit_from_internal :: proc(value: f64, to: Unit) -> f64 {
	return unit_convert(value, .Millimeters, to)
}

// Format a value with unit abbreviation
unit_format :: proc(value: f64, unit: Unit, decimal_places: int = 2) -> string {
	format_str := fmt.tprintf("%%.%df %%s", decimal_places)
	return fmt.tprintf(format_str, value, unit_abbreviation(unit))
}

// =============================================================================
// Document Settings
// =============================================================================

// Document-level settings
DocumentSettings :: struct {
	units:          Unit, // Current unit system
	decimal_places: int, // Number of decimal places for display
}

// Create default document settings
document_settings_default :: proc() -> DocumentSettings {
	return DocumentSettings{units = .Millimeters, decimal_places = 2}
}

// Set the unit system for the document
document_settings_set_units :: proc(settings: ^DocumentSettings, units: Unit) {
	settings.units = units
	fmt.printf("✓ Document units set to: %s\n", unit_name(units))
}

// Set decimal places for display
document_settings_set_decimal_places :: proc(settings: ^DocumentSettings, places: int) {
	settings.decimal_places = max(0, min(places, 6)) // Clamp to 0-6
}

// Format a value according to document settings
document_format_value :: proc(settings: ^DocumentSettings, value: f64) -> string {
	display_value := unit_from_internal(value, settings.units)
	return unit_format(display_value, settings.units, settings.decimal_places)
}

// Parse a value from user input (returns value in internal units)
document_parse_value :: proc(
	settings: ^DocumentSettings,
	input: string,
) -> (
	value: f64,
	ok: bool,
) {
	// TODO: Implement more sophisticated parsing with unit detection
	// For now, just parse as float and assume it's in document units

	parsed, parse_ok := strconv.parse_f64(input)
	if !parse_ok do return 0, false

	// Convert to internal units
	internal_value := unit_to_internal(parsed, settings.units)
	return internal_value, true
}
