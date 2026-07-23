#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <dirent.h>
#include <sys/stat.h>

#define SECTOR_SIZE 512
#define FS_MAGIC 0x534F5359

#define FS_SUPERBLOCK_LBA 101
#define FS_INODE_BMAP_LBA 102
#define FS_DATA_BMAP_LBA 103
#define FS_INODE_START_LBA 111
#define FS_DATA_START_LBA 367

#define FS_INODE_COUNT 2048
#define FS_DATA_BLOCK_COUNT 4096

#pragma pack(push, 1)
typedef struct {
    uint8_t type;         // 0=free, 1=file, 2=dir (1B)
    char name[27];        // (27B)
    uint32_t size;        // (4B)
    uint32_t start_block; // LBA (4B)
    uint32_t blocks_cnt;  // (4B)
    uint32_t parent;      // (4B)
    uint8_t reserved[20]; // (20B) -> Total exactly 64 bytes
} inode_t;
typedef struct {
    uint32_t child_inode; // (4B)
    uint8_t child_type;   // 1=file, 2=dir (1B)
    char child_name[27];  // (27B) -> Total exactly 32 bytes
} dir_entry_t;
#pragma pack(pop)


static FILE *img_fp = NULL;

static void read_sector(uint32_t lba, void *buf) {
    fseek(img_fp, lba * SECTOR_SIZE, SEEK_SET);
    fread(buf, 1, SECTOR_SIZE, img_fp);
}

static void write_sector(uint32_t lba, const void *buf) {
    fseek(img_fp, lba * SECTOR_SIZE, SEEK_SET);
    fwrite(buf, 1, SECTOR_SIZE, img_fp);
    fflush(img_fp);
}

static int bitmap_test(uint32_t base_lba, uint32_t bit_idx) {
    uint32_t byte_off = bit_idx / 8;
    uint32_t sector_off = byte_off / SECTOR_SIZE;
    uint32_t in_sector_byte = byte_off % SECTOR_SIZE;
    uint8_t bit_off = bit_idx % 8;

    uint8_t sector_buf[SECTOR_SIZE];
    read_sector(base_lba + sector_off, sector_buf);
    return (sector_buf[in_sector_byte] >> bit_off) & 1;
}

static void bitmap_set(uint32_t base_lba, uint32_t bit_idx) {
    uint32_t byte_off = bit_idx / 8;
    uint32_t sector_off = byte_off / SECTOR_SIZE;
    uint32_t in_sector_byte = byte_off % SECTOR_SIZE;
    uint8_t bit_off = bit_idx % 8;

    uint8_t sector_buf[SECTOR_SIZE];
    read_sector(base_lba + sector_off, sector_buf);
    sector_buf[in_sector_byte] |= (1 << bit_off);
    write_sector(base_lba + sector_off, sector_buf);
}

static int alloc_inode(void) {
    for (uint32_t i = 2; i < FS_INODE_COUNT; i++) {
        if (!bitmap_test(FS_INODE_BMAP_LBA, i)) {
            bitmap_set(FS_INODE_BMAP_LBA, i);
            return (int)i;
        }
    }
    return -1;
}

static int alloc_contiguous_data_blocks(uint32_t count) {
    if (count == 0) return 0;
    uint32_t consecutive = 0;
    uint32_t start_idx = 0;

    for (uint32_t i = 2; i < FS_DATA_BLOCK_COUNT; i++) {
        if (!bitmap_test(FS_DATA_BMAP_LBA, i)) {
            if (consecutive == 0) start_idx = i;
            consecutive++;
            if (consecutive == count) {
                for (uint32_t j = start_idx; j < start_idx + count; j++) {
                    bitmap_set(FS_DATA_BMAP_LBA, j);
                }
                return (int)start_idx;
            }
        } else {
            consecutive = 0;
        }
    }
    return -1;
}

static void read_inode(uint32_t inode_idx, inode_t *inode) {
    uint32_t sector_off = inode_idx / 8;
    uint32_t in_sector_idx = inode_idx % 8;
    uint8_t sector_buf[SECTOR_SIZE];
    read_sector(FS_INODE_START_LBA + sector_off, sector_buf);
    memcpy(inode, sector_buf + (in_sector_idx * sizeof(inode_t)), sizeof(inode_t));
}

static void write_inode(uint32_t inode_idx, const inode_t *inode) {
    uint32_t sector_off = inode_idx / 8;
    uint32_t in_sector_idx = inode_idx % 8;
    uint8_t sector_buf[SECTOR_SIZE];
    read_sector(FS_INODE_START_LBA + sector_off, sector_buf);
    memcpy(sector_buf + (in_sector_idx * sizeof(inode_t)), inode, sizeof(inode_t));
    write_sector(FS_INODE_START_LBA + sector_off, sector_buf);
}

