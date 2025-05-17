`timescale 1ns/1ps

module conv1d_k1_tb;
  reg  clk = 0; always #5 clk = ~clk;
  reg            en   = 0;
  reg  signed [15:0] din0 = 2, din1 = 4;
  wire out_valid;
  wire signed [15:0] dout0;

  conv1d_k1 #(.IN_CH(2), .OUT_CH(1), .DATA_WIDTH(16)) uut (
    .clk(clk), .en(en), .din0(din0), .din1(din1),
    .out_valid(out_valid), .dout0(dout0)
  );

  initial begin
    #10; en=1;
    #10; en=0; #1;
    $display("dout0=%d out_valid=%b", dout0, out_valid);
    $finish;
  end
endmodule
