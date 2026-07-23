#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#define ELF_MAGIC "\x7f" "ELF"

#pragma pack(push, 1)
typedef struct {
    unsigned char e_ident[16];
    uint16_t e_type;
    uint16_t e_machine;
    uint32_t e_version;
    uint32_t e_entry;
    uint32_t e_phoff;
    uint32_t e_shoff;
    uint32_t e_flags;
    uint16_t e_ehsize;
    uint16_t e_phentsize;
    uint16_t e_phnum;
    uint16_t e_shentsize;
    uint16_t e_shnum;
    uint16_t e_shstrndx;
} Elf32_Ehdr;

typedef struct {
    uint32_t sh_name;
    uint32_t sh_type;
    uint32_t sh_flags;
    uint32_t sh_addr;
    uint32_t sh_offset;
    uint32_t sh_size;
    uint32_t sh_link;
    uint32_t sh_info;
    uint32_t sh_addralign;
    uint32_t sh_entsize;
} Elf32_Shdr;

typedef struct {
    uint32_t st_name;
    uint32_t st_value;
    uint32_t st_size;
    uint8_t  st_info;
    uint8_t  st_other;
    uint16_t st_shndx;
} Elf32_Sym;

typedef struct {
    uint32_t r_offset;
    uint32_t r_info;
} Elf32_Rel;
#pragma pack(pop)

#define SHT_PROGBITS 1
#define SHT_SYMTAB   2
#define SHT_STRTAB   3
#define SHT_RELA     4
#define SHT_NOBITS   8
#define SHT_REL      9

#define R_386_32   1
#define R_386_PC32 2

#define ELF32_R_SYM(val)  ((val) >> 8)
#define ELF32_R_TYPE(val) ((val) & 0xff)

typedef struct {
    char name[128];
    uint32_t addr;
    int defined;
} Symbol;

#define MAX_SYMBOLS 1024
#define MAX_BUF_SIZE (512 * 1024)

static Symbol symtab_global[MAX_SYMBOLS];
static int sym_count = 0;

static uint8_t out_buf[MAX_BUF_SIZE];
static uint32_t out_size = 0;

static void add_symbol(const char *name, uint32_t addr, int defined) {
    if (!name || strlen(name) == 0) return;
    for (int i = 0; i < sym_count; i++) {
        if (strcmp(symtab_global[i].name, name) == 0) {
            if (defined && !symtab_global[i].defined) {
                symtab_global[i].addr = addr;
                symtab_global[i].defined = 1;
            }
            return;
        }
    }
    if (sym_count < MAX_SYMBOLS) {
        strncpy(symtab_global[sym_count].name, name, 127);
        symtab_global[sym_count].addr = addr;
        symtab_global[sym_count].defined = defined;
        sym_count++;
    }
}

static uint32_t find_symbol(const char *name) {
    for (int i = 0; i < sym_count; i++) {
        if (strcmp(symtab_global[i].name, name) == 0) {
            if (!symtab_global[i].defined) {
                fprintf(stderr, "Warning: Symbol '%s' referenced but undefined.\n", name);
            }
            return symtab_global[i].addr;
        }
    }
    fprintf(stderr, "Error: Symbol '%s' not found.\n", name);
    return 0;
}

typedef struct {
    char name[128];
    uint8_t *file_data;
    Elf32_Ehdr *ehdr;
    Elf32_Shdr *shdrs;
    char *shstrtab;
    uint32_t section_out_offs[64];
} ObjFile;

