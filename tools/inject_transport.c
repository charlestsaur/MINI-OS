#define _DEFAULT_SOURCE

#include <dirent.h>
#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>

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

static FILE *img_fp;
static uint64_t img_size;

static int block_valid(uint32_t block) {
    return block >= 2U && block < FS_DATA_BLOCK_COUNT;
}

static int fat_value_valid(uint16_t value) {
    return value == 0U || value == FAT_EOC || block_valid(value);
}

static int name_valid(const char *name) {
    size_t length;

    if (name == NULL) return 0;
    length = strlen(name);
    return length > 0U && length < INODE_NAME_CAP &&
           strcmp(name, ".") != 0 && strcmp(name, "..") != 0 &&
           strchr(name, '/') == NULL;
}

static int checked_seek(FILE *fp, uint64_t offset, const char *what) {
    if (offset > (uint64_t)LONG_MAX) {
        fprintf(stderr, "Error: %s offset is too large.\n", what);
        return -1;
    }
    if (fseek(fp, (long)offset, SEEK_SET) != 0) {
        fprintf(stderr, "Error: cannot seek %s: %s\n", what, strerror(errno));
        return -1;
    }
    return 0;
}

static int read_sector(uint32_t lba, void *buffer) {
    uint64_t offset;

    if (lba >= FS_TOTAL_SECTORS) {
        fprintf(stderr, "Error: sector read LBA %u exceeds filesystem geometry.\n", lba);
        return -1;
    }
    offset = (uint64_t)lba * SECTOR_SIZE;
    if (offset + SECTOR_SIZE > img_size ||
        checked_seek(img_fp, offset, "disk image") < 0) {
        return -1;
    }
    if (fread(buffer, 1, SECTOR_SIZE, img_fp) != SECTOR_SIZE) {
        fprintf(stderr, "Error: short read at image LBA %u.\n", lba);
        return -1;
    }
    return 0;
}

static int write_sector(uint32_t lba, const void *buffer) {
    uint64_t offset;

    if (lba >= FS_TOTAL_SECTORS) {
        fprintf(stderr, "Error: sector write LBA %u exceeds filesystem geometry.\n", lba);
        return -1;
    }
    offset = (uint64_t)lba * SECTOR_SIZE;
    if (offset + SECTOR_SIZE > img_size ||
        checked_seek(img_fp, offset, "disk image") < 0) {
        return -1;
    }
    if (fwrite(buffer, 1, SECTOR_SIZE, img_fp) != SECTOR_SIZE) {
        fprintf(stderr, "Error: short write at image LBA %u.\n", lba);
        return -1;
    }
    if (fflush(img_fp) != 0) {
        fprintf(stderr, "Error: cannot flush image LBA %u: %s\n", lba, strerror(errno));
        return -1;
    }
    return 0;
}

static int bitmap_test(uint32_t bit_index, int *is_set) {
    uint32_t byte_offset;
    uint32_t sector_offset;
    uint32_t byte_in_sector;
    uint8_t sector[SECTOR_SIZE];

    if (bit_index >= FS_INODE_COUNT) return -1;
    byte_offset = bit_index / 8U;
    sector_offset = byte_offset / SECTOR_SIZE;
    byte_in_sector = byte_offset % SECTOR_SIZE;
    if (read_sector(FS_INODE_BMAP_LBA + sector_offset, sector) < 0) return -1;
    *is_set = (sector[byte_in_sector] >> (bit_index % 8U)) & 1U;
    return 0;
}

static int bitmap_update(uint32_t bit_index, int set) {
    uint32_t byte_offset;
    uint32_t sector_offset;
    uint32_t byte_in_sector;
    uint8_t mask;
    uint8_t sector[SECTOR_SIZE];

    if (bit_index >= FS_INODE_COUNT) return -1;
    byte_offset = bit_index / 8U;
    sector_offset = byte_offset / SECTOR_SIZE;
    byte_in_sector = byte_offset % SECTOR_SIZE;
    mask = (uint8_t)(1U << (bit_index % 8U));
    if (read_sector(FS_INODE_BMAP_LBA + sector_offset, sector) < 0) return -1;
    if (set) sector[byte_in_sector] |= mask;
    else sector[byte_in_sector] &= (uint8_t)~mask;
    return write_sector(FS_INODE_BMAP_LBA + sector_offset, sector);
}

