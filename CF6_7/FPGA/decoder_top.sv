`timescale 1ns/1ps

module decoder_top #(
  parameter DATA_WIDTH = 16
)(
  input  logic                        clk,
  input  logic                        start,
  input  logic signed [DATA_WIDTH-1:0] din,
  output logic                        done,
  output logic signed [DATA_WIDTH-1:0] dout
);

  // valid‐pulse pipeline
  logic v0, v1, v2, v3, v4, v5, v6, v7, v8, v9;
  always_ff @(posedge clk) v0 <= start;

  // 1) ReLU
  logic signed [DATA_WIDTH-1:0] s1;
  relu16 #(.DATA_WIDTH(DATA_WIDTH)) u1 (
    .clk(clk), .en(v0), .din(din), .dout(s1)
  );
  always_ff @(posedge clk) v1 <= v0;

  // 2) Upsample×2
  logic signed [DATA_WIDTH-1:0] s2;
  logic                         u2;
  upsample2 #(.DATA_WIDTH(DATA_WIDTH)) u2p (
    .clk(clk), .en(v1), .din(s1),
    .out_valid(u2), .dout(s2)
  );
  always_ff @(posedge clk) v2 <= u2;

  // 3) Conv1D k=3 (single‐channel)
  logic signed [DATA_WIDTH-1:0] s3;
  logic                         u3;
  conv1d_k3 #(
    .IN_CH     (1),
    .OUT_CH    (1),
    .DATA_WIDTH(DATA_WIDTH)
  ) u3c (
    .clk      (clk),
    .en       (v2),
    .din0     (s2),
    .din1     (16'sd0),    // <-- explicit 16-bit zero
    .out_valid(u3),
    .dout0    (s3)
  );
  always_ff @(posedge clk) v3 <= u3;

  // 4) ReLU
  logic signed [DATA_WIDTH-1:0] s4;
  relu16 #(.DATA_WIDTH(DATA_WIDTH)) u4 (
    .clk(clk), .en(v3), .din(s3), .dout(s4)
  );
  always_ff @(posedge clk) v4 <= v3;

  // 5) Upsample×2
  logic signed [DATA_WIDTH-1:0] s5;
  logic                         u5;
  upsample2 #(.DATA_WIDTH(DATA_WIDTH)) u5p (
    .clk(clk), .en(v4), .din(s4),
    .out_valid(u5), .dout(s5)
  );
  always_ff @(posedge clk) v5 <= u5;

  // 6) Conv1D k=3
  logic signed [DATA_WIDTH-1:0] s6;
  logic                         u6;
  conv1d_k3 #(
    .IN_CH     (1),
    .OUT_CH    (1),
    .DATA_WIDTH(DATA_WIDTH)
  ) u6c (
    .clk      (clk),
    .en       (v5),
    .din0     (s5),
    .din1     (16'sd0),    // <-- explicit 16-bit zero
    .out_valid(u6),
    .dout0    (s6)
  );
  always_ff @(posedge clk) v6 <= u6;

  // 7) ReLU
  logic signed [DATA_WIDTH-1:0] s7;
  relu16 #(.DATA_WIDTH(DATA_WIDTH)) u7 (
    .clk(clk), .en(v6), .din(s6), .dout(s7)
  );
  always_ff @(posedge clk) v7 <= v6;

  // 8) Conv1D k=1
  logic signed [DATA_WIDTH-1:0] s8;
  logic                         u8;
  conv1d_k1 #(
    .IN_CH     (1),
    .OUT_CH    (1),
    .DATA_WIDTH(DATA_WIDTH)
  ) u8c (
    .clk      (clk),
    .en       (v7),
    .din0     (s7),
    .din1     (16'sd0),    // <-- explicit 16-bit zero
    .out_valid(u8),
    .dout0    (s8)
  );
  always_ff @(posedge clk) v8 <= u8;

  // 9) Final ReLU
  relu16 #(.DATA_WIDTH(DATA_WIDTH)) u9 (
    .clk(clk), .en(v8), .din(s8), .dout(dout)
  );
  always_ff @(posedge clk) v9 <= v8;

  assign done = v9;

endmodule
