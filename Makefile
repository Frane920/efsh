ASM_DIR := asm
ASMS      := $(wildcard $(ASM_DIR)/*.asm)
OBJS       := $(ASMS:.asm=.o)
TARGET  := efsh

.PHONY: all clean build

all: build

$(ASM_DIR)/%.o: $(ASM_DIR)/%.asm
	fasm $< $@

build: $(OBJS)
	odin build . \
		-o:size \
		-out:$(TARGET) \
		-microarch:native \
		-no-type-assert \
		-disable-assert \
		-no-bounds-check \
		-linker:lld \
		-target:linux_amd64 \
		-build-mode:exe \
		-vet-unused \
		-vet-unused-variables \
		-vet-unused-imports \
		-no-crt \
		-default-to-nil-allocator \
		-no-thread-local \
		-extra-linker-flags:"\
			-flto=full \
			-fuse-ld=lld \
			-Wl,-O3 \
			-Wl,--gc-sections \
			-Wl,--icf=all \
			-Wl,--lto-O3 \
			-Wl,-z,norelro \
			-Wl,-z,noseparate-code \
			-Wl,--no-eh-frame-hdr \
			-Wl,--hash-style=sysv \
			-Wl,--build-id=none \
			-Wl,-z,now \
			-Wl,--as-needed \
			-Wl,--no-undefined \
			-Wl,--strip-all \
			-Wl,-s \
			-Wl,--discard-all \
			-Wl,--no-dynamic-linker \
			$(OBJS) "

strip:
	sstrip --zeroes $(TARGET)

clean:
	rm -f $(ASM_DIR)/*.o $(TARGET)
