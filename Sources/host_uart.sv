// Transport boundary: UART -> 256-byte RX FIFO -> parser/control;
// CPU SEND -> packet serializer -> 64-byte TX FIFO -> UART.
module host_uart #(parameter int CLOCK_HZ=100_000_000, BAUD=115200, MEMORY_SIZE=1024)(
    input logic clk, reset, uart_rx, output wire uart_tx,
    output wire running, cpu_reset,
    output wire [$clog2(MEMORY_SIZE)-1:0] load_address,
    output wire load_write, output wire [15:0] load_data,
    input logic [7:0] send_data, input logic send_valid, output wire send_ready,
    output logic rx_error, output wire load_error
);
    wire [7:0] rx_data, rx_head, command, payload, tx_data, tx_head;
    wire rx_valid, rx_ready, rx_head_valid, parser_ready, frame_error;
    wire command_valid, payload_valid, tx_valid, tx_ready, tx_head_valid, uart_ready;
    uart_rx #(.CLOCK_HZ(CLOCK_HZ),.BAUD(BAUD)) receiver(
        .clk(clk),.reset(reset),.rx(uart_rx),.data(rx_data),.valid(rx_valid),.framing_error(frame_error));
    byte_fifo #(.DEPTH(256)) rx_fifo(.clk(clk),.reset(reset),
        .in_data(rx_data),.in_valid(rx_valid),.in_ready(rx_ready),
        .out_data(rx_head),.out_valid(rx_head_valid),.out_ready(parser_ready),.count());
    packet_rx parser(.clk(clk),.reset(reset),.data(rx_head),.valid(rx_head_valid),.ready(parser_ready),
        .command(command),.command_valid(command_valid),.payload(payload),.payload_valid(payload_valid));
    host_cpu #(.MEMORY_SIZE(MEMORY_SIZE)) control(.clk(clk),.reset(reset),
        .command(command),.command_valid(command_valid),.payload(payload),.payload_valid(payload_valid),
        .running(running),.cpu_reset(cpu_reset),.address(load_address),.write_enable(load_write),
        .write_data(load_data),.load_error(load_error));
    packet_tx serializer(.clk(clk),.reset(reset),.payload(send_data),.payload_valid(send_valid),
        .payload_ready(send_ready),.data(tx_data),.valid(tx_valid),.ready(tx_ready));
    byte_fifo #(.DEPTH(64)) tx_fifo(.clk(clk),.reset(reset),
        .in_data(tx_data),.in_valid(tx_valid),.in_ready(tx_ready),
        .out_data(tx_head),.out_valid(tx_head_valid),.out_ready(uart_ready),.count());
    uart_tx #(.CLOCK_HZ(CLOCK_HZ),.BAUD(BAUD)) transmitter(.clk(clk),.reset(reset),
        .data(tx_head),.valid(tx_head_valid),.ready(uart_ready),.tx(uart_tx));
    always_ff @(posedge clk) begin
        if (reset) rx_error <= 0;
        else if (frame_error || (rx_valid && !rx_ready)) rx_error <= 1;
    end
endmodule
