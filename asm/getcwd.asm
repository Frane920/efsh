format ELF64
public asm_getcwd

section '.text' executable

asm_getcwd:
    mov eax, 79
    syscall

    ret
