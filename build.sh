fasm asm/exit.asm
fasm asm/write.asm
fasm asm/read.asm
odin build . -o:size -extra-linker-flags:"-flto -Wl,--gc-sections -Wl,--sort-common -Wl,--icf=all -Wl,-z,norelro asm/exit.o asm/write.o asm/read.o -s -w" -linker:lld -microarch:native -no-type-assert
sstrip --zeroes efsh

