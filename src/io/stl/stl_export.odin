// io/stl - STL Export Module
// Exports SimpleSolid triangle meshes to binary STL format
package ohcad_io_stl

import "core:fmt"
import "core:os"
import "core:encoding/endian"
import m "../../core/math"
import extrude "../../features/extrude"

// STL Export Result
STLExportResult :: struct {
	success: bool,
	message: string,
	filepath: string,
}

// Export a SimpleSolid to binary STL file
export_stl :: proc(solid: ^extrude.SimpleSolid, filepath: string) -> STLExportResult {
	result: STLExportResult
	result.filepath = filepath

	// Validate input
	if solid == nil {
		result.message = "Error: Solid is nil"
		return result
	}

	if len(solid.triangles) == 0 {
		result.message = "Error: Solid has no triangles to export"
		return result
	}

	// Create STL file
	file, err := os.open(filepath, os.O_WRONLY | os.O_CREATE | os.O_TRUNC, 0o644)
	if err != os.ERROR_NONE {
		result.message = fmt.aprintf("Error: Failed to create file '%s': %v", filepath, err)
		return result
	}
	defer os.close(file)

	// Write binary STL format
	if !write_binary_stl(file, solid) {
		result.message = "Error: Failed to write STL data"
		return result
	}

	result.success = true
	result.message = fmt.aprintf("✅ Exported %d triangles to '%s'", len(solid.triangles), filepath)

	fmt.println(result.message)
	return result
}

// Export all solids from feature tree to binary STL file
export_feature_tree_to_stl :: proc(features: []^extrude.SimpleSolid, filepath: string) -> STLExportResult {
	result: STLExportResult
	result.filepath = filepath

	if len(features) == 0 {
		result.message = "Error: No solids to export"
		return result
	}

	// Count total triangles
	total_triangles := 0
	for solid in features {
		if solid != nil {
			total_triangles += len(solid.triangles)
		}
	}

	if total_triangles == 0 {
		result.message = "Error: No triangles to export"
		return result
	}

	// Create STL file
	file, err := os.open(filepath, os.O_WRONLY | os.O_CREATE | os.O_TRUNC, 0o644)
	if err != os.ERROR_NONE {
		result.message = fmt.aprintf("Error: Failed to create file '%s': %v", filepath, err)
		return result
	}
	defer os.close(file)

	// Write binary STL header (80 bytes)
	header := [80]u8{}
	header_text := "OhCAD Binary STL Export"
	for i in 0..<min(len(header_text), 80) {
		header[i] = header_text[i]
	}
	os.write(file, header[:])

	// Write triangle count (4 bytes, little-endian)
	count_bytes: [4]u8
	endian.put_u32(count_bytes[:], .Little, u32(total_triangles))
	os.write(file, count_bytes[:])

	// Write all triangles from all solids
	for solid in features {
		if solid != nil {
			for tri in solid.triangles {
				write_stl_triangle(file, tri)
			}
		}
	}

	result.success = true
	result.message = fmt.aprintf("✅ Exported %d triangles from %d solids to '%s'",
		total_triangles, len(features), filepath)

	fmt.println(result.message)
	return result
}

// =============================================================================
// Internal Binary STL Writer
// =============================================================================

// Write binary STL format to file
write_binary_stl :: proc(file: os.Handle, solid: ^extrude.SimpleSolid) -> bool {
	// Binary STL format:
	// - 80 byte header (can be anything)
	// - 4 bytes: number of triangles (uint32, little-endian)
	// - For each triangle (50 bytes):
	//   - 12 bytes: normal vector (3 x float32)
	//   - 12 bytes: vertex 1 (3 x float32)
	//   - 12 bytes: vertex 2 (3 x float32)
	//   - 12 bytes: vertex 3 (3 x float32)
	//   - 2 bytes: attribute byte count (uint16, usually 0)

	// Write header (80 bytes)
	header := [80]u8{}
	header_text := "OhCAD Binary STL Export"
	for i in 0..<min(len(header_text), 80) {
		header[i] = header_text[i]
	}
	os.write(file, header[:])

	// Write triangle count (4 bytes, little-endian)
	count_bytes: [4]u8
	endian.put_u32(count_bytes[:], .Little, u32(len(solid.triangles)))
	os.write(file, count_bytes[:])

	// Write each triangle
	for tri in solid.triangles {
		if !write_stl_triangle(file, tri) {
			return false
		}
	}

	return true
}

