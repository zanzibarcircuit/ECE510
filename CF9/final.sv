`timescale 1ns/1ps

// ============================================================================
// Combined fc_with_relu_layer Module (Working)
// ============================================================================
module fc_with_relu_layer #(
    parameter int DATA_WIDTH = 16,
    parameter int FRACTIONAL_BITS = 8,
    parameter int LATENT_DIM_FC = 4,
    parameter int NUM_OUT_CHANNELS_FC = 4,
    parameter int NUM_OUT_FRAMES_FC = 1
) (
    input wire                           clk,
    input wire                           rst_n,
    input wire                           i_start,
    input wire signed [DATA_WIDTH-1:0]   i_z [0:LATENT_DIM_FC-1],
    output logic                         o_busy,
    output logic                         o_done_tick,
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
    localparam logic signed [DATA_WIDTH-1:0] S16_MAX_VAL = (1<<(DATA_WIDTH-1))-1; // 32767 for DATA_WIDTH=16
    localparam logic signed [DATA_WIDTH-1:0] S16_MIN_VAL = -(1<<(DATA_WIDTH-1)); // -32768 for DATA_WIDTH=16
    // Rounding constant for fixed-point arithmetic
    localparam logic signed [31:0] ROUND_CONST = (FRACTIONAL_BITS > 0) ? (1 << (FRACTIONAL_BITS - 1)) : 0;

    // Temporary storage for combinational result before registering
    logic signed [DATA_WIDTH-1:0] temp_combined_result_comb [0:NUM_OUT_CHANNELS_FC-1];

    // State machine definition
    typedef enum logic [0:0] {
        IDLE,    // Waiting for start signal
        COMPUTE  // Performing FC and ReLU computation
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
                    next_state = COMPUTE;
                end
            end
            COMPUTE: begin
                o_done_tick = 1'b1; // Computation finishes in one cycle after start
                next_state = IDLE;
            end
            default: begin
                next_state = IDLE;
            end
        endcase
    end

    // Busy signal generation
    assign o_busy = (current_state == COMPUTE);

    // Combinational logic for FC and ReLU
    always_comb begin
        int i; // Loop variable for output channels
        int j; // Loop variable for input latent dimensions
        logic signed [DATA_WIDTH-1:0] fc_intermediate_val; // Result after FC, before ReLU
        logic signed [31:0] acc;                           // Accumulator for MAC operations (wider to prevent overflow)
        logic signed [31:0] prod;                          // Product of weight and input (wider)

        // Initialize temporary result to current output (important for behavior when not in COMPUTE state)
        for (i = 0; i < NUM_OUT_CHANNELS_FC; i = i + 1) begin
            temp_combined_result_comb[i] = o_fc_relu_result[i][0];
        end

        if (current_state == COMPUTE) begin
            // Iterate over each output channel
            for (i = 0; i < NUM_OUT_CHANNELS_FC; i = i + 1) begin
                acc = 32'sd0; // Initialize accumulator for current output channel
                // Perform dot product (Multiply-Accumulate)
                for (j = 0; j < LATENT_DIM_FC; j = j + 1) begin
                    prod = i_z[j] * WEIGHTS_FC[i][j]; // Multiply input by weight
                    // Add rounding constant before shifting for fixed-point division
                    acc += (prod + ROUND_CONST) >>> FRACTIONAL_BITS;
                end
                acc += BIAS_FC[i]; // Add bias

                // Saturate the result to DATA_WIDTH
                if (acc > S16_MAX_VAL) begin
                    fc_intermediate_val = S16_MAX_VAL;
                end else if (acc < S16_MIN_VAL) begin
                    fc_intermediate_val = S16_MIN_VAL;
                end else begin
                    fc_intermediate_val = acc[DATA_WIDTH-1:0]; // Truncate to DATA_WIDTH
                end

                // Apply ReLU activation
                if (fc_intermediate_val < 16'sd0) begin
                    temp_combined_result_comb[i] = 16'sd0; // ReLU output is 0 for negative inputs
                end else begin
                    temp_combined_result_comb[i] = fc_intermediate_val; // ReLU output is input for non-negative inputs
                end
            end
        end
    end

    // Output register: Store the result of FC and ReLU
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset output to 0
            for (int i_ff = 0; i_ff < NUM_OUT_CHANNELS_FC; i_ff = i_ff + 1) begin
                // Assuming NUM_OUT_FRAMES_FC is always 1 for this specific FC layer
                o_fc_relu_result[i_ff][0] <= 16'sd0;
            end
        end else if (o_done_tick) begin // When computation is done
            // Register the computed result
            for (int i_ff = 0; i_ff < NUM_OUT_CHANNELS_FC; i_ff = i_ff + 1) begin 
                o_fc_relu_result[i_ff][0] <= temp_combined_result_comb[i_ff];
            end
        end
    end
endmodule

// ============================================================================
// upsample_module (Working)
// Nearest Neighbor Upsampling
// ============================================================================
module upsample_module #(
    parameter int NUM_CHANNELS = 4,            // Number of input/output channels
    parameter int FRAMES_PER_CHANNEL_IN = 1,   // Number of frames per input channel
    parameter int SCALE_FACTOR = 2,            // Upsampling scale factor
    parameter int DATA_WIDTH = 16              // Data width of inputs and outputs
) (
    input wire                           clk,
    input wire                           rst_n,
    input wire                           i_start,     // Start signal for the module
    input wire signed [DATA_WIDTH-1:0]   i_data [0:NUM_CHANNELS-1][0:FRAMES_PER_CHANNEL_IN-1], // Input data
    output logic                         o_done_tick, // Signal indicating computation is done for one cycle
    output logic signed [DATA_WIDTH-1:0] o_result [0:NUM_CHANNELS-1][0:(FRAMES_PER_CHANNEL_IN * SCALE_FACTOR)-1] // Upsampled output data
);
    // Calculate the number of frames per output channel
    localparam int FRAMES_PER_CHANNEL_OUT = FRAMES_PER_CHANNEL_IN * SCALE_FACTOR;

    // Temporary storage for the combinational result before registering
    logic signed [DATA_WIDTH-1:0] temp_result_comb [0:NUM_CHANNELS-1][0:FRAMES_PER_CHANNEL_OUT-1];

    // State machine definition
    typedef enum logic [0:0] {
        IDLE,           // Waiting for start signal
        UPSAMPLE_DATA   // Performing upsampling
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
        int ch;         // Loop variable for channels
        int out_fr;     // Loop variable for output frames
        int in_fr_idx;  // Calculated index for input frame

        // Iterate over each channel
        for (ch = 0; ch < NUM_CHANNELS; ch = ch + 1) begin
            // Iterate over each output frame for the current channel
            for (out_fr = 0; out_fr < FRAMES_PER_CHANNEL_OUT; out_fr = out_fr + 1) begin
                // Calculate the corresponding input frame index (integer division for nearest neighbor)
                in_fr_idx = out_fr / SCALE_FACTOR;
                // Assign the input data to the temporary result (replication for upsampling)
                temp_result_comb[ch][out_fr] = i_data[ch][in_fr_idx];
            end
        end
    end

    // Output register: Store the upsampled result
    always_ff @(posedge clk or negedge rst_n) begin
        int ch_reg;     // Loop variable for channels in register block
        int out_fr_reg; // Loop variable for output frames in register block

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
// conv1_module (Working)
// 1D Convolutional Layer
// ============================================================================
module conv1_module #(
    parameter int DATA_WIDTH = 16,          // Data width of inputs, outputs, weights, biases
    parameter int FRACTIONAL_BITS = 8,      // Number of fractional bits for fixed-point arithmetic
    parameter int NUM_IN_CHANNELS  = 4,     // Number of input channels
    parameter int NUM_OUT_CHANNELS = 2,     // Number of output channels (kernels)
    parameter int KERNEL_SIZE      = 3,     // Size of the convolution kernel
    parameter int PADDING          = 1,     // Padding applied to input frames
    parameter int STRIDE           = 1,     // Stride of the convolution
    parameter int NUM_IN_FRAMES    = 2,     // Number of frames in the input data
    // Parameter to automatically calculate output frames, accessible by instantiating module
    parameter int P_NUM_OUT_FRAMES = ( (NUM_IN_FRAMES + 2 * PADDING) - KERNEL_SIZE) / STRIDE + 1
) (
    input wire                           clk,        // Clock signal
    input wire                           rst_n,      // Asynchronous reset (active low)
    input wire                           i_start,    // Start signal for computation
    input wire signed [DATA_WIDTH-1:0]   i_data [0:NUM_IN_CHANNELS-1][0:NUM_IN_FRAMES-1], // Input data
    output logic signed [DATA_WIDTH-1:0] o_result [0:NUM_OUT_CHANNELS-1][0:P_NUM_OUT_FRAMES-1], // Output data
    output logic                         o_busy,     // Busy signal, high during computation
    output logic                         o_done_tick // Single cycle pulse when computation for one output set is done
);
    // Internal calculation for number of input frames after padding
    localparam int NUM_IN_FRAMES_PADDED = NUM_IN_FRAMES + 2 * PADDING;
    // Internal calculation for number of output frames (consistent with P_NUM_OUT_FRAMES)
    localparam int NUM_OUT_FRAMES_INTERNAL = P_NUM_OUT_FRAMES;

    // Saturation values for 16-bit signed data
    localparam logic signed [DATA_WIDTH-1:0] S16_MAX_VAL = (1<<(DATA_WIDTH-1))-1;
    localparam logic signed [DATA_WIDTH-1:0] S16_MIN_VAL = -(1<<(DATA_WIDTH-1));
    // Rounding constant for fixed-point arithmetic
    localparam logic signed [31:0] ROUND_CONST = (FRACTIONAL_BITS > 0) ? (1<<(FRACTIONAL_BITS-1)) : 0;

    // Convolution kernels (weights)
    localparam logic signed [DATA_WIDTH-1:0] KERNELS [0:NUM_OUT_CHANNELS-1][0:NUM_IN_CHANNELS-1][0:KERNEL_SIZE-1] = '{
        // Kernel for Output Channel 0
        '{  '{16'sd26,16'sd51,16'sd26},    // Weights for Input Channel 0
            '{16'sd77,16'sd26,16'sd51},    // Weights for Input Channel 1
            '{16'sd51,16'sd77,16'sd26},    // Weights for Input Channel 2
            '{16'sd26,16'sd26,16'sd77}     // Weights for Input Channel 3
        },
        // Kernel for Output Channel 1
        '{  '{16'sd102,16'sd51,16'sd26},   // Weights for Input Channel 0
            '{16'sd26,16'sd77,16'sd102},   // Weights for Input Channel 1
            '{16'sd77,16'sd51,16'sd51},   // Weights for Input Channel 2
            '{16'sd51,16'sd102,16'sd26}    // Weights for Input Channel 3
        }
    };
    // Biases for each output channel
    localparam logic signed [DATA_WIDTH-1:0] BIASES [0:NUM_OUT_CHANNELS-1] = '{ 16'sd13, 16'sd15 };

    // Internal storage for padded input data
    logic signed [DATA_WIDTH-1:0] padded_input_data [0:NUM_IN_CHANNELS-1][0:NUM_IN_FRAMES_PADDED-1];

    // State machine definition
    typedef enum logic [1:0] {
        S_IDLE,          // Waiting for start signal
        S_COMPUTE_SETUP, // Initial setup for computation (can be merged if not needed)
        S_COMPUTE_ITER,  // Iterating through output channels and frames
        S_DONE           // Computation finished for the current input
    } state_t;
    state_t current_state, next_state;

    // Registers to iterate through output channels (oc) and output frames (of)
    logic [($clog2(NUM_OUT_CHANNELS)>0?$clog2(NUM_OUT_CHANNELS)-1:0):0]       oc_reg; // Output channel counter
    logic [($clog2(NUM_OUT_FRAMES_INTERNAL)>0?$clog2(NUM_OUT_FRAMES_INTERNAL)-1:0):0] of_reg; // Output frame counter

    // Combinational result for the current pixel/frame being computed
    logic signed [DATA_WIDTH-1:0] current_pixel_value_comb;

    // Initial block to check for valid parameter configurations
    initial begin 
        if (NUM_OUT_FRAMES_INTERNAL <= 0) begin
            $error("conv1_module: NUM_OUT_FRAMES_INTERNAL must be positive. Check KERNEL_SIZE, PADDING, STRIDE, NUM_IN_FRAMES.");
            $finish;
        end
    end

    // Combinational logic for padding the input data
    always_comb begin
        integer ic_pad, f_pad; // Loop variables for padding
        for(ic_pad=0; ic_pad<NUM_IN_CHANNELS; ic_pad=ic_pad+1) begin
            for(f_pad=0; f_pad<NUM_IN_FRAMES_PADDED; f_pad=f_pad+1) begin
                // Apply zero-padding
                if(f_pad<PADDING || f_pad>=(NUM_IN_FRAMES+PADDING)) begin
                    padded_input_data[ic_pad][f_pad]=16'sd0;
                end else begin
                    // Copy input data to the non-padded region
                    padded_input_data[ic_pad][f_pad]=i_data[ic_pad][f_pad-PADDING];
                end
            end
        end
    end

    // State register
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            current_state<=S_IDLE;
        end else begin
            current_state<=next_state;
        end
    end

    // oc_reg and of_reg counters
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            oc_reg<='0;
            of_reg<='0;
        end else if(next_state==S_IDLE && current_state!=S_IDLE)begin // Reset counters when returning to IDLE
            oc_reg<='0;
            of_reg<='0;
        end else if(current_state==S_COMPUTE_ITER)begin // Increment counters during computation
            if(of_reg==NUM_OUT_FRAMES_INTERNAL-1)begin
                of_reg<='0; // Reset frame counter
                if(oc_reg==NUM_OUT_CHANNELS-1)begin
                    oc_reg<='0; // Reset channel counter (should transition out of S_COMPUTE_ITER before this is used)
                end else begin
                    oc_reg<=oc_reg+1; // Increment channel counter
                end
            end else begin
                of_reg<=of_reg+1; // Increment frame counter
            end
        end else if(current_state==S_IDLE && i_start)begin // Initialize counters on new start
            oc_reg<='0;
            of_reg<='0;
        end
    end

    // Next state logic for FSM, and o_busy/o_done_tick generation
    always_comb begin
        next_state=current_state;
        o_done_tick=1'b0;
        o_busy=1'b1; // Default busy to high unless in IDLE or DONE
        case(current_state)
            S_IDLE:begin
                o_busy=1'b0;
                if(i_start)begin
                    next_state=S_COMPUTE_SETUP; // Or directly to S_COMPUTE_ITER if no setup needed
                end
            end
            S_COMPUTE_SETUP:begin
                next_state=S_COMPUTE_ITER; // Proceed to computation
            end
            S_COMPUTE_ITER:begin
                // Check if all output channels and frames have been computed
                if(oc_reg==NUM_OUT_CHANNELS-1 && of_reg==NUM_OUT_FRAMES_INTERNAL-1)begin
                    next_state=S_DONE; // All computations finished
                end else begin
                    next_state=S_COMPUTE_ITER; // Continue computation
                end
            end
            S_DONE:begin
                o_done_tick=1'b1; // Signal completion
                next_state=S_IDLE;  // Return to IDLE
                o_busy=1'b0;        // Not busy anymore
            end
            default:begin
                next_state=S_IDLE;
                o_busy=1'b0;
            end
        endcase
    end

    // Combinational logic for convolution operation (MAC unit)
    always_comb begin
        logic signed[31:0] acc_mac;             // Accumulator for MAC (wider to prevent overflow)
        logic signed[31:0] prod_mac;            // Product of input and kernel (wider)
        logic signed[31:0] scaled_prod_mac;     // Product after scaling (fixed-point division)
        logic signed[31:0] bias_ext_mac;        // Bias extended to accumulator width
        integer ic_m, k_m, rfs_m, ifi_m;        // Loop/index variables for MAC

        acc_mac=32'sd0; // Initialize accumulator for the current output pixel

        // Iterate over input channels
        for(ic_m=0; ic_m<NUM_IN_CHANNELS; ic_m=ic_m+1)begin
            // Iterate over kernel size
            for(k_m=0; k_m<KERNEL_SIZE; k_m=k_m+1)begin
                // Calculate receptive field start based on output frame and stride
                rfs_m = of_reg * STRIDE; 
                // Calculate input frame index for the current kernel element
                ifi_m = rfs_m + k_m;      
                
                // Ensure input frame index is within bounds of padded input
                if (ifi_m >= 0 && ifi_m < NUM_IN_FRAMES_PADDED) begin 
                    prod_mac = padded_input_data[ic_m][ifi_m] * KERNELS[oc_reg][ic_m][k_m];
                    // Scale product (fixed-point division) with rounding
                    scaled_prod_mac = (prod_mac + ROUND_CONST) >>> FRACTIONAL_BITS;
                    acc_mac += scaled_prod_mac; // Accumulate
                end
                // else: if ifi_m is out of bounds, effectively multiply by zero (due to padding or incorrect indexing)
            end
        end
        bias_ext_mac = BIASES[oc_reg]; // Extend bias to 32 bits
        acc_mac += bias_ext_mac;       // Add bias

        // Saturate the accumulated result to DATA_WIDTH
        if(acc_mac > S16_MAX_VAL)begin
            current_pixel_value_comb = S16_MAX_VAL;
        end else if(acc_mac < S16_MIN_VAL)begin
            current_pixel_value_comb = S16_MIN_VAL;
        end else begin
            current_pixel_value_comb = acc_mac[DATA_WIDTH-1:0]; // Truncate to DATA_WIDTH
        end
    end

    // Output register: Store the computed pixel value
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            // Reset output array to zeros
            for(int ocl_ff=0; ocl_ff<NUM_OUT_CHANNELS; ocl_ff=ocl_ff+1)begin
                if (NUM_OUT_FRAMES_INTERNAL > 0) begin 
                    for(int ofl_ff=0; ofl_ff<NUM_OUT_FRAMES_INTERNAL; ofl_ff=ofl_ff+1)begin
                        o_result[ocl_ff][ofl_ff] <= {DATA_WIDTH{1'b0}};
                    end
                end
            end
        end else if(current_state==S_COMPUTE_ITER)begin 
            // When in computation state, register the combinational result for the current output pixel
            // Bounds check to prevent writing out of array range (though FSM should manage this)
            if (oc_reg < NUM_OUT_CHANNELS && of_reg < NUM_OUT_FRAMES_INTERNAL) begin
                o_result[oc_reg][of_reg] <= current_pixel_value_comb;
            end
        end
    end
endmodule

// ============================================================================
// relu_module (Standard Version - Working)
// Rectified Linear Unit Activation
// ============================================================================
module relu_module #(
    parameter int NUM_CHANNELS = 4,             // Number of channels
    parameter int FRAMES_PER_CHANNEL = 1,       // Number of frames per channel
    parameter int DATA_WIDTH = 16               // Data width of inputs and outputs
) (
    input wire                           clk,
    input wire                           rst_n,
    input wire                           i_start,      // Start signal
    input wire signed [DATA_WIDTH-1:0]   i_data [0:NUM_CHANNELS-1][0:FRAMES_PER_CHANNEL-1], // Input data
    output logic                         o_done_tick,  // Computation done signal
    output logic signed [DATA_WIDTH-1:0] o_result [0:NUM_CHANNELS-1][0:FRAMES_PER_CHANNEL-1]  // Output data after ReLU
);
    // Temporary storage for the combinational result
    logic signed [DATA_WIDTH-1:0] temp_result_comb [0:NUM_CHANNELS-1][0:FRAMES_PER_CHANNEL-1];

    // State machine definition
    typedef enum logic [0:0] {
        IDLE,       // Waiting for start
        APPLY_RELU  // Applying ReLU operation
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
                    next_state = APPLY_RELU;
                end
            end
            APPLY_RELU: begin
                o_done_tick = 1'b1; // ReLU operation is combinational, done in one cycle
                next_state = IDLE;
            end
            default: begin
                next_state = IDLE;
            end
        endcase
    end

    // Combinational logic for ReLU
    always_comb begin
        // Iterate over each channel and frame
        for (int ch = 0; ch < NUM_CHANNELS; ch = ch + 1) begin
            for (int fr = 0; fr < FRAMES_PER_CHANNEL; fr = fr + 1) begin
                // Apply ReLU: output = (input < 0) ? 0 : input
                temp_result_comb[ch][fr] = (i_data[ch][fr] < 16'sd0) ? 16'sd0 : i_data[ch][fr];
            end
        end
    end

    // Output register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset output to 0
            for (int ch_reg=0; ch_reg<NUM_CHANNELS; ch_reg=ch_reg+1) begin
                for (int fr_reg=0; fr_reg<FRAMES_PER_CHANNEL; fr_reg=fr_reg+1) begin
                    o_result[ch_reg][fr_reg] <= {DATA_WIDTH{1'b0}};
                end
            end
        end else if (o_done_tick) begin // When ReLU computation is done
            // Register the result
            for (int ch_reg=0; ch_reg<NUM_CHANNELS; ch_reg=ch_reg+1) begin
                for (int fr_reg=0; fr_reg<FRAMES_PER_CHANNEL; fr_reg=fr_reg+1) begin
                    o_result[ch_reg][fr_reg] <= temp_result_comb[ch_reg][fr_reg];
                end
            end
        end
    end
endmodule

// ============================================================================
// conv2_module (from original simple_decoder_accelerator.sv)
// 1D Convolutional Layer (variant, e.g. for different configuration)
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
    input wire                           clk, rst_n, i_start,
    input wire signed [DATA_WIDTH-1:0]   i_data [0:NUM_IN_CHANNELS-1][0:NUM_IN_FRAMES-1],
    output logic signed [DATA_WIDTH-1:0] o_result [0:NUM_OUT_CHANNELS-1][0:P_NUM_OUT_FRAMES-1],
    output logic                         o_busy, o_done_tick
);
    localparam int NUM_IN_FRAMES_PADDED = NUM_IN_FRAMES + 2 * PADDING;
    localparam int NUM_OUT_FRAMES_INTERNAL = P_NUM_OUT_FRAMES;
    localparam logic signed [DATA_WIDTH-1:0] S16_MAX_VAL = (1<<(DATA_WIDTH-1))-1;
    localparam logic signed [DATA_WIDTH-1:0] S16_MIN_VAL = -(1<<(DATA_WIDTH-1));
    localparam logic signed [31:0] ROUND_CONST = (FRACTIONAL_BITS > 0) ? (1<<(FRACTIONAL_BITS-1)) : 0;
    // Kernels for conv2
    localparam logic signed [DATA_WIDTH-1:0] KERNELS [0:NUM_OUT_CHANNELS-1][0:NUM_IN_CHANNELS-1][0:KERNEL_SIZE-1] = 
        // Only one output channel (NUM_OUT_CHANNELS = 1)
        '{  // Kernel for Output Channel 0
            '{  // Weights for Input Channel 0
                {16'sd128,16'sd26,16'sd51},
                // Weights for Input Channel 1
                {16'sd51,16'sd77,16'sd128}
            }
        };
    // Biases for conv2
    localparam logic signed [DATA_WIDTH-1:0] BIASES [0:NUM_OUT_CHANNELS-1] = '{ 16'sd18 }; // Bias for Output Channel 0

    logic signed [DATA_WIDTH-1:0] padded_input_data [0:NUM_IN_CHANNELS-1][0:NUM_IN_FRAMES_PADDED-1];
    typedef enum logic [1:0] { S_IDLE, S_COMPUTE_SETUP, S_COMPUTE_ITER, S_DONE } state_t;
    state_t current_state, next_state;
    
    // Output channel counter: Width is conditional. If NUM_OUT_CHANNELS=1, $clog2 is 0, so range is effectively empty or needs careful handling.
    // For NUM_OUT_CHANNELS = 1, oc_reg is not strictly needed for indexing KERNELS[0] but FSM might use it.
    logic [($clog2(NUM_OUT_CHANNELS)>0 ? $clog2(NUM_OUT_CHANNELS)-1 : 0):0] oc_reg; 
    logic [($clog2(NUM_OUT_FRAMES_INTERNAL)>0 ? $clog2(NUM_OUT_FRAMES_INTERNAL)-1 : 0):0] of_reg;
    logic signed [DATA_WIDTH-1:0] current_pixel_value_comb;

    initial begin 
        if (NUM_OUT_FRAMES_INTERNAL <= 0) begin
            $error("conv2_module: NUM_OUT_FRAMES_INTERNAL must be positive.");
            $finish;
        end
    end

    always_comb begin
        integer ic_pad,f_pad;
        for(ic_pad=0;ic_pad<NUM_IN_CHANNELS;ic_pad=ic_pad+1) begin
            for(f_pad=0;f_pad<NUM_IN_FRAMES_PADDED;f_pad=f_pad+1) begin
                if(f_pad<PADDING||f_pad>=(NUM_IN_FRAMES+PADDING)) begin
                    padded_input_data[ic_pad][f_pad]=16'sd0;
                end else begin
                    padded_input_data[ic_pad][f_pad]=i_data[ic_pad][f_pad-PADDING];
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            current_state<=S_IDLE;
        end else begin
            current_state<=next_state;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            if (NUM_OUT_CHANNELS > 1) oc_reg<='0; 
            else oc_reg <= '0; // Handles 0-width case if $clog2 is 0
            of_reg<='0;
        end else if(next_state==S_IDLE && current_state!=S_IDLE)begin
            if (NUM_OUT_CHANNELS > 1) oc_reg<='0;
            else oc_reg <= '0;
            of_reg<='0;
        end else if(current_state==S_COMPUTE_ITER)begin
            if(of_reg==NUM_OUT_FRAMES_INTERNAL-1)begin
                of_reg<='0;
                if (NUM_OUT_CHANNELS == 1 || oc_reg==NUM_OUT_CHANNELS-1)begin 
                    if (NUM_OUT_CHANNELS > 1) oc_reg<='0;
                    else oc_reg <= '0;
                end else begin
                    oc_reg<=oc_reg+1;
                end
            end else begin
                of_reg<=of_reg+1;
            end
        end else if(current_state==S_IDLE && i_start)begin
            if (NUM_OUT_CHANNELS > 1) oc_reg<='0;
            else oc_reg <= '0;
            of_reg<='0;
        end
    end

    always_comb begin
        next_state=current_state;
        o_done_tick=1'b0;
        o_busy=1'b1;
        case(current_state)
            S_IDLE:begin
                o_busy=1'b0;
                if(i_start)begin
                    next_state=S_COMPUTE_SETUP;
                end
            end
            S_COMPUTE_SETUP:begin
                next_state=S_COMPUTE_ITER;
            end
            S_COMPUTE_ITER:begin
                logic target_oc_reached;
                if (NUM_OUT_CHANNELS == 1) target_oc_reached = 1'b1; // For 1 output channel, oc_reg is effectively always at the target.
                else target_oc_reached = (oc_reg == NUM_OUT_CHANNELS-1);

                if(target_oc_reached && of_reg==NUM_OUT_FRAMES_INTERNAL-1)begin
                    next_state=S_DONE;
                end else begin
                    next_state=S_COMPUTE_ITER;
                end
            end
            S_DONE:begin
                o_done_tick=1'b1;
                next_state=S_IDLE;
                o_busy=1'b0;
            end
            default:begin
                next_state=S_IDLE;
                o_busy=1'b0;
            end
        endcase
    end

    always_comb begin
        logic signed[31:0]acc_mac,prod_mac,scaled_prod_mac,bias_ext_mac;
        integer ic_m,k_m,rfs_m,ifi_m;
        // current_oc_idx will be 0 if NUM_OUT_CHANNELS is 1
        logic [($clog2(NUM_OUT_CHANNELS)>0 ? $clog2(NUM_OUT_CHANNELS)-1 : 0):0] current_oc_idx; 

        if (NUM_OUT_CHANNELS == 1) current_oc_idx = '0; 
        else current_oc_idx = oc_reg;

        acc_mac=32'sd0;
        for(ic_m=0;ic_m<NUM_IN_CHANNELS;ic_m=ic_m+1)begin
            for(k_m=0;k_m<KERNEL_SIZE;k_m=k_m+1)begin
                rfs_m=of_reg*STRIDE;
                ifi_m=rfs_m+k_m;
                if (ifi_m >= 0 && ifi_m < NUM_IN_FRAMES_PADDED) begin
                    prod_mac=padded_input_data[ic_m][ifi_m]*KERNELS[current_oc_idx][ic_m][k_m];
                    scaled_prod_mac=(prod_mac+ROUND_CONST)>>>FRACTIONAL_BITS;
                    acc_mac+=scaled_prod_mac;
                end
            end
        end
        bias_ext_mac=BIASES[current_oc_idx];
        acc_mac+=bias_ext_mac;
        if(acc_mac>S16_MAX_VAL)begin
            current_pixel_value_comb=S16_MAX_VAL;
        end else if(acc_mac<S16_MIN_VAL)begin
            current_pixel_value_comb=S16_MIN_VAL;
        end else begin
            current_pixel_value_comb=acc_mac[DATA_WIDTH-1:0];
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        logic [($clog2(NUM_OUT_CHANNELS)>0 ? $clog2(NUM_OUT_CHANNELS)-1 : 0):0] current_oc_val_ff;
        if(!rst_n)begin
            for(int ocl_ff=0;ocl_ff<NUM_OUT_CHANNELS;ocl_ff=ocl_ff+1)begin
                if (NUM_OUT_FRAMES_INTERNAL > 0) begin 
                    for(int ofl_ff=0;ofl_ff<NUM_OUT_FRAMES_INTERNAL;ofl_ff=ofl_ff+1)begin
                        o_result[ocl_ff][ofl_ff]<={DATA_WIDTH{1'b0}};
                    end
                end
            end
        end else if(current_state==S_COMPUTE_ITER)begin
            if (NUM_OUT_CHANNELS == 1) current_oc_val_ff = '0; 
            else current_oc_val_ff = oc_reg;
            
            if (of_reg < NUM_OUT_FRAMES_INTERNAL) begin 
                 o_result[current_oc_val_ff][of_reg]<=current_pixel_value_comb;
            end
        end
    end
endmodule

// ============================================================================
// conv3_output_module
// Final 1D Convolutional Layer (e.g., 1x1 convolution for channel adjustment)
// ============================================================================
module conv3_output_module #(
    parameter int DATA_WIDTH = 16, 
    parameter int FRACTIONAL_BITS = 8,
    parameter int NUM_IN_CHANNELS  = 1, 
    parameter int NUM_OUT_CHANNELS = 2,
    parameter int KERNEL_SIZE      = 1, // Often 1 for a final pointwise convolution
    parameter int PADDING          = 0, // Typically 0 for a 1x1 convolution
    parameter int STRIDE           = 1,
    parameter int NUM_IN_FRAMES    = 4, 
    parameter int P_NUM_OUT_FRAMES = ((NUM_IN_FRAMES + 2 * PADDING) - KERNEL_SIZE) / STRIDE + 1
) (
    input wire                           clk, rst_n, i_start,
    input wire signed [DATA_WIDTH-1:0]   i_data [0:NUM_IN_CHANNELS-1][0:NUM_IN_FRAMES-1],
    output logic signed [DATA_WIDTH-1:0] o_result [0:NUM_OUT_CHANNELS-1][0:P_NUM_OUT_FRAMES-1],
    output logic                         o_busy, o_done_tick
);
    localparam int NUM_IN_FRAMES_PADDED = NUM_IN_FRAMES + 2 * PADDING; 
    localparam int NUM_OUT_FRAMES_INTERNAL = P_NUM_OUT_FRAMES;
    localparam logic signed [DATA_WIDTH-1:0] S16_MAX_VAL = (1<<(DATA_WIDTH-1))-1;
    localparam logic signed [DATA_WIDTH-1:0] S16_MIN_VAL = -(1<<(DATA_WIDTH-1));
    localparam logic signed [31:0] ROUND_CONST = (FRACTIONAL_BITS > 0) ? (1<<(FRACTIONAL_BITS-1)) : 0;
    // Kernels for conv3 (example for NUM_OUT_CHANNELS=2, NUM_IN_CHANNELS=1, KERNEL_SIZE=1)
    localparam logic signed [DATA_WIDTH-1:0] KERNELS [0:NUM_OUT_CHANNELS-1][0:NUM_IN_CHANNELS-1][0:KERNEL_SIZE-1] = 
        '{  // Output Channel 0
            '{ '{16'sd205} }, // Input Channel 0, Kernel Element 0
            // Output Channel 1
            '{ '{16'sd230} }  // Input Channel 0, Kernel Element 0
        };
    // Biases for conv3
    localparam logic signed [DATA_WIDTH-1:0] BIASES [0:NUM_OUT_CHANNELS-1] = '{ 16'sd20, 16'sd23 };

    logic signed [DATA_WIDTH-1:0] padded_input_data [0:NUM_IN_CHANNELS-1][0:NUM_IN_FRAMES_PADDED-1];
    typedef enum logic [1:0] { S_IDLE, S_COMPUTE_SETUP, S_COMPUTE_ITER, S_DONE } state_t;
    state_t current_state, next_state;
    logic [($clog2(NUM_OUT_CHANNELS)>0?$clog2(NUM_OUT_CHANNELS)-1:0):0] oc_reg; 
    logic [($clog2(NUM_OUT_FRAMES_INTERNAL)>0?$clog2(NUM_OUT_FRAMES_INTERNAL)-1:0):0] of_reg;
    logic signed [DATA_WIDTH-1:0] current_pixel_value_comb;

    initial begin 
        if (NUM_OUT_FRAMES_INTERNAL <= 0) begin
            $error("conv3_output_module: NUM_OUT_FRAMES_INTERNAL must be positive.");
            $finish;
        end
         if (NUM_IN_FRAMES_PADDED != NUM_IN_FRAMES && PADDING == 0) begin
            $error("conv3_output_module: PADDING is 0, NUM_IN_FRAMES_PADDED (%0d) should equal NUM_IN_FRAMES (%0d).", NUM_IN_FRAMES_PADDED, NUM_IN_FRAMES);
            $finish;
        end
    end

    always_comb begin
        integer ic_pad,f_pad;
        for(ic_pad=0;ic_pad<NUM_IN_CHANNELS;ic_pad=ic_pad+1) begin 
            for(f_pad=0;f_pad<NUM_IN_FRAMES_PADDED;f_pad=f_pad+1) begin
                // Simplified padding logic as PADDING is often 0 for this type of layer
                if(PADDING==0) begin 
                    // Ensure f_pad does not go out of bounds for i_data
                    if (f_pad < NUM_IN_FRAMES) begin
                        padded_input_data[ic_pad][f_pad]=i_data[ic_pad][f_pad];
                    end else begin
                        // This case should not be hit if NUM_IN_FRAMES_PADDED == NUM_IN_FRAMES
                        padded_input_data[ic_pad][f_pad]=16'sd0; // Safety
                    end
                end else if(f_pad<PADDING||f_pad>=(NUM_IN_FRAMES+PADDING)) begin
                    padded_input_data[ic_pad][f_pad]=16'sd0;
                end else begin
                    padded_input_data[ic_pad][f_pad]=i_data[ic_pad][f_pad-PADDING];
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            current_state<=S_IDLE;
        end else begin
            current_state<=next_state;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            oc_reg<='0;
            of_reg<='0;
        end else if(next_state==S_IDLE && current_state!=S_IDLE)begin
            oc_reg<='0;
            of_reg<='0;
        end else if(current_state==S_COMPUTE_ITER)begin
            if(of_reg==NUM_OUT_FRAMES_INTERNAL-1)begin
                of_reg<='0;
                if(oc_reg==NUM_OUT_CHANNELS-1)begin
                    oc_reg<='0;
                end else begin
                    oc_reg<=oc_reg+1;
                end
            end else begin
                of_reg<=of_reg+1;
            end
        end else if(current_state==S_IDLE && i_start)begin
            oc_reg<='0;
            of_reg<='0;
        end
    end

    always_comb begin
        next_state=current_state;
        o_done_tick=1'b0;
        o_busy=1'b1;
        case(current_state)
            S_IDLE:begin
                o_busy=1'b0;
                if(i_start)begin
                    next_state=S_COMPUTE_SETUP;
                end
            end
            S_COMPUTE_SETUP:begin
                next_state=S_COMPUTE_ITER;
            end
            S_COMPUTE_ITER:begin
                if(oc_reg==NUM_OUT_CHANNELS-1 && of_reg==NUM_OUT_FRAMES_INTERNAL-1)begin
                    next_state=S_DONE;
                end else begin
                    next_state=S_COMPUTE_ITER;
                end
            end
            S_DONE:begin
                o_done_tick=1'b1;
                next_state=S_IDLE;
                o_busy=1'b0;
            end
            default:begin
                next_state=S_IDLE;
                o_busy=1'b0;
            end
        endcase
    end

    always_comb begin
        logic signed[31:0]acc_mac,prod_mac,scaled_prod_mac,bias_ext_mac;
        integer ic_m,k_m,rfs_m,ifi_m;
        
        acc_mac=32'sd0;
        for(ic_m=0;ic_m<NUM_IN_CHANNELS;ic_m=ic_m+1)begin 
            for(k_m=0;k_m<KERNEL_SIZE;k_m=k_m+1)begin 
                rfs_m=of_reg*STRIDE; 
                ifi_m=rfs_m+k_m;
                // With KERNEL_SIZE=1, PADDING=0, STRIDE=1, ifi_m will be equal to of_reg.
                // NUM_IN_FRAMES_PADDED will be equal to NUM_IN_FRAMES.
                // of_reg iterates from 0 to NUM_OUT_FRAMES_INTERNAL-1.
                // NUM_OUT_FRAMES_INTERNAL = NUM_IN_FRAMES in this case.
                // So, ifi_m should always be a valid index for padded_input_data[ic_m][ifi_m]
                // as long as of_reg < NUM_IN_FRAMES.
                if (ifi_m < NUM_IN_FRAMES_PADDED) begin 
                    prod_mac = padded_input_data[ic_m][ifi_m] * KERNELS[oc_reg][ic_m][k_m];
                    scaled_prod_mac = (prod_mac + ROUND_CONST) >>> FRACTIONAL_BITS;
                    acc_mac += scaled_prod_mac;
                end
            end
        end
        bias_ext_mac=BIASES[oc_reg];
        acc_mac+=bias_ext_mac;
        if(acc_mac>S16_MAX_VAL)begin
            current_pixel_value_comb=S16_MAX_VAL;
        end else if(acc_mac<S16_MIN_VAL)begin
            current_pixel_value_comb=S16_MIN_VAL;
        end else begin
            current_pixel_value_comb=acc_mac[DATA_WIDTH-1:0];
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            for(int ocl_ff=0;ocl_ff<NUM_OUT_CHANNELS;ocl_ff=ocl_ff+1)begin
                for(int ofl_ff=0;ofl_ff<NUM_OUT_FRAMES_INTERNAL;ofl_ff=ofl_ff+1)begin
                    o_result[ocl_ff][ofl_ff]<={DATA_WIDTH{1'b0}};
                end
            end
        end else if(current_state==S_COMPUTE_ITER)begin
            if (oc_reg < NUM_OUT_CHANNELS && of_reg < NUM_OUT_FRAMES_INTERNAL) begin
                 o_result[oc_reg][of_reg]<=current_pixel_value_comb;
            end
        end
    end
endmodule


// ============================================================================
// Chain: fc_relu -> up0 -> conv1 -> relu1 -> up1 -> conv2 -> relu2 -> up2 -> conv3 -> relu3
// ============================================================================
module full_chain_stage4 #(
    parameter int DATA_WIDTH = 16,
    parameter int FRACTIONAL_BITS = 8,
    parameter int LATENT_DIM = 4,
    // Stage 1: FC_ReLU
    parameter int FC_RELU_OUT_CH = 4, 
    parameter int FC_RELU_OUT_FR = 1, 
    // Stage 2: Upsample0
    parameter int UP0_SCALE_FACTOR = 2,
    // Stage 3: Conv1
    parameter int C1_OUT_CH = 2,       
    parameter int C1_K = 3, 
    parameter int C1_P = 1, 
    parameter int C1_S = 1,
    // Stage 4: ReLU1
    // Stage 5: Upsample1
    parameter int UP1_SCALE_FACTOR = 2,
    // Stage 6: Conv2
    parameter int C2_OUT_CH = 1, 
    parameter int C2_K = 3,
    parameter int C2_P = 1,
    parameter int C2_S = 1,
    // Stage 7: ReLU2
    // Stage 8: Upsample2
    parameter int UP2_SCALE_FACTOR = 2,
    // Stage 9: Conv3
    parameter int C3_OUT_CH = 2, 
    parameter int C3_K = 1,
    parameter int C3_P = 0,
    parameter int C3_S = 1,
    // Stage 10: ReLU3 (dimensions derived from Conv3 output)

    // Parameter to define the number of output frames for the entire chain.
    // This value is calculated by the instantiating module (e.g., testbench)
    // and represents the number of frames after the Conv3 layer (which is the same for ReLU3).
    parameter int P_CHAIN_FINAL_OUT_FRAMES = 8 // Default, should be overridden by testbench
) (
    input wire clk,
    input wire rst_n,
    input wire i_top_start,
    input wire signed [DATA_WIDTH-1:0] i_z_top [0:LATENT_DIM-1],

    output logic o_top_busy,
    output logic o_top_done_tick,
    // Final output of this chain (after relu3)
    // Dimensions use module parameters directly for port declaration.
    // C3_OUT_CH defines the channel dimension (ReLU3 doesn't change it).
    // P_CHAIN_FINAL_OUT_FRAMES (passed as parameter) defines the frame dimension (ReLU3 doesn't change it).
    output logic signed [DATA_WIDTH-1:0] o_chain_result 
        [0 : C3_OUT_CH - 1] 
        [0 : P_CHAIN_FINAL_OUT_FRAMES - 1]
);

    // --- Stage Dimensions Calculations (Internal localparams for clarity and reuse) ---
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

    // Dimensions for the new ReLU3 layer (input from Conv3)
    localparam int RELU3_IN_CH_calc = C3_OUT_CH;
    localparam int RELU3_IN_FR_calc = C3_OUT_FR_INTERNAL_CALC; // This is also P_CHAIN_FINAL_OUT_FRAMES

    // Sanity check: Ensure the passed P_CHAIN_FINAL_OUT_FRAMES matches internal calculation for Conv3 output frames.
    initial begin
        if (P_CHAIN_FINAL_OUT_FRAMES != C3_OUT_FR_INTERNAL_CALC) begin
            $error("full_chain_stage4: Mismatch in final output frames. Passed P_CHAIN_FINAL_OUT_FRAMES (%0d) != Internally calculated C3_OUT_FR_INTERNAL_CALC (%0d) for Conv3 output.",
                   P_CHAIN_FINAL_OUT_FRAMES, C3_OUT_FR_INTERNAL_CALC);
            $finish;
        end
        if (P_CHAIN_FINAL_OUT_FRAMES != RELU3_IN_FR_calc) begin // Also check against ReLU3 input frames
             $error("full_chain_stage4: Mismatch in ReLU3 input frames. Passed P_CHAIN_FINAL_OUT_FRAMES (%0d) != Internally calculated RELU3_IN_FR_calc (%0d).",
                   P_CHAIN_FINAL_OUT_FRAMES, RELU3_IN_FR_calc);
            $finish;
        end
    end

    // --- Done Signals ---
    logic fc_relu_done_sig, upsample0_done_sig, conv1_done_sig, relu1_done_sig;
    logic upsample1_done_sig, conv2_done_sig, relu2_done_sig, upsample2_done_sig;
    logic conv3_done_sig, relu3_done_sig; // Added relu3_done_sig

    // --- Start Signals ---
    logic fc_relu_start_sig, upsample0_start_sig, conv1_start_sig, relu1_start_sig;
    logic upsample1_start_sig, conv2_start_sig, relu2_start_sig, upsample2_start_sig;
    logic conv3_start_sig, relu3_start_sig; // Added relu3_start_sig

    // --- Data Wires between stages ---
    logic signed [DATA_WIDTH-1:0] data_fc_relu_out   [0:FC_RELU_OUT_CH-1][0:FC_RELU_OUT_FR-1];
    logic signed [DATA_WIDTH-1:0] data_upsample0_out [0:C1_IN_CH_calc-1][0:C1_IN_FR_calc-1]; 
    logic signed [DATA_WIDTH-1:0] data_conv1_out     [0:C1_OUT_CH-1][0:C1_OUT_FR_calc-1];
    logic signed [DATA_WIDTH-1:0] data_relu1_out     [0:UP1_IN_CH_calc-1][0:UP1_IN_FR_calc-1]; 
    logic signed [DATA_WIDTH-1:0] data_upsample1_out [0:C2_IN_CH_calc-1][0:C2_IN_FR_calc-1]; 
    logic signed [DATA_WIDTH-1:0] data_conv2_out     [0:RELU2_IN_CH_calc-1][0:RELU2_IN_FR_calc-1]; 
    logic signed [DATA_WIDTH-1:0] data_relu2_out     [0:UP2_IN_CH_calc-1][0:UP2_IN_FR_calc-1]; 
    logic signed [DATA_WIDTH-1:0] data_upsample2_out [0:C3_IN_CH_calc-1][0:C3_IN_FR_calc-1]; 
    logic signed [DATA_WIDTH-1:0] data_conv3_out     [0:RELU3_IN_CH_calc-1][0:RELU3_IN_FR_calc-1]; // Output of conv3, input to relu3
    // o_chain_result is the output of relu3_inst
    
    // --- Instantiate Modules ---
    fc_with_relu_layer #(
        .DATA_WIDTH(DATA_WIDTH), .FRACTIONAL_BITS(FRACTIONAL_BITS), .LATENT_DIM_FC(LATENT_DIM),
        .NUM_OUT_CHANNELS_FC(FC_RELU_OUT_CH), .NUM_OUT_FRAMES_FC(FC_RELU_OUT_FR)
    ) fc_relu_inst (
        .clk(clk), .rst_n(rst_n), .i_start(fc_relu_start_sig), .i_z(i_z_top), 
        .o_busy(), .o_done_tick(fc_relu_done_sig), .o_fc_relu_result(data_fc_relu_out)
    );

    upsample_module #(
        .NUM_CHANNELS(FC_RELU_OUT_CH), .FRAMES_PER_CHANNEL_IN(FC_RELU_OUT_FR),
        .SCALE_FACTOR(UP0_SCALE_FACTOR), .DATA_WIDTH(DATA_WIDTH)
    ) upsample0_inst (
        .clk(clk), .rst_n(rst_n), .i_start(upsample0_start_sig), .i_data(data_fc_relu_out), 
        .o_done_tick(upsample0_done_sig), .o_result(data_upsample0_out)
    );

    conv1_module #(
        .DATA_WIDTH(DATA_WIDTH), .FRACTIONAL_BITS(FRACTIONAL_BITS), 
        .NUM_IN_CHANNELS(C1_IN_CH_calc), .NUM_OUT_CHANNELS(C1_OUT_CH), 
        .KERNEL_SIZE(C1_K), .PADDING(C1_P), .STRIDE(C1_S), .NUM_IN_FRAMES(C1_IN_FR_calc)
    ) conv1_inst (
        .clk(clk), .rst_n(rst_n), .i_start(conv1_start_sig), .i_data(data_upsample0_out), 
        .o_busy(), .o_done_tick(conv1_done_sig), .o_result(data_conv1_out)
    );

    relu_module #(
        .NUM_CHANNELS(C1_OUT_CH), .FRAMES_PER_CHANNEL(C1_OUT_FR_calc), 
        .DATA_WIDTH(DATA_WIDTH)
    ) relu1_inst (
        .clk(clk), .rst_n(rst_n), .i_start(relu1_start_sig), .i_data(data_conv1_out), 
        .o_done_tick(relu1_done_sig), .o_result(data_relu1_out)
    );

    upsample_module #(
        .NUM_CHANNELS(UP1_IN_CH_calc), .FRAMES_PER_CHANNEL_IN(UP1_IN_FR_calc), 
        .SCALE_FACTOR(UP1_SCALE_FACTOR), .DATA_WIDTH(DATA_WIDTH)
    ) upsample1_inst (
        .clk(clk), .rst_n(rst_n), .i_start(upsample1_start_sig), .i_data(data_relu1_out), 
        .o_done_tick(upsample1_done_sig), .o_result(data_upsample1_out)
    );

    conv2_module #(
        .DATA_WIDTH(DATA_WIDTH), .FRACTIONAL_BITS(FRACTIONAL_BITS), 
        .NUM_IN_CHANNELS(C2_IN_CH_calc), .NUM_OUT_CHANNELS(C2_OUT_CH), 
        .KERNEL_SIZE(C2_K), .PADDING(C2_P), .STRIDE(C2_S), .NUM_IN_FRAMES(C2_IN_FR_calc)
    ) conv2_inst (
        .clk(clk), .rst_n(rst_n), .i_start(conv2_start_sig), .i_data(data_upsample1_out), 
        .o_busy(), .o_done_tick(conv2_done_sig), .o_result(data_conv2_out)
    );
    
    relu_module #(
        .NUM_CHANNELS(RELU2_IN_CH_calc), .FRAMES_PER_CHANNEL(RELU2_IN_FR_calc), 
        .DATA_WIDTH(DATA_WIDTH)
    ) relu2_inst (
        .clk(clk), .rst_n(rst_n), .i_start(relu2_start_sig), .i_data(data_conv2_out), 
        .o_done_tick(relu2_done_sig), .o_result(data_relu2_out)
    );

    upsample_module #(
        .NUM_CHANNELS(UP2_IN_CH_calc), .FRAMES_PER_CHANNEL_IN(UP2_IN_FR_calc), 
        .SCALE_FACTOR(UP2_SCALE_FACTOR), .DATA_WIDTH(DATA_WIDTH)
    ) upsample2_inst (
        .clk(clk), .rst_n(rst_n), .i_start(upsample2_start_sig), .i_data(data_relu2_out), 
        .o_done_tick(upsample2_done_sig), .o_result(data_upsample2_out)
    );

    conv3_output_module #(
        .DATA_WIDTH(DATA_WIDTH), .FRACTIONAL_BITS(FRACTIONAL_BITS),
        .NUM_IN_CHANNELS(C3_IN_CH_calc), .NUM_OUT_CHANNELS(C3_OUT_CH), 
        .KERNEL_SIZE(C3_K), .PADDING(C3_P), .STRIDE(C3_S),
        .NUM_IN_FRAMES(C3_IN_FR_calc),
        .P_NUM_OUT_FRAMES(P_CHAIN_FINAL_OUT_FRAMES) // Conv3 output frames = ReLU3 input frames
    ) conv3_inst (
        .clk(clk), .rst_n(rst_n), .i_start(conv3_start_sig), .i_data(data_upsample2_out), 
        .o_busy(), .o_done_tick(conv3_done_sig), .o_result(data_conv3_out) // Output to data_conv3_out
    );

    // New ReLU layer at the end
    relu_module #(
        .NUM_CHANNELS(RELU3_IN_CH_calc),         // Channels from Conv3 output
        .FRAMES_PER_CHANNEL(RELU3_IN_FR_calc), // Frames from Conv3 output (P_CHAIN_FINAL_OUT_FRAMES)
        .DATA_WIDTH(DATA_WIDTH)
    ) relu3_inst (
        .clk(clk), .rst_n(rst_n), .i_start(relu3_start_sig), .i_data(data_conv3_out), 
        .o_done_tick(relu3_done_sig), .o_result(o_chain_result) // Final chain output
    );


    // --- Control FSM for sequencing the chain ---
    // Increased state bits for more stages if needed, current 5 bits is enough for 10 computation stages + IDLE/DONE
    typedef enum logic [4:0] { 
        S_IDLE, 
        S_FCR_START, S_FCR_WAIT,      
        S_UP0_START, S_UP0_WAIT,      
        S_C1_START,  S_C1_WAIT,        
        S_RL1_START, S_RL1_WAIT,      
        S_UP1_START, S_UP1_WAIT,
        S_C2_START,  S_C2_WAIT,
        S_RL2_START, S_RL2_WAIT,
        S_UP2_START, S_UP2_WAIT, 
        S_C3_START,  S_C3_WAIT,
        S_RL3_START, S_RL3_WAIT,   // New states for relu3
        S_ALL_DONE 
    } state_e;
    state_e current_fsm_state, next_fsm_state;

    // FSM state register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) current_fsm_state <= S_IDLE;
        else current_fsm_state <= next_fsm_state;
    end

    // FSM next state logic and start signal generation
    always_comb begin
        next_fsm_state = current_fsm_state; 
        fc_relu_start_sig   = 1'b0; upsample0_start_sig = 1'b0; conv1_start_sig     = 1'b0; relu1_start_sig     = 1'b0;
        upsample1_start_sig = 1'b0; conv2_start_sig     = 1'b0; relu2_start_sig     = 1'b0; upsample2_start_sig = 1'b0;
        conv3_start_sig     = 1'b0; relu3_start_sig     = 1'b0; // Added relu3_start_sig
        
        o_top_busy = 1'b1; 
        o_top_done_tick = 1'b0;

        case (current_fsm_state)
            S_IDLE:      begin 
                            o_top_busy = 1'b0; 
                            if (i_top_start) next_fsm_state = S_FCR_START;   
                         end
            S_FCR_START: begin fc_relu_start_sig   = 1'b1; next_fsm_state = S_FCR_WAIT;   end
            S_FCR_WAIT:  if (fc_relu_done_sig)   next_fsm_state = S_UP0_START;
            S_UP0_START: begin upsample0_start_sig = 1'b1; next_fsm_state = S_UP0_WAIT;   end
            S_UP0_WAIT:  if (upsample0_done_sig) next_fsm_state = S_C1_START;
            S_C1_START:  begin conv1_start_sig     = 1'b1; next_fsm_state = S_C1_WAIT;    end
            S_C1_WAIT:   if (conv1_done_sig)     next_fsm_state = S_RL1_START;
            S_RL1_START: begin relu1_start_sig     = 1'b1; next_fsm_state = S_RL1_WAIT;   end
            S_RL1_WAIT:  if (relu1_done_sig)     next_fsm_state = S_UP1_START;
            S_UP1_START: begin upsample1_start_sig = 1'b1; next_fsm_state = S_UP1_WAIT;   end
            S_UP1_WAIT:  if (upsample1_done_sig) next_fsm_state = S_C2_START;
            S_C2_START:  begin conv2_start_sig     = 1'b1; next_fsm_state = S_C2_WAIT;    end
            S_C2_WAIT:   if (conv2_done_sig)     next_fsm_state = S_RL2_START;
            S_RL2_START: begin relu2_start_sig     = 1'b1; next_fsm_state = S_RL2_WAIT;   end
            S_RL2_WAIT:  if (relu2_done_sig)     next_fsm_state = S_UP2_START; 
            S_UP2_START: begin upsample2_start_sig = 1'b1; next_fsm_state = S_UP2_WAIT;   end 
            S_UP2_WAIT:  if (upsample2_done_sig) next_fsm_state = S_C3_START;    
            S_C3_START:  begin conv3_start_sig     = 1'b1; next_fsm_state = S_C3_WAIT;    end 
            S_C3_WAIT:   if (conv3_done_sig)     next_fsm_state = S_RL3_START;   // Transition to new relu3
            S_RL3_START: begin relu3_start_sig     = 1'b1; next_fsm_state = S_RL3_WAIT;   end // New state action
            S_RL3_WAIT:  if (relu3_done_sig)     next_fsm_state = S_ALL_DONE;   // Final layer's done
            S_ALL_DONE:  begin 
                            o_top_done_tick = 1'b1; 
                            o_top_busy = 1'b0; 
                            next_fsm_state = S_IDLE; 
                         end
            default:     begin 
                            next_fsm_state = S_IDLE; 
                            o_top_busy = 1'b0; 
                         end
        endcase
        if (current_fsm_state == S_IDLE && !i_top_start) begin
            o_top_busy = 1'b0;
        end
    end
endmodule
