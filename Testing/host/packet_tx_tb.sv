`timescale 1ns/1ps
module packet_tx_tb;
    logic clk=0,reset=1,pv=0,ready=0;
    logic [7:0] payload=0;
    wire pr,valid;
    wire [7:0] data;
    always #5 clk=~clk;
    packet_tx dut(clk,reset,payload,pv,pr,data,valid,ready);
    initial begin
        repeat(3) @(negedge clk); reset=0;
        payload='hab; pv=1; @(negedge clk); pv=0; payload=0;
        for(int i=0;i<3;i++) begin
            repeat(5) begin
                if(!valid || pr || data !== (i==0 ? 8'h00 : i==1 ? 8'h01 : 8'hab)) $fatal(1,"stalled packet");
                @(negedge clk);
            end
            ready=1; @(negedge clk); ready=0;
        end
        if(valid || !pr) $fatal(1,"packet completion");
        pv=1; @(negedge clk); reset=1; @(negedge clk);
        if(valid || !pr) $fatal(1,"serializer reset");
        $display("PASS: TX packet encoding, stable backpressure, reset"); $finish;
    end
    initial begin #10000; $fatal(1,"TX packet timeout"); end
endmodule
