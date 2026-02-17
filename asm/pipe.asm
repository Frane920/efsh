format ELF64
public asm_pipe

section '.text' executable

asm_pipe:
    mov eax, 22
    syscall

    ret
