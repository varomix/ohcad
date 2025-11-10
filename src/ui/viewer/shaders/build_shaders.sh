#!/bin/bash
# Build script for compiling Metal shaders to .metallib format

echo "=== OhCAD Metal Shader Compilation ==="
echo ""

SHADER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
METAL_FILE="$SHADER_DIR/line_shader.metal"
AIR_FILE="$SHADER_DIR/line_shader.air"
METALLIB_FILE="$SHADER_DIR/line_shader.metallib"

# Check if metal shader file exists
if [ ! -f "$METAL_FILE" ]; then
    echo "ERROR: Metal shader file not found: $METAL_FILE"
    exit 1
fi

echo "Compiling Metal shader..."
echo "  Input:  $METAL_FILE"
echo ""

# Step 1: Compile .metal to .air (Metal intermediate representation)
echo "[1/2] Compiling to AIR format..."
xcrun -sdk macosx metal -c "$METAL_FILE" -o "$AIR_FILE"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to compile Metal shader to AIR"
    exit 1
fi

echo "  ✓ Created: $AIR_FILE"

# Step 2: Link .air to .metallib (Metal library)
echo "[2/2] Linking to metallib..."
xcrun -sdk macosx metallib "$AIR_FILE" -o "$METALLIB_FILE"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to link AIR to metallib"
    rm -f "$AIR_FILE"
    exit 1
fi

echo "  ✓ Created: $METALLIB_FILE"

# Clean up intermediate file
rm -f "$AIR_FILE"

echo ""
echo "✓ Metal shader compilation successful!"
echo "  Output: $METALLIB_FILE"
echo ""

# Show file size
ls -lh "$METALLIB_FILE" | awk '{print "  Size: " $5}'

echo ""
echo "To use in Odin:"
echo "  1. Load metallib file at runtime"
echo "  2. Get vertex/fragment functions by name:"
echo "     - vertex_main"
echo "     - fragment_main"
