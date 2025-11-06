.section .text
.global el3_mmu_setup
.type el3_mmu_setup, %function

el3_mmu_setup:
    // --- MAIR & TCR ---
    ldr x0, =mair_el3_value
    msr MAIR_EL3, x0
    isb
    ldr x0, =tcr_el3_value
    msr TCR_EL3, x0
    isb

    // --- Set TTBR0_EL3 ---
    ldr x0, =ttbr0_table
    msr TTBR0_EL3, x0
    isb

    // --- Map EL3 reserved memory (last 16 MB) ---
    ldr x1, =el3_reserved_base
    ldr x2, =el3_reserved_size
    ldr x3, =l3_table_el3
map_loop:
    cmp x2, #0
    beq map_done
    add x4, x3, x2, lsl #3
    ldr x5, =PAGE_ATTR_RAM
    str x5, [x4]
    sub x2, x2, #0x1000
    b map_loop
map_done:

    // --- TLB invalidation ---
    dsb ish
    tlbi vmalle1
    dsb ish
    isb

    // --- Enable MMU ---
    mrs x0, SCTLR_EL3
    orr x0, x0, #(1<<0)   // M = MMU
    orr x0, x0, #(1<<2)   // C = Data cache
    orr x0, x0, #(1<<12)  // I = Instruction cache
    msr SCTLR_EL3, x0
    isb
    ret

.section .rodata
mair_el3_value:     .quad 0xff000044
tcr_el3_value:      .quad ((64-48)<<0)|(0b00<<6)|(0b11<<8)|(0b11<<10)
PAGE_ATTR_RAM:      .quad 0x407       // normal, RWX

.section .data
.align 12
ttbr0_table:        .space 0x1000
l1_table:           .space 0x1000
l2_table:           .space 0x1000
l3_table_el3:       .space 0x4000    // enough for 16 MB / 4KB pages

el3_reserved_base:  .quad 0x1FF000000
el3_reserved_size:  .quad 0x0100000   // 16 MB