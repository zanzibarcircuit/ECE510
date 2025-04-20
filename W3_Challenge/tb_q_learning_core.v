`timescale 1ns / 1ps

module tb_q_learning_core();
    reg clk = 0;
    reg rst;
    reg start;
    reg [4:0] s_row, s_col, s_prime_row, s_prime_col;
    reg [1:0] action;
    reg signed [15:0] reward;
    wire done;

    q_learning_core dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .s_row(s_row),
        .s_col(s_col),
        .s_prime_row(s_prime_row),
        .s_prime_col(s_prime_col),
        .action(action),
        .reward(reward),
        .done(done)
    );

    always #5 clk = ~clk;  // 100 MHz clock

    initial begin
        $display("Starting Q-Learning core test...");
        rst = 1;
        start = 0;
        #20;
        rst = 0;

        s_row = 0; s_col = 0;       // Current state
        s_prime_row = 1; s_prime_col = 0; // Next state
        action = 2'd1;              // Action taken (down)
        reward = -5 * 4096;         // -5 in Q4.12

        #10;
        start = 1;
        #10;
        start = 0;
        wait(done);
        #20;
        $display("Updated Q[0][0][1] = %d", dut.Q_table[0][0][1]);
        $finish;
    end
endmodule
