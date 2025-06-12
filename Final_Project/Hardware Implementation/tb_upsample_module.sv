// tb_upsample_module_generic.sv
// Testbench for the generic upsample_module
`timescale 1ns/1ps

module tb_upsample_module_generic;

    localparam int DATA_WIDTH = 16;
    // Parameters for this specific Upsample instance for testing
    localparam int NUM_CHANNELS_TB = 2;          // Example: 2 channels
    localparam int FRAMES_PER_CHANNEL_IN_TB = 2; // Example: 2 input frames per channel
    localparam int SCALE_FACTOR_TB = 2;          // Example: Upsample by 2
    localparam int FRAMES_PER_CHANNEL_OUT_TB = FRAMES_PER_CHANNEL_IN_TB * SCALE_FACTOR_TB; // Expected output frames

    localparam time CLK_PERIOD = 10ns;
    localparam real FIXED_POINT_SCALE = 256.0; // Assuming 8 fractional bits for display purposes

    // Testbench signals
    logic clk;
    logic rst_n;
    logic i_start;
    logic signed [DATA_WIDTH-1:0] i_data_tb [0:NUM_CHANNELS_TB-1][0:FRAMES_PER_CHANNEL_IN_TB-1];
    logic o_done_tick;
    logic signed [DATA_WIDTH-1:0] o_result_tb [0:NUM_CHANNELS_TB-1][0:FRAMES_PER_CHANNEL_OUT_TB-1];

    // Instantiate the DUT with specific parameters
    upsample_module #(
        .NUM_CHANNELS(NUM_CHANNELS_TB),
        .FRAMES_PER_CHANNEL_IN(FRAMES_PER_CHANNEL_IN_TB),
        .SCALE_FACTOR(SCALE_FACTOR_TB),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .i_start(i_start),
        .i_data(i_data_tb),    // Connect testbench data to DUT input
        .o_done_tick(o_done_tick),
        .o_result(o_result_tb) // Connect DUT output to testbench signal
    );

    // Clock generation
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // --- Test Case 1 Data ---
    const logic signed [DATA_WIDTH-1:0] test_input_1 [0:NUM_CHANNELS_TB-1][0:FRAMES_PER_CHANNEL_IN_TB-1] = '{
        '{16'sd111, 16'sd222}, // Channel 0: Frame0=111, Frame1=222
        '{16'sd333, 16'sd444}  // Channel 1: Frame0=333, Frame1=444
    };
    // Golden output for Test Case 1 (Upsampled by 2)
    const logic signed [DATA_WIDTH-1:0] golden_output_1 [0:NUM_CHANNELS_TB-1][0:FRAMES_PER_CHANNEL_OUT_TB-1] = '{
        '{16'sd111, 16'sd111, 16'sd222, 16'sd222}, // Channel 0
        '{16'sd333, 16'sd333, 16'sd444, 16'sd444}  // Channel 1
    };

    // --- Test Case 2 Data: With some negative values ---
    const logic signed [DATA_WIDTH-1:0] test_input_2 [0:NUM_CHANNELS_TB-1][0:FRAMES_PER_CHANNEL_IN_TB-1] = '{
        '{-16'sd50, 16'sd60},  // Channel 0
        '{16'sd70, -16'sd80}   // Channel 1
    };
    // Golden output for Test Case 2 (Upsampled by 2)
    const logic signed [DATA_WIDTH-1:0] golden_output_2 [0:NUM_CHANNELS_TB-1][0:FRAMES_PER_CHANNEL_OUT_TB-1] = '{
        '{-16'sd50, -16'sd50, 16'sd60,  16'sd60},  // Channel 0
        '{16'sd70,  16'sd70, -16'sd80, -16'sd80}   // Channel 1
    };
    
    initial begin
        int ch, fr_in, fr_out;
        int cycles_waited;
        logic test_passed_tc1, test_passed_tc2;
        real expected_f, got_f;

        $display("Starting Testbench for upsample_module (Generic)...");
        rst_n = 1'b0;
        i_start = 1'b0;
        // Initialize inputs (will be overwritten per test case)
        for (ch = 0; ch < NUM_CHANNELS_TB; ch++) begin
            for (fr_in = 0; fr_in < FRAMES_PER_CHANNEL_IN_TB; fr_in++) begin
                i_data_tb[ch][fr_in] = 16'sd0;
            end
        end

        repeat(2) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        // ******************** TEST CASE 1 ********************
        $display("[%0t] ========= TEST CASE 1: Positive Inputs =========", $time);
        for (ch = 0; ch < NUM_CHANNELS_TB; ch++) begin
            for (fr_in = 0; fr_in < FRAMES_PER_CHANNEL_IN_TB; fr_in++) begin
                i_data_tb[ch][fr_in] = test_input_1[ch][fr_in];
            end
        end

        $display("[%0t] Applying input for TC1 and starting Upsample computation...", $time);
        i_start = 1'b1;
        @(posedge clk);
        i_start = 1'b0;

        cycles_waited = 0;
        while (o_done_tick !== 1'b1 && cycles_waited < 10) begin
            @(posedge clk);
            cycles_waited++;
        end

        if (o_done_tick === 1'b1) begin
            $display("[%0t] TC1 Upsample computation done. o_done_tick received.", $time);
            // Upsample module output is combinational based on current input if state is UPSAMPLE_DATA
            // and registers on o_done_tick. Wait for that registered output.
            @(posedge clk); 
            $display("[%0t] TC1 Sampling registered output.", $time);
            #1ps; 

            test_passed_tc1 = 1'b1;
            for (ch = 0; ch < NUM_CHANNELS_TB; ch++) begin
                for (fr_out = 0; fr_out < FRAMES_PER_CHANNEL_OUT_TB; fr_out++) begin
                    if (o_result_tb[ch][fr_out] !== golden_output_1[ch][fr_out]) begin
                        expected_f = $itor(golden_output_1[ch][fr_out]) / FIXED_POINT_SCALE;
                        got_f      = $itor(o_result_tb[ch][fr_out]) / FIXED_POINT_SCALE;
                        $error("[%0t] TC1 MISMATCH for Ch%0d,Frame%0d: Expected %d (F~%0.4f), Got %d (F~%0.4f)",
                               $time, ch, fr_out, golden_output_1[ch][fr_out], expected_f,
                               o_result_tb[ch][fr_out], got_f);
                        test_passed_tc1 = 1'b0;
                    end else begin
                        expected_f = $itor(golden_output_1[ch][fr_out]) / FIXED_POINT_SCALE;
                        got_f      = $itor(o_result_tb[ch][fr_out]) / FIXED_POINT_SCALE;
                        $display("[%0t] TC1 MATCH for Ch%0d,Frame%0d: Expected %d (F~%0.4f), Got %d (F~%0.4f)",
                               $time, ch, fr_out, golden_output_1[ch][fr_out], expected_f, 
                               o_result_tb[ch][fr_out], got_f );
                    end
                end
            end

            if (test_passed_tc1) begin
                $display("[%0t] Upsample TEST CASE 1 PASSED!", $time);
            end else begin
                $display("[%0t] Upsample TEST CASE 1 FAILED!", $time);
            end
        end else begin
            $error("[%0t] TC1 TIMEOUT: Upsample o_done_tick not received after %0d cycles.", $time, cycles_waited);
            $display("[%0t] Upsample TEST CASE 1 FAILED (Timeout)!", $time);
        end
        @(posedge clk); // Cycle separation

        // ******************** TEST CASE 2 ********************
        $display("[%0t] ========= TEST CASE 2: Mixed Sign Inputs =========", $time);
        for (ch = 0; ch < NUM_CHANNELS_TB; ch++) begin
            for (fr_in = 0; fr_in < FRAMES_PER_CHANNEL_IN_TB; fr_in++) begin
                i_data_tb[ch][fr_in] = test_input_2[ch][fr_in];
            end
        end
        
        $display("[%0t] Applying input for TC2 and starting Upsample computation...", $time);
        i_start = 1'b1;
        @(posedge clk);
        i_start = 1'b0;

        cycles_waited = 0;
        while (o_done_tick !== 1'b1 && cycles_waited < 10) begin
            @(posedge clk);
            cycles_waited++;
        end

        if (o_done_tick === 1'b1) begin
            $display("[%0t] TC2 Upsample computation done. o_done_tick received.", $time);
            @(posedge clk); 
            $display("[%0t] TC2 Sampling registered output.", $time);
            #1ps; 

            test_passed_tc2 = 1'b1;
            for (ch = 0; ch < NUM_CHANNELS_TB; ch++) begin
                for (fr_out = 0; fr_out < FRAMES_PER_CHANNEL_OUT_TB; fr_out++) begin
                    if (o_result_tb[ch][fr_out] !== golden_output_2[ch][fr_out]) begin
                        expected_f = $itor(golden_output_2[ch][fr_out]) / FIXED_POINT_SCALE;
                        got_f      = $itor(o_result_tb[ch][fr_out]) / FIXED_POINT_SCALE;
                        $error("[%0t] TC2 MISMATCH for Ch%0d,Frame%0d: Expected %d (F~%0.4f), Got %d (F~%0.4f)",
                               $time, ch, fr_out, golden_output_2[ch][fr_out], expected_f,
                               o_result_tb[ch][fr_out], got_f);
                        test_passed_tc2 = 1'b0;
                    end else begin
                        expected_f = $itor(golden_output_2[ch][fr_out]) / FIXED_POINT_SCALE;
                        got_f      = $itor(o_result_tb[ch][fr_out]) / FIXED_POINT_SCALE;
                        $display("[%0t] TC2 MATCH for Ch%0d,Frame%0d: Expected %d (F~%0.4f), Got %d (F~%0.4f)",
                               $time, ch, fr_out, golden_output_2[ch][fr_out], expected_f, 
                               o_result_tb[ch][fr_out], got_f );
                    end
                end
            end

            if (test_passed_tc2) begin
                $display("[%0t] Upsample TEST CASE 2 PASSED!", $time);
            end else begin
                $display("[%0t] Upsample TEST CASE 2 FAILED!", $time);
            end
        end else begin
            $error("[%0t] TC2 TIMEOUT: Upsample o_done_tick not received after %0d cycles.", $time, cycles_waited);
            $display("[%0t] Upsample TEST CASE 2 FAILED (Timeout)!", $time);
        end

        #(CLK_PERIOD * 5);
        $finish;
    end

endmodule