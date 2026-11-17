#include "fixed.h"

uint32_t op1(uint32_t a, uint32_t b, int *n)
{
    int passes = 0;
    while (b != 0) {
        uint32_t carry = (a & b) << 1;
        a ^= b;
        b = carry;
        passes++;
    }
    *n = passes;
    return a;
}

uint32_t op2(uint32_t a, uint32_t b)
{
    return a - b;
}

uint32_t op3(uint32_t a, uint32_t b)
{
    return (a & b) + ((a ^ b) >> 1);
}

int32_t q_mul(int32_t a, int32_t b)
{
    uint32_t ua = (uint32_t) a;
    uint32_t ub = (uint32_t) b;
    uint32_t al = ua & 0xffffu;
    uint32_t ah = ua >> 16;
    uint32_t bl = ub & 0xffffu;
    uint32_t bh = ub >> 16;

    /* Four 16-by-16 products avoid the unavailable 64-bit multiply. */
    uint64_t product = (uint64_t) (al * bl) + ((uint64_t) (al * bh) << 16) +
                       ((uint64_t) (ah * bl) << 16) +
                       ((uint64_t) (ah * bh) << 32);

    /* Correct the unsigned product to the signed two's-complement one. */
    uint32_t correction =
        ((0u - (uint32_t) (a < 0)) & ub) + ((0u - (uint32_t) (b < 0)) & ua);
    product -= (uint64_t) correction << 32;

    /* Unsigned shift has the same low 32 bits as an arithmetic shift. */
    return (int32_t) (uint32_t) ((product + (UINT64_C(1) << 19)) >> 20);
}
