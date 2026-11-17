/* Assignment 2 Rubik solver, hand-written RV32I (no M/F/C or runtime calls).
 * Reuses Assignment 1 permutation/orientation move and distance tables.
 * The final four moves use a small exact, sorted near-goal table.
 *
 * a0 = state string, a1 = output, a2 = capacity
 * Returns: shortest length, -1 invalid state, -2 output too small.
 */
    .option norelax
    .text
    .align 2
    .globl rubik_solve_asm
    .type rubik_solve_asm, @function
rubik_solve_asm:
    addi sp, sp, -80
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)
    sw s2, 12(sp)
    sw s3, 16(sp)
    sw s4, 20(sp)
    sw s5, 24(sp)
    sw s6, 28(sp)
    sw s7, 32(sp)
    sw s8, 36(sp)
    sw s9, 40(sp)
    sw s10, 44(sp)
    sw s11, 48(sp)
    sw a1, 52(sp)
    sw a2, 56(sp)

    jal ra, .Lparse_rank
    li t0, -1
    beq a0, t0, .Lreturn_invalid
    mv s10, a0                         /* root permutation rank */
    mv s11, a1                         /* root orientation rank */

    la s3, asm_solution
    la s4, asm_allowed_moves
    la s5, asm_near4_states
    la s6, perm_move
    la s7, ori_move
    la s8, perm_dist_packed
    la s9, ori_dist_packed
    sw zero, 64(sp)                   /* prefix length is normally 0 */

    /* Use the exact first move for any one of the 2,644 depth-11 states. */
    slli a0, s10, 10
    or a0, a0, s11
    jal ra, .Lnear11_find
    li t0, -1
    beq a0, t0, .Lno_prefix
    andi t5, a0, 15                 /* first move toward solved */
    sb t5, 0(s3)
    slli t0, s10, 4
    slli t1, s10, 1
    add t0, t0, t1
    slli t2, t5, 1
    add t0, t0, t2
    add t0, t0, s6
    lhu t0, 0(t0)
    slli t1, s11, 4
    slli t2, s11, 1
    add t1, t1, t2
    slli t2, t5, 1
    add t1, t1, t2
    add t1, t1, s7
    lhu s11, 0(t1)
    mv s10, t0
    addi s3, s3, 1
    li t0, 1
    sw t0, 64(sp)
.Lno_prefix:
    srli t0, s10, 1
    add t0, s8, t0
    lbu t0, 0(t0)
    andi t1, s10, 1
    slli t1, t1, 2
    srl t0, t0, t1
    andi t0, t0, 15
    srli t1, s11, 1
    add t1, s9, t1
    lbu t1, 0(t1)
    andi t2, s11, 1
    slli t2, t2, 2
    srl t1, t1, t2
    andi t1, t1, 15
    mv s1, t0
    bgeu s1, t1, .Lnew_bound
    mv s1, t1

.Lnew_bound:
    li t0, 11
    bgtu s1, t0, .Lreturn_invalid
    li s0, 0                          /* depth */
    la s2, asm_ida_stack             /* current frame (8 bytes) */
    sh s10, 0(s2)
    sh s11, 2(s2)
    li t0, 3                          /* root row in move table */
    sb t0, 4(s2)
    sb zero, 5(s2)

.Lsearch_loop:
    lhu t0, 0(s2)                    /* current p */
    lhu t1, 2(s2)                    /* current o */
    or t2, t0, t1
    beqz t2, .Lfound_at_depth

    sub t2, s1, s0                   /* steps remaining under bound */
    li t3, 4
    bgtu t2, t3, .Lexpand

    /* Exact four-move cutoff: key = (p << 10) | o. */
    slli a0, t0, 10
    or a0, a0, t1
    jal ra, .Lnear4_find
    li t3, -1
    beq a0, t3, .Lbacktrack
    srli t3, a0, 4
    andi t3, t3, 15                 /* exact remaining distance */
    bgtu t3, t2, .Lbacktrack

    add a7, s0, t3                   /* full optimal solution length */
    mv t4, s0                        /* output move index */
    mv t5, t0                        /* current p */
    mv t6, t1                        /* current o */
    mv a6, a0                        /* packed near-goal entry */
