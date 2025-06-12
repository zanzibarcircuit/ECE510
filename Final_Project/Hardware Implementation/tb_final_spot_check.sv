`timescale 1ns/1ps

module spot_check_tb;

    // Parameters for the chain
    localparam int DATA_WIDTH = 16;
    localparam int FRACTIONAL_BITS = 8; 
    localparam int LATENT_DIM = 4;
    // Stage 1: FC_ReLU
    localparam int FC_RELU_OUT_CH = 4;
    localparam int FC_RELU_OUT_FR = 1;
    // Stage 2: Upsample0
    localparam int UP0_SCALE_FACTOR = 2; 
    // Stage 3: Conv1
    localparam int C1_OUT_CH = 2; 
    localparam int C1_K = 3; 
    localparam int C1_P = 1; 
    localparam int C1_S = 1;
    // Stage 4: ReLU1
    // Stage 5: Upsample1
    localparam int UP1_SCALE_FACTOR = 2;
    // Stage 6: Conv2
    localparam int C2_OUT_CH = 1; 
    localparam int C2_K = 3;
    localparam int C2_P = 1;
    localparam int C2_S = 1;
    // Stage 7: ReLU2
    // Stage 8: Upsample2
    localparam int UP2_SCALE_FACTOR = 2;
    // Stage 9: Conv3
    localparam int C3_OUT_CH_TB = 2; 
    localparam int C3_K_TB = 1;    
    localparam int C3_P_TB = 0;    
    localparam int C3_S_TB = 1;    
    // Stage 10: ReLU3 (dimensions derived from Conv3)


    localparam time CLK_PERIOD = 10ns;
    localparam signed [31:0] ROUND_CONST_TB = (FRACTIONAL_BITS > 0) ? (1 << (FRACTIONAL_BITS - 1)) : 0;


    // Calculated dimensions for chain output (after ReLU3)
    localparam int UP0_OUT_FR_TB = FC_RELU_OUT_FR * UP0_SCALE_FACTOR;
    localparam int C1_IN_CH_ACTUAL_TB = FC_RELU_OUT_CH;
    localparam int C1_IN_FR_ACTUAL_TB = UP0_OUT_FR_TB;
    localparam int C1_OUT_FR_CALC_TB = ((C1_IN_FR_ACTUAL_TB + 2 * C1_P) - C1_K) / C1_S + 1;
    
    localparam int UP1_IN_CH_ACTUAL_TB = C1_OUT_CH;
    localparam int UP1_IN_FR_ACTUAL_TB = C1_OUT_FR_CALC_TB;
    localparam int UP1_OUT_FR_TB = UP1_IN_FR_ACTUAL_TB * UP1_SCALE_FACTOR;
    
    localparam int C2_IN_CH_ACTUAL_TB = UP1_IN_CH_ACTUAL_TB;
    localparam int C2_IN_FR_ACTUAL_TB = UP1_OUT_FR_TB;
    localparam int C2_OUT_FR_CALC_TB = ((C2_IN_FR_ACTUAL_TB + 2 * C2_P) - C2_K) / C2_S + 1; 
    
    localparam int RELU2_IN_CH_ACTUAL_TB = C2_OUT_CH;
    localparam int RELU2_IN_FR_ACTUAL_TB = C2_OUT_FR_CALC_TB;

    localparam int UP2_IN_CH_ACTUAL_TB = RELU2_IN_CH_ACTUAL_TB;
    localparam int UP2_IN_FR_ACTUAL_TB = RELU2_IN_FR_ACTUAL_TB;
    localparam int UP2_OUT_FR_TB = UP2_IN_FR_ACTUAL_TB * UP2_SCALE_FACTOR; 
    
    localparam int C3_IN_CH_ACTUAL_TB = UP2_IN_CH_ACTUAL_TB; 
    localparam int C3_IN_FR_ACTUAL_TB = UP2_OUT_FR_TB;       
    localparam int C3_OUT_FR_CALC_TB = ((C3_IN_FR_ACTUAL_TB + 2 * C3_P_TB) - C3_K_TB) / C3_S_TB + 1;
    
    // This is the value that will be passed to the DUT's P_CHAIN_FINAL_OUT_FRAMES parameter.
    // It represents the number of frames after Conv3 (and thus for ReLU3).
    localparam int FINAL_OUT_FRAMES_TO_PASS = C3_OUT_FR_CALC_TB;
    localparam int FINAL_OUT_CHANNELS_CHAIN = C3_OUT_CH_TB; // ReLU3 does not change channel count from C3


    // Testbench signals
    logic clk;
    logic rst_n;
    logic i_top_start_tb; 
    logic signed [DATA_WIDTH-1:0] i_z_tb [0:LATENT_DIM-1];
    logic o_top_busy_tb;
    logic o_top_done_tick_tb;
    logic signed [DATA_WIDTH-1:0] o_chain_result_tb [0:FINAL_OUT_CHANNELS_CHAIN-1][0:FINAL_OUT_FRAMES_TO_PASS-1];

    // Instantiate the DUT
    full_chain_stage4 #(
        .DATA_WIDTH(DATA_WIDTH), .FRACTIONAL_BITS(FRACTIONAL_BITS), .LATENT_DIM(LATENT_DIM),
        .FC_RELU_OUT_CH(FC_RELU_OUT_CH), .FC_RELU_OUT_FR(FC_RELU_OUT_FR),
        .UP0_SCALE_FACTOR(UP0_SCALE_FACTOR),
        .C1_OUT_CH(C1_OUT_CH), .C1_K(C1_K), .C1_P(C1_P), .C1_S(C1_S),
        .UP1_SCALE_FACTOR(UP1_SCALE_FACTOR),
        .C2_OUT_CH(C2_OUT_CH), .C2_K(C2_K), .C2_P(C2_P), .C2_S(C2_S),
        .UP2_SCALE_FACTOR(UP2_SCALE_FACTOR),
        .C3_OUT_CH(C3_OUT_CH_TB), .C3_K(C3_K_TB), .C3_P(C3_P_TB), .C3_S(C3_S_TB),
        .P_CHAIN_FINAL_OUT_FRAMES(FINAL_OUT_FRAMES_TO_PASS) 
    ) dut (
        .clk(clk), .rst_n(rst_n), .i_top_start(i_top_start_tb), .i_z_top(i_z_tb),
        .o_top_busy(o_top_busy_tb), .o_top_done_tick(o_top_done_tick_tb), .o_chain_result(o_chain_result_tb)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Expected output after final ReLU3
    localparam logic signed [DATA_WIDTH-1:0] input_to_c3_frame0_tb = 16'sd428; 

    localparam logic signed [31:0] acc_c3_ch0_fr0_tb = (input_to_c3_frame0_tb * 16'sd205 + ROUND_CONST_TB) >>> FRACTIONAL_BITS;
    localparam logic signed [DATA_WIDTH-1:0] conv3_out_0_0_tb = acc_c3_ch0_fr0_tb + 16'sd20; // Expected 363
    
    localparam logic signed [31:0] acc_c3_ch1_fr0_tb = (input_to_c3_frame0_tb * 16'sd230 + ROUND_CONST_TB) >>> FRACTIONAL_BITS;
    localparam logic signed [DATA_WIDTH-1:0] conv3_out_1_0_tb = acc_c3_ch1_fr0_tb + 16'sd23; // Expected 408

    // Apply ReLU to the expected conv3 outputs
    localparam logic signed [DATA_WIDTH-1:0] expected_final_0_0 = (conv3_out_0_0_tb < 0) ? 16'sd0 : conv3_out_0_0_tb;
    localparam logic signed [DATA_WIDTH-1:0] expected_final_1_0 = (conv3_out_1_0_tb < 0) ? 16'sd0 : conv3_out_1_0_tb;

    
    initial begin
        int cycles_waited;
        $display("Starting Testbench for full_chain_stage4 with final ReLU3 layer...");
        $display("TB: FINAL_OUT_FRAMES_TO_PASS = %0d", FINAL_OUT_FRAMES_TO_PASS);
        $display("TB: FINAL_OUT_CHANNELS_CHAIN = %0d", FINAL_OUT_CHANNELS_CHAIN);
        $display("TB: Conv3 output [0][0] before ReLU3 expected: %d", conv3_out_0_0_tb);
        $display("TB: Conv3 output [1][0] before ReLU3 expected: %d", conv3_out_1_0_tb);
        $display("TB: Expected final o_chain_result_tb[0][0] (after ReLU3) = %d (0x%h)", expected_final_0_0, expected_final_0_0); 
        $display("TB: Expected final o_chain_result_tb[1][0] (after ReLU3) = %d (0x%h)", expected_final_1_0, expected_final_1_0); 

        rst_n = 1'b0;
        i_top_start_tb = 1'b0;
        i_z_tb[0] = 16'sd26; i_z_tb[1] = 16'sd128; i_z_tb[2] = 16'sd51; i_z_tb[3] = 16'sd154;

        repeat(2) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        $display("[%0t] Reset released. i_z = {%d,%d,%d,%d}", $time, i_z_tb[0],i_z_tb[1],i_z_tb[2],i_z_tb[3]);

        $display("[%0t] Applying input and starting chain computation...", $time);
        i_top_start_tb = 1'b1;
        @(posedge clk);
        i_top_start_tb = 1'b0;

        cycles_waited = 0;
        // Add 1-2 cycles for ReLU3 and FSM state
        while (o_top_done_tick_tb !== 1'b1 && cycles_waited < 125) begin 
            @(posedge clk);
            cycles_waited++;
        end

        if (o_top_done_tick_tb === 1'b1) begin
            $display("[%0t] Chain computation done in %0d cycles. o_top_done_tick_tb received. o_top_busy_tb: %b", $time, cycles_waited, o_top_busy_tb);
            #1ps; 

            if (FINAL_OUT_CHANNELS_CHAIN > 0 && FINAL_OUT_FRAMES_TO_PASS > 0) begin
                if (o_chain_result_tb[0][0] == expected_final_0_0) begin
                    $display("[%0t] SPOT CHECK PASSED for output[0][0]: Got %d, Expected %d",
                             $time, o_chain_result_tb[0][0], expected_final_0_0);
                end else begin
                    $error("[%0t] SPOT CHECK FAILED for output[0][0]: Got %d (0x%0h), Expected %d (0x%0h)",
                            $time, o_chain_result_tb[0][0], o_chain_result_tb[0][0], 
                            expected_final_0_0, expected_final_0_0);
                end
            end

            if (FINAL_OUT_CHANNELS_CHAIN > 1 && FINAL_OUT_FRAMES_TO_PASS > 0) begin
                 if (o_chain_result_tb[1][0] == expected_final_1_0) begin
                    $display("[%0t] SPOT CHECK PASSED for output[1][0]: Got %d, Expected %d",
                             $time, o_chain_result_tb[1][0], expected_final_1_0);
                end else begin
                    $error("[%0t] SPOT CHECK FAILED for output[1][0]: Got %d (0x%0h), Expected %d (0x%0h)",
                            $time, o_chain_result_tb[1][0], o_chain_result_tb[1][0], 
                            expected_final_1_0, expected_final_1_0);
                end
            end

            for (int ch = 0; ch < FINAL_OUT_CHANNELS_CHAIN; ch = ch + 1) begin
                string s;
                s = $sformatf("[%0t] Full output[%0d]: Got={", $time, ch);
                for(int fr=0; fr<FINAL_OUT_FRAMES_TO_PASS; fr++) begin
                    s = $sformatf("%s%d",s, o_chain_result_tb[ch][fr]);
                    if (fr < FINAL_OUT_FRAMES_TO_PASS-1) s = $sformatf("%s, ",s);
                end
                s = $sformatf("%s}",s);
                $display("%s",s);
            end

        end else begin
            $error("[%0t] TIMEOUT: o_top_done_tick_tb not received after %0d cycles. o_top_busy_tb: %b", $time, cycles_waited, o_top_busy_tb);
            $display("[%0t] TEST FAILED (Timeout)!", $time);
        end

        #(CLK_PERIOD * 5);
        $finish;
    end
endmodule