static int read_inode(uint32_t inode_index, inode_t *inode) {
    uint8_t sector[SECTOR_SIZE];
    uint32_t sector_offset;
    uint32_t byte_offset;

    if (inode_index >= FS_INODE_COUNT) return -1;
    sector_offset = inode_index / 8U;
    byte_offset = (inode_index % 8U) * (uint32_t)sizeof(*inode);
    if (read_sector(FS_INODE_START_LBA + sector_offset, sector) < 0) return -1;
    memcpy(inode, sector + byte_offset, sizeof(*inode));
    return 0;
}

static int write_inode(uint32_t inode_index, const inode_t *inode) {
    uint8_t sector[SECTOR_SIZE];
    uint32_t sector_offset;
    uint32_t byte_offset;

    if (inode_index >= FS_INODE_COUNT) return -1;
    sector_offset = inode_index / 8U;
    byte_offset = (inode_index % 8U) * (uint32_t)sizeof(*inode);
    if (read_sector(FS_INODE_START_LBA + sector_offset, sector) < 0) return -1;
    memcpy(sector + byte_offset, inode, sizeof(*inode));
    return write_sector(FS_INODE_START_LBA + sector_offset, sector);
}

static int fat_read(uint32_t block, uint16_t *value) {
    uint8_t sector[SECTOR_SIZE];
    uint32_t sector_offset;
    uint32_t byte_offset;

    if (block >= FS_DATA_BLOCK_COUNT) return -1;
    sector_offset = block / 256U;
    byte_offset = (block % 256U) * 2U;
    if (sector_offset >= FS_FAT_SECS ||
        read_sector(FS_FAT_LBA + sector_offset, sector) < 0) {
        return -1;
    }
    memcpy(value, sector + byte_offset, sizeof(*value));
    if (!fat_value_valid(*value)) {
        fprintf(stderr, "Error: FAT block %u contains invalid value %u.\n", block, *value);
        return -1;
    }
    return 0;
}

static int fat_write(uint32_t block, uint16_t value) {
    uint8_t sector[SECTOR_SIZE];
    uint32_t sector_offset;
    uint32_t byte_offset;

    if (block >= FS_DATA_BLOCK_COUNT || !fat_value_valid(value)) return -1;
    sector_offset = block / 256U;
    byte_offset = (block % 256U) * 2U;
    if (sector_offset >= FS_FAT_SECS ||
        read_sector(FS_FAT_LBA + sector_offset, sector) < 0) {
        return -1;
    }
    memcpy(sector + byte_offset, &value, sizeof(value));
    return write_sector(FS_FAT_LBA + sector_offset, sector);
}

static int collect_chain(uint32_t first, uint32_t count, uint32_t **blocks_out) {
    uint8_t *visited;
    uint32_t *blocks;
    uint32_t current;
    uint32_t i;
    uint16_t next;

    if (count == 0U || count > FS_DATA_BLOCK_COUNT || !block_valid(first)) return -1;
    visited = calloc(FS_DATA_BLOCK_COUNT, 1U);
    blocks = calloc(count, sizeof(*blocks));
    if (visited == NULL || blocks == NULL) {
        free(visited);
        free(blocks);
        return -1;
    }

    current = first;
    for (i = 0; i < count; i++) {
        if (!block_valid(current) || visited[current]) {
            fprintf(stderr, "Error: FAT chain is out of range or cyclic at block %u.\n", current);
            free(visited);
            free(blocks);
            return -1;
        }
        visited[current] = 1U;
        blocks[i] = current;
        if (fat_read(current, &next) < 0) {
            free(visited);
            free(blocks);
            return -1;
        }
        if (i + 1U == count) {
            if (next != FAT_EOC) {
                fprintf(stderr, "Error: FAT chain is longer than its declared block count.\n");
                free(visited);
                free(blocks);
                return -1;
            }
        } else {
            if (next == FAT_EOC || next == 0U || !block_valid(next)) {
                fprintf(stderr, "Error: FAT chain ends before its declared block count.\n");
                free(visited);
                free(blocks);
                return -1;
            }
            current = next;
        }
    }

    free(visited);
    *blocks_out = blocks;
    return 0;
}

