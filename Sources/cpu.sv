module cpu #(
    parameter int WORD_WIDTH = 16,
    parameter int NUM_REGISTERS = 8,
    parameter int MEMORY_SIZE = 1024,
    parameter int GPIO_WIDTH = 8
)(
    input logic clk,
    input logic reset,

    //Memory
    output logic [$clog2(MEMORY_SIZE)-1:0] address,
    output logic write_enable,
    output logic [WORD_WIDTH-1:0] write_data,
    input logic [WORD_WIDTH-1:0] read_data,

    //GPIO
    output logic set_io_mask,
    output logic set_gpio,
    output logic [GPIO_WIDTH-1:0] mask, 
    input logic [GPIO_WIDTH-1:0] gpio_input  

);

    logic [WORD_WIDTH-1:0] regs [0:NUM_REGISTERS-1];
    logic [$clog2(MEMORY_SIZE)-1:0] pc;
    logic z_flag;

    logic [15:0] clk_count;

    logic [WORD_WIDTH-1:0] instr;
    logic [4:0] opcode; 
    logic [$clog2(NUM_REGISTERS)-1:0] Rx;
    logic [7:0] imm;

    typedef enum logic [2:0] {
        FETCH,
        FETCH_WAIT,
        DECODE,
        EXECUTE,
        MEMORY,
        WRITEBACK
    } cpu_state;

    cpu_state state;

    typedef enum logic [4:0] {
        OP_DELAY = 6'h00,
        OP_LDI = 6'h01,
        OP_SUB = 6'h02,
        OP_JMPZ = 6'h03,
        OP_SET = 6'h04
    } opcodes;

    always_ff @(posedge clk) begin
        if (reset) begin
            for (int i = 0; i < NUM_REGISTERS; i++) begin
                regs[i] <= '0;
            end
            pc <= '0;
            z_flag <= 0;
            clk_count <= '0;
            instr <= '0;
            opcode <= '0;
            imm <= '0;
            Rx <= '0;
            mask <= '0;
            set_gpio <= 1'b0;

            state <= FETCH;
        end 
        else begin 
            case(state)

                FETCH: begin
                    clk_count <= '0;
                    set_gpio <= 1'b0;
                    state <= FETCH_WAIT;
                end

                FETCH_WAIT: begin
                    instr <= read_data;
                    pc <= pc + 1'b1;
                    state <= DECODE;
                end

                DECODE: begin
                    opcode <= instr[15:11];
                    imm <= instr[10:3];
                    Rx <= instr[2:0];
                    state <= EXECUTE;
                end

                EXECUTE: begin
                    case(opcode)
                        OP_DELAY: begin
                            if (imm == 0 || clk_count == imm - 1'b1) begin
                                clk_count <= '0;
                                state <= FETCH;
                            end
                            else begin
                                clk_count <= clk_count + 1'b1;
                            end
                        end

                        OP_LDI: begin
                            regs[Rx] <= imm;
                            state <= FETCH;
                        end

                        OP_SUB: begin
                            regs[Rx] <= regs[Rx] - imm;
                            z_flag <= ((regs[Rx] - imm) == 0);
                            state <= FETCH;
                        end

                        OP_JMPZ: begin
                            if (z_flag) begin
                                pc <= regs[Rx];
                            end
                            state <= FETCH;
                        end

                        OP_SET: begin
                            mask <= regs[Rx];
                            set_gpio <= 1'b1;
                            state <= FETCH;
                        end

                        default: begin
                            state <= FETCH;
                        end

                    endcase
                end

                default: begin
                    state <= FETCH;
                end

            endcase  
        end             
    end                 

    assign address = pc;

endmodule