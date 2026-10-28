module top #(
    parameter int WORD_WIDTH    = 16,
    parameter int NUM_REGISTERS = 8,
    parameter int MEMORY_SIZE   = 1024,
    parameter int GPIO_WIDTH    = 8,
    parameter string PROGRAM_FILE = "uart_tx.hex",
    parameter int PROGRAM_WORDS = 73
)(
    input  logic clk,
    input  logic reset,
    input  logic uart_rx,
    output wire  uart_tx,
    // Basys 3: GPIO bits 0..7 drive LEDs LD0..LD7 via the XDC.
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

    // Synchronize both edges of the external button to the system clock.
    // Initial values hold the CPU in reset at FPGA configuration. Keeping the
    // core reset fully synchronous also avoids asynchronous block-RAM controls.
    (* ASYNC_REG = "TRUE" *) logic [1:0] reset_pipe = 2'b11;
    wire core_reset = reset_pipe[1];
    always_ff @(posedge clk) begin
        reset_pipe <= {reset_pipe[0], reset};
    end

    // Latch the same bit that GPIO captures on SET. A registered UART output
    // stays idle during startup and avoids glitches when GPIO leaves tri-state.
    logic uart_tx_value = 1'b1;
    always_ff @(posedge clk) begin
        if (core_reset)
            uart_tx_value <= 1'b1;
        else if (set_gpio)
            uart_tx_value <= gpio_mask[0];
    end

    // Route GPIO bit 0 to the board's UART TX pin.
    assign uart_tx = uart_tx_value;
    // uart_rx is reserved for a future UART receiver.

    gpio #(
        .GPIO_WIDTH(GPIO_WIDTH)
    ) gpio_inst (
        .clk(clk),
        .reset(core_reset),
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
        .reset(core_reset),
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
        .MEMORY_SIZE(MEMORY_SIZE),
        .INIT_FILE(PROGRAM_FILE),
        .INIT_WORDS(PROGRAM_WORDS)
    ) mem_inst (
        .clk(clk),
        .address(mem_address),
        .write_enable(mem_write_enable),
        .write_data(mem_write_data),
        .read_data(mem_read_data)
    );
endmodule
