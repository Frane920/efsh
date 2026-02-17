format ELF64
public asm_faccessat

section '.text' executable

asm_faccessat:
    mov r10, rcx
    mov eax, 269
    syscall
    ret
