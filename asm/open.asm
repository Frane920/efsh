    format ELF64
    public asm_open

    section '.text' executable

    asm_open:
        mov r10, rcx
        mov eax, 257
        syscall
        ret
