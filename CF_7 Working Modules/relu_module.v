// relu_module.v
// Applies ReLU function element-wise: output = (input < 0) ? 0 : input;
// SystemVerilog version

module relu_module (
    input wire                  clk,
    input wire                  rst_n,
    input wire                  i_start,        // Start computation
    input wire signed [15:0]    i_data [0:3],   // Input data array (4 elements, S7.8 like)

    output logic                o_done_tick,    // Output valid for one cycle
    output logic signed [15:0]  o_result [0:3]  // Output data array (ReLU applied)
);

    // For ReLU, computation is simple and can be combinational with registered output
    // Or purely combinational if the next stage can accept it immediately.
    // Let's make it a 1-cycle operation like fc_layer for consistency in control.

    logic signed [15:0] temp_result_comb [0:3]; // Combinational result before registration

    // State machine for control 
    typedef enum logic [0:0] {
        IDLE,
        APPLY_RELU
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

    // Next state logic & o_done_tick
    always_comb begin
        next_state = current_state;
        o_done_tick = 1'b0; // Default

        case (current_state)
            IDLE: begin
                if (i_start) begin
                    next_state = APPLY_RELU;
                end
            end
            APPLY_RELU: begin
                // Combinational calculation is done, signal done
                o_done_tick = 1'b1;
                next_state = IDLE; // Go back to IDLE
            end
            default: next_state = IDLE;
        endcase
    end

    // Combinational ReLU logic: temp_result_comb is calculated based on i_data
    // This happens continuously, but is only meaningful/latched when APPLY_RELU state is active.
    always_comb begin
        for (int i = 0; i < 4; i++) begin // NUM_ELEMENTS is 4
            if (i_data[i] < 16'sd0) begin
                temp_result_comb[i] = 16'sd0;
            end else begin
                temp_result_comb[i] = i_data[i];
            end
        end
    end

    // Output register: Latch the combinational result when o_done_tick is asserted
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 4; i++) begin // NUM_ELEMENTS is 4
                o_result[i] <= 16'sd0;
            end
        end else if (o_done_tick) begin // Latch when computation is "done" for this cycle
            for (int i = 0; i < 4; i++) begin // NUM_ELEMENTS is 4
                o_result[i] <= temp_result_comb[i];
            end
        end
        // If not o_done_tick, o_result holds its previous value
    end

endmodule