static int clear_block_list(const uint32_t *blocks, uint32_t count) {
    uint32_t i;
    int result;

    result = 0;
    for (i = 0; i < count; i++) {
        if (fat_write(blocks[i], 0U) < 0) result = -1;
    }
    return result;
}

static int alloc_fat_chain(uint32_t count, uint32_t *first_out) {
    uint32_t *blocks;
    uint32_t found;
    uint32_t block;
    uint32_t i;
    uint16_t value;

    if (count == 0U || count > FS_DATA_BLOCK_COUNT - 2U) return -1;
    blocks = calloc(count, sizeof(*blocks));
    if (blocks == NULL) return -1;

    found = 0U;
    for (block = 2U; block < FS_DATA_BLOCK_COUNT && found < count; block++) {
        if (fat_read(block, &value) < 0) {
            free(blocks);
            return -1;
        }
        if (value == 0U) blocks[found++] = block;
    }
    if (found != count) {
        fprintf(stderr, "Error: insufficient free data blocks (need %u, found %u).\n", count, found);
        free(blocks);
        return -1;
    }

    for (i = 0; i < count; i++) {
        value = (i + 1U == count) ? FAT_EOC : (uint16_t)blocks[i + 1U];
        if (fat_write(blocks[i], value) < 0) {
            clear_block_list(blocks, i + 1U);
            free(blocks);
            return -1;
        }
    }
    *first_out = blocks[0];
    free(blocks);
    return 0;
}

static int free_fat_chain(uint32_t first, uint32_t count) {
    uint32_t *blocks;
    int result;

    if (collect_chain(first, count, &blocks) < 0) return -1;
    result = clear_block_list(blocks, count);
    free(blocks);
    return result;
}

static int alloc_inode(uint32_t *inode_out) {
    uint32_t index;
    int is_set;

    for (index = 2U; index < FS_INODE_COUNT; index++) {
        if (bitmap_test(index, &is_set) < 0) return -1;
        if (!is_set) {
            if (bitmap_update(index, 1) < 0) return -1;
            *inode_out = index;
            return 0;
        }
    }
    fprintf(stderr, "Error: no free inode is available.\n");
    return -1;
}

static int free_inode(uint32_t inode_index) {
    inode_t empty;
    int result;

    memset(&empty, 0, sizeof(empty));
    result = write_inode(inode_index, &empty);
    if (bitmap_update(inode_index, 0) < 0) result = -1;
    return result;
}

static int field_name_equals(const char field[27], const char *name) {
    if (memchr(field, '\0', INODE_NAME_CAP) == NULL) return -1;
    return strcasecmp(field, name) == 0;
}

static int find_child(uint32_t parent_index, const char *name,
                      uint32_t *child_out, uint8_t *type_out) {
    inode_t parent;
    uint32_t *blocks;
    uint32_t b;
    uint32_t i;
    uint8_t sector[SECTOR_SIZE];
    dir_entry_t *entries;
    int equal;

    if (read_inode(parent_index, &parent) < 0 || parent.type != 2U ||
        collect_chain(parent.start_block, parent.blocks_cnt, &blocks) < 0) {
        return -1;
    }
    for (b = 0; b < parent.blocks_cnt; b++) {
        if (read_sector(FS_DATA_START_LBA + blocks[b], sector) < 0) {
            free(blocks);
            return -1;
        }
        entries = (dir_entry_t *)sector;
        for (i = 0; i < DIR_ENTRY_COUNT; i++) {
            if (entries[i].child_inode == 0U) continue;
            if (entries[i].child_inode >= FS_INODE_COUNT ||
                (entries[i].child_type != 1U && entries[i].child_type != 2U)) {
                free(blocks);
                return -1;
            }
            equal = field_name_equals(entries[i].child_name, name);
            if (equal < 0) {
                free(blocks);
                return -1;
            }
            if (equal) {
                *child_out = entries[i].child_inode;
                *type_out = entries[i].child_type;
                free(blocks);
                return 1;
            }
        }
    }
    free(blocks);
    return 0;
}

static int add_dir_entry(uint32_t parent_index, uint32_t child_index,
                         uint8_t child_type, const char *child_name) {
    inode_t parent;
    uint32_t *blocks;
    uint32_t b;
    uint32_t i;
    uint32_t new_block;
    uint32_t last_block;
    uint8_t sector[SECTOR_SIZE];
    dir_entry_t *entries;

    if (!name_valid(child_name) || child_index >= FS_INODE_COUNT ||
        (child_type != 1U && child_type != 2U)) return -1;
    if (read_inode(parent_index, &parent) < 0 || parent.type != 2U ||
        collect_chain(parent.start_block, parent.blocks_cnt, &blocks) < 0) {
        return -1;
    }

    for (b = 0; b < parent.blocks_cnt; b++) {
        if (read_sector(FS_DATA_START_LBA + blocks[b], sector) < 0) {
            free(blocks);
            return -1;
        }
        entries = (dir_entry_t *)sector;
        for (i = 0; i < DIR_ENTRY_COUNT; i++) {
            if (entries[i].child_inode == 0U) {
                memset(&entries[i], 0, sizeof(entries[i]));
                entries[i].child_inode = child_index;
                entries[i].child_type = child_type;
                memcpy(entries[i].child_name, child_name, strlen(child_name));
                if (write_sector(FS_DATA_START_LBA + blocks[b], sector) < 0) {
                    free(blocks);
                    return -1;
                }
                free(blocks);
                return 0;
            }
        }
    }

    last_block = blocks[parent.blocks_cnt - 1U];
    free(blocks);
    if (alloc_fat_chain(1U, &new_block) < 0) return -1;

    memset(sector, 0, sizeof(sector));
    entries = (dir_entry_t *)sector;
    entries[0].child_inode = child_index;
    entries[0].child_type = child_type;
    memcpy(entries[0].child_name, child_name, strlen(child_name));
    if (write_sector(FS_DATA_START_LBA + new_block, sector) < 0) {
        free_fat_chain(new_block, 1U);
        return -1;
    }
    if (fat_write(last_block, (uint16_t)new_block) < 0) {
        free_fat_chain(new_block, 1U);
        return -1;
    }
    parent.blocks_cnt++;
    if (write_inode(parent_index, &parent) < 0) {
        fat_write(last_block, FAT_EOC);
        free_fat_chain(new_block, 1U);
        return -1;
    }
    return 0;
}

static int rollback_new_item(uint32_t inode_index, uint32_t first_block,
                             uint32_t block_count) {
    int result;

    result = 0;
    if (block_count != 0U && free_fat_chain(first_block, block_count) < 0) result = -1;
    if (free_inode(inode_index) < 0) result = -1;
    return result;
}

static int create_directory(uint32_t parent_index, const char *name,
                            uint32_t *inode_out) {
    uint32_t inode_index;
    uint32_t data_block;
    inode_t inode;
    uint8_t sector[SECTOR_SIZE];

    if (!name_valid(name) || alloc_inode(&inode_index) < 0) return -1;
    if (alloc_fat_chain(1U, &data_block) < 0) {
        free_inode(inode_index);
        return -1;
    }
    memset(sector, 0, sizeof(sector));
    if (write_sector(FS_DATA_START_LBA + data_block, sector) < 0) {
        rollback_new_item(inode_index, data_block, 1U);
        return -1;
    }

    memset(&inode, 0, sizeof(inode));
    inode.type = 2U;
    memcpy(inode.name, name, strlen(name));
    inode.start_block = data_block;
    inode.blocks_cnt = 1U;
    inode.parent = parent_index;
    if (write_inode(inode_index, &inode) < 0 ||
        add_dir_entry(parent_index, inode_index, 2U, name) < 0) {
        rollback_new_item(inode_index, data_block, 1U);
        return -1;
    }
    *inode_out = inode_index;
    return 0;
}

static int get_or_create_directory(uint32_t parent_index, const char *name,
                                   uint32_t *inode_out) {
    uint32_t child;
    uint8_t type;
    int found;
    inode_t inode;

    found = find_child(parent_index, name, &child, &type);
    if (found < 0) return -1;
    if (found) {
        if (type != 2U || read_inode(child, &inode) < 0 || inode.type != 2U) {
            fprintf(stderr, "Error: '%s' exists but is not a valid directory.\n", name);
            return -1;
        }
        *inode_out = child;
        return 0;
    }
    return create_directory(parent_index, name, inode_out);
}

