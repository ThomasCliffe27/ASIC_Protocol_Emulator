`timescale 1ns/1ps
module top_tb;
    logic clk=0, reset=0, rx=1;
    wire tx;
    wire [7:0] gpio;
    int received=0;
    logic [15:0] program_words[0:6];
    logic [9:0] held_pc;
    top dut(.clk(clk),.reset(reset),.uart_rx(rx),.uart_tx(tx),.gpio_pins(gpio));
    always #5 clk=~clk;
    task automatic send_byte(input logic [7:0] value);
        rx=0; #8680;
        for(int i=0;i<8;i++) begin rx=value[i]; #8680; end
        rx=1; #8680;
    endtask
    // Decode at the real 115200 baud independently of internal transmitter signals.
    initial forever begin
        logic [7:0] value;
        @(negedge tx); #4340;
        if(tx !== 0) $fatal(1,"TX start");
        for(int i=0;i<8;i++) begin #8680; value[i]=tx; end
        #8680;
        if(tx !== 1) $fatal(1,"TX stop");
        case(received%6)
            0,3: if(value !== 0) $fatal(1,"TX command %h",value);
            1,4: if(value !== 1) $fatal(1,"TX length %h",value);
            2: if(value !== 84) $fatal(1,"SEND T %h",value);
            5: if(value !== 67) $fatal(1,"SEND C %h",value);
        endcase
        received++;
    end
    initial begin
        program_words[0]=16'h0aa0; // LDI R0,84
        program_words[1]=16'h3000; // SEND R0
        program_words[2]=16'h0a18; // LDI R0,67
        program_words[3]=16'h3000;
        program_words[4]=16'h0801; // LDI R1,0
        program_words[5]=16'h1001; // SUB R1,0
        program_words[6]=16'h1801; // JMPZ R1
        repeat(20) @(negedge clk);
        if(dut.running !== 0 || tx !== 1) $fatal(1,"boot must be halted/idle");
        send_byte(1);
        // Deliberately split a word at the packet boundary.
        send_byte(0); send_byte(3);
        send_byte(program_words[0][7:0]); send_byte(program_words[0][15:8]);
        send_byte(program_words[1][7:0]);
        send_byte(0); send_byte(11); send_byte(program_words[1][15:8]);
        for(int i=2;i<7;i++) begin send_byte(program_words[i][7:0]); send_byte(program_words[i][15:8]); end
        for(int i=0;i<7;i++) if(dut.mem_inst.mem[i] !== program_words[i]) $fatal(1,"load word %0d",i);
        send_byte(2);
        wait(received>=6);
        // CPU quickly fills TX FIFO and stalls on SEND until space is available.
        if(dut.host.tx_fifo.count < 60) $fatal(1,"expected TX backpressure");
        send_byte(3); repeat(20) @(negedge clk);
        held_pc=dut.cpu_inst.pc;
        repeat(1000) @(negedge clk);
        if(dut.cpu_inst.pc !== held_pc || dut.running) $fatal(1,"halt must preserve PC");
        send_byte(2); repeat(100) @(negedge clk);
        if(!dut.running) $fatal(1,"resume");
        send_byte(4); repeat(20) @(negedge clk);
        if(dut.cpu_inst.pc !== 0 || dut.running || dut.cpu_inst.regs[0] !== 0) $fatal(1,"reset CPU state");
        for(int i=0;i<7;i++) if(dut.mem_inst.mem[i] !== program_words[i]) $fatal(1,"reset erased RAM");
        if(dut.rx_error || dut.load_error) $fatal(1,"unexpected transport error");
        $display("PASS: 115200 UART program load, SEND packets, TX backpressure, halt/resume, reset retains memory");
        $finish;
    end
    initial begin #10000000; $fatal(1,"top timeout"); end
endmodule
