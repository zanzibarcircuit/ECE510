module conv1d_residual_tb;

    parameter DATA_WIDTH = 16;

    reg clk;
    reg rst;
    reg signed [DATA_WIDTH-1:0] input_data_0;
    reg signed [DATA_WIDTH-1:0] input_data_1;
    reg signed [DATA_WIDTH-1:0] skip_data_0;
    reg signed [DATA_WIDTH-1:0] skip_data_1;
    wire signed [DATA_WIDTH-1:0] output_data_0;
    wire signed [DATA_WIDTH-1:0] output_data_1;

    conv1d_residual dut (
        .clk(clk),
        .rst(rst),
        .input_data_0(input_data_0),
        .input_data_1(input_data_1),
        .skip_data_0(skip_data_0),
        .skip_data_1(skip_data_1),
        .output_data_0(output_data_0),
        .output_data_1(output_data_1)
    );

    // Input memory
    reg signed [DATA_WIDTH-1:0] input_mem_0 [0:3];
    reg signed [DATA_WIDTH-1:0] input_mem_1 [0:3];
    reg signed [DATA_WIDTH-1:0] skip_mem_0 [0:3];
    reg signed [DATA_WIDTH-1:0] skip_mem_1 [0:3];

    integer t;

    initial begin
        // Initialize memories
        input_mem_0[0] = 1; input_mem_1[0] = 5;
        input_mem_0[1] = 2; input_mem_1[1] = 6;
        input_mem_0[2] = 3; input_mem_1[2] = 7;
        input_mem_0[3] = 4; input_mem_1[3] = 8;

        skip_mem_0[0] = 1; skip_mem_1[0] = 5;
        skip_mem_0[1] = 2; skip_mem_1[1] = 6;
        skip_mem_0[2] = 3; skip_mem_1[2] = 7;
        skip_mem_0[3] = 4; skip_mem_1[3] = 8;

        clk = 0;
        rst = 1;
        input_data_0 = 0;
        input_data_1 = 0;
        skip_data_0 = 0;
        skip_data_1 = 0;

        #10 rst = 0; // Deassert reset after 10ns

        for (t = 0; t < 4; t = t + 1) begin
            input_data_0 = input_mem_0[t];
            input_data_1 = input_mem_1[t];
            skip_data_0 = skip_mem_0[t];
            skip_data_1 = skip_mem_1[t];
            #10; // One clock cycle per sample
        end

        $finish;
    end

    always #5 clk = ~clk; // Clock generator

    always @(posedge clk) begin
        $display("Time %0t: output_data_0=%0d, output_data_1=%0d", $time, output_data_0, output_data_1);
    end

endmodule
