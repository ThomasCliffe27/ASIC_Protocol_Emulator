from instr_to_bin import instr_to_bin

def assemble(inputFile: str, outputFile: str) -> None:
    binary_instructions = []

    with open(inputFile, "r") as f:
        for line in f:
            line = line.strip()

            if line and not line.startswith("//"):
                binary_instructions.append(instr_to_bin(line))

    with open(outputFile, "wb") as f:
        for instr in binary_instructions:
            f.write(int(instr, 2).to_bytes(2))


if __name__ == "__main__":
    input_file = r"Programs\test.asm"
    output_file = r"Programs\test.hex"

    assemble(input_file, output_file)
