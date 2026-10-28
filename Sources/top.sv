module top #(
    parameter int WORD_WIDTH    = 16,
    parameter int NUM_REGISTERS = 8,
    parameter int MEMORY_SIZE   = 1024,
    parameter int GPIO_WIDTH    = 8,
    parameter string PROGRAM_FILE = "",
    parameter int CLOCK_HZ = 100_000_000,
    parameter int BAUD = 115200,
    parameter int PROGRAM_WORDS = 1024
)(
    input  logic clk,
    input  logic reset,
    input  logic uart_rx,
    output wire  uart_tx,
    // Basys 3: GPIO bits 0..7 drive LEDs LD0..LD7 via the XDC.
    inout  wire [GPIO_WIDTH-1:0] gpio_pins
);

    initial if (WORD_WIDTH != 16) $fatal(1, "Host loader requires 16-bit instruction memory");

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

    wire running, host_reset, load_write, send_valid, send_ready;
    wire [$clog2(MEMORY_SIZE)-1:0] load_address;
    wire [15:0] load_data;
    wire [7:0] send_data;
    wire rx_error, load_error;
    host_uart #(.CLOCK_HZ(CLOCK_HZ), .BAUD(BAUD), .MEMORY_SIZE(MEMORY_SIZE)) host(
        .clk(clk), .reset(core_reset), .uart_rx(uart_rx), .uart_tx(uart_tx),
        .running(running), .cpu_reset(host_reset), .load_address(load_address),
        .load_write(load_write), .load_data(load_data), .send_data(send_data),
        .send_valid(send_valid), .send_ready(send_ready), .rx_error(rx_error), .load_error(load_error));

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
        .reset(core_reset | host_reset),
        .run_enable(running), .send_data(send_data), .send_valid(send_valid), .send_ready(send_ready),
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
        .address(load_write ? load_address : mem_address),
        .write_enable(load_write | mem_write_enable),
        .write_data(load_write ? load_data : mem_write_data),
        .read_data(mem_read_data)
    );
endmodule
