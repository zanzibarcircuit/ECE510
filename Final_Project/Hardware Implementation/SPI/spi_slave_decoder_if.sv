// spi_slave_decoder_if.sv (Corrected async SCLK version)
`timescale 1ns/1ps

module spi_slave_decoder_if #(
  parameter int DATA_WIDTH        = 16,
  parameter int N_MELS            = 2,
  parameter int FIXED_FRAMES_FINAL = 4
) (
  input  wire                       cs_n,    // active-low chip select
  input  wire                       sclk,    // SPI clock, mode 0
  input  wire                       mosi,    // not used here
  output reg                        miso,    // data out
  // parallel data in
  input  wire signed [DATA_WIDTH-1:0] data_in [0:N_MELS-1][0:FIXED_FRAMES_FINAL-1]
);

  localparam int TOTAL_WORDS = N_MELS * FIXED_FRAMES_FINAL;
  integer word_idx; // Index of the current word being transmitted
  integer bit_idx;  // Tracks how many bits of the current word have been prepared for MISO
                    // (e.g., after bit_idx increments to 1, the 2nd MSB is on MISO)
  reg [DATA_WIDTH-1:0] shift_reg;

  // On CS falling, load the very first word and drive its MSB out.
  // This MISO value will be sampled by the master on the first SCLK rising edge.
  always @(negedge cs_n) begin
    word_idx  = 0;
    bit_idx   = 0; // Indicates that 0 bits have been shifted out; MSB is active.
    shift_reg = data_in[0][0];
    miso      = shift_reg[DATA_WIDTH-1]; // Output MSB of the first word
  end

  // On each SCLK falling edge, prepare the MISO line for the *next* SCLK rising edge.
  always @(negedge sclk) begin
    if (!cs_n) begin
      // Current MISO holds the bit that was (or should have been) sampled on the preceding rising SCLK edge.
      // We now prepare MISO for the *next* bit.

      bit_idx = bit_idx + 1; // Increment the count of bits processed for the current word.

      if (bit_idx == DATA_WIDTH) begin
        // All bits of the current word in shift_reg have been made available on MISO.
        // Load the next word.
        bit_idx = 0; // Reset bit counter for the new word.
        word_idx = (word_idx == TOTAL_WORDS - 1) ? 0 : word_idx + 1;
        shift_reg = data_in[word_idx / FIXED_FRAMES_FINAL]
                           [word_idx % FIXED_FRAMES_FINAL];
        // MISO gets the MSB of this new word, to be sampled on the next rising SCLK.
        miso = shift_reg[DATA_WIDTH-1];
      end else begin
        // More bits to send from the current word.
        // Shift the register to bring the next bit to the MSB position.
        shift_reg = {shift_reg[DATA_WIDTH-2:0], 1'b0}; // Left shift
        // MISO gets the new MSB (which is the next bit to be transmitted).
        miso = shift_reg[DATA_WIDTH-1];
      end
    end
  end
endmodule
