#!/usr/bin/env python3
"""Build-policy, dependency, and fallback-linker regression checks."""

from __future__ import annotations

from pathlib import Path
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time
from typing import Optional


SECTOR_SIZE = 512
BOOT_ID_OFFSET = 504
BOOT_ID_SIZE = 6
SUPERBLOCK_LBA = 101
SUPER_DIRTY_OFFSET = 24
FAT_LBA = 103
INODE_START_LBA = 119
DATA_START_LBA = 375
INODE_SIZE = 64
INODE_NAME_CAP = 27


def run(
    command: list[str],
    cwd: Path,
    expect_success: bool = True,
    env: Optional[dict[str, str]] = None,
) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        command, cwd=cwd, text=True, capture_output=True, env=env
    )
    if expect_success and result.returncode != 0:
        raise RuntimeError(
            f"command failed: {' '.join(command)}\n{result.stdout}{result.stderr}"
        )
    if not expect_success and result.returncode == 0:
        raise RuntimeError(f"command unexpectedly succeeded: {' '.join(command)}")
    return result


def copy_repository(source: Path, destination: Path) -> None:
    def ignore(directory: str, names: list[str]) -> set[str]:
        ignored = {".git", "build", "local", "__pycache__", ".DS_Store"}
        if Path(directory).name == "transport":
            ignored.add("build")
        return ignored.intersection(names)

    shutil.copytree(source, destination, ignore=ignore)


def timestamp(path: Path) -> int:
    return path.stat().st_mtime_ns


def make_source_newer(path: Path) -> None:
    time.sleep(1.05)
    os.utime(path, None)


def assert_changed(before: dict[Path, int], paths: list[Path], label: str) -> None:
    unchanged = [str(path) for path in paths if timestamp(path) == before[path]]
    if unchanged:
        raise RuntimeError(f"{label} did not rebuild: {', '.join(unchanged)}")


def assert_unchanged(before: dict[Path, int], paths: list[Path], label: str) -> None:
    changed = [str(path) for path in paths if timestamp(path) != before[path]]
    if changed:
        raise RuntimeError(f"{label} rebuilt unexpectedly: {', '.join(changed)}")


def smoke(repo: Path) -> None:
    run(
        [
            sys.executable,
            "tests/qemu_e2e.py",
            "--image",
            "build/mini_os.img",
            "--checker",
            "build/check_image",
            "--smoke",
        ],
        repo,
    )


def expect_checker_failure(repo: Path, image: Path) -> None:
    run(["build/check_image", str(image)], repo, expect_success=False)


def verify_kernel_entry_stub(repo: Path) -> None:
    kernel = (repo / "build/kernel.bin").read_bytes()
    if len(kernel) >= 5 and kernel[0] == 0xE9:
        instruction_size = 5
        displacement = struct.unpack_from("<i", kernel, 1)[0]
    elif len(kernel) >= 2 and kernel[0] == 0xEB:
        instruction_size = 2
        displacement = struct.unpack_from("<b", kernel, 1)[0]
    else:
        raise RuntimeError("kernel image does not begin with a jump entry stub")
    target = instruction_size + displacement
    if target < instruction_size or target >= len(kernel):
        raise RuntimeError("kernel entry stub jumps outside the kernel image")


