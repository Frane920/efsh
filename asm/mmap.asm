format ELF64
public asm_mmap

section '.text' executable

asm_mmap:
    mov r10, rcx
    push 9
    pop rax
    syscall
    ret
