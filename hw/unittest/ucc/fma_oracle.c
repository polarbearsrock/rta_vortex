#include <fenv.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

int main(void) {
    const int modes[] = {FE_TONEAREST, FE_TOWARDZERO, FE_DOWNWARD, FE_UPWARD};
    unsigned a, b, c, mode;
    while (scanf("%x %x %x %u", &a, &b, &c, &mode) == 4) {
        float x, y, z, result;
        uint32_t bits;
        memcpy(&x, &a, 4);
        memcpy(&y, &b, 4);
        memcpy(&z, &c, 4);
        if (mode >= 4 || fesetround(modes[mode])) return 2;
        feclearexcept(FE_ALL_EXCEPT);
        result = fmaf(x, y, z);
        const int flags = fetestexcept(FE_ALL_EXCEPT);
        memcpy(&bits, &result, 4);
        if ((bits & 0x7fffffff) > 0x7f800000) bits = 0x7fc00000;
        const unsigned encoded = !!(flags & FE_INEXACT) | (!!(flags & FE_UNDERFLOW) << 1)
            | (!!(flags & FE_OVERFLOW) << 2) | (!!(flags & FE_DIVBYZERO) << 3)
            | (!!(flags & FE_INVALID) << 4);
        printf("%08x %02x\n", bits, encoded);
    }
    return 0;
}