// Write a single triangle in binary STL format (50 bytes)
write_stl_triangle :: proc(file: os.Handle, tri: extrude.Triangle3D) -> bool {
	// Normal vector (12 bytes: 3 x float32)
	write_vec3_f32(file, tri.normal)

	// Vertex 1 (12 bytes)
	write_vec3_f32(file, tri.v0)

	// Vertex 2 (12 bytes)
	write_vec3_f32(file, tri.v1)

	// Vertex 3 (12 bytes)
	write_vec3_f32(file, tri.v2)

	// Attribute byte count (2 bytes, usually 0)
	attr_bytes: [2]u8 = {0, 0}
	os.write(file, attr_bytes[:])

	return true
}

// Write a Vec3 as 3 x float32 (12 bytes, little-endian)
write_vec3_f32 :: proc(file: os.Handle, v: m.Vec3) {
	// Convert f64 to f32
	x := f32(v.x)
	y := f32(v.y)
	z := f32(v.z)

	// Write as little-endian float32
	x_bytes: [4]u8
	y_bytes: [4]u8
	z_bytes: [4]u8

	endian.put_f32(x_bytes[:], .Little, x)
	endian.put_f32(y_bytes[:], .Little, y)
	endian.put_f32(z_bytes[:], .Little, z)

	os.write(file, x_bytes[:])
	os.write(file, y_bytes[:])
	os.write(file, z_bytes[:])
}

// =============================================================================
// ASCII STL Writer (Optional - for debugging/readability)
// =============================================================================

// Write ASCII STL format (human-readable, larger files)
write_ascii_stl :: proc(file: os.Handle, solid: ^extrude.SimpleSolid) -> bool {
	// ASCII STL format:
	// solid name
	//   facet normal nx ny nz
	//     outer loop
	//       vertex x1 y1 z1
	//       vertex x2 y2 z2
	//       vertex x3 y3 z3
	//     endloop
	//   endfacet
	// endsolid name

	// Write header
	os.write_string(file, "solid OhCAD_Export\n")

	// Write each triangle
	for tri in solid.triangles {
		// Facet normal
		os.write_string(file, fmt.aprintf("  facet normal %.6e %.6e %.6e\n",
			tri.normal.x, tri.normal.y, tri.normal.z))

		os.write_string(file, "    outer loop\n")

		// Vertices
		os.write_string(file, fmt.aprintf("      vertex %.6e %.6e %.6e\n",
			tri.v0.x, tri.v0.y, tri.v0.z))
		os.write_string(file, fmt.aprintf("      vertex %.6e %.6e %.6e\n",
			tri.v1.x, tri.v1.y, tri.v1.z))
		os.write_string(file, fmt.aprintf("      vertex %.6e %.6e %.6e\n",
			tri.v2.x, tri.v2.y, tri.v2.z))

		os.write_string(file, "    endloop\n")
		os.write_string(file, "  endfacet\n")
	}

	// Write footer
	os.write_string(file, "endsolid OhCAD_Export\n")

	return true
}

// Export solid to ASCII STL (for debugging/readability)
export_stl_ascii :: proc(solid: ^extrude.SimpleSolid, filepath: string) -> STLExportResult {
	result: STLExportResult
	result.filepath = filepath

	if solid == nil {
		result.message = "Error: Solid is nil"
		return result
	}

	if len(solid.triangles) == 0 {
		result.message = "Error: Solid has no triangles to export"
		return result
	}

	file, err := os.open(filepath, os.O_WRONLY | os.O_CREATE | os.O_TRUNC, 0o644)
	if err != os.ERROR_NONE {
		result.message = fmt.aprintf("Error: Failed to create file '%s': %v", filepath, err)
		return result
	}
	defer os.close(file)

	if !write_ascii_stl(file, solid) {
		result.message = "Error: Failed to write ASCII STL data"
		return result
	}

	result.success = true
	result.message = fmt.aprintf("✅ Exported %d triangles to ASCII '%s'", len(solid.triangles), filepath)

	fmt.println(result.message)
	return result
}
