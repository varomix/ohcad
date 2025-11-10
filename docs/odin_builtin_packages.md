# Odin Built-in Packages for CAD Development

This document catalogs the Odin built-in packages we can leverage to accelerate development of the CAD system.

---

## Core Math & Linear Algebra

### `core:math/linalg/glsl`
**Location:** `/Users/varomix/dev/ODIN_DEV/Odin/core/math/linalg/glsl`

**Provides:**
- ✅ **Vector Types**: `vec2`, `vec3`, `vec4` (f32) and `dvec2`, `dvec3`, `dvec4` (f64)
- ✅ **Matrix Types**: `mat2`, `mat3`, `mat4` (f32) and `dmat2`, `dmat3`, `dmat4` (f64)
- ✅ **Quaternions**: `quat` (f32) and `dquat` (f64)
- ✅ **Vector Operations**: dot, cross, normalize, length, distance, reflect
- ✅ **Matrix Operations**:
  - inverse, transpose, determinant, adjugate, cofactor
  - perspective, orthographic, lookAt projection matrices
  - rotate, translate, scale transformation matrices
  - matrix-from-quaternion conversion
- ✅ **Math Utilities**: min, max, clamp, lerp, mix, smoothstep, step, saturate
- ✅ **Trig Functions**: sin, cos, tan, asin, acos, atan, atan2
- ✅ **Quaternion Operations**: slerp, nlerp, axis-angle construction
- ✅ **Constants**: `PI`, `TAU`, `E`, `F32_EPSILON`, `F64_EPSILON`

**Usage for CAD:**
- Use `dvec2`, `dvec3`, `dmat4` for all CAD geometry (f64 precision)
- Built-in tolerance constants (`F64_EPSILON`) for comparisons
- Transformation matrices for view/projection in viewer
- All basic vector/matrix operations we need

**What We Still Need to Implement:**
- CAD-specific tolerance management (configurable epsilon)
- `is_near(a, b, eps)` wrappers for robust comparisons
- Point-on-plane projection
- Line-line intersection (2D/3D)
- Plane-plane intersection
- Geometric predicates specific to B-rep operations

---

## Graphics & Windowing

### `vendor:glfw`
**Location:** `/Users/varomix/dev/ODIN_DEV/Odin/vendor/glfw`

**Provides:**
- ✅ Window creation and management
- ✅ OpenGL context creation
- ✅ Input handling (mouse, keyboard, gamepad)
- ✅ Monitor and display management
- ✅ Cursor control
- ✅ Event callbacks (key, mouse, window resize, etc.)
- ✅ Clipboard access
- ✅ Timing functions

**Usage for CAD:**
- Week 3: Window and OpenGL context for 3D viewer
- Mouse input for camera orbit/pan/zoom
- Keyboard shortcuts for CAD operations
- Window resize handling for viewport

### `vendor:OpenGL`
**Location:** `/Users/varomix/dev/ODIN_DEV/Odin/vendor/OpenGL`

**Provides:**
- ✅ Complete OpenGL bindings (modern GL)
- ✅ Helper functions and wrappers
- ✅ Enum definitions for all GL constants

**Usage for CAD:**
- 3D rendering of B-rep solids (wireframe, shaded)
- 2D sketch overlay rendering
- Line drawing for technical drawings
- Shader compilation and management

---

## File I/O & Serialization

### `core:encoding/json`
**Location:** `/Users/varomix/dev/ODIN_DEV/Odin/core/encoding/json`

**Provides:**
- ✅ JSON parsing (unmarshal)
- ✅ JSON generation (marshal)
- ✅ JSON validation
- ✅ Tokenizer for custom parsing

**Usage for CAD:**
- Save/load project files
- Export/import sketch data
- Configuration files
- Feature parameter serialization

### `core:os`
**Standard file I/O operations**

**Provides:**
- ✅ File reading/writing
- ✅ Directory operations
- ✅ Path manipulation
- ✅ File metadata (exists, size, permissions)

**Usage for CAD:**
- STL file export (binary/ASCII)
- SVG/PDF export
- Model file loading/saving

### `core:encoding/xml`
**For STEP/IGES file formats (future)**

**Provides:**
- ✅ XML parsing and tokenization
- ✅ Helper functions for XML navigation

### `core:encoding/csv`
**For exporting dimension tables or part lists**

---

## Imaging & Graphics Utilities

### `vendor:stb/image`
**Location:** `/Users/varomix/dev/ODIN_DEV/Odin/vendor/stb/image`

**Provides:**
- ✅ Image loading (PNG, JPG, BMP, TGA, etc.)
- ✅ Image writing (PNG, BMP, TGA, JPG)
- ✅ Image resizing

**Usage for CAD:**
- Load textures for UI elements
- Export rendered views as images
- Icon loading for toolbar

### `vendor:stb/truetype`
**TrueType font rendering**

**Provides:**
- ✅ Font loading and rendering
- ✅ Glyph rasterization
- ✅ Font metrics

**Usage for CAD:**
- Text rendering for dimensions and annotations
- UI text rendering
- Technical drawing labels

### `vendor:stb/rect_pack`
**Rectangle packing for texture atlases**

**Usage for CAD:**
- Font atlas generation for text rendering
- UI icon atlas packing

---

## Data Structures & Containers

### `core:container/queue`
**FIFO queue implementation**

**Usage for CAD:**
- Feature regeneration queue
- Command history for undo/redo

### `core:container/priority_queue`
**Heap-based priority queue**

**Usage for CAD:**
- Spatial indexing queries
- Nearest-neighbor searches

