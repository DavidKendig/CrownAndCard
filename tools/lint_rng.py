# SPDX-License-Identifier: AGPL-3.0-or-later
"""
Fails if game code calls Std.random or Math.random (GAME_DESIGN.md §7.2).
All randomness must go through rng.IRng so it is seeded, saved and fair.

Usage:  python tools/lint_rng.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
BANNED = re.compile(r"\b(Std\.random|Math\.random)\s*\(")

problems = []
for path in sorted((ROOT / "src").rglob("*.hx")):
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if BANNED.search(line):
            problems.append(f"{path.relative_to(ROOT)}:{number}: {line.strip()}")

if problems:
    print("Banned random calls (use rng.IRng instead):")
    print("\n".join(problems))
    sys.exit(1)
print("lint_rng: OK")