static void add_dir_entry(uint32_t parent_inode_idx, uint32_t child_inode_idx, uint8_t child_type, const char *child_name) {
    inode_t parent_inode;
    read_inode(parent_inode_idx, &parent_inode);

    uint32_t data_lba = parent_inode.start_block;
    uint8_t sector_buf[SECTOR_SIZE];
    read_sector(data_lba, sector_buf);

    dir_entry_t *entries = (dir_entry_t *)sector_buf;
    for (int i = 0; i < 16; i++) {
        if (entries[i].child_inode == 0) {
            entries[i].child_inode = child_inode_idx;
            entries[i].child_type = child_type;
            memset(entries[i].child_name, 0, 27);
            strncpy(entries[i].child_name, child_name, 26);
            write_sector(data_lba, sector_buf);
            return;
        }
    }
    fprintf(stderr, "Error: Directory data block full for inode %u\n", parent_inode_idx);
}

static int get_or_create_dir_entry(uint32_t parent_inode_idx, const char *dir_name) {
    inode_t parent_inode;
    read_inode(parent_inode_idx, &parent_inode);

    uint8_t sector_buf[SECTOR_SIZE];
    read_sector(parent_inode.start_block, sector_buf);

    dir_entry_t *entries = (dir_entry_t *)sector_buf;
    for (int i = 0; i < 16; i++) {
        if (entries[i].child_inode != 0 && strcasecmp(entries[i].child_name, dir_name) == 0) {
            return entries[i].child_inode;
        }
    }

    // Create directory
    int new_inode_idx = alloc_inode();
    int new_data_block = alloc_contiguous_data_blocks(1);
    if (new_inode_idx < 0 || new_data_block < 0) {
        fprintf(stderr, "Error allocating inode/block for directory %s\n", dir_name);
        return -1;
    }

    inode_t new_dir_inode;
    memset(&new_dir_inode, 0, sizeof(new_dir_inode));
    new_dir_inode.type = 2; // dir
    strncpy(new_dir_inode.name, dir_name, 26);
    new_dir_inode.size = 0;
    new_dir_inode.start_block = FS_DATA_START_LBA + new_data_block;
    new_dir_inode.blocks_cnt = 1;
    new_dir_inode.parent = parent_inode_idx;
    write_inode(new_inode_idx, &new_dir_inode);

    // Clear new dir data sector
    memset(sector_buf, 0, SECTOR_SIZE);
    write_sector(new_dir_inode.start_block, sector_buf);

    // Add entry in parent
    add_dir_entry(parent_inode_idx, new_inode_idx, 2, dir_name);
    return new_inode_idx;
}

static void inject_host_file(uint32_t parent_inode_idx, const char *host_path, const char *fs_name) {
    FILE *f = fopen(host_path, "rb");
    if (!f) {
        fprintf(stderr, "Failed to open host file: %s\n", host_path);
        return;
    }

    fseek(f, 0, SEEK_END);
    long file_size = ftell(f);
    fseek(f, 0, SEEK_SET);

    uint32_t blocks_needed = (file_size + SECTOR_SIZE - 1) / SECTOR_SIZE;
    if (blocks_needed == 0) blocks_needed = 1;

    int new_inode_idx = alloc_inode();
    int new_data_block = alloc_contiguous_data_blocks(blocks_needed);
    if (new_inode_idx < 0 || new_data_block < 0) {
        fprintf(stderr, "Error allocating space for file %s\n", fs_name);
        fclose(f);
        return;
    }

    uint32_t start_lba = FS_DATA_START_LBA + new_data_block;

    // Read and write payload
    uint8_t sector_buf[SECTOR_SIZE];
    for (uint32_t b = 0; b < blocks_needed; b++) {
        memset(sector_buf, 0, SECTOR_SIZE);
        fread(sector_buf, 1, SECTOR_SIZE, f);
        write_sector(start_lba + b, sector_buf);
    }
    fclose(f);

    // Write inode
    inode_t file_inode;
    memset(&file_inode, 0, sizeof(file_inode));
    file_inode.type = 1; // file
    strncpy(file_inode.name, fs_name, 26);
    file_inode.size = (uint32_t)file_size;
    file_inode.start_block = start_lba;
    file_inode.blocks_cnt = blocks_needed;
    file_inode.parent = parent_inode_idx;
    write_inode(new_inode_idx, &file_inode);

    // Add entry in parent
    add_dir_entry(parent_inode_idx, new_inode_idx, 1, fs_name);
    printf("Injected file '%s' (%ld bytes, %u sectors) -> inode %d, LBA %u\n",
           fs_name, file_size, blocks_needed, new_inode_idx, start_lba);
}

static void process_directory_tree(uint32_t target_fs_inode, const char *host_dir_path) {
    DIR *d = opendir(host_dir_path);
    if (!d) return;

    struct dirent *dir;
    while ((dir = readdir(d)) != NULL) {
        if (strcmp(dir->d_name, ".") == 0 || strcmp(dir->d_name, "..") == 0) continue;

        char full_host_path[1024];
        snprintf(full_host_path, sizeof(full_host_path), "%s/%s", host_dir_path, dir->d_name);

        struct stat st;
        if (stat(full_host_path, &st) == 0) {
            if (S_ISDIR(st.st_mode)) {
                int child_dir_inode = get_or_create_dir_entry(target_fs_inode, dir->d_name);
                if (child_dir_inode >= 0) {
                    process_directory_tree(child_dir_inode, full_host_path);
                }
            } else if (S_ISREG(st.st_mode)) {
                inject_host_file(target_fs_inode, full_host_path, dir->d_name);
            }
        }
    }
    closedir(d);
}

