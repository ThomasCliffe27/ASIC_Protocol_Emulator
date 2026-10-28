// Synchronous byte FIFO, combinational head, ready/valid handshakes.
module byte_fifo #(parameter int DEPTH = 256)(
    input logic clk, reset,
    input logic [7:0] in_data, input logic in_valid, output wire in_ready,
    output wire [7:0] out_data, output wire out_valid, input logic out_ready,
    output logic [$clog2(DEPTH+1)-1:0] count
);
    localparam int AW = (DEPTH > 1) ? $clog2(DEPTH) : 1;
    logic [7:0] storage [0:DEPTH-1];
    logic [AW-1:0] rd, wr;
    wire pop = out_valid && out_ready;
    wire push = in_valid && in_ready;
    assign out_valid = count != 0;
    assign in_ready = count < DEPTH || pop;
    assign out_data = storage[rd];
    always_ff @(posedge clk) begin
        if (reset) begin rd <= 0; wr <= 0; count <= 0; end
        else begin
            if (push) begin
                storage[wr] <= in_data;
                wr <= (wr == DEPTH-1) ? 0 : wr + 1'b1;
            end
            if (pop) rd <= (rd == DEPTH-1) ? 0 : rd + 1'b1;
            case ({push,pop})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: ;
            endcase
        end
    end
endmodule
