`timescale 1ns/1ps

module conv1d_k1 #(
  parameter IN_CH      = 2,
  parameter OUT_CH     = 1,
  parameter DATA_WIDTH = 16
)(
  input  logic                         clk,
  input  logic                         en,
  input  logic signed [DATA_WIDTH-1:0] din0,
  input  logic signed [DATA_WIDTH-1:0] din1,
  output logic                         out_valid,
  output logic signed [DATA_WIDTH-1:0] dout0
);
  // weights
  reg signed [DATA_WIDTH-1:0] w0 = 3, w1 = 5;
  reg signed [DATA_WIDTH+8:0] acc;

  always @(posedge clk) begin
    if (en) begin
      acc        = w0*din0 + w1*din1;
      dout0 <= acc[DATA_WIDTH+4 -: DATA_WIDTH];
      out_valid  <= 1;
    end else begin
      out_valid <= 0;
    end
  end
endmodule
