`timescale 1ns/1ps
module snn_2layer_tb;

    parameter WIDTH = 16;
    parameter N_INPUTS = 2;
    parameter N1 = 3;
    parameter N2 = 2;

    reg clk = 0;
    reg reset = 1;
    reg signed [WIDTH-1:0] input_vector [N_INPUTS-1:0];
    wire [N2-1:0] spike_out;

    snn_2layer #(
        .WIDTH(WIDTH),
        .N_INPUTS(N_INPUTS),
        .N1(N1),
        .N2(N2)
    ) snn (
        .clk(clk),
        .reset(reset),
        .input_vector(input_vector),
        .spike_out(spike_out)
    );

    always #5 clk = ~clk;

    integer i;
    initial begin
        $dumpfile("snn_2layer.vcd");
        $dumpvars(0, snn_2layer_tb);
        $dumpvars(0, snn);

        input_vector[0] = 0;
        input_vector[1] = 0;
        #10 reset = 0;

        #10 input_vector[0] = 10; input_vector[1] = 10;
        #100 input_vector[0] = 20; input_vector[1] = -10;
        #100 input_vector[0] = 0;  input_vector[1] = 0;

        #200 $finish;
    end

endmodule
