#!/usr/bin/env python3
"""Deterministic QEMU regression for the MINI-OS shell and filesystem."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import select
import shutil
import subprocess
import sys
import tempfile
import time


BOOT_TIMEOUT = 10.0
COMMAND_TIMEOUT = 12.0


def run_checked(command: list[str], cwd: Path) -> None:
    subprocess.run(command, cwd=cwd, check=True)


def prepare_debug_image(repo: Path, source: Path, destination: Path) -> None:
    kernel = destination.with_suffix(".kernel.bin")
    boot = destination.with_suffix(".boot.bin")
    run_checked(
        [
            "nasm",
            "-w-label-redef-late",
            "-d",
            "ENABLE_DEBUGCON=1",
            "-f",
            "bin",
            "OS_src/kernel/main.asm",
            "-o",
            str(kernel),
        ],
        repo,
    )
    kernel_bytes = kernel.read_bytes()
    sectors = (len(kernel_bytes) + 511) // 512
    if sectors > 100:
        raise RuntimeError("debug kernel exceeds the 100-sector boot reservation")
    run_checked(
        [
            "nasm",
            "-w-label-redef-late",
            "-d",
            f"KERNEL_SECTORS={sectors}",
            "-f",
            "bin",
            "OS_src/boot/boot.asm",
            "-o",
            str(boot),
        ],
        repo,
    )
    boot_bytes = boot.read_bytes()
    if len(boot_bytes) != 512 or boot_bytes[510:] != b"\x55\xaa":
        raise RuntimeError("debug boot sector has an invalid size or signature")

    shutil.copy2(source, destination)
    with destination.open("r+b") as image:
        image.seek(0)
        image.write(boot_bytes)
        image.seek(512)
        image.write(b"\0" * (100 * 512))
        image.seek(512)
        image.write(kernel_bytes)


class VirtualMachine:
    def __init__(self, image: Path, log: Path, qemu: str, instance: int) -> None:
        self.image = image
        self.log = log
        self.qemu = qemu
        self.instance = instance
        self.process: subprocess.Popen[bytes] | None = None

    def start(self) -> None:
        self.log.write_bytes(b"")
        command = [
            self.qemu,
            "-drive",
            f"file={self.image},format=raw,if=ide,index=0,media=disk",
            "-display",
            "none",
            "-monitor",
            "stdio",
            "-debugcon",
            f"file:{self.log}",
            "-global",
            "isa-debugcon.iobase=0xe9",
            "-no-reboot",
            "-no-shutdown",
        ]
        self.process = subprocess.Popen(
            command,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        if self.process.poll() is not None:
            error = self.process.stderr.read().decode("utf-8", "replace")
            raise RuntimeError(f"QEMU exited during startup: {error}")
        self._read_prompt()
        self.wait_for("MINI_OS: shell ready", 0, BOOT_TIMEOUT)

    def _read_prompt(self) -> str:
        if self.process is None or self.process.stdout is None:
            raise RuntimeError("QEMU monitor is not connected")
        response = bytearray()
        deadline = time.monotonic() + 3.0
        while b"(qemu)" not in response:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise RuntimeError("timed out reading the QEMU monitor prompt")
            ready, _, _ = select.select([self.process.stdout], [], [], remaining)
            if not ready:
                raise RuntimeError("timed out reading the QEMU monitor prompt")
            chunk = os.read(self.process.stdout.fileno(), 4096)
            if not chunk:
                raise RuntimeError("QEMU monitor closed unexpectedly")
            response.extend(chunk)
        return response.decode("utf-8", "replace")

    def hmp(self, command: str) -> str:
        if self.process is None or self.process.stdin is None:
            raise RuntimeError("QEMU monitor is not connected")
        self.process.stdin.write(command.encode("ascii") + b"\n")
        self.process.stdin.flush()
        return self._read_prompt()

    @staticmethod
    def key_name(character: str) -> str:
        if character.isascii() and (character.islower() or character.isdigit()):
            return character
        mapping = {
            " ": "spc",
            "/": "slash",
            ".": "dot",
            "_": "shift-minus",
            "-": "minus",
        }
        if character not in mapping:
            raise ValueError(f"no QEMU key mapping for {character!r}")
        return mapping[character]

    def send_command(self, command: str) -> int:
        start = self.log.stat().st_size
        for character in command:
            self.hmp(f"sendkey {self.key_name(character)} 2")
        self.hmp("sendkey ret 2")
        return start

    def text(self) -> str:
        return self.log.read_bytes().decode("latin1", "replace")

    def wait_for(self, expected: str, start: int, timeout: float) -> str:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            data = self.text()
            segment = data[start:]
            if expected in segment:
                return segment
            if self.process is not None and self.process.poll() is not None:
                error = self.process.stderr.read().decode("utf-8", "replace")
                raise RuntimeError(f"QEMU exited while waiting for {expected!r}: {error}")
            time.sleep(0.03)
        raise RuntimeError(
            f"timed out waiting for {expected!r}; debug console follows:\n{self.text()}"
        )

    def command_expect(self, command: str, expected: str) -> str:
        start = self.send_command(command)
        return self.wait_for(expected, start, COMMAND_TIMEOUT)

    def stop(self) -> None:
        if self.process is None:
            return
        if self.process.poll() is None:
            try:
                self.hmp("quit")
            except (OSError, RuntimeError):
                self.process.terminate()
        try:
            self.process.wait(timeout=5.0)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait(timeout=5.0)


def check_image(checker: Path, image: Path, repo: Path) -> None:
    run_checked([str(checker), str(image)], repo)


def smoke_test(vm: VirtualMachine) -> None:
    vm.command_expect(
        "run /transport/build/lib_test/test_bss.bin", "BSS test: PASS"
    )
    vm.command_expect("pwd", "/ > ")


def full_test(repo: Path, checker: Path, image: Path, qemu: str, temp: Path) -> None:
    first = VirtualMachine(image, temp / "session-1.log", qemu, 1)
    try:
        first.start()
        first.command_expect(
            "run /transport/build/lib_test/test_string.bin",
            "STRING/FORMAT TESTS PASSED",
        )
        first.command_expect(
            "run /transport/build/lib_test/test_heap.bin", "HEAP/STDLIB TESTS PASSED"
        )
        first.command_expect(
            "run /transport/build/lib_test/test_bss.bin", "BSS test: PASS"
        )
        first.command_expect(
            "run /transport/build/lib_test/test_file.bin",
            "SYSCALL/STREAM TESTS PASSED",
        )
        segment = first.command_expect("cat syslib.txt", "E2E-APPEND")
        if "E2E-BEGIN" not in segment or "E2E-END" not in segment:
            raise RuntimeError("cross-sector file markers were not all read back")
        first.command_expect("mkdir e2e", "Directory created: e2e")
        first.command_expect("mv syslib.txt e2e/moved.txt", "Renamed.")
        first.command_expect("cd e2e", "/e2e > ")
        first.command_expect("ls", "moved.txt (f)")
    finally:
        first.stop()

    check_image(checker, image, repo)

    second = VirtualMachine(image, temp / "session-2.log", qemu, 2)
    try:
        second.start()
        segment = second.command_expect("cat /e2e/moved.txt", "E2E-APPEND")
        if "E2E-BEGIN" not in segment or "E2E-END" not in segment:
            raise RuntimeError("file contents did not survive a QEMU restart")
        second.command_expect("mv /e2e/moved.txt /persist.txt", "Renamed.")
        second.command_expect("rm /persist.txt", "Removed.")
        second.command_expect("rm /e2e", "Removed.")
        start = second.send_command("ls")
        segment = second.wait_for("/ > ", start, COMMAND_TIMEOUT)
        if "e2e (d)" in segment or "persist.txt (f)" in segment:
            raise RuntimeError("removed entries remain visible after cleanup")
    finally:
        second.stop()

    check_image(checker, image, repo)

    third = VirtualMachine(image, temp / "session-3.log", qemu, 3)
    try:
        third.start()
        start = third.send_command("ls")
        segment = third.wait_for("/ > ", start, COMMAND_TIMEOUT)
        if "e2e (d)" in segment or "persist.txt (f)" in segment:
            raise RuntimeError("removal did not survive a QEMU restart")
    finally:
        third.stop()

    check_image(checker, image, repo)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--image", required=True, type=Path)
    parser.add_argument("--checker", required=True, type=Path)
    parser.add_argument("--qemu", default="qemu-system-i386")
    parser.add_argument("--smoke", action="store_true")
    args = parser.parse_args()

    repo = Path(__file__).resolve().parents[1]
    source_image = args.image.resolve()
    checker = args.checker.resolve()
    if not source_image.is_file() or not checker.is_file():
        parser.error("--image and --checker must name existing files")

    with tempfile.TemporaryDirectory(prefix="mini-os-e2e-") as directory:
        temp = Path(directory)
        debug_image = temp / "mini_os_debug.img"
        prepare_debug_image(repo, source_image, debug_image)
        if args.smoke:
            vm = VirtualMachine(debug_image, temp / "smoke.log", args.qemu, 0)
            try:
                vm.start()
                smoke_test(vm)
            finally:
                vm.stop()
            check_image(checker, debug_image, repo)
        else:
            full_test(repo, checker, debug_image, args.qemu, temp)

    print("QEMU filesystem regression: PASS")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"QEMU filesystem regression: FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
