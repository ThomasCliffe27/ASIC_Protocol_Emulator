`timescale 1ns/1ps

// Compile with Sources/memory.sv and select memory_tb as the simulation top.
module memory_tb;
    wire default_done, narrow_done, wide_done, single_bit_done;

    memory_test_case #(.WORD_WIDTH(16), .MEMORY_SIZE(1024)) default_case(default_done);
    memory_test_case #(.WORD_WIDTH(7), .MEMORY_SIZE(13)) narrow_case(narrow_done);
    memory_test_case #(.WORD_WIDTH(33), .MEMORY_SIZE(17)) wide_case(wide_done);
    memory_test_case #(.WORD_WIDTH(1), .MEMORY_SIZE(2)) single_bit_case(single_bit_done);

    initial begin
        #20000000;
        $fatal(1, "Memory regression timed out");
    end

    initial begin
        wait (default_done && narrow_done && wide_done && single_bit_done);
        $display("PASS: all four memory configurations completed");
        $finish;
    end
endmodule

module memory_test_case #(
    parameter int WORD_WIDTH = 16,
    parameter int MEMORY_SIZE = 1024
)(output bit done = 1'b0);
    localparam int ADDRESS_WIDTH = $clog2(MEMORY_SIZE);
    // Exhaust every word value up to 16 bits; wider words get walking-bit tests.
    localparam int EXHAUSTIVE_BITS = (WORD_WIDTH < 16) ? WORD_WIDTH : 16;
    localparam int NUM_VALUES = 1 << EXHAUSTIVE_BITS;

    logic clk = 1'b0;
    logic [ADDRESS_WIDTH-1:0] address = '0;
    logic write_enable = 1'b0;
    logic [WORD_WIDTH-1:0] write_data = '0;
    wire [WORD_WIDTH-1:0] read_data;

    memory #(.WORD_WIDTH(WORD_WIDTH), .MEMORY_SIZE(MEMORY_SIZE)) dut (
        .clk(clk), .address(address), .write_enable(write_enable),
        .write_data(write_data), .read_data(read_data)
    );

    // Independent reference state; no DUT internals are read or initialized.
    // There is no reset or initialization in memory.sv: unwritten words are X.
    logic [WORD_WIDTH-1:0] expected_memory [0:MEMORY_SIZE-1];
    logic [WORD_WIDTH-1:0] expected_read = 'x;
    int unsigned check_count = 0;
    int unsigned cycle_count = 0;
    int unsigned test_count = 0;
    string current_test = "startup";

    always #5 clk = ~clk;

    task automatic start_test(input string name);
        current_test = name;
        test_count++;
        $display("START %m: %s (width=%0d depth=%0d)", name, WORD_WIDTH, MEMORY_SIZE);
    endtask

    task automatic check_read(input string phase);
        check_count++;
        if (read_data !== expected_read)
            $fatal(1,
                "%m: %s / %s at %0t cycle=%0d: addr=%0d we=%b data=%h expected=%h actual=%h",
                current_test, phase, $time, cycle_count,
                address, write_enable, write_data, expected_read, read_data);
    endtask

    // Monitor EVERY rising edge, including edges between task transactions.
    // Read-before-write is intentional: a write returns the previous word.
    always @(posedge clk) begin
        cycle_count++;
        expected_read = expected_memory[address];
        if (write_enable)
            expected_memory[address] = write_data;
        #1;
        check_read("after rising edge");
    end

    // Drive away from the sampling edge. The output must retain its previous
    // value until the next rising edge, even when the read address changes.
    task automatic cycle(input int unsigned location,
                         input logic enable,
                         input logic [WORD_WIDTH-1:0] data);
        if (location >= MEMORY_SIZE)
            $fatal(1, "%m: invalid test address %0d", location);
        @(negedge clk);
        address = ADDRESS_WIDTH'(location);
        write_enable = enable;
        write_data = data;
        #1;
        check_read("before rising edge");
        @(posedge clk);
        #2; // Let the independent monitor and nonblocking assignments settle.
    endtask

    task automatic read_all();
        for (int location = 0; location < MEMORY_SIZE; location++)
            cycle(location, 1'b0, '0);
    endtask

    function automatic logic [WORD_WIDTH-1:0] alternating_pattern();
        logic [WORD_WIDTH-1:0] result;
        for (int bit_index = 0; bit_index < WORD_WIDTH; bit_index++)
            result[bit_index] = (bit_index % 2) != 0;
        return result;
    endfunction

    task automatic test_uninitialized_reads();
        start_test("unwritten locations return X");
        read_all();
        // The first write must also return X; only the next read sees data.
        cycle(MEMORY_SIZE - 1, 1'b1, '1);
        cycle(MEMORY_SIZE - 1, 1'b0, '0);
        cycle(0, 1'b0, '0);
    endtask

    task automatic test_full_memory_patterns();
        logic [WORD_WIDTH-1:0] pattern;
        start_test("all addresses: zeros, ones, checkerboards and address patterns");
        for (int pass = 0; pass < 6; pass++) begin
            for (int location = 0; location < MEMORY_SIZE; location++) begin
                case (pass)
                    0: pattern = '0;
                    1: pattern = '1;
                    2: pattern = alternating_pattern();
                    3: pattern = ~alternating_pattern();
                    4: pattern = WORD_WIDTH'(location);
                    5: pattern = ~WORD_WIDTH'(location);
                endcase
                cycle(location, 1'b1, pattern);
            end
            read_all();
            for (int location = MEMORY_SIZE - 1; location >= 0; location--)
                cycle(location, 1'b0, '1);
        end
    endtask

    task automatic test_walking_data_bits();
        logic [WORD_WIDTH-1:0] walking_bit;
        start_test("walking ones and zeros at every address");
        for (int bit_index = 0; bit_index < WORD_WIDTH; bit_index++) begin
            walking_bit = WORD_WIDTH'(1) << bit_index;
            for (int polarity = 0; polarity < 2; polarity++) begin
                for (int location = 0; location < MEMORY_SIZE; location++)
                    cycle(location, 1'b1, polarity ? ~walking_bit : walking_bit);
                read_all();
            end
        end
    endtask

    task automatic test_address_isolation();
        start_test("each address changed alone, with all other words checked");
        for (int location = 0; location < MEMORY_SIZE; location++)
            cycle(location, 1'b1, '0);
        // Scan every word while exactly one location holds ones. This detects
        // address aliases, stuck address bits and writes affecting neighbours.
        for (int target = 0; target < MEMORY_SIZE; target++) begin
            cycle(target, 1'b1, '1);
            read_all();
            cycle(target, 1'b1, '0);
        end
        read_all();
    endtask

    task automatic test_read_before_write();
        start_test("consecutive writes, old-data readback and boundary alternation");
        for (int target_index = 0; target_index < 3; target_index++) begin
            for (int value = 0; value < NUM_VALUES; value++)
                cycle((target_index == 0) ? 0 :
                      (target_index == 1) ? MEMORY_SIZE / 2 : MEMORY_SIZE - 1,
                      1'b1, WORD_WIDTH'(value));
            cycle((target_index == 0) ? 0 :
                  (target_index == 1) ? MEMORY_SIZE / 2 : MEMORY_SIZE - 1,
                  1'b0, '0);
        end
        for (int value = 0; value < 256; value++) begin
            cycle(0, 1'b1, WORD_WIDTH'(value));
            cycle(MEMORY_SIZE - 1, 1'b1, ~WORD_WIDTH'(value));
            cycle(0, 1'b0, '0);
            cycle(MEMORY_SIZE - 1, 1'b0, '0);
        end
    endtask

    task automatic test_enable_and_edge_timing();
        start_test("registered read timing, ignored writes and between-edge pulses");
        cycle(0, 1'b1, '0);
        cycle(MEMORY_SIZE - 1, 1'b1, '1);
        cycle(0, 1'b0, '1);

        @(negedge clk);
        address = ADDRESS_WIDTH'(MEMORY_SIZE - 1);
        write_enable = 1'b1;
        write_data = '0;
        #1;
        check_read("address change and write pulse without rising edge");
        #1;
        address = '0;
        write_data = '1;
        #1;
        check_read("data and address changed during pulse");
        write_enable = 1'b0;
        #1;
        check_read("write pulse removed before rising edge");
        // Neither word may have been written by the pulse.
        cycle(0, 1'b0, '1);
        cycle(MEMORY_SIZE - 1, 1'b0, '0);

        for (int repeat_index = 0; repeat_index < 64; repeat_index++) begin
            cycle(0, 1'b0, WORD_WIDTH'(repeat_index));
            cycle(MEMORY_SIZE - 1, 1'b0, ~WORD_WIDTH'(repeat_index));
        end
        read_all();
    endtask

    task automatic test_four_state_data();
        logic [WORD_WIDTH-1:0] mixed_data;
        start_test("stored X/Z data, disabled unknown writes and recovery");
        for (int bit_index = 0; bit_index < WORD_WIDTH; bit_index++) begin
            case (bit_index % 4)
                0: mixed_data[bit_index] = 1'b0;
                1: mixed_data[bit_index] = 1'b1;
                2: mixed_data[bit_index] = 1'bx;
                3: mixed_data[bit_index] = 1'bz;
            endcase
        end
        for (int location = 0; location < MEMORY_SIZE; location++) begin
            cycle(location, 1'b0, 'x);
            cycle(location, 1'b1, 'x);
            cycle(location, 1'b0, '0);
            cycle(location, 1'b1, 'z);
            cycle(location, 1'b0, '0);
            cycle(location, 1'b1, mixed_data);
            cycle(location, 1'b0, '1);
            cycle(location, 1'b1, '0);
            cycle(location, 1'b0, 'z);
        end
        read_all();
        // Unknown control values do not satisfy a procedural if in this RTL.
        cycle(0, 1'bx, '1);
        cycle(0, 1'bz, '1);
        cycle(0, 1'b0, '0);
    endtask

    function automatic logic [31:0] next_random(input logic [31:0] value);
        logic [31:0] result;
        result = value ^ (value << 13);
        result = result ^ (result >> 17);
        result = result ^ (result << 5);
        return result;
    endfunction

    task automatic test_random_sequences();
        logic [31:0] random_state;
        logic [WORD_WIDTH-1:0] random_data;
        int unsigned random_address;
        logic random_enable;
        start_test("10000 reproducible mixed transactions (seed 1BADF00D)");
        random_state = 32'h1BADF00D;
        for (int transaction = 0; transaction < 10000; transaction++) begin
            random_state = next_random(random_state);
            // Modulo keeps non-power-of-two configurations in range.
            random_address = random_state % MEMORY_SIZE;
            random_enable = random_state[31];
            for (int bit_index = 0; bit_index < WORD_WIDTH; bit_index++) begin
                random_state = next_random(random_state);
                random_data[bit_index] = random_state[0];
            end
            cycle(random_address, random_enable, random_data);
        end
        // Read every word after random traffic, including infrequent addresses.
        read_all();
    endtask

    initial begin
        for (int location = 0; location < MEMORY_SIZE; location++)
            expected_memory[location] = 'x;
        test_uninitialized_reads();
        test_full_memory_patterns();
        test_walking_data_bits();
        test_address_isolation();
        test_read_before_write();
        test_enable_and_edge_timing();
        test_four_state_data();
        test_random_sequences();
        // Leave the completed instance read-only while the others finish.
        @(negedge clk);
        write_enable = 1'b0;
        $display("PASS %m: %0d test groups, %0d cycles, %0d readback checks",
                 test_count, cycle_count, check_count);
        done = 1'b1;
    end
endmodule
