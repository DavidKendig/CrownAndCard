# SPDX-License-Identifier: AGPL-3.0-or-later
"""
Draws the launcher icon (a pixel-art crown on a playing card) and writes
launcher/assets/launcher.ico with 16, 24, 32, 48, 64 and 256 px images.
Standard library only.

Usage:  python tools/make_launcher_icon.py
"""
import pathlib
import struct
import zlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "launcher" / "assets" / "launcher.ico"

CLEAR = (0, 0, 0, 0)
CARD = (242, 234, 208, 255)
CARD_EDGE = (58, 42, 16, 255)
GOLD = (212, 175, 55, 255)
GOLD_LIGHT = (246, 214, 110, 255)
GOLD_DARK = (128, 96, 24, 255)
RUBY = (176, 32, 48, 255)
FELT = (31, 107, 58, 255)


def base_icon():
    """32 x 32 design."""
    px = [[CLEAR] * 32 for _ in range(32)]

    def rect(x0, y0, x1, y1, c):
        for y in range(y0, y1):
            for x in range(x0, x1):
                px[y][x] = c

    # Card with rounded corners and a dark edge.
    rect(6, 2, 26, 30, CARD_EDGE)
    rect(7, 3, 25, 29, CARD)
    for x, y in [(6, 2), (25, 2), (6, 29), (25, 29)]:
        px[y][x] = CLEAR
    # Felt-green pips in the corners.
    for x, y in [(9, 5), (22, 26)]:
        rect(x, y, x + 2, y + 2, FELT)
    # Crown: band, three spikes, jewels.
    rect(10, 19, 22, 23, GOLD)
    rect(10, 19, 22, 20, GOLD_LIGHT)
    rect(10, 22, 22, 23, GOLD_DARK)
    for cx, top in [(11, 12), (16, 9), (21, 12)]:
        for y in range(top, 19):
            half = (y - top) // 3
            for x in range(cx - half, cx + half + 1):
                if 10 <= x < 22:
                    px[y][x] = GOLD
    for x in range(10, 22):
        px[18][x] = GOLD
    for cx, top in [(11, 12), (16, 9), (21, 12)]:
        px[top - 1][cx] = RUBY
        px[top][cx] = GOLD_LIGHT
    px[20][13] = RUBY
    px[20][16] = RUBY
    px[20][19] = RUBY
    return px


def scale(px, size):
    src = len(px)
    return [[px[y * src // size][x * src // size] for x in range(size)] for y in range(size)]


def png(px):
    size = len(px)
    raw = b"".join(b"\x00" + b"".join(struct.pack("4B", *c) for c in row) for row in px)

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b""))


def ico(images):
    header = struct.pack("<HHH", 0, 1, len(images))
    offset = 6 + 16 * len(images)
    entries, blobs = b"", b""
    for size, data in images:
        entries += struct.pack("<BBBBHHII", size % 256, size % 256, 0, 0, 1, 32, len(data), offset)
        offset += len(data)
        blobs += data
    return header + entries + blobs


if __name__ == "__main__":
    design = base_icon()
    images = [(s, png(scale(design, s))) for s in (16, 24, 32, 48, 64, 256)]
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(ico(images))
    print(f"Wrote {OUT.relative_to(ROOT)} ({OUT.stat().st_size} bytes)")
