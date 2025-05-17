`timescale 1ns/1ps

module decoder_top_tb;
  // Clock
  reg                clk   = 0;
  always #5 clk = ~clk;

  // Stimulus
  reg  signed [15:0] din   = 16'sd10;
  reg                start = 0;
  wire               done;
  wire signed [15:0] dout;

  // DUT instance
  decoder_top uut (
    .clk   (clk),
    .start (start),
    .din   (din),
    .done  (done),
    .dout  (dout)
  );

  // Expose internal registers as nets
  wire signed [15:0] ts1 = uut.s1;
  wire signed [15:0] ts2 = uut.s2;
  wire signed [15:0] ts3 = uut.s3;
  wire signed [15:0] ts4 = uut.s4;
  wire signed [15:0] ts5 = uut.s5;
  wire signed [15:0] ts6 = uut.s6;
  wire signed [15:0] ts7 = uut.s7;
  wire signed [15:0] ts8 = uut.s8;

  // Print every cycle on the rising edge
  always @(posedge clk) begin
    $display("Cyc %2d | s1=%2d s2=%2d s3=%2d s4=%2d s5=%2d s6=%2d s7=%2d s8=%2d dout=%2d",
             $time/10, ts1, ts2, ts3, ts4, ts5, ts6, ts7, ts8, dout);
  end

  initial begin
    $display("=== Pipeline debug ===");
    // Warm‐up 1 & 2
    #10 start = 1; #10 start = 0;
    #10 start = 1; #10 start = 0;
    // Real pulse
    #10 start = 1; #10 start = 0;
    // Wait for final done
    wait(done);
    $display("\nExpected (>>2 trunc): s3=7, s6=5, s8=3, dout=3");
    $finish;
  end
endmodule
