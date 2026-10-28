`timescale 1ns/1ps
module uart_tb;
    logic clk=0, reset=1, rx=1;
    wire [7:0] data;
    wire valid, error;
    int good=0,bad=0;
    always #5 clk=~clk;
    uart_rx #(.CLOCK_HZ(1_600_000),.BAUD(100_000)) dut(clk,reset,rx,data,valid,error);
    always @(posedge clk) begin
        if(valid) begin
            if(data !== (good==0 ? 8'ha5 : 8'h00)) $fatal(1,"RX data");
            good++;
        end
        if(error) bad++;
    end
    task automatic send(input byte value,input bit stop);
        rx=0; #160;
        for(int i=0;i<8;i++) begin rx=value[i]; #160; end
        rx=stop; #160; rx=1; #160;
    endtask
    initial begin
        repeat(3) @(negedge clk); reset=0;
        rx=0; #30; rx=1; #300; // false start
        if(good || bad) $fatal(1,"false start");
        send('ha5,1); send('h7e,0); send(0,1);
        if(good != 2 || bad != 1) $fatal(1,"framing counts");
        rx=0; #200; reset=1; @(negedge clk); rx=1; reset=0; #400;
        if(good != 2) $fatal(1,"reset mid frame");
        $display("PASS: RX synchronization, false start, framing error, recovery, reset"); $finish;
    end
    initial begin #100000; $fatal(1,"UART timeout"); end
endmodule
