format ELF64
public asm_exit

section '.text' executable

asm_exit:
    mov rax, 60
    syscall
    ret
