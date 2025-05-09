`timescale 1ns/1ps

module lif_neuron #(
  parameter signed [7:0] LAMBDA      = 8'sb0001_0100,  // 1.25 in Q4.4
  parameter signed [7:0] THRESHOLD   = 8'sb0100_0000,  // 4.0 in Q4.4
  parameter signed [7:0] RESET_LEVEL = 8'sb0000_0000   // 0.0
) (
  input  logic clk,
  input  logic rst_n,     // active-low reset
  input  logic spike_in,
  output logic spike_out
);

  // State registers
  logic signed [7:0] P_reg, P_next;
  logic signed [7:0] integrated;

  // Fixed-point multiply: 8×8 → 16 bits (Q8.8)
  wire signed [15:0] mul_full  = P_reg * LAMBDA;
  // Downshift to Q4.4 by taking bits [11:4]
  wire signed [7:0]  leak_mult = mul_full[11:4];

  // Combinational next-state and integration
  always_comb begin
    integrated = leak_mult + spike_in;  // Q4.4 + integer → Q4.4
    if (integrated >= THRESHOLD)
      P_next = RESET_LEVEL;
    else
      P_next = integrated;
  end

  // Sequential update and spike generation
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      P_reg    <= RESET_LEVEL;
      spike_out<= 1'b0;
    end else begin
      P_reg    <= P_next;
      // Fire when threshold crossed
      spike_out<= (P_next == RESET_LEVEL && integrated >= THRESHOLD);
    end
  end

endmodule
