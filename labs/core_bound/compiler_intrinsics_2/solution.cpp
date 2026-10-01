#include "solution.hpp"
#include <arm_neon.h>
#include <algorithm>
#include <bit>

inline uint16_t neon_movemask_epi8(uint8x16_t input) {
    static const uint8x16_t bit_mask = {
        1<<0, 1<<1, 1<<2, 1<<3, 1<<4, 1<<5, 1<<6, 1<<7,
        1<<0, 1<<1, 1<<2, 1<<3, 1<<4, 1<<5, 1<<6, 1<<7
    };

    // 2. Keep only the bits where the input had a match (0xFF)
    uint8x16_t minput = vandq_u8(input, bit_mask);

    // 3. Pairwise add the bytes together to accumulate the bits into the bottom of each 64-bit lane
    uint8x8_t tmp = vpadd_u8(vget_low_u8(minput), vget_high_u8(minput));
    tmp = vpadd_u8(tmp, tmp);
    tmp = vpadd_u8(tmp, tmp);

    // 4. Extract the cleanly accumulated 16 bits
    return vget_lane_u16(vreinterpret_u16_u8(tmp), 0);
}

unsigned solution(const std::string &inputContents) {
    size_t pos = 0;
    size_t len = inputContents.size();
    unsigned longestLine = 0;
    size_t curr_begin = 0;

    if (len >= 16) {
        // vdupq_n_u8 broadcasts a single byte to all 16 lanes (equivalent to _mm_set1_epi8)
        const uint8x16_t eol = vdupq_n_u8('\n');
        const char* ptr = inputContents.data();

        // Process in chunks of 16 bytes (128-bit NEON vector)
        for (; pos + 15 < len; pos += 16) {
            // vld1q_u8 loads 16 bytes from memory (equivalent to _mm_loadu_si128)
            uint8x16_t v = vld1q_u8(reinterpret_cast<const uint8_t*>(ptr + pos));

            // vceqq_u8 compares for equality. Returns 0xFF if true, 0x00 if false
            uint8x16_t v_mask = vceqq_u8(v, eol);

            // Convert the 16 bytes of 0xFF/0x00 into a 16-bit scalar integer
            uint32_t mask = neon_movemask_epi8(v_mask);

            while (mask) {
                uint32_t chars = std::__countr_zero(mask);

                size_t curr_len;
                if (pos < curr_begin) {
                    curr_len = chars;
                } else {
                    curr_len = (pos - curr_begin) + chars;
                }

                curr_begin += curr_len + 1;
                longestLine = std::max(longestLine, static_cast<unsigned>(curr_len));

                chars++;
                if (chars > 15) {
                    break;
                }
                mask >>= chars;
            }
        }
    }

    // Scalar fallback
    unsigned curLineLength = static_cast<unsigned>(pos - curr_begin);

    for (; pos < len; pos++) {
        if (inputContents[pos] == '\n') {
            longestLine = std::max(curLineLength, longestLine);
            curLineLength = 0;
            curr_begin = pos + 1;
        } else {
            curLineLength++;
        }
    }

    longestLine = std::max(curLineLength, longestLine);

    return longestLine;
}
