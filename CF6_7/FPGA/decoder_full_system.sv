`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// ReLU Module
// -----------------------------------------------------------------------------
module relu16 #(
  parameter DATA_WIDTH = 16
)(
  input  logic                        clk,
  input  logic                        en,
  input  logic signed [DATA_WIDTH-1:0] din,
  output logic signed [DATA_WIDTH-1:0] dout
);
  always_ff @(posedge clk) begin
    if (en)
      dout <= (din[DATA_WIDTH-1] ? '0 : din);
  end
endmodule

// -----------------------------------------------------------------------------
// Nearest-Neighbor Upsampler ×2
// -----------------------------------------------------------------------------
module upsample2 #(
  parameter DATA_WIDTH = 16
)(
  input  logic                        clk,
  input  logic                        en,
  input  logic signed [DATA_WIDTH-1:0] din,
  output logic                        out_valid,
  output logic signed [DATA_WIDTH-1:0] dout
);
  logic toggle;
  always_ff @(posedge clk) begin
    if (en) begin
      toggle    <= 1'b0;
      dout      <= din;
      out_valid <= 1'b1;
    end else if (out_valid) begin
      if (!toggle) begin
        toggle    <= 1'b1;
        out_valid <= 1'b1;
      end else begin
        out_valid <= 1'b0;
      end
    end else begin
      out_valid <= 1'b0;
    end
  end
endmodule

// -----------------------------------------------------------------------------
// 1D Convolution, Kernel=3, Padding=1 (single-channel)
// -----------------------------------------------------------------------------
module conv1d_k3 #(
  parameter DATA_WIDTH = 16
)(
  input  logic                         clk,
  input  logic                         en,
  input  logic signed [DATA_WIDTH-1:0] din0,
  input  logic signed [DATA_WIDTH-1:0] din1,
  output logic                         out_valid,
  output logic signed [DATA_WIDTH-1:0] dout0
);
  // two-deep line buffers, zero-initialized
  reg signed [DATA_WIDTH-1:0] buf1_0 = 0, buf2_0 = 0;
  reg signed [DATA_WIDTH-1:0] buf1_1 = 0, buf2_1 = 0;
  // weights and accumulator
  reg signed [DATA_WIDTH-1:0] w00 = 1, w01 = 2, w02 = 3;
  reg signed [DATA_WIDTH-1:0] w10 = 4, w11 = 5, w12 = 6;
  reg signed [DATA_WIDTH+8:0]  acc;

  // shift registers
  always_ff @(posedge clk) if (en) begin
    buf2_0 <= buf1_0; buf1_0 <= din0;
    buf2_1 <= buf1_1; buf1_1 <= din1;
  end

  // MAC + output (>>2 truncate)
  always_ff @(posedge clk) begin
    if (en) begin
      acc = w00*buf2_0 + w01*buf1_0 + w02*din0
          + w10*buf2_1 + w11*buf1_1 + w12*din1;
      dout0     <= acc[17:2];
      out_valid <= 1'b1;
    end else out_valid <= 1'b0;
  end
endmodule

// -----------------------------------------------------------------------------
// 1D Convolution, Kernel=1
// -----------------------------------------------------------------------------
module conv1d_k1 #(
  parameter DATA_WIDTH = 16
)(
  input  logic                         clk,
  input  logic                         en,
  input  logic signed [DATA_WIDTH-1:0] din0,
  input  logic signed [DATA_WIDTH-1:0] din1,
  output logic                         out_valid,
  output logic signed [DATA_WIDTH-1:0] dout0
);
  reg signed [DATA_WIDTH-1:0] w0 = 3, w1 = 5;
  reg signed [DATA_WIDTH+8:0] acc;

  always_ff @(posedge clk) begin
    if (en) begin
      acc        = w0*din0 + w1*din1;
      dout0      <= acc[17:2];
      out_valid  <= 1'b1;
    end else out_valid <= 1'b0;
  end
endmodule

// -----------------------------------------------------------------------------
// Top-Level Decoder Pipeline (single-channel toy example)
// -----------------------------------------------------------------------------
module decoder_top #(
  parameter DATA_WIDTH = 16
)(
  input  logic                        clk,
  input  logic                        start,
  input  logic signed [DATA_WIDTH-1:0] din,
  output logic                        done,
  output logic signed [DATA_WIDTH-1:0] dout
);
  logic v0,v1,v2,v3,v4,v5,v6,v7,v8,v9;
  always_ff @(posedge clk) v0 <= start;

  // Stage 1: ReLU
  logic signed [DATA_WIDTH-1:0] s1;
  relu16 #(.DATA_WIDTH(DATA_WIDTH)) u1(.clk(clk),.en(v0),.din(din),.dout(s1));
  always_ff @(posedge clk) v1 <= v0;

  // Stage 2: Upsample×2
  logic signed [DATA_WIDTH-1:0] s2;
  logic                         u2;
  upsample2 #(.DATA_WIDTH(DATA_WIDTH)) u2p(.clk(clk),.en(v1),.din(s1),.out_valid(u2),.dout(s2));
  always_ff @(posedge clk) v2 <= u2;

  // Stage 3: Conv1D k=3
  logic signed [DATA_WIDTH-1:0] s3;
  logic                         u3;
  conv1d_k3 #(.DATA_WIDTH(DATA_WIDTH)) u3c(.clk(clk),.en(v2),.din0(s2),.din1(16'sd0),.out_valid(u3),.dout0(s3));
  always_ff @(posedge clk) v3 <= u3;

  // Stage 4: ReLU
  logic signed [DATA_WIDTH-1:0] s4;
  relu16 #(.DATA_WIDTH(DATA_WIDTH)) u4(.clk(clk),.en(v3),.din(s3),.dout(s4));
  always_ff @(posedge clk) v4 <= v3;

  // Stage 5: Upsample×2
  logic signed [DATA_WIDTH-1:0] s5;
  logic                         u5;
  upsample2 #(.DATA_WIDTH(DATA_WIDTH)) u5p(.clk(clk),.en(v4),.din(s4),.out_valid(u5),.dout(s5));
  always_ff @(posedge clk) v5 <= u5;

  // Stage 6: Conv1D k=3
  logic signed [DATA_WIDTH-1:0] s6;
  logic                         u6;
  conv1d_k3 #(.DATA_WIDTH(DATA_WIDTH)) u6c(.clk(clk),.en(v5),.din0(s5),.din1(16'sd0),.out_valid(u6),.dout0(s6));
  always_ff @(posedge clk) v6 <= u6;

  // Stage 7: ReLU
  logic signed [DATA_WIDTH-1:0] s7;
  relu16 #(.DATA_WIDTH(DATA_WIDTH)) u7(.clk(clk),.en(v6),.din(s6),.dout(s7));
  always_ff @(posedge clk) v7 <= v6;

  // Stage 8: Conv1D k=1
  logic signed [DATA_WIDTH-1:0] s8;
  logic                         u8;
  conv1d_k1 #(.DATA_WIDTH(DATA_WIDTH)) u8c(.clk(clk),.en(v7),.din0(s7),.din1(16'sd0),.out_valid(u8),.dout0(s8));
  always_ff @(posedge clk) v8 <= u8;

  // Stage 9: Final ReLU
  relu16 #(.DATA_WIDTH(DATA_WIDTH)) u9(.clk(clk),.en(v8),.din(s8),.dout(dout));
  always_ff @(posedge clk) v9 <= v8;

  assign done = v9;
endmodule
