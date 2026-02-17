format ELF64
public asm_fork

section '.text' executable

asm_fork:
    mov eax, 57
    syscall

    ret
