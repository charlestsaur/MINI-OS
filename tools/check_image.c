#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SECTOR_SIZE 512U
#define FAT_EOC 0xFFFFU
#define INODE_NAME_CAP 27U
#define DIR_ENTRY_COUNT 16U

#define FS_LAYOUT_CONST(name, value) enum { name = value };
#include "../OS_src/kernel/fs/layout.def"
#undef FS_LAYOUT_CONST

#define FS_TOTAL_SECTORS ((uint64_t)FS_DATA_START_LBA + FS_DATA_BLOCK_COUNT)

#pragma pack(push, 1)
typedef struct {
    uint8_t type;
    char name[27];
    uint32_t size;
    uint32_t start_block;
    uint32_t blocks_cnt;
    uint32_t parent;
    uint8_t reserved[20];
} inode_t;

typedef struct {
    uint32_t child_inode;
    uint8_t child_type;
    char child_name[27];
} dir_entry_t;
#pragma pack(pop)

_Static_assert(sizeof(inode_t) == 64U, "inode layout must remain 64 bytes");
_Static_assert(sizeof(dir_entry_t) == 32U, "directory entry must remain 32 bytes");

static FILE *image;
static uint64_t image_size;
static uint8_t inode_bitmap[SECTOR_SIZE];
static uint16_t fat[FS_DATA_BLOCK_COUNT];
static inode_t inodes[FS_INODE_COUNT];
static int32_t block_owner[FS_DATA_BLOCK_COUNT];
static uint8_t reachable[FS_INODE_COUNT];
static uint8_t visit_state[FS_INODE_COUNT];
static uint32_t link_count[FS_INODE_COUNT];
static uint32_t allocated_inode_count;
static uint32_t owned_block_count;

static int fail(const char *message) {
    fprintf(stderr, "check_image: %s\n", message);
    return -1;
}

static int fail_index(const char *message, uint32_t index) {
    fprintf(stderr, "check_image: %s %u\n", message, index);
    return -1;
}

static int read_at(uint64_t offset, void *buffer, size_t size) {
    if (offset > (uint64_t)LONG_MAX || offset + size > image_size) {
        return fail("read exceeds image bounds");
    }
    if (fseek(image, (long)offset, SEEK_SET) != 0) {
        fprintf(stderr, "check_image: seek failed: %s\n", strerror(errno));
        return -1;
    }
    if (fread(buffer, 1, size, image) != size) {
        return fail("short image read");
    }
    return 0;
}

static int read_lba(uint32_t lba, void *buffer) {
    if (lba >= FS_TOTAL_SECTORS) return fail_index("LBA out of range:", lba);
    return read_at((uint64_t)lba * SECTOR_SIZE, buffer, SECTOR_SIZE);
}

static int bitmap_is_set(uint32_t inode_index) {
    return (inode_bitmap[inode_index / 8U] >> (inode_index % 8U)) & 1U;
}

static int block_valid(uint32_t block) {
    return block >= 2U && block < FS_DATA_BLOCK_COUNT;
}

static int field_is_terminated(const char field[INODE_NAME_CAP]) {
    return memchr(field, '\0', INODE_NAME_CAP) != NULL;
}

static unsigned char ascii_fold(unsigned char value) {
    if (value >= 'A' && value <= 'Z') return (unsigned char)(value + ('a' - 'A'));
    return value;
}

static int names_equal_ci(const char *left, const char *right) {
    while (*left != '\0' && *right != '\0') {
        if (ascii_fold((unsigned char)*left) != ascii_fold((unsigned char)*right)) {
            return 0;
        }
        left++;
        right++;
    }
    return *left == *right;
}

static int load_metadata(void) {
    uint8_t sector[SECTOR_SIZE];
    uint32_t superblock[6];
    uint32_t i;

    if (read_lba(FS_SUPERBLOCK_LBA, sector) < 0) return -1;
    memcpy(superblock, sector, sizeof(superblock));
    if (superblock[0] != FS_MAGIC || superblock[1] != FS_INODE_COUNT ||
        superblock[2] != FS_DATA_BLOCK_COUNT ||
        superblock[3] != FS_INODE_START_LBA ||
        superblock[4] != FS_DATA_START_LBA || superblock[5] != 0U) {
        return fail("superblock does not match layout.def");
    }

    if (read_lba(FS_INODE_BMAP_LBA, inode_bitmap) < 0) return -1;
    for (i = FS_INODE_COUNT / 8U; i < SECTOR_SIZE; i++) {
        if (inode_bitmap[i] != 0U) return fail("unused inode bitmap bits are set");
    }

    if (read_at((uint64_t)FS_FAT_LBA * SECTOR_SIZE, fat, sizeof(fat)) < 0) {
        return -1;
    }
    if (read_at((uint64_t)FS_INODE_START_LBA * SECTOR_SIZE,
                inodes, sizeof(inodes)) < 0) {
        return -1;
    }
    return 0;
}

