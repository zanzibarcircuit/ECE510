import numpy as np

def conv1d_reference(x, w, b=0):
    """
    Naive 1D convolution (no padding, stride=1).
    x: input signal, shape (T,)
    w: kernel weights, shape (K,)
    b: bias term (scalar)
    returns: output signal, shape (T - K + 1,)
    """
    K = len(w)
    T = len(x)
    y = np.zeros(T - K + 1)
    for i in range(T - K + 1):
        y[i] = np.sum(x[i:i+K] * w) + b
    return y
