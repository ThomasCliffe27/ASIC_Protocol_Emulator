// Repeated UART message: TC, then approximately 1.003 seconds idle.
// Target: 100 MHz CPU clock, GPIO bit 0 -> uart_tx, 115200 baud, 8N1.
// Each UART bit lasts 868 clocks (115207.37 baud, +0.0064% error).
// DELAY R3 executes for 861 clocks, plus 3 fetch/decode clocks.
// The following SET takes 4 clocks: 861 + 3 + 4 = 868.
// R0=low, R1=high, R2=permanent zero, R3=861, R4=65535.
// R5/R6 are loop/exit addresses; R7 is a counter or jump target.
// SET writes the whole GPIO port; the other GPIO bits stay low.
// Jump immediates are WORD addresses. Update them if instructions move.

// LDI only has an 8-bit immediate. Construct 861 once at startup:
// -(253 * 255 + 160) modulo 65536 = 861. UART stays idle during setup.
LDI R0, 0        // 000
LDI R1, 1        // 001
LDI R2, 0        // 002
LDI R3, 0        // 003
LDI R7, 253      // 004
LDI R5, 7        // 005
LDI R6, 12       // 006
SUB R3, 255      // 007
SUB R7, 1        // 008
JMPZ R6          // 009
SUB R2, 0        // 010
JMPZ R5          // 011
SUB R3, 160      // 012

// Long-delay register: unsigned 16-bit wraparound gives 65535.
LDI R4, 0        // 013
SUB R4, 1        // 014
LDI R5, 60       // 015
LDI R6, 70       // 016

// Establish idle-high for at least one bit before the first start bit.
SET R1           // 017
DELAY R3         // 018

// 'T' = 0x54: start=0, eight LSB-first data bits, stop=1.
// start: 0
SET R0           // 019
DELAY R3         // 020
// data bit 0: 0
SET R0           // 021
DELAY R3         // 022
// data bit 1: 0
SET R0           // 023
DELAY R3         // 024
// data bit 2: 1
SET R1           // 025
DELAY R3         // 026
// data bit 3: 0
SET R0           // 027
DELAY R3         // 028
// data bit 4: 1
SET R1           // 029
DELAY R3         // 030
// data bit 5: 0
SET R0           // 031
DELAY R3         // 032
// data bit 6: 1
SET R1           // 033
DELAY R3         // 034
// data bit 7: 0
SET R0           // 035
DELAY R3         // 036
// stop: 1
SET R1           // 037
DELAY R3         // 038

// 'C' = 0x43: start=0, eight LSB-first data bits, stop=1.
// start: 0
SET R0           // 039
DELAY R3         // 040
// data bit 0: 1
SET R1           // 041
DELAY R3         // 042
// data bit 1: 1
SET R1           // 043
DELAY R3         // 044
// data bit 2: 0
SET R0           // 045
DELAY R3         // 046
// data bit 3: 0
SET R0           // 047
DELAY R3         // 048
// data bit 4: 0
SET R0           // 049
DELAY R3         // 050
// data bit 5: 0
SET R0           // 051
DELAY R3         // 052
// data bit 6: 1
SET R1           // 053
DELAY R3         // 054
// data bit 7: 0
SET R0           // 055
DELAY R3         // 056
// stop: 1
SET R1           // 057
DELAY R3         // 058

// Leave TX high. Each pass has six DELAY R4 instructions.
// 255 passes give approximately one second between messages.
// Last C stop-bit SET -> next T start-bit SET: 100278096 clocks
// (1.00278096 s), including loop overhead and the stop-bit hold.
LDI R7, 255      // 059
DELAY R4         // 060
DELAY R4         // 061
DELAY R4         // 062
DELAY R4         // 063
DELAY R4         // 064
DELAY R4         // 065
SUB R7, 1        // 066
JMPZ R6          // 067
SUB R2, 0        // 068
JMPZ R5          // 069
SUB R2, 0        // 070
LDI R7, 19       // 071
JMPZ R7          // 072
