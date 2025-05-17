`timescale 1ns/1ps

module conv1d_k3 #(
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

  // two‐deep line buffers
  reg signed [15:0] buf1_0 = 0, buf2_0 = 0;
  reg signed [15:0] buf1_1 = 0, buf2_1 = 0;

  // initialize buffers to zero so first output is valid
  initial begin
    buf1_0 = '0;
    buf2_0 = '0;
    buf1_1 = '0;
    buf2_1 = '0;
  end

  // toy weights
  reg signed [DATA_WIDTH-1:0] w00 = 1, w01 = 2, w02 = 3;
  reg signed [DATA_WIDTH-1:0] w10 = 4, w11 = 5, w12 = 6;
  reg signed [DATA_WIDTH+8:0] acc;

  // shift registers
  always @(posedge clk) if (en) begin
    buf2_0 <= buf1_0; buf1_0 <= din0;
    buf2_1 <= buf1_1; buf1_1 <= din1;
  end

  // MAC + output
  always @(posedge clk) begin
    if (en) begin
      acc = w00*buf2_0 + w01*buf1_0 + w02*din0
          + w10*buf2_1 + w11*buf1_1 + w12*din1;
      dout0 <= acc[DATA_WIDTH+4 -: DATA_WIDTH];
      out_valid <= 1;
    end else
      out_valid <= 0;
  end
endmodule