.Lfinish_loop:
    srli t3, a6, 4
    andi t3, t3, 15
    beqz t3, .Lfound_exact
    andi t3, a6, 15                 /* next move toward solved */
    add a0, s3, t4
    sb t3, 0(a0)

    slli a1, t5, 4                  /* p * 18 = p * 16 + p * 2 */
    slli a2, t5, 1
    add a1, a1, a2
    slli a2, t3, 1
    add a1, a1, a2
    add a1, a1, s6
    lhu t5, 0(a1)

    slli a1, t6, 4                  /* o * 18 + move * 2 */
    slli a2, t6, 1
    add a1, a1, a2
    slli a2, t3, 1
    add a1, a1, a2
    add a1, a1, s7
    lhu t6, 0(a1)

    addi t4, t4, 1
    slli a0, t5, 10
    or a0, a0, t6
    jal ra, .Lnear4_find
    mv a6, a0
    j .Lfinish_loop

.Lfound_exact:
    mv a0, a7
    j .Lfound
.Lfound_at_depth:
    mv a0, s0
    j .Lfound

.Lexpand:
    lbu t2, 4(s2)                   /* previous face row */
    lbu t3, 5(s2)                   /* next candidate index */
    slli t4, t2, 4                  /* 16-byte row stride */
    add t4, t4, t3
    add t4, t4, s4
    lbu t4, 0(t4)                   /* high nibble: next face */
    li t5, 255                      /* end-of-row sentinel */
    beq t4, t5, .Lbacktrack
    addi t3, t3, 1
    sb t3, 5(s2)

    andi t5, t4, 15                 /* move number 0..8 */
    srli t6, t4, 4                  /* next previous-face index */

    slli a1, t0, 4
    slli a2, t0, 1
    add a1, a1, a2
    slli a2, t5, 1
    add a1, a1, a2
    add a1, a1, s6
    lhu t2, 0(a1)                   /* next p */

    slli a1, t1, 4
    slli a2, t1, 1
    add a1, a1, a2
    slli a2, t5, 1
    add a1, a1, a2
    add a1, a1, s7
    lhu t3, 0(a1)                   /* next o */

    srli a1, t2, 1
    add a1, s8, a1
    lbu a1, 0(a1)
    andi a2, t2, 1
    slli a2, a2, 2
    srl a1, a1, a2
    andi a1, a1, 15
    srli a2, t3, 1
    add a2, s9, a2
    lbu a2, 0(a2)
    andi a3, t3, 1
    slli a3, a3, 2
    srl a2, a2, a3
    andi a2, a2, 15
    bgeu a1, a2, .Lheur_ready
    mv a1, a2
.Lheur_ready:
    addi a2, s0, 1
    add a1, a1, a2
    bgtu a1, s1, .Lsearch_loop      /* admissible-heuristic prune */

    add a1, s3, s0
    sb t5, 0(a1)
    addi s0, s0, 1
    addi s2, s2, 8
    sh t2, 0(s2)
    sh t3, 2(s2)
    sb t6, 4(s2)
    sb zero, 5(s2)
    j .Lsearch_loop

.Lbacktrack:
    beqz s0, .Lnext_bound
    addi s0, s0, -1
    addi s2, s2, -8
    j .Lsearch_loop
.Lnext_bound:
    addi s1, s1, 1
    j .Lnew_bound

/* Binary search only the sparse distance-11 root states. */
.Lnear11_find:
    li a1, 0
    li a2, 2644
    la a6, asm_near11_states
.Lnear11_loop:
    bgeu a1, a2, .Lnear11_absent
    add a3, a1, a2
    srli a3, a3, 1
    slli a4, a3, 2
    add a4, a4, a6
    lw a4, 0(a4)
    srli a5, a4, 4
    bltu a5, a0, .Lnear11_higher
    bltu a0, a5, .Lnear11_lower
    mv a0, a4
    ret
.Lnear11_higher:
    addi a1, a3, 1
    j .Lnear11_loop
