`timescale 1ns/1ps

module fc2x2_tb;
  reg clk = 0;
  always #5 clk = ~clk;

  reg signed [15:0] z0 = 0, z1 = 0;
  reg               en = 0;
  wire              done;
  wire signed [15:0] out0, out1;

  fc2x2 uut (
    .clk  (clk),
    .en   (en),
    .z0   (z0),
    .z1   (z1),
    .done (done),
    .out0 (out0),
    .out1 (out1)
  );

  initial begin
    $dumpfile("fc2x2.vcd");
    $dumpvars(0, fc2x2_tb);

    $display("time | en z0 z1 => done out0 out1  (expect out0=5, out1=11 for z0=1,z1=2)");
    $display("---------------------------------------------------------------------");

    #10;
      z0 = 1; z1 = 2; en = 1;  // 1*1 + 2*2 = 5 >>2 = 1; 3*1 + 4*2 =11 >>2 = 2  (we'll see truncation)
    #10;
      en = 0;
    #1;
      $display("%4t |  %b  %4d  %4d =>   %b    %4d   %4d", 
               $time, en, z0, z1, done, out0, out1);
    #10;
      $display("%4t | (after) done=%b", $time, done);
    #10;
    $finish;
  end
endmodule
