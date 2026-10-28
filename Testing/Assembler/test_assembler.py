import sys
import tempfile
import unittest
from pathlib import Path

class AssemblerTests(unittest.TestCase):
    def setUp(self) -> None:
        # Bootstrap direct execution within test setup, keeping module imports
        # together. Restore the search path after each test.
        project_root = str(Path(__file__).resolve().parents[2])
        if project_root not in sys.path:
            sys.path.insert(0, project_root)
            self.addCleanup(sys.path.remove, project_root)

        from Assembler.assembler import assemble
        from Assembler.instr_to_bin import instr_to_bin

        self.assemble = assemble
        self.instr_to_bin = instr_to_bin

    def test_all_register_immediate_encodings(self):
        for mnemonic, opcode in (("LDI", 1), ("SUB", 2)):
            for reg in range(8):
                for immediate in range(256):
                    self.assertEqual(
                        int(self.instr_to_bin(f"{mnemonic} R{reg}, {immediate}"), 2),
                        (opcode << 11) | (immediate << 3) | reg,
                    )
        for immediate in range(256):
            self.assertEqual(int(self.instr_to_bin(f"DELAY {immediate}"), 2), immediate << 3)
        for mnemonic, opcode in (("JMPZ", 3), ("SET", 4)):
            for reg in range(8):
                self.assertEqual(int(self.instr_to_bin(f"{mnemonic} R{reg}"), 2), (opcode << 11) | reg)

    def test_readmemh_text_and_comments(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "program.asm"
            output = source.with_suffix(".hex")
            source.write_text("// comment\n# comment\n\nldi r0, 0x2a // load\nSET R0 # emit\nSUB R0, 42\n", encoding="utf-8")
            self.assemble(source, output)
            self.assertEqual(output.read_bytes(), b"0950\n2000\n1150\n")

    def test_invalid_operands(self):
        for instruction in ("LDI X0, 1", "LDI R8, 1", "LDI R-1, 1", "LDI R0, 256",
                            "SUB R0, -1", "DELAY 256", "SET R0, 1", "JMPZ", "BAD R0"):
            with self.subTest(instruction=instruction), self.assertRaises(ValueError):
                self.instr_to_bin(instruction)

    def test_diagnostic_and_existing_output_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "bad.asm"
            output = source.with_suffix(".hex")
            source.write_text("// comment\nLDI R8, 1\n", encoding="utf-8")
            output.write_text("2000\n", encoding="ascii")
            with self.assertRaisesRegex(ValueError, r"bad\.asm:2: Register"):
                self.assemble(source, output)
            self.assertEqual(output.read_text(), "2000\n")


if __name__ == "__main__":
    unittest.main()
