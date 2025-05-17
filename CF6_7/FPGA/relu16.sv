`timescale 1ns/1ps

module relu16 #(
  parameter DATA_WIDTH = 16
)(
  input  logic                      clk,
  input  logic                      en,    // pulse each sample
  input  logic signed [DATA_WIDTH-1:0] din,
  output logic signed [DATA_WIDTH-1:0] dout
);
  // clamp negative to zero
  always_ff @(posedge clk) begin
    if (en)
      dout <= (din[DATA_WIDTH-1] ? '0 : din);
  end
endmodule