### `core:container/small_array`
**Stack-allocated small arrays**

**Usage for CAD:**
- Efficient small collections (e.g., face edges, typically 3-6 items)
- Avoid allocations for small topology queries

### `core:slice`
**Slice manipulation utilities**

**Usage for CAD:**
- Dynamic array operations for geometry collections
- Efficient memory management

---

## Testing & Development

### `core:testing`
**Built-in testing framework**

**Provides:**
- ✅ Test runner
- ✅ Assertions (expect, expect_value, etc.)
- ✅ Test organization and reporting

**Usage for CAD:**
- Unit tests for all math/geometry functions
- Integration tests for features
- Regression tests for topology operations

**Example:**
```odin
package test_math

import "core:testing"
import "core:math/linalg/glsl"

@(test)
test_point_on_plane :: proc(t: ^testing.T) {
    plane := Plane{origin = {0, 0, 0}, normal = {0, 1, 0}}
    point := glsl.dvec3{1, 5, 2}

    projected := project_point_on_plane(point, plane)

    testing.expect_value(t, projected.y, 0.0)
    testing.expect_value(t, projected.x, point.x)
    testing.expect_value(t, projected.z, point.z)
}
```

### `core:log`
**Structured logging**

**Provides:**
- ✅ Log levels (debug, info, warn, error)
- ✅ Formatted output
- ✅ Custom loggers

**Usage for CAD:**
- Debug logging for solver convergence
- Error reporting for boolean operations
- Performance profiling logs

---

## String & Text Processing

### `core:strings`
**String manipulation utilities**

**Usage for CAD:**
- Filename handling
- String building for export formats
- Text parsing for file import

### `core:fmt`
**Formatted printing (like printf)**

**Usage for CAD:**
- Debug output
- Export file formatting (STL ASCII, SVG text)
- Error messages

---

## Memory Management

### `core:mem`
**Memory allocators and utilities**

**Provides:**
- ✅ Arena allocator (fast bump allocator)
- ✅ Pool allocator
- ✅ Tracking allocator (for leak detection)
- ✅ Scratch allocator

**Usage for CAD:**
- Arena allocator for temporary geometry during boolean operations
- Pool allocator for topology handles
- Tracking allocator during development to detect leaks

---

## Other Useful Packages

### `core:compress/zlib`
**Compression for file formats**

**Usage for CAD:**
- Compressed project file storage
- Efficient large model serialization

### `core:time`
**Time and duration utilities**

**Usage for CAD:**
- Performance profiling
- Timestamp for file versioning
- Animation/interpolation timing

### `core:math`
**Additional math utilities beyond linalg**

**Provides:**
- ✅ Constants and basic functions
- ✅ Random number generation
- ✅ Noise functions

### `core:hash`
**Hashing functions**

**Usage for CAD:**
- Geometry hashing for deduplication
- Fast equality checks for topology
- Hash maps for handle lookups

---

## Summary: What Odin Provides vs What We Build

### ✅ **Odin Provides (Ready to Use):**
1. **Complete linear algebra** - vectors, matrices, quaternions, all operations
2. **Window system** - GLFW with full OpenGL support
3. **File I/O** - reading, writing, path manipulation
4. **Serialization** - JSON, XML, CSV, binary
5. **Image handling** - load/save images, font rendering
6. **Testing framework** - comprehensive unit testing
7. **Data structures** - queues, priority queues, arrays
8. **Memory management** - various allocator types
9. **Logging** - structured logging system
10. **String utilities** - formatting, manipulation

### 🔨 **What We Need to Implement:**
1. **CAD-specific geometry** - primitives (Line2, Circle2, Plane, etc.)
2. **Topology system** - B-rep structures, handles, Euler operators
3. **Constraint solver** - 2D sketch constraint solving
4. **Boolean operations** - CSG and B-rep booleans
5. **Feature system** - extrude, revolve, fillet, parametric tree
6. **Sketcher** - 2D drawing and editing
7. **Technical drawing** - projection, hidden line removal, dimensions
8. **File formats** - STL, SVG, PDF export (STEP later)
9. **UI/Viewer** - 3D viewport with camera controls
10. **CAD-specific utilities** - tolerance management, geometric predicates

---

## Updated Week 1 Plan Based on Available Packages

**Revised Week 1 Tasks:**

```odin
// Project structure leveraging Odin packages

package ohcad

import gl "vendor:OpenGL"
import "vendor:glfw"
import "core:math/linalg/glsl"
import "core:encoding/json"
import "core:os"
import "core:testing"
import "core:log"
import "core:mem"

// Type aliases using Odin's built-in types
Vec2 :: glsl.dvec2
Vec3 :: glsl.dvec3
Mat3 :: glsl.dmat3
Mat4 :: glsl.dmat4

// CAD-specific constants and utilities
CAD_TOLERANCE :: 1e-9  // Configurable for model

// Only implement what Odin doesn't provide
is_near :: proc(a, b, eps: f64) -> bool { ... }
project_point_on_plane :: proc(p: Vec3, plane: Plane) -> Vec3 { ... }
line_line_intersect_2d :: proc(l1, l2: Line2) -> (Vec2, bool) { ... }
```

**Time Savings:**
- **Week 1:** ~60% time saved (no need to implement basic math)
- **Week 3:** ~40% time saved (GLFW/OpenGL already integrated)
- **Throughout:** Robust testing framework, logging, and memory management ready to use

This is **exactly** the kind of foundation that makes Odin excellent for systems programming!
