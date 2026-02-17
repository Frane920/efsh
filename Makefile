ASM_DIR := asm
ASMS      := $(wildcard $(ASM_DIR)/*.asm)
OBJS       := $(ASMS:.asm=.o)
TARGET  := efsh

.PHONY: all clean build

all: build

$(ASM_DIR)/%.o: $(ASM_DIR)/%.asm
	fasm $< $@

build: $(OBJS)
	odin build . -o:size -out=$(TARGET) \
	-extra-linker-flags:"-flto -Wl,--gc-sections -Wl,--sort-common -Wl,--icf=all -Wl,-z,norelro $(OBJS) -s -w" \
	-linker:lld -microarch:native -no-type-assert

strip:
	sstrip --zeroes $(TARGET)

clean:
	rm -f $(ASM_DIR)/*.o $(TARGET)
