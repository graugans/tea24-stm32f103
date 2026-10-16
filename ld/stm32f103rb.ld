ENTRY(Reset_Handler)

/* Minimum stack reservation for the descending MSP stack.
 * Heap can grow only up to _stack_limit.
 */
_Min_Stack_Size = 0x800; /* 2 KiB */

MEMORY
{
  FLASH (rx) : ORIGIN = 0x08000000, LENGTH = 128K
  RAM (xrw)  : ORIGIN = 0x20000000, LENGTH = 20K
}

/* First vector-table entry: initial Main Stack Pointer (MSP). */
_stack_top = ORIGIN(RAM) + LENGTH(RAM);
_estack = _stack_top;

SECTIONS
{
  /* Interrupt vector table must stay at the beginning of flash. */
  .isr_vector :
  {
    . = ALIGN(4);
    KEEP(*(.isr_vector))
    . = ALIGN(4);
  } > FLASH

  /* Executable code + constants in flash.
   * .rodata (const globals/string literals) also lives here.
   */
  .text :
  {
    . = ALIGN(4);
    *(.init)
    *(.fini)
    *(.text*)
    *(.rodata*)
    *(.glue_7)
    *(.glue_7t)
    *(.eh_frame*)
    KEEP(*(.init_array*))
    KEEP(*(.fini_array*))
    KEEP(*(.preinit_array*))
    . = ALIGN(4);
    _etext = .;
  } > FLASH

  /* Exception unwinding tables emitted by compiler/runtime. */
  .ARM.extab :
  {
    *(.ARM.extab* .gnu.linkonce.armextab.*)
  } > FLASH

  .ARM.exidx :
  {
    __exidx_start = .;
    *(.ARM.exidx* .gnu.linkonce.armexidx.*)
    __exidx_end = .;
  } > FLASH

  /* Flash source address for .data initialization image. */
  _sidata = LOADADDR(.data);

  /* .data: initialized read/write globals.
   * Runtime location is RAM; initial values are copied from flash.
   */
  .data : AT(_sidata)
  {
    . = ALIGN(4);
    _sdata = .;
    *(.data*)
    . = ALIGN(4);
    _edata = .;
  } > RAM

  /* .bss: zero-initialized globals/statics in RAM.
   * Startup clears this range to zero.
   */
  .bss :
  {
    . = ALIGN(4);
    _sbss = .;
    *(.bss*)
    *(COMMON)
    . = ALIGN(4);
    _ebss = .;
  } > RAM

  /* Optional non-initialized variables that must survive reset
   * can be placed in a .noinit section.
   */
  .noinit (NOLOAD) :
  {
    . = ALIGN(4);
    *(.noinit*)
    . = ALIGN(4);
  } > RAM

  /* Heap grows upward from _heap_start to _heap_end.
   * Stack grows downward from _stack_top to _stack_limit.
   */
  . = ALIGN(8);
  _end = .;
  _heap_start = .;
  _stack_limit = ORIGIN(RAM) + LENGTH(RAM) - _Min_Stack_Size;
  _heap_end = _stack_limit;

  ASSERT(_heap_end >= _heap_start, "RAM overflow: .data/.bss exceed available RAM")

  /DISCARD/ :
  {
    *(.note*)
    *(.comment*)
  }
}
