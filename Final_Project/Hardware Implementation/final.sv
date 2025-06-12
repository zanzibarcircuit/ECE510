// Timescale directive
`timescale 1ns/1ps

// ============================================================================
// Combined fc_with_relu_layer Module (Working - Original)
// ============================================================================
module fc_with_relu_layer #(
    parameter int DATA_WIDTH = 16,
    parameter int FRACTIONAL_BITS = 8,
    parameter int LATENT_DIM_FC = 4,
    parameter int NUM_OUT_CHANNELS_FC = 4,
    parameter int NUM_OUT_FRAMES_FC = 1
) (
    input wire clk,
    input wire rst_n,
    input wire i_start,
    input wire signed [DATA_WIDTH-1:0] i_z [0:LATENT_DIM_FC-1],
    output logic o_busy,
    output logic o_done_tick,
    output logic signed [DATA_WIDTH-1:0] o_fc_relu_result [0:NUM_OUT_CHANNELS_FC-1][0:NUM_OUT_FRAMES_FC-1]
);
    // Weights for the fully connected layer
    localparam logic signed [DATA_WIDTH-1:0] WEIGHTS_FC [0:NUM_OUT_CHANNELS_FC-1][0:LATENT_DIM_FC-1] = '{
        '{ 16'sd26,  16'sd51,  16'sd77, 16'sd102 },
        '{ 16'sd128, 16'sd154, 16'sd179, 16'sd205 },
        '{ 16'sd51,  16'sd102, 16'sd154, 16'sd205 },
        '{ 16'sd26,  16'sd77,  16'sd128, 16'sd179 }
    };
    // Biases for the fully connected layer
    localparam logic signed [DATA_WIDTH-1:0] BIAS_FC [0:NUM_OUT_CHANNELS_FC-1] =
        '{ 16'sd3, 16'sd5, 16'sd8, 16'sd10 };
    // Saturation values for 16-bit signed data
    localparam logic signed [DATA_WIDTH-1:0] S16_MAX_VAL = (1<<(DATA_WIDTH-1))-1;
    localparam logic signed [DATA_WIDTH-1:0] S16_MIN_VAL = -(1<<(DATA_WIDTH-1));
    // Rounding constant for fixed-point arithmetic
    localparam logic signed [31:0] ROUND_CONST = (FRACTIONAL_BITS > 0) ? (1 << (FRACTIONAL_BITS - 1)) : 0;

    logic signed [DATA_WIDTH-1:0] temp_combined_result_comb [0:NUM_OUT_CHANNELS_FC-1];

    typedef enum logic [0:0] { IDLE, COMPUTE } state_t;
    state_t current_state, next_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) current_state <= IDLE;
        else current_state <= next_state;
    end

    always_comb begin
        next_state = current_state;
        o_done_tick = 1'b0;
        case (current_state)
            IDLE: if (i_start) next_state = COMPUTE;
            COMPUTE: begin
                o_done_tick = 1'b1;
                next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end

    assign o_busy = (current_state == COMPUTE);

    always_comb begin
        logic signed [DATA_WIDTH-1:0] fc_intermediate_val;
        logic signed [31:0] acc;
        logic signed [31:0] prod;

        for (int i = 0; i < NUM_OUT_CHANNELS_FC; i = i + 1) begin
            temp_combined_result_comb[i] = o_fc_relu_result[i][0];
        end

        if (current_state == COMPUTE) begin
            for (int i = 0; i < NUM_OUT_CHANNELS_FC; i = i + 1) begin
                acc = 32'sd0;
                for (int j = 0; j < LATENT_DIM_FC; j = j + 1) begin
                    prod = i_z[j] * WEIGHTS_FC[i][j];
                    acc += (prod + ROUND_CONST) >>> FRACTIONAL_BITS;
                end
                acc += BIAS_FC[i];

                if (acc > S16_MAX_VAL) fc_intermediate_val = S16_MAX_VAL;
                else if (acc < S16_MIN_VAL) fc_intermediate_val = S16_MIN_VAL;
                else fc_intermediate_val = acc[DATA_WIDTH-1:0];

                if (fc_intermediate_val < 16'sd0) temp_combined_result_comb[i] = 16'sd0;
                else temp_combined_result_comb[i] = fc_intermediate_val;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i_ff = 0; i_ff < NUM_OUT_CHANNELS_FC; i_ff = i_ff + 1) begin
                o_fc_relu_result[i_ff][0] <= 16'sd0;
            end
        end else if (o_done_tick) begin
            for (int i_ff = 0; i_ff < NUM_OUT_CHANNELS_FC; i_ff = i_ff + 1) begin
                o_fc_relu_result[i_ff][0] <= temp_combined_result_comb[i_ff];
            end
        end
    end
endmodule

// ============================================================================
// upsample_module (Corrected for SV-IRTAV error)
// Nearest Neighbor Upsampling
// ============================================================================
module upsample_module #(
    parameter int NUM_CHANNELS = 4,            // Number of input/output channels
    parameter int FRAMES_PER_CHANNEL_IN = 1,   // Number of frames per input channel
    parameter int SCALE_FACTOR = 2,            // Upsampling scale factor
    parameter int DATA_WIDTH = 16              // Data width of inputs and outputs
) (
    input wire clk,
    input wire rst_n,
    input wire i_start,     // Start signal for the module
    input wire signed [DATA_WIDTH-1:0] i_data [0:NUM_CHANNELS-1][0:FRAMES_PER_CHANNEL_IN-1], // Input data
    output logic o_done_tick, // Signal indicating computation is done for one cycle
    output logic signed [DATA_WIDTH-1:0] o_result [0:NUM_CHANNELS-1][0:(FRAMES_PER_CHANNEL_IN * SCALE_FACTOR)-1] // Upsampled output data
);
    // Calculate the number of frames per output channel
    localparam int FRAMES_PER_CHANNEL_OUT = FRAMES_PER_CHANNEL_IN * SCALE_FACTOR;

    // Temporary storage for the combinational result before registering
    logic signed [DATA_WIDTH-1:0] temp_result_comb [0:NUM_CHANNELS-1][0:FRAMES_PER_CHANNEL_OUT-1];

    // State machine definition
    typedef enum logic [0:0] {
        IDLE,          // Waiting for start signal
        UPSAMPLE_DATA  // Performing upsampling
    } state_t;
    state_t current_state, next_state;

    // State register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    // Next state logic and o_done_tick generation
    always_comb begin
        next_state = current_state;
        o_done_tick = 1'b0;
        case (current_state)
            IDLE: begin
                if (i_start) begin
                    next_state = UPSAMPLE_DATA;
                end
            end
            UPSAMPLE_DATA: begin
                o_done_tick = 1'b1; // Upsampling finishes in one cycle
                next_state = IDLE;
            end
            default: begin
                next_state = IDLE;
            end
        endcase
    end

    // Combinational logic for nearest neighbor upsampling
    always_comb begin
        // Declare loop variables here with static lifetime for combinational block
        integer ch;
        integer out_fr;
        integer in_fr_idx; 

        // Iterate over each channel
        for (ch = 0; ch < NUM_CHANNELS; ch = ch + 1) begin
            // Iterate over each output frame for the current channel
            for (out_fr = 0; out_fr < FRAMES_PER_CHANNEL_OUT; out_fr = out_fr + 1) begin
                // Calculate the corresponding input frame index (integer division for nearest neighbor)
                in_fr_idx = out_fr / SCALE_FACTOR;
                // Assign the input data to the temporary result (replication for upsampling)
                // Bounds checks are implicitly handled by loop conditions and parameter calculations
                // assuming parameters are valid (e.g. SCALE_FACTOR > 0)
                temp_result_comb[ch][out_fr] = i_data[ch][in_fr_idx];
            end
        end
    end

    // Output register: Store the upsampled result
    always_ff @(posedge clk or negedge rst_n) begin
        integer ch_reg;     // Using integer for broader compatibility in sequential blocks
        integer out_fr_reg; 

        if (!rst_n) begin
            // Reset output to 0
            for (ch_reg=0; ch_reg<NUM_CHANNELS; ch_reg=ch_reg+1) begin
                for (out_fr_reg=0; out_fr_reg<FRAMES_PER_CHANNEL_OUT; out_fr_reg=out_fr_reg+1) begin
                    o_result[ch_reg][out_fr_reg] <= {DATA_WIDTH{1'b0}};
                end
            end
        end else if (o_done_tick) begin // When upsampling is done for the current input
            // Register the computed upsampled result
            for (ch_reg=0; ch_reg<NUM_CHANNELS; ch_reg=ch_reg+1) begin
                for (out_fr_reg=0; out_fr_reg<FRAMES_PER_CHANNEL_OUT; out_fr_reg=out_fr_reg+1) begin
                    o_result[ch_reg][out_fr_reg] <= temp_result_comb[ch_reg][out_fr_reg];
                end
            end
        end
    end
endmodule

// ============================================================================
// conv1_module (FULLY PARALLELIZED VERSION)
// ============================================================================
module conv1_module #(
    parameter int DATA_WIDTH = 16,
    parameter int FRACTIONAL_BITS = 8,
    parameter int NUM_IN_CHANNELS  = 4,
    parameter int NUM_OUT_CHANNELS = 2,
    parameter int KERNEL_SIZE      = 3,
    parameter int PADDING          = 1,
    parameter int STRIDE           = 1,
    parameter int NUM_IN_FRAMES    = 2,
    parameter int P_NUM_OUT_FRAMES = ( (NUM_IN_FRAMES + 2 * PADDING) - KERNEL_SIZE) / STRIDE + 1
) (
    input wire clk,
    input wire rst_n,
    input wire i_start,
    input wire signed [DATA_WIDTH-1:0] i_data [0:NUM_IN_CHANNELS-1][0:NUM_IN_FRAMES-1],
    output logic signed [DATA_WIDTH-1:0] o_result [0:NUM_OUT_CHANNELS-1][0:P_NUM_OUT_FRAMES-1],
    output logic o_busy,
    output logic o_done_tick
);
    localparam int NUM_IN_FRAMES_PADDED = NUM_IN_FRAMES + 2 * PADDING;
    localparam int NUM_OUT_FRAMES_INTERNAL = P_NUM_OUT_FRAMES; // Should match P_NUM_OUT_FRAMES

    localparam logic signed [DATA_WIDTH-1:0] S16_MAX_VAL = (1<<(DATA_WIDTH-1))-1;
    localparam logic signed [DATA_WIDTH-1:0] S16_MIN_VAL = -(1<<(DATA_WIDTH-1));
    localparam logic signed [31:0] ROUND_CONST = (FRACTIONAL_BITS > 0) ? (1<<(FRACTIONAL_BITS-1)) : 0;

    localparam logic signed [DATA_WIDTH-1:0] KERNELS [0:NUM_OUT_CHANNELS-1][0:NUM_IN_CHANNELS-1][0:KERNEL_SIZE-1] = '{
        '{  '{16'sd26,16'sd51,16'sd26}, '{16'sd77,16'sd26,16'sd51}, '{16'sd51,16'sd77,16'sd26}, '{16'sd26,16'sd26,16'sd77} },
        '{  '{16'sd102,16'sd51,16'sd26}, '{16'sd26,16'sd77,16'sd102}, '{16'sd77,16'sd51,16'sd51}, '{16'sd51,16'sd102,16'sd26} }
    };
    localparam logic signed [DATA_WIDTH-1:0] BIASES [0:NUM_OUT_CHANNELS-1] = '{ 16'sd13, 16'sd15 };

    logic signed [DATA_WIDTH-1:0] padded_input_data [0:NUM_IN_CHANNELS-1][0:NUM_IN_FRAMES_PADDED-1];
    logic signed [DATA_WIDTH-1:0] temp_o_result_comb [0:NUM_OUT_CHANNELS-1][0:NUM_OUT_FRAMES_INTERNAL-1];

    typedef enum logic [0:0] { S_IDLE, S_COMPUTE } state_t; // Simplified state machine
    state_t current_state, next_state;

    initial begin
        if (NUM_OUT_FRAMES_INTERNAL <= 0) begin
            $error("conv1_module: NUM_OUT_FRAMES_INTERNAL must be positive.");
            $finish;
        end
        if (P_NUM_OUT_FRAMES != NUM_OUT_FRAMES_INTERNAL) begin
             $error("conv1_module: P_NUM_OUT_FRAMES (%0d) must match NUM_OUT_FRAMES_INTERNAL (%0d).", P_NUM_OUT_FRAMES, NUM_OUT_FRAMES_INTERNAL);
             $finish;
         end
    end

    // Combinational logic for padding (remains the same)
    always_comb begin
        for(int ic_pad=0; ic_pad<NUM_IN_CHANNELS; ic_pad=ic_pad+1) begin
            for(int f_pad=0; f_pad<NUM_IN_FRAMES_PADDED; f_pad=f_pad+1) begin
                if(f_pad<PADDING || f_pad>=(NUM_IN_FRAMES+PADDING)) begin
                    padded_input_data[ic_pad][f_pad]=16'sd0;
                end else begin
                    padded_input_data[ic_pad][f_pad]=i_data[ic_pad][f_pad-PADDING];
                end
            end
        end
    end

    // State register
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) current_state <= S_IDLE;
        else current_state <= next_state;
    end

    // Next state logic and control signals (o_busy, o_done_tick)
    always_comb begin
        next_state = current_state;
        o_done_tick = 1'b0;
        o_busy = 1'b0; // Default to not busy

        case(current_state)
            S_IDLE: begin
                if(i_start) next_state = S_COMPUTE;
            end
            S_COMPUTE: begin
                o_busy = 1'b1;      // Busy during computation
                o_done_tick = 1'b1; // Computation is done in this cycle
                next_state = S_IDLE;  // Go back to IDLE
            end
            default: begin
                next_state = S_IDLE;
            end
        endcase
    end

    // Fully parallel computation logic
    always_comb begin
        for (int oc = 0; oc < NUM_OUT_CHANNELS; oc = oc + 1) begin
            for (int of = 0; of < NUM_OUT_FRAMES_INTERNAL; of = of + 1) begin
                logic signed[31:0] acc_mac_local; // Accumulator for this specific (oc, of)
                logic [31:0] rfs_m_local_calc;
                logic [31:0] ifi_m_local_calc;

                acc_mac_local = 32'sd0;
                for(int ic_m = 0; ic_m < NUM_IN_CHANNELS; ic_m = ic_m + 1) begin
                    for(int k_m = 0; k_m < KERNEL_SIZE; k_m = k_m + 1) begin
                        rfs_m_local_calc = of * STRIDE; // Use 'of' from outer loop
                        ifi_m_local_calc = rfs_m_local_calc + k_m;

                        if (ifi_m_local_calc >= 0 && ifi_m_local_calc < NUM_IN_FRAMES_PADDED) begin
                            logic signed[31:0] prod_mac_local;
                            logic signed[31:0] scaled_prod_mac_local;

                            prod_mac_local = padded_input_data[ic_m][ifi_m_local_calc] * KERNELS[oc][ic_m][k_m]; // Use 'oc' from outer loop
                            scaled_prod_mac_local = (prod_mac_local + ROUND_CONST) >>> FRACTIONAL_BITS;
                            acc_mac_local += scaled_prod_mac_local;
                        end
                    end
                end
                acc_mac_local += BIASES[oc]; // Add bias, use 'oc' from outer loop

                // Saturate and assign to the temporary result for this (oc, of)
                if(acc_mac_local > S16_MAX_VAL) temp_o_result_comb[oc][of] = S16_MAX_VAL;
                else if(acc_mac_local < S16_MIN_VAL) temp_o_result_comb[oc][of] = S16_MIN_VAL;
                else temp_o_result_comb[oc][of] = acc_mac_local[DATA_WIDTH-1:0];
            end
        end
    end

    // Output register: Store the computed result
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            for(int ocl_ff=0; ocl_ff<NUM_OUT_CHANNELS; ocl_ff=ocl_ff+1)begin
                if (NUM_OUT_FRAMES_INTERNAL > 0) begin // Check to prevent empty loop range
                    for(int ofl_ff=0; ofl_ff<NUM_OUT_FRAMES_INTERNAL; ofl_ff=ofl_ff+1)begin
                        o_result[ocl_ff][ofl_ff] <= {DATA_WIDTH{1'b0}};
                    end
                end
            end
        end else if (o_done_tick) begin // When computation for the current input is done
            // Register the entire computed result in parallel
            for(int ocl_ff = 0; ocl_ff < NUM_OUT_CHANNELS; ocl_ff = ocl_ff + 1) begin
                if (NUM_OUT_FRAMES_INTERNAL > 0) begin
                    for(int ofl_ff = 0; ofl_ff < NUM_OUT_FRAMES_INTERNAL; ofl_ff = ofl_ff + 1) begin
                        o_result[ocl_ff][ofl_ff] <= temp_o_result_comb[ocl_ff][ofl_ff];
                    end
                end
            end
        end
    end
endmodule

// ============================================================================
// relu_module (Standard Version - Working - Original)
// ============================================================================
module relu_module #(
    parameter int NUM_CHANNELS = 4,
    parameter int FRAMES_PER_CHANNEL = 1,
    parameter int DATA_WIDTH = 16
) (
    input wire clk,
    input wire rst_n,
    input wire i_start,
    input wire signed [DATA_WIDTH-1:0] i_data [0:NUM_CHANNELS-1][0:FRAMES_PER_CHANNEL-1],
    output logic o_done_tick,
    output logic signed [DATA_WIDTH-1:0] o_result [0:NUM_CHANNELS-1][0:FRAMES_PER_CHANNEL-1]
);
    logic signed [DATA_WIDTH-1:0] temp_result_comb [0:NUM_CHANNELS-1][0:FRAMES_PER_CHANNEL-1];
    typedef enum logic [0:0] { IDLE, APPLY_RELU } state_t;
    state_t current_state, next_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) current_state <= IDLE;
        else current_state <= next_state;
    end

    always_comb begin
        next_state = current_state;
        o_done_tick = 1'b0;
        case (current_state)
            IDLE: if (i_start) next_state = APPLY_RELU;
            APPLY_RELU: begin
                o_done_tick = 1'b1;
                next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end

    always_comb begin
        for (int ch = 0; ch < NUM_CHANNELS; ch = ch + 1) begin
            for (int fr = 0; fr < FRAMES_PER_CHANNEL; fr = fr + 1) begin
                temp_result_comb[ch][fr] = (i_data[ch][fr] < 16'sd0) ? 16'sd0 : i_data[ch][fr];
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int ch_reg=0; ch_reg<NUM_CHANNELS; ch_reg=ch_reg+1) begin
                for (int fr_reg=0; fr_reg<FRAMES_PER_CHANNEL; fr_reg=fr_reg+1) begin
                    o_result[ch_reg][fr_reg] <= {DATA_WIDTH{1'b0}};
                end
            end
        end else if (o_done_tick) begin
            for (int ch_reg=0; ch_reg<NUM_CHANNELS; ch_reg=ch_reg+1) begin
                for (int fr_reg=0; fr_reg<FRAMES_PER_CHANNEL; fr_reg=fr_reg+1) begin
                    o_result[ch_reg][fr_reg] <= temp_result_comb[ch_reg][fr_reg];
                end
            end
        end
    end
endmodule

// ============================================================================
// conv2_module (FULLY PARALLELIZED VERSION - WITH SYNTAX CORRECTION)
// ============================================================================
module conv2_module #(
    parameter int DATA_WIDTH = 16,
    parameter int FRACTIONAL_BITS = 8,
    parameter int NUM_IN_CHANNELS  = 2,
    parameter int NUM_OUT_CHANNELS = 1,
    parameter int KERNEL_SIZE      = 3,
    parameter int PADDING          = 1,
    parameter int STRIDE           = 1,
    parameter int NUM_IN_FRAMES    = 4,
    parameter int P_NUM_OUT_FRAMES = ((NUM_IN_FRAMES + 2 * PADDING) - KERNEL_SIZE) / STRIDE + 1
) (
    input wire clk, rst_n, i_start,
    input wire signed [DATA_WIDTH-1:0] i_data [0:NUM_IN_CHANNELS-1][0:NUM_IN_FRAMES-1],
    output logic signed [DATA_WIDTH-1:0] o_result [0:NUM_OUT_CHANNELS-1][0:P_NUM_OUT_FRAMES-1],
    output logic o_busy, o_done_tick
);
    localparam int NUM_IN_FRAMES_PADDED = NUM_IN_FRAMES + 2 * PADDING;
    localparam int NUM_OUT_FRAMES_INTERNAL = P_NUM_OUT_FRAMES;
    localparam logic signed [DATA_WIDTH-1:0] S16_MAX_VAL = (1<<(DATA_WIDTH-1))-1;
    localparam logic signed [DATA_WIDTH-1:0] S16_MIN_VAL = -(1<<(DATA_WIDTH-1));
    localparam logic signed [31:0] ROUND_CONST = (FRACTIONAL_BITS > 0) ? (1<<(FRACTIONAL_BITS-1)) : 0;

    localparam logic signed [DATA_WIDTH-1:0] KERNELS [0:NUM_OUT_CHANNELS-1][0:NUM_IN_CHANNELS-1][0:KERNEL_SIZE-1] =
    '{ '{ {16'sd128,16'sd26,16'sd51}, {16'sd51,16'sd77,16'sd128} } };
    localparam logic signed [DATA_WIDTH-1:0] BIASES [0:NUM_OUT_CHANNELS-1] = '{ 16'sd18 };

    logic signed [DATA_WIDTH-1:0] padded_input_data [0:NUM_IN_CHANNELS-1][0:NUM_IN_FRAMES_PADDED-1];
    logic signed [DATA_WIDTH-1:0] temp_o_result_comb [0:NUM_OUT_CHANNELS-1][0:NUM_OUT_FRAMES_INTERNAL-1];

    typedef enum logic [0:0] { S_IDLE, S_COMPUTE } state_t;
    state_t current_state, next_state;

    initial begin
        if (NUM_OUT_FRAMES_INTERNAL <= 0) begin
            $error("conv2_module: NUM_OUT_FRAMES_INTERNAL must be positive.");
            $finish;
        end
    end

    always_comb begin // For padded_input_data
        for(int ic_pad=0;ic_pad<NUM_IN_CHANNELS;ic_pad=ic_pad+1) begin
            for(int f_pad=0;f_pad<NUM_IN_FRAMES_PADDED;f_pad=f_pad+1) begin
                if(f_pad<PADDING||f_pad>=(NUM_IN_FRAMES+PADDING)) begin
                    padded_input_data[ic_pad][f_pad]=16'sd0;
                end else begin
                    padded_input_data[ic_pad][f_pad]=i_data[ic_pad][f_pad-PADDING];
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) current_state <= S_IDLE;
        else current_state <= next_state;
    end

    always_comb begin // For FSM
        next_state = current_state;
        o_done_tick = 1'b0;
        o_busy = 1'b0;
        case(current_state)
            S_IDLE: if(i_start) next_state = S_COMPUTE;
            S_COMPUTE: begin
                o_busy = 1'b1;
                o_done_tick = 1'b1;
                next_state = S_IDLE;
            end
            default: next_state = S_IDLE;
        endcase
    end

    always_comb begin // For temp_o_result_comb (parallel computation)
        for (int oc = 0; oc < NUM_OUT_CHANNELS; oc = oc + 1) begin
            for (int of = 0; of < NUM_OUT_FRAMES_INTERNAL; of = of + 1) begin
                logic signed[31:0] acc_mac_local; // Accumulator for this specific (oc, of)
                logic [31:0] rfs_m_local_calc; 
                logic [31:0] ifi_m_local_calc;

                acc_mac_local = 32'sd0;
                for(int ic_m = 0; ic_m < NUM_IN_CHANNELS; ic_m = ic_m + 1) begin
                    for(int k_m = 0; k_m < KERNEL_SIZE; k_m = k_m + 1) begin
                        rfs_m_local_calc = of * STRIDE;
                        ifi_m_local_calc = rfs_m_local_calc + k_m;

                        if (ifi_m_local_calc >= 0 && ifi_m_local_calc < NUM_IN_FRAMES_PADDED) begin
                            logic signed[31:0] prod_mac_local;      // Product for this specific MAC op
                            logic signed[31:0] scaled_prod_mac_local; // Scaled product

                            prod_mac_local = padded_input_data[ic_m][ifi_m_local_calc] * KERNELS[oc][ic_m][k_m];
                            scaled_prod_mac_local = (prod_mac_local + ROUND_CONST) >>> FRACTIONAL_BITS;
                            acc_mac_local += scaled_prod_mac_local;
                        end
                    end
                end
                acc_mac_local += BIASES[oc]; // Add bias

                // Saturate and assign to the temporary result for this (oc, of)
                if(acc_mac_local > S16_MAX_VAL) temp_o_result_comb[oc][of] = S16_MAX_VAL;
                else if(acc_mac_local < S16_MIN_VAL) temp_o_result_comb[oc][of] = S16_MIN_VAL;
                else temp_o_result_comb[oc][of] = acc_mac_local[DATA_WIDTH-1:0];
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin // For o_result
        if(!rst_n) begin
            for(int ocl_ff=0; ocl_ff<NUM_OUT_CHANNELS; ocl_ff=ocl_ff+1) begin
                if (NUM_OUT_FRAMES_INTERNAL > 0) begin
                    for(int ofl_ff=0; ofl_ff<NUM_OUT_FRAMES_INTERNAL; ofl_ff=ofl_ff+1) begin
                        o_result[ocl_ff][ofl_ff] <= {DATA_WIDTH{1'b0}};
                    end
                end
            end
        end else if (o_done_tick) begin
             for(int ocl_ff = 0; ocl_ff < NUM_OUT_CHANNELS; ocl_ff = ocl_ff + 1) begin
                if (NUM_OUT_FRAMES_INTERNAL > 0) begin
                    for(int ofl_ff = 0; ofl_ff < NUM_OUT_FRAMES_INTERNAL; ofl_ff = ofl_ff + 1) begin
                        o_result[ocl_ff][ofl_ff] <= temp_o_result_comb[ocl_ff][ofl_ff];
                    end
                end
            end
        end
    end
endmodule

// ============================================================================
// conv3_output_module (FULLY PARALLELIZED VERSION)
// ============================================================================
module conv3_output_module #(
    parameter int DATA_WIDTH = 16,
    parameter int FRACTIONAL_BITS = 8,
    parameter int NUM_IN_CHANNELS  = 1,
    parameter int NUM_OUT_CHANNELS = 2,
    parameter int KERNEL_SIZE      = 1,
    parameter int PADDING          = 0,
    parameter int STRIDE           = 1,
    parameter int NUM_IN_FRAMES    = 4,
    parameter int P_NUM_OUT_FRAMES = ((NUM_IN_FRAMES + 2 * PADDING) - KERNEL_SIZE) / STRIDE + 1
) (
    input wire clk, rst_n, i_start,
    input wire signed [DATA_WIDTH-1:0] i_data [0:NUM_IN_CHANNELS-1][0:NUM_IN_FRAMES-1],
    output logic signed [DATA_WIDTH-1:0] o_result [0:NUM_OUT_CHANNELS-1][0:P_NUM_OUT_FRAMES-1],
    output logic o_busy, o_done_tick
);
    localparam int NUM_IN_FRAMES_PADDED = NUM_IN_FRAMES + 2 * PADDING;
    localparam int NUM_OUT_FRAMES_INTERNAL = P_NUM_OUT_FRAMES; // Should match P_NUM_OUT_FRAMES
    localparam logic signed [DATA_WIDTH-1:0] S16_MAX_VAL = (1<<(DATA_WIDTH-1))-1;
    localparam logic signed [DATA_WIDTH-1:0] S16_MIN_VAL = -(1<<(DATA_WIDTH-1));
    localparam logic signed [31:0] ROUND_CONST = (FRACTIONAL_BITS > 0) ? (1<<(FRACTIONAL_BITS-1)) : 0;

    localparam logic signed [DATA_WIDTH-1:0] KERNELS [0:NUM_OUT_CHANNELS-1][0:NUM_IN_CHANNELS-1][0:KERNEL_SIZE-1] =
    '{ '{ '{16'sd205} }, '{ '{16'sd230} } }; // Example KERNELS for NUM_OUT_CHANNELS=2, NUM_IN_CHANNELS=1, KERNEL_SIZE=1
    localparam logic signed [DATA_WIDTH-1:0] BIASES [0:NUM_OUT_CHANNELS-1] = '{ 16'sd20, 16'sd23 }; // Example BIASES

    logic signed [DATA_WIDTH-1:0] padded_input_data [0:NUM_IN_CHANNELS-1][0:NUM_IN_FRAMES_PADDED-1];
    logic signed [DATA_WIDTH-1:0] temp_o_result_comb [0:NUM_OUT_CHANNELS-1][0:NUM_OUT_FRAMES_INTERNAL-1];

    typedef enum logic [0:0] { S_IDLE, S_COMPUTE } state_t; // Simplified state machine
    state_t current_state, next_state;

    initial begin
        if (NUM_OUT_FRAMES_INTERNAL <= 0) begin
            $error("conv3_output_module: NUM_OUT_FRAMES_INTERNAL must be positive.");
            $finish;
        end
         if (P_NUM_OUT_FRAMES != NUM_OUT_FRAMES_INTERNAL) begin
             $error("conv3_output_module: P_NUM_OUT_FRAMES (%0d) must match NUM_OUT_FRAMES_INTERNAL (%0d).", P_NUM_OUT_FRAMES, NUM_OUT_FRAMES_INTERNAL);
             $finish;
         end
        if (PADDING == 0 && NUM_IN_FRAMES_PADDED != NUM_IN_FRAMES) begin
             // This check might be overly strict if NUM_IN_FRAMES_PADDED is used correctly elsewhere,
             // but good for ensuring understanding of PADDING=0.
            $error("conv3_output_module: PADDING is 0, NUM_IN_FRAMES_PADDED (%0d) should equal NUM_IN_FRAMES (%0d).", NUM_IN_FRAMES_PADDED, NUM_IN_FRAMES);
            $finish;
        end
    end

    // Combinational logic for padding (remains the same)
    always_comb begin
        for(int ic_pad=0;ic_pad<NUM_IN_CHANNELS;ic_pad=ic_pad+1) begin
            for(int f_pad=0;f_pad<NUM_IN_FRAMES_PADDED;f_pad=f_pad+1) begin
                if(PADDING==0) begin
                    // When PADDING is 0, NUM_IN_FRAMES_PADDED should be equal to NUM_IN_FRAMES.
                    // The loop for f_pad should correctly access i_data.
                    if (f_pad < NUM_IN_FRAMES) begin // Ensure we only access valid i_data indices
                        padded_input_data[ic_pad][f_pad]=i_data[ic_pad][f_pad];
                    end else begin
                        // This case should ideally not be hit if NUM_IN_FRAMES_PADDED == NUM_IN_FRAMES when PADDING == 0.
                        // Assigning 0 for safety if dimensions were miscalculated.
                        padded_input_data[ic_pad][f_pad]=16'sd0;
                    end
                end else if(f_pad<PADDING||f_pad>=(NUM_IN_FRAMES+PADDING)) begin
                    padded_input_data[ic_pad][f_pad]=16'sd0; // Pad with zeros
                end else begin
                    padded_input_data[ic_pad][f_pad]=i_data[ic_pad][f_pad-PADDING];
                end
            end
        end
    end

    // State register
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) current_state <= S_IDLE;
        else current_state <= next_state;
    end

    // Next state logic and control signals (o_busy, o_done_tick)
    always_comb begin
        next_state = current_state;
        o_done_tick = 1'b0;
        o_busy = 1'b0; // Default to not busy

        case(current_state)
            S_IDLE: begin
                if(i_start) next_state = S_COMPUTE;
            end
            S_COMPUTE: begin
                o_busy = 1'b1;      // Busy during computation
                o_done_tick = 1'b1; // Computation is done in this cycle
                next_state = S_IDLE;  // Go back to IDLE
            end
            default: begin
                next_state = S_IDLE;
            end
        endcase
    end

    // Fully parallel computation logic
    always_comb begin
        for (int oc = 0; oc < NUM_OUT_CHANNELS; oc = oc + 1) begin
            for (int of = 0; of < NUM_OUT_FRAMES_INTERNAL; of = of + 1) begin
                logic signed[31:0] acc_mac_local; // Accumulator for this specific (oc, of)
                logic [31:0] rfs_m_local_calc;    // Renamed from rfs_m to avoid conflict if declared outside
                logic [31:0] ifi_m_local_calc;    // Renamed from ifi_m

                acc_mac_local = 32'sd0;
                for(int ic_m = 0; ic_m < NUM_IN_CHANNELS; ic_m = ic_m + 1) begin
                    for(int k_m = 0; k_m < KERNEL_SIZE; k_m = k_m + 1) begin
                        rfs_m_local_calc = of * STRIDE; // Use 'of' from outer loop
                        ifi_m_local_calc = rfs_m_local_calc + k_m;

                        if (ifi_m_local_calc >= 0 && ifi_m_local_calc < NUM_IN_FRAMES_PADDED) begin
                            logic signed[31:0] prod_mac_local;
                            logic signed[31:0] scaled_prod_mac_local;

                            prod_mac_local = padded_input_data[ic_m][ifi_m_local_calc] * KERNELS[oc][ic_m][k_m]; // Use 'oc' from outer loop
                            scaled_prod_mac_local = (prod_mac_local + ROUND_CONST) >>> FRACTIONAL_BITS;
                            acc_mac_local += scaled_prod_mac_local;
                        end
                    end
                end
                acc_mac_local += BIASES[oc]; // Add bias, use 'oc' from outer loop

                // Saturate and assign to the temporary result for this (oc, of)
                if(acc_mac_local > S16_MAX_VAL) temp_o_result_comb[oc][of] = S16_MAX_VAL;
                else if(acc_mac_local < S16_MIN_VAL) temp_o_result_comb[oc][of] = S16_MIN_VAL;
                else temp_o_result_comb[oc][of] = acc_mac_local[DATA_WIDTH-1:0];
            end
        end
    end

    // Output register: Store the computed result
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            for(int ocl_ff=0;ocl_ff<NUM_OUT_CHANNELS;ocl_ff=ocl_ff+1)begin
                if(NUM_OUT_FRAMES_INTERNAL > 0) begin // Check to prevent empty loop range during synthesis
                    for(int ofl_ff=0;ofl_ff<NUM_OUT_FRAMES_INTERNAL;ofl_ff=ofl_ff+1)begin
                        o_result[ocl_ff][ofl_ff]<={DATA_WIDTH{1'b0}};
                    end
                end
            end
        end else if (o_done_tick) begin // When computation for the current input is done
             // Register the entire computed result in parallel
            for(int ocl_ff = 0; ocl_ff < NUM_OUT_CHANNELS; ocl_ff = ocl_ff + 1) begin
                if (NUM_OUT_FRAMES_INTERNAL > 0) begin
                    for(int ofl_ff = 0; ofl_ff < NUM_OUT_FRAMES_INTERNAL; ofl_ff = ofl_ff + 1) begin
                        o_result[ocl_ff][ofl_ff] <= temp_o_result_comb[ocl_ff][ofl_ff];
                    end
                end
            end
        end
    end
endmodule

// ============================================================================
// Chain: fc_relu -> up0 -> conv1 -> relu1 -> up1 -> conv2 -> relu2 -> up2 -> conv3 -> relu3
// The full_chain_stage4 module does not need to change as its FSM waits for done signals.
// The instantiation of conv3_output_module also remains the same.
// Only the internal implementation of conv3_output_module has changed.
// ============================================================================
// ... (rest of your full_chain_stage4 and other modules remain the same)


// ============================================================================
// Chain: fc_relu -> up0 -> conv1 -> relu1 -> up1 -> conv2 -> relu2 -> up2 -> conv3 -> relu3
// ============================================================================
module full_chain_stage4 #(
    parameter int DATA_WIDTH = 16,
    parameter int FRACTIONAL_BITS = 8,
    parameter int LATENT_DIM = 4,
    parameter int FC_RELU_OUT_CH = 4,
    parameter int FC_RELU_OUT_FR = 1,
    parameter int UP0_SCALE_FACTOR = 2,
    parameter int C1_OUT_CH = 2,
    parameter int C1_K = 3,
    parameter int C1_P = 1,
    parameter int C1_S = 1,
    parameter int UP1_SCALE_FACTOR = 2,
    parameter int C2_OUT_CH = 1,
    parameter int C2_K = 3,
    parameter int C2_P = 1,
    parameter int C2_S = 1,
    parameter int UP2_SCALE_FACTOR = 2,
    parameter int C3_OUT_CH = 2,
    parameter int C3_K = 1,
    parameter int C3_P = 0,
    parameter int C3_S = 1,
    parameter int P_CHAIN_FINAL_OUT_FRAMES = 8
) (
    input wire clk,
    input wire rst_n,
    input wire i_top_start,
    input wire signed [DATA_WIDTH-1:0] i_z_top [0:LATENT_DIM-1],
    output logic o_top_busy,
    output logic o_top_done_tick,
    output logic signed [DATA_WIDTH-1:0] o_chain_result
        [0 : C3_OUT_CH - 1]
        [0 : P_CHAIN_FINAL_OUT_FRAMES - 1]
);

    localparam int UP0_OUT_FR_calc = FC_RELU_OUT_FR * UP0_SCALE_FACTOR;
    localparam int C1_IN_CH_calc = FC_RELU_OUT_CH;
    localparam int C1_IN_FR_calc = UP0_OUT_FR_calc;
    localparam int C1_OUT_FR_calc = (((C1_IN_FR_calc + (2 * C1_P)) - C1_K) / C1_S) + 1;

    localparam int UP1_IN_CH_calc = C1_OUT_CH;
    localparam int UP1_IN_FR_calc = C1_OUT_FR_calc;
    localparam int UP1_OUT_FR_calc = UP1_IN_FR_calc * UP1_SCALE_FACTOR;

    localparam int C2_IN_CH_calc = UP1_IN_CH_calc;
    localparam int C2_IN_FR_calc = UP1_OUT_FR_calc;
    localparam int C2_OUT_FR_calc = (((C2_IN_FR_calc + (2 * C2_P)) - C2_K) / C2_S) + 1;

    localparam int RELU2_IN_CH_calc = C2_OUT_CH;
    localparam int RELU2_IN_FR_calc = C2_OUT_FR_calc;

    localparam int UP2_IN_CH_calc = RELU2_IN_CH_calc;
    localparam int UP2_IN_FR_calc = RELU2_IN_FR_calc;
    localparam int UP2_OUT_FR_calc = UP2_IN_FR_calc * UP2_SCALE_FACTOR;

    localparam int C3_IN_CH_calc = UP2_IN_CH_calc;
    localparam int C3_IN_FR_calc = UP2_OUT_FR_calc;
    localparam int C3_OUT_FR_INTERNAL_CALC = (((C3_IN_FR_calc + (2 * C3_P)) - C3_K) / C3_S) + 1;

    localparam int RELU3_IN_CH_calc = C3_OUT_CH;
    localparam int RELU3_IN_FR_calc = C3_OUT_FR_INTERNAL_CALC;

    initial begin
        if (P_CHAIN_FINAL_OUT_FRAMES != C3_OUT_FR_INTERNAL_CALC) begin
            $error("full_chain_stage4: Mismatch P_CHAIN_FINAL_OUT_FRAMES (%0d) != C3_OUT_FR_INTERNAL_CALC (%0d).",
                   P_CHAIN_FINAL_OUT_FRAMES, C3_OUT_FR_INTERNAL_CALC);
            $finish;
        end
        if (P_CHAIN_FINAL_OUT_FRAMES != RELU3_IN_FR_calc) begin
             $error("full_chain_stage4: Mismatch P_CHAIN_FINAL_OUT_FRAMES (%0d) != RELU3_IN_FR_calc (%0d).",
                   P_CHAIN_FINAL_OUT_FRAMES, RELU3_IN_FR_calc);
            $finish;
        end
    end

    logic fc_relu_done_sig, upsample0_done_sig, conv1_done_sig, relu1_done_sig;
    logic upsample1_done_sig, conv2_done_sig, relu2_done_sig, upsample2_done_sig;
    logic conv3_done_sig, relu3_done_sig;

    logic fc_relu_start_sig, upsample0_start_sig, conv1_start_sig, relu1_start_sig;
    logic upsample1_start_sig, conv2_start_sig, relu2_start_sig, upsample2_start_sig;
    logic conv3_start_sig, relu3_start_sig;

    logic signed [DATA_WIDTH-1:0] data_fc_relu_out   [0:FC_RELU_OUT_CH-1][0:FC_RELU_OUT_FR-1];
    logic signed [DATA_WIDTH-1:0] data_upsample0_out [0:C1_IN_CH_calc-1][0:C1_IN_FR_calc-1];
    logic signed [DATA_WIDTH-1:0] data_conv1_out     [0:C1_OUT_CH-1][0:C1_OUT_FR_calc-1];
    logic signed [DATA_WIDTH-1:0] data_relu1_out     [0:UP1_IN_CH_calc-1][0:UP1_IN_FR_calc-1];
    logic signed [DATA_WIDTH-1:0] data_upsample1_out [0:C2_IN_CH_calc-1][0:C2_IN_FR_calc-1];
    logic signed [DATA_WIDTH-1:0] data_conv2_out     [0:RELU2_IN_CH_calc-1][0:RELU2_IN_FR_calc-1];
    logic signed [DATA_WIDTH-1:0] data_relu2_out     [0:UP2_IN_CH_calc-1][0:UP2_IN_FR_calc-1];
    logic signed [DATA_WIDTH-1:0] data_upsample2_out [0:C3_IN_CH_calc-1][0:C3_IN_FR_calc-1];
    logic signed [DATA_WIDTH-1:0] data_conv3_out     [0:RELU3_IN_CH_calc-1][0:RELU3_IN_FR_calc-1];

    fc_with_relu_layer #(
        .DATA_WIDTH(DATA_WIDTH), .FRACTIONAL_BITS(FRACTIONAL_BITS), .LATENT_DIM_FC(LATENT_DIM),
        .NUM_OUT_CHANNELS_FC(FC_RELU_OUT_CH), .NUM_OUT_FRAMES_FC(FC_RELU_OUT_FR)
    ) fc_relu_inst (.clk, .rst_n, .i_start(fc_relu_start_sig), .i_z(i_z_top), .o_busy(), .o_done_tick(fc_relu_done_sig), .o_fc_relu_result(data_fc_relu_out));

    upsample_module #(
        .NUM_CHANNELS(FC_RELU_OUT_CH), .FRAMES_PER_CHANNEL_IN(FC_RELU_OUT_FR), .SCALE_FACTOR(UP0_SCALE_FACTOR), .DATA_WIDTH(DATA_WIDTH)
    ) upsample0_inst (.clk, .rst_n, .i_start(upsample0_start_sig), .i_data(data_fc_relu_out), .o_done_tick(upsample0_done_sig), .o_result(data_upsample0_out));

    conv1_module #( // Original sequential conv1_module
        .DATA_WIDTH(DATA_WIDTH), .FRACTIONAL_BITS(FRACTIONAL_BITS), .NUM_IN_CHANNELS(C1_IN_CH_calc), .NUM_OUT_CHANNELS(C1_OUT_CH),
        .KERNEL_SIZE(C1_K), .PADDING(C1_P), .STRIDE(C1_S), .NUM_IN_FRAMES(C1_IN_FR_calc), .P_NUM_OUT_FRAMES(C1_OUT_FR_calc)
    ) conv1_inst (.clk, .rst_n, .i_start(conv1_start_sig), .i_data(data_upsample0_out), .o_busy(), .o_done_tick(conv1_done_sig), .o_result(data_conv1_out));

    relu_module #( .NUM_CHANNELS(C1_OUT_CH), .FRAMES_PER_CHANNEL(C1_OUT_FR_calc), .DATA_WIDTH(DATA_WIDTH)
    ) relu1_inst (.clk, .rst_n, .i_start(relu1_start_sig), .i_data(data_conv1_out), .o_done_tick(relu1_done_sig), .o_result(data_relu1_out));

    upsample_module #(
        .NUM_CHANNELS(UP1_IN_CH_calc), .FRAMES_PER_CHANNEL_IN(UP1_IN_FR_calc), .SCALE_FACTOR(UP1_SCALE_FACTOR), .DATA_WIDTH(DATA_WIDTH)
    ) upsample1_inst (.clk, .rst_n, .i_start(upsample1_start_sig), .i_data(data_relu1_out), .o_done_tick(upsample1_done_sig), .o_result(data_upsample1_out));

    conv2_module #( // Fully parallel conv2_module
        .DATA_WIDTH(DATA_WIDTH), .FRACTIONAL_BITS(FRACTIONAL_BITS), .NUM_IN_CHANNELS(C2_IN_CH_calc), .NUM_OUT_CHANNELS(C2_OUT_CH),
        .KERNEL_SIZE(C2_K), .PADDING(C2_P), .STRIDE(C2_S), .NUM_IN_FRAMES(C2_IN_FR_calc), .P_NUM_OUT_FRAMES(C2_OUT_FR_calc)
    ) conv2_inst (.clk, .rst_n, .i_start(conv2_start_sig), .i_data(data_upsample1_out), .o_busy(), .o_done_tick(conv2_done_sig), .o_result(data_conv2_out));

    relu_module #( .NUM_CHANNELS(RELU2_IN_CH_calc), .FRAMES_PER_CHANNEL(RELU2_IN_FR_calc), .DATA_WIDTH(DATA_WIDTH)
    ) relu2_inst (.clk, .rst_n, .i_start(relu2_start_sig), .i_data(data_conv2_out), .o_done_tick(relu2_done_sig), .o_result(data_relu2_out));

    upsample_module #(
        .NUM_CHANNELS(UP2_IN_CH_calc), .FRAMES_PER_CHANNEL_IN(UP2_IN_FR_calc), .SCALE_FACTOR(UP2_SCALE_FACTOR), .DATA_WIDTH(DATA_WIDTH)
    ) upsample2_inst (.clk, .rst_n, .i_start(upsample2_start_sig), .i_data(data_relu2_out), .o_done_tick(upsample2_done_sig), .o_result(data_upsample2_out));

    conv3_output_module #( // Original sequential conv3_output_module
        .DATA_WIDTH(DATA_WIDTH), .FRACTIONAL_BITS(FRACTIONAL_BITS), .NUM_IN_CHANNELS(C3_IN_CH_calc), .NUM_OUT_CHANNELS(C3_OUT_CH),
        .KERNEL_SIZE(C3_K), .PADDING(C3_P), .STRIDE(C3_S), .NUM_IN_FRAMES(C3_IN_FR_calc), .P_NUM_OUT_FRAMES(P_CHAIN_FINAL_OUT_FRAMES)
    ) conv3_inst (.clk, .rst_n, .i_start(conv3_start_sig), .i_data(data_upsample2_out), .o_busy(), .o_done_tick(conv3_done_sig), .o_result(data_conv3_out));

    relu_module #( .NUM_CHANNELS(RELU3_IN_CH_calc), .FRAMES_PER_CHANNEL(RELU3_IN_FR_calc), .DATA_WIDTH(DATA_WIDTH)
    ) relu3_inst (.clk, .rst_n, .i_start(relu3_start_sig), .i_data(data_conv3_out), .o_done_tick(relu3_done_sig), .o_result(o_chain_result));

    typedef enum logic [4:0] {
        S_IDLE, S_FCR_START, S_FCR_WAIT, S_UP0_START, S_UP0_WAIT, S_C1_START,  S_C1_WAIT, S_RL1_START, S_RL1_WAIT,
        S_UP1_START, S_UP1_WAIT, S_C2_START,  S_C2_WAIT, S_RL2_START, S_RL2_WAIT, S_UP2_START, S_UP2_WAIT,
        S_C3_START,  S_C3_WAIT, S_RL3_START, S_RL3_WAIT, S_ALL_DONE
    } state_e;
    state_e current_fsm_state, next_fsm_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) current_fsm_state <= S_IDLE;
        else current_fsm_state <= next_fsm_state;
    end

    always_comb begin
        next_fsm_state = current_fsm_state;
        {fc_relu_start_sig, upsample0_start_sig, conv1_start_sig, relu1_start_sig, upsample1_start_sig, conv2_start_sig, relu2_start_sig, upsample2_start_sig, conv3_start_sig, relu3_start_sig} = '0;
        o_top_busy = 1'b1; o_top_done_tick = 1'b0;

        case (current_fsm_state)
            S_IDLE:      begin o_top_busy = 1'b0; if (i_top_start) next_fsm_state = S_FCR_START; end
            S_FCR_START: begin fc_relu_start_sig   = 1'b1; next_fsm_state = S_FCR_WAIT;  end
            S_FCR_WAIT:  if (fc_relu_done_sig)   next_fsm_state = S_UP0_START;
            S_UP0_START: begin upsample0_start_sig = 1'b1; next_fsm_state = S_UP0_WAIT;  end
            S_UP0_WAIT:  if (upsample0_done_sig) next_fsm_state = S_C1_START;
            S_C1_START:  begin conv1_start_sig     = 1'b1; next_fsm_state = S_C1_WAIT;   end
            S_C1_WAIT:   if (conv1_done_sig)     next_fsm_state = S_RL1_START;
            S_RL1_START: begin relu1_start_sig     = 1'b1; next_fsm_state = S_RL1_WAIT;  end
            S_RL1_WAIT:  if (relu1_done_sig)     next_fsm_state = S_UP1_START;
            S_UP1_START: begin upsample1_start_sig = 1'b1; next_fsm_state = S_UP1_WAIT;  end
            S_UP1_WAIT:  if (upsample1_done_sig) next_fsm_state = S_C2_START;
            S_C2_START:  begin conv2_start_sig     = 1'b1; next_fsm_state = S_C2_WAIT;   end
            S_C2_WAIT:   if (conv2_done_sig)     next_fsm_state = S_RL2_START; // This state will be much shorter
            S_RL2_START: begin relu2_start_sig     = 1'b1; next_fsm_state = S_RL2_WAIT;  end
            S_RL2_WAIT:  if (relu2_done_sig)     next_fsm_state = S_UP2_START;
            S_UP2_START: begin upsample2_start_sig = 1'b1; next_fsm_state = S_UP2_WAIT;  end
            S_UP2_WAIT:  if (upsample2_done_sig) next_fsm_state = S_C3_START;
            S_C3_START:  begin conv3_start_sig     = 1'b1; next_fsm_state = S_C3_WAIT;   end
            S_C3_WAIT:   if (conv3_done_sig)     next_fsm_state = S_RL3_START;
            S_RL3_START: begin relu3_start_sig     = 1'b1; next_fsm_state = S_RL3_WAIT;  end
            S_RL3_WAIT:  if (relu3_done_sig)     next_fsm_state = S_ALL_DONE;
            S_ALL_DONE:  begin o_top_done_tick = 1'b1; o_top_busy = 1'b0; next_fsm_state = S_IDLE; end
            default:     begin next_fsm_state = S_IDLE; o_top_busy = 1'b0; end
        endcase
        if (current_fsm_state == S_IDLE && !i_top_start) o_top_busy = 1'b0;
    end
endmodule