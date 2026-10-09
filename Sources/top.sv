module top (
    input  logic        clk,
    input  logic        uart_rx,
    output logic        uart_tx
);

    wire [1:0] gpio_pins;
    assign gpio_pins[0] = uart_rx;
    assign uart_tx = gpio_pins[1]

    gpio #(
        .GPIO_WIDTH(2)
    ) gpio_inst (
        .clk(clk),
        .reset(gpio_reset),
        .set_io_mask(gpio_set_io_mask),
        .set_gpio(set_gpio),
        .mask(gpio_mask),
        .gpio(gpio_pins),
        .gpio_input(gpio_input)
    )


    // always_ff @(posedge clk) begin
        
    // end


endmodule