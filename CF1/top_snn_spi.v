module top_snn_spi #(
    parameter WIDTH = 16,
    parameter N_INPUTS = 2,
    parameter N1 = 3,
    parameter N2 = 2,
    parameter REG_COUNT = 32,
    parameter THRESHOLD = 100,
    parameter LEAK = 1,
    parameter REFRACTORY_TICKS = 10
)(
    input wire clk,
    input wire rst,

    // SPI interface
    input wire sclk,
    input wire mosi,
    input wire cs,
    output wire miso,

    // Inputs to the network (static for now)
    input wire signed [WIDTH-1:0] input_vector [N_INPUTS-1:0],

    output wire [N2-1:0] spike_out
);

    // SPI <-> Register File Interface
    wire wr_en;
    wire rd_en;
    wire [$clog2(REG_COUNT)-1:0] addr;
    wire signed [WIDTH-1:0] data_in;
    wire signed [WIDTH-1:0] data_out;

    // Register file
    snn_register_file #(
        .WIDTH(WIDTH),
        .REG_COUNT(REG_COUNT)
    ) reg_file (
        .clk(clk),
        .reset(rst),
        .wr_en(wr_en),
        .rd_en(rd_en),
        .addr(addr),
        .data_in(data_in),
        .data_out(data_out)
    );

    // SPI interface
    spi_slave_to_registers #(
        .WIDTH(WIDTH),
        .REG_ADDR_WIDTH($clog2(REG_COUNT)),
        .REG_COUNT(REG_COUNT)
    ) spi (
        .clk(clk),
        .rst(rst),
        .sclk(sclk),
        .mosi(mosi),
        .cs(cs),
        .miso(miso),
        .wr_en(wr_en),
        .rd_en(rd_en),
        .addr(addr),
        .data_in(data_in),
        .data_out(data_out)
    );

    // NOTE: Weights must be hardcoded or mapped from reg_file separately in synthesis
    // Example hardcoded weights for now (to keep synthesizable for simulation)
    localparam signed [WIDTH-1:0] W_INPUT_TO_L1 [N_INPUTS-1:0][N1-1:0] = '{
        '{16'sd1, 16'sd1, 16'sd1},
        '{16'sd1, 16'sd1, 16'sd1}
    };

    localparam signed [WIDTH-1:0] W_L1_TO_L2 [N1-1:0][N2-1:0] = '{
        '{16'sd1, 16'sd1},
        '{16'sd1, 16'sd1},
        '{16'sd1, 16'sd1}
    };

    snn_2layer #(
        .WIDTH(WIDTH),
        .N_INPUTS(N_INPUTS),
        .N1(N1),
        .N2(N2),
        .THRESHOLD(THRESHOLD),
        .LEAK(LEAK),
        .REFRACTORY_TICKS(REFRACTORY_TICKS),
        .W_INPUT_TO_L1(W_INPUT_TO_L1),
        .W_L1_TO_L2(W_L1_TO_L2)
    ) snn_core (
        .clk(clk),
        .reset(rst),
        .input_vector(input_vector),
        .spike_out(spike_out)
    );

endmodule
