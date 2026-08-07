BUILD_DIR := build
SRC_DIR := OS_src
BOOT_SRC := $(SRC_DIR)/boot/boot.asm
KERNEL_SRC := $(SRC_DIR)/kernel/main.asm
KERNEL_DEPS := $(shell find $(SRC_DIR)/kernel -type f \( -name '*.asm' -o -name '*.def' \)) transport/lib/syscall.def
FS_LAYOUT_DEF := $(SRC_DIR)/kernel/fs/layout.def

BOOT_BIN := $(BUILD_DIR)/boot.bin
KERNEL_BIN := $(BUILD_DIR)/kernel.bin
OS_IMG := $(BUILD_DIR)/mini_os.img

INJECT_TOOL := $(BUILD_DIR)/inject_transport
ELF2BIN_TOOL := $(BUILD_DIR)/elf2bin

LIB_DIR := transport/lib
APPS_DIR := transport/apps
LIB_TEST_DIR := transport/lib_test
APP_BUILD_DIR := transport/build

CRT0_SRC := $(LIB_DIR)/crt0.asm
MINILIBC_SRC := $(LIB_DIR)/minilibc.c

CRT0_OBJ := $(BUILD_DIR)/crt0.o
MINILIBC_OBJ := $(BUILD_DIR)/minilibc.o

APP_SRCS := $(shell find $(APPS_DIR) $(LIB_TEST_DIR) -name '*.c' 2>/dev/null)
APP_BINS := $(patsubst transport/%.c,$(APP_BUILD_DIR)/%.bin,$(APP_SRCS))

NASM := nasm -w-label-redef-late

CC := cc
CLANG := clang
LLD := ld.lld
QEMU := qemu-system-i386

.PHONY: all clean run apps app solution_a solution_b

all: $(OS_IMG)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(APP_BUILD_DIR):
	mkdir -p $(APP_BUILD_DIR)

$(INJECT_TOOL): tools/inject_transport.c $(FS_LAYOUT_DEF) | $(BUILD_DIR)
	$(CC) -O2 tools/inject_transport.c -o $(INJECT_TOOL)

$(ELF2BIN_TOOL): tools/elf2bin.c | $(BUILD_DIR)
	$(CC) -O2 tools/elf2bin.c -o $(ELF2BIN_TOOL)

$(CRT0_OBJ): $(CRT0_SRC) | $(BUILD_DIR)
	$(NASM) -f elf32 $(CRT0_SRC) -o $(CRT0_OBJ)

$(MINILIBC_OBJ): $(MINILIBC_SRC) $(LIB_DIR)/minilibc.h $(LIB_DIR)/syscall.def $(LIB_DIR)/limits.h | $(BUILD_DIR)
	$(CLANG) -target i386-unknown-none-elf -m32 -march=i386 -mno-sse -mno-mmx -ffreestanding -nostdlib -O2 -std=gnu11 -I$(LIB_DIR) -c $(MINILIBC_SRC) -o $(MINILIBC_OBJ)

# Generic rule to compile any C app or library test under transport/
$(APP_BUILD_DIR)/%.bin: transport/%.c $(CRT0_OBJ) $(MINILIBC_OBJ) $(ELF2BIN_TOOL) | $(BUILD_DIR) $(APP_BUILD_DIR)
	@echo "Compiling C binary '$<'..."
	@mkdir -p $(dir $@)
	$(CLANG) -target i386-unknown-none-elf -m32 -march=i386 -mno-sse -mno-mmx -ffreestanding -nostdlib -O2 -std=c90 -pedantic-errors -Wall -Wextra -Werror -I$(LIB_DIR) -c $< -o $(BUILD_DIR)/$(notdir $*).o
	@if command -v $(LLD) >/dev/null 2>&1; then \
		echo "Linking '$@' using Solution A (ld.lld)..."; \
		$(LLD) -m elf_i386 --image-base 0x40000 -Ttext 0x40000 --oformat binary $(CRT0_OBJ) $(BUILD_DIR)/$(notdir $*).o $(MINILIBC_OBJ) -o $@; \
	else \
		echo "Linking '$@' using Solution B (elf2bin host tool)..."; \
		$(ELF2BIN_TOOL) $@ 0x40000 $(CRT0_OBJ) $(BUILD_DIR)/$(notdir $*).o $(MINILIBC_OBJ); \
	fi

apps: $(APP_BINS)

# Single app compile target (usage: make app APP=hello.c or make app APP=hello)
app:
	@if [ -z "$(APP)" ]; then \
		echo "Usage: make app APP=<name.c>"; \
		exit 1; \
	fi; \
	APP_NAME=$$(basename $(APP) .c); \
	$(MAKE) $(APP_BUILD_DIR)/$$APP_NAME.bin

$(KERNEL_BIN): $(KERNEL_DEPS) | $(BUILD_DIR)
	$(NASM) -f bin $(KERNEL_SRC) -o $(KERNEL_BIN)

$(BOOT_BIN): $(BOOT_SRC) $(KERNEL_BIN) | $(BUILD_DIR)
	@KERNEL_SIZE=$$(wc -c < $(KERNEL_BIN)); \
	KERNEL_SECTORS=$$(( (KERNEL_SIZE + 511) / 512 )); \
	if [ $$KERNEL_SECTORS -gt 100 ]; then \
		echo "error: kernel is $$KERNEL_SECTORS sectors, exceeds reserved 100-sector area (LBA 1-100)."; \
		exit 1; \
	fi; \
	$(NASM) -f bin -d KERNEL_SECTORS=$$KERNEL_SECTORS $(BOOT_SRC) -o $(BOOT_BIN)

$(OS_IMG): $(BOOT_BIN) $(KERNEL_BIN) $(INJECT_TOOL) $(APP_BINS) | $(BUILD_DIR)
	dd if=/dev/zero of=$(OS_IMG) bs=512 count=4096 conv=notrunc
	dd if=$(BOOT_BIN) of=$(OS_IMG) bs=512 seek=0 conv=notrunc
	dd if=$(KERNEL_BIN) of=$(OS_IMG) bs=512 seek=1 conv=notrunc
	$(INJECT_TOOL) $(OS_IMG) transport

run: $(OS_IMG)
	$(QEMU) -drive format=raw,file=$(OS_IMG)

clean:
	rm -rf $(BUILD_DIR) $(APP_BUILD_DIR)
