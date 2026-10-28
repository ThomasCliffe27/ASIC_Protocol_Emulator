This is my submission for the [Jane Street Protocol Emulator ASIC design competition](https://blog.janestreet.com/protocol-emulator-asic-competition/)
This is the first very simple version

## Running all tests

From the repository root, run:

```powershell
python Testing/test_all.py
```

The runner finds every `test_*.py` suite and `*_tb.sv` testbench under `Testing`,
runs the assembler tests, regenerates assembly fixtures, and compiles and runs
each HDL testbench with Vivado. It prints a pass/fail summary and exits with
code 1 if any suite fails, tools are missing, or a simulation does not finish.
Build files and full logs are kept in `Testing/.test_all/`.

Vivado is detected from PATH, `XILINX_VIVADO`, or common installation folders.
To select an installation explicitly:

```powershell
python Testing/test_all.py --vivado-bin "C:/AMDDesignTools/2025.2/Vivado/bin"
```

The runner works from other working directories when invoked by its full path.
Use `--timeout SECONDS` to change the default 180-second limit per command.

## Design

16 bit CPU
8 16 bit GPRs
A z flag for calculations and logic flow
1024x16 memory

ISA:

DELAY imm - Wait a number of clock cycles
LDI Rx, imm - Load imm into Rx
SUB Rx, imm - Update z flag if result = 0
JMPZ Rx - Set PC to Rx if z flag = 1
SET Rx - Update the GPIO pins with the LSBs of Rx

16-bit instructions
15-11 = opcode
10-3 = imm
2-0 = register

opcodes:
DELAY - 0x00
LDI - 0x01
SUB - 0x02
JMPZ - 0x03
SET - 0x04

IDEAS:
- Commands do both gpio control and cpu logic
- Mode that acts almost like an oscilliscope/ signal analyser
- Two "cores" one for input one for output
- Pipelining but need to maintain cycle timing consistency
