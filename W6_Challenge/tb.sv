// File: lif_neuron_tb.sv
`timescale 1ns/1ps

module lif_neuron_tb;
  // Clock and signals
  logic clk;
  logic rst_n;
  logic spike_in;
  logic spike_out;

  // Instantiate DUT using default parameters
  lif_neuron dut (
    .clk      (clk),
    .rst_n    (rst_n),
    .spike_in (spike_in),
    .spike_out(spike_out)
  );

  // Clock generation: 10 ns period
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  //=====================================================================
  // Task: reset DUT
  task automatic do_reset();
    begin
      rst_n    = 1'b0;
      spike_in = 1'b0;
      #20;
      rst_n    = 1'b1;
      @(posedge clk);
    end
  endtask

  // Task: constant input below threshold
  task automatic constant_input_0();
    begin
      // Ensure input remains zero
      spike_in = 1'b0;

      // Run for 20 cycles
      repeat (20) @(posedge clk);

      // Check that no spike occurred
      if (spike_out) begin
        $error("[FAIL] TC 1: Unexpected spike on constant-zero input");
      end else begin
        $display("[PASS] TC 1: No spikes as expected");
      end
    end
  endtask

// Task: constant input
  task automatic constant_input_1();
    integer i;
    bit saw_spike;
    begin
      spike_in   = 1'b1;
      saw_spike  = 0;

      for (i = 0; i < 20; i++) begin
        @(posedge clk);
        if (spike_out) begin
          $display("[PASS] TC 2: saw spike at cycle %0d", i+1);
          saw_spike = 1;
          disable constant_input_1;  // exit the task early
        end
      end

      if (!saw_spike)
        $error("[FAIL] TC 2: never spiked within 20 cycles");
    end
  endtask
  
    // send a 1 every `period` cycles, for `n_cycles` total
  task automatic periodic_spikes(input int period, input int n_cycles);
    bit saw_spike;

    int i;
    begin
      saw_spike = 0;

      // assume DUT’s been reset already
      for (i = 1; i <= n_cycles; i++) begin
        // drive spike_in = 1 on exactly the 10th, 20th, 30th… cycle
        spike_in = (i % period == 0) ? 1'b1 : 1'b0;
        @(posedge clk);
        // optional: print what you saw
        if (spike_out) begin
          $display("[INFO] Periodic_spikes every %0d cycles saw spike at cycle %0d", period, i+1);
          saw_spike = 1;
        end
        
      end
      if (!saw_spike) begin
        $display("[INFO] Didn't see spike for spike at every %0d cycles aftr %0d total sycles", period, n_cycles);
      end
      
    end
  endtask
  
  //=====================================================================
  initial begin
    // Run test scenarios
    do_reset();
    constant_input_0();
    do_reset();
    constant_input_1();
    do_reset();
    periodic_spikes(10, 100);
    do_reset();
    periodic_spikes(500, 1000);
    $display("All tests complete.");
    $finish;
  end
endmodule
