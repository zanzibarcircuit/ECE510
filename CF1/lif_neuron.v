module lif_neuron #(
    parameter WIDTH = 16,
    parameter THRESHOLD = 100,
    parameter LEAK = 1,
    parameter REFRACTORY_TICKS = 10
)(
    input wire clk,
    input wire reset,
    input wire signed [WIDTH-1:0] input_current,
    output reg spike
);

    reg signed [WIDTH-1:0] membrane_potential;
    reg [$clog2(REFRACTORY_TICKS+1)-1:0] refractory_counter;
    reg in_refractory;

    reg signed [WIDTH-1:0] updated_potential;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            membrane_potential <= 0;
            refractory_counter <= 0;
            in_refractory <= 0;
            spike <= 0;
        end else begin
            if (in_refractory) begin
                spike <= 0;
                if (refractory_counter > 0)
                    refractory_counter <= refractory_counter - 1;
                else
                    in_refractory <= 0;
            end else begin
                updated_potential = membrane_potential + input_current;
                if (updated_potential > LEAK)
                    updated_potential = updated_potential - LEAK;
                else
                    updated_potential = 0;

                membrane_potential <= updated_potential;

                if (updated_potential >= THRESHOLD) begin
                    spike <= 1;
                    membrane_potential <= 0;
                    in_refractory <= 1;
                    refractory_counter <= REFRACTORY_TICKS - 1;
                end else begin
                    spike <= 0;
                end
            end
        end
    end

endmodule
