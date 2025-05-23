// tb_conv2_module.v
// Testbench for the Conv2D module - Syntax fix for 'else'
`timescale 1ns/1ps

module tb_conv2_module;

    // Parameters matching conv2_module defaults
    localparam int DATA_WIDTH = 16;
    localparam int FRACTIONAL_BITS = 8;
    localparam int NUM_IN_CHANNELS  = 2;
    localparam int NUM_OUT_CHANNELS = 1;
    localparam int KERNEL_SIZE      = 3;
    localparam int PADDING          = 1;
    localparam int STRIDE           = 1;
    localparam int NUM_IN_FRAMES    = 4;
    localparam int NUM_OUT_FRAMES_EXPECTED = ( (NUM_IN_FRAMES + 2 * PADDING) - KERNEL_SIZE) / STRIDE + 1; // Should be 4

    localparam time CLK_PERIOD = 10ns;

    // Testbench signals
    logic clk;
    logic rst_n;
    logic i_start;
    logic signed [DATA_WIDTH-1:0] i_data [0:NUM_IN_CHANNELS-1][0:NUM_IN_FRAMES-1];
    logic o_busy;
    logic o_done_tick;
    logic signed [DATA_WIDTH-1:0] o_result [0:NUM_OUT_CHANNELS-1][0:NUM_OUT_FRAMES_EXPECTED-1];

    // Instantiate the DUT (using conv2_module)
    conv2_module dut (
        .clk(clk),
        .rst_n(rst_n),
        .i_start(i_start),
        .i_data(i_data),
        .o_busy(o_busy),
        .o_done_tick(o_done_tick),
        .o_result(o_result)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Input data (2 channels, 4 frames each) - from Python golden values
    const logic signed [DATA_WIDTH-1:0] test_input [0:NUM_IN_CHANNELS-1][0:NUM_IN_FRAMES-1] = '{
        '{16'sd286, 16'sd286, 16'sd295, 16'sd295}, // Channel 0
        '{16'sd404, 16'sd404, 16'sd402, 16'sd402}  // Channel 1
    };

    // Golden output (1 channel, 4 frames) - from Python golden values
    const logic signed [DATA_WIDTH-1:0] golden_output [0:NUM_OUT_CHANNELS-1][0:NUM_OUT_FRAMES_EXPECTED-1] = '{
        '{16'sd428, 16'sd652, 16'sd652, 16'sd397}  // Output Channel 0
    };
    
    initial begin
        // Declare variables at the beginning of the initial block
        int ic, igf; 
        int oc, of; 
        int cycles_waited;
        logic test_passed;
        real expected_f, got_f;

        $display("Starting Testbench for conv2_module (SystemVerilog version)...");
        rst_n = 1'b0;
        i_start = 1'b0;
        // Initialize inputs
        for (ic = 0; ic < NUM_IN_CHANNELS; ic++) begin
            for (igf = 0; igf < NUM_IN_FRAMES; igf++) begin
                i_data[ic][igf] = test_input[ic][igf];
            end
        end

        repeat(2) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        $display("[%0t] Applying input and starting Conv2 computation...", $time);
        i_start = 1'b1;
        @(posedge clk); // Ensure start is seen by DUT
        i_start = 1'b0;

        cycles_waited = 0;
        // Timeout should be NUM_OUT_CHANNELS * NUM_OUT_FRAMES_EXPECTED + some buffer for state transitions
        while (o_done_tick !== 1'b1 && cycles_waited < (NUM_OUT_CHANNELS * NUM_OUT_FRAMES_EXPECTED + 10)) begin
            @(posedge clk);
            cycles_waited++;
        end

        if (o_done_tick === 1'b1) begin
            $display("[%0t] Conv2 computation done. o_done_tick received after %0d compute cycles (approx).", $time, cycles_waited);
            #1ps; // Epsilon delay for non-blocking assignment propagation for checking

            test_passed = 1'b1; // Initialize test_passed
            for (oc = 0; oc < NUM_OUT_CHANNELS; oc++) begin
                for (of = 0; of < NUM_OUT_FRAMES_EXPECTED; of++) begin
                    if (o_result[oc][of] !== golden_output[oc][of]) begin
                        expected_f = $itor(golden_output[oc][of]) / 256.0; 
                        got_f      = $itor(o_result[oc][of]) / 256.0;
                        $error("[%0t] MISMATCH for output Ch%0d,Frame%0d: Expected %d (%f), Got %d (%f)",
                               $time, oc, of, golden_output[oc][of], expected_f,
                               o_result[oc][of], got_f);
                        test_passed = 1'b0;
                    end else begin
                         expected_f = $itor(golden_output[oc][of]) / 256.0;
                         got_f      = $itor(o_result[oc][of]) / 256.0;
                         $display("[%0t] MATCH for output Ch%0d,Frame%0d: Expected %d (%0.4f), Got %d (%0.4f)",
                               $time, oc, of, golden_output[oc][of], expected_f, 
                               o_result[oc][of], got_f );
                    end
                end
            end

            // ** Corrected if/else structure **
            if (test_passed) begin
                $display("[%0t] Conv2 TEST PASSED!", $time);
            end else begin // This 'else' corresponds to 'if (test_passed)'
                $display("[%0t] Conv2 TEST FAILED!", $time);
            end
        // This 'end' closes the 'if (o_done_tick === 1'b1)' block
        end else begin // This 'else' corresponds to 'if (o_done_tick === 1'b1)'
            $error("[%0t] TIMEOUT: Conv2 o_done_tick not received after %0d cycles.", $time, cycles_waited);
            $display("[%0t] Conv2 TEST FAILED (Timeout)!", $time);
        end

        #(CLK_PERIOD * 5);
        $finish;
    end

endmodule
