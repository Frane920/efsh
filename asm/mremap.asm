format ELF64
public asm_mremap

section '.text' executable

asm_mremap:
    mov r10, rcx
    mov rax, 164
    syscall
    ret
