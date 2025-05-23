// fc_layer.v
// Implements a fully connected layer: o = W * i + b
// SystemVerilog version - With rounding for product scaling

module fc_layer (
    input wire                  clk,
    input wire                  rst_n,
    input wire                  i_start,        // Start computation
    input wire signed [15:0]    i_z [0:3],      // Input vector (LATENT_DIM=4, S7.8 like)

    output logic                o_busy,         // Busy signal
    output logic                o_done_tick,    // Output valid for one cycle
    output logic signed [15:0]  o_fc_result [0:3] // Output vector (FC_OUTPUT_SIZE=4, S7.8 like)
);

    localparam int FRACTIONAL_BITS = 8;

    localparam logic signed [15:0] WEIGHTS_FC [0:3][0:3] = '{
        '{ 16'sd26,  16'sd51,  16'sd77, 16'sd102 },
        '{ 16'sd128, 16'sd154, 16'sd179, 16'sd205 },
        '{ 16'sd51,  16'sd102, 16'sd154, 16'sd205 },
        '{ 16'sd26,  16'sd77,  16'sd128, 16'sd179 }
    };

    localparam logic signed [15:0] BIAS_FC [0:3] = '{ 16'sd3, 16'sd5, 16'sd8, 16'sd10 };

    localparam logic signed [15:0] S16_MAX_VAL = 32767;
    localparam logic signed [15:0] S16_MIN_VAL = -32768;

    localparam logic signed [31:0] ROUND_CONST = (1 << (FRACTIONAL_BITS - 1)); // 128

    logic signed [15:0] temp_fc_result_comb [0:3]; 

    typedef enum logic [0:0] {
        IDLE,
        COMPUTE
    } state_t;
    state_t current_state, next_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end

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
                o_done_tick = 1'b1;
                next_state = IDLE;
            end
            default: begin
                next_state = IDLE;
            end
        endcase
    end
    
    assign o_busy = (current_state == COMPUTE);

    always_comb begin
        for (int i = 0; i < 4; i++) begin
            temp_fc_result_comb[i] = o_fc_result[i]; 
        end

        if (current_state == COMPUTE) begin
            for (int i = 0; i < 4; i++) begin
                logic signed [31:0] accumulated_sum_wide; 
                logic signed [31:0] product_wide;
                logic signed [31:0] product_scaled;
                logic signed [31:0] bias_extended;

                accumulated_sum_wide = 32'sd0; 

                for (int j = 0; j < 4; j++) begin
                    product_wide = i_z[j] * WEIGHTS_FC[i][j]; 
                    // Add ROUND_CONST before shifting for rounding
                    product_scaled = (product_wide + ROUND_CONST) >>> FRACTIONAL_BITS;
                    accumulated_sum_wide = accumulated_sum_wide + product_scaled;
                end

                bias_extended = BIAS_FC[i]; 
                accumulated_sum_wide = accumulated_sum_wide + bias_extended;

                if (accumulated_sum_wide > S16_MAX_VAL) begin
                    temp_fc_result_comb[i] = S16_MAX_VAL;
                end else if (accumulated_sum_wide < S16_MIN_VAL) begin
                    temp_fc_result_comb[i] = S16_MIN_VAL;
                end else begin
                    temp_fc_result_comb[i] = accumulated_sum_wide[15:0];
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 4; i++) begin
                o_fc_result[i] <= 16'sd0;
            end
        end else if (o_done_tick) begin
            for (int i = 0; i < 4; i++) begin
                o_fc_result[i] <= temp_fc_result_comb[i];
            end
        end
    end

endmodule
