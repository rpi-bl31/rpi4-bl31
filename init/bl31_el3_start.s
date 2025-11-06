/* file: bl31_el3_start.S */

    .section .text
    .global _start
    .align 7

/* ----------------------
   Entry point
   ---------------------- */
_start:
    /* Set stack pointer for EL3 */
    ldr x0, =stack_top
    mov sp, x0

    /* EL3 CPU setup */
    bl el3_setup

    /* Set exception vectors */
    ldr x0, =el3_vectors
    msr VBAR_EL3, x0
    isb

    /* Call the next stage in BL31 */
    bl bl31_main

    /* Should never return, loop if it does */
1:  wfe
    b 1b

/* ----------------------
   EL3 CPU setup
   ---------------------- */
el3_setup:
    /* Disable interrupts temporarily */
    mov x0, #0
    msr DAIF, x0

    /* Configure SCR_EL3 (secure config) */
    mrs x1, SCR_EL3
    /* Example: keep things mostly default for now */
    msr SCR_EL3, x1
    isb

    ret

/* ----------------------
   Exception Vector Table (EL3)
   ---------------------- */
    .align 11          /* 2KB alignment for VBAR */
el3_vectors:
    /* Each exception type branches to its handler */
    b el3_sync_handler     /* Synchronous */
    b el3_irq_handler      /* IRQ */
    b el3_fiq_handler      /* FIQ */
    b el3_serror_handler   /* SError */

    /* Fill remaining vector slots with default sync handler */
    .rept 4
        b el3_sync_handler
    .endr

/* ----------------------
   Register save/restore macros
   ---------------------- */
.macro SAVE_REGS
    stp x0, x1, [sp, #-16]!
    stp x2, x3, [sp, #-16]!
    stp x4, x5, [sp, #-16]!
    stp x6, x7, [sp, #-16]!
    stp x8, x9, [sp, #-16]!
    stp x10, x11, [sp, #-16]!
    stp x12, x13, [sp, #-16]!
    stp x14, x15, [sp, #-16]!
    stp x16, x17, [sp, #-16]!
    stp x18, x19, [sp, #-16]!
    stp x20, x21, [sp, #-16]!
    stp x22, x23, [sp, #-16]!
    stp x24, x25, [sp, #-16]!
    stp x26, x27, [sp, #-16]!
    stp x28, x29, [sp, #-16]!
    str x30, [sp, #-8]!
.endm

.macro RESTORE_REGS
    ldr x30, [sp], #8
    ldp x28, x29, [sp], #16
    ldp x26, x27, [sp], #16
    ldp x24, x25, [sp], #16
    ldp x22, x23, [sp], #16
    ldp x20, x21, [sp], #16
    ldp x18, x19, [sp], #16
    ldp x16, x17, [sp], #16
    ldp x14, x15, [sp], #16
    ldp x12, x13, [sp], #16
    ldp x10, x11, [sp], #16
    ldp x8, x9, [sp], #16
    ldp x6, x7, [sp], #16
    ldp x4, x5, [sp], #16
    ldp x2, x3, [sp], #16
    ldp x0, x1, [sp], #16
.endm

/* ----------------------
   Exception Handlers
   ---------------------- */

el3_sync_handler:
    SAVE_REGS
    mrs x0, ESR_EL3        /* Exception info */
    mrs x1, ELR_EL3        /* Return address */
    /* TODO: process exception or log */
    /* For now, loop but structured for extension */
1:  wfe
    b 1b
    RESTORE_REGS
    eret

el3_irq_handler:
    SAVE_REGS
    mrs x0, ESR_EL3
    /* IRQ handling logic can go here */
1:  wfe
    b 1b
    RESTORE_REGS
    eret

el3_fiq_handler:
    SAVE_REGS
    mrs x0, ESR_EL3
    /* FIQ handling logic */
1:  wfe
    b 1b
    RESTORE_REGS
    eret

el3_serror_handler:
    SAVE_REGS
    mrs x0, ESR_EL3
    /* SError handling */
1:  wfe
    b 1b
    RESTORE_REGS
    eret

/* ----------------------
   BL31 next init stages
   ---------------------- */
    .global bl31_main
bl31_main:
    /* call next BL31 code */
    b el3_mmu_setup
    b el3_init_add
    b el3_setup_misc
    mov x0, #0
    ret

/* ----------------------
   Stack for EL3
   ---------------------- */
    .section .bss
    .align 16
stack_bottom:
    .space 0x2000        /* 8 KB stack */
stack_top:
