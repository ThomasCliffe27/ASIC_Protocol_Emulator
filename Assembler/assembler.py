"""Assemble one 16-bit text hexadecimal word per line for $readmemh."""

import argparse
from os import PathLike
from pathlib import Path

if __package__:
    from .instr_to_bin import instr_to_bin
else:
    from instr_to_bin import instr_to_bin

def assemble(inputFile: str | PathLike[str], outputFile: str | PathLike[str]) -> None:
    words = []

    with open(inputFile, "r", encoding="utf-8") as f:
        for line_number, line in enumerate(f, start=1):
            line = line.split("//", 1)[0].split("#", 1)[0].strip()

            if line:
                try:
                    words.append(f"{int(instr_to_bin(line), 2):04X}\n")
                except ValueError as error:
                    raise ValueError(f"{inputFile}:{line_number}: {error}") from error

    # Parse the complete source before opening the output, preserving any
    # existing program if an instruction is invalid.
    with open(outputFile, "w", encoding="ascii", newline="\n") as f:
        f.writelines(words)


if __name__ == "__main__":
    project_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", nargs="?", type=Path,
                        default=project_root / "Programs" / "test.asm")
    parser.add_argument("output", nargs="?", type=Path)
    args = parser.parse_args()
    output_file = args.output if args.output is not None else args.input.with_suffix(".hex")
    try:
        assemble(args.input, output_file)
    except (OSError, ValueError) as error:
        parser.exit(1, f"{error}\n")