int main(int argc, char *argv[]) {
    if (argc < 4) {
        fprintf(stderr, "Usage: %s <output.bin> <base_addr_hex> <obj1.o> [obj2.o ...]\n", argv[0]);
        return 1;
    }

    const char *out_file = argv[1];
    uint32_t base_addr = (uint32_t)strtoul(argv[2], NULL, 0);

    int num_objs = argc - 3;
    ObjFile *objs = calloc(num_objs, sizeof(ObjFile));

    memset(out_buf, 0, sizeof(out_buf));
    out_size = 0;

    // Pass 1: Read files and collect sections into out_buf
    for (int o = 0; o < num_objs; o++) {
        const char *filename = argv[o + 3];
        strncpy(objs[o].name, filename, 127);

        FILE *f = fopen(filename, "rb");
        if (!f) {
            perror(filename);
            return 1;
        }

        fseek(f, 0, SEEK_END);
        long sz = ftell(f);
        fseek(f, 0, SEEK_SET);

        objs[o].file_data = malloc(sz);
        fread(objs[o].file_data, 1, sz, f);
        fclose(f);

        Elf32_Ehdr *ehdr = (Elf32_Ehdr *)objs[o].file_data;
        if (memcmp(ehdr->e_ident, ELF_MAGIC, 4) != 0 || ehdr->e_machine != 3) {
            fprintf(stderr, "%s is not a valid 32-bit x86 ELF object.\n", filename);
            return 1;
        }

        objs[o].ehdr = ehdr;
        objs[o].shdrs = (Elf32_Shdr *)(objs[o].file_data + ehdr->e_shoff);
        objs[o].shstrtab = (char *)(objs[o].file_data + objs[o].shdrs[ehdr->e_shstrndx].sh_offset);

        // Copy SHF_ALLOC sections (.text, .rodata, .data)
        for (int i = 0; i < ehdr->e_shnum; i++) {
            Elf32_Shdr *sh = &objs[o].shdrs[i];
            const char *sec_name = objs[o].shstrtab + sh->sh_name;

            if (sh->sh_type == SHT_PROGBITS && (sh->sh_flags & 2)) { // SHF_ALLOC = 2
                // Align out_size
                uint32_t align = sh->sh_addralign ? sh->sh_addralign : 4;
                out_size = (out_size + align - 1) & ~(align - 1);

                objs[o].section_out_offs[i] = out_size;
                memcpy(out_buf + out_size, objs[o].file_data + sh->sh_offset, sh->sh_size);
                out_size += sh->sh_size;
            }
        }
    }

    // Pass 2: Collect Symbols
    for (int o = 0; o < num_objs; o++) {
        Elf32_Ehdr *ehdr = objs[o].ehdr;
        for (int i = 0; i < ehdr->e_shnum; i++) {
            Elf32_Shdr *sh = &objs[o].shdrs[i];
            if (sh->sh_type == SHT_SYMTAB) {
                Elf32_Sym *syms = (Elf32_Sym *)(objs[o].file_data + sh->sh_offset);
                int num_syms = sh->sh_size / sizeof(Elf32_Sym);
                char *strtab = (char *)(objs[o].file_data + objs[o].shdrs[sh->sh_link].sh_offset);

                for (int s = 0; s < num_syms; s++) {
                    const char *sym_name = strtab + syms[s].st_name;
                    uint16_t shndx = syms[s].st_shndx;

                    if (shndx > 0 && shndx < ehdr->e_shnum) {
                        uint32_t sec_off = objs[o].section_out_offs[shndx];
                        uint32_t sym_addr = base_addr + sec_off + syms[s].st_value;
                        add_symbol(sym_name, sym_addr, 1);
                    } else if (shndx == 0 && strlen(sym_name) > 0) {
                        add_symbol(sym_name, 0, 0);
                    }
                }
            }
        }
    }

    // Pass 3: Apply Relocations (R_386_32 & R_386_PC32)
    for (int o = 0; o < num_objs; o++) {
        Elf32_Ehdr *ehdr = objs[o].ehdr;
        for (int i = 0; i < ehdr->e_shnum; i++) {
            Elf32_Shdr *sh = &objs[o].shdrs[i];
            if (sh->sh_type == SHT_REL) {
                uint32_t target_sec = sh->sh_info;
                uint32_t sec_out_off = objs[o].section_out_offs[target_sec];

                Elf32_Rel *rels = (Elf32_Rel *)(objs[o].file_data + sh->sh_offset);
                int num_rels = sh->sh_size / sizeof(Elf32_Rel);

                Elf32_Shdr *symsec = &objs[o].shdrs[sh->sh_link];
                Elf32_Sym *syms = (Elf32_Sym *)(objs[o].file_data + symsec->sh_offset);
                char *strtab = (char *)(objs[o].file_data + objs[o].shdrs[symsec->sh_link].sh_offset);

                for (int r = 0; r < num_rels; r++) {
                    uint32_t sym_idx = ELF32_R_SYM(rels[r].r_info);
                    uint32_t type = ELF32_R_TYPE(rels[r].r_info);

                    Elf32_Sym *sym = &syms[sym_idx];
                    const char *sym_name = strtab + sym->st_name;

                    uint32_t S = 0;
                    if (sym->st_shndx > 0 && sym->st_shndx < ehdr->e_shnum) {
                        S = base_addr + objs[o].section_out_offs[sym->st_shndx] + sym->st_value;
                    } else {
                        S = find_symbol(sym_name);
                    }

                    uint32_t P = base_addr + sec_out_off + rels[r].r_offset;
                    uint32_t *patch_loc = (uint32_t *)(out_buf + sec_out_off + rels[r].r_offset);
                    int32_t A = (int32_t)*patch_loc;

                    if (type == R_386_32) {
                        *patch_loc = S + A;
                    } else if (type == R_386_PC32) {
                        *patch_loc = S + A - P;
                    } else {
                        fprintf(stderr, "Unsupported relocation type %u in %s\n", type, objs[o].name);
                    }
                }
            }
        }
    }

    FILE *out_fp = fopen(out_file, "wb");
    if (!out_fp) {
        perror(out_file);
        return 1;
    }
    fwrite(out_buf, 1, out_size, out_fp);
    fclose(out_fp);

    printf("elf2bin: Generated '%s' (%u bytes) at base 0x%08X\n", out_file, out_size, base_addr);

    for (int o = 0; o < num_objs; o++) free(objs[o].file_data);
    free(objs);
    return 0;
}
