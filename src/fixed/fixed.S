
# Hand-written RV32I implementations for Q11.20 arithmetic.
# All functions are leaf functions; no stack space or CSR access.

    .text

    .globl  op1_asm
    .type   op1_asm, @function
    .align  2
op1_asm:
    li      t0, 0
    beqz    a1, .Lop1_done

.Lop1_loop:
    and     t1, a0, a1
    slli    t1, t1, 1
    xor     a0, a0, a1
    mv      a1, t1
    addi    t0, t0, 1
    bnez    a1, .Lop1_loop

.Lop1_done:
    sw      t0, 0(a2)
    ret

    .size   op1_asm, .-op1_asm


    .globl  op2_asm
    .type   op2_asm, @function
    .align  2
op2_asm:
    sub     a0, a0, a1
    ret

    .size   op2_asm, .-op2_asm


    .globl  op3_asm
    .type   op3_asm, @function
    .align  2
op3_asm:
    and     t0, a0, a1
    xor     a0, a0, a1
    srli    a0, a0, 1
    add     a0, a0, t0
    ret

    .size   op3_asm, .-op3_asm


    .globl  q_mul_asm
    .type   q_mul_asm, @function
    .align  2
q_mul_asm:
    beqz    a0, .Lq_zero
    beqz    a1, .Lq_zero

    # Signed product = unsigned product - correction * 2^32.
    srai    a2, a0, 31
    and     a2, a2, a1
    srai    a3, a1, 31
    and     a3, a3, a0
    add     a2, a2, a3

    # Initialize 64-bit shifted multiplicand.
    mv      t0, a0
    li      t1, 0

    # Initialize 64-bit accumulator.
    li      t2, 0
    sub     t3, zero, a2

.Lq_loop:
    andi    t4, a1, 1
    beqz    t4, .Lq_skip_add

    # Add the 64-bit shifted multiplicand.
    add     t4, t2, t0
    sltu    t5, t4, t2
    add     t3, t3, t1
    add     t3, t3, t5
    mv      t2, t4

.Lq_skip_add:
    # Move to the next multiplier bit.
    srli    a1, a1, 1
    beqz    a1, .Lq_round

    # Shift the 64-bit multiplicand left by one.
    srli    t5, t0, 31
    slli    t0, t0, 1
    slli    t1, t1, 1
    or      t1, t1, t5
    j       .Lq_loop

.Lq_round:
    # Add 2^19 for rounding.
    li      t4, 0x80000
    add     t5, t2, t4
    sltu    t4, t5, t2
    add     t3, t3, t4

    # Extract bits [51:20] of the rounded product.
    srli    t5, t5, 20
    slli    t3, t3, 12
    or      a0, t5, t3
    ret

.Lq_zero:
    li      a0, 0
    ret

    .size   q_mul_asm, .-q_mul_asm
