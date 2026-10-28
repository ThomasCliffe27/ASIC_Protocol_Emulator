// Host packet parser: only LOAD (00) has length + payload. Other bytes are commands.
// No inter-byte timeout: arbitrary host scheduling delays do not truncate packets.
module packet_rx (
    input logic clk, reset,
    input logic [7:0] data, input logic valid, output wire ready,
    output wire [7:0] command, output wire command_valid,
    output wire [7:0] payload, output wire payload_valid
);
    typedef enum logic [1:0] {COMMAND, LENGTH, PAYLOAD} state_t;
    state_t state;
    logic [7:0] remaining;
    assign ready = 1'b1;
    assign command = data;
    assign command_valid = valid && state == COMMAND;
    assign payload = data;
    assign payload_valid = valid && state == PAYLOAD;
    always_ff @(posedge clk) begin
        if (reset) begin state <= COMMAND; remaining <= 0; end
        else if (valid) case(state)
            COMMAND: if (data == 0) state <= LENGTH;
            LENGTH: begin remaining <= data; if (data != 0) state <= PAYLOAD; else state <= COMMAND; end
            PAYLOAD: begin remaining <= remaining-1'b1; if (remaining == 1) state <= COMMAND; end
            default: state <= COMMAND;
        endcase
    end
endmodule
