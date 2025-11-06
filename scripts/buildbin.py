#!/usr/bin/env python3
import argparse
import subprocess
import shutil
import sys

def main():
    parser = argparse.ArgumentParser(
        description="Convert ELF executable to flat binary using objcopy."
    )
    parser.add_argument("input", help="Input ELF executable file")
    parser.add_argument("output", help="Output flat binary file (.bin)")
    parser.add_argument(
        "-s", "--sections", nargs="*", help="Optional list of sections to include (e.g. .text .data)"
    )
    parser.add_argument(
        "--objcopy",
        default="objcopy",
        help="Path to objcopy (default: use system objcopy)"
    )

    args = parser.parse_args()

    # Check if objcopy exists
    if not shutil.which(args.objcopy):
        print(f"Error: '{args.objcopy}' not found in PATH", file=sys.stderr)
        sys.exit(1)

    # Build the objcopy command
    cmd = [args.objcopy, "-O", "binary"]

    # Include only specific sections if provided
    if args.sections:
        for section in args.sections:
            cmd += ["--only-section", section]

    cmd += [args.input, args.output]

    print("Running:", " ".join(cmd))

    try:
        subprocess.run(cmd, check=True)
        print(f"✅ Successfully created binary: {args.output}")
    except subprocess.CalledProcessError as e:
        print(f"❌ objcopy failed: {e}", file=sys.stderr)
        sys.exit(e.returncode)

if __name__ == "__main__":
    main()