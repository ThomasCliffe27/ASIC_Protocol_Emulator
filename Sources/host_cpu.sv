// CPU control and byte-to-word loader. Memory pointer counts 16-bit words.
// Odd payload bytes carry across packets. Pointer reset/CPU reset discard a half word.
module host_cpu #(parameter int MEMORY_SIZE=1024)(
    input logic clk, reset,
    input logic [7:0] command, input logic command_valid,
    input logic [7:0] payload, input logic payload_valid,
    output logic running, output logic cpu_reset,
    output wire [$clog2(MEMORY_SIZE)-1:0] address,
    output wire write_enable, output wire [15:0] write_data,
    output logic load_error
);
    logic [$clog2(MEMORY_SIZE):0] pointer;
    logic [7:0] low_byte;
    logic half_word, accept_load;
    assign address = pointer[$clog2(MEMORY_SIZE)-1:0];
    assign write_data = {payload,low_byte};
    assign write_enable = payload_valid && accept_load && half_word && pointer < MEMORY_SIZE && !running;
    always_ff @(posedge clk) begin
        cpu_reset <= 0;
        if (reset) begin
            running <= 0; cpu_reset <= 1; pointer <= 0;
            half_word <= 0; low_byte <= 0; accept_load <= 0; load_error <= 0;
        end else begin
            if (command_valid) case(command)
                0: begin accept_load <= !running; if (running) load_error <= 1; end
                1: begin pointer <= 0; half_word <= 0; load_error <= 0; end
                2: running <= 1;
                3: running <= 0;
                4: begin running <= 0; cpu_reset <= 1; half_word <= 0; end
                default: ;
            endcase
            if (payload_valid && accept_load && !running) begin
                if (pointer >= MEMORY_SIZE) load_error <= 1;
                else if (!half_word) begin low_byte <= payload; half_word <= 1; end
                else begin pointer <= pointer+1'b1; half_word <= 0; end
            end
        end
    end
endmodule
