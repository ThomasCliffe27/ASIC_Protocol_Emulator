module memory #(
    parameter int WORD_WIDTH = 16,
    parameter int MEMORY_SIZE = 1024,
    parameter string INIT_FILE = "",
    parameter int INIT_WORDS = MEMORY_SIZE
)(
    input logic clk,

    input logic [$clog2(MEMORY_SIZE)-1:0] address,
    input logic write_enable,
    input logic [WORD_WIDTH-1:0] write_data,
    
    output logic [WORD_WIDTH-1:0] read_data
);

    logic [WORD_WIDTH-1:0] mem [0:MEMORY_SIZE-1];

    // Empty INIT_FILE preserves uninitialized RAM behaviour for unit tests.
    // Vivado embeds enabled initialization in the FPGA configuration bitstream.
    generate
        if (INIT_FILE != "") begin : initialize_memory
            initial begin
                if (INIT_WORDS < 1 || INIT_WORDS > MEMORY_SIZE)
                    $fatal(1, "INIT_WORDS must be between 1 and MEMORY_SIZE");
                for (int i = 0; i < MEMORY_SIZE; i++)
                    mem[i] = '0;
                $readmemh(INIT_FILE, mem, 0, INIT_WORDS - 1);
            end
        end
    endgenerate

    always_ff @(posedge clk) begin

        if (write_enable) begin
                mem[address] <= write_data;
        end

        read_data <= mem[address];
    end
    
endmodule
