"""Logical byte-address to physical module signal mappings.

The real AS4C32M16SB geometry is 13 row bits, 2 bank bits and 10 word-column
bits. Experimental 1 KiB mappings remain bijective: one higher address bit
becomes physical column A9, so no fourteenth row pin is invented.
"""

from dataclasses import dataclass


@dataclass(frozen=True)
class Address:
    chip: int
    bank: int
    row: int
    column: int
    byte: int
    logical_chunk: int


MAPPINGS = (
    "row-chip-bank-column",
    "row-bank-chip-column",
    "linear",
    "chip-row-bank-column",
    "stripe-1k-chip-bank",
    "stripe-1k-bank-chip",
)


def decode_address(byte_address: int, mapping: str) -> Address:
    if byte_address < 0 or byte_address >= 128 * 1024 * 1024:
        raise ValueError("address outside modeled 128 MiB")
    if mapping not in MAPPINGS:
        raise ValueError(f"unknown mapping {mapping!r}; choose from {MAPPINGS}")
    byte = byte_address & 1
    word = byte_address >> 1
    if mapping == "linear":
        column = word & 0x3FF
        row = (word >> 10) & 0x1FFF
        bank = (word >> 23) & 3
        chip = (word >> 25) & 1
        chunk = word >> 10
    elif mapping == "chip-row-bank-column":
        column = word & 0x3FF
        upper = word >> 10
        bank = upper & 3
        row = (upper >> 2) & 0x1FFF
        chip = (upper >> 15) & 1
        chunk = upper
    elif mapping in ("row-chip-bank-column", "row-bank-chip-column"):
        column = word & 0x3FF
        upper = word >> 10
        if mapping == "row-chip-bank-column":
            bank, chip = upper & 3, (upper >> 2) & 1
        else:
            chip, bank = upper & 1, (upper >> 1) & 3
        row, chunk = upper >> 3, upper
    else:
        column_lo = word & 0x1FF
        upper = word >> 9
        if mapping == "stripe-1k-chip-bank":
            bank, chip = upper & 3, (upper >> 2) & 1
        else:
            chip, bank = upper & 1, (upper >> 1) & 3
        remainder = upper >> 3
        column = column_lo | ((remainder & 1) << 9)
        row, chunk = remainder >> 1, upper
    return Address(chip, bank, row, column, byte, chunk)
