// tb_conv2_module_parallel.sv
// Testbench for the parallelized Conv2 module
`timescale 1ns/1ps

module tb_conv2_module_parallel;

    // Parameters matching your conv2_module
    localparam int DATA_WIDTH = 16;
    localparam int FRACTIONAL_BITS = 8; // For DUT and float display
    localparam int NUM_IN_CHANNELS  = 2;
    localparam int NUM_OUT_CHANNELS = 1;
    localparam int KERNEL_SIZE      = 3;
    localparam int PADDING          = 1;
    localparam int STRIDE           = 1;
    localparam int NUM_IN_FRAMES    = 4;
    // P_NUM_OUT_FRAMES is calculated inside DUT, for TB we use an expected value
    localparam int NUM_OUT_FRAMES_EXPECTED = ((NUM_IN_FRAMES + 2 * PADDING) - KERNEL_SIZE) / STRIDE + 1; // Should be 4

    localparam time CLK_PERIOD = 10ns;
    localparam real FIXED_POINT_SCALE = 1.0 * (1 << FRACTIONAL_BITS);

    // Testbench signals
    logic clk;
    logic rst_n;
    logic i_start;
    logic signed [DATA_WIDTH-1:0] i_data_tb [0:NUM_IN_CHANNELS-1][0:NUM_IN_FRAMES-1];
    logic o_busy;
    logic o_done_tick;
    logic signed [DATA_WIDTH-1:0] o_result_tb [0:NUM_OUT_CHANNELS-1][0:NUM_OUT_FRAMES_EXPECTED-1];

    // Instantiate the DUT (conv2_module)
    conv2_module #(
        .DATA_WIDTH(DATA_WIDTH),
        .FRACTIONAL_BITS(FRACTIONAL_BITS),
        .NUM_IN_CHANNELS(NUM_IN_CHANNELS),
        .NUM_OUT_CHANNELS(NUM_OUT_CHANNELS),
        .KERNEL_SIZE(KERNEL_SIZE),
        .PADDING(PADDING),
        .STRIDE(STRIDE),
        .NUM_IN_FRAMES(NUM_IN_FRAMES)
        // .P_NUM_OUT_FRAMES(NUM_OUT_FRAMES_EXPECTED) // This is calculated inside DUT
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .i_start(i_start),
        .i_data(i_data_tb),
        .o_busy(o_busy),
        .o_done_tick(o_done_tick),
        .o_result(o_result_tb)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Input data (2 channels, 4 frames each) - from your example
    const logic signed [DATA_WIDTH-1:0] test_input_1 [0:NUM_IN_CHANNELS-1][0:NUM_IN_FRAMES-1] = '{
        '{16'sd286, 16'sd286, 16'sd295, 16'sd295}, // Channel 0
        '{16'sd404, 16'sd404, 16'sd402, 16'sd402}  // Channel 1
    };

    // Golden output (1 channel, 4 frames) - from your example
    const logic signed [DATA_WIDTH-1:0] golden_output_1 [0:NUM_OUT_CHANNELS-1][0:NUM_OUT_FRAMES_EXPECTED-1] = '{
        '{16'sd428, 16'sd652, 16'sd652, 16'sd397}  // Output Channel 0
    };
    
    // --- Add a second test case for variety ---
    // Input data (2 channels, 4 frames each) - different values
    const logic signed [DATA_WIDTH-1:0] test_input_2 [0:NUM_IN_CHANNELS-1][0:NUM_IN_FRAMES-1] = '{
        '{16'sd10, 16'sd20, 16'sd30, 16'sd40},   // Channel 0
        '{16'sd50, 16'sd60, 16'sd70, 16'sd80}    // Channel 1
    };

    // Golden output for test_input_2 (needs to be calculated based on conv2_module's kernels and biases)
    // KERNELS = '{ '{ {16'sd128,16'sd26,16'sd51}, {16'sd51,16'sd77,16'sd128} } };
    // BIASES  = '{ 16'sd18 };
    // For simplicity, let's assume a placeholder. You'd replace this with actual calculated values.
    // Manually calculating for test_input_2 and conv2_module's parameters:
    // Padded input for Ch0: {0, 10, 20, 30, 40, 0}
    // Padded input for Ch1: {0, 50, 60, 70, 80, 0}
    // Kernel Ch0: {128, 26, 51}
    // Kernel Ch1: {51, 77, 128}
    // Bias: 18
    // ROUND_CONST = 128

    // Frame 0 (output):
    // (0*128 + 10*26 + 20*51) + (0*51 + 50*77 + 60*128) scaled + bias
    // Ch0 contrib: (0 + 260 + 1020) = 1280
    // Ch1 contrib: (0 + 3850 + 7680) = 11530
    // Scaled Sum: ((1280 + 128)>>>8) + ((11530 + 128)>>>8) = (1408>>>8) + (11658>>>8) = 5 + 45 = 50
    // Total + Bias: 50 + 18 = 68

    // Frame 1 (output):
    // (10*128 + 20*26 + 30*51) + (50*51 + 60*77 + 70*128) scaled + bias
    // Ch0 contrib: (1280 + 520 + 1530) = 3330
    // Ch1 contrib: (2550 + 4620 + 8960) = 16130
    // Scaled Sum: ((3330 + 128)>>>8) + ((16130 + 128)>>>8) = (3458>>>8) + (16258>>>8) = 13 + 63 = 76
    // Total + Bias: 76 + 18 = 94

    // Frame 2 (output):
    // (20*128 + 30*26 + 40*51) + (60*51 + 70*77 + 80*128) scaled + bias
    // Ch0 contrib: (2560 + 780 + 2040) = 5380
    // Ch1 contrib: (3060 + 5390 + 10240) = 18690
    // Scaled Sum: ((5380 + 128)>>>8) + ((18690 + 128)>>>8) = (5508>>>8) + (18818>>>8) = 21 + 73 = 94
    // Total + Bias: 94 + 18 = 112

    // Frame 3 (output):
    // (30*128 + 40*26 + 0*51) + (70*51 + 80*77 + 0*128) scaled + bias
    // Ch0 contrib: (3840 + 1040 + 0) = 4880
    // Ch1 contrib: (3570 + 6160 + 0) = 9730
    // Scaled Sum: ((4880 + 128)>>>8) + ((9730 + 128)>>>8) = (5008>>>8) + (9858>>>8) = 19 + 38 = 57
    // Total + Bias: 57 + 18 = 75
    const logic signed [DATA_WIDTH-1:0] golden_output_2 [0:NUM_OUT_CHANNELS-1][0:NUM_OUT_FRAMES_EXPECTED-1] = '{
        '{16'sd68, 16'sd94, 16'sd112, 16'sd75}  // Output Channel 0 - Calculated
    };

    initial begin
        int ic, igf; 
        int oc, of; 
        int cycles_waited;
        logic test_passed_tc1, test_passed_tc2;
        real expected_f, got_f;

        $display("Starting Testbench for parallel conv2_module...");
        rst_n = 1'b0;
        i_start = 1'b0;
        for (ic = 0; ic < NUM_IN_CHANNELS; ic++) begin
            for (igf = 0; igf < NUM_IN_FRAMES; igf++) begin
                i_data_tb[ic][igf] = 16'sd0; // Initialize
            end
        end

        repeat(2) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        // ******************** TEST CASE 1 ********************
        $display("[%0t] ========= TEST CASE 1 =========", $time);
        for (ic = 0; ic < NUM_IN_CHANNELS; ic++) begin
            for (igf = 0; igf < NUM_IN_FRAMES; igf++) begin
                i_data_tb[ic][igf] = test_input_1[ic][igf];
            end
        end

        $display("[%0t] Applying input TC1 and starting Conv2 computation...", $time);
        i_start = 1'b1;
        @(posedge clk); 
        i_start = 1'b0;

        cycles_waited = 0;
        // For parallel DUT, timeout can be small
        while (o_done_tick !== 1'b1 && cycles_waited < 10) begin 
            @(posedge clk);
            cycles_waited++;
        end

        if (o_done_tick === 1'b1) begin
            $display("[%0t] TC1 Conv2 computation done. o_done_tick received.", $time);
            @(posedge clk); // Wait for registered output
            $display("[%0t] TC1 Sampling registered output.", $time);
            #1ps; 

            test_passed_tc1 = 1'b1; 
            for (oc = 0; oc < NUM_OUT_CHANNELS; oc++) begin
                for (of = 0; of < NUM_OUT_FRAMES_EXPECTED; of++) begin
                    if (o_result_tb[oc][of] !== golden_output_1[oc][of]) begin
                        expected_f = $itor(golden_output_1[oc][of]) / FIXED_POINT_SCALE; 
                        got_f      = $itor(o_result_tb[oc][of]) / FIXED_POINT_SCALE;
                        $error("[%0t] TC1 MISMATCH for Ch%0d,Frame%0d: Expected %d (F~%0.4f), Got %d (F~%0.4f)",
                               $time, oc, of, golden_output_1[oc][of], expected_f,
                               o_result_tb[oc][of], got_f);
                        test_passed_tc1 = 1'b0;
                    end else begin
                        expected_f = $itor(golden_output_1[oc][of]) / FIXED_POINT_SCALE;
                        got_f      = $itor(o_result_tb[oc][of]) / FIXED_POINT_SCALE;
                        $display("[%0t] TC1 MATCH for Ch%0d,Frame%0d: Expected %d (F~%0.4f), Got %d (F~%0.4f)",
                               $time, oc, of, golden_output_1[oc][of], expected_f, 
                               o_result_tb[oc][of], got_f );
                    end
                end
            end

            if (test_passed_tc1) begin
                $display("[%0t] Conv2 TEST CASE 1 PASSED!", $time);
            end else begin
                $display("[%0t] Conv2 TEST CASE 1 FAILED!", $time);
            end
        end else begin 
            $error("[%0t] TC1 TIMEOUT: Conv2 o_done_tick not received after %0d cycles.", $time, cycles_waited);
            $display("[%0t] Conv2 TEST CASE 1 FAILED (Timeout)!", $time);
        end
        @(posedge clk);

        // ******************** TEST CASE 2 ********************
        $display("[%0t] ========= TEST CASE 2 =========", $time);
        for (ic = 0; ic < NUM_IN_CHANNELS; ic++) begin
            for (igf = 0; igf < NUM_IN_FRAMES; igf++) begin
                i_data_tb[ic][igf] = test_input_2[ic][igf];
            end
        end

        $display("[%0t] Applying input TC2 and starting Conv2 computation...", $time);
        i_start = 1'b1;
        @(posedge clk); 
        i_start = 1'b0;

        cycles_waited = 0;
        while (o_done_tick !== 1'b1 && cycles_waited < 10) begin 
            @(posedge clk);
            cycles_waited++;
        end

        if (o_done_tick === 1'b1) begin
            $display("[%0t] TC2 Conv2 computation done. o_done_tick received.", $time);
            @(posedge clk); // Wait for registered output
            $display("[%0t] TC2 Sampling registered output.", $time);
            #1ps; 

            test_passed_tc2 = 1'b1; 
            for (oc = 0; oc < NUM_OUT_CHANNELS; oc++) begin
                for (of = 0; of < NUM_OUT_FRAMES_EXPECTED; of++) begin
                    if (o_result_tb[oc][of] !== golden_output_2[oc][of]) begin
                        expected_f = $itor(golden_output_2[oc][of]) / FIXED_POINT_SCALE; 
                        got_f      = $itor(o_result_tb[oc][of]) / FIXED_POINT_SCALE;
                        $error("[%0t] TC2 MISMATCH for Ch%0d,Frame%0d: Expected %d (F~%0.4f), Got %d (F~%0.4f)",
                               $time, oc, of, golden_output_2[oc][of], expected_f,
                               o_result_tb[oc][of], got_f);
                        test_passed_tc2 = 1'b0;
                    end else begin
                        expected_f = $itor(golden_output_2[oc][of]) / FIXED_POINT_SCALE;
                        got_f      = $itor(o_result_tb[oc][of]) / FIXED_POINT_SCALE;
                        $display("[%0t] TC2 MATCH for Ch%0d,Frame%0d: Expected %d (F~%0.4f), Got %d (F~%0.4f)",
                               $time, oc, of, golden_output_2[oc][of], expected_f, 
                               o_result_tb[oc][of], got_f );
                    end
                end
            end

            if (test_passed_tc2) begin
                $display("[%0t] Conv2 TEST CASE 2 PASSED!", $time);
            end else begin
                $display("[%0t] Conv2 TEST CASE 2 FAILED!", $time);
            end
        end else begin 
            $error("[%0t] TC2 TIMEOUT: Conv2 o_done_tick not received after %0d cycles.", $time, cycles_waited);
            $display("[%0t] Conv2 TEST CASE 2 FAILED (Timeout)!", $time);
        end

        #(CLK_PERIOD * 5);
        $finish;
    end

endmodule