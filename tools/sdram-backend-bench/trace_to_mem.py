#!/usr/bin/env python3
"""Convert logical SDRAM request CSV traces to readmemh-friendly records."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


FIELDS = [
    "issue_time_ns",
    "client_id",
    "op",
    "address",
    "length_words",
    "byte_enable",
    "tag",
    "deadline_ns",
    "traffic_class",
]


def parse_int(value: str) -> int:
    return int(value, 0)


def pack_row(row: dict[str, str]) -> int:
    issue_time_ns = parse_int(row["issue_time_ns"])
    client = parse_int(row["client_id"])
    op = 1 if row["op"] == "W" else 0
    address = parse_int(row["address"])
    words = parse_int(row["length_words"])
    byte_enable = parse_int(row["byte_enable"])
    tag = parse_int(row["tag"])
    deadline_ns = parse_int(row["deadline_ns"])
    encoded_deadline = (1 << 64) - 1 if deadline_ns == -1 else deadline_ns
    if row["op"] not in ("R", "W"):
        raise ValueError(f"bad op: {row['op']}")
    if not 0 <= issue_time_ns < (1 << 64):
        raise ValueError(f"issue_time_ns out of range: {issue_time_ns}")
    if not 0 <= encoded_deadline < (1 << 64):
        raise ValueError(f"deadline_ns out of range: {deadline_ns}")
    if not 0 <= client < (1 << 4):
        raise ValueError(f"client out of range: {client}")
    if not 0 <= address < (1 << 32):
        raise ValueError(f"address out of range: {address:#x}")
    if not 0 <= words < (1 << 16):
        raise ValueError(f"words out of range: {words}")
    if not 0 <= byte_enable < (1 << 2):
        raise ValueError(f"byte_enable out of range: {byte_enable:#x}")
    if not 0 <= tag < (1 << 32):
        raise ValueError(f"tag out of range: {tag}")
    return (
        (issue_time_ns << 160)
        | (encoded_deadline << 96)
        | (client << 92)
        | (op << 91)
        | (address << 59)
        | (words << 43)
        | (byte_enable << 41)
        | (tag << 9)
    )


def convert(trace_csv: Path, output_mem: Path) -> int:
    with trace_csv.open(newline="", encoding="utf-8") as src:
        reader = csv.DictReader(src)
        if reader.fieldnames != FIELDS:
            raise ValueError(f"{trace_csv}: expected {FIELDS}, got {reader.fieldnames}")
        rows = [pack_row(row) for row in reader]
    with output_mem.open("w", encoding="utf-8") as dst:
        dst.write("// issue_time_ns[223:160] deadline_ns[159:96] client[95:92] write[91] address[90:59]\n")
        dst.write("// length_words[58:43] byte_enable[42:41] tag[40:9] reserved[8:0]\n")
        dst.write("// deadline_ns is all ones when the CSV deadline is -1\n")
        for row in rows:
            dst.write(f"{row:056x}\n")
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
