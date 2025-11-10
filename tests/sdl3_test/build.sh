#!/bin/bash

# Build script for SDL3 test program

echo "Building SDL3 test program..."
odin build . -out:sdl3_test -debug

if [ $? -eq 0 ]; then
    echo "✓ Build successful: sdl3_test"
    echo ""
    echo "Run with: ./sdl3_test"
else
    echo "❌ Build failed"
    exit 1
fi
