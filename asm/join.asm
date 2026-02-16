format ELF64
public asm_join

section '.text' executable

asm_join:
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    ; R8 is sep_len

.loop:
    test r14, r14
    jz .done

    mov rsi, [r13]
    mov rcx, [r13+8]
    rep movsb

    dec r14
    jz .done

    mov rsi, r15
    mov rcx, r8
    rep movsb

    add r13, 16
    jmp .loop

.done:
    sub r12, rdi
    mov rax, r12

    pop r15
    pop r14
    pop r13
    pop r12
    ret
