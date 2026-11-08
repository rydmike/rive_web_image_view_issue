#!/usr/bin/env python3
"""Writes rive_project/checker.png: a 256 px, 8 x 8 orange and teal checker with a white border.

Standard library only, so the image is reproducible from this script.
"""
from pathlib import Path
import struct
import zlib

SIZE = 256
CELL = SIZE // 8
BORDER = 8
ORANGE = (255, 122, 26, 255)
TEAL = (26, 176, 200, 255)
WHITE = (255, 255, 255, 255)


def pixel(x: int, y: int) -> tuple:
    if x < BORDER or y < BORDER or x >= SIZE - BORDER or y >= SIZE - BORDER:
        return WHITE
    return ORANGE if (x // CELL + y // CELL) % 2 == 0 else TEAL


def chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xFFFFFFFF)


rows = b''.join(b'\x00' + b''.join(bytes(pixel(x, y)) for x in range(SIZE)) for y in range(SIZE))
png = (b'\x89PNG\r\n\x1a\n'
       + chunk(b'IHDR', struct.pack('>IIBBBBB', SIZE, SIZE, 8, 6, 0, 0, 0))
       + chunk(b'IDAT', zlib.compress(rows, 9))
       + chunk(b'IEND', b''))
out = Path(__file__).resolve().parents[1] / 'rive_project' / 'checker.png'
out.write_bytes(png)
print(f'{out.name}: {len(png)} bytes')
