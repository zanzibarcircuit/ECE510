// tb_relu_module.v
// Testbench for the ReLU module
`timescale 1ns/1ps

module tb_relu_module;

    localparam int DATA_WIDTH = 16;
    localparam int NUM_ELEMENTS = 4; // Corresponds to the reshaped FC output size
    localparam time CLK_PERIOD = 10ns;

    // Testbench signals
    logic clk;
    logic rst_n;
    logic i_start;
    logic signed [DATA_WIDTH-1:0] i_data [0:NUM_ELEMENTS-1];
    logic o_done_tick;
    logic signed [DATA_WIDTH-1:0] o_result [0:NUM_ELEMENTS-1];

    // Instantiate the DUT
    relu_module dut (
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

    // Input values based on actual Verilog fc_layer output (from Python script)
    const logic signed [DATA_WIDTH-1:0] test_input [0:NUM_ELEMENTS-1] = '{
        16'sd108, // Approx Float: 0.4219
        16'sd254, // Approx Float: 0.9922
        16'sd218, // Approx Float: 0.8516
        16'sd186  // Approx Float: 0.7266
    };

    // Golden output (ReLU applied to test_input)
    const logic signed [DATA_WIDTH-1:0] golden_output [0:NUM_ELEMENTS-1] = '{
        16'sd108, // Approx Float: 0.4219
        16'sd254, // Approx Float: 0.9922
        16'sd218, // Approx Float: 0.8516
        16'sd186  // Approx Float: 0.7266
    };
    
    // Test sequence
    initial begin
        // Declare all variables used in this initial block at the beginning
        int cycles_waited;
        logic test_passed;
        real expected_f, got_f; // For display purposes
        int i; // Loop variable

        $display("Starting Testbench for relu_module (SystemVerilog version)...");
        rst_n = 1'b0; // Assert reset
        i_start = 1'b0;
        // Initialize inputs
        for (i = 0; i < NUM_ELEMENTS; i++) begin
            i_data[i] = test_input[i];
        end

        repeat(2) @(posedge clk); // Hold reset for 2 cycles
        rst_n = 1'b1;    // De-assert reset
        @(posedge clk);

        $display("[%0t] Applying input and starting ReLU computation...", $time);
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
            $display("[%0t] ReLU computation done. o_done_tick received.", $time);
            #1ps; // Epsilon delay for non-blocking assignment propagation for checking

            test_passed = 1'b1; // Initialize test_passed
            for (i = 0; i < NUM_ELEMENTS; i++) begin 
                if (o_result[i] !== golden_output[i]) begin
                    expected_f = $itor(golden_output[i]) / 256.0;
                    got_f      = $itor(o_result[i]) / 256.0;
                    $error("[%0t] MISMATCH for output[%0d]: Expected %d (%f), Got %d (%f)",
                           $time, i, golden_output[i], expected_f,
                           o_result[i], got_f);
                    test_passed = 1'b0;
                end else begin
                     expected_f = $itor(golden_output[i]) / 256.0;
                     got_f      = $itor(o_result[i]) / 256.0;
                     $display("[%0t] MATCH for output[%0d]: Expected %d (%0.4f), Got %d (%0.4f)",
                           $time, i, golden_output[i], expected_f, 
                           o_result[i], got_f );
                end
            end

            if (test_passed) begin
                $display("[%0t] ReLU TEST PASSED!", $time);
            end else begin
                $display("[%0t] ReLU TEST FAILED!", $time);
            end
        end else begin
            $error("[%0t] TIMEOUT: ReLU o_done_tick not received after %0d cycles.", $time, cycles_waited);
            $display("[%0t] ReLU TEST FAILED (Timeout)!", $time);
        end

        #(CLK_PERIOD * 5);
        $finish;
    end

endmodule
