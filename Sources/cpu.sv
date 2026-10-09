module cpu #(
    parameter int WORD_WIDTH = 16,
    parameter int NUM_REGISTERS = 8

)(
    input logic clk,
    input logic reset,

    input logic set_io_mask,
    input logic set_gpio,
    input logic [GPIO_WIDTH-1:0] mask, //for both gpio and io_mask

    inout wire [GPIO_WIDTH-1:0] gpio,
    output logic [GPIO_WIDTH-1:0] gpio_input //outputs the gpio input
);

    logic [GPIO_WIDTH-1:0] gpio_out; //value to be output on gpio pins
    logic [GPIO_WIDTH-1:0] io_mask; //0 = input, 1 = output

    always_ff @(posedge clk) begin
        if (reset) begin
            gpio <= '0;
            io_mask <= '0;
        end
        else begin
            if (set_gpio) begin
                gpio_out <= mask;
            end
            if (set_io_mask) begin
                io_mask <= mask;
            end
        end
    end

    //assign gpio pins:
    generate
        for (genvar i = 0; i < GPIO_WIDTH; i++) begin
            assign gpio[i] = io_mask[i] ? gpio_out[i] : 1'bz;
        end
    endgenerate

    //Read gpio pins
    always_comb begin
        gpio_input = gpio;
    end
    
endmodule