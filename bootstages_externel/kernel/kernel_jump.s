.section .text
    .globl  bl31_jump_to_kernel_pi4_robust
    .align  7
bl31_jump_to_kernel_pi4_robust:
    //
    // Inputs (these constants / labels below are placeholders — replace
    // with the real addresses or make them dynamic by reading the armstub
    // area if you prefer):
    //   kernel_phys_addr -> physical address where the Linux Image entry is.
    //   fdt_phys_addr    -> physical address of DTB (must be in RAM).
    //   kernel_size      -> size of kernel (for cache clean loop; optional).
    //
    // This code:
    //  - sets SCR_EL3 to non-secure/AArch64 and enables HVC
    //  - builds SPSR_EL3 for EL2h with all exceptions masked
    //  - sets up a minimal EL2 context: SP_EL2, clears SCTLR_EL2 (MMU OFF),
    //    clears relevant registers, sets HCR_EL2 to a safe value
    //  - performs minimal cache maintenance for kernel image range (optional)
    //  - sets ELR_EL3 to the kernel entry and puts DTB in x0
    //  - ERET to drop to non-secure EL2h and start kernel
    //

    // --- load addresses (replace with your actual symbols or make dynamic)
    adrp    x10, kernel_phys_addr
    add     x10, x10, :lo12:kernel_phys_addr    // x10 = kernel entry (phys)
    adrp    x11, fdt_phys_addr
    add     x11, x11, :lo12:fdt_phys_addr        // x11 = DTB phys

    // -----------------------
    // SCR_EL3: Make lower EL non-secure, AArch64
    // NS (bit0)=1, HCE(bit8)=1, RW(bit10)=1 => 0x501
    // OR with existing scr_el3 to preserve platform bits where appropriate.
    // -----------------------
    mrs     x12, scr_el3
    movz    x13, #0x501
    orr     x12, x12, x13
    msr     scr_el3, x12

    // -----------------------
    // SPSR_EL3: target EL2h, mask all exceptions (DAIF=1)
    // Mode EL2h = 0b0101 ; DAIF mask bits set -> value = 0x3C0 | 0x5 = 0x3C5
    // -----------------------
    movz    x14, #0x3C5
    msr     spsr_el3, x14

    // -----------------------
    // Prepare minimal EL2 context
    //  - SP_EL2 -> a reserved stack area
    //  - SCTLR_EL2 = 0 (MMU OFF per kernel requirements)
    //  - HCR_EL2 = 0 (do not force traps)
    //  - CPTR_EL2, CPTR_EL3 etc. left default (TF-A does platform hardening)
    // -----------------------
    adrp    x15, el2_stack_top
    add     x15, x15, :lo12:el2_stack_top
    msr     sp_el2, x15

    movz    x16, #0
    msr     sctlr_el2, x16      // MMU OFF for target EL (kernel requires MMU off)
    msr     hcr_el2,  x16       // minimal HCR_EL2
    msr     cpacr_el1, x16      // optional: clear trap bits (safe default)

    // -----------------------
    // Cache maintenance: ensure kernel image is clean to PoC and I-cache
    // invalidated. Kernel doc requires D-cache clean and no stale I-cache.
    //
    // We do a minimal clean by VA to PoC on the kernel image range.
    // For simplicity we assume a page size loop — replace kernel_size
    // and do a tighter maintenance if you want.
    // If you cannot know size here, ensure the loader cleaned caches or
    // the memory is strongly ordered/coherent (GPU firmware usually does).
    // -----------------------
    adrp    x17, kernel_phys_addr
    add     x17, x17, :lo12:kernel_phys_addr    // start VA (physical = identity)
    adrp    x18, kernel_size
    add     x18, x18, :lo12:kernel_size         // kernel size in bytes

    cbz     x18, .SKIP_CLEAN    // if size==0 skip maintenance
    // loop: for (addr = start; addr < start+size; addr+=64) dc cvau, then dsb ish, ic iallu
    
    b       smc_entry
.CLEAN_LOOP:
    mov     x19, #64
    // dc cvau, x17
    dc      cvau, x17
    add     x17, x17, x19
    subs    x18, x18, x19
    b.gt    .CLEAN_LOOP
    dsb     ish
    ic      iallu
    dsb     ish
    isb
.SKIP_CLEAN:

    // -----------------------
    // Finalize args and PC:
    // Kernel protocol (per kernel docs):
    //   x0 = DTB phys addr
    //   x1 = 0
    //   x2 = 0
    //   x3 = 0
    // Put ELR_EL3 = kernel entry (x10)
    // -----------------------
    mov     x0, x11
    mov     x1, xzr
    mov     x2, xzr
    mov     x3, xzr

    msr     elr_el3, x10

    // ensure all register writes complete
    dsb     sy
    isb

    // ERET -> will resume at ELR_EL3 with state from SPSR_EL3 (EL2h non-secure)
    eret

    // If ERET returns, hang
.hang:
    wfi
    b       .hang

    .align 12
// -----------------------
// Replaceable constants/labels (edit for your platform)
// The Raspberry Pi GPU firmware defaults commonly used:
    .quad   0x00080000                // kernel_phys_addr (default load: 0x80000 for 64-bit)
kernel_phys_addr:
    .quad   0x00100000                // fdt_phys_addr (common default 0x100000)
fdt_phys_addr:
    .quad   0x02000000                // el2_stack_top (pick a safe RAM area above kernel/DTB)
el2_stack_top:
    .quad   0x0                        // kernel_size (0 -> skip cleaning; set real size if available)
kernel_size:
