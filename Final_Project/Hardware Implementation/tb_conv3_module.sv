// tb_conv3_module_parallel.sv
// Testbench for the parallelized Conv3 output module
`timescale 1ns/1ps

module tb_conv3_module_parallel;

    // Parameters matching your conv3_output_module
    localparam int DATA_WIDTH = 16;
    localparam int FRACTIONAL_BITS = 8; // For DUT and float display
    localparam int NUM_IN_CHANNELS  = 1;
    localparam int NUM_OUT_CHANNELS = 2;
    localparam int KERNEL_SIZE      = 1;
    localparam int PADDING          = 0;
    localparam int STRIDE           = 1;
    localparam int NUM_IN_FRAMES    = 4;
    localparam int NUM_OUT_FRAMES_EXPECTED = ((NUM_IN_FRAMES + 2 * PADDING) - KERNEL_SIZE) / STRIDE + 1;

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

    // Instantiate the DUT (conv3_output_module)
    conv3_output_module #(
        .DATA_WIDTH(DATA_WIDTH),
        .FRACTIONAL_BITS(FRACTIONAL_BITS),
        .NUM_IN_CHANNELS(NUM_IN_CHANNELS),
        .NUM_OUT_CHANNELS(NUM_OUT_CHANNELS),
        .KERNEL_SIZE(KERNEL_SIZE),
        .PADDING(PADDING),
        .STRIDE(STRIDE),
        .NUM_IN_FRAMES(NUM_IN_FRAMES)
        // .P_NUM_OUT_FRAMES(NUM_OUT_FRAMES_EXPECTED) // Calculated inside DUT
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

    // Input data for Test Case 1
    const logic signed [DATA_WIDTH-1:0] test_input_1 [0:NUM_IN_CHANNELS-1][0:NUM_IN_FRAMES-1] = '{
        '{16'sd10, 16'sd20, 16'sd30, 16'sd40} // IC0
    };

    // Golden output for Test Case 1
    const logic signed [DATA_WIDTH-1:0] golden_output_1 [0:NUM_OUT_CHANNELS-1][0:NUM_OUT_FRAMES_EXPECTED-1] = '{
        '{16'sd28, 16'sd36, 16'sd44, 16'sd52}, // OC0
        '{16'sd32, 16'sd41, 16'sd50, 16'sd59}  // OC1
    };
    
    initial begin
        int ic, igf; 
        int oc, of; 
        int cycles_waited;
        logic test_passed_tc1;
        real expected_f, got_f;

        $display("Starting Testbench for parallel conv3_output_module...");
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

        $display("[%0t] Applying input TC1 and starting Conv3 computation...", $time);
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
            $display("[%0t] TC1 Conv3 computation done. o_done_tick received.", $time);
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
                $display("[%0t] Conv3 TEST CASE 1 PASSED!", $time);
            end else begin
                $display("[%0t] Conv3 TEST CASE 1 FAILED!", $time);
            end
        end else begin 
            $error("[%0t] TC1 TIMEOUT: Conv3 o_done_tick not received after %0d cycles.", $time, cycles_waited);
            $display("[%0t] Conv3 TEST CASE 1 FAILED (Timeout)!", $time);
        end
        // Add more test cases here if desired, following the same pattern

        #(CLK_PERIOD * 5);
        $finish;
    end

endmodule