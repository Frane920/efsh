format ELF64
public asm_close

section '.text' executable

asm_close:
    push 3
    pop rax
    syscall
    neg rax
    js .zero
    ret
.zero:
    xor eax, eax
    ret
