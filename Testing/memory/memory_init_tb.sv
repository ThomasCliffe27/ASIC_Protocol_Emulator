`timescale 1ns/1ps

module memory_init_tb;
    logic clk = 0;
    logic [3:0] address = 0;
    logic write_enable = 0;
    logic [15:0] write_data = 0;
    wire [15:0] read_data;
    int unsigned check_count = 0;

    memory #(.WORD_WIDTH(16), .MEMORY_SIZE(13), .INIT_FILE("memory_init.hex"),
             .INIT_WORDS(4)) dut (.*);
    always #5 clk = ~clk;

    initial begin
        #10000;
        $fatal(1, "Initialized memory regression timed out");
    end

    task automatic cycle(input logic [3:0] location, input logic enable,
                         input logic [15:0] data, input logic [15:0] expected);
        @(negedge clk);
        address = location;
        write_enable = enable;
        write_data = data;
        @(posedge clk);
        #1;
        check_count++;
        if (read_data !== expected)
            $fatal(1, "Initialized memory address %0d: expected %h, got %h",
                   location, expected, read_data);
    endtask

    initial begin
        $display("START initialized memory: file words, zero padding and read-before-write");
        cycle(0, 0, 0, 16'h0123);
        cycle(1, 0, 0, 16'hABCD);
        cycle(2, 0, 0, 16'h8001);
        cycle(3, 0, 0, 16'hFFFF);
        for (int location = 4; location < 13; location++)
            cycle(4'(location), 0, 0, 0);
        cycle(0, 1, 16'h5678, 16'h0123);
        cycle(0, 0, 0, 16'h5678);
        cycle(12, 1, 16'hA5A5, 0);
        cycle(12, 0, 0, 16'hA5A5);
        cycle(1, 0, 0, 16'hABCD);
        $display("PASS: %0d initialized-memory checks", check_count);
        $finish;
    end
endmodule