static int inject_host_file(uint32_t parent_index, const char *host_path,
                            const char *fs_name) {
    FILE *host;
    long file_size_long;
    uint32_t file_size;
    uint32_t blocks_needed;
    uint32_t inode_index;
    uint32_t first_block;
    uint32_t *blocks;
    uint32_t remaining;
    uint32_t b;
    size_t wanted;
    uint8_t sector[SECTOR_SIZE];
    inode_t inode;
    uint32_t existing;
    uint8_t existing_type;
    int found;
    int trailing;
    int host_error;

    if (!name_valid(fs_name)) {
        fprintf(stderr, "Error: invalid filesystem name '%s'.\n", fs_name);
        return -1;
    }
    found = find_child(parent_index, fs_name, &existing, &existing_type);
    if (found < 0) return -1;
    if (found) {
        fprintf(stderr, "Error: destination entry '%s' already exists.\n", fs_name);
        return -1;
    }

    host = fopen(host_path, "rb");
    if (host == NULL) {
        fprintf(stderr, "Error: cannot open host file '%s': %s\n", host_path, strerror(errno));
        return -1;
    }
    if (fseek(host, 0, SEEK_END) != 0 || (file_size_long = ftell(host)) < 0 ||
        fseek(host, 0, SEEK_SET) != 0 ||
        (uint64_t)file_size_long > (uint64_t)FS_DATA_BLOCK_COUNT * SECTOR_SIZE ||
        (uint64_t)file_size_long > UINT32_MAX) {
        fprintf(stderr, "Error: cannot size host file '%s'.\n", host_path);
        fclose(host);
        return -1;
    }
    file_size = (uint32_t)file_size_long;
    blocks_needed = (file_size + SECTOR_SIZE - 1U) / SECTOR_SIZE;
    if (blocks_needed == 0U) blocks_needed = 1U;

    if (alloc_inode(&inode_index) < 0) {
        fclose(host);
        return -1;
    }
    if (alloc_fat_chain(blocks_needed, &first_block) < 0) {
        free_inode(inode_index);
        fclose(host);
        return -1;
    }
    if (collect_chain(first_block, blocks_needed, &blocks) < 0) {
        rollback_new_item(inode_index, first_block, blocks_needed);
        fclose(host);
        return -1;
    }

    remaining = file_size;
    for (b = 0; b < blocks_needed; b++) {
        memset(sector, 0, sizeof(sector));
        wanted = remaining < SECTOR_SIZE ? remaining : SECTOR_SIZE;
        if (wanted != 0U && fread(sector, 1, wanted, host) != wanted) {
            fprintf(stderr, "Error: short read from host file '%s'.\n", host_path);
            free(blocks);
            rollback_new_item(inode_index, first_block, blocks_needed);
            fclose(host);
            return -1;
        }
        if (write_sector(FS_DATA_START_LBA + blocks[b], sector) < 0) {
            free(blocks);
            rollback_new_item(inode_index, first_block, blocks_needed);
            fclose(host);
            return -1;
        }
        remaining -= (uint32_t)wanted;
    }
    free(blocks);
    trailing = fgetc(host);
    host_error = remaining != 0U || trailing != EOF || ferror(host);
    if (fclose(host) != 0) host_error = 1;
    if (host_error) {
        fprintf(stderr, "Error: host file '%s' changed or failed during injection.\n", host_path);
        rollback_new_item(inode_index, first_block, blocks_needed);
        return -1;
    }

    memset(&inode, 0, sizeof(inode));
    inode.type = 1U;
    memcpy(inode.name, fs_name, strlen(fs_name));
    inode.size = file_size;
    inode.start_block = first_block;
    inode.blocks_cnt = blocks_needed;
    inode.parent = parent_index;
    if (write_inode(inode_index, &inode) < 0 ||
        add_dir_entry(parent_index, inode_index, 1U, fs_name) < 0) {
        rollback_new_item(inode_index, first_block, blocks_needed);
        return -1;
    }

    printf("Injected file '%s' (%u bytes, %u sectors) -> inode %u, LBA %u\n",
           fs_name, file_size, blocks_needed, inode_index,
           FS_DATA_START_LBA + first_block);
    return 0;
}

static int skip_host_metadata(const char *name) {
    return strcmp(name, ".") == 0 || strcmp(name, "..") == 0 ||
           strcmp(name, ".DS_Store") == 0 || strcmp(name, "Thumbs.db") == 0 ||
           strcmp(name, ".git") == 0 || strncmp(name, "._", 2U) == 0;
}