.Lnear11_lower:
    mv a2, a3
    j .Lnear11_loop
.Lnear11_absent:
    li a0, -1
    ret

/* Binary search the 2232 packed, sorted exact near-goal states.
 * Input a0 = key, returns packed entry or -1.
 * Does not clobber t0..t6, a6 or a7 (used by the finishing loop).
 */
.Lnear4_find:
    srli a1, a0, 14                /* bucket: permutation >> 4 */
    slli a1, a1, 1
    la a2, asm_near4_index
    add a1, a1, a2
    lhu a2, 2(a1)                  /* exclusive upper index */
    lhu a1, 0(a1)                  /* inclusive lower index */
.Lnear4_loop:
    bgeu a1, a2, .Lnear4_absent
    add a3, a1, a2
    srli a3, a3, 1
    slli a4, a3, 2
    add a4, a4, s5
    lw a4, 0(a4)
    srli a5, a4, 8
    bltu a5, a0, .Lnear4_higher
    bltu a0, a5, .Lnear4_lower
    mv a0, a4
    ret
.Lnear4_higher:
    addi a1, a3, 1
    j .Lnear4_loop
.Lnear4_lower:
    mv a2, a3
    j .Lnear4_loop
.Lnear4_absent:
    li a0, -1
    ret

/* Convert permutation/orientation digits to compact ranks.
 * Uses only caller-saved registers; returns a0=p, a1=o, or a0=-1.
 */
.Lparse_rank:
    beqz a0, .Lparse_invalid
    mv t0, a0
    la t1, asm_perms
    li t2, 0
    li t4, 0                          /* seen-cubie bitmap */
.Lparse_perm_loop:
    li t6, 7
    bgeu t2, t6, .Lparse_ori_begin
    lbu t3, 0(t0)
    addi t3, t3, -49
    bgeu t3, t6, .Lparse_invalid
    li a2, 1
    sll a2, a2, t3
    and a3, a2, t4
    bnez a3, .Lparse_invalid
    or t4, t4, a2
    sb t3, 0(t1)
    addi t0, t0, 1
    addi t1, t1, 1
    addi t2, t2, 1
    j .Lparse_perm_loop

.Lparse_ori_begin:
    li t2, 0
    li t5, 0                          /* orientation sum modulo 3 */
    li a1, 0                          /* orientation rank */
.Lparse_ori_loop:
    li t6, 7
    bgeu t2, t6, .Lparse_ori_done
    lbu t3, 0(t0)
    addi t3, t3, -49
    li t4, 3
    bgeu t3, t4, .Lparse_invalid
    add t5, t5, t3
    bltu t5, t4, .Lparse_sum_ok
    addi t5, t5, -3
.Lparse_sum_ok:
    li t4, 6
    bgeu t2, t4, .Lparse_ori_skip_rank
    slli t4, a1, 1
    add a1, a1, t4
    add a1, a1, t3
.Lparse_ori_skip_rank:
    addi t0, t0, 1
    addi t2, t2, 1
    j .Lparse_ori_loop
.Lparse_ori_done:
    lbu t3, 0(t0)
    bnez t3, .Lparse_invalid
    bnez t5, .Lparse_invalid

    la t0, asm_perms
    li t2, 0
    li a0, 0
.Lrank_outer:
    li t6, 6
    bgeu t2, t6, .Lparse_success
    lbu t3, 0(t0)
    addi t1, t0, 1
    li t4, 0
    sub t5, t6, t2                  /* number of entries to the right */
.Lrank_inner:
    beqz t5, .Lrank_digit_done
    lbu t6, 0(t1)
    bgeu t6, t3, .Lrank_not_smaller
    addi t4, t4, 1
.Lrank_not_smaller:
    addi t1, t1, 1
    addi t5, t5, -1
    j .Lrank_inner
.Lrank_digit_done:
    li t6, 7
    sub t6, t6, t2                  /* mixed-radix factor 7-i */
    mv a2, a0
    li a0, 0
.Lrank_multiply:
    beqz t6, .Lrank_mul_done
    add a0, a0, a2                  /* small constant multiply, RV32I */
    addi t6, t6, -1
    j .Lrank_multiply
