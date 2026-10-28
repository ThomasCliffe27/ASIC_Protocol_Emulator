`timescale 1ns/1ps
module cpu_control_tb;
    logic clk=0,reset=1,run_enable=1,send_ready=0;
    wire [9:0] address;
    logic [15:0] rd;
    wire [7:0] data;
    wire valid;
    logic [15:0] held_delay;
    logic [9:0] held_pc;
    int sent=0;
    always #5 clk=~clk;
    cpu dut(.clk(clk),.reset(reset),.run_enable(run_enable),.send_data(data),
        .send_valid(valid),.send_ready(send_ready),.address(address),.read_data(rd),.gpio_input(8'h00));
    always @(posedge clk) begin
        case(address)
            0: rd<=16'h0800; // LDI R0,0
            1: rd<=16'h1008; // SUB R0,1 -> ffff
            2: rd<=16'h3000; // SEND R0
            3: rd<=16'h2800; // DELAY R0
            default: rd<=0;
        endcase
        if(valid && send_ready) sent++;
    end
    initial begin
        repeat(3) @(negedge clk); reset=0;
        wait(valid); @(negedge clk);
        held_pc=address;
        repeat(30) begin
            if(!valid || data !== 8'hff || address !== held_pc) $fatal(1,"SEND backpressure/low byte");
            @(negedge clk);
        end
        run_enable=0; send_ready=1;
        repeat(20) begin @(negedge clk); if(valid || sent || address !== held_pc) $fatal(1,"halt pending SEND"); end
        run_enable=1; @(negedge clk);
        if(sent != 1) $fatal(1,"resume SEND exactly once");
        repeat(10) @(negedge clk);
        if(sent != 1) $fatal(1,"duplicate SEND");
        run_enable=0; held_delay=dut.clk_count; held_pc=address;
        repeat(20) @(negedge clk);
        if(dut.clk_count !== held_delay || address !== held_pc) $fatal(1,"halt freezes delay");
        run_enable=1; @(negedge clk);
        if(dut.clk_count !== held_delay-1) $fatal(1,"resume delay");
        reset=1; @(negedge clk); run_enable=0; reset=0; @(negedge clk);
        if(address !== 0 || dut.regs[0] !== 0 || valid) $fatal(1,"reset while running");
        $display("PASS: SEND low byte/backpressure/exactly once, halt/resume pending SEND and DELAY, CPU reset"); $finish;
    end
    initial begin #100000; $fatal(1,"CPU control timeout"); end
endmodule
