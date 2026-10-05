#include "const.h"
#include "solution.h"
#include <arm_neon.h>
#include <vector>

std::vector<short> mandelbrot(int image_width, int image_height) {
    const int data_width = image_width + 2;
    const int data_height = image_height + 2;
    const float diameter_y = (float)kDiameterX / image_width * image_height;
    const float min_x = kCenterX - kDiameterX / 2.0f;
    const float max_x = kCenterX + kDiameterX / 2.0f;
    const float min_y = kCenterY - diameter_y / 2.0f;
    const float max_y = kCenterY + diameter_y / 2.0f;
    const float scale_x = (max_x - min_x) / data_width;
    const float scale_y = (max_y - min_y) / data_height;

    std::vector<short> result(data_width * data_height);

    float32x4_t v_min_x = vdupq_n_f32(min_x);
    float32x4_t v_min_y = vdupq_n_f32(min_y);
    float32x4_t v_scale_x = vdupq_n_f32(scale_x);
    float32x4_t v_scale_y = vdupq_n_f32(scale_y);
    float32x4_t v_bound = vdupq_n_f32(kSquareBound);
    uint32x4_t v_one = vdupq_n_u32(1);

    for (int py = 0; py < data_height; ++py) {
        float32x4_t v_py = vdupq_n_f32((float)py);
        float32x4_t v_cy = vmlaq_f32(v_min_y, v_py, v_scale_y);

        int px = 0;
        for (; px <= data_width - 4; px += 4) {
            float offsets[4] = {(float)px, (float)px+1, (float)px+2, (float)px+3};
            float32x4_t v_px_vec = vld1q_f32(offsets);
            float32x4_t v_cx = vmlaq_f32(v_min_x, v_px_vec, v_scale_x);

            float32x4_t v_zx = vdupq_n_f32(0.0f);
            float32x4_t v_zy = vdupq_n_f32(0.0f);

            // Track iteration counts for all 4 pixels independently
            uint32x4_t v_iters = vdupq_n_u32(0);

            // Mask to track which pixels are still "active"
            uint32x4_t v_active = vdupq_n_u32(0xFFFFFFFF);

            for (int iter = 0; iter < kMaxIterations; ++iter) {
                float32x4_t v_zxx = vmulq_f32(v_zx, v_zx);
                float32x4_t v_zyy = vmulq_f32(v_zy, v_zy);
                float32x4_t v_mag2 = vaddq_f32(v_zxx, v_zyy);

                //Are the pixels still <= kSquareBound?
                uint32x4_t v_cmp = vcleq_f32(v_mag2, v_bound);

                // Update active mask (only pixels that were already active and are still active stay active)
                v_active = vandq_u32(v_active, v_cmp);

                // If no pixels are active anymore, we can safely break out of the loop
                // vmaxvq_u32 returns the max value across all 4 lanes. If it's 0, all are inactive.
                if (vmaxvq_u32(v_active) == 0) {
                    break;
                }

                // Add 1 to the iteration count ONLY for the active pixels
                v_iters = vaddq_u32(v_iters, vandq_u32(v_active, v_one));

                // Continue the math updates
                float32x4_t v_zxy = vmulq_f32(v_zx, v_zy);
                v_zx = vaddq_f32(vsubq_f32(v_zxx, v_zyy), v_cx);
                v_zy = vaddq_f32(vaddq_f32(v_zxy, v_zxy), v_cy);
            }

            // Convert the four 32-bit integers into four 16-bit integers (shorts)
            uint16x4_t v_iters_short = vmovn_u32(v_iters);

            // Write all 4 results to memory at the exact right position
            vst1_u16(reinterpret_cast<uint16_t*>(&result[py * data_width + px]), v_iters_short);
        }

        //Scalar fallback: Clean up the last 1 to 3 pixels if data_width isn't a multiple of 4
        for (; px < data_width; ++px) {
            float c_x = min_x + px * scale_x;
            float c_y = min_y + py * scale_y;
            float z_x = 0.0f;
            float z_y = 0.0f;
            int iter = 0;
            for (; iter < kMaxIterations; ++iter) {
                float z_xx = z_x * z_x;
                float z_yy = z_y * z_y;
                if (z_xx + z_yy > kSquareBound) break;
                float z_xy = z_x * z_y;
                z_x = z_xx - z_yy + c_x;
                z_y = z_xy + z_xy + c_y;
            }
            result[py * data_width + px] = iter;
        }
    }
    return result;
}
