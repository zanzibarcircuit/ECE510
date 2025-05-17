`timescale 1ns/1ps

module conv1d_k3_tb;
  reg  clk = 0; always #5 clk = ~clk;
  reg  en  = 0;
  reg  signed [15:0] din0 = 0, din1 = 0;
  wire out_valid;
  wire signed [15:0] dout0;

  conv1d_k3 #(.IN_CH(2), .OUT_CH(1), .DATA_WIDTH(16)) uut (
    .clk      (clk),
    .en       (en),
    .din0     (din0),
    .din1     (din1),
    .out_valid(out_valid),
    .dout0    (dout0)
  );

  initial begin
    $display("time en | dout0 valid");
    // Warm‐up #1
    #10; din0=1; din1=2; en=1;
    #10; en=0;
    // Warm‐up #2
    #10; din0=1; din1=2; en=1;
    #10; en=0;
    // Test
    #10; din0=3; din1=4; en=1;
    #10; en=0; #1;
    $display("%4t  %b | %4d     %b", $time, en, dout0, out_valid);
    $finish;
  end
endmodule
