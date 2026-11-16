# gcd_u32_asm: binary GCD, hand-written RV32I.
#
# a0: first operand and return value
# a1: second operand
# t0: number of shared factors of two
# t1: temporary value
#
# No calls, stack storage, or CSR access.

    .text

    .globl  gcd_u32_asm
    .type   gcd_u32_asm, @function
    .align  2
gcd_u32_asm:
    beq     a0, zero, .Lreturn_b
    beq     a1, zero, .Lreturn

    li      t0, 0
    or      t1, a0, a1
    andi    t1, t1, 1
    bne     t1, zero, .Lcheck_a

.Lcommon_twos:
    srli    a0, a0, 1
    srli    a1, a1, 1
    addi    t0, t0, 1
    or      t1, a0, a1
    andi    t1, t1, 1
    beq     t1, zero, .Lcommon_twos

.Lcheck_a:
    andi    t1, a0, 1
    bne     t1, zero, .Lcheck_b

.Lstrip_a:
    srli    a0, a0, 1
    andi    t1, a0, 1
    beq     t1, zero, .Lstrip_a

.Lcheck_b:
    andi    t1, a1, 1
    bne     t1, zero, .Lorder

.Lstrip_b:
    srli    a1, a1, 1
    andi    t1, a1, 1
    beq     t1, zero, .Lstrip_b

.Lorder:
    bgeu    a1, a0, .Lsubtract

    mv      t1, a0
    mv      a0, a1
    mv      a1, t1

.Lsubtract:
    sub     a1, a1, a0
    bne     a1, zero, .Lstrip_b

    sll     a0, a0, t0

.Lreturn:
    ret

.Lreturn_b:
    mv      a0, a1
    ret

    .size   gcd_u32_asm, .-gcd_u32_asm
