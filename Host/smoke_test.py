"""Opt-in board test: overwrites program RAM; leaves CPU halted.

Run only after configuring the current bitstream:
python -m Host.smoke_test --port COM4
"""
import argparse
import serial
from .protocol import CPUClient, START, HALT, RESET


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", required=True)
    args = parser.parse_args()
    # Emit TC once, then loop at word 6. Fill all RAM to exercise 255-byte splits.
    words = [0x0AA0, 0x3000, 0x0A18, 0x3000, 0x0831, 0x1002, 0x1801]
    words += [0] * (1024-len(words))
    data = b"".join(word.to_bytes(2, "little") for word in words)
    with serial.Serial(args.port, 115200, timeout=0.05, write_timeout=5) as port:
        client = CPUClient(port)
        try:
            client.load(data, start=True)
            assert client.receive() == b"T", "First SEND mismatch"
            assert client.receive() == b"C", "Second SEND mismatch"
            client.control(HALT)
            client.control(START)
            assert port.read(1) == b"", "Resume unexpectedly restarted program"
            client.control(RESET)
            client.control(START)
            assert client.receive() == b"T", "Reset did not retain program"
            assert client.receive() == b"C", "Reset/restart second SEND mismatch"
            print("PASS: 2048-byte upload, split packets, SEND TC, halt/resume, reset retains RAM")
        finally:
            client.control(HALT)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
