import numpy as np

def leaky_relu(x, negative_slope=0.01):
    return np.where(x >= 0, x, x * negative_slope)

def conv1d_residual_block(input_data, skip_data, weights):
    input_channels, time_steps = input_data.shape
    output_channels, _, kernel_size = weights.shape

    # Pad input on time axis (zero padding by 1 on each side)
    padded_input = np.pad(input_data, ((0, 0), (1, 1)), mode='constant', constant_values=0)

    # Output buffer
    output_data = np.zeros((output_channels, time_steps))

    # Process each time step
    for t in range(time_steps):
        for out_ch in range(output_channels):
            acc = 0
            for in_ch in range(input_channels):
                window = padded_input[in_ch, t:t+kernel_size]  # 3-sample window
                kernel = weights[out_ch, in_ch, :]
                acc += np.sum(window * kernel)
            # Add skip connection
            acc += skip_data[out_ch, t]
            # Apply LeakyReLU activation
            output_data[out_ch, t] = leaky_relu(acc)

    return output_data

def main():
    # Settings
    input_channels = 2
    output_channels = 2
    kernel_size = 3
    time_steps = 4

    # Example input activations (input_channels x time_steps)
    input_data = np.array([
        [1, 2, 3, 4],  # Channel 0
        [5, 6, 7, 8]   # Channel 1
    ], dtype=np.float32)

    # Use input data as skip connection for simplicity
    skip_data = np.copy(input_data)

    # Example weights [output_channels][input_channels][kernel_size]
    weights = np.zeros((output_channels, input_channels, kernel_size), dtype=np.float32)

    # Fill weights manually for clarity
    weights[0, 0] = [1, 0, -1]   # out0, ch0
    weights[0, 1] = [2, 0, -2]   # out0, ch1
    weights[1, 0] = [0, 1, 0]    # out1, ch0
    weights[1, 1] = [1, -1, 1]   # out1, ch1

    # Print inputs
    print("Input Data:\n", input_data)
    print("Skip Data:\n", skip_data)
    print("Weights:\n", weights)

    # Run convolution + residual + activation
    output_data = conv1d_residual_block(input_data, skip_data, weights)

    # Print output
    print("Output Data:\n", output_data)

if __name__ == "__main__":
    main()
