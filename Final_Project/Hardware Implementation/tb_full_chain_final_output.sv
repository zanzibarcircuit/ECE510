`timescale 1ns/1ps

module tb_full_chain_final_output;

    // Parameters from full_chain_stage4 (or can be set here if overriding)
    localparam int DATA_WIDTH = 16;
    localparam int FRACTIONAL_BITS = 8;
    localparam int LATENT_DIM = 4;
    localparam int C3_OUT_CH_EXPECTED = 2; // From full_chain_stage4 C3_OUT_CH
    localparam int FINAL_OUT_FRAMES_EXPECTED = 8; // From full_chain_stage4 P_CHAIN_FINAL_OUT_FRAMES

    localparam time CLK_PERIOD = 10ns;
    localparam real FIXED_POINT_SCALE = 1.0 * (1 << FRACTIONAL_BITS);

    // Testbench signals
    logic clk;
    logic rst_n;
    logic i_top_start;
    logic signed [DATA_WIDTH-1:0] i_z_top_tb [0:LATENT_DIM-1];

    logic o_top_busy;
    logic o_top_done_tick;
    logic signed [DATA_WIDTH-1:0] o_chain_result_tb [0:C3_OUT_CH_EXPECTED-1][0:FINAL_OUT_FRAMES_EXPECTED-1];

    // Instantiate the Unit Under Test (UUT)
    full_chain_stage4 uut (
        .clk(clk),
        .rst_n(rst_n),
        .i_top_start(i_top_start),
        .i_z_top(i_z_top_tb),
        .o_top_busy(o_top_busy),
        .o_top_done_tick(o_top_done_tick),
        .o_chain_result(o_chain_result_tb)
    );

    // Clock generation
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // --- Test Input Data ---
    const logic signed [DATA_WIDTH-1:0] test_input_iz [0:LATENT_DIM-1] = '{
        16'sd25, 16'sd50, 16'sd75, 16'sd100
    };

    // --- Golden Final Output ---
    // !!! CRITICAL: These values are PLACEHOLDERS based on previous partial calculations.
    // You MUST replace them with the accurately calculated final output of your
    // entire network for the 'test_input_iz' above.
    const logic signed [DATA_WIDTH-1:0] golden_chain_result [0:C3_OUT_CH_EXPECTED-1][0:FINAL_OUT_FRAMES_EXPECTED-1] = '{
        // Channel 0 (8 frames) - Example Placeholder Values
        '{16'sd275, 16'sd275, 16'sd406, 16'sd406, 16'sd406, 16'sd406, 16'sd260, 16'sd260},
        // Channel 1 (8 frames) - Example Placeholder Values
        '{16'sd309, 16'sd309, 16'sd455, 16'sd455, 16'sd455, 16'sd455, 16'sd288, 16'sd288}
    };

    initial begin
        logic test_passed;
        int cycles_waited;
        int ch, fr;
        real expected_f, got_f;

        $display("Starting Testbench for full_chain_stage4 (Final Output Check)...");
        rst_n = 1'b0;
        i_top_start = 1'b0;
        for (int i = 0; i < LATENT_DIM; i++) begin
            i_z_top_tb[i] = 16'sd0; // Initialize
        end

        repeat(2) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        // Load input
        for (int i = 0; i < LATENT_DIM; i++) begin
            i_z_top_tb[i] = test_input_iz[i];
            $display("[%0t] Testbench: i_z_top_tb[%0d] = %d", $time, i, i_z_top_tb[i]);
        end

        $display("[%0t] Starting full chain computation...", $time);
        i_top_start = 1'b1;
        @(posedge clk);
        i_top_start = 1'b0;

        // Wait for o_top_done_tick with a timeout
        // Timeout should be generous enough for the entire chain.
        // Since all conv layers are parallel, FSM has ~20 states (2 per module + transitions)
        // So, 20*2 + buffer = ~50-100 cycles should be plenty.
        cycles_waited = 0;
        while (o_top_done_tick !== 1'b1 && cycles_waited < 100) begin
            @(posedge clk);
            cycles_waited++;
        end

        if (o_top_done_tick === 1'b1) begin
            $display("[%0t] Full chain computation done. o_top_done_tick received.", $time);
            // Wait for the final registered output to be stable
            @(posedge clk);
            $display("[%0t] Sampling final registered o_chain_result_tb.", $time);
            #1ps; // Epsilon delay

            test_passed = 1'b1;
            $display("Checking Final Output (o_chain_result_tb):");
            for (ch = 0; ch < C3_OUT_CH_EXPECTED; ch++) begin
                for (fr = 0; fr < FINAL_OUT_FRAMES_EXPECTED; fr++) begin
                    if (o_chain_result_tb[ch][fr] !== golden_chain_result[ch][fr]) begin
                        expected_f = $itor(golden_chain_result[ch][fr]) / FIXED_POINT_SCALE;
                        got_f      = $itor(o_chain_result_tb[ch][fr]) / FIXED_POINT_SCALE;
                        $error("[%0t] FINAL MISMATCH Ch%0d,Fr%0d: Exp %d (F~%0.4f), Got %d (F~%0.4f)",
                               $time, ch, fr, golden_chain_result[ch][fr], expected_f,
                               o_chain_result_tb[ch][fr], got_f);
                        test_passed = 1'b0;
                    end else begin
                        // Optional: Display matches for verbosity during debugging
                        expected_f = $itor(golden_chain_result[ch][fr]) / FIXED_POINT_SCALE;
                        got_f      = $itor(o_chain_result_tb[ch][fr]) / FIXED_POINT_SCALE;
                        $display("[%0t] FINAL MATCH Ch%0d,Fr%0d: Exp %d (F~%0.4f), Got %d (F~%0.4f)",
                               $time, ch, fr, golden_chain_result[ch][fr], expected_f,
                               o_chain_result_tb[ch][fr], got_f);
                    end
                end
            end

            if (test_passed) begin
                $display("[%0t] FULL CHAIN TEST PASSED!", $time);
            end else begin
                $display("[%0t] FULL CHAIN TEST FAILED!", $time);
            end

        end else begin
            $error("[%0t] TIMEOUT: Full chain o_top_done_tick not received after %0d cycles.", $time, cycles_waited);
            $display("[%0t] FULL CHAIN TEST FAILED (Timeout)!", $time);
        end

        #(CLK_PERIOD * 5);
        $finish;
    end

endmodule