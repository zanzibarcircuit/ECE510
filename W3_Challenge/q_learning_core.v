module q_learning_core(
    input clk,
    input rst,
    input start,
    input [4:0] s_row, s_col, s_prime_row, s_prime_col,
    input [1:0] action,
    input signed [15:0] reward,
    output done
);
    parameter signed [15:0] ALPHA     = 16'sd2048; // 0.5 in Q4.12
    parameter signed [15:0] ONE_MINUS_ALPHA = 16'sd2048; // 1 - 0.5
    parameter signed [15:0] GAMMA     = 16'sd3686; // 0.9 in Q4.12

    reg signed [15:0] Q_table[0:4][0:4][0:3];

    typedef enum logic [3:0] {
        IDLE,
        READ_Q_CURRENT,
        READ_Q_NEXT_ALL_WAIT,
        READ_Q_NEXT_ALL,
        COMPUTE_MAX_WAIT,
        COMPUTE_MAX,
        UPDATE_Q_WAIT,
        UPDATE_Q,
        UPDATE_Q_CALC,
        WRITE_BACK,
        DONE
    } state_t;

    state_t state;
    reg signed [15:0] q_current, q0, q1, q2, q3, max_q, target, updated;
    assign done = (state == DONE);

    function signed [15:0] fixed_mult;
        input signed [15:0] a, b;
        reg signed [31:0] product;
        begin
            product = a * b;
            fixed_mult = product >>> 12;
        end
    endfunction

    function signed [15:0] max2;
        input signed [15:0] a, b;
        max2 = (a > b) ? a : b;
    endfunction

    function signed [15:0] max4;
        input signed [15:0] a, b, c, d;
        max4 = max2(max2(a, b), max2(c, d));
    endfunction

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            integer i, j, k;
            for (i = 0; i < 5; i = i + 1)
                for (j = 0; j < 5; j = j + 1)
                    for (k = 0; k < 4; k = k + 1)
                        Q_table[i][j][k] <= 16'sd0;
            state <= IDLE;
        end else begin
            case (state)
                IDLE:
                    if (start) state <= READ_Q_CURRENT;

                READ_Q_CURRENT: begin
                    q_current <= Q_table[s_row][s_col][action];
                    $display("READ_Q_CURRENT: Q[%0d][%0d][%0d] = %d", s_row, s_col, action, Q_table[s_row][s_col][action]);
                    state <= READ_Q_NEXT_ALL_WAIT;
                end

                READ_Q_NEXT_ALL_WAIT:
                    state <= READ_Q_NEXT_ALL;

                READ_Q_NEXT_ALL: begin
                    q0 <= Q_table[s_prime_row][s_prime_col][0];
                    q1 <= Q_table[s_prime_row][s_prime_col][1];
                    q2 <= Q_table[s_prime_row][s_prime_col][2];
                    q3 <= Q_table[s_prime_row][s_prime_col][3];
                    $display("READ_Q_NEXT_ALL: Q' = [%d, %d, %d, %d]", Q_table[s_prime_row][s_prime_col][0], Q_table[s_prime_row][s_prime_col][1], Q_table[s_prime_row][s_prime_col][2], Q_table[s_prime_row][s_prime_col][3]);
                    state <= COMPUTE_MAX_WAIT;
                end

                COMPUTE_MAX_WAIT:
                    state <= COMPUTE_MAX;

                COMPUTE_MAX: begin
                    max_q <= max4(q0, q1, q2, q3);
                    $display("COMPUTE_MAX: max_q = %d", max4(q0, q1, q2, q3));
                    state <= UPDATE_Q_WAIT;
                end

                UPDATE_Q_WAIT:
                    state <= UPDATE_Q;

                UPDATE_Q: begin
                    target <= reward + fixed_mult(GAMMA, max_q);
                    $display("UPDATE_Q: reward = %d, gamma = %d, max_q = %d", reward, GAMMA, max_q);
                    $display("UPDATE_Q: target = reward + gamma*max_q = %d", reward + fixed_mult(GAMMA, max_q));
                    state <= UPDATE_Q_CALC;
                end

                UPDATE_Q_CALC: begin
                    updated <= fixed_mult(ONE_MINUS_ALPHA, q_current) + fixed_mult(ALPHA, target);
                    $display("UPDATE_Q_CALC: q_current = %d", q_current);
                    $display("UPDATE_Q_CALC: updated = (1-alpha)*q_current + alpha*target = %d", fixed_mult(ONE_MINUS_ALPHA, q_current) + fixed_mult(ALPHA, target));
                    state <= WRITE_BACK;
                end

                WRITE_BACK: begin
                    Q_table[s_row][s_col][action] <= updated;
                    $display("WRITE_BACK: Writing Q[%0d][%0d][%0d] = %d", s_row, s_col, action, updated);
                    state <= DONE;
                end

                DONE:
                    state <= IDLE;
            endcase
        end
    end
endmodule