def reject_corrupt_images(repo: Path) -> None:
    source = repo / "build/mini_os.img"
    corrupt = repo / "build/corrupt-boot-id.img"
    shutil.copyfile(source, corrupt)
    with corrupt.open("r+b") as image:
        image.seek(BOOT_ID_OFFSET)
        image.write(b"\0" * BOOT_ID_SIZE)
    result = run(["build/check_image", str(corrupt)], repo, expect_success=False)
    if "boot volume ID is missing" not in result.stderr:
        raise RuntimeError("checker did not reject a missing boot volume ID")

    corrupt = repo / "build/corrupt-dirty.img"
    shutil.copyfile(source, corrupt)
    with corrupt.open("r+b") as image:
        image.seek(SUPERBLOCK_LBA * SECTOR_SIZE + SUPER_DIRTY_OFFSET)
        image.write(struct.pack("<I", 1))
    result = run(["build/check_image", str(corrupt)], repo, expect_success=False)
    if "filesystem has an unfinished mutation" not in result.stderr:
        raise RuntimeError("checker did not diagnose the dirty mutation marker")

    corrupt = repo / "build/corrupt-fat.img"
    shutil.copyfile(source, corrupt)
    with corrupt.open("r+b") as image:
        image.seek(FAT_LBA * SECTOR_SIZE + 2 * 2)
        image.write(struct.pack("<H", 2))
    expect_checker_failure(repo, corrupt)

    for value, label in ((4096 * SECTOR_SIZE + 1, "capacity"),
                         (0xFFFFFFFF, "uint32")):
        corrupt = repo / f"build/corrupt-size-{label}.img"
        shutil.copyfile(source, corrupt)
        inode_offset = INODE_START_LBA * SECTOR_SIZE + INODE_SIZE
        with corrupt.open("r+b") as image:
            image.seek(inode_offset + 32)
            start_block = struct.unpack("<I", image.read(4))[0]
            image.seek(FAT_LBA * SECTOR_SIZE + start_block * 2)
            image.write(struct.pack("<H", 0))
            image.seek(inode_offset + 28)
            image.write(struct.pack("<III", value, 0, 0))
        expect_checker_failure(repo, corrupt)

    corrupt = repo / "build/corrupt-reserved-name.img"
    shutil.copyfile(source, corrupt)
    inode_offset = INODE_START_LBA * SECTOR_SIZE + INODE_SIZE
    with corrupt.open("r+b") as image:
        image.seek(INODE_START_LBA * SECTOR_SIZE + 32)
        root_block = struct.unpack("<I", image.read(4))[0]
        invalid_name = b".\0" + b"\0" * (INODE_NAME_CAP - 2)
        image.seek(inode_offset + 1)
        image.write(invalid_name)
        image.seek((DATA_START_LBA + root_block) * SECTOR_SIZE + 5)
        image.write(invalid_name)
    expect_checker_failure(repo, corrupt)


def reject_reserved_injector_names(repo: Path) -> None:
    source = repo / "build/mini_os.img"
    for index, name in enumerate((".", "..", "bad/name")):
        image = repo / f"build/inject-invalid-{index}.img"
        shutil.copyfile(source, image)
        run(
            ["build/inject_transport", str(image), "transport", name],
            repo,
            expect_success=False,
        )
        run(["build/check_image", str(image)], repo)


def reject_unsafe_injector_targets(repo: Path) -> None:
    source = repo / "build/mini_os.img"
    alias = repo / "build/inject-hardlink.img"
    os.link(source, alias)
    result = run(
        ["build/inject_transport", str(alias), "transport", "hardlinkprobe"],
        repo,
        expect_success=False,
    )
    if "multiple hard links" not in result.stderr:
        raise RuntimeError("injector did not diagnose a hard-linked target")
    run(["build/check_image", str(source)], repo)
    run(["build/check_image", str(alias)], repo)
    alias.unlink()