.Lrank_mul_done:
    add a0, a0, t4
    addi t0, t0, 1
    addi t2, t2, 1
    j .Lrank_outer
.Lparse_success:
    ret
.Lparse_invalid:
    li a0, -1
    li a1, 0
    ret

/* Produce the exact move spelling without division or multiply. */
.Lfound:
    lw t1, 64(sp)
    add a0, a0, t1
    la s3, asm_solution
    sw a0, 60(sp)                    /* move count */
    mv t2, zero
    mv t1, zero                      /* formatted string length */
    beqz a0, .Lcheck_capacity
    addi t1, a0, -1                  /* spaces between moves */
    la t6, asm_move_pair
.Lmeasure_loop:
    add t3, s3, t2
    lbu t4, 0(t3)
    slli t4, t4, 1
    add t4, t4, t6
    lbu t5, 1(t4)
    addi t1, t1, 1                   /* face letter */
    beqz t5, .Lmeasure_no_suffix
    addi t1, t1, 1
.Lmeasure_no_suffix:
    addi t2, t2, 1
    bltu t2, a0, .Lmeasure_loop
.Lcheck_capacity:
    lw t0, 56(sp)
    bgeu t1, t0, .Lreturn_small
    lw t0, 52(sp)
    lw t1, 60(sp)
    li t2, 0
    la t6, asm_move_pair
.Lformat_loop:
    bgeu t2, t1, .Lformat_done
    beqz t2, .Lformat_no_space
    li t3, 32
    sb t3, 0(t0)
    addi t0, t0, 1
.Lformat_no_space:
    add t3, s3, t2
    lbu t4, 0(t3)
    slli t4, t4, 1
    add t4, t4, t6
    lbu t5, 0(t4)
    sb t5, 0(t0)
    addi t0, t0, 1
    lbu t5, 1(t4)
    beqz t5, .Lformat_no_suffix
    sb t5, 0(t0)
    addi t0, t0, 1
.Lformat_no_suffix:
    addi t2, t2, 1
    j .Lformat_loop
.Lformat_done:
    sb zero, 0(t0)
    lw a0, 60(sp)
    j .Lreturn
.Lreturn_small:
    beqz t0, .Lsmall_no_write
    lw t1, 52(sp)
    sb zero, 0(t1)
.Lsmall_no_write:
    li a0, -2
    j .Lreturn
.Lreturn_invalid:
    li a0, -1
.Lreturn:
    lw ra, 0(sp)
    lw s0, 4(sp)
    lw s1, 8(sp)
    lw s2, 12(sp)
    lw s3, 16(sp)
    lw s4, 20(sp)
    lw s5, 24(sp)
    lw s6, 28(sp)
    lw s7, 32(sp)
    lw s8, 36(sp)
    lw s9, 40(sp)
    lw s10, 44(sp)
    lw s11, 48(sp)
    addi sp, sp, 80
    ret
    .size rubik_solve_asm, .-rubik_solve_asm

    .section .rodata
    .balign 4
/* A row is 16 bytes; 0xff marks the end. High nibble is next face index. */
asm_allowed_moves:
    .byte 0x13,0x14,0x15,0x26,0x27,0x28,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff
    .byte 0x00,0x01,0x02,0x26,0x27,0x28,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff
    .byte 0x00,0x01,0x02,0x13,0x14,0x15,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff
    .byte 0x00,0x01,0x02,0x13,0x14,0x15,0x26,0x27,0x28,0xff,0xff,0xff,0xff,0xff,0xff,0xff
asm_move_pair:
    .byte 82,0, 82,50, 82,39, 66,0, 66,50, 66,39, 68,0, 68,50, 68,39

    .section .bss
    .balign 4
asm_perms:
    .space 8
asm_solution:
    .space 12
    .balign 4
asm_ida_stack:
    .space 96

/* Original Assignment 1 transition/heuristic tables, and small exact table. */
    .include "src/rubik/tables_compact.inc"
    .include "src/rubik/near11_generated.inc"
    .include "src/rubik/near4_generated.inc"
