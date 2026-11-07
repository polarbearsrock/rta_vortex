#include <stdint.h>
#include <stdio.h>
#include "softfloat.h"

int main(void) {
    const uint_fast8_t modes[] = {softfloat_round_near_even, softfloat_round_minMag,
                                 softfloat_round_min, softfloat_round_max};
    unsigned a, b, c, mode;
    softfloat_detectTininess = softfloat_tininess_afterRounding;
    while (scanf("%x %x %x %u", &a, &b, &c, &mode) == 4) {
        if (mode >= 4) return 2;
        softfloat_roundingMode = modes[mode];
        softfloat_exceptionFlags = 0;
        float32_t x = {a}, y = {b}, z = {c};
        uint32_t result = f32_mulAdd(x, y, z).v;
        if ((result & 0x7fffffff) > 0x7f800000) result = 0x7fc00000;
        printf("%08x %02x\n", result, (unsigned)softfloat_exceptionFlags);
    }
    return 0;
}
