//Program to test the cpu to host communication
//In pseudocode:
//LOOP FOREVER:
//  SEND("hello ")
//  FOR (int i = 0; i < 256; i++):
//      DELAY(393,210)

//Send "hello " over ascii
LDI R0, 104
SEND R0
LDI R0, 101
SEND R0
LDI R0, 108
SEND R0
SEND R0
LDI R0, 111
SEND R0
LDI R0, 32
SEND R0

//loop tracker for total delay of 1.003 seconds
LDI R3, 255

//Get value of 2^16 - 1
LDI R4, 0
SUB R4, 1

//Delay 6 * (2^16 - 1) clock cycles = 393,210
DELAY R4
DELAY R4
DELAY R4
DELAY R4
DELAY R4
DELAY R4

//If block of delay has occured 255 time go to start of program
SUB R3, 1
JMPZ R1

//Else go to start of loop
LDI R6, 14
LDI R5, 1
SUB R5, 1 //Equals 0 so JMPZ always happens
JMPZ, R6

