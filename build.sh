fasm asm/exit.asm
fasm asm/write.asm
fasm asm/read.asm
fasm asm/join.asm
fasm asm/to_cstring.asm
odin build . -o:size -extra-linker-flags:"-flto -Wl,--gc-sections -Wl,--sort-common -Wl,--icf=all -Wl,-z,norelro asm/exit.o asm/write.o asm/read.o asm/join.o asm/to_cstring.o -s -w" -linker:lld -microarch:native -no-type-assert
sstrip --zeroes efsh

