module snn_2layer #(
    parameter WIDTH = 16,
    parameter N_INPUTS = 2,
    parameter N1 = 3,
    parameter N2 = 2,
    parameter THRESHOLD = 100,
    parameter LEAK = 1,
    parameter REFRACTORY_TICKS = 10,
    parameter signed [WIDTH-1:0] W_INPUT_TO_L1 [N_INPUTS-1:0][N1-1:0],
    parameter signed [WIDTH-1:0] W_L1_TO_L2 [N1-1:0][N2-1:0]
)(
    input wire clk,
    input wire reset,
    input wire signed [WIDTH-1:0] input_vector [N_INPUTS-1:0],
    output wire [N2-1:0] spike_out
);

    wire [N1-1:0] spike_layer1;

    genvar i, j;
    generate
        for (i = 0; i < N1; i = i + 1) begin : layer1
            reg signed [WIDTH-1:0] total_input;
            integer k;

            always @(*) begin
                total_input = 0;
                for (k = 0; k < N_INPUTS; k = k + 1)
                    total_input = total_input + input_vector[k] * W_INPUT_TO_L1[k][i];
            end

            lif_neuron #(
                .WIDTH(WIDTH),
                .THRESHOLD(THRESHOLD),
                .LEAK(LEAK),
                .REFRACTORY_TICKS(REFRACTORY_TICKS)
            ) neuron (
                .clk(clk),
                .reset(reset),
                .input_current(total_input),
                .spike(spike_layer1[i])
            );
        end
    endgenerate

    generate
        for (j = 0; j < N2; j = j + 1) begin : layer2
            reg signed [WIDTH-1:0] total_input;
            integer m;

            always @(*) begin
                total_input = 0;
                for (m = 0; m < N1; m = m + 1)
                    total_input = total_input + spike_layer1[m] * W_L1_TO_L2[m][j];
            end

            lif_neuron #(
                .WIDTH(WIDTH),
                .THRESHOLD(THRESHOLD),
                .LEAK(LEAK),
                .REFRACTORY_TICKS(REFRACTORY_TICKS)
            ) neuron (
                .clk(clk),
                .reset(reset),
                .input_current(total_input),
                .spike(spike_out[j])
            );
        end
    endgenerate

endmodule
