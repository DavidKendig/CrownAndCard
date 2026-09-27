# SPDX-License-Identifier: AGPL-3.0-or-later
"""
Independent Python reference for the game's RNG (GAME_DESIGN.md §7).

It re-implements ChaCha20 (RFC 8439), the ChaChaRng word stream, the unbiased
`below()` and the Fisher-Yates shuffle, plus xoshiro128**, so the Haxe tests
can be checked against values this script produced rather than values the
Haxe code produced itself.

Usage:  python tools/rng_reference.py
"""
import hashlib
import struct

MASK = 0xFFFFFFFF


def rotl(x, n):
    return ((x << n) | (x >> (32 - n))) & MASK


def chacha20_block(key_words, counter, nonce_words):
    s = [0x61707865, 0x3320646E, 0x79622D32, 0x6B206574] + list(key_words) + [counter] + list(nonce_words)
    x = s[:]

    def qr(a, b, c, d):
        x[a] = (x[a] + x[b]) & MASK; x[d] = rotl(x[d] ^ x[a], 16)
        x[c] = (x[c] + x[d]) & MASK; x[b] = rotl(x[b] ^ x[c], 12)
        x[a] = (x[a] + x[b]) & MASK; x[d] = rotl(x[d] ^ x[a], 8)
        x[c] = (x[c] + x[d]) & MASK; x[b] = rotl(x[b] ^ x[c], 7)

    for _ in range(10):
        qr(0, 4, 8, 12); qr(1, 5, 9, 13); qr(2, 6, 10, 14); qr(3, 7, 11, 15)
        qr(0, 5, 10, 15); qr(1, 6, 11, 12); qr(2, 7, 8, 13); qr(3, 4, 9, 14)
    return [(x[i] + s[i]) & MASK for i in range(16)]


class ChaChaRng:
    def __init__(self, key_words, nonce_words=(0, 0, 0)):
        self.key = list(key_words)
        self.nonce = list(nonce_words)
        self.counter = 0
        self.buf = []

    @classmethod
    def from_seed(cls, seed: bytes):
        return cls(struct.unpack("<8I", seed))

    def next_u32(self):
        if not self.buf:
            self.buf = chacha20_block(self.key, self.counter, self.nonce)
            self.counter = (self.counter + 1) & MASK
        return self.buf.pop(0)

    def fork(self, label: str):
        nonce = struct.unpack("<3I", hashlib.sha256(label.encode("utf-8")).digest()[:12])
        return ChaChaRng(chacha20_block(self.key, 0, nonce)[:8])

    def below(self, bound):
        mask = bound - 1
        for shift in (1, 2, 4, 8, 16):
            mask |= mask >> shift
        while True:
            x = self.next_u32() & mask
            if x < bound:
                return x

    def shuffle(self, items):
        i = len(items)
        while i > 1:
            j = self.below(i)
            i -= 1
            items[i], items[j] = items[j], items[i]


class Xoshiro128ss:
    def __init__(self, s0, s1, s2, s3):
        self.s = [s0 & MASK, s1 & MASK, s2 & MASK, s3 & MASK]

    def next_u32(self):
        s = self.s
        result = (rotl((s[1] * 5) & MASK, 7) * 9) & MASK
        t = (s[1] << 9) & MASK
        s[2] ^= s[0]; s[3] ^= s[1]; s[1] ^= s[2]; s[0] ^= s[3]; s[2] ^= t
        s[3] = rotl(s[3], 11)
        return result


def stream_digest(rng, count):
    data = b"".join(struct.pack("<I", rng.next_u32()) for _ in range(count))
    return hashlib.sha256(data).hexdigest()


RANKS = "23456789TJQKA"
SUITS = "cdhs"


def card_code(index):
    return RANKS[index >> 2] + SUITS[index & 3]


def self_check():
    """The reference must itself match RFC 8439 §2.3.2 before its output is trusted."""
    key = struct.unpack("<8I", bytes(range(32)))
    nonce = struct.unpack("<3I", bytes.fromhex("000000090000004a00000000"))
    got = chacha20_block(key, 1, nonce)
    want = [int(w, 16) for w in (
        "e4e7f110 15593bd1 1fdd0f50 c47120a3 c7f4d1c7 0368c033 9aaa2204 4e6cd4c3 "
        "466482d2 09aa9f07 05d7c214 a2028bd9 d19c12b5 b94e16de e883d0cb 4e3c50a2").split()]
    assert got == want, "reference ChaCha20 does not match RFC 8439"


if __name__ == "__main__":
    self_check()
    seed = bytes(range(32))

    r = ChaChaRng.from_seed(seed)
    print("ChaChaRng seed 00..1f, first 4 words:", " ".join("%08x" % r.next_u32() for _ in range(4)))
    print("ChaChaRng seed 00..1f, sha256 of first 10000 words (LE):",
          stream_digest(ChaChaRng.from_seed(seed), 10000))

    f = ChaChaRng.from_seed(seed).fork("table/card-room/blackjack/shuffle")
    print("fork('table/card-room/blackjack/shuffle') first 4 words:",
          " ".join("%08x" % f.next_u32() for _ in range(4)))

    deck = list(range(52))
    ChaChaRng.from_seed(seed).shuffle(deck)
    print("Shuffled deck (seed 00..1f):", " ".join(card_code(c) for c in deck))

    x = Xoshiro128ss(1, 2, 3, 4)
    print("xoshiro128** (1,2,3,4) first 8:", " ".join("%08x" % x.next_u32() for _ in range(8)))
    print("xoshiro128** (1,2,3,4) sha256 of first 10000 words (LE):",
          stream_digest(Xoshiro128ss(1, 2, 3, 4), 10000))
