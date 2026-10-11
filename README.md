This is my submission for the [Jane Street Protocol Emulator ASIC design competition](https://blog.janestreet.com/protocol-emulator-asic-competition/)
This is the first very simple version

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
