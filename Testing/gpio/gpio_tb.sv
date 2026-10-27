`timescale 1ns/1ps

module gpio_tb;
    localparam int GPIO_WIDTH = 8;
    localparam int NUM_VALUES = 1 << GPIO_WIDTH;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic set_io_mask = 1'b0;
    logic set_gpio = 1'b0;
    logic [GPIO_WIDTH-1:0] mask = '0;
    wire [GPIO_WIDTH-1:0] gpio_pins;
    wire [GPIO_WIDTH-1:0] gpio_input;

    // External device: each pin can be driven independently or released.
    logic [GPIO_WIDTH-1:0] external_enable = '0;
    logic [GPIO_WIDTH-1:0] external_value = '0;
    for (genvar i = 0; i < GPIO_WIDTH; i++) begin : external_drivers
        assign gpio_pins[i] = external_enable[i] ? external_value[i] : 1'bz;
    end

    gpio #(.GPIO_WIDTH(GPIO_WIDTH)) dut (
        .clk(clk), 
        .reset(reset),
        .set_io_mask(set_io_mask), 
        .set_gpio(set_gpio), 
        .mask(mask),
        .gpio(gpio_pins), 
        .gpio_input(gpio_input)
    );

    // Reference state is maintained independently; no DUT internals are read.
    logic [GPIO_WIDTH-1:0] expected_direction = '0;
    logic [GPIO_WIDTH-1:0] expected_output = '0;
    int unsigned check_count = 0;
    int unsigned cycle_count = 0;
    int unsigned test_count = 0;
    string current_test = "startup";

    always #5 clk = ~clk;

    initial begin
        #20000000;
        $fatal(1, "GPIO regression timed out during %s", current_test);
    end

    task automatic start_test(input string name);
        current_test = name;
        test_count++;
        $display("START %s", name);
    endtask

    // Digital equal-strength resolution, including intentionally injected X/Z.
    // Opposing drivers are for simulation tests only, not safe hardware use.
    function automatic logic resolve_pin(input logic internal_drive,
                                         input logic external_drive);
        if (internal_drive === 1'bz)
            resolve_pin = external_drive;
        else if (external_drive === 1'bz)
            resolve_pin = internal_drive;
        else if (internal_drive === external_drive)
            resolve_pin = internal_drive;
        else
            resolve_pin = 1'bx;
    endfunction

    task automatic check_pins(input string phase);
        logic [GPIO_WIDTH-1:0] expected_pins;
        for (int i = 0; i < GPIO_WIDTH; i++) begin
            expected_pins[i] = resolve_pin(
                expected_direction[i] ? expected_output[i] : 1'bz,
                external_enable[i] ? external_value[i] : 1'bz);
        end
        check_count++;
        if ((gpio_pins !== expected_pins) || (gpio_input !== expected_pins))
            $fatal(1,
                "%s / %s at %0t cycle=%0d: dir=%b out=%b ext_en=%b ext=%b expected=%b pins=%b readback=%b",
                current_test, phase, $time, cycle_count,
                expected_direction, expected_output, external_enable,
                external_value, expected_pins, gpio_pins, gpio_input);
    endtask

    // Stimulus is driven away from the sampling edge. Check both before the
    // edge (no premature changes) and after nonblocking assignments settle.
    task automatic cycle(input logic reset_value,
                         input logic direction_enable,
                         input logic output_enable,
                         input logic [GPIO_WIDTH-1:0] data);
        @(negedge clk);
        reset = reset_value;
        set_io_mask = direction_enable;
        set_gpio = output_enable;
        mask = data;
        #1;
        check_pins("before rising edge");
        @(posedge clk);
        cycle_count++;
        if (reset_value) begin
            expected_direction = '0;
            expected_output = '0;
        end
        else begin
            if (direction_enable) expected_direction = data;
            if (output_enable) expected_output = data;
        end
        #1;
        check_pins("after rising edge");
    endtask

    task automatic drive_external(input logic [GPIO_WIDTH-1:0] enables,
                                  input logic [GPIO_WIDTH-1:0] values);
        @(negedge clk);
        external_enable = enables;
        external_value = values;
        #1;
        // Readback is combinational: no rising edge is needed.
        check_pins("external input changed between rising edges");
    endtask

    task automatic test_startup_reset();
        start_test("startup reset and released pins");
        repeat (2) @(posedge clk);
        #1;
        check_pins("initial reset");
        cycle(1'b0, 1'b0, 1'b0, '0);
    endtask

    task automatic test_output_values_and_directions();
        start_test("every direction mask against every output value");
        drive_external('0, '0);
        cycle(1'b1, 1'b0, 1'b0, '0);
        for (int direction = 0; direction < NUM_VALUES; direction++) begin
            cycle(1'b0, 1'b1, 1'b0, GPIO_WIDTH'(direction));
            for (int value = 0; value < NUM_VALUES; value++)
                cycle(1'b0, 1'b0, 1'b1, GPIO_WIDTH'(value));
        end
    endtask

    task automatic test_inputs_and_readback();
        start_test("every direction mask against every external input value");
        cycle(1'b1, 1'b0, 1'b0, '0);
        cycle(1'b0, 1'b0, 1'b1, 8'hA5);
        for (int direction = 0; direction < NUM_VALUES; direction++) begin
            drive_external('0, '0);
            cycle(1'b0, 1'b1, 1'b0, GPIO_WIDTH'(direction));
            // Only input pins are driven externally in this test.
            for (int value = 0; value < NUM_VALUES; value++)
                drive_external(~GPIO_WIDTH'(direction), GPIO_WIDTH'(value));
        end
        drive_external('0, '0);
    endtask

    task automatic test_enables_and_retention();
        start_test("enable combinations, consecutive writes and retained values");
        cycle(1'b1, 1'b0, 1'b0, '0);
        for (int value = 0; value < NUM_VALUES; value++) begin
            // Both enables must update their respective registers together.
            cycle(1'b0, 1'b1, 1'b1, GPIO_WIDTH'(value));
            cycle(1'b0, 1'b0, 1'b0, ~GPIO_WIDTH'(value));
            // Reveal output bits previously hidden by input direction bits.
            cycle(1'b0, 1'b1, 1'b0, '1);
            // Consecutive writes with the output enable continuously high.
            cycle(1'b0, 1'b0, 1'b1, ~GPIO_WIDTH'(value));
            cycle(1'b0, 1'b0, 1'b1, GPIO_WIDTH'(value));
            // Writes while pins are inputs must still be stored.
            cycle(1'b0, 1'b1, 1'b0, '0);
            cycle(1'b0, 1'b0, 1'b1, ~GPIO_WIDTH'(value));
            cycle(1'b0, 1'b1, 1'b0, '1);
        end
        repeat (16) cycle(1'b0, 1'b0, 1'b0, '0);
    endtask

    task automatic test_reset_from_all_states();
        logic [GPIO_WIDTH-1:0] direction_bits;
        start_test("reset from every direction/output state");
        // All 65,536 pairs for this 8-bit DUT. Also vary pending enables,
        // reset duration, and external inputs still driven during reset.
        for (int direction = 0; direction < NUM_VALUES; direction++) begin
            direction_bits = GPIO_WIDTH'(direction);
            for (int value = 0; value < NUM_VALUES; value++) begin
                drive_external('0, '0);
                cycle(1'b0, 1'b0, 1'b1, GPIO_WIDTH'(value));
                cycle(1'b0, 1'b1, 1'b0, direction_bits);
                drive_external(~direction_bits, ~GPIO_WIDTH'(value));
                cycle(1'b1, (value & 1) != 0, (value & 2) != 0,
                      ~GPIO_WIDTH'(value));
                if ((value & 3) == 0)
                    cycle(1'b1, 1'b1, 1'b1, '1);
                cycle(1'b0, 1'b0, 1'b0, '1);
                drive_external('0, '0);
                // Released pins alone do not prove the output value reset.
                // Enable all outputs to expose and check their stored zeros.
                cycle(1'b0, 1'b1, 1'b0, '1);
            end
        end
    endtask

    task automatic test_reset_timing();
        start_test("synchronous reset timing and pulses between edges");
        cycle(1'b0, 1'b1, 1'b1, '1);
        cycle(1'b0, 1'b0, 1'b0, '0);
        // A pulse entirely between rising edges must have no effect.
        @(negedge clk);
        reset = 1'b1;
        #1;
        check_pins("reset asserted without a rising edge");
        #1;
        reset = 1'b0;
        #1;
        check_pins("reset pulse removed before rising edge");
        cycle(1'b0, 1'b0, 1'b0, '0);
        cycle(1'b1, 1'b1, 1'b1, '1);
        repeat (4) cycle(1'b1, 1'b1, 1'b1, '1);
        cycle(1'b0, 1'b0, 1'b0, '1);
        cycle(1'b0, 1'b1, 1'b0, '1);
    endtask

    task automatic test_four_state_inputs_and_contention();
        start_test("floating inputs, X/Z readback and simulated contention");
        cycle(1'b1, 1'b0, 1'b0, '0);
        cycle(1'b0, 1'b0, 1'b0, '0);
        drive_external('1, 'x);
        drive_external('1, 'z);
        for (int i = 0; i < GPIO_WIDTH; i++) begin
            drive_external(GPIO_WIDTH'(1 << i), '1);
            drive_external(GPIO_WIDTH'(1 << i), '0);
        end
        drive_external('0, '0);
        cycle(1'b0, 1'b1, 1'b0, '1);
        for (int value = 0; value < NUM_VALUES; value++) begin
            cycle(1'b0, 1'b0, 1'b1, GPIO_WIDTH'(value));
            drive_external('1, GPIO_WIDTH'(value)); // Agreeing drivers.
            drive_external('1, ~GPIO_WIDTH'(value)); // Opposing drivers -> X.
            drive_external('0, '0); // Release restores the output value.
        end
    endtask

    // Fixed-seed pseudo-random sequence makes failures reproducible.
    function automatic logic [31:0] next_random(input logic [31:0] value);
        logic [31:0] result;
        result = value ^ (value << 13);
        result = result ^ (result >> 17);
        result = result ^ (result << 5);
        return result;
    endfunction

    task automatic test_random_sequences();
        logic [31:0] random_state;
        start_test("10000 reproducible mixed transactions (seed 1BADF00D)");
        random_state = 32'h1BADF00D;
        drive_external('0, '0);
        cycle(1'b1, 1'b0, 1'b0, '0);
        for (int transaction = 0; transaction < 10000; transaction++) begin
            random_state = next_random(random_state);
            // Arbitrary external drive masks include simulated contention.
            drive_external(random_state[15:8], random_state[23:16]);
            cycle(random_state[31:28] == 4'h0,
                  random_state[24], random_state[25], random_state[7:0]);
        end
        drive_external('0, '0);
    endtask

    initial begin
        test_startup_reset();
        test_output_values_and_directions();
        test_inputs_and_readback();
        test_enables_and_retention();
        test_reset_from_all_states();
        test_reset_timing();
        test_four_state_inputs_and_contention();
        test_random_sequences();
        $display("PASS: %0d test groups, %0d cycles, %0d pin/readback checks",
                 test_count, cycle_count, check_count);
        $finish;
    end
endmodule
