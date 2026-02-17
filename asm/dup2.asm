format ELF64
public asm_dup2

section '.text' executable

asm_dup2:
    mov eax, 33
    syscall

    ret