def injector_transaction_faults(repo: Path) -> None:
    source = repo / "build/mini_os.img"
    pristine = source.read_bytes()
    host_source = repo / "build/fault-source"
    host_source.mkdir()
    (host_source / "payload.bin").write_bytes(b"fault injection payload\n")
    fault_tool = repo / "build/inject_transport_fault"
    run(
        [
            "cc",
            "-O2",
            "-std=c11",
            "-Wall",
            "-Wextra",
            "-Werror",
            "-DINJECT_FAULT_TEST",
            "-DCHECK_IMAGE_LIBRARY",
            "tools/inject_transport.c",
            "tools/check_image.c",
            "-o",
            str(fault_tool),
        ],
        repo,
    )

    probe = repo / "build/inject-fault-probe.img"
    shutil.copyfile(source, probe)
    result = run(
        [str(fault_tool), str(probe), str(host_source), "faultprobe"], repo
    )
    match = re.search(
        r"Fault-test sector writes: ([0-9]+)", result.stdout + result.stderr
    )
    if match is None or int(match.group(1)) == 0:
        raise RuntimeError("fault injector did not report its sector-write count")
    write_count = int(match.group(1))
    run(["build/check_image", str(probe)], repo)

    candidate = repo / "build/inject-fault-candidate.img"
    for variable in (
        "MINI_OS_INJECT_FAIL_BEFORE",
        "MINI_OS_INJECT_FAIL_AFTER",
    ):
        for sequence in range(1, write_count + 1):
            shutil.copyfile(source, candidate)
            environment = os.environ.copy()
            environment[variable] = str(sequence)
            run(
                [
                    str(fault_tool),
                    str(candidate),
                    str(host_source),
                    "faultprobe",
                ],
                repo,
                expect_success=False,
                env=environment,
            )
            if candidate.read_bytes() != pristine:
                raise RuntimeError(
                    f"injector changed the original after {variable}={sequence}"
                )
            run(["build/check_image", str(candidate)], repo)
            if list(candidate.parent.glob(candidate.name + ".inject-*")):
                raise RuntimeError("injector left a failed temporary image behind")

    for phase in ("chmod", "flush", "close", "check", "rename"):
        shutil.copyfile(source, candidate)
        environment = os.environ.copy()
        environment["MINI_OS_INJECT_FAIL_FINAL"] = phase
        run(
            [str(fault_tool), str(candidate), str(host_source), "faultprobe"],
            repo,
            expect_success=False,
            env=environment,
        )
        if candidate.read_bytes() != pristine:
            raise RuntimeError(
                f"injector changed the original after final-{phase} failure"
            )
        run(["build/check_image", str(candidate)], repo)
        if list(candidate.parent.glob(candidate.name + ".inject-*")):
            raise RuntimeError(
                f"injector left a final-{phase} temporary image behind"
            )

    dirty = repo / "build/inject-dirty.img"
    shutil.copyfile(source, dirty)
    with dirty.open("r+b") as image:
        image.seek(SUPERBLOCK_LBA * SECTOR_SIZE + SUPER_DIRTY_OFFSET)
        image.write(struct.pack("<I", 1))
    dirty_before = dirty.read_bytes()
    result = run(
        ["build/inject_transport", str(dirty), str(host_source), "faultprobe"],
        repo,
        expect_success=False,
    )
    if "unfinished mutation" not in result.stderr or dirty.read_bytes() != dirty_before:
        raise RuntimeError("injector did not safely reject a dirty filesystem")

    corrupt = repo / "build/inject-unrelated-corrupt.img"
    shutil.copyfile(source, corrupt)
    inode_offset = INODE_START_LBA * SECTOR_SIZE + INODE_SIZE
    with corrupt.open("r+b") as image:
        image.seek(inode_offset + 32)
        readme_block = struct.unpack("<I", image.read(4))[0]
        image.seek(FAT_LBA * SECTOR_SIZE + readme_block * 2)
        image.write(struct.pack("<H", readme_block))
    corrupt_before = corrupt.read_bytes()
    result = run(
        ["build/inject_transport", str(corrupt), str(host_source), "faultprobe"],
        repo,
        expect_success=False,
    )
    if (
        "failed the integrity check" not in result.stderr
        or corrupt.read_bytes() != corrupt_before
    ):
        raise RuntimeError(
            "injector committed an image that failed its pre-rename integrity gate"
        )
    if list(corrupt.parent.glob(corrupt.name + ".inject-*")):
        raise RuntimeError("injector left an integrity-rejected temporary image behind")


def compile_elf_probe(repo: Path, source: Path, output: Path) -> None:
    run(
        [
            "clang",
            "-target",
            "i386-unknown-none-elf",
            "-m32",
            "-march=i386",
            "-ffreestanding",
            "-nostdlib",
            "-O0",
            "-c",
            str(source),
            "-o",
            str(output),
        ],
        repo,
    )


def reject_invalid_elf_inputs(repo: Path) -> None:
    elf2bin = "build/elf2bin"
    output = repo / "build/rejected.bin"
    truncated = repo / "build/truncated.o"
    truncated.write_bytes(b"\x7fELF")
    run([elf2bin, str(output), "0x40000", str(truncated)], repo,
        expect_success=False)

    invalid_offset = repo / "build/invalid-section-offset.o"
    shutil.copyfile(repo / "build/crt0.o", invalid_offset)
    with invalid_offset.open("r+b") as stream:
        stream.seek(32)
        stream.write(struct.pack("<I", 0xFFFFFFF0))
    run([elf2bin, str(output), "0x40000", str(invalid_offset)], repo,
        expect_success=False)

    undefined_source = repo / "build/undefined.c"
    undefined_object = repo / "build/undefined.o"
    undefined_source.write_text(
        "extern void missing_symbol(void);\n"
        "void undefined_probe(void) { missing_symbol(); }\n",
        encoding="utf-8",
    )
    compile_elf_probe(repo, undefined_source, undefined_object)
    run([elf2bin, str(output), "0x40000", str(undefined_object)], repo,
        expect_success=False)

    duplicate_objects = []
    for index in range(2):
        duplicate_source = repo / f"build/duplicate-{index}.c"
        duplicate_object = repo / f"build/duplicate-{index}.o"
        duplicate_source.write_text(
            f"int duplicate_symbol = {index + 1};\n", encoding="utf-8"
        )
        compile_elf_probe(repo, duplicate_source, duplicate_object)
        duplicate_objects.append(str(duplicate_object))
    run([elf2bin, str(output), "0x40000", *duplicate_objects], repo,
        expect_success=False)

    overflow_source = repo / "build/output-overflow.c"
    overflow_object = repo / "build/output-overflow.o"
    overflow_source.write_text(
        "unsigned char oversized_output[524289] = { 1 };\n", encoding="utf-8"
    )
    compile_elf_probe(repo, overflow_source, overflow_object)
    run([elf2bin, str(output), "0x40000", str(overflow_object)], repo,
        expect_success=False)


