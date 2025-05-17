`timescale 1ns/1ps

module fc2x2 (
  input  clk,
  input  en,
  input  signed [15:0] z0,
  input  signed [15:0] z1,
  output reg           done,
  output reg signed [15:0] out0,
  output reg signed [15:0] out1
);

  // weights
  reg signed [15:0] w00, w01, w10, w11;
  // accumulators
  reg signed [31:0] acc0, acc1;

  initial begin
    w00 = 16'd1;  // out0 = 1*z0 + 2*z1
    w01 = 16'd2;
    w10 = 16'd3;  // out1 = 3*z0 + 4*z1
    w11 = 16'd4;
  end

  always @(posedge clk) begin
    if (en) begin
      acc0 = w00*z0 + w01*z1;
      acc1 = w10*z0 + w11*z1;
      // truncate low 2 bits
      out0 <= acc0[17:2];
      out1 <= acc1[17:2];
      done <= 1'b1;
    end else begin
      done <= 1'b0;
    end
  end
endmodule
