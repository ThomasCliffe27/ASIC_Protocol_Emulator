import re


OPCODES = {
    "DELAY": 0x00,
    "LDI":   0x01,
    "SUB":   0x02,
    "JMPZ":  0x03,
    "SET":   0x04,
    "SEND":  0x06
}

# DELAY Rx uses a separate encoding; DELAY imm retains its original encoding.
REGISTER_DELAY_OPCODE = 0x05

def _register(token: str) -> int:
    if re.fullmatch(r"R[0-7]", token) is None:
        raise ValueError("Register must be R0-R7")
    return int(token[1:])


def instr_to_bin(line: str) -> str:
    line = line.split("//", 1)[0].split("#", 1)[0].strip().upper()
    parts = line.replace(",", " ").split()

    if not parts:
        raise ValueError("Empty instruction")

    mnemonic = parts[0]

    if mnemonic not in OPCODES:
        raise ValueError(f"Unknown instruction: {mnemonic}")

    opcode = OPCODES[mnemonic]
    reg = 0
    imm = 0

    if mnemonic == "DELAY":
        if len(parts) != 2:
            raise ValueError("Expected: DELAY imm or DELAY Rx")

        if parts[1].startswith("R"):
            opcode = REGISTER_DELAY_OPCODE
            reg = _register(parts[1])
        else:
            imm = int(parts[1], 0)

    elif mnemonic in ("LDI", "SUB"):
        if len(parts) != 3:
            raise ValueError(f"Expected: {mnemonic} Rx, imm")

        reg = _register(parts[1])
        imm = int(parts[2], 0)

    elif mnemonic in ("JMPZ", "SET", "SEND"):
        if len(parts) != 2:
            raise ValueError(f"Expected: {mnemonic} Rx")

        reg = _register(parts[1])

    if not 0 <= reg <= 7:
        raise ValueError("Register must be R0-R7")

    if not 0 <= imm <= 255:
        raise ValueError("Immediate must be 0-255")

    instruction = (opcode << 11) | (imm << 3) | reg

    return f"{instruction:016b}"
