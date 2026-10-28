import tempfile
import unittest
from pathlib import Path
from Host.protocol import CPUClient, load_packets, program_bytes
from Assembler.instr_to_bin import instr_to_bin


class Transport:
    def __init__(self, incoming=b"", limit=10000):
        self.sent = bytearray()
        self.incoming = bytearray(incoming)
        self.limit = limit
    def write(self, data):
        part = data[:self.limit]
        self.sent.extend(part)
        return len(part)
    def flush(self):
        pass
    def read(self, count):
        result = self.incoming[:min(count, 1)]
        del self.incoming[:len(result)]
        return bytes(result)


class ProtocolTests(unittest.TestCase):
    def test_control_is_one_byte(self):
        transport = Transport()
        client = CPUClient(transport)
        for command in range(1, 5):
            client.control(command)
        self.assertEqual(transport.sent, bytes(range(1, 5)))
        with self.assertRaises(ValueError):
            client.control(0)

    def test_packet_boundaries(self):
        for size in (0, 1, 254, 255, 256, 510, 511, 2048):
            data = bytes(i % 256 for i in range(size))
            packets = list(load_packets(data))
            self.assertEqual(b"".join(packet[2:] for packet in packets), data)
            for packet in packets:
                self.assertEqual(packet[0], 0)
                self.assertEqual(packet[1], len(packet)-2)
                self.assertLessEqual(packet[1], 255)

    def test_load_order_partial_writes(self):
        transport = Transport(limit=3)
        data = bytes(range(256)) * 8
        CPUClient(transport).load(data, start=True)
        self.assertEqual(transport.sent, b"\x03\x04\x01" + b"".join(load_packets(data)) + b"\x02")

    def test_invalid_load_does_not_touch_device(self):
        transport = Transport()
        for data in (b"", b"a", bytes(2050)):
            with self.assertRaises(ValueError):
                CPUClient(transport).load(data)
        self.assertEqual(transport.sent, b"")

    def test_no_write_progress(self):
        with self.assertRaises(OSError):
            CPUClient(Transport(limit=0)).control(3)

    def test_receive_fragmented_and_zero_length(self):
        client = CPUClient(Transport(b"\x00\x03abc\x00\x00\x00\x01z"))
        self.assertEqual(client.receive(), b"abc")
        self.assertEqual(client.receive(), b"")
        self.assertEqual(client.receive(), b"z")

    def test_receive_errors(self):
        with self.assertRaises(ValueError):
            CPUClient(Transport(b"\x01")).receive()
        with self.assertRaises(TimeoutError):
            CPUClient(Transport(b"\x00\x02a")).receive(0.001)

    def test_files_and_send_encoding(self):
        self.assertEqual(int(instr_to_bin("SEND R7"), 2), 0x3007)
        for instruction in ("SEND", "SEND R8", "SEND 2", "SEND R0, 1"):
            with self.assertRaises(ValueError):
                instr_to_bin(instruction)
        with tempfile.TemporaryDirectory() as directory:
            for suffix, content in ((".asm", b"LDI R0, 84\nSEND R0\n"),
                                    (".hex", b"0AA0 3000 // comment\n"),
                                    (".bin", b"\xa0\x0a\x00\x30")):
                path = Path(directory) / ("program" + suffix)
                path.write_bytes(content)
                self.assertEqual(program_bytes(path), b"\xa0\x0a\x00\x30")
            path.write_bytes(b"x")
            with self.assertRaises(ValueError):
                program_bytes(path)
            path = Path(directory) / "invalid.hex"
            path.write_text("10000")
            with self.assertRaises(ValueError):
                program_bytes(path)

    def test_partial_packet_survives_timeout(self):
        transport = Transport(b"\x00\x03a")
        client = CPUClient(transport)
        with self.assertRaises(TimeoutError):
            client.receive(0.001)
        transport.incoming.extend(b"bc")
        self.assertEqual(client.receive(), b"abc")

if __name__ == "__main__":
    unittest.main()
