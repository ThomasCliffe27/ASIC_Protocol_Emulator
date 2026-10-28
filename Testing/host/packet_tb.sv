`timescale 1ns/1ps
module packet_tb;
    logic clk=0, reset=1, valid=0;
    logic [7:0] data=0;
    wire ready, cv,pv,running,cr,we,error;
    wire [7:0] command,payload;
    wire [1:0] address;
    wire [15:0] wd;
    logic [15:0] mem[0:3];
    int writes=0;
    always #5 clk=~clk;
    packet_rx parser(clk,reset,data,valid,ready,command,cv,payload,pv);
    host_cpu #(.MEMORY_SIZE(4)) control(clk,reset,command,cv,payload,pv,running,cr,address,we,wd,error);
    always @(posedge clk) if(we) begin mem[address]<=wd; writes++; end
    task automatic put(input byte value);
        data=value; valid=1; @(negedge clk); valid=0;
    endtask
    initial begin
        repeat(3) @(negedge clk); reset=0;
        put(0); put(0); // zero length, then a control byte
        put(2); if(!running) $fatal(1,"start after empty packet");
        put(0); put(2); put(1); put(2); // reject load while running; consume payload
        if(writes != 0 || !error || !running) $fatal(1,"running load rejection");
        put(3); put(1);
        if(running || error) $fatal(1,"halt/pointer reset");
        put(0); put(1); put('h34);
        repeat(10) @(negedge clk); // preserve partial word across packets and delays
        put(0); put(3); put('h12); put('h78); put('h56);
        if(writes != 2 || mem[0] !== 16'h1234 || mem[1] !== 16'h5678) $fatal(1,"word packing");
        put(0); put(6); put(0); put(1); put(2); put(3); put(4); put(5);
        if(writes != 4 || !error || mem[0] !== 16'h1234) $fatal(1,"memory boundary");
        put(4); if(!cr || running || mem[0] !== 16'h1234) $fatal(1,"CPU reset");
        put('hff); put(1); // unknown command ignored; pointer reset
        put(0); put(1); put('haa); put(1);
        put(0); put(2); put('hef); put('hbe);
        if(mem[0] !== 16'hbeef) $fatal(1,"discard partial word on pointer reset");
        // Maximum length must count all 255 bytes, including command-valued payloads.
        put(0); put(255);
        for(int i=0;i<255;i++) put(8'(i));
        put(2); if(!running) $fatal(1,"255 length boundary");
        // Reset parser in the middle of a packet.
        put(0); put(255); put(1); reset=1; @(negedge clk); reset=0;
        put(2); if(!running) $fatal(1,"parser reset");
        $display("PASS: packet lengths, split words, commands, running rejection, memory bounds, resets"); $finish;
    end
    initial begin #100000; $fatal(1,"packet timeout"); end
endmodule
