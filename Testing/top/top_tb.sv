`timescale 1ns/1ps

// Tests the same file initialization and reset circuitry used in the bitstream.
// No hierarchical memory writes or forces: the DUT loads uart_tx.hex itself.
module top_tb;
    logic clk = 1'b0;
    logic reset = 1'b0;
    wire uart_tx;
    wire [7:0] gpio_pins;
    int unsigned byte_count = 0;

    top dut (.clk(clk), .reset(reset), .uart_rx(1'b1),
             .uart_tx(uart_tx), .gpio_pins(gpio_pins));

    always #5 clk = ~clk;

    initial begin
        #1000000;
        $fatal(1, "Top-level UART regression timed out");
    end

    task automatic receive_byte(input logic [7:0] expected_byte);
        logic [7:0] actual_byte;
        @(negedge uart_tx);
        #4340; // Centre of start bit: 434 of the 868 clocks per bit.
        if (uart_tx !== 1'b0) $fatal(1, "Invalid UART start bit");
        for (int bit_index = 0; bit_index < 8; bit_index++) begin
            #8680;
            actual_byte[bit_index] = uart_tx;
            if (gpio_pins[0] !== uart_tx || gpio_pins[7:1] !== 7'b0)
                $fatal(1, "UART/LED wiring mismatch");
        end
        #8680;
        if (uart_tx !== 1'b1) $fatal(1, "Invalid UART stop bit");
        if (actual_byte !== expected_byte)
            $fatal(1, "Expected UART byte %h, received %h", expected_byte, actual_byte);
        byte_count++;
    endtask

    initial begin
        $display("START top: automatic power-on reset and initialized UART program");
        #1;
        if (uart_tx !== 1'b1) $fatal(1, "UART is not idle at power-on");
        // No external reset is needed to boot the configured FPGA.
        receive_byte(8'h54);
        receive_byte(8'h43);
        repeat (3000) begin
            @(negedge clk);
            if (uart_tx !== 1'b1) $fatal(1, "UART did not remain idle during pause");
        end

        $display("START top: button reset and program restart");
        #2;
        reset = 1'b1;
        #1;
        if (uart_tx !== 1'b1) $fatal(1, "UART is not idle during reset");
        repeat (3) @(negedge clk);
        if (gpio_pins !== 8'bzzzzzzzz) $fatal(1, "GPIO did not reset to inputs");
        reset = 1'b0;
        @(negedge clk);
        if (gpio_pins !== 8'bzzzzzzzz) $fatal(1, "Reset released before synchronization");
        receive_byte(8'h54);
        receive_byte(8'h43);
        $display("PASS: initialized ROM, power-on/button reset, UART idle and %0d decoded bytes", byte_count);
        $finish;
    end
endmodule
