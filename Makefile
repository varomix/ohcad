# OhCAD Makefile
# Build system for the Odin CAD project

# Odin compiler
ODIN := odin

# Output directories
BUILD_DIR := build
BIN_DIR := bin

# Application name
APP_NAME := ohcad

# Source directories
SRC_DIR := src
TEST_DIR := tests

# Build flags
RELEASE_FLAGS := -o:speed -no-bounds-check
DEBUG_FLAGS := -debug -o:minimal
TEST_FLAGS := -all-packages

# Default target
.PHONY: all
all: release

# Release build
.PHONY: release
release:
	@echo "Building OhCAD (Release)..."
	@mkdir -p $(BIN_DIR)
	$(ODIN) build $(SRC_DIR) -out:$(BIN_DIR)/$(APP_NAME) $(RELEASE_FLAGS)
	@echo "✓ Build complete: $(BIN_DIR)/$(APP_NAME)"

# Debug build
.PHONY: debug
debug:
	@echo "Building OhCAD (Debug)..."
	@mkdir -p $(BIN_DIR)
	$(ODIN) build $(SRC_DIR) -out:$(BIN_DIR)/$(APP_NAME)_debug $(DEBUG_FLAGS)
	@echo "✓ Debug build complete: $(BIN_DIR)/$(APP_NAME)_debug"

# Run the application
.PHONY: run
run: release
	@echo "Running OhCAD..."
	@./$(BIN_DIR)/$(APP_NAME)

# Build viewer test
.PHONY: viewer
viewer:
	@echo "Building Viewer Test..."
	@mkdir -p $(BIN_DIR)
	$(ODIN) build src/viewer_test.odin -file -out:$(BIN_DIR)/viewer_test
	@echo "✓ Viewer test complete: $(BIN_DIR)/viewer_test"

# Run viewer test
.PHONY: run-viewer
run-viewer: viewer
	@echo "Running Viewer Test..."
	@./$(BIN_DIR)/viewer_test

# Build GPU viewer test
.PHONY: gpu-viewer
gpu-viewer:
	@echo "Building GPU Viewer Test..."
	@mkdir -p $(BIN_DIR)
	$(ODIN) build $(TEST_DIR)/gpu_viewer_test -out:$(BIN_DIR)/gpu_viewer_test $(DEBUG_FLAGS)
	@echo "✓ GPU Viewer test complete: $(BIN_DIR)/gpu_viewer_test"

# Run GPU viewer test
.PHONY: run-gpu-viewer
run-gpu-viewer: gpu-viewer
	@echo "Running GPU Viewer Test..."
	@./$(BIN_DIR)/gpu_viewer_test

# Build SDL3 GPU main application
.PHONY: gpu
gpu:
	@echo "Building OhCAD (SDL3 GPU)..."
	@mkdir -p $(BIN_DIR)
	$(ODIN) build src/main_gpu.odin -file -out:$(BIN_DIR)/ohcad_gpu $(DEBUG_FLAGS)
	@echo "✓ SDL3 GPU build complete: $(BIN_DIR)/ohcad_gpu"

# Run SDL3 GPU main application
.PHONY: run-gpu
run-gpu: gpu
	@echo "Running OhCAD (SDL3 GPU)..."
	@./$(BIN_DIR)/ohcad_gpu

# Run debug version
.PHONY: run-debug
run-debug: debug
	@echo "Running OhCAD (Debug)..."
	@./$(BIN_DIR)/$(APP_NAME)_debug

# Run tests
.PHONY: test
test:
	@echo "Running tests..."
	$(ODIN) test $(TEST_DIR) $(TEST_FLAGS)

# Run specific test package
.PHONY: test-math
test-math:
	@echo "Running math tests..."
	$(ODIN) test tests/math $(TEST_FLAGS)

.PHONY: test-geometry
test-geometry:
	@echo "Running geometry tests..."
	$(ODIN) test tests/geometry $(TEST_FLAGS)

.PHONY: test-topology
test-topology:
	@echo "Running topology tests..."
	$(ODIN) test tests/topology $(TEST_FLAGS)

# Check for syntax errors without building
.PHONY: check
check:
	@echo "Checking syntax..."
	$(ODIN) check $(SRC_DIR)
	@echo "✓ No syntax errors"

# Clean build artifacts
.PHONY: clean
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BIN_DIR)
	@rm -rf $(BUILD_DIR)
	@echo "✓ Clean complete"

# Generate documentation (future)
.PHONY: docs
docs:
	@echo "TODO: Generate documentation"

# Install (copy to system location)
.PHONY: install
install: release
	@echo "Installing OhCAD to /usr/local/bin..."
	@sudo cp $(BIN_DIR)/$(APP_NAME) /usr/local/bin/
	@echo "✓ Installation complete"

# Uninstall
.PHONY: uninstall
uninstall:
	@echo "Uninstalling OhCAD from /usr/local/bin..."
	@sudo rm -f /usr/local/bin/$(APP_NAME)
	@echo "✓ Uninstall complete"

# Help
.PHONY: help
help:
	@echo "OhCAD Build System"
	@echo ""
	@echo "Targets:"
	@echo "  all          - Build release version (default)"
	@echo "  release      - Build optimized release version"
	@echo "  debug        - Build debug version with symbols"
	@echo "  run          - Build and run release version"
	@echo "  run-debug    - Build and run debug version"
	@echo "  test         - Run all tests"
	@echo "  test-math    - Run math tests only"
	@echo "  test-geometry- Run geometry tests only"
	@echo "  test-topology- Run topology tests only"
	@echo "  check        - Check syntax without building"
	@echo "  clean        - Remove build artifacts"
	@echo "  install      - Install to /usr/local/bin"
	@echo "  uninstall    - Remove from /usr/local/bin"
	@echo "  help         - Show this help message"
