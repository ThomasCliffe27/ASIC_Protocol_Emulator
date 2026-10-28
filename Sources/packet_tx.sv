// Each SEND emits [00,01,data]. Hold all bytes stable under backpressure.
module packet_tx (
    input logic clk, reset,
    input logic [7:0] payload, input logic payload_valid, output wire payload_ready,
    output wire [7:0] data, output wire valid, input logic ready
);
    logic [1:0] state;
    logic [7:0] saved;
    assign payload_ready = state == 0;
    assign valid = state != 0;
    assign data = state == 1 ? 8'h00 : state == 2 ? 8'h01 : saved;
    always_ff @(posedge clk) begin
        if (reset) begin state <= 0; saved <= 0; end
        else if (state == 0) begin
            if (payload_valid) begin saved <= payload; state <= 1; end
        end else if (ready) state <= state == 3 ? 0 : state+1'b1;
    end
endmodule
