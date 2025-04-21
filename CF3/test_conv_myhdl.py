from myhdl import Signal, intbv, ResetSignal, delay, instance, Simulation, now, StopSimulation
from conv_myhdl import conv1d_stream
from conv_ref import conv1d_reference
import numpy as np

def testbench():
    clk = Signal(bool(0))
    rst = ResetSignal(0, active=1, isasync=False)
    din = Signal(intbv(0, min=-128, max=128))            # Q4.4 input
    dout = Signal(intbv(0, min=-32768, max=32768))        # Q8.8 output
    valid_in = Signal(bool(0))
    valid_out = Signal(bool(0))

    # Use fixed kernel values directly matching MyHDL (Q4.4: 3, 8, -4)
    kernel_vals = [intbv(k, min=-128, max=128) for k in [3, 8, -4]]
    kernel = [Signal(k) for k in kernel_vals]

    dut = conv1d_stream(clk, rst, din, dout, kernel, valid_in, valid_out)

    # Input signal and matching kernel for NumPy
    x = np.array([1, 2, 3, 4, 5], dtype=float)
    w = np.array([3/16, 8/16, -4/16])
    ref_out = conv1d_reference(x, w[::-1])  # Reverse for kernel alignment
    x_fixed = [int(i * 16) for i in x]      # Convert to Q4.4

    @instance
    def clkgen():
        while True:
            clk.next = not clk
            yield delay(5)

    @instance
    def stimulus():
        yield delay(10)
        rst.next = 1
        yield delay(10)
        rst.next = 0

        print("Feeding input and checking output...")

        output_index = 0
        max_cycles = 100
        i = 0

        for cycle in range(max_cycles):
            # Feed input sample if available
            if i < len(x_fixed):
                din.next = x_fixed[i]
                valid_in.next = True
                i += 1
            else:
                valid_in.next = False

            yield delay(10)

            if valid_out and output_index < len(ref_out):
                val = dout.signed() / 256.0  # Convert from Q8.8 to float
                expected = ref_out[output_index]
                print(f"[{now()}] Out: {val:.4f}  (Expected: {expected:.4f})")
                output_index += 1

        if output_index == 0:
            print("⚠️  No valid output was received.")

        raise StopSimulation()

    return dut, clkgen, stimulus

if __name__ == '__main__':
    sim = Simulation(testbench())
    sim.run()
