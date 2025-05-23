// tb_upsample_module_after_conv1relu.v
// Testbench for the 2nd Upsample module (input from Conv1->ReLU output)
`timescale 1ns/1ps

module tb_upsample_module_after_conv1relu;

    localparam int DATA_WIDTH = 16;
    // Parameters for this specific Upsample instance
    localparam int NUM_CHANNELS_TB = 2;
    localparam int FRAMES_PER_CHANNEL_IN_TB = 2; // Input frames to this upsampler
    localparam int SCALE_FACTOR_TB = 2;
    localparam int FRAMES_PER_CHANNEL_OUT_TB = FRAMES_PER_CHANNEL_IN_TB * SCALE_FACTOR_TB; // Expected output frames

    localparam time CLK_PERIOD = 10ns;

    logic clk;
    logic rst_n;
    logic i_start;
    logic signed [DATA_WIDTH-1:0] i_data [0:NUM_CHANNELS_TB-1][0:FRAMES_PER_CHANNEL_IN_TB-1];
    logic o_done_tick;
    logic signed [DATA_WIDTH-1:0] o_result [0:NUM_CHANNELS_TB-1][0:FRAMES_PER_CHANNEL_OUT_TB-1];

    // Instantiate the DUT with specific parameters
    upsample_module #(
        .NUM_CHANNELS(NUM_CHANNELS_TB),
        .FRAMES_PER_CHANNEL_IN(FRAMES_PER_CHANNEL_IN_TB), // Pass correct input frames
        .SCALE_FACTOR(SCALE_FACTOR_TB),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .i_start(i_start),
        .i_data(i_data),
        .o_done_tick(o_done_tick),
        .o_result(o_result)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Input values (output from 2nd ReLU stage)
    const logic signed [DATA_WIDTH-1:0] test_input [0:NUM_CHANNELS_TB-1][0:FRAMES_PER_CHANNEL_IN_TB-1] = '{
        '{16'sd286, 16'sd295}, // Channel 0
        '{16'sd404, 16'sd402}  // Channel 1
    };

    // Golden output (Upsampled: 2 channels, 4 frames each)
    const logic signed [DATA_WIDTH-1:0] golden_output [0:NUM_CHANNELS_TB-1][0:FRAMES_PER_CHANNEL_OUT_TB-1] = '{
        '{16'sd286, 16'sd286, 16'sd295, 16'sd295}, // Channel 0
        '{16'sd404, 16'sd404, 16'sd402, 16'sd402}  // Channel 1
    };
    
    initial begin
        int ch, fr_in, fr_out;
        int cycles_waited;
        logic test_passed;
        real expected_f, got_f;

        $display("Starting Testbench for 2nd upsample_module (input from Conv1->ReLU)...");
        rst_n = 1'b0;
        i_start = 1'b0;
        for (ch = 0; ch < NUM_CHANNELS_TB; ch++) begin
            for (fr_in = 0; fr_in < FRAMES_PER_CHANNEL_IN_TB; fr_in++) begin
                i_data[ch][fr_in] = test_input[ch][fr_in];
            end
        end

        repeat(2) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        $display("[%0t] Applying input and starting 2nd Upsample computation...", $time);
        i_start = 1'b1;
        @(posedge clk);
        i_start = 1'b0;

        cycles_waited = 0;
        while (o_done_tick !== 1'b1 && cycles_waited < 10) begin
            @(posedge clk);
            cycles_waited++;
        end

        if (o_done_tick === 1'b1) begin
            $display("[%0t] 2nd Upsample computation done. o_done_tick received.", $time);
            #1ps; 

            test_passed = 1'b1;
            for (ch = 0; ch < NUM_CHANNELS_TB; ch++) begin
                for (fr_out = 0; fr_out < FRAMES_PER_CHANNEL_OUT_TB; fr_out++) begin
                    if (o_result[ch][fr_out] !== golden_output[ch][fr_out]) begin
                        expected_f = $itor(golden_output[ch][fr_out]) / 256.0;
                        got_f      = $itor(o_result[ch][fr_out]) / 256.0;
                        $error("[%0t] MISMATCH for output Ch%0d,Frame%0d: Expected %d (%f), Got %d (%f)",
                               $time, ch, fr_out, golden_output[ch][fr_out], expected_f,
                               o_result[ch][fr_out], got_f);
                        test_passed = 1'b0;
                    end else begin
                         expected_f = $itor(golden_output[ch][fr_out]) / 256.0;
                         got_f      = $itor(o_result[ch][fr_out]) / 256.0;
                         $display("[%0t] MATCH for output Ch%0d,Frame%0d: Expected %d (%0.4f), Got %d (%0.4f)",
                               $time, ch, fr_out, golden_output[ch][fr_out], expected_f, 
                               o_result[ch][fr_out], got_f );
                    end
                end
            end

            if (test_passed) begin
                $display("[%0t] 2nd Upsample TEST PASSED!", $time);
            end else begin
                $display("[%0t] 2nd Upsample TEST FAILED!", $time);
            end
        end else begin
            $error("[%0t] TIMEOUT: 2nd Upsample o_done_tick not received after %0d cycles.", $time, cycles_waited);
            $display("[%0t] 2nd Upsample TEST FAILED (Timeout)!", $time);
        end

        #(CLK_PERIOD * 5);
        $finish;
    end

endmodule
