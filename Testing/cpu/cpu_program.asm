// End-to-end assembler/CPU fixture. Jump targets are word addresses.
LDI R0, 42
SET R0
SUB R0, 42
SET R0
LDI R1, 8
SUB R2, 0
JMPZ R1
SET R1          // Must be skipped by the taken branch.
DELAY 3
LDI R3, 165
SET R3
DELAY R3       // Use the full register value without changing it.
SET R3
