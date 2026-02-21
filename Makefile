BUILD_DIR := build
SRC_DIR := OS_src
BOOT_SRC := $(SRC_DIR)/boot/boot.asm
KERNEL_SRC := $(SRC_DIR)/kernel/main.asm

BOOT_BIN := $(BUILD_DIR)/boot.bin
KERNEL_BIN := $(BUILD_DIR)/kernel.bin
OS_IMG := $(BUILD_DIR)/mini_os.img

NASM := nasm
QEMU := qemu-system-i386

.PHONY: all clean run

all: $(OS_IMG)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(KERNEL_BIN): $(KERNEL_SRC) | $(BUILD_DIR)
	$(NASM) -f bin $(KERNEL_SRC) -o $(KERNEL_BIN)

$(BOOT_BIN): $(BOOT_SRC) $(KERNEL_BIN) | $(BUILD_DIR)
	@KERNEL_SIZE=$$(wc -c < $(KERNEL_BIN)); \
	KERNEL_SECTORS=$$(( (KERNEL_SIZE + 511) / 512 )); \
	if [ $$KERNEL_SECTORS -gt 100 ]; then \
		echo "error: kernel is $$KERNEL_SECTORS sectors, exceeds reserved 100-sector area (LBA 1-100)."; \
		exit 1; \
	fi; \
	$(NASM) -f bin -d KERNEL_SECTORS=$$KERNEL_SECTORS $(BOOT_SRC) -o $(BOOT_BIN)

$(OS_IMG): $(BOOT_BIN) $(KERNEL_BIN) | $(BUILD_DIR)
	dd if=/dev/zero of=$(OS_IMG) bs=512 count=4096 conv=notrunc
	dd if=$(BOOT_BIN) of=$(OS_IMG) bs=512 seek=0 conv=notrunc
	dd if=$(KERNEL_BIN) of=$(OS_IMG) bs=512 seek=1 conv=notrunc

run: $(OS_IMG)
	$(QEMU) -drive format=raw,file=$(OS_IMG)

clean:
	rm -rf $(BUILD_DIR)
