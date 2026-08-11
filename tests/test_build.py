#!/usr/bin/env python3
"""Build-policy, dependency, and fallback-linker regression checks."""

from __future__ import annotations

from pathlib import Path
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import time


def run(command: list[str], cwd: Path, expect_success: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, cwd=cwd, text=True, capture_output=True)
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


def reject_corrupt_image(repo: Path) -> None:
    corrupt = repo / "build/corrupt.img"
    shutil.copyfile(repo / "build/mini_os.img", corrupt)
    with corrupt.open("r+b") as image:
        image.seek(103 * 512 + 2 * 2)
        image.write(struct.pack("<H", 2))
    run(["build/check_image", str(corrupt)], repo, expect_success=False)


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
        run(["build/check_image", "build/mini_os.img"], repo)
        reject_corrupt_image(repo)
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
