format ELF64
public asm_chdir

section '.text' executable

asm_chdir:
    mov eax, 80
    syscall

    ret
