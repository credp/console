#!/usr/bin/env python3
"""Convert SDRAM benchmark CSV traces to readmemh-friendly records."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


FIELDS = ["cycle", "client", "op", "address", "words", "byte_enable", "tag"]


def parse_int(value: str) -> int:
    return int(value, 0)


def pack_row(row: dict[str, str]) -> int:
    cycle = parse_int(row["cycle"])
    client = parse_int(row["client"])
    op = 1 if row["op"] == "W" else 0
    address = parse_int(row["address"])
    words = parse_int(row["words"])
    byte_enable = parse_int(row["byte_enable"])
    tag = parse_int(row["tag"])
    if not 0 <= cycle < (1 << 32):
        raise ValueError(f"cycle out of range: {cycle}")
    if not 0 <= client < (1 << 2):
        raise ValueError(f"client out of range: {client}")
    if not 0 <= address < (1 << 27):
        raise ValueError(f"address out of range: {address:#x}")
    if not 0 <= words < (1 << 16):
        raise ValueError(f"words out of range: {words}")
    if not 0 <= byte_enable < (1 << 2):
        raise ValueError(f"byte_enable out of range: {byte_enable:#x}")
    if not 0 <= tag < (1 << 16):
        raise ValueError(f"tag out of range: {tag}")
    return (
        (cycle << 64)
        | (client << 62)
        | (op << 61)
        | (address << 34)
        | (words << 18)
        | (byte_enable << 16)
        | tag
    )


def convert(trace_csv: Path, output_mem: Path) -> int:
    with trace_csv.open(newline="", encoding="utf-8") as src:
        reader = csv.DictReader(src)
        if reader.fieldnames != FIELDS:
            raise ValueError(f"{trace_csv}: expected {FIELDS}, got {reader.fieldnames}")
        rows = [pack_row(row) for row in reader]
    with output_mem.open("w", encoding="utf-8") as dst:
        dst.write("// cycle[95:64] client[63:62] write[61] address[60:34] words[33:18] byte_enable[17:16] tag[15:0]\n")
        for row in rows:
            dst.write(f"{row:024x}\n")
    return len(rows)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("trace_csv", type=Path)
    parser.add_argument("output_mem", type=Path)
    args = parser.parse_args()
    count = convert(args.trace_csv, args.output_mem)
    print(f"wrote {count} records to {args.output_mem}")


if __name__ == "__main__":
    main()
