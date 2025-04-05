module snn_register_file #(
    parameter WIDTH = 16,
    parameter REG_COUNT = 32
)(
    input wire clk,
    input wire reset,

    input wire wr_en,
    input wire rd_en,
    input wire [$clog2(REG_COUNT)-1:0] addr,
    input wire signed [WIDTH-1:0] data_in,
    output reg signed [WIDTH-1:0] data_out
);

    reg signed [WIDTH-1:0] registers [0:REG_COUNT-1];

    integer i;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < REG_COUNT; i = i + 1)
                registers[i] <= 0;
        end else if (wr_en) begin
            registers[addr] <= data_in;
        end
    end

    always @(*) begin
        if (rd_en)
            data_out = registers[addr];
        else
            data_out = 0;
    end

endmodule
