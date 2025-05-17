`timescale 1ns/1ps

module upsample2 #(
  parameter DATA_WIDTH = 16
)(
  input  logic                      clk,
  input  logic                      en,        // pulse on new input
  input  logic signed [DATA_WIDTH-1:0] din,
  output logic                      out_valid, // high each output
  output logic signed [DATA_WIDTH-1:0] dout
);
  logic toggle;  // 0 → 1st copy, 1 → 2nd copy

  always_ff @(posedge clk) begin
    if (en) begin
      toggle    <= 1'b0;
      dout      <= din;
      out_valid <= 1'b1;
    end
    else if (out_valid) begin
      if (!toggle) begin
        toggle    <= 1'b1;
        out_valid <= 1'b1;
      end else begin
        out_valid <= 1'b0;
      end
    end else begin
      out_valid <= 1'b0;
    end
  end
endmodule