static void format_fresh_filesystem(void) {
    uint8_t zero_sec[SECTOR_SIZE];
    memset(zero_sec, 0, SECTOR_SIZE);

    // Clear Bitmaps and Inode table
    write_sector(FS_SUPERBLOCK_LBA, zero_sec);
    write_sector(FS_INODE_BMAP_LBA, zero_sec);
    for (uint32_t i = 0; i < 8; i++) write_sector(FS_DATA_BMAP_LBA + i, zero_sec);
    for (uint32_t i = 0; i < 256; i++) write_sector(FS_INODE_START_LBA + i, zero_sec);

    // 1. Superblock (LBA 101)
    uint32_t sb[6];
    sb[0] = FS_MAGIC;
    sb[1] = FS_INODE_COUNT;
    sb[2] = FS_DATA_BLOCK_COUNT;
    sb[3] = FS_INODE_START_LBA;
    sb[4] = FS_DATA_START_LBA;
    sb[5] = 0; // Root inode
    memset(zero_sec, 0, SECTOR_SIZE);
    memcpy(zero_sec, sb, sizeof(sb));
    write_sector(FS_SUPERBLOCK_LBA, zero_sec);

    // 2. Bitmaps (Bit 0 and Bit 1 reserved)
    bitmap_set(FS_INODE_BMAP_LBA, 0);
    bitmap_set(FS_INODE_BMAP_LBA, 1);
    bitmap_set(FS_DATA_BMAP_LBA, 0);
    bitmap_set(FS_DATA_BMAP_LBA, 1);

    // 3. Inode 0 (Root)
    inode_t root_inode;
    memset(&root_inode, 0, sizeof(root_inode));
    root_inode.type = 2; // dir
    root_inode.name[0] = '/';
    root_inode.start_block = FS_DATA_START_LBA;
    root_inode.blocks_cnt = 1;
    root_inode.parent = 0;
    write_inode(0, &root_inode);

    // 4. Inode 1 (README.TXT)
    const char *readme_name = "README.TXT";
    const char *readme_content = "Welcome to MINI_OS.\nThis disk was initialized by the kernel formatter.\nTry: ls, cd external, run hello.bin\n";
    uint32_t readme_len = (uint32_t)strlen(readme_content);

    inode_t readme_inode;
    memset(&readme_inode, 0, sizeof(readme_inode));
    readme_inode.type = 1; // file
    strncpy(readme_inode.name, readme_name, 26);
    readme_inode.size = readme_len;
    readme_inode.start_block = FS_DATA_START_LBA + 1;
    readme_inode.blocks_cnt = 1;
    readme_inode.parent = 0;
    write_inode(1, &readme_inode);

    // 5. Root Directory Data Block (LBA 367)
    memset(zero_sec, 0, SECTOR_SIZE);
    dir_entry_t *root_entries = (dir_entry_t *)zero_sec;
    root_entries[0].child_inode = 1;
    root_entries[0].child_type = 1;
    strncpy(root_entries[0].child_name, readme_name, 26);
    write_sector(FS_DATA_START_LBA, zero_sec);

    // 6. README.TXT Data Block (LBA 368)
    memset(zero_sec, 0, SECTOR_SIZE);
    memcpy(zero_sec, readme_content, readme_len);
    write_sector(FS_DATA_START_LBA + 1, zero_sec);

    printf("Formatted fresh MINI-OS filesystem on disk image.\n");
}

static const char *get_basename_path(const char *path) {
    const char *base = strrchr(path, '/');
    if (base && *(base + 1) != '\0') return base + 1;
    return path;
}

int main(int argc, char *argv[]) {
    if (argc < 3) {
        fprintf(stderr, "Usage: %s <mini_os.img> <host_source_dir>\n", argv[0]);
        return 1;
    }

    const char *img_path = argv[1];
    const char *transport_dir = argv[2];
    const char *target_os_dir = (argc >= 4) ? argv[3] : get_basename_path(transport_dir);

    img_fp = fopen(img_path, "rb+");
    if (!img_fp) {
        perror("Failed to open disk image");
        return 1;
    }

    // Verify Superblock
    uint8_t sb_buf[SECTOR_SIZE];
    read_sector(FS_SUPERBLOCK_LBA, sb_buf);
    uint32_t magic = *(uint32_t *)(sb_buf);
    if (magic != FS_MAGIC) {
        format_fresh_filesystem();
    } else {
        printf("MINI-OS filesystem verified. Injecting '%s' -> OS directory '/%s'...\n", transport_dir, target_os_dir);
    }

    int root_target_inode = get_or_create_dir_entry(0, target_os_dir);
    if (root_target_inode < 0) {
        fprintf(stderr, "Failed to create target OS directory '/%s'\n", target_os_dir);
        fclose(img_fp);
        return 1;
    }

    process_directory_tree((uint32_t)root_target_inode, transport_dir);


    fclose(img_fp);
    printf("Injection complete.\n");
    return 0;
}