static int validate_chain(uint32_t inode_index, const inode_t *inode) {
    uint8_t seen[FS_DATA_BLOCK_COUNT];
    uint32_t current;
    uint32_t i;
    uint16_t next;

    memset(seen, 0, sizeof(seen));
    current = inode->start_block;
    for (i = 0; i < inode->blocks_cnt; i++) {
        if (!block_valid(current)) return fail_index("inode has invalid block:", inode_index);
        if (seen[current]) return fail_index("inode FAT chain is cyclic:", inode_index);
        if (block_owner[current] >= 0) {
            fprintf(stderr,
                    "check_image: data block %u is owned by both inode %d and inode %u\n",
                    current, block_owner[current], inode_index);
            return -1;
        }
        seen[current] = 1U;
        block_owner[current] = (int32_t)inode_index;
        owned_block_count++;
        next = fat[current];
        if (i + 1U == inode->blocks_cnt) {
            if (next != FAT_EOC) return fail_index("inode chain does not end at declared length:", inode_index);
        } else {
            if (next == 0U || next == FAT_EOC || !block_valid(next)) {
                return fail_index("inode chain ends early:", inode_index);
            }
            current = next;
        }
    }
    return 0;
}

static int validate_inodes_and_fat(void) {
    uint32_t i;
    uint32_t expected_blocks;
    inode_t *inode;

    for (i = 0; i < FS_DATA_BLOCK_COUNT; i++) block_owner[i] = -1;
    block_owner[0] = -2;
    block_owner[1] = -2;
    if (fat[0] != FAT_EOC || fat[1] != FAT_EOC) {
        return fail("reserved FAT entries 0 and 1 must be EOC");
    }

    for (i = 0; i < FS_INODE_COUNT; i++) {
        inode = &inodes[i];
        if (!bitmap_is_set(i)) {
            if (inode->type != 0U) return fail_index("free bitmap bit has a live inode:", i);
            continue;
        }

        allocated_inode_count++;
        if (inode->type != 1U && inode->type != 2U) {
            return fail_index("allocated inode has invalid type:", i);
        }
        if (!field_is_terminated(inode->name)) {
            return fail_index("inode name is not terminated:", i);
        }
        if (i == 0U) {
            if (inode->type != 2U || strcmp(inode->name, "/") != 0 ||
                inode->parent != 0U) {
                return fail("root inode shape is invalid");
            }
        } else {
            if (inode->name[0] == '\0' || inode->parent >= FS_INODE_COUNT) {
                return fail_index("inode name or parent is invalid:", i);
            }
        }

        if (inode->type == 2U) {
            if (inode->blocks_cnt == 0U || inode->size != 0U) {
                return fail_index("directory inode shape is invalid:", i);
            }
        } else if (inode->size == 0U) {
            if (inode->blocks_cnt > 1U) {
                return fail_index("empty file retains more than one block:", i);
            }
        } else {
            expected_blocks = (inode->size + SECTOR_SIZE - 1U) / SECTOR_SIZE;
            if (inode->blocks_cnt != expected_blocks) {
                return fail_index("file block count does not match byte size:", i);
            }
        }

        if (inode->blocks_cnt == 0U) {
            if (inode->start_block != 0U) {
                return fail_index("zero-block inode has a start block:", i);
            }
        } else if (validate_chain(i, inode) < 0) {
            return -1;
        }
    }

    for (i = 2U; i < FS_DATA_BLOCK_COUNT; i++) {
        if (block_owner[i] == -1 && fat[i] != 0U) {
            return fail_index("FAT allocation is not owned by any inode:", i);
        }
        if (block_owner[i] >= 0 && fat[i] == 0U) {
            return fail_index("owned block is marked free in FAT:", i);
        }
    }
    return 0;
}

static int empty_entry_is_zero(const dir_entry_t *entry) {
    const uint8_t *bytes = (const uint8_t *)entry;
    size_t i;
    for (i = 0; i < sizeof(*entry); i++) {
        if (bytes[i] != 0U) return 0;
    }
    return 1;
}

