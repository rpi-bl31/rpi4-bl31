.section .text
    .global el3_setup_misc
    .align 2

/* ---------- Constants ---------- */
.set CNTFRQ_VAL, 54000000           /* 0x0337F980 */
.set UART0_BASE, 0xFE201000         /* PL011 base */
.set UART0_DR,   (UART0_BASE + 0x00)
.set UART0_FR,   (UART0_BASE + 0x18)
.set UART0_LCRH, (UART0_BASE + 0x2C)
.set UART0_CR,   (UART0_BASE + 0x30)

.set MBOX_BASE,   0xFE00B880
.set MBOX_READ,   (MBOX_BASE + 0x00)
.set MBOX_STATUS, (MBOX_BASE + 0x18)
.set MBOX_WRITE,  (MBOX_BASE + 0x20)
.set MBOX_CH_PROP, 8
.set TAG_GET_ARM_MEMORY, 0x00010005

/* ---------- helper macro ---------- */
.macro delay_loop reg, cnt
    mov \reg, #\cnt
1:  subs \reg, \reg, #1
    b.ne 1b
.endm

/* ---------- entry ---------- */
el3_setup_misc:
    /* Save frame pointer if needed later; but we can keep simple here. */
    /* CNTFRQ_EL0 = CNTFRQ_VAL (load via movz/movk) */
    /* CNTFRQ_VAL = 0x0337F980 -> build with movz/movk */
    movz    x0, #0xF980             /* lower 16 bits */
    movk    x0, #0x0337, lsl #16    /* bits 16..31 */
    msr     CNTFRQ_EL0, x0
    isb

    /* --- UART init (use GAS form adrp / add #:lo12:) --- */
    adrp    x1, UART0_BASE
    add     x1, x1, #:lo12:UART0_BASE

    /* Disable UART (write 0 to CR) */
    mov     w2, #0
    str     w2, [x1, #(UART0_CR - UART0_BASE)]
    delay_loop x3, 1000

    /* LCRH: FIFO enable + 8-bit (0x70) */
    mov     w2, #0x70
    str     w2, [x1, #(UART0_LCRH - UART0_BASE)]

    /* Enable UART: RX+TX+UARTEN (0x301) */
    mov     w2, #0x301
    str     w2, [x1, #(UART0_CR - UART0_BASE)]
    delay_loop x3, 1000

    dsb     sy
    isb

    /* Print startup message */
    adr     x0, startup_msg
    bl      uart_puts

    /* Mailbox: buffer pointer in x0 */
    adr     x0, mbox_buf
    bl      mailbox_property_call_get_arm_mem

    /* Read returned addr/size: words at offsets 20 and 24 */
    ldr     w1, [x0, #20]   /* returned address low32 */
    ldr     w2, [x0, #24]   /* returned size low32 */

    adr     x3, got_mem_msg
    bl      uart_puts

    ret

/* ---------- uart helpers ---------- */
/* x0 = pointer to null-terminated ASCII string */
uart_puts:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
1:  ldrb    w1, [x0], #1
    cbz     w1, 2f
    mov     w0, w1
    bl      uart_putc
    b       1b
2:  ldp     x29, x30, [sp], #16
    ret

/* x0 = character in w0 (ASCII) */
uart_putc:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adrp    x1, UART0_BASE
    add     x1, x1, #:lo12:UART0_BASE
    add     x1, x1, #(UART0_FR - UART0_BASE)
1:  ldr     w2, [x1]
    and     w2, w2, #(1 << 5)    /* TXFF bit */
    cbnz    w2, 1b

    /* write character (32-bit) to DR */
    adrp    x1, UART0_BASE
    add     x1, x1, #:lo12:UART0_BASE
    add     x1, x1, #(UART0_DR - UART0_BASE)
    str     w0, [x1]

    ldp     x29, x30, [sp], #16
    ret

/* ---------- mailbox property helper (GET_ARM_MEMORY) ----------
   x0 = pointer to 16-byte aligned buffer (VA or PA if identity-mapped)
*/
mailbox_property_call_get_arm_mem:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    /* Build message:
       offset 0: total size (u32) => 7*4 = 28
       4: req code (u32) = 0
       8: tag id (u32)
       12: value buffer size (u32) = 8
       16: req/resp length (u32) = 0
       20: response addr low (u32)
       24: response size low (u32)
       28: end tag (u32) = 0
    */
    mov     w1, #28
    str     w1, [x0, #0]
    mov     w1, #0
    str     w1, [x0, #4]
    /* TAG_GET_ARM_MEMORY (0x00010005) - load with movz/movk */
    movz    w1, #0x0005
    movk    w1, #0x0001, lsl #16
    str     w1, [x0, #8]
    mov     w1, #8
    str     w1, [x0, #12]
    mov     w1, #0
    str     w1, [x0, #16]
    str     w1, [x0, #20]
    str     w1, [x0, #24]
    str     w1, [x0, #28]

    /* If caches are on, you should clean D-cache for buffer before handing to VC.
       For brevity we use a conservative DSBon/ISB; if your build enables caches,
       add a proper dc CVAU / dsb sequence that iterates cache lines.
    */
    dsb     sy
    isb

    /* Wait for mailbox write not full (status bit31) */
1:  adrp    x2, MBOX_STATUS
    add     x2, x2, #:lo12:MBOX_STATUS
    ldr     w3, [x2]
    tst     w3, #(1 << 31)
    b.ne    1b

    /* Compose payload: (buffer & ~0xF) | channel
       Use BIC to clear low bits (GAS doesn't like inverted immediates with AND) */
    bic     x4, x0, #15          /* clear low 4 bits */
    orr     x4, x4, #MBOX_CH_PROP

    /* write low32 of payload to MBOX_WRITE (use w-register) */
    adrp    x2, MBOX_WRITE
    add     x2, x2, #:lo12:MBOX_WRITE
    str     w4, [x2]

    /* Poll for response: wait for status read-empty bit (bit30) to clear and read matching channel */
2:  adrp    x2, MBOX_STATUS
    add     x2, x2, #:lo12:MBOX_STATUS
    ldr     w3, [x2]
    tst     w3, #(1 << 30)
    b.ne    2b

    adrp    x2, MBOX_READ
    add     x2, x2, #:lo12:MBOX_READ
    ldr     w5, [x2]            /* read 32-bit value */
    and     w6, w5, #0xF
    cmp     w6, #MBOX_CH_PROP
    b.ne    2b

    dsb     sy
    isb

    ldp     x29, x30, [sp], #16
    ret
    
    b       bl31_jump_to_kernel_pi4_robust

/* ---------- data ---------- */
    .section .rodata
startup_msg:
    .asciz "EL3 misc init: CNTFRQ set, UART up, mailbox query...\n"

got_mem_msg:
    .asciz "Mailbox GET_ARM_MEMORY done (see buffer)\n"

    .section .bss
    .balign 16
mbox_buf:
    .zero  8*4   /* 8 words = 32 bytes */
