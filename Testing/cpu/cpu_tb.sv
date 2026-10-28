`timescale 1ns/1ps

// Compile with Sources/cpu.sv; select cpu_tb as top and use Run All.
// Optional: +PROGRAM_HEX=/absolute/path/to/Testing/cpu/cpu_program.hex
module cpu_tb;
    localparam int WORD_WIDTH = 16;
    localparam int NUM_REGISTERS = 8;
    localparam int MEMORY_SIZE = 1024;
    localparam int ADDRESS_WIDTH = $clog2(MEMORY_SIZE);
    localparam int GPIO_WIDTH = 8;
    localparam logic [4:0] OP_DELAY = 0, OP_LDI = 1, OP_SUB = 2,
                           OP_JMPZ = 3, OP_SET = 4, OP_DELAY_REG = 5;

    logic clk = 1'b0;
    logic reset = 1'b1;
    wire [ADDRESS_WIDTH-1:0] address;
    wire write_enable;
    wire [WORD_WIDTH-1:0] write_data;
    logic [WORD_WIDTH-1:0] read_data;
    wire set_io_mask, set_gpio;
    wire [GPIO_WIDTH-1:0] mask;
    logic [GPIO_WIDTH-1:0] gpio_input = '0;

    cpu dut (
        .clk(clk), .reset(reset), .run_enable(1'b1), .send_ready(1'b1), .address(address),
        .write_enable(write_enable), .write_data(write_data), .read_data(read_data),
        .set_io_mask(set_io_mask), .set_gpio(set_gpio), .mask(mask), .gpio_input(gpio_input)
    );

    // Instruction ROM uses the same registered read timing as memory.sv.
    // Keep the memory response clocked: an asynchronous ROM can hide fetch bugs.
    logic [15:0] program_memory [0:MEMORY_SIZE-1];
    always @(posedge clk)
        read_data <= program_memory[address];

    // Architectural reference model. No DUT registers, state or decode signals
    // are inspected. Predict instruction effects and their specified timing
    // from the program, rather than copying the DUT state machine.
    logic [15:0] expected_regs [0:NUM_REGISTERS-1];
    logic [ADDRESS_WIDTH-1:0] expected_pc = '0;
    logic expected_z = 1'b0;
    logic expected_set_gpio = 1'b0;
    logic expected_set_io_mask = 1'b1;
    logic [GPIO_WIDTH-1:0] expected_mask = '1;
    logic [15:0] model_instruction;
    logic [15:0] subtraction_result;
    int instruction_age = 0;
    int instruction_cycles = 4;
    int unsigned retired_count = 0;
    int unsigned gpio_write_count = 0;
    int unsigned cycle_count = 0;
    int unsigned check_count = 0;
    int unsigned test_count = 0;
    int program_length = 0;
    string current_test = "startup";

    always #5 clk = ~clk;

    initial begin
        #200000000;
        $fatal(1, "CPU regression timed out during %s", current_test);
    end

    function automatic logic [15:0] encode(input logic [4:0] opcode,
                                          input logic [7:0] immediate,
                                          input logic [2:0] reg_index);
        return {opcode, immediate, reg_index};
    endfunction

    task automatic start_test(input string name);
        current_test = name;
        test_count++;
        $display("START %s", name);
    endtask

    task automatic check_ports(input string phase);
        check_count++;
        if (address !== expected_pc || write_enable !== 1'b0 || write_data !== 16'b0 ||
            set_gpio !== expected_set_gpio || set_io_mask !== expected_set_io_mask ||
            mask !== expected_mask)
            $fatal(1,
                "%s / %s at %0t cycle=%0d retired=%0d age=%0d instr=%h: pc=%h expected_pc=%h we=%b wd=%h set=%b/%b dir=%b/%b mask=%h/%h",
                current_test, phase, $time, cycle_count, retired_count, instruction_age,
                model_instruction, address, expected_pc, write_enable, write_data,
                set_gpio, expected_set_gpio, set_io_mask, expected_set_io_mask,
                mask, expected_mask);
    endtask

    always @(posedge clk) begin
        cycle_count++;
        if (reset) begin
            for (int r = 0; r < NUM_REGISTERS; r++) expected_regs[r] = '0;
            expected_pc = '0;
            expected_z = 1'b0;
            expected_mask = '1;
            expected_set_gpio = 1'b0;
            expected_set_io_mask = 1'b1;
            instruction_age = 0;
            retired_count = 0;
            gpio_write_count = 0;
            model_instruction = '0;
        end else begin
            expected_set_io_mask = 1'b0;
            instruction_age++;
            if (instruction_age == 1) begin
                expected_set_gpio = 1'b0;
                model_instruction = program_memory[expected_pc];
                // Three fetch/decode clocks plus one execution clock, except
                // DELAY N spends max(1,N) execution clocks.
                instruction_cycles = 4;
                if (model_instruction[15:11] == OP_DELAY && model_instruction[10:3] > 0)
                    instruction_cycles = 3 + int'(model_instruction[10:3]);
                if (model_instruction[15:11] == OP_DELAY_REG &&
                    expected_regs[model_instruction[2:0]] > 0)
                    instruction_cycles = 3 + int'(expected_regs[model_instruction[2:0]]);
            end
            // Fetch advances the address before the instruction completes.
            if (instruction_age == 2) expected_pc = expected_pc + 1'b1;
            if (instruction_age == instruction_cycles) begin
                case (model_instruction[15:11])
                    OP_LDI: expected_regs[model_instruction[2:0]] = {8'b0, model_instruction[10:3]};
                    OP_SUB: begin
                        subtraction_result = expected_regs[model_instruction[2:0]] -
                                             {8'b0, model_instruction[10:3]};
                        expected_regs[model_instruction[2:0]] = subtraction_result;
                        expected_z = (subtraction_result == 0);
                    end
                    OP_JMPZ: if (expected_z)
                        expected_pc = ADDRESS_WIDTH'(expected_regs[model_instruction[2:0]]);
                    OP_SET: begin
                        expected_mask = GPIO_WIDTH'(expected_regs[model_instruction[2:0]]);
                        expected_set_gpio = 1'b1;
                        gpio_write_count++;
                    end
                    default: begin end // DELAY and unsupported opcodes have no data effects.
                endcase
                retired_count++;
                instruction_age = 0;
            end
        end
        #1;
        check_ports("after rising edge");
    end

    task automatic prepare_program();
        @(negedge clk);
        reset = 1'b1;
        for (int location = 0; location < MEMORY_SIZE; location++)
            program_memory[location] = encode(OP_DELAY, 0, 0);
        program_length = 0;
        repeat (2) @(posedge clk);
        #2;
    endtask

    task automatic emit(input logic [4:0] opcode, input logic [7:0] immediate,
                        input logic [2:0] reg_index);
        if (program_length >= MEMORY_SIZE) $fatal(1, "Test program exceeds ROM size");
        program_memory[program_length] = encode(opcode, immediate, reg_index);
        program_length++;
    endtask

    task automatic release_reset();
        @(negedge clk);
        reset = 1'b0;
        #1;
        check_ports("reset removed without a rising edge");
    endtask

    task automatic run_instructions(input int count);
        int unsigned target;
        target = retired_count + count;
        while (retired_count < target) @(negedge clk);
    endtask

    task automatic test_reset_and_registers();
        start_test("reset state, all cleared registers and GPIO direction pulse");
        prepare_program();
        for (int r = 0; r < NUM_REGISTERS; r++) emit(OP_SET, 0, 3'(r));
        release_reset();
        run_instructions(NUM_REGISTERS);
        if (gpio_write_count != NUM_REGISTERS || mask !== 8'b0)
            $fatal(1, "Reset register readback failed");
    endtask

    task automatic test_load_immediates();
        start_test("every immediate in every register, register isolation and consecutive SETs");
        for (int target = 0; target < NUM_REGISTERS; target++) begin
            prepare_program();
            // Distinct sentinels in the other registers reveal wrong-register writes.
            for (int r = 0; r < NUM_REGISTERS; r++) emit(OP_LDI, 8'(r + 160), 3'(r));
            for (int value = 0; value < 256; value++) begin
                emit(OP_LDI, 8'(value), 3'(target));
                emit(OP_SET, 0, 3'(target));
            end
            for (int r = 0; r < NUM_REGISTERS; r++) emit(OP_SET, 0, 3'(r));
            release_reset();
            run_instructions(program_length);
        end
    endtask

    task automatic test_subtraction();
        start_test("all 65536 byte operand pairs, underflow, zero flag and register selection");
        // Rotate the destination register across operand pairs. A branch after
        // each subtraction makes the zero flag observable at the address port.
        for (int lhs = 0; lhs < 256; lhs++) begin
            // Eight pairs per program leave room for result and branch probes.
            for (int first_rhs = 0; first_rhs < 256; first_rhs += 8) begin
                prepare_program();
                for (int rhs = first_rhs; rhs < first_rhs + 8; rhs++) begin
                    emit(OP_LDI, 8'(lhs), 3'(rhs));
                    emit(OP_SUB, 8'(rhs), 3'(rhs));
                    emit(OP_SET, 0, 3'(rhs));
                    // LDI must preserve z. Jump over one observable SET only
                    // when the subtraction was zero, then continue the batch.
                    emit(OP_LDI, 8'(program_length + 3), 3'(rhs + 1));
                    emit(OP_JMPZ, 0, 3'(rhs + 1));
                    emit(OP_SET, 0, 3'(rhs + 1));
                end
                release_reset();
                run_instructions(program_length - ((lhs >= first_rhs && lhs < first_rhs + 8) ? 1 : 0));
            end
        end
        // Expose the upper result bits through a branch target after underflow.
        prepare_program();
        emit(OP_SUB, 1, 0); // R0 = FFFF, z=0.
        emit(OP_SUB, 0, 1); // R1 = 0, z=1.
        emit(OP_JMPZ, 0, 0);
        program_memory[MEMORY_SIZE - 1] = encode(OP_SET, 0, 0);
        release_reset();
        run_instructions(3);
        if (address !== 10'h3FF) $fatal(1, "Underflow or jump truncation failed");
        run_instructions(1);
        if (address !== 10'b0 || mask !== 8'hFF) $fatal(1, "PC wraparound failed");
    endtask

    task automatic test_branches();
        int scratch, preserve;
        start_test("taken/untaken JMPZ for every register and zero-flag persistence");
        for (int target = 0; target < NUM_REGISTERS; target++) begin
            scratch = (target + 1) % NUM_REGISTERS;
            preserve = (target + 2) % NUM_REGISTERS;
            prepare_program();
            emit(OP_LDI, 10, 3'(target)); // 0
            emit(OP_JMPZ, 0, 3'(target)); // 1: initial z=0, fall through.
            emit(OP_LDI, 1, 3'(scratch)); // 2
            emit(OP_SUB, 1, 3'(scratch)); // 3: z=1.
            emit(OP_LDI, 7, 3'(preserve)); // 4: must preserve z.
            emit(OP_SET, 0, 3'(preserve)); // 5: must preserve z.
            emit(OP_DELAY, 2, 0); // 6: must preserve z.
            emit(OP_JMPZ, 0, 3'(target)); // 7: jump to 10.
            emit(OP_SET, 0, 3'(scratch)); // 8: skipped.
            emit(OP_SET, 0, 3'(scratch)); // 9: skipped.
            emit(OP_SET, 0, 3'(target)); // 10: must preserve z.
            emit(OP_SUB, 1, 3'(scratch)); // 11: FFFF, z=0.
            emit(OP_JMPZ, 0, 3'(target)); // 12: fall through.
            emit(OP_SET, 0, 3'(scratch)); // 13
            release_reset();
            run_instructions(12);
            if (address !== 10'd14 || gpio_write_count != 3 || mask !== 8'hFF)
                $fatal(1, "Branch path or flag persistence failed for R%0d", target);
        end
    endtask

    task automatic test_delays_and_invalid_opcodes();
        start_test("exact timing for all DELAY values and all unsupported opcodes");
        prepare_program();
        emit(OP_LDI, 165, 0);
        for (int value = 0; value < 256; value++) begin
            emit(OP_SET, 0, 0);
            emit(OP_DELAY, 8'(value), 0);
        end
        for (int opcode = 6; opcode < 32; opcode++) begin
            emit(5'(opcode), 255, 7);
            emit(OP_SET, 0, 0);
        end
        release_reset();
        run_instructions(program_length);
        if (gpio_write_count != 282 || mask !== 8'hA5)
            $fatal(1, "Delay/unsupported opcode output count failed");
    endtask

    // Build a known full-width register value using only the public ISA.
    task automatic emit_load_word(input int unsigned value, input logic [2:0] reg_index);
        int unsigned remaining;
        if (value < 256) begin
            emit(OP_LDI, 8'(value), reg_index);
        end else begin
            emit(OP_LDI, 0, reg_index);
            remaining = 65536 - value;
            while (remaining > 255) begin
                emit(OP_SUB, 255, reg_index);
                remaining -= 255;
            end
            if (remaining != 0) emit(OP_SUB, 8'(remaining), reg_index);
        end
    endtask

    task automatic test_register_delay_values();
        int unsigned started;
        start_test("register DELAY: all byte counts in all registers, exact timing and retained values");
        for (int r = 0; r < NUM_REGISTERS; r++) begin
            prepare_program();
            for (int value = 0; value < 256; value++) begin
                emit(OP_LDI, 8'(value), 3'(r));
                emit(OP_DELAY_REG, 0, 3'(r));
                emit(OP_SET, 0, 3'(r));
            end
            release_reset();
            started = cycle_count;
            run_instructions(program_length);
            // Sum(max(1,N)+3+4+4) for N=0..255, independent of the model.
            if (cycle_count - started != 35457 || gpio_write_count != 256 || mask !== 8'hFF)
                $fatal(1, "Register delay byte sweep failed for R%0d", r);
        end
    endtask

    task automatic test_register_delay_full_width();
        int unsigned counts [0:8] = '{256, 257, 511, 512, 1023, 32768, 65280, 65534, 65535};
        int unsigned load_count, started;
        start_test("full 16-bit register delays, upper bits, maximum count and mixed delay forms");
        for (int r = 0; r < NUM_REGISTERS; r++) begin
            foreach (counts[index]) begin
                prepare_program();
                emit_load_word(counts[index], 3'(r));
                load_count = program_length;
                emit(OP_DELAY_REG, 0, 3'(r));
                emit(OP_SET, 0, 3'(r));
                emit(OP_DELAY, 7, 0);
                // Reserved immediate bits do not affect the register form.
                emit(OP_DELAY_REG, 255, 3'(r));
                emit(OP_SET, 0, 3'(r));
                release_reset();
                run_instructions(load_count);
                started = cycle_count;
                run_instructions(1);
                if (cycle_count - started != counts[index] + 3)
                    $fatal(1, "Wrong first DELAY R%0d duration for count %0d", r, counts[index]);
                run_instructions(2); // SET and immediate DELAY 7.
                started = cycle_count;
                run_instructions(1);
                if (cycle_count - started != counts[index] + 3)
                    $fatal(1, "Register changed or counter retained state between delays");
                run_instructions(1);
                if (mask !== 8'(counts[index]) || gpio_write_count != 2)
                    $fatal(1, "Register DELAY modified the source register");
            end
        end
    endtask

    task automatic test_register_delay_flags();
        int scratch, branch_register;
        start_test("register DELAY preserves both zero-flag states and source registers");
        for (int r = 0; r < NUM_REGISTERS; r++) begin
            scratch = (r + 1) % NUM_REGISTERS;
            branch_register = (r + 2) % NUM_REGISTERS;
            for (int flag_value = 0; flag_value < 2; flag_value++) begin
                prepare_program();
                emit(OP_LDI, 37, 3'(r));             // 0
                emit(OP_LDI, 9, 3'(branch_register)); // 1
                emit(OP_LDI, 1, 3'(scratch));        // 2
                emit(OP_SUB, 8'(flag_value), 3'(scratch)); // 3: choose z=0/1.
                emit(OP_DELAY_REG, 0, 3'(r));        // 4: must preserve z.
                emit(OP_SET, 0, 3'(r));              // 5
                emit(OP_JMPZ, 0, 3'(branch_register)); // 6
                emit(OP_SET, 0, 3'(scratch));        // 7: skipped when z=1.
                emit(OP_DELAY, 0, 0);               // 8: skipped when z=1.
                emit(OP_SET, 0, 3'(r));              // 9
                release_reset();
                run_instructions(flag_value ? 8 : 10);
                if (address !== 10'd10 || mask !== 8'd37 ||
                    gpio_write_count != (flag_value ? 2 : 3))
                    $fatal(1, "Register delay damaged flags/registers for R%0d", r);
            end
        end
    endtask

    task automatic test_register_delay_reset();
        int unsigned started;
        start_test("reset cancels a 65535-clock register delay and restarts its full duration");
        prepare_program();
        emit_load_word(65535, 3); // LDI R3,0; SUB R3,1.
        emit(OP_DELAY_REG, 0, 3);
        emit(OP_SET, 0, 3);
        release_reset();
        run_instructions(2);
        repeat (1000) @(negedge clk);
        if (gpio_write_count != 0) $fatal(1, "Long delay finished prematurely");
        reset = 1'b1;
        #1;
        check_ports("reset during register delay before rising edge");
        repeat (3) @(posedge clk);
        #2;
        release_reset();
        started = cycle_count;
        run_instructions(3);
        if (cycle_count - started != 65546) // Two 4-clock loads plus 65535+3.
            $fatal(1, "Reset did not restart the full register delay");
        run_instructions(1);
        if (gpio_write_count != 1 || mask !== 8'hFF)
            $fatal(1, "Program did not resume correctly after register delay reset");
    endtask

    task automatic test_reset_during_execution();
        start_test("synchronous reset during fetch, decode, SET and active DELAY");
        for (int offset = 1; offset <= 20; offset++) begin
            prepare_program();
            emit(OP_LDI, 165, 0);
            emit(OP_SET, 0, 0);
            emit(OP_DELAY, 255, 0);
            emit(OP_SET, 0, 0);
            release_reset();
            repeat (offset) @(negedge clk);
            reset = 1'b1;
            #1;
            check_ports("reset asserted between rising edges");
            repeat (3) @(posedge clk);
            #2;
            release_reset();
            run_instructions(2);
            if (gpio_write_count != 1 || mask !== 8'hA5)
                $fatal(1, "CPU did not restart its program after reset");
        end
        // A reset pulse entirely between edges must have no effect.
        @(negedge clk);
        reset = 1'b1;
        #1;
        check_ports("short reset pulse asserted");
        #1;
        reset = 1'b0;
        #1;
        check_ports("short reset pulse removed");
        run_instructions(2);
    endtask

    function automatic logic [31:0] next_random(input logic [31:0] value);
        logic [31:0] result;
        result = value ^ (value << 13);
        result = result ^ (result >> 17);
        result = result ^ (result << 5);
        return result;
    endfunction

    task automatic test_random_programs();
        logic [31:0] random_state;
        start_test("four reproducible random programs, branches and arbitrary GPIO inputs");
        for (int seed = 0; seed < 4; seed++) begin
            prepare_program();
            random_state = 32'h1BADF00D + 32'(seed);
            for (int location = 0; location < MEMORY_SIZE; location++) begin
                random_state = next_random(random_state);
                // Opcodes 0..7 include both DELAY forms and unsupported no-ops.
                program_memory[location] = encode(5'(random_state[18:16]),
                                                  random_state[15:8], random_state[2:0]);
            end
            release_reset();
            repeat (20000) begin
                @(negedge clk);
                random_state = next_random(random_state);
                gpio_input = random_state[7:0];
                #1;
                check_ports("inputs changed without a rising edge");
            end
        end
    endtask

    task automatic test_assembled_program();
        string filename;
        int handle;
        start_test("assembler-generated readmemh program and skipped-branch output");
        prepare_program();
        if (!$value$plusargs("PROGRAM_HEX=%s", filename)) begin
            filename = "Testing/cpu/cpu_program.hex";
            handle = $fopen(filename, "r");
            if (handle == 0) begin
                filename = "cpu_program.hex";
                handle = $fopen(filename, "r");
            end
            if (handle == 0) begin
                filename = "../../../../../Testing/cpu/cpu_program.hex";
                handle = $fopen(filename, "r");
            end
        end else handle = $fopen(filename, "r");
        if (handle == 0)
            $fatal(1, "Cannot open cpu_program.hex; assemble cpu_program.asm and supply +PROGRAM_HEX=<path>");
        $fclose(handle);
        $readmemh(filename, program_memory, 0, 12);
        // Known words verify the file independently of the architectural model.
        if (program_memory[0] !== 16'h0950 || program_memory[1] !== 16'h2000 ||
            program_memory[2] !== 16'h1150 || program_memory[3] !== 16'h2000 ||
            program_memory[4] !== 16'h0841 || program_memory[5] !== 16'h1002 ||
            program_memory[6] !== 16'h1801 || program_memory[7] !== 16'h2001 ||
            program_memory[8] !== 16'h0018 || program_memory[9] !== 16'h0D2B ||
            program_memory[10] !== 16'h2003 || program_memory[11] !== 16'h2803 ||
            program_memory[12] !== 16'h2003)
            $fatal(1, "Assembled fixture does not contain the expected instruction words");
        release_reset();
        run_instructions(12);
        if (gpio_write_count != 4 || mask !== 8'hA5 || address !== 10'd13)
            $fatal(1, "Assembled program output sequence or branch failed");
    endtask

    initial begin
        test_reset_and_registers();
        test_load_immediates();
        test_subtraction();
        test_branches();
        test_delays_and_invalid_opcodes();
        test_register_delay_values();
        test_register_delay_full_width();
        test_register_delay_flags();
        test_register_delay_reset();
        test_reset_during_execution();
        test_random_programs();
        test_assembled_program();
        $display("PASS: %0d CPU test groups, %0d cycles, %0d port checks",
                 test_count, cycle_count, check_count);
        $finish;
    end
endmodule
