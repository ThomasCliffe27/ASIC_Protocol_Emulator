`timescale 1ns/1ps
module fifo_check #(parameter int DEPTH=256)(output logic done=0);
    logic clk=0, reset=1, iv=0, ready=0;
    logic [7:0] data=0;
    wire ir, ov;
    wire [7:0] out_data;
    wire [$clog2(DEPTH+1)-1:0] count;
    always #5 clk=~clk;
    byte_fifo #(.DEPTH(DEPTH)) dut(clk,reset,data,iv,ir,out_data,ov,ready,count);
    initial begin
        repeat(2) @(negedge clk); reset=0;
        if(ov || count != 0) $fatal(1,"FIFO reset");
        ready=1; repeat(3) @(negedge clk); ready=0;
        if(count != 0) $fatal(1,"FIFO underflow");
        for(int i=0;i<DEPTH;i++) begin
            data=8'(i); iv=1; @(negedge clk);
        end
        iv=0;
        if(ir || count != DEPTH) $fatal(1,"FIFO capacity");
        data=8'haa; iv=1; repeat(2) @(negedge clk); iv=0;
        if(count != DEPTH || out_data != 0) $fatal(1,"FIFO overflow protection");
        // Full simultaneous read/write must accept both, preserving order.
        ready=1; iv=1; data=8'hbe;
        #1; if(!ir) $fatal(1,"FIFO full simultaneous acceptance");
        @(negedge clk); iv=0;
        for(int i=1;i<DEPTH;i++) begin
            if(!ov || out_data !== 8'(i)) $fatal(1,"FIFO ordering %0d",i);
            @(negedge clk);
        end
        if(out_data !== 8'hbe) $fatal(1,"FIFO replacement");
        @(negedge clk); ready=0;
        if(ov || count != 0) $fatal(1,"FIFO drain");
        // More than two wraps at constant occupancy.
        data=8'hff; iv=1; @(negedge clk);
        ready=1;
        for(int i=0;i<DEPTH*3;i++) begin
            if(out_data !== (i==0 ? 8'hff : 8'(i-1))) $fatal(1,"FIFO wrap");
            data=8'(i); @(negedge clk);
        end
        reset=1; @(negedge clk);
        if(ov || count != 0) $fatal(1,"FIFO reset while active");
        done=1;
    end
endmodule
module fifo_tb;
    wire a,b;
    fifo_check #(.DEPTH(256)) rx(a);
    fifo_check #(.DEPTH(64)) tx(b);
    initial begin wait(a && b); $display("PASS: FIFO capacities, wrap, simultaneous transfers, reset, overflow/underflow"); $finish; end
    initial begin #100000; $fatal(1,"FIFO timeout"); end
endmodule
