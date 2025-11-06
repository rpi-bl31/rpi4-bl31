.section .text
    .global smc_entry
    .align  4

// smc_entry:
// Save caller registers (x0..x7) in a stack frame, call C dispatcher,
// then restore x0..x3 for return values and ERET back to non-secure.
// Assumes EL3 stack is already initialized.

smc_entry:
    // Reserve 192 bytes for the frame (aligned). Enough to hold saved regs.
    sub     sp, sp, #192

    // Save callee-saved frame pointer for C
    stp     x29, x30, [sp, #160]      // x29/x30 at top of frame
    add     x29, sp, #160

    // Save x0..x7 into frame (8 regs, 8*8 = 64 bytes)
    stp     x0, x1, [sp, #0]
    stp     x2, x3, [sp, #16]
    stp     x4, x5, [sp, #32]
    stp     x6, x7, [sp, #48]

    // Also save additional scratch regs we may clobber in C (x9..x12)
    stp     x9, x10, [sp, #64]
    stp     x11, x12, [sp, #80]

    // Pass pointer to saved frame (sp) as first arg to C dispatcher
    mov     x0, sp
    bl      smc_dispatch_c

    // After C returns, restored results are kept in saved slots.
    // Restore x0..x3 from frame (these will be returned to caller)
    ldp     x0, x1, [sp, #0]
    ldp     x2, x3, [sp, #16]

    // Restore scratch regs and frame pointer/return addr.
    ldp     x9, x10, [sp, #64]
    ldp     x11, x12, [sp, #80]
    ldp     x29, x30, [sp, #160]

    // Deallocate frame
    add     sp, sp, #192

    // Return to lower world
    eret

    .size smc_entry, .-smc_entry