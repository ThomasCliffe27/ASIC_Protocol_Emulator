// 8N1 UART, rounded integer baud divider; RX input has a two-flop synchronizer.
module uart_rx #(parameter int CLOCK_HZ=100_000_000, BAUD=115200)(
    input logic clk, reset, rx,
    output logic [7:0] data, output logic valid, output logic framing_error
);
    localparam int TICKS=(CLOCK_HZ+BAUD/2)/BAUD;
    (* ASYNC_REG = "TRUE" *) logic [1:0] sync_rx = 2'b11;
    logic [7:0] shift;
    integer timer, bit_index;
    typedef enum logic [1:0] {IDLE, START, DATA, STOP} state_t;
    state_t state;
    always_ff @(posedge clk) begin
        sync_rx <= {sync_rx[0], rx};
        valid <= 0; framing_error <= 0;
        if (reset) begin
            state <= IDLE; timer <= 0; bit_index <= 0; data <= 0; shift <= 0;
            sync_rx <= 2'b11;
        end else case(state)
            IDLE: if (!sync_rx[1]) begin state <= START; timer <= TICKS/2-1; end
            START: if (timer != 0) timer <= timer-1;
                else if (sync_rx[1]) state <= IDLE;
                else begin state <= DATA; timer <= TICKS-1; bit_index <= 0; end
            DATA: if (timer != 0) timer <= timer-1;
                else begin
                    shift[bit_index] <= sync_rx[1]; timer <= TICKS-1;
                    if (bit_index == 7) state <= STOP;
                    else bit_index <= bit_index+1;
                end
            STOP: if (timer != 0) timer <= timer-1;
                else begin
                    if (sync_rx[1]) begin data <= shift; valid <= 1; end
                    else framing_error <= 1;
                    state <= IDLE;
                end
        endcase
    end
endmodule

module uart_tx #(parameter int CLOCK_HZ=100_000_000, BAUD=115200)(
    input logic clk, reset, input logic [7:0] data, input logic valid,
    output wire ready, output wire tx
);
    localparam int TICKS=(CLOCK_HZ+BAUD/2)/BAUD;
    logic [9:0] shift = 10'h3ff;
    integer timer, remaining;
    assign ready = remaining == 0;
    assign tx = shift[0];
    always_ff @(posedge clk) begin
        if (reset) begin shift <= 10'h3ff; timer <= 0; remaining <= 0; end
        else if (ready) begin
            if (valid) begin shift <= {1'b1,data,1'b0}; remaining <= 10; timer <= TICKS-1; end
        end else if (timer != 0) timer <= timer-1;
        else begin
            shift <= {1'b1,shift[9:1]}; remaining <= remaining-1; timer <= TICKS-1;
        end
    end
endmodule
