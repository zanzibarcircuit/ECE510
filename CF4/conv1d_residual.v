module conv1d_residual #(
    parameter INPUT_CHANNELS = 2,
    parameter OUTPUT_CHANNELS = 2,
    parameter KERNEL_SIZE = 3,
    parameter DATA_WIDTH = 16
)(
    input clk,
    input rst,

    input signed [DATA_WIDTH-1:0] input_data_0,
    input signed [DATA_WIDTH-1:0] input_data_1,

    input signed [DATA_WIDTH-1:0] skip_data_0,
    input signed [DATA_WIDTH-1:0] skip_data_1,

    output reg signed [DATA_WIDTH-1:0] output_data_0,
    output reg signed [DATA_WIDTH-1:0] output_data_1
);

    wire signed [DATA_WIDTH-1:0] input_data [0:1];
    assign input_data[0] = input_data_0;
    assign input_data[1] = input_data_1;

    wire signed [DATA_WIDTH-1:0] skip_data [0:1];
    assign skip_data[0] = skip_data_0;
    assign skip_data[1] = skip_data_1;

    reg signed [DATA_WIDTH-1:0] window [0:1][0:2];
    reg signed [DATA_WIDTH-1:0] weights [0:1][0:1][0:2];

    integer i, k, o;
    reg signed [DATA_WIDTH*2-1:0] mac_result [0:1];
    reg signed [DATA_WIDTH*2-1:0] result [0:1];

    // Initialize weights
    initial begin
        weights[0][0][0] = 1; weights[0][0][1] = 0; weights[0][0][2] = -1;
        weights[0][1][0] = 2; weights[0][1][1] = 0; weights[0][1][2] = -2;
        weights[1][0][0] = 0; weights[1][0][1] = 1; weights[1][0][2] = 0;
        weights[1][1][0] = 1; weights[1][1][1] = -1; weights[1][1][2] = 1;
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < INPUT_CHANNELS; i = i + 1) begin
                for (k = 0; k < KERNEL_SIZE; k = k + 1) begin
                    window[i][k] <= 0;
                end
            end
        end else begin
            for (i = 0; i < INPUT_CHANNELS; i = i + 1) begin
                window[i][2] <= window[i][1];
                window[i][1] <= window[i][0];
                window[i][0] <= input_data[i];
            end
        end
    end

    always @(*) begin
        for (o = 0; o < OUTPUT_CHANNELS; o = o + 1) begin
            mac_result[o] = 0;
            for (i = 0; i < INPUT_CHANNELS; i = i + 1) begin
                for (k = 0; k < KERNEL_SIZE; k = k + 1) begin
                    mac_result[o] = mac_result[o] + window[i][k] * weights[o][i][k];
                end
            end
        end
    end

    always @(posedge clk) begin
        for (o = 0; o < OUTPUT_CHANNELS; o = o + 1) begin
            result[o] = mac_result[o] + skip_data[o];
            if (result[o] >= 0)
                case (o)
                    0: output_data_0 <= result[o][DATA_WIDTH-1:0];
                    1: output_data_1 <= result[o][DATA_WIDTH-1:0];
                endcase
            else
                case (o)
                    0: output_data_0 <= result[o] >>> 6;
                    1: output_data_1 <= result[o] >>> 6;
                endcase
        end
    end

endmodule