static int process_directory_tree(uint32_t target_inode, const char *host_path) {
    struct dirent **entries;
    struct stat status;
    char full_path[1024];
    uint32_t child_inode;
    int count;
    int i;
    int result;

    count = scandir(host_path, &entries, NULL, alphasort);
    if (count < 0) {
        fprintf(stderr, "Error: cannot scan '%s': %s\n", host_path, strerror(errno));
        return -1;
    }
    result = 0;
    for (i = 0; i < count; i++) {
        if (result == 0 && !skip_host_metadata(entries[i]->d_name)) {
            if (!name_valid(entries[i]->d_name)) {
                fprintf(stderr, "Error: invalid host name '%s'.\n", entries[i]->d_name);
                result = -1;
            } else if (snprintf(full_path, sizeof(full_path), "%s/%s", host_path,
                                entries[i]->d_name) >= (int)sizeof(full_path)) {
                fprintf(stderr, "Error: host path is too long under '%s'.\n", host_path);
                result = -1;
            } else if (lstat(full_path, &status) != 0) {
                fprintf(stderr, "Error: cannot inspect '%s': %s\n", full_path, strerror(errno));
                result = -1;
            } else if (S_ISDIR(status.st_mode)) {
                if (get_or_create_directory(target_inode, entries[i]->d_name,
                                            &child_inode) < 0 ||
                    process_directory_tree(child_inode, full_path) < 0) {
                    result = -1;
                }
            } else if (S_ISREG(status.st_mode)) {
                if (inject_host_file(target_inode, full_path, entries[i]->d_name) < 0) {
                    result = -1;
                }
            } else {
                fprintf(stderr, "Error: unsupported host item '%s'.\n", full_path);
                result = -1;
            }
        }
        free(entries[i]);
    }
    free(entries);
    return result;
}

static int superblock_matches_layout(const uint8_t sector[SECTOR_SIZE]) {
    uint32_t values[6];

    memcpy(values, sector, sizeof(values));
    return values[0] == FS_MAGIC && values[1] == FS_INODE_COUNT &&
           values[2] == FS_DATA_BLOCK_COUNT && values[3] == FS_INODE_START_LBA &&
           values[4] == FS_DATA_START_LBA && values[5] == 0U;
}

static int format_fresh_filesystem(void) {
    uint8_t sector[SECTOR_SIZE];
    uint32_t superblock[6];
    uint32_t i;
    uint32_t root_block;
    uint32_t readme_block;
    inode_t inode;
    dir_entry_t *entries;
    const char *readme_name;
    const char *readme_content;
    size_t readme_length;

    memset(sector, 0, sizeof(sector));
    if (write_sector(FS_SUPERBLOCK_LBA, sector) < 0 ||
        write_sector(FS_INODE_BMAP_LBA, sector) < 0) return -1;
    for (i = 0; i < FS_FAT_SECS; i++) {
        if (write_sector(FS_FAT_LBA + i, sector) < 0) return -1;
    }
    for (i = 0; i < FS_INODE_SECS; i++) {
        if (write_sector(FS_INODE_START_LBA + i, sector) < 0) return -1;
    }
    if (bitmap_update(0U, 1) < 0 || bitmap_update(1U, 1) < 0 ||
        fat_write(0U, FAT_EOC) < 0 || fat_write(1U, FAT_EOC) < 0) return -1;

    superblock[0] = FS_MAGIC;
    superblock[1] = FS_INODE_COUNT;
    superblock[2] = FS_DATA_BLOCK_COUNT;
    superblock[3] = FS_INODE_START_LBA;
    superblock[4] = FS_DATA_START_LBA;
    superblock[5] = 0U;
    memset(sector, 0, sizeof(sector));
    memcpy(sector, superblock, sizeof(superblock));
    if (write_sector(FS_SUPERBLOCK_LBA, sector) < 0 ||
        alloc_fat_chain(1U, &root_block) < 0 ||
        alloc_fat_chain(1U, &readme_block) < 0) return -1;

    memset(&inode, 0, sizeof(inode));
    inode.type = 2U;
    inode.name[0] = '/';
    inode.start_block = root_block;
    inode.blocks_cnt = 1U;
    if (write_inode(0U, &inode) < 0) return -1;

    readme_name = "README.TXT";
    readme_content = "Welcome to MINI_OS.\nTry: cd /transport/build/apps, ls, run hello.bin\n";
    readme_length = strlen(readme_content);
    memset(&inode, 0, sizeof(inode));
    inode.type = 1U;
    memcpy(inode.name, readme_name, strlen(readme_name));
    inode.size = (uint32_t)readme_length;
    inode.start_block = readme_block;
    inode.blocks_cnt = 1U;
    if (write_inode(1U, &inode) < 0) return -1;

    memset(sector, 0, sizeof(sector));
    entries = (dir_entry_t *)sector;
    entries[0].child_inode = 1U;
    entries[0].child_type = 1U;
    memcpy(entries[0].child_name, readme_name, strlen(readme_name));
    if (write_sector(FS_DATA_START_LBA + root_block, sector) < 0) return -1;
    memset(sector, 0, sizeof(sector));
    memcpy(sector, readme_content, readme_length);
    if (write_sector(FS_DATA_START_LBA + readme_block, sector) < 0) return -1;

    printf("Formatted fresh MINI-OS filesystem on disk image.\n");
    return 0;
}

