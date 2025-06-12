// testbench.sv
`timescale 1ns/1ps

module tb_spi_slave_if_only;
  // these must match your spi_slave_decoder_if parameters
  localparam int DATA_WIDTH          = 16;
  localparam int N_MELS              = 2;
  localparam int FIXED_FRAMES_FINAL  = 4;
  localparam int TOTAL_WORDS         = N_MELS * FIXED_FRAMES_FINAL;

  // SPI lines
  reg         sclk = 0;
  reg         cs_n = 1;
  reg         mosi = 1'b0;  // not used
  wire        miso;

  // drive SCLK @10 MHz whenever CS_N is low
  initial begin
    forever begin
      @(negedge cs_n);
      forever #50 sclk = ~sclk;
    end
  end

  // test pattern storage
  reg signed [DATA_WIDTH-1:0] data_in [0:N_MELS-1][0:FIXED_FRAMES_FINAL-1];

  // instantiate the SPI-slave under test
  spi_slave_decoder_if #(
    .DATA_WIDTH(DATA_WIDTH),
    .N_MELS(N_MELS),
    .FIXED_FRAMES_FINAL(FIXED_FRAMES_FINAL)
  ) dut (
    .cs_n    (cs_n),
    .sclk    (sclk),
    .mosi    (mosi),
    .miso    (miso),
    .data_in (data_in)
  );

  integer w, b;
  reg [DATA_WIDTH-1:0]         received;
  reg signed [DATA_WIDTH-1:0]  expected_word;

  initial begin
    // 1) Initialize a known pattern
    data_in[0][0] = 16'hAAAA;
    data_in[0][1] = 16'h1234;
    data_in[0][2] = 16'h0F0F;
    data_in[0][3] = 16'h00FF;
    data_in[1][0] = 16'h8001;
    data_in[1][1] = 16'h7FFF;
    data_in[1][2] = 16'h55AA;
    data_in[1][3] = 16'hDEAD;

    // 2) Let signals settle
    #100;

    // 3) Assert CS low to start
    cs_n = 0;
    #10;

    // 4) For each of the TOTAL_WORDS,
    //    sample exactly 16 bits on successive SCLK posedges
    for (w = 0; w < TOTAL_WORDS; w = w + 1) begin
      received = '0;
      for (b = DATA_WIDTH-1; b >= 0; b = b - 1) begin
        @(posedge sclk);
        received[b] = miso;
      end
      expected_word = data_in[w/FIXED_FRAMES_FINAL]
                             [w%FIXED_FRAMES_FINAL];
      $display("Word %0d: got=0x%0h, exp=0x%0h", 
                w, received, expected_word);
      if (received !== expected_word)
        $error("  >> MISMATCH at word %0d!", w);
    end

    // 5) Finish up
    cs_n = 1;
    #50;
    $display("=== SPI INTERFACE TEST PASSED ===");
    $finish;
  end
endmodule
