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

## Basys 3 UART demonstration

`Programs/uart_tx.asm` sends `TC` at **115200 baud, 8 data bits, no parity,
one stop bit**, with about **1.003 seconds idle** between messages. It assumes
the board's 100 MHz clock. GPIO bit 0 and UART TX capture the same output bit;
GPIO bits 0..7 are assigned to LEDs LD0..LD7. The centre button resets the CPU.
The UART stays high during startup, and the FPGA starts the program automatically
after configuration.

The 73-instruction program uses `DELAY R3` for each bit (R3 holds 861), and
`DELAY R4` in the idle loop (R4 holds 65535). At 100 MHz, each bit still lasts
868 clocks after accounting for fetch/decode and GPIO-write overhead.

The saved Vivado project uses `top` for synthesis and `top_tb` for simulation.
Reopen the project if it was already open while these settings were changed.
The program hex file is included as a memory initialization file. Its contents
are embedded in the FPGA bitstream; no PC file access is needed while running.
Standalone memory instances still start uninitialized unless `INIT_FILE` is set.

To assemble, synthesize, implement, check timing and generate the bitstream,
run from the repository root:

```powershell
& "C:/AMDDesignTools/2025.2/Vivado/bin/vivado.bat" -mode batch -source Scripts/build_uart.tcl
```

The script uses a separate build directory, `Build/uart_tx/`, and produces
`uart_tx.bit`, `timing_summary.rpt`, `drc.rpt` and `utilization.rpt`. It checks
setup and hold timing before generating the bitstream. If the program length
changes, update `PROGRAM_WORDS` in `Sources/top.sv` to the new instruction count.

Connect and power the Basys 3 through its PROG/UART USB connector. To load the
bitstream into the single connected Digilent/xc7a35t target:

```powershell
& "C:/AMDDesignTools/2025.2/Vivado/bin/vivado.bat" -mode batch -source Scripts/program_uart.tcl
```

This programs volatile FPGA configuration. Run it again after a power cycle;
SPI flash is not written. Alternatively, use Hardware Manager's **Program
Device** command and select `Build/uart_tx/uart_tx.bit`.

Open the board's serial port with **115200, 8N1, no flow control**. The board
was identified as **COM4** on this PC. You should see `TCTCTC...`, without
newlines. The serial verification closes its connection so a terminal can open
the port afterwards. Test initialization, UART framing and reset automatically
with `python Testing/test_all.py`; this does not require a connected board.

## Design

16 bit CPU
8 16 bit GPRs
A z flag for calculations and logic flow
1024x16 memory

ISA:

DELAY imm - Wait using an 8-bit immediate count (0..255)
DELAY Rx - Wait using the full unsigned value in register Rx (0..65535 at 16 bits)
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
DELAY Rx - 0x05 (immediate field reserved/ignored; assembler writes zero)

Both delay forms spend `max(1, count)` clocks in execution, plus the existing
three fetch/decode clocks. They preserve the register values and zero flag;
reset cancels a pending delay. Immediate-delay machine code and timing are
unchanged. For example:

```text
LDI R3, 200
DELAY R3       // 200 execution clocks, 203 clocks including fetch/decode
DELAY 10       // Immediate form still works
LDI R4, 0
SUB R4, 1      // 16-bit wraparound gives 65535
DELAY R4       // 65535 execution clocks, 65538 clocks in total
```

IDEAS:
- Commands do both gpio control and cpu logic
- Mode that acts almost like an oscilliscope/ signal analyser
- Two "cores" one for input one for output
- Pipelining but need to maintain cycle timing consistency
