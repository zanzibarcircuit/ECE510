from myhdl import block, always_seq, Signal, intbv, ResetSignal, instances, now

@block
def conv1d_stream(clk, rst, din, dout, kernel, valid_in, valid_out):
    """
    Streaming 1D convolution with kernel size 3.
    - din: input sample (Q4.4 fixed-point, signed 8-bit)
    - dout: output sample (Q8.8 fixed-point, signed 16-bit)
    - kernel: 3-element list of 8-bit signed fixed-point weights
    """
    window = [Signal(intbv(0, min=-128, max=128)) for _ in range(3)]
    count = Signal(intbv(0, min=0, max=4))  # Tracks how many samples have been loaded

    @always_seq(clk.posedge, reset=rst)
    def logic():
        print(f"[{now()}] CLK ↑ — valid_in: {int(valid_in)}, din: {int(din)}")

        if valid_in:
            # Shift window
            print(f"  → Shifting window: {int(window[0])}, {int(window[1])}, {int(window[2])}")
            window[2].next = window[1]
            window[1].next = window[0]
            window[0].next = din

            # Update sample counter
            if count < 3:
                count.next = count + 1
            print(f"  → Sample count: {int(count)}")

            if count >= 2:
                acc = intbv(0, min=-2**15, max=2**15)
                for i in range(3):
                    prod = window[i].signed() * kernel[2 - i].signed()
                    acc += prod
                    print(f"    MAC[{i}]: {int(window[i])} * {int(kernel[2 - i])} = {int(prod)}")

                dout.next = acc
                valid_out.next = True
                print(f"  → Output: {int(acc)} (Q8.8), valid_out: 1")
            else:
                valid_out.next = False
                print("  → Window not full — no output yet.")
        else:
            valid_out.next = False

    return instances()
