`timescale 1ns/1ps
module SimpleDecoder_tb;
  reg  signed [15:0] latent0, latent1, latent2, latent3;
  wire signed [15:0] out0, out1, out2, out3, out4, out5, out6, out7;

  SimpleDecoder UUT (
    .latent0(latent0), .latent1(latent1),
    .latent2(latent2), .latent3(latent3),
    .out0(out0), .out1(out1), .out2(out2), .out3(out3),
    .out4(out4), .out5(out5), .out6(out6), .out7(out7)
  );

  initial begin
    // drive [1,2,3,4] in Q8.8 (i.e. 1.0=256)
    latent0 = 256;  // 1.0
    latent1 = 512;  // 2.0
    latent2 = 768;  // 3.0
    latent3 = 1024; // 4.0
    #1;  // let it settle

    $display("Decoded output:");
    $display(" out0 = %0d", out0);
    $display(" out1 = %0d", out1);
    $display(" out2 = %0d", out2);
    $display(" out3 = %0d", out3);
    $display(" out4 = %0d", out4);
    $display(" out5 = %0d", out5);
    $display(" out6 = %0d", out6);
    $display(" out7 = %0d", out7);
    $finish;
  end
endmodule
