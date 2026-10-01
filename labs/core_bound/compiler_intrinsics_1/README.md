# Compiler Intrinsics 1: 1D Image Smoothing with ARM NEON

This lab explores optimizing a 1D image smoothing (moving average / sliding window) kernel on ARM using **ARM NEON SIMD intrinsics** (`<arm_neon.h>`).

---

## Problem Overview

The algorithm calculates a sliding window prefix sum over an input array of bytes (`uint8_t`) with a radius of $r = 13$ (diameter $2r + 1 = 27$ elements) and writes results into a 16-bit integer array (`uint16_t`):

$$\text{output}[pos] = \sum_{k = pos - radius}^{pos + radius} \text{input}[k]$$

### The Recurrence Bottleneck
In the scalar algorithm:
```cpp
for (; pos < limit; ++pos) {
  currentSum -= input[pos - radius - 1]; // Drop outgoing element
  currentSum += input[pos + radius];     // Add incoming element
  output[pos] = currentSum;
}
```
Because each iteration's `currentSum` strictly depends on the previous iteration's result, standard compilers cannot auto-vectorize this loop.

---

## ARM NEON Solution Architecture

To vectorize the sliding window, we process **8 elements simultaneously** using 128-bit NEON registers (`uint16x8_t`):

1. **Load & Widen 8 Elements**:
   - Outgoing values: `vld1_u8(subtract_ptr + i)` $\to$ `vmovl_u8(...)` gives 8 $\times$ `uint16_t`.
   - Incoming values: `vld1_u8(add_ptr + i)` $\to$ `vmovl_u8(...)` gives 8 $\times$ `uint16_t`.
   - Difference vector: `diff = vsubq_u16(add_16, sub_16)`.

2. **Logarithmic Parallel Prefix Scan (Kogge-Stone Algorithm)**:
   Instead of sequentially accumulating `diff` values, we perform a parallel prefix sum across the 8 vector lanes in 3 steps ($O(\log_2 8)$):
   - **Step 1 (shift by 1)**: `s1 = vextq_u16(zero, diff, 7)` $\to$ `delta = vaddq_u16(diff, s1)`
   - **Step 2 (shift by 2)**: `s2 = vextq_u16(zero, delta, 6)` $\to$ `delta = vaddq_u16(delta, s2)`
   - **Step 3 (shift by 4)**: `s4 = vextq_u16(zero, delta, 4)` $\to$ `delta = vaddq_u16(delta, s4)`

3. **Accumulate & Store**:
   - Add `delta` to the broadcasted base sum: `result = vaddq_u16(delta, current)`.
   - Store 8 results directly to memory: `vst1q_u16(output_ptr + i, result)`.

4. **Register-to-Register Feedback**:
   - Extract and broadcast the 7th lane directly inside NEON registers for the next batch:
     `current = vdupq_laneq_u16(result, 7);` (single instruction `dup v0.8h, v1.h[7]`).

---

## Benchmark Results

Benchmarks were executed on an Apple Silicon ARM64 CPU ($N = 40,000$ elements, 5 repetitions, Google Benchmark):

| Implementation | Mean Time | Median Time | StdDev | Speedup |
| :--- | :---: | :---: | :---: | :---: |
| **Baseline CPU (Scalar)** | **19.6 µs** | 19.6 µs | 0.08 µs | 1.00× (baseline) |
| **ARM NEON (Vectorized)** | **6.99 µs** | 6.97 µs | 0.04 µs | **2.80×** |

> **Performance Gain:** **~64.3% execution time reduction** (~2.80× faster) with 100% bit-exact correctness.

---

## How to Compile & Run with Clang

### 1. Run Validation
```bash
clang++ -O3 -std=c++17 -march=native -I. validate.cpp init.cpp solution.cpp -o validate
./validate
```

### 2. Run Google Benchmark
```bash
clang++ -O3 -std=c++17 -march=native \
  -I. -I$(brew --prefix)/include -L$(brew --prefix)/lib \
  bench.cpp init.cpp solution.cpp -lbenchmark -o lab

./lab --benchmark_repetitions=5
```
