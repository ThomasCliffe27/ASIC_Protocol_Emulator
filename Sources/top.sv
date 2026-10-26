module top #(
    parameter int WORD_WIDTH    = 16,
    parameter int NUM_REGISTERS = 8,
    parameter int MEMORY_SIZE   = 1024,
    parameter int GPIO_WIDTH    = 8
)(
    input  logic clk,
    input  logic reset,
    input  logic uart_rx,
    output wire  uart_tx,
    // Basys 3: gpio_pins[2] (third GPIO bit) drives LED LD2 via the XDC.
    inout  wire [GPIO_WIDTH-1:0] gpio_pins
);

    wire [$clog2(MEMORY_SIZE)-1:0] mem_address;
    wire mem_write_enable;
    wire [WORD_WIDTH-1:0] mem_write_data;
    wire [WORD_WIDTH-1:0] mem_read_data;

    wire gpio_set_io_mask;
    wire set_gpio;
    wire [GPIO_WIDTH-1:0] gpio_mask;
    wire [GPIO_WIDTH-1:0] gpio_input;

    // UART is not yet implemented. Idle UART TX must be high.
    assign uart_tx = 1'b1;
    // uart_rx is reserved for a future UART receiver.

    gpio #(
        .GPIO_WIDTH(GPIO_WIDTH)
    ) gpio_inst (
        .clk(clk),
        .reset(reset),
        .set_io_mask(gpio_set_io_mask),
        .set_gpio(set_gpio),
        .mask(gpio_mask),
        .gpio(gpio_pins),
        .gpio_input(gpio_input)
    );

    cpu #(
        .WORD_WIDTH(WORD_WIDTH),
        .NUM_REGISTERS(NUM_REGISTERS),
        .MEMORY_SIZE(MEMORY_SIZE),
        .GPIO_WIDTH(GPIO_WIDTH)
    ) cpu_inst (
        .clk(clk),
        .reset(reset),
        .address(mem_address),
        .write_enable(mem_write_enable),
        .write_data(mem_write_data),
        .read_data(mem_read_data),
        .set_io_mask(gpio_set_io_mask),
        .set_gpio(set_gpio),
        .mask(gpio_mask),
        .gpio_input(gpio_input)
    );

    memory #(
        .WORD_WIDTH(WORD_WIDTH),
        .MEMORY_SIZE(MEMORY_SIZE)
    ) mem_inst (
        .clk(clk),
        .address(mem_address),
        .write_enable(mem_write_enable),
        .write_data(mem_write_data),
        .read_data(mem_read_data)
    );
endmodule
