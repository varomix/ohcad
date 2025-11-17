#!/bin/bash
#
# Build OCCT C Wrapper
# Creates libocct_wrapper.dylib for use with Odin FFI
#

set -e  # Exit on error

echo "=== Building OCCT C Wrapper ==="
echo

# Configuration
WRAPPER_DIR="src/core/geometry/occt"
OCCT_INCLUDE="/opt/homebrew/include/opencascade"
OCCT_LIB="/opt/homebrew/lib"
OUTPUT_LIB="$WRAPPER_DIR/libocct_wrapper.dylib"

# Required OCCT libraries (in dependency order - order matters!)
OCCT_LIBS=(
    "-lTKernel"       # Foundation (must be first)
    "-lTKMath"        # Math utilities
    "-lTKG2d"         # 2D geometry
    "-lTKG3d"         # 3D geometry
    "-lTKGeomBase"    # Geometry base
    "-lTKBRep"        # B-Rep topology
    "-lTKGeomAlgo"    # Geometry algorithms
    "-lTKTopAlgo"     # Topology algorithms
    "-lTKShHealing"   # Shape healing
    "-lTKPrim"        # Primitives (box, cylinder, etc.)
    "-lTKBO"          # Boolean operations (base)
    "-lTKBool"        # Boolean operations (algorithms)
    "-lTKFeat"        # Features (extrude, revolve, etc.)
    "-lTKMesh"        # Mesh generation (tessellation)
    "-lTKOffset"      # Offset operations
    "-lTKFillet"      # Fillets and chamfers
)

# Compiler flags
CXXFLAGS="-std=c++17 -fPIC -O2 -Wall"
LDFLAGS="-shared -Wl,-rpath,$OCCT_LIB"

# Check if OCCT is installed
if [ ! -d "$OCCT_INCLUDE" ]; then
    echo "ERROR: OCCT headers not found at $OCCT_INCLUDE"
    echo "Install OCCT: brew install opencascade"
    exit 1
fi

# Build wrapper
echo "Compiling wrapper..."
clang++ $CXXFLAGS \
    -I"$OCCT_INCLUDE" \
    -c "$WRAPPER_DIR/occt_c_wrapper.cpp" \
    -o "$WRAPPER_DIR/occt_c_wrapper.o"

if [ $? -ne 0 ]; then
    echo "ERROR: Compilation failed"
    exit 1
fi

echo "Linking shared library..."
clang++ $LDFLAGS \
    -L"$OCCT_LIB" \
    "${OCCT_LIBS[@]}" \
    "$WRAPPER_DIR/occt_c_wrapper.o" \
    -o "$OUTPUT_LIB"

if [ $? -ne 0 ]; then
    echo "ERROR: Linking failed"
    rm -f "$WRAPPER_DIR/occt_c_wrapper.o"
    exit 1
fi

# Clean up object file
rm -f "$WRAPPER_DIR/occt_c_wrapper.o"

# Verify library
if [ ! -f "$OUTPUT_LIB" ]; then
    echo "ERROR: Library not created"
    exit 1
fi

# Print library info
echo
echo "✓ Successfully built: $OUTPUT_LIB"
echo
echo "Library info:"
file "$OUTPUT_LIB"
echo
echo "Linked OCCT libraries:"
otool -L "$OUTPUT_LIB" | grep -i "TK" | sed 's/^/  /'
echo
echo "=== Build Complete ==="
