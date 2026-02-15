format ELF64
public asm_read

section '.text' executable

asm_read:
    mov rax, 0
    syscall
    ret
