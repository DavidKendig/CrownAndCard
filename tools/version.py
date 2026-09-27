# SPDX-License-Identifier: AGPL-3.0-or-later
"""
The project version lives in version.json as 0.YY.BBB:
  0    major (pre-release)
  YY   two-digit year (2026 -> 26)
  BBB  build number, starting at 001

Usage:
  python tools/version.py          print the current version
  python tools/version.py bump     next build number; a new year resets it to 001
"""
import datetime
import json
import pathlib
import sys

FILE = pathlib.Path(__file__).resolve().parent.parent / "version.json"


def read():
    return json.loads(FILE.read_text(encoding="utf-8"))["version"]


def bump(current, today=None):
    year = (today or datetime.date.today()).year % 100
    major, cur_year, build = (int(p) for p in current.split("."))
    build = build + 1 if cur_year == year else 1
    if build > 999:
        raise SystemExit("Build number would pass 999 this year")
    return f"{major}.{year:02d}.{build:03d}"


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "bump":
        new = bump(read())
        FILE.write_text(json.dumps({"version": new}, indent=2) + "\n", encoding="utf-8")
        print(new)
    else:
        print(read())
