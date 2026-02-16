fasm asm/exit.asm
fasm asm/mremap.asm
fasm asm/mmap.asm
fasm asm/write.asm
fasm asm/read.asm
fasm asm/join.asm
fasm asm/to_cstring.asm
fasm asm/close.asm
odin build . -o:size -extra-linker-flags:"-flto -Wl,--gc-sections -Wl,--sort-common -Wl,--icf=all -Wl,-z,norelro asm/mremap.o asm/close.o asm/exit.o asm/write.o asm/read.o asm/join.o asm/to_cstring.o asm/mmap.o -s -w" -linker:lld -microarch:native -no-type-assert
sstrip --zeroes efsh

