// tb_relu_module_final.v
// Testbench for the 4th (Final) ReLU module (input from Conv3_Output)
`timescale 1ns/1ps

module tb_relu_module_final;

    localparam int DATA_WIDTH = 16;
    // Parameters for this specific ReLU instance
    localparam int NUM_CHANNELS_TB = 2;
    localparam int FRAMES_PER_CHANNEL_TB = 4; 
    localparam time CLK_PERIOD = 10ns;

    // Testbench signals
    logic clk;
    logic rst_n;
    logic i_start;
    logic signed [DATA_WIDTH-1:0] i_data [0:NUM_CHANNELS_TB-1][0:FRAMES_PER_CHANNEL_TB-1];
    logic o_done_tick;
    logic signed [DATA_WIDTH-1:0] o_result [0:NUM_CHANNELS_TB-1][0:FRAMES_PER_CHANNEL_TB-1];

    // Instantiate the DUT with specific parameters
    relu_module #(
        .NUM_CHANNELS(NUM_CHANNELS_TB),
        .FRAMES_PER_CHANNEL(FRAMES_PER_CHANNEL_TB),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .i_start(i_start),
        .i_data(i_data),
        .o_done_tick(o_done_tick),
        .o_result(o_result)
    );

    // Clock generation
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Input values (output from Conv3_Output)
    const logic signed [DATA_WIDTH-1:0] test_input [0:NUM_CHANNELS_TB-1][0:FRAMES_PER_CHANNEL_TB-1] = '{
        '{16'sd363, 16'sd542, 16'sd542, 16'sd338}, // Channel 0
        '{16'sd408, 16'sd609, 16'sd609, 16'sd380}  // Channel 1
    };

    // Golden output (ReLU applied to test_input)
    const logic signed [DATA_WIDTH-1:0] golden_output [0:NUM_CHANNELS_TB-1][0:FRAMES_PER_CHANNEL_TB-1] = '{
        '{16'sd363, 16'sd542, 16'sd542, 16'sd338}, // Channel 0
        '{16'sd408, 16'sd609, 16'sd609, 16'sd380}  // Channel 1
    };
    
    // Test sequence
    initial begin
        // Declare all variables used in this initial block at the beginning
        int ch, fr;
        int cycles_waited;
        logic test_passed;
        real expected_f, got_f; // For display purposes

        $display("Starting Testbench for 4th (Final) relu_module (input from Conv3_Output)...");
        rst_n = 1'b0; 
        i_start = 1'b0;
        // Initialize inputs
        for (ch = 0; ch < NUM_CHANNELS_TB; ch++) begin
            for (fr = 0; fr < FRAMES_PER_CHANNEL_TB; fr++) begin
                i_data[ch][fr] = test_input[ch][fr];
            end
        end

        repeat(2) @(posedge clk); 
        rst_n = 1'b1;    
        @(posedge clk);

        $display("[%0t] Applying input and starting 4th ReLU computation...", $time);
        i_start = 1'b1;
        @(posedge clk); 
        i_start = 1'b0;

        cycles_waited = 0; 
        while (o_done_tick !== 1'b1 && cycles_waited < 10) begin
            @(posedge clk);
            cycles_waited++;
        end

        if (o_done_tick === 1'b1) begin
            $display("[%0t] 4th ReLU computation done. o_done_tick received.", $time);
            #1ps; 

            test_passed = 1'b1; 
            for (ch = 0; ch < NUM_CHANNELS_TB; ch++) begin 
                for (fr = 0; fr < FRAMES_PER_CHANNEL_TB; fr++) begin
                    if (o_result[ch][fr] !== golden_output[ch][fr]) begin
                        expected_f = $itor(golden_output[ch][fr]) / 256.0;
                        got_f      = $itor(o_result[ch][fr]) / 256.0;
                        $error("[%0t] MISMATCH for output Ch%0d,Frame%0d: Expected %d (%f), Got %d (%f)",
                               $time, ch, fr, golden_output[ch][fr], expected_f,
                               o_result[ch][fr], got_f);
                        test_passed = 1'b0;
                    end else begin
                         expected_f = $itor(golden_output[ch][fr]) / 256.0;
                         got_f      = $itor(o_result[ch][fr]) / 256.0;
                         $display("[%0t] MATCH for output Ch%0d,Frame%0d: Expected %d (%0.4f), Got %d (%0.4f)",
                               $time, ch, fr, golden_output[ch][fr], expected_f, 
                               o_result[ch][fr], got_f );
                    end
                end
            end

            if (test_passed) begin
                $display("[%0t] 4th (Final) ReLU TEST PASSED!", $time);
            end else begin
                $display("[%0t] 4th (Final) ReLU TEST FAILED!", $time);
            end
        end else begin
            $error("[%0t] TIMEOUT: 4th ReLU o_done_tick not received after %0d cycles.", $time, cycles_waited);
            $display("[%0t] 4th (Final) ReLU TEST FAILED (Timeout)!", $time);
        end

        #(CLK_PERIOD * 5);
        $finish;
    end

endmodule
