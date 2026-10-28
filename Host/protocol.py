"""Wire encoding and CPU client; serial-like transport is injectable for tests."""
import time
from pathlib import Path
from Assembler.instr_to_bin import instr_to_bin

LOAD, POINTER_RESET, START, HALT, RESET = range(5)
MEMORY_BYTES = 2048


def load_packets(data: bytes):
    for offset in range(0, len(data), 255):
        part = data[offset:offset + 255]
        yield bytes((LOAD, len(part))) + part


def program_bytes(path: str | Path) -> bytes:
    path = Path(path)
    if path.suffix.lower() == ".bin":
        result = path.read_bytes()
    elif path.suffix.lower() in (".asm", ".hex", ".mem"):
        words = []
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            line = line.split("//", 1)[0].split("#", 1)[0].strip()
            if not line:
                continue
            try:
                if path.suffix.lower() == ".asm":
                    values = [int(instr_to_bin(line), 2)]
                else:
                    values = [int(word, 16) for word in line.split()]
                if any(not 0 <= value <= 65535 for value in values):
                    raise ValueError("word outside 0..65535")
                words.extend(values)
            except ValueError as error:
                raise ValueError(f"{path}:{number}: {error}") from error
        result = b"".join(word.to_bytes(2, "little") for word in words)
    else:
        raise ValueError("Expected .asm, .hex, .mem or .bin file")
    validate_program(result)
    return result


def validate_program(data: bytes):
    if not data or len(data) % 2 or len(data) > MEMORY_BYTES:
        raise ValueError("Program must contain 1..1024 complete 16-bit words")


class CPUClient:
    def __init__(self, transport):
        self.transport = transport
        self._rx_buffer = bytearray()

    def write(self, data: bytes):
        view = memoryview(data)
        while view:
            written = self.transport.write(view)
            if written is None or written <= 0 or written > len(view):
                raise OSError("Serial write made no valid progress")
            view = view[written:]
        self.transport.flush()

    def control(self, command: int):
        if command not in (POINTER_RESET, START, HALT, RESET):
            raise ValueError("Invalid control command")
        self.write(bytes((command,)))

    def load(self, data: bytes, start: bool = False):
        validate_program(data)  # Validate before changing board state.
        self.write(bytes((HALT, RESET, POINTER_RESET)))
        for packet in load_packets(data):
            self.write(packet)
        if start:
            self.control(START)

    def receive(self, timeout: float = 5.0) -> bytes:
        """Read one packet, retaining partial bytes across timeouts on this client."""
        deadline = time.monotonic() + timeout
        while True:
            buffer = self._rx_buffer
            if buffer and buffer[0] != 0:
                raise ValueError(f"Unknown device command 0x{buffer[0]:02x}; reset the board and reconnect")
            target = 1 if not buffer else 2 if len(buffer) == 1 else 2 + buffer[1]
            if len(buffer) >= 2 and len(buffer) == target:
                payload = bytes(buffer[2:])
                buffer.clear()
                return payload
            if time.monotonic() >= deadline:
                raise TimeoutError("Timed out waiting for a complete packet")
            buffer.extend(self.transport.read(target - len(buffer)))
