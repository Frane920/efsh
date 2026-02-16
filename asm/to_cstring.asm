format ELF64
public asm_to_cstring

section '.text' executable

asm_to_cstring:
    mov rax, rdi
    mov rcx, rdx
    rep movsb
    mov byte [rdi], 0
    ret
.done_null:
    mov byte [rdi], 0
    mov rax, rdi
    ret
