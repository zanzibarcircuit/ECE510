`timescale 1ns/1ps
module upsample2_tb;
  logic clk=0; always #5 clk=~clk;
  logic en=0;
  logic signed [15:0] din=0;
  logic valid;
  logic signed [15:0] dout;

  upsample2 #(.DATA_WIDTH(16)) uut(
    .clk(clk), .en(en), .din(din),
    .out_valid(valid), .dout(dout)
  );

  initial begin
    $display(" time | en din => valid dout");
    $display("------+-----------------");
    // feed value 7
    #10; din=7;  en=1;
    #10; en=0;
    #10; // first copy
       $display("%4t |  %b  %3d =>  %b   %3d", $time, en, din, valid, dout);
    #10; // second copy
       $display("%4t |  %b  %3d =>  %b   %3d", $time, en, din, valid, dout);

    // feed value -3
    #10; din=-3; en=1;
    #10; en=0;
    #10; $display("%4t |  %b  %3d =>  %b   %3d", $time, en, din, valid, dout);
    #10; $display("%4t |  %b  %3d =>  %b   %3d", $time, en, din, valid, dout);

    $finish;
  end
endmodule