static const char *path_basename(const char *path) {
    const char *slash;

    slash = strrchr(path, '/');
    return slash != NULL && slash[1] != '\0' ? slash + 1 : path;
}

static int validate_geometry(void) {
    uint64_t required_size;

    if ((uint64_t)FS_FAT_SECS * SECTOR_SIZE <
            (uint64_t)FS_DATA_BLOCK_COUNT * sizeof(uint16_t) ||
        FS_FAT_LBA + FS_FAT_SECS > FS_INODE_START_LBA ||
        FS_INODE_START_LBA + FS_INODE_SECS > FS_DATA_START_LBA) {
        fprintf(stderr, "Error: filesystem constants describe overlapping metadata.\n");
        return -1;
    }
    required_size = FS_TOTAL_SECTORS * SECTOR_SIZE;
    if (img_size < required_size) {
        fprintf(stderr,
                "Error: image is %llu bytes; filesystem geometry requires at least %llu bytes (%llu sectors).\n",
                (unsigned long long)img_size, (unsigned long long)required_size,
                (unsigned long long)FS_TOTAL_SECTORS);
        return -1;
    }
    return 0;
}

int main(int argc, char **argv) {
    const char *image_path;
    const char *host_directory;
    const char *target_name;
    long size;
    uint8_t superblock[SECTOR_SIZE];
    uint32_t target_inode;
    int result;

    if (argc < 3 || argc > 4) {
        fprintf(stderr, "Usage: %s <mini_os.img> <host_source_dir> [target_name]\n", argv[0]);
        return 1;
    }
    image_path = argv[1];
    host_directory = argv[2];
    target_name = argc == 4 ? argv[3] : path_basename(host_directory);
    if (!name_valid(target_name)) {
        fprintf(stderr,
                "Error: target directory name must contain 1..26 bytes and cannot be '.', '..', or contain '/'.\n");
        return 1;
    }

    img_fp = fopen(image_path, "rb+");
    if (img_fp == NULL) {
        fprintf(stderr, "Error: cannot open disk image '%s': %s\n", image_path, strerror(errno));
        return 1;
    }
    if (fseek(img_fp, 0, SEEK_END) != 0 || (size = ftell(img_fp)) < 0) {
        fprintf(stderr, "Error: cannot determine image size.\n");
        fclose(img_fp);
        return 1;
    }
    img_size = (uint64_t)size;
    if (validate_geometry() < 0 || read_sector(FS_SUPERBLOCK_LBA, superblock) < 0) {
        fclose(img_fp);
        return 1;
    }

    if (!superblock_matches_layout(superblock)) {
        if (format_fresh_filesystem() < 0) {
            fclose(img_fp);
            return 1;
        }
    } else {
        printf("MINI-OS filesystem verified. Injecting '%s' at '/%s'.\n",
               host_directory, target_name);
    }

    result = get_or_create_directory(0U, target_name, &target_inode);
    if (result == 0) result = process_directory_tree(target_inode, host_directory);
    if (result < 0) fprintf(stderr, "Injection failed; the disk image is incomplete.\n");
    if (fclose(img_fp) != 0) {
        fprintf(stderr, "Error: cannot close disk image: %s\n", strerror(errno));
        result = -1;
    }
    if (result < 0) return 1;
    printf("Injection complete.\n");
    return 0;
}