static int walk_directory(uint32_t inode_index) {
    const inode_t *directory;
    dir_entry_t entries[DIR_ENTRY_COUNT];
    char (*seen_names)[INODE_NAME_CAP];
    uint32_t name_capacity;
    uint32_t seen_count;
    uint32_t current;
    uint32_t block_index;
    uint32_t entry_index;
    uint32_t child;
    uint32_t i;
    const dir_entry_t *entry;
    const inode_t *child_inode;

    if (visit_state[inode_index] == 1U) return fail_index("directory cycle reaches inode:", inode_index);
    if (visit_state[inode_index] == 2U) return 0;
    visit_state[inode_index] = 1U;
    reachable[inode_index] = 1U;
    directory = &inodes[inode_index];
    current = directory->start_block;
    seen_count = 0U;
    name_capacity = directory->blocks_cnt * DIR_ENTRY_COUNT;
    if (name_capacity > FS_INODE_COUNT) name_capacity = FS_INODE_COUNT;
    seen_names = calloc(name_capacity, sizeof(*seen_names));
    if (seen_names == NULL) return fail("cannot allocate directory name table");

    for (block_index = 0; block_index < directory->blocks_cnt; block_index++) {
        if (read_lba(FS_DATA_START_LBA + current, entries) < 0) return -1;
        for (entry_index = 0; entry_index < DIR_ENTRY_COUNT; entry_index++) {
            entry = &entries[entry_index];
            if (entry->child_inode == 0U) {
                if (!empty_entry_is_zero(entry)) return fail_index("malformed empty directory entry in inode:", inode_index);
                continue;
            }
            child = entry->child_inode;
            if (child >= FS_INODE_COUNT || !bitmap_is_set(child)) {
                return fail_index("directory references an unallocated inode:", child);
            }
            if (!field_is_terminated(entry->child_name) || entry->child_name[0] == '\0') {
                return fail_index("directory entry has an invalid name in inode:", inode_index);
            }
            for (i = 0; i < seen_count; i++) {
                if (names_equal_ci(seen_names[i], entry->child_name)) {
                    return fail_index("directory contains a duplicate name in inode:", inode_index);
                }
            }
            if (seen_count == name_capacity) {
                return fail_index("directory contains too many live entries:", inode_index);
            }
            memcpy(seen_names[seen_count], entry->child_name, INODE_NAME_CAP);
            seen_count++;

            child_inode = &inodes[child];
            if (entry->child_type != child_inode->type ||
                strcmp(entry->child_name, child_inode->name) != 0 ||
                child_inode->parent != inode_index) {
                return fail_index("directory entry disagrees with child inode:", child);
            }
            link_count[child]++;
            if (link_count[child] != 1U) return fail_index("inode has multiple directory links:", child);
            reachable[child] = 1U;
            if (child_inode->type == 2U && walk_directory(child) < 0) return -1;
        }
        if (block_index + 1U < directory->blocks_cnt) current = fat[current];
    }
    visit_state[inode_index] = 2U;
    free(seen_names);
    return 0;
}

static int validate_reachability(void) {
    uint32_t i;

    if (!bitmap_is_set(0U)) return fail("root inode is not allocated");
    if (walk_directory(0U) < 0) return -1;
    for (i = 0; i < FS_INODE_COUNT; i++) {
        if (bitmap_is_set(i) && !reachable[i]) {
            return fail_index("allocated inode is unreachable:", i);
        }
        if (i != 0U && bitmap_is_set(i) && link_count[i] != 1U) {
            return fail_index("allocated inode does not have exactly one parent link:", i);
        }
    }
    return 0;
}

int main(int argc, char **argv) {
    long length;
    int close_result;

    if (argc != 2) {
        fprintf(stderr, "Usage: %s <mini_os.img>\n", argv[0]);
        return 2;
    }
    image = fopen(argv[1], "rb");
    if (image == NULL) {
        fprintf(stderr, "check_image: cannot open '%s': %s\n", argv[1], strerror(errno));
        return 1;
    }
    if (fseek(image, 0, SEEK_END) != 0 || (length = ftell(image)) < 0) {
        fail("cannot determine image size");
        fclose(image);
        return 1;
    }
    image_size = (uint64_t)length;
    if (image_size != FS_TOTAL_SECTORS * SECTOR_SIZE) {
        fprintf(stderr,
                "check_image: image is %llu bytes; expected exactly %llu bytes\n",
                (unsigned long long)image_size,
                (unsigned long long)(FS_TOTAL_SECTORS * SECTOR_SIZE));
        fclose(image);
        return 1;
    }

    if (load_metadata() < 0 || validate_inodes_and_fat() < 0 ||
        validate_reachability() < 0) {
        fclose(image);
        return 1;
    }
    close_result = fclose(image);
    if (close_result != 0) {
        fprintf(stderr, "check_image: close failed: %s\n", strerror(errno));
        return 1;
    }
    printf("Image integrity OK: %u reachable inodes, %u owned data blocks.\n",
           allocated_inode_count, owned_block_count);
    return 0;
}
