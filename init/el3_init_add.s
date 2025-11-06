/*------------------------------------------------------------------------------
 * el3.S - EL3 init + minimal GICv3 init for Raspberry Pi 4
 * GCC-compatible AArch64 assembly (no complex immediate expressions)
 *----------------------------------------------------------------------------*/

.section .bss
.align 14              // 2^14 = 16 KB alignment
idmap_table:
    .skip 0x4000      // 16 KB for 4-level translation tables

.section .text
.global el3_init_add
.type el3_init_add, %function

/* GICv3 register offsets */
.equ GICD_CTLR,       0x000
.equ GICD_ISENABLER0, 0x100
.equ GICR_WAKER,      0x14
.equ GICR_CTLR,       0x0

/* Base addresses for Pi4 */
.equ GICD_BASE, 0xFF841000
.equ GICR_BASE, 0xFF842000

/* EL3 stack (example) */
.equ EL3_STACK_TOP, 0x400000

el3_init_add:
    // ----------------------
    // Set up EL3 stack
    // ----------------------
    ldr x1, =EL3_STACK_TOP
    mov sp, x1

    // ----------------------
    // SCR_EL3: Read, set HCE (bit10) and RW (bit0), write back
    // Use small immediates (1 and 1024) which are encodable.
    // ----------------------
    mrs x0, S3_6_C1_C1_0       // scr_el3
    orr x0, x0, #1024          // set HCE (1 << 10)
    orr x0, x0, #1             // set RW  (1 << 0)
    msr S3_6_C1_C1_0, x0
    isb

    // ----------------------
    // TTBR0_EL3 and TTBR1_EL3 (point both to idmap_table)
    // ----------------------
    ldr x0, =idmap_table
    msr S3_6_C2_C0_0, x0       // ttbr0_el3
    msr S3_6_C2_C0_1, x0       // ttbr1_el3
    isb

    // ----------------------
    // TCR_EL3: 4KB granule, 48-bit VA
    // ----------------------
    // Precomputed numeric value for the chosen fields:
    //  TG1=0b00, SH1=0b11, ORGN1=0b01, IRGN1=0b01, T1SZ=0b11
    //  TG0=0b00, SH0=0b11, ORGN0=0b01, IRGN0=0b01, T0SZ=0b00
    //  value = 0x350035C0
    // Build the 64-bit register value using MOVZ/MOVK to avoid logical-immediate issues.
    // ----------------------
    movz x0, #0x35C0           // lower 16 bits
    movk x0, #0x3500, lsl #16 // upper 16 bits -> final 0x350035C0
    msr S3_6_C2_C0_2, x0       // tcr_el3
    isb

    // ----------------------
    // Enable MMU and caches: SCTLR_EL3
    // Set M (bit0), C (bit2), I (bit12)
    // We'll avoid attempting to OR big immediate masks directly:
    // - set M and C with immediate small ORR
    // - set I (bit12 = 4096) by building it in a temp register and ORR reg form
    // ----------------------
    mrs x0, S3_6_C1_C0_0       // sctlr_el3
    orr x0, x0, #1             // M = 1
    orr x0, x0, #4             // C = 1 (bit2)
    // set I (bit12) via register
    mov x2, #4096              // assembler will select an appropriate encoding (MOVZ)
    orr x0, x0, x2
    msr S3_6_C1_C0_0, x0
    isb

    // ----------------------
    // Disable timers temporarily
    // ----------------------
    msr CNTP_CTL_EL0, xzr
    msr CNTV_CTL_EL0, xzr

    // ----------------------
    // ===== GICv3 Initialization =====
    // We'll use register-form logical ops so we don't rely on logical immediates.
    // ----------------------

    // --- Enable GIC redistributor: clear ProcessorSleep (bit1) in GICR_WAKER ---
    ldr x0, =GICR_BASE
    ldr x1, [x0, #GICR_WAKER]   // x1 = GICR.WAKER
    // Build mask in x2 and do bic register-form
    mov x2, #2                  // mask for ProcessorSleep (bit1)
    bic x1, x1, x2              // x1 = x1 & ~2
    str x1, [x0, #GICR_WAKER]
1:  ldr x2, [x0, #GICR_WAKER]
    mov x3, #4                  // ChildrenAsleep bit = bit2
    tst x2, x3
    bne 1b                      // wait until ChildrenAsleep == 0

    // Enable redistributor forwarding: write GICR_CTLR = 1
    mov x1, #1
    str x1, [x0, #GICR_CTLR]

    // --- Enable GIC distributor ---
    ldr x0, =GICD_BASE
    mov x1, #1
    str x1, [x0, #GICD_CTLR]

    // Enable SGIs and PPIs (first 32 IRQs): write to GICD_ISENABLER0
    // Build 0xFFFFFFFF in registers; mov immediate may not accept 32-bit at once, but assembler will expand.
    // Using movz/movk is more explicit, but mov may be OK; for safety we'll build via movz/movk below.
    movz x1, #0xFFFF             // lower 16 bits = 0xFFFF
    movk x1, #0xFFFF, lsl #16   // x1 = 0xFFFFFFFF
    str x1, [x0, #GICD_ISENABLER0]

halt_loop:
    wfe
    b halt_loop
