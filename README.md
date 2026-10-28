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

## Host communication over UART

The Basys 3 top level boots **halted** and uses the 100 MHz clock with a dedicated
**115200 baud, 8N1** UART (no flow control). The centre button resets the CPU,
transport FIFOs, packet parsers and load pointer; RAM contents are retained.
The previous GPIO-driven UART demonstration is replaced. GPIO remains available
on the LEDs, independently of UART TX. Programs are loaded over UART after boot;
there is no default embedded program.

### Wire format

All fields are **one byte**. Only data commands carry a length and payload.
Length counts payload bytes, from 0 to 255. Larger transfers use multiple packets.

| Direction | Bytes | Meaning |
| --- | --- | --- |
| Host to CPU | `00 length payload...` | Load program bytes at the current memory pointer |
| Host to CPU | `01` | Reset memory pointer to word address zero |
| Host to CPU | `02` | Start or resume CPU execution |
| Host to CPU | `03` | Halt, preserving PC, registers and delay progress |
| Host to CPU | `04` | Reset CPU registers/PC; remain halted; retain RAM |
| CPU to host | `00 length payload...` | Data packet (currently `00 01 data` per SEND) |

There are **no acknowledgements, checksums or status responses**. Unknown host
command bytes are ignored. Control bytes appearing inside a declared payload
are data, not commands. A zero-length data packet is a no-op. Packets may have
arbitrary gaps between bytes; the parser does not time out.

Instructions are 16 bits, transmitted **low byte first**. For example, loading
`LDI R0,84` (`0AA0`) and `SEND R0` (`3000`) is `00 04 A0 0A 00 30`.
The memory pointer increments after each complete word. An unmatched low byte
carries across packets (including 255-byte packet boundaries); `01` or `04`
discards that partial word. `04` otherwise preserves the load pointer. `01`
does not clear memory or reset/halt the CPU.

Loads received while running are consumed but ignored. Loading beyond 1024 words
is discarded without wrapping over earlier words. Internal sticky `load_error`
is cleared by pointer reset or board reset; `rx_error` records framing errors or
RX overflow and is cleared by board reset. These signals are available in RTL,
but are not sent to the host. Complete words from a partial transfer are already
written; loading is not transactional.

If a transfer is interrupted or a serial byte is lost, the simple protocol cannot
automatically find packet boundaries. Reset the board with the centre button,
then reload the program. A CPU reset command does not reset the serial parser.
Halt and CPU reset do not discard already queued outgoing packets; they drain
normally. Board reset discards them and can interrupt an outgoing UART frame.

### Modules

- `uart.sv`: synchronized UART receiver and ready/valid transmitter.
- `byte_fifo.sv`: reusable FIFO; `host_uart.sv` instantiates **256 RX bytes** and
  **64 TX bytes** (wire packet bytes, including headers).
- `packet_rx.sv` / `packet_tx.sv`: command parsing and data serialization.
- `host_cpu.sv`: CPU controls, load pointer and byte-to-word conversion.
- `host_uart.sv`: transport integration; `top.sv` connects memory and CPU.

`SEND Rx` uses opcode **0x06** with the existing register field (immediate field
reserved/ignored). It sends the register's **low 8 bits**, preserving registers
and flags. SEND stalls in execution until its byte is accepted by the serializer.
The serializer and TX FIFO apply backpressure, so a fast program cannot silently
drop output. Halt also pauses a pending SEND. Existing instruction timing is unchanged
while the CPU runs. This host integration targets the existing 16-bit CPU.

### Python serial monitor

Run this once to open a desktop serial monitor:

```powershell
cd C:\FPGA\Protocol_Emulator
python Host/cli.py --port COM4
```

The window has a live receive log above a fixed command box. Received **payload
bytes** appear automatically as packets arrive, without typing `receive`.
Choose **Hex + ASCII**, **Hex**, or **ASCII**; non-printable characters are escaped.
UART packet command/length headers are decoded rather than printed as data.
The display refreshes every 20 ms. You can keep typing while data arrives.

Type a command at the bottom and press **Enter** or **Send**:

```text
load Programs/send.asm
start
halt
reset
help
```

