`timescale 1ns/1ps

module tb_fc_with_relu_layer;

    // Parameters for fc_with_relu_layer
    localparam int DATA_WIDTH = 16;
    localparam int FRACTIONAL_BITS = 8;
    localparam int LATENT_DIM_FC = 4;
    localparam int NUM_OUT_CHANNELS_FC = 4;
    localparam int NUM_OUT_FRAMES_FC = 1; // This is fixed to 1 in the DUT

    localparam time CLK_PERIOD = 10ns;
    localparam real FIXED_POINT_SCALE = 1.0 * (1 << FRACTIONAL_BITS); // For float display

    // Testbench signals
    logic clk;
    logic rst_n;
    logic i_start;
    logic signed [DATA_WIDTH-1:0] i_z_tb [0:LATENT_DIM_FC-1];

    logic o_busy; // Monitor if needed, not explicitly checked in this TB style
    logic o_done_tick;
    logic signed [DATA_WIDTH-1:0] o_fc_relu_result_tb [0:NUM_OUT_CHANNELS_FC-1][0:NUM_OUT_FRAMES_FC-1];

    // Instantiate the DUT
    fc_with_relu_layer #(
        .DATA_WIDTH(DATA_WIDTH),
        .FRACTIONAL_BITS(FRACTIONAL_BITS),
        .LATENT_DIM_FC(LATENT_DIM_FC),
        .NUM_OUT_CHANNELS_FC(NUM_OUT_CHANNELS_FC),
        .NUM_OUT_FRAMES_FC(NUM_OUT_FRAMES_FC)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .i_start(i_start),
        .i_z(i_z_tb),
        .o_busy(o_busy),
        .o_done_tick(o_done_tick),
        .o_fc_relu_result(o_fc_relu_result_tb)
    );

    // Clock generation
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // --- Test Case 1 Data ---
    const logic signed [DATA_WIDTH-1:0] test_input_1 [0:LATENT_DIM_FC-1] = '{
        16'sd25,  // Approx Float: 25/256 = 0.0977
        16'sd50,  // Approx Float: 50/256 = 0.1953
        16'sd75,  // Approx Float: 75/256 = 0.2930
        16'sd100  // Approx Float: 100/256 = 0.3906
    };
    const logic signed [DATA_WIDTH-1:0] golden_output_1 [0:NUM_OUT_CHANNELS_FC-1][0:NUM_OUT_FRAMES_FC-1] = '{
        '{16'sd79},  // Expected from manual calculation
        '{16'sd180}, // Expected from manual calculation
        '{16'sd158}, // Expected from manual calculation
        '{16'sd136}  // Expected from manual calculation
    };

    // --- Test Case 2 Data ---
    const logic signed [DATA_WIDTH-1:0] test_input_2 [0:LATENT_DIM_FC-1] = '{
        16'sd10,
        16'sd20,
       -16'sd30,
       -16'sd5
    };
    const logic signed [DATA_WIDTH-1:0] golden_output_2 [0:NUM_OUT_CHANNELS_FC-1][0:NUM_OUT_FRAMES_FC-1] = '{
        '{16'sd0},   // Expected from manual calculation (ReLU effect)
        '{16'sd0},   // Expected from manual calculation
        '{16'sd0},   // Expected from manual calculation
        '{16'sd0}    // Expected from manual calculation
    };
    
    // Test sequence
    initial begin
        // Declare all variables used in this initial block at the beginning
        int cycles_waited;
        logic test_passed;
        real expected_f, got_f; // For display purposes
        int i; // Loop variable for channels
        // int j; // Loop variable for frames (not needed as NUM_OUT_FRAMES_FC is 1)

        $display("Starting Testbench for fc_with_relu_layer...");
        rst_n = 1'b0; // Assert reset
        i_start = 1'b0;
        
        // Initialize inputs to a known state (though they'll be set per test case)
        for (i = 0; i < LATENT_DIM_FC; i++) begin
            i_z_tb[i] = 16'sd0;
        end

        repeat(2) @(posedge clk); // Hold reset for 2 cycles
        rst_n = 1'b1;     // De-assert reset
        @(posedge clk);   // Allow one cycle for reset to propagate

        // ******************** TEST CASE 1 ********************
        $display("[%0t] ========= TEST CASE 1: Positive Inputs =========", $time);
        // Apply test_input_1
        for (i = 0; i < LATENT_DIM_FC; i++) begin
            i_z_tb[i] = test_input_1[i];
            $display("[%0t] Applied i_z_tb[%0d] = %d (Approx Float: %0.4f)", $time, i, i_z_tb[i], $itor(i_z_tb[i])/FIXED_POINT_SCALE);
        end

        $display("[%0t] Applying input and starting FC+ReLU computation...", $time);
        i_start = 1'b1;
        @(posedge clk); // Ensure start is seen by DUT
        i_start = 1'b0;

        // Wait for o_done_tick (with a timeout)
        cycles_waited = 0;  
        while (o_done_tick !== 1'b1 && cycles_waited < 10) begin
            @(posedge clk);
            cycles_waited++;
        end

        if (o_done_tick === 1'b1) begin
            $display("[%0t] FC+ReLU computation done. o_done_tick received.", $time);
            // Wait for the next clock edge for the result to be registered if DUT registers on done_tick
            // Based on previous discussions, fc_with_relu_layer registers output on o_done_tick
            @(posedge clk); 
            $display("[%0t] Sampling registered output.", $time);
            #1ps; // Epsilon delay for non-blocking assignment propagation for checking

            test_passed = 1'b1; 
            for (i = 0; i < NUM_OUT_CHANNELS_FC; i++) begin  
                if (o_fc_relu_result_tb[i][0] !== golden_output_1[i][0]) begin
                    expected_f = $itor(golden_output_1[i][0]) / FIXED_POINT_SCALE;
                    got_f      = $itor(o_fc_relu_result_tb[i][0]) / FIXED_POINT_SCALE;
                    $error("[%0t] MISMATCH for output_channel[%0d]: Expected %d (Approx F: %0.4f), Got %d (Approx F: %0.4f)",
                           $time, i, golden_output_1[i][0], expected_f,
                           o_fc_relu_result_tb[i][0], got_f);
                    test_passed = 1'b0;
                end else begin
                    expected_f = $itor(golden_output_1[i][0]) / FIXED_POINT_SCALE;
                    got_f      = $itor(o_fc_relu_result_tb[i][0]) / FIXED_POINT_SCALE;
                    $display("[%0t] MATCH for output_channel[%0d]: Expected %d (Approx F: %0.4f), Got %d (Approx F: %0.4f)",
                           $time, i, golden_output_1[i][0], expected_f, 
                           o_fc_relu_result_tb[i][0], got_f );
                end
            end

            if (test_passed) begin
                $display("[%0t] TEST CASE 1 PASSED!", $time);
            end else begin
                $display("[%0t] TEST CASE 1 FAILED!", $time);
            end
        end else begin
            $error("[%0t] TIMEOUT TC1: FC+ReLU o_done_tick not received after %0d cycles.", $time, cycles_waited);
            $display("[%0t] TEST CASE 1 FAILED (Timeout)!", $time);
        end
        @(posedge clk); // Cycle separation

        // ******************** TEST CASE 2 ********************
        $display("[%0t] ========= TEST CASE 2: Mixed Sign Inputs =========", $time);
        // Apply test_input_2
        for (i = 0; i < LATENT_DIM_FC; i++) begin
            i_z_tb[i] = test_input_2[i];
            $display("[%0t] Applied i_z_tb[%0d] = %d (Approx Float: %0.4f)", $time, i, i_z_tb[i], $itor(i_z_tb[i])/FIXED_POINT_SCALE);
        end

        $display("[%0t] Applying input and starting FC+ReLU computation...", $time);
        i_start = 1'b1;
        @(posedge clk); // Ensure start is seen by DUT
        i_start = 1'b0;

        // Wait for o_done_tick (with a timeout)
        cycles_waited = 0;  
        while (o_done_tick !== 1'b1 && cycles_waited < 10) begin
            @(posedge clk);
            cycles_waited++;
        end

        if (o_done_tick === 1'b1) begin
            $display("[%0t] FC+ReLU computation done. o_done_tick received.", $time);
            @(posedge clk); 
            $display("[%0t] Sampling registered output.", $time);
            #1ps; 

            test_passed = 1'b1; 
            for (i = 0; i < NUM_OUT_CHANNELS_FC; i++) begin  
                if (o_fc_relu_result_tb[i][0] !== golden_output_2[i][0]) begin
                    expected_f = $itor(golden_output_2[i][0]) / FIXED_POINT_SCALE;
                    got_f      = $itor(o_fc_relu_result_tb[i][0]) / FIXED_POINT_SCALE;
                    $error("[%0t] MISMATCH for output_channel[%0d]: Expected %d (Approx F: %0.4f), Got %d (Approx F: %0.4f)",
                           $time, i, golden_output_2[i][0], expected_f,
                           o_fc_relu_result_tb[i][0], got_f);
                    test_passed = 1'b0;
                end else begin
                    expected_f = $itor(golden_output_2[i][0]) / FIXED_POINT_SCALE;
                    got_f      = $itor(o_fc_relu_result_tb[i][0]) / FIXED_POINT_SCALE;
                    $display("[%0t] MATCH for output_channel[%0d]: Expected %d (Approx F: %0.4f), Got %d (Approx F: %0.4f)",
                           $time, i, golden_output_2[i][0], expected_f, 
                           o_fc_relu_result_tb[i][0], got_f );
                end
            end

            if (test_passed) begin
                $display("[%0t] TEST CASE 2 PASSED!", $time);
            end else begin
                $display("[%0t] TEST CASE 2 FAILED!", $time);
            end
        end else begin
            $error("[%0t] TIMEOUT TC2: FC+ReLU o_done_tick not received after %0d cycles.", $time, cycles_waited);
            $display("[%0t] TEST CASE 2 FAILED (Timeout)!", $time);
        end

        #(CLK_PERIOD * 5);
        $finish;
    end

endmodule