`timescale 1ns/1ps
module relu16_tb;
  logic clk = 0; always #5 clk = ~clk;
  logic en      = 0;
  logic signed [15:0] din = 0;
  logic signed [15:0] dout;

  relu16 #(.DATA_WIDTH(16)) uut(
    .clk(clk), .en(en), .din(din), .dout(dout)
  );

  initial begin
    $display(" time | en din   => dout");
    $display("-----+-------------");
    #10; en=1; din=-5;   #10; $display("%4t |  %b  %3d  => %3d", $time, en, din, dout);
    en=0;  #10;
    #10; en=1; din=0;    #10; $display("%4t |  %b  %3d  => %3d", $time, en, din, dout);
    en=0;  #10;
    #10; en=1; din=123;  #10; $display("%4t |  %b  %3d  => %3d", $time, en, din, dout);
    $finish;
  end
endmodule
