#include "bf16.h"

/* Dummies: every function returns 0. Replace with the real routines. */
uint16_t bf16_from_f32(uint32_t f32bits)
{
    uint32_t exp = (f32bits >> 23) & 0xffu;

    if (exp == 0xffu)
        return (uint16_t) (f32bits >> 16);

    uint32_t rounding = 0x7fffu + ((f32bits >> 16) & 1u);

    return (uint16_t) ((f32bits + rounding) >> 16);
}



uint16_t bf16_mul(uint16_t a, uint16_t b)
{
    uint32_t sign = (a ^ b) & 0x8000u;
    uint32_t ea = (a >> 7) & 0xffu;
    uint32_t eb = (b >> 7) & 0xffu;
    uint32_t fa = a & 0x7fu;
    uint32_t fb = b & 0x7fu;

    /* Handle NaN and infinity in operand order. */
    if (ea == 255u) {
        if (fa != 0)
            return a;
        if ((b & 0x7fffu) == 0)
            return 0x7fc0u;
        return (uint16_t) (sign | 0x7f80u);
    }

    if (eb == 255u) {
        if (fb != 0)
            return b;
        if ((a & 0x7fffu) == 0)
            return 0x7fc0u;
        return (uint16_t) (sign | 0x7f80u);
    }

    if ((a & 0x7fffu) == 0 || (b & 0x7fffu) == 0)
        return (uint16_t) sign;

    int exp_a = (int) ea;
    int exp_b = (int) eb;
    uint32_t ma = fa;
    uint32_t mb = fb;

    /* Normalize both significands. */
    if (exp_a != 0) {
        ma |= 0x80u;
    } else {
        exp_a = 1;
        while (ma < 0x80u) {
            ma <<= 1;
            exp_a--;
        }
    }

    if (exp_b != 0) {
        mb |= 0x80u;
    } else {
        exp_b = 1;
        while (mb < 0x80u) {
            mb <<= 1;
            exp_b--;
        }
    }

    uint32_t product = ma * mb;
    int exp = exp_a + exp_b - 127;

    if (product >= 0x8000u) {
        product >>= 8;
        exp++;
    } else {
        product >>= 7;
    }

    if (exp >= 255)
        return (uint16_t) (sign | 0x7f80u);

    if (exp <= 0) {
        if (exp < -6)
            return (uint16_t) sign;

        return (uint16_t) (sign | ((product & 0x7fu) >> (1 - exp)));
    }

    return (uint16_t) (sign | ((uint32_t) exp << 7) | (product & 0x7fu));
}



uint16_t bf16_sqrt(uint16_t a)
{
    uint32_t exp = (a >> 7) & 0xffu;
    uint32_t frac = a & 0x7fu;

    if (exp == 255u) {
        if (frac != 0)
            return a;
        if ((a & 0x8000u) != 0)
            return 0x7fc0u;
        return a;
    }

    if ((a & 0x7fffu) == 0)
        return 0;

    if ((a & 0x8000u) != 0)
        return 0x7fc0u;

    if (exp == 0)
        return 0;

    int e = (int) exp - 127;
    uint32_t m = 0x80u | frac;

    /* Make the unbiased exponent even. */
    if ((exp & 1u) == 0) {
        m <<= 1;
        e--;
    }

    /* Find the largest valid integer square root. */
    int low = 90;
    int high = 256;
    int best = 90;

    while (low <= high) {
        int mid = (low + high) >> 1;
        uint32_t square = (uint32_t) mid * (uint32_t) mid;

        if ((square >> 7) <= m) {
            best = mid;
            low = mid + 1;
        } else {
            high = mid - 1;
        }
    }

    int result_exp = e / 2 + 127;

    if (best >= 256) {
        best >>= 1;
        result_exp++;
    }

    if (result_exp >= 255)
        return 0x7f80u;

    if (result_exp <= 0)
        return 0;

    return (uint16_t) (((uint32_t) result_exp << 7) |
                       ((uint32_t) best & 0x7fu));
}
