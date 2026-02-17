format ELF64
public asm_wait4

section '.text' executable

asm_wait4:
    mov r10, rcx
    mov eax, 61
    syscall

    ret
