module uart_tx #(
    parameter int CLK_FREQ = 100_000_000,
    parameter int BAUD_RATE = 9600
)(
    input  logic       clk,

    input  logic [7:0] data,
    input  logic       start,

    output logic       tx,
    output logic       busy
);

    localparam int CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

    typedef enum logic [1:0] {
        IDLE,
        START,
        SEND,
        STOP
    } state_t;

    state_t state = IDLE;

    logic [$clog2(CLKS_PER_BIT)-1:0] clk_count = '0;
    logic [2:0] bit_index = '0;
    logic [7:0] data_latch = '0;


    always_ff @(posedge clk) begin

        case (state)
            IDLE: begin
                clk_count <= '0;
                bit_index <= '0;
                busy <= 1'b0;
                tx <= 1'b1;

                if (start == 1'b1) begin
                    busy <= 1'b1;
                    data_latch <= data;
                    state <= START;
                end
            end

            START: begin
                tx <= 1'b0;
                if (clk_count == CLKS_PER_BIT - 1) begin
                    clk_count <= '0;
                    state <= SEND;
                end else begin
                    clk_count <= clk_count + 1;
                end
            end

            SEND: begin
                tx <= data_latch[bit_index];

                if (clk_count == CLKS_PER_BIT - 1) begin
                    clk_count <= '0;

                    if (bit_index == 3'd7) begin
                        bit_index <= '0;
                        state <= STOP;
                    end else begin
                        bit_index <= bit_index + 1;
                    end
                end else begin
                    clk_count <= clk_count + 1;
                end
            end

            STOP: begin
                tx <= 1'b1;
                if (clk_count == CLKS_PER_BIT - 1) begin
                    clk_count <= '0;
                    busy <= '0;
                    state <= IDLE;
                end else begin
                    clk_count <= clk_count + 1;
                end
            end

            default: begin
                state <= IDLE;
            end
        endcase
    end
endmodule