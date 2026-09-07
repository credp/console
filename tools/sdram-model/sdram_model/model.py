"""Cycle-level AS4C32M16SB command/state and shared-DQ model."""

from dataclasses import dataclass, field
from decimal import Decimal, ROUND_CEILING, ROUND_FLOOR
from functools import cache


CL3_MAX_MHZ = 1000 / 7


def ns_to_cycles_min(ns: float, frequency_mhz: float) -> int:
    """Ceil a minimum-time constraint so the result is never too short."""
    if ns < 0 or frequency_mhz <= 0:
        raise ValueError("non-negative time and positive clock required")
    value = Decimal(str(ns)) * Decimal(str(frequency_mhz)) / Decimal(1000)
    return int(value.to_integral_value(rounding=ROUND_CEILING))


def ns_to_cycles_max(ns: float, frequency_mhz: float) -> int:
    """Floor a maximum interval so the result is never too long."""
    if ns < 0 or frequency_mhz <= 0:
        raise ValueError("non-negative time and positive clock required")
    value = Decimal(str(ns)) * Decimal(str(frequency_mhz)) / Decimal(1000)
    return int(value.to_integral_value(rounding=ROUND_FLOOR))


ns_to_cycles = ns_to_cycles_min


@dataclass(frozen=True)
class Timing:
    frequency_mhz: float = 100.0
    cas: int = 3
    allow_overclock: bool = False
    # Alliance AS4C32M16SB Rev 1.4 table 16, -7 column.
    tRCD_ns: float = 21
    tRP_ns: float = 21
    tRAS_ns: float = 42
    tRC_ns: float = 63
    tRRD_ns: float = 14
    tWR_ns: float = 14
    tRFC_ns: float = 63
    tMRD_ns: float = 14
    tREFI_ns: float = 7800
    turnaround_cycles: int = 1  # explicit controller/board assumption

    def __post_init__(self):
        if self.frequency_mhz > CL3_MAX_MHZ and not self.allow_overclock:
            raise ValueError("-7 part requires tCK >= 7 ns; use --allow-overclock for exploratory runs")
        if self.cas not in (2, 3):
            raise ValueError("CAS must be 2 or 3")
        if self.cas == 2 and self.frequency_mhz > 100:
            raise ValueError("datasheet requires tCK >= 10 ns for CAS 2")

    @cache
    def cycles(self, name: str) -> int:
        return ns_to_cycles_min(getattr(self, name + "_ns"), self.frequency_mhz)

    @property
    def refresh_interval(self) -> int:
        return ns_to_cycles_max(self.tREFI_ns, self.frequency_mhz)

    @property
    def board_guaranteed(self) -> bool:
        # Provenance: official MiSTer MemTest README says boards should pass
        # at least 130 MHz. This is a project acceptance-test boundary, not an
        # Alliance component guarantee; see ../SOURCES.md.
        return self.frequency_mhz <= 130

    @property
    def device_rated(self) -> bool:
        return self.frequency_mhz <= CL3_MAX_MHZ


class CommandError(RuntimeError):
    pass


@dataclass
class Bank:
    row: int | None = None
    activated: int = -10**9
    precharged: int = -10**9
    last_write_data: int = -10**9
    last_read_data: int = -10**9
    act: int = 0
    pre: int = 0
    reads: int = 0
    writes: int = 0


@dataclass
class SDRAM:
    timing: Timing
    banks: list[list[Bank]] = field(default_factory=lambda: [[Bank() for _ in range(4)] for _ in range(2)])
    dq: dict[int, tuple[str, int, int, int]] = field(default_factory=dict)
    commands: dict[int, str] = field(default_factory=dict)
    command_requests: dict[int, int | None] = field(default_factory=dict)
    chip_busy_until: list[int] = field(default_factory=lambda: [0, 0])
    last_activate: list[int] = field(default_factory=lambda: [-10**9, -10**9])
    last_dq_direction: str | None = None
    last_dq_cycle: int = -10**9
    refreshes: list[int] = field(default_factory=lambda: [0, 0])
    row_hits: int = 0
    row_misses: int = 0
    dq_turnarounds: int = 0

    def _command(self, cycle: int, chip: int, text: str, request_id: int | None = None) -> None:
        if cycle < self.chip_busy_until[chip]:
            raise CommandError(f"cycle {cycle}: chip {chip} busy until {self.chip_busy_until[chip]}")
        if cycle in self.commands:
            raise CommandError(f"cycle {cycle}: command bus already occupied")
        self.commands[cycle] = text
        self.command_requests[cycle] = request_id

    def activate(self, cycle: int, chip: int, bank: int, row: int, request_id: int | None = None) -> None:
        b = self.banks[chip][bank]
        if not 0 <= row < 8192:
            raise CommandError("row does not fit physical A0-A12")
        if b.row is not None:
            raise CommandError("ACTIVE requires an idle bank")
        if cycle - b.precharged < self.timing.cycles("tRP"):
            raise CommandError("tRP violation")
        if cycle - b.activated < self.timing.cycles("tRC"):
            raise CommandError("tRC violation")
        if cycle - self.last_activate[chip] < self.timing.cycles("tRRD"):
            raise CommandError("tRRD violation")
        self._command(cycle, chip, f"ACT c{chip}b{bank} r{row}", request_id)
        b.row, b.activated = row, cycle
        b.act += 1
        self.row_misses += 1
        self.last_activate[chip] = cycle

    def precharge(self, cycle: int, chip: int, bank: int, request_id: int | None = None) -> None:
        b = self.banks[chip][bank]
        if b.row is None:
            raise CommandError("PRECHARGE requires an active bank")
        if cycle - b.activated < self.timing.cycles("tRAS"):
            raise CommandError("tRAS violation")
        if cycle - b.last_write_data < self.timing.cycles("tWR"):
            raise CommandError("tWR violation")
        if cycle <= b.last_read_data:
            raise CommandError("PRECHARGE would interrupt read burst")
        self._command(cycle, chip, f"PRE c{chip}b{bank}", request_id)
        b.row, b.precharged = None, cycle
        b.pre += 1

    def access(self, cycle: int, chip: int, bank: int, row: int, write: bool,
               words: int, request_id: int) -> tuple[int, int]:
        b = self.banks[chip][bank]
        if b.row != row:
            raise CommandError("READ/WRITE requires the requested open row")
        if cycle - b.activated < self.timing.cycles("tRCD"):
            raise CommandError("tRCD violation")
        direction = "W" if write else "R"
        start = cycle if write else cycle + self.timing.cas
        if self.last_dq_direction not in (None, direction):
            if start <= self.last_dq_cycle + self.timing.turnaround_cycles:
                raise CommandError("read/write DQ turnaround violation")
            self.dq_turnarounds += 1
        end = start + words
        for c in range(start, end):
            if c in self.dq:
                raise CommandError(f"cycle {c}: shared DQ collision")
        self._command(cycle, chip, f"{'WRITE' if write else 'READ'} c{chip}b{bank} x{words} q{request_id}", request_id)
        for c in range(start, end):
            self.dq[c] = (direction, request_id, chip, bank)
        self.last_dq_direction, self.last_dq_cycle = direction, end - 1
        self.row_hits += 1
        if write:
            b.writes += words
            b.last_write_data = end - 1
        else:
            b.reads += words
            b.last_read_data = end - 1
        return start, end

    def refresh(self, cycle: int, chip: int) -> None:
        if any(b.row is not None for b in self.banks[chip]):
            raise CommandError(f"REFRESH requires every bank on chip {chip} idle")
        self._command(cycle, chip, f"REFRESH c{chip}")
        self.chip_busy_until[chip] = cycle + self.timing.cycles("tRFC")
        self.refreshes[chip] += 1