**Load program…** opens a file picker. **Start**, **Halt**, and **Reset** buttons
send the same commands. Use the port selector and **Connect**/**Disconnect** to
manage the connection, **Clear log** to clear displayed text, and **Autoscroll**
to follow incoming data. Up/Down in the command box recalls command history.
You can omit `--port` to select a port in the window.

| Command | Action |
| --- | --- |
| `ports` | List available serial ports |
| `connect PORT` | Open the port at 115200 baud, 8N1 |
| `load FILE` | Halt/reset CPU and pointer, upload program, leave CPU halted |
| `start` | Start or resume execution |
| `halt` | Pause execution, preserving CPU state |
| `reset` | Reset CPU state, preserve program RAM, leave halted |
| `pointer_reset` | Reset the memory loading pointer |
| `status` | Show connection and host-side drops |
| `disconnect` | Close the port without changing CPU execution |
| `quit` | Close the connection and window |

Quote filenames containing spaces, e.g. `load "C:\My Programs\test.asm"`.
Supported formats are `.asm`, `.hex`, `.mem`, and `.bin`. The example
`Programs/send.asm` emits alternating `54` and `43` (ASCII T and C).
Commands have no device acknowledgements. Use **Halt** before closing if you want
the CPU to stop. Close any other serial terminal using the port before connecting.

The receive queue holds 4096 packets and reports drops if it fills. The display
keeps the latest 100,000 characters to stay responsive during continuous output;
it is a live view, not a lossless recording. Loading runs in a worker so the
window and receive display remain responsive. Commands execute one at a time.

The text-only interactive shell remains available with `python Host/cli.py --terminal`.
In that mode, type `connect COM4`, use `receive [COUNT]` to display buffered packets,
and type `quit` to exit. The desktop monitor displays received data automatically.

On another computer, install the dependency once with
`python -m pip install -r Host/requirements.txt`. The desktop monitor also uses
Tkinter, included with the standard Windows Python installer. No virtual
environment is required. If a serial byte is lost or you connect in the middle
of a packet, reset the board and reconnect to restore framing.

### Build and verification

```powershell
python Testing/test_all.py
& "C:/AMDDesignTools/2025.2/Vivado/bin/vivado.bat" -mode batch -source Scripts/build_uart.tcl
& "C:/AMDDesignTools/2025.2/Vivado/bin/vivado.bat" -mode batch -source Scripts/program_uart.tcl
```

The build script reads all modules under `Sources` and generates
`Build/uart_tx/uart_tx.bit`, timing, DRC and utilization reports. Programming
updates volatile FPGA configuration only. The saved Vivado project also includes
the transport modules; reopen it if already open.

Tests cover FIFO capacity/wrap/backpressure, UART framing and false starts,
packet lengths, split words, memory bounds, CPU controls, SEND stalling and
low-byte selection, host protocol/file encoding, and a real-115200-baud top-level load/send
simulation. The existing assembler, CPU, memory and GPIO regressions also run.

### Verified on 28 October 2026

- All **10 HDL regression suites passed** for the UART/CPU implementation.
- The serial monitor, interactive shell and host protocol pass **22 Python tests**, including
  a persistent command session, background reception, timeouts, bounded buffering,
  invalid commands and connection cleanup. The interactive-shell board check could
  not open COM4 (Windows access denied); the hardware results below apply to the
  UART/CPU design and protocol smoke test.
- Vivado 2025.2 generated the Basys 3 bitstream: internal setup slack **2.856 ns**,
  hold slack **0.096 ns**, and no unconstrained internal endpoints. Asynchronous
  UART/button inputs and LED/UART outputs have no external synchronous I/O delays.
- DRC reports no errors; eight GPIO buffering warnings remain because the CPU
  currently does not use its GPIO inputs.
- Connected Basys 3 on **COM4** passed a full 2048-byte upload, SEND output,
  halt/resume and reset-with-memory-retention test. Board left halted.

Repeat the opt-in hardware test after programming the bitstream:

```powershell
python -m Host.smoke_test --port COM4
```

This overwrites program RAM with a test image and leaves the CPU halted.

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
SEND Rx - 0x06 (send low byte over UART; immediate field reserved/ignored)

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
