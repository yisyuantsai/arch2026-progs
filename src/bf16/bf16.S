
# BF16 arithmetic using RV32I only.
# a0/a1: input bit patterns; a0: result bit pattern.

    .text

    .globl  bf16_from_f32_asm
    .type   bf16_from_f32_asm, @function
    .align  2
bf16_from_f32_asm:
    # Remove the sign bit and check exponent == 0xFF.
    slli    t0, a0, 1
    lui     t1, 0xff000
    bgeu    t0, t1, .Lf32_done

    # Round to nearest, ties to even.
    srli    t0, a0, 16
    andi    t0, t0, 1
    li      t1, 0x7fff
    add     t1, t1, t0
    add     a0, a0, t1

.Lf32_done:
    srli    a0, a0, 16
    ret

    .size   bf16_from_f32_asm, .-bf16_from_f32_asm


    .globl  bf16_mul_asm
    .type   bf16_mul_asm, @function
    .align  2
bf16_mul_asm:
    xor     t0, a0, a1
    li      t6, 0x8000
    and     t0, t0, t6

    srli    t1, a0, 7
    andi    t1, t1, 255
    srli    t2, a1, 7
    andi    t2, t2, 255
    andi    t3, a0, 127
    andi    t4, a1, 127

    li      t6, 255
    beq     t1, t6, .Lmul_special_a
    beq     t2, t6, .Lmul_special_b

    # Check zero operands.
    slli    t6, a0, 17
    beqz    t6, .Lmul_zero
    slli    t6, a1, 17
    beqz    t6, .Lmul_zero

    # Normalize the first significand.
    beqz    t1, .Lmul_denorm_a
    ori     t3, t3, 128

.Lmul_a_ready:
    # Normalize the second significand.
    beqz    t2, .Lmul_denorm_b
    ori     t4, t4, 128

.Lmul_b_ready:
    add     a2, t1, t2
    addi    a2, a2, -127

    # Eight-bit shift-and-add multiplication.
    li      t5, 0

.Lmul_product_loop:
    andi    t6, t4, 1
    beqz    t6, .Lmul_skip_add
    add     t5, t5, t3

.Lmul_skip_add:
    srli    t4, t4, 1
    beqz    t4, .Lmul_product_done
    slli    t3, t3, 1
    j       .Lmul_product_loop

.Lmul_product_done:
    # Normalize and truncate the product.
    li      t6, 0x8000
    bltu    t5, t6, .Lmul_product_small
    srli    t5, t5, 8
    addi    a2, a2, 1
    j       .Lmul_exponent

.Lmul_product_small:
    srli    t5, t5, 7

.Lmul_exponent:
    li      t6, 255
    bge     a2, t6, .Lmul_inf
    bge     zero, a2, .Lmul_subnormal

    slli    a2, a2, 7
    andi    t5, t5, 127
    or      a0, t0, a2
    or      a0, a0, t5
    ret

.Lmul_subnormal:
    li      t6, -6
    blt     a2, t6, .Lmul_zero
    li      t6, 1
    sub     t6, t6, a2
    andi    t5, t5, 127
    srl     t5, t5, t6
    or      a0, t0, t5
    ret

.Lmul_denorm_a:
    li      t1, 1

.Lmul_shift_a:
    li      t6, 128
    bgeu    t3, t6, .Lmul_a_ready
    slli    t3, t3, 1
    addi    t1, t1, -1
    j       .Lmul_shift_a

.Lmul_denorm_b:
    li      t2, 1

.Lmul_shift_b:
    li      t6, 128
    bgeu    t4, t6, .Lmul_b_ready
    slli    t4, t4, 1
    addi    t2, t2, -1
    j       .Lmul_shift_b

    # Special values: operand a is examined first.
.Lmul_special_a:
    bnez    t3, .Lmul_return_a
    slli    t6, a1, 17
    beqz    t6, .Lmul_nan
    j       .Lmul_inf

.Lmul_special_b:
    bnez    t4, .Lmul_return_b
    slli    t6, a0, 17
    beqz    t6, .Lmul_nan
    j       .Lmul_inf

.Lmul_return_a:
    ret

.Lmul_return_b:
    mv      a0, a1
    ret

.Lmul_zero:
    mv      a0, t0
    ret

.Lmul_inf:
    li      a0, 0x7f80
    or      a0, a0, t0
    ret

.Lmul_nan:
    li      a0, 0x7fc0
    ret

    .size   bf16_mul_asm, .-bf16_mul_asm


    .globl  bf16_sqrt_asm
    .type   bf16_sqrt_asm, @function
    .align  2
bf16_sqrt_asm:
    srli    t0, a0, 7
    andi    t0, t0, 255
    andi    t1, a0, 127

    li      t2, 255
    beq     t0, t2, .Lsqrt_special
    beqz    t0, .Lsqrt_subnormal_or_zero

    # Negative finite normals give a quiet NaN.
    srli    t2, a0, 15
    bnez    t2, .Lsqrt_nan

    # Extract unbiased exponent and significand.
    addi    t0, t0, -127
    addi    t1, t1, 128
    andi    t2, t0, 1
    beqz    t2, .Lsqrt_even_exp
    slli    t1, t1, 1
    addi    t0, t0, -1

.Lsqrt_even_exp:
    srai    t0, t0, 1
    addi    t0, t0, 127

    # Largest mid satisfying:
    # floor(mid * mid / 128) <= m
    # equals integer_sqrt(128 * (m + 1) - 1).
    addi    t1, t1, 1
    slli    t1, t1, 7
    addi    t1, t1, -1
    slli    t1, t1, 16

    # Digit-by-digit integer square root.
    li      t2, 0
    li      t3, 0
    li      t4, 8

.Lsqrt_digit_loop:
    srli    t5, t1, 30
    slli    t1, t1, 2
    slli    t3, t3, 2
    or      t3, t3, t5

    slli    t5, t2, 2
    ori     t5, t5, 1
    slli    t2, t2, 1

    bltu    t3, t5, .Lsqrt_skip_subtract
    sub     t3, t3, t5
    ori     t2, t2, 1

.Lsqrt_skip_subtract:
    addi    t4, t4, -1
    bnez    t4, .Lsqrt_digit_loop

    # Pack the resulting exponent and fraction.
    slli    t0, t0, 7
    andi    t2, t2, 127
    or      a0, t0, t2
    ret

.Lsqrt_special:
    bnez    t1, .Lsqrt_return
    srli    t2, a0, 15
    bnez    t2, .Lsqrt_nan

.Lsqrt_return:
    ret

.Lsqrt_subnormal_or_zero:
    srli    t2, a0, 15
    beqz    t2, .Lsqrt_zero
    beqz    t1, .Lsqrt_zero

.Lsqrt_nan:
    li      a0, 0x7fc0
    ret

.Lsqrt_zero:
    li      a0, 0
    ret

    .size   bf16_sqrt_asm, .-bf16_sqrt_asm
