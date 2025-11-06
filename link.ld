ENTRY(_start)

SECTIONS
{
    . = 0x160000;      /* load address for BL31 */

    .text : {
        *(.text*)
    }

    .rodata : {
        *(.rodata*)
    }

    .data : {
        *(.data*)
    }

    .bss (NOLOAD) : ALIGN(16) {
        __bss_start = .;
        *(.bss*)
        __bss_end = .;
    }

    _end = .;
}