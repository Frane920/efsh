format ELF64
public asm_execveat

section '.text' executable

asm_execveat:
    mov r10, rcx
    mov eax, 322
    syscall
    ret
