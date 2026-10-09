module memory #(
    parameter int WORD_WIDTH = 16,
    parameter int MEMORY_SIZE = 1024
)(
    input logic clk,

    input logic [$clog2(MEMORY_SIZE)-1:0] address,
    input logic write_enable,
    input logic [WORD_WIDTH-1:0] write_data,
    
    output logic [WORD_WIDTH-1:0] read_data
);

    logic [WORD_WIDTH-1:0] mem [0:MEMORY_SIZE-1];

    always_ff @(posedge clk) begin

        if (write_enable) begin
                mem[address] <= write_data;
        end

        read_data <= mem[address];
    end
    
endmodule