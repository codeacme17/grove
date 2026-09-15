#!/usr/bin/env python3
"""Check that an idle Grove window is not stuck in a SwiftUI layout transaction.

After adding a multi-worktree project and allowing the list to appear, run:
    python3 scripts/check-ui-idle.py --pid <Grove PID>
Saved `sample` reports can also be checked with --sample <path>.
This is a macOS UI integration check, not a replacement for the core tests.
"""

import argparse
import pathlib
import re
import subprocess
import tempfile
import time


def check(report):
    main = re.search(r"^\s+(\d+) Thread_.*com\.apple\.main-thread", report, re.MULTILINE)
    if not main:
        raise ValueError("No main-thread sample found")
    next_thread = re.search(r"^\s+\d+ Thread_", report[main.end():], re.MULTILINE)
    end = main.end() + next_thread.start() if next_thread else len(report)
    transaction_counts = re.findall(
        r"^[^\n]*?\b(\d+) GraphHost\.flushTransactions\(\)",
        report[main.start():end], re.MULTILINE,
    )
    total = int(main.group(1))
    busy = sum(map(int, transaction_counts))
    share = busy / total
    print(f"SwiftUI layout transactions: {busy}/{total} main-thread samples ({share:.0%})")
    if share >= 0.8:
        print("FAIL: the idle main thread is continuously updating the view graph")
        return 1
    print("PASS: no sustained SwiftUI layout loop detected")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--pid", type=int)
    source.add_argument("--sample", type=pathlib.Path)
    args = parser.parse_args()
    if args.sample:
        return check(args.sample.read_text())
    # Let the preceding add/scroll/resize interaction settle before sampling.
    time.sleep(2)
    with tempfile.TemporaryDirectory(prefix="grove-ui-idle-") as directory:
        report = pathlib.Path(directory) / "sample.txt"
        subprocess.run(["/usr/bin/sample", str(args.pid), "3", "-file", str(report)],
                       check=True, capture_output=True, timeout=15)
        return check(report.read_text())


if __name__ == "__main__":
    raise SystemExit(main())
