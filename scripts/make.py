import os
import subprocess
import argparse

# ---------------- Configuration ----------------
# Set FREESTANDING to 1 for freestanding (no libc), 0 for normal
FREESTANDING = 1
# ------------------------------------------------

def compile_sources(input_folder, output_file):
    c_files = []
    asm_files = []

    # Walk through all subfolders for source files
    for root, dirs, files in os.walk(input_folder):
        for f in files:
            full_path = os.path.join(root, f)
            if f.endswith(".c"):
                c_files.append(full_path)
            elif f.endswith((".s", ".S")):
                asm_files.append(full_path)

    all_sources = c_files + asm_files

    if not all_sources:
        print(f"No C or assembly files found in {input_folder}")
        return

    # Base GCC command
    gcc_cmd = ["gcc", "-march=armv8-a", "-o", output_file]

    # Freestanding options
    if FREESTANDING == 1:
        gcc_cmd += ["-ffreestanding", "-nostdlib", "-nostartfiles" "-T", "./link.ld"]

    # Add source files
    gcc_cmd += all_sources

    print("Running command:", " ".join(gcc_cmd))

    # Execute the compilation
    result = subprocess.run(gcc_cmd, capture_output=True, text=True)

    if result.returncode == 0:
        print(f"Successfully compiled to {output_file}")
    else:
        print("Compilation failed:")
        print(result.stdout)
        print(result.stderr)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Compile ARM64 C/assembly sources with optional freestanding mode")
    parser.add_argument("input_folder", help="Folder containing .c, .s/.S sources, and optionally a linker script")
    parser.add_argument("output_file", help="Output ELF executable file")
    
    args = parser.parse_args()
    compile_sources(args.input_folder, args.output_file)
