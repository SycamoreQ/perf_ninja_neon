#include "solution.h"
#include <algorithm>
#include <arm_neon.h>
#include <memory>

void imageSmoothing(const InputVector &input, uint8_t radius,
                    OutputVector &output) {
  int pos = 0;
  int currentSum = 0;
  int size = static_cast<int>(input.size());

  // 1. left border - time spent in this loop can be ignored (radius is small)
  for (int i = 0; i < std::min<int>(size, radius); ++i) {
    currentSum += input[i];
  }

  int limit = std::min(radius + 1, size - radius);
  for (pos = 0; pos < limit; ++pos) {
    currentSum += input[pos + radius];
    output[pos] = currentSum;
  }

  // 2. main loop - vectorized with ARM NEON intrinsics
  limit = size - radius;
  const uint8_t *subtract_ptr = input.data() + pos - radius - 1;
  const uint8_t *add_ptr = input.data() + pos + radius;
  uint16_t *output_ptr = output.data() + pos;

  // Broadcast currentSum into all 8 lanes of a 128-bit vector register
  uint16x8_t current = vdupq_n_u16(static_cast<uint16_t>(currentSum));
  const uint16x8_t zero = vdupq_n_u16(0);

  int i = 0;
  // Process 8 elements (uint16_t x 8 = 128 bits) per iteration
  for (; i + 7 + pos < limit; i += 8) {
    // Load 8 uint8 values dropped from the window and 8 newly added
    uint8x8_t sub_8 = vld1_u8(subtract_ptr + i);
    uint8x8_t add_8 = vld1_u8(add_ptr + i);

    // Widen uint8_t (8 lanes) to uint16_t (8 lanes)
    uint16x8_t sub_16 = vmovl_u8(sub_8);
    uint16x8_t add_16 = vmovl_u8(add_8);

    // Compute diff: add - sub for each of the 8 positions
    uint16x8_t diff = vsubq_u16(add_16, sub_16);

    // Parallel prefix sum on 8 lanes (Kogge-Stone scan pattern)
    // Step 1: Shift right by 1 element and accumulate
    uint16x8_t s1 = vextq_u16(zero, diff, 7);
    uint16x8_t delta = vaddq_u16(diff, s1);

    // Step 2: Shift right by 2 elements and accumulate
    uint16x8_t s2 = vextq_u16(zero, delta, 6);
    delta = vaddq_u16(delta, s2);

    // Step 3: Shift right by 4 elements and accumulate
    uint16x8_t s4 = vextq_u16(zero, delta, 4);
    delta = vaddq_u16(delta, s4);

    // Add prefix-sum delta to baseline current
    uint16x8_t result = vaddq_u16(delta, current);

    // Store 8 results to output memory
    vst1q_u16(output_ptr + i, result);

    // Broadcast the last lane (lane 7) as the base sum for the next iteration
    current = vdupq_laneq_u16(result, 7);
  }

  // Sync back currentSum to scalar for any remainder elements
  if (i > 0) {
    currentSum = static_cast<int>(vgetq_lane_u16(current, 0));
  }
  pos += i;

  // Scalar tail loop for remaining elements that did not fill a block of 8
  for (; pos < limit; ++pos) {
    currentSum -= input[pos - radius - 1];
    currentSum += input[pos + radius];
    output[pos] = currentSum;
  }

  // 3. special case, executed only if size <= 2*radius + 1
  limit = std::min(radius + 1, size);
  for (; pos < limit; pos++) {
    output[pos] = currentSum;
  }

  // 4. right border - time spent in this loop can be ignored
  for (; pos < size; ++pos) {
    currentSum -= input[pos - radius - 1];
    output[pos] = currentSum;
  }
}