def main() -> int:
    source = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="mini-os-build-test-") as directory:
        repo = Path(directory) / "repo"
        copy_repository(source, repo)

        run(["make", "clean"], repo)
        clean_build = run(["make"], repo)
        output = clean_build.stdout + clean_build.stderr
        if "-std=gnu11" not in output:
            raise RuntimeError("runtime library was not compiled as modern C")
        if "-std=c90" not in output or "-pedantic-errors" not in output:
            raise RuntimeError("applications were not compiled with strict C90 diagnostics")
        verify_kernel_entry_stub(repo)
        run(["build/check_image", "build/mini_os.img"], repo)
        reject_corrupt_images(repo)
        reject_reserved_injector_names(repo)
        reject_unsafe_injector_targets(repo)
        injector_transaction_faults(repo)
        reject_invalid_elf_inputs(repo)
        smoke(repo)

        probe = repo / "transport/apps/c99_probe.c"
        probe.write_text(
            "int main(void) { for (int i = 0; i < 1; i++) {} return 0; }\n",
            encoding="utf-8",
        )
        failed_probe = run(
            ["make", "app", "APP=c99_probe.c"], repo, expect_success=False
        )
        probe.unlink()
        if "for loop initial declarations" not in (
            failed_probe.stdout + failed_probe.stderr
        ) and "C99" not in (failed_probe.stdout + failed_probe.stderr):
            raise RuntimeError("strict-C90 negative probe failed for an unexpected reason")

        tracked = [
            repo / "build/kernel.bin",
            repo / "build/minilibc.o",
            repo / "transport/build/apps/hello.bin",
            repo / "build/mini_os.img",
        ]
        before = {path: timestamp(path) for path in tracked}
        run(["make"], repo)
        assert_unchanged(before, tracked, "no-op incremental build")

        header = repo / "transport/lib/string.h"
        with header.open("a", encoding="utf-8") as stream:
            stream.write("\n/* dependency regression marker */\n")
        make_source_newer(header)
        before = {path: timestamp(path) for path in tracked}
        run(["make"], repo)
        assert_changed(before, tracked[1:], "runtime-header dependency")
        assert_unchanged(before, tracked[:1], "runtime-header dependency")

        driver = repo / "OS_src/kernel/drivers.asm"
        with driver.open("a", encoding="utf-8") as stream:
            stream.write("\n; dependency regression marker\n")
        make_source_newer(driver)
        kernel_paths = [repo / "build/kernel.bin", repo / "build/boot.bin", repo / "build/mini_os.img"]
        app_path = repo / "transport/build/apps/hello.bin"
        before_kernel = {path: timestamp(path) for path in kernel_paths}
        before_app = timestamp(app_path)
        run(["make"], repo)
        assert_changed(before_kernel, kernel_paths, "kernel-include dependency")
        if timestamp(app_path) != before_app:
            raise RuntimeError("kernel-only change rebuilt an unrelated application")

        run(["make", "clean"], repo)
        fallback = run(["make", "LLD=__missing_ld_lld__"], repo)
        fallback_output = fallback.stdout + fallback.stderr
        if "linking 'transport/build" not in fallback_output or "with elf2bin" not in fallback_output:
            raise RuntimeError("fallback build did not use elf2bin")
        run(["build/check_image", "build/mini_os.img"], repo)
        smoke(repo)

    print("Build regression: PASS")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError) as error:
        print(f"Build regression: FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
