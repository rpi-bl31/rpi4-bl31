# ===============================================
# Makefile for BL31 using Python scripts
# Ensures proper order: build -> flat binary
# ===============================================

# Use the right Python interpreter
PYTHON := python3

# Directories
SRC_DIR := ..
BUILD_DIR := build

# Script arguments
MAKE_ARGS := . $(BUILD_DIR)/bl31.elf
FLAT_ARGS := $(BUILD_DIR)/bl31.elf $(BUILD_DIR)/bl31.bin -s .text .bss .data .rodata

# Phony targets
.PHONY: all build flat clean

# Default target
all: flat

# Step 1: Build everything into a single executable
build:
	mkdir -p build
	@echo "=== Building BL31 ELF ==="
	$(PYTHON) $(SRC_DIR)/make.py $(MAKE_ARGS)

# Step 2: Convert the ELF into a flat binary
flat: build
	@echo "=== Converting to flat binary ==="
	$(PYTHON) $(SRC_DIR)/buildbin.py $(FLAT_ARGS)
	rm build/bl31.elf

# Optional: clean build directory
clean:
	@echo "=== Cleaning build directory ==="
	rm -rf $(BUILD_DIR)
	mkdir -p $(BUILD_DIR)
