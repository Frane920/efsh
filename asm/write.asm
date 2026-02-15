format ELF64
public asm_write

section '.text' executable

asm_write:
    mov rax, 1
    syscall
    ret
