"""Independent arbitration/page policies, simulation driver, and metrics."""

from collections import defaultdict
from dataclasses import dataclass
from .mapping import decode_address
from .model import CommandError, SDRAM, Timing


SCHEDULERS = ("fifo", "row-hit", "edf", "edf-row-hit", "fixed-priority",
              "round-robin", "watermark")
PAGE_POLICIES = ("open", "close")
CHANNEL_PRIORITY = {"audio": 0, "scanout": 1, "audio-write": 2,
                    "frame-write": 3, "background": 4}


@dataclass
class Result:
    cycles: int
    requests: list
    memory: SDRAM
    pending: int


def _is_hit(req, memory, addresses):
    a = addresses[req.id]
    return memory.banks[a.chip][a.bank].row == a.row


def _order(ready, memory, addresses, scheduler, cycle, deadline_guard, rr_channel,
           watermark_urgent=frozenset()):
    indexed = list(enumerate(ready))
    def compact(items):
        selected, seen = [], set()
        for item in items:
            r = item[1]; a = addresses[r.id]
            hit = memory.banks[a.chip][a.bank].row == a.row
            key = (hit, a.chip, a.bank, r.write if hit else None)
            if key not in seen:
                seen.add(key); selected.append(item)
        return selected
    if scheduler == "fifo":
        return indexed[:1]
    if scheduler == "row-hit":
        return compact([x for x in indexed if _is_hit(x[1], memory, addresses)] +
                       [x for x in indexed if not _is_hit(x[1], memory, addresses)])
    if scheduler == "edf":
        return compact(sorted(indexed, key=lambda x: (x[1].deadline is None, x[1].deadline or 10**18, x[1].id)))
    if scheduler == "fixed-priority":
        return compact(sorted(indexed, key=lambda x: CHANNEL_PRIORITY.get(x[1].requester, 10)))
    if scheduler == "round-robin":
        channels = sorted({r.requester for r in ready})
        if channels:
            start = (channels.index(rr_channel) + 1) % len(channels) if rr_channel in channels else 0
            rank = {ch: (i-start) % len(channels) for i, ch in enumerate(channels)}
            return compact(sorted(indexed, key=lambda x: (rank[x[1].requester], x[1].arrival, x[1].id)))
    if scheduler == "watermark":
        # Non-urgent presentation work deliberately waits so that transfers
        # form useful FIFO-sized runs. Audio is tiny and always pre-emptible.
        eligible = [x for x in indexed
                    if x[1].requester in ("audio", "audio-write", "background")
                    or x[1].requester in watermark_urgent
                    or x[1].fifo_kind is None]
        def rank(item):
            channel = item[1].requester
            if channel in ("audio", "audio-write"): return 0
            if channel in watermark_urgent: return 1
            if channel == "background": return 2
            return 3
        return compact(sorted(eligible, key=lambda x: (
            rank(x), not _is_hit(x[1], memory, addresses),
            x[1].arrival, x[1].id)))
    # EDF inside the guard window; otherwise exploit row hits, preserving FIFO
    # order without sorting the usually much larger non-urgent backlog.
    urgent = [x for x in indexed if x[1].deadline is not None and x[1].deadline <= cycle+deadline_guard]
    urgent.sort(key=lambda x: (x[1].deadline, x[1].id))
    remaining = [x for x in indexed if x not in urgent]
    return compact(urgent + [x for x in remaining if _is_hit(x[1], memory, addresses)] +
                   [x for x in remaining if not _is_hit(x[1], memory, addresses)])


def run(requests, timing: Timing, mapping: str, scheduler: str = "row-hit",
        page_policy: str = "open", *, horizon: int | None = None,
        deadline_guard: int = 64, refresh_stagger: int = 0,
        grant_words: dict[str, int] | None = None,
        scheduler_lookahead: int = 64,
        watermark_low_words: int = 512,
        watermark_high_words: int = 1536) -> Result:
    if scheduler not in SCHEDULERS:
        raise ValueError(f"unknown scheduler {scheduler}")
    if page_policy not in PAGE_POLICIES:
        raise ValueError(f"unknown page policy {page_policy}")
    memory = SDRAM(timing)
    future = sorted(requests, key=lambda r: (r.arrival, r.id))
    addresses = {r.id: decode_address(r.address, mapping) for r in requests}
    if scheduler_lookahead <= 0:
        raise ValueError("scheduler lookahead must be positive")
    if not 0 <= watermark_low_words < watermark_high_words:
        raise ValueError("watermarks must satisfy 0 <= low < high")
    cursor, ready, ready_count, cycle = 0, defaultdict(list), 0, 0
    next_refresh = [timing.refresh_interval, timing.refresh_interval + max(0, refresh_stagger)]
    close_wanted: set[tuple[int, int]] = set()
    rr_channel = ""
    grant_words = grant_words or {}
    active_grant, grant_left = None, 0
    watermark_urgent: set[str] = set()

    while ((horizon is not None and cycle < horizon) or
           (horizon is None and (cursor < len(future) or ready_count))):
        if cycle > 100_000_000:
            raise RuntimeError("simulation failed to converge")
        while cursor < len(future) and future[cursor].arrival <= cycle:
            request = future[cursor]
            ready[request.requester].append(request)
            ready_count += 1
            cursor += 1
        if active_grant and not ready.get(active_grant):
            active_grant, grant_left = None, 0

        issued = False
        candidates = []
        # A refresh deadline is mandatory for that chip, but if tRAS/tWR keeps
        # it from making progress the other chip may still receive a command.
        due = [c for c in range(2) if cycle >= next_refresh[c]]
        for chip in due:
            active = [b for b in range(4) if memory.banks[chip][b].row is not None]
            if active:
                for bank in active:
                    try:
                        memory.precharge(cycle, chip, bank); issued = True; break
                    except CommandError:
                        pass
            else:
                try:
                    memory.refresh(cycle, chip)
                    next_refresh[chip] += timing.refresh_interval
                    issued = True
                except CommandError:
                    pass
            if issued:
                break

        if not issued and close_wanted:
            for chip, bank in sorted(close_wanted):
                try:
                    memory.precharge(cycle, chip, bank)
                    close_wanted.remove((chip, bank)); issued = True; break
                except CommandError:
                    pass

        if not issued and ready_count:
            # A real controller has bounded request storage and cannot search
            # an entire frame-sized backlog associatively every clock. Keep
            # arrival order per channel and expose a bounded window from each.
            candidates = []
            for channel, queue in ready.items():
                limit = (scheduler_lookahead
                         if scheduler != "watermark" or channel == "background"
                         else 1)
                candidates.extend(queue[:limit])
            if scheduler == "watermark":
                for channel in ("scanout", "frame-write"):
                    queue = ready.get(channel, [])
                    if not queue:
                        watermark_urgent.discard(channel)
                        continue
                    request = queue[0]
                    if not request.fifo_kind or request.deadline is None:
                        continue
                    capacity = request.fifo_capacity
                    if watermark_high_words > capacity:
                        raise ValueError("high watermark exceeds FIFO capacity")
                    until_deadline = max(0, request.deadline-cycle)
                    if request.fifo_kind == "read":
                        level = max(0, min(capacity,
                            until_deadline*request.flow_words_per_cycle-request.original_words))
                        if channel in watermark_urgent:
                            if level >= watermark_high_words: watermark_urgent.discard(channel)
                        elif level <= watermark_low_words:
                            watermark_urgent.add(channel)
                    else:
                        free = max(0, min(capacity,
                            until_deadline*request.flow_words_per_cycle))
                        level = capacity-free
                        if channel in watermark_urgent:
                            if level <= watermark_low_words: watermark_urgent.discard(channel)
                        elif level >= watermark_high_words:
                            watermark_urgent.add(channel)
                    # End-of-frame flushing remains an explicit event in real
                    # hardware even if the tail never crosses the high mark.
                    if (request.fifo_kind == "write" and request.frame_deadline is not None
                            and request.frame_deadline <= cycle+deadline_guard):
                        watermark_urgent.add(channel)
            protected_banks = set()
            if scheduler != "watermark":
                for other in candidates:
                    other_addr = addresses[other.id]
                    if memory.banks[other_addr.chip][other_addr.bank].row == other_addr.row:
                        protected_banks.add((other_addr.chip, other_addr.bank))
            ordered = _order(candidates, memory, addresses, scheduler, cycle,
                             deadline_guard, rr_channel, watermark_urgent)
            if active_grant and grant_left > 0 and scheduler != "watermark":
                ordered = ([x for x in ordered if x[1].requester == active_grant] +
                           [x for x in ordered if x[1].requester != active_grant])
            for _, req in ordered:
                a = addresses[req.id]
                if a.chip in due:
                    continue
                b = memory.banks[a.chip][a.bank]
                words = min(req.words, req.max_burst, 1024 - a.column)
                try:
                    if b.row is None:
                        memory.activate(cycle, a.chip, a.bank, a.row, req.id)
                    elif b.row != a.row:
                        # Do not destroy useful locality merely because the
                        # preferred hit is temporarily blocked by DQ timing.
                        if (a.chip, a.bank) in protected_banks:
                            continue
                        memory.precharge(cycle, a.chip, a.bank, req.id)
                    else:
                        direction = "W" if req.write else "R"
                        dq_start = cycle if req.write else cycle + timing.cas
                        if (memory.last_dq_direction not in (None, direction)
                                and dq_start <= memory.last_dq_cycle + timing.turnaround_cycles):
                            continue
                        if any(c in memory.dq for c in range(dq_start, dq_start+words)):
                            continue
                        _, end = memory.access(cycle, a.chip, a.bank, a.row, req.write, words, req.id)
                        if active_grant is None or grant_left <= 0:
                            active_grant = req.requester
                            grant_left = max(words, grant_words.get(req.requester, words))
                        if req.requester == active_grant:
                            grant_left -= words
                            if grant_left <= 0:
                                active_grant = None
                        if req.started is None:
                            req.started = cycle
                        if words == req.words:
                            req.completed = end
                            ready[req.requester].remove(req)
                            ready_count -= 1
                            rr_channel = req.requester
                        else:
                            req.address += words * 2
                            req.words -= words
                            addresses[req.id] = decode_address(req.address, mapping)
                        if page_policy == "close":
                            close_wanted.add((a.chip, a.bank))
                    issued = True
                    break
                except CommandError:
                    continue
        advance = 1
        if (not issued and candidates and not close_wanted and not due and
                all(memory.banks[addresses[r.id].chip][addresses[r.id].bank].row
                    == addresses[r.id].row for r in candidates)):
            # Once every visible request already has its row open, intervening
            # clocks cannot change arbitration. Jump across occupied DQ clocks
            # to the earliest cycle at which one visible access could start.
            earliest = []
            for request in candidates:
                address = addresses[request.id]
                bank = memory.banks[address.chip][address.bank]
                command_cycle = bank.activated + timing.cycles("tRCD")
                direction = "W" if request.write else "R"
                data_ready = memory.last_dq_cycle + 1
                if memory.last_dq_direction not in (None, direction):
                    data_ready += timing.turnaround_cycles
                command_cycle = max(command_cycle,
                                    data_ready - (0 if request.write else timing.cas))
                earliest.append(command_cycle)
            target = max(cycle + 1, min(earliest))
            target = min(target, min(next_refresh))
            advance = max(1, target-cycle)
        cycle += advance

    if horizon is None:
        cycle = max([cycle, *(memory.dq.keys() or [0])]) + 1
    pending = sum(r.completed is None or r.completed > cycle for r in requests)
    return Result(cycle, requests, memory, pending)


def metrics(result: Result, timing: Timing) -> dict:
    cycles = result.cycles
    request_by_id = {r.id: r for r in result.requests}
    dq_by_channel = defaultdict(list)
    for cycle, (_, request_id, _, _) in result.memory.dq.items():
        if cycle < cycles:
            dq_by_channel[request_by_id[request_id].requester].append(cycle)
    channels = {}
    for name in sorted({r.requester for r in result.requests}):
        reqs = [r for r in result.requests if r.requester == name]
        done = [r for r in reqs if r.completed is not None and r.completed <= cycles]
        latencies = [r.completed-r.arrival for r in done]
        waits = [r.started-r.arrival for r in done if r.started is not None]
        deadline_slacks = [r.deadline-r.completed for r in done if r.deadline is not None]
        late = [r for r in reqs if r.deadline is not None and r.deadline <= cycles
                and (r.completed is None or r.completed > r.deadline)]
        service = sorted(dq_by_channel[name])
        offered_words = sum(r.original_words for r in reqs)
        chip_words = [0, 0]
        bank_words = [[0]*4 for _ in range(2)]
        for c in service:
            _, _, chip, bank = result.memory.dq[c]
            chip_words[chip] += 1; bank_words[chip][bank] += 1
        gaps = ([service[0], cycles-1-service[-1]] + [b-a-1 for a,b in zip(service, service[1:])]
                if service else [cycles])
        runs, previous = [], None
        for c in service:
            if previous is not None and c == previous + 1:
                runs[-1] += 1
            else:
                runs.append(1)
            previous = c
        command_count = sum(request_by_id[rid].requester == name
                            for c,rid in result.memory.command_requests.items()
                            if c < cycles and rid is not None)
        channels[name] = {
            "requests": len(reqs), "completed": len(done), "words": len(service),
            "offered_words": offered_words,
            "offered_mb_s": offered_words*2*timing.frequency_mhz/cycles,
            "service_pct": 100*len(service)/offered_words if offered_words else 100,
            "backlog_words": offered_words-len(service),
            "mb_s": len(service)*2*timing.frequency_mhz/cycles,
            "dq_share_pct": 100*len(service)/cycles,
            "command_cycles": command_count,
            "avg_latency": sum(latencies)/len(latencies) if latencies else 0,
            "max_latency": max(latencies, default=0),
            "avg_wait": sum(waits)/len(waits) if waits else 0,
            "max_wait": max(waits, default=0),
            "avg_wait_us": (sum(waits)/len(waits)/timing.frequency_mhz) if waits else 0,
            "max_wait_us": max(waits, default=0)/timing.frequency_mhz,
            "avg_latency_us": (sum(latencies)/len(latencies)/timing.frequency_mhz) if latencies else 0,
            "max_latency_us": max(latencies, default=0)/timing.frequency_mhz,
            "deadline_misses": len(late),
            "min_deadline_slack": min(deadline_slacks, default=None),
            "min_deadline_slack_us": (min(deadline_slacks)/timing.frequency_mhz
                                       if deadline_slacks else None),
            "max_lateness": max(((r.completed or cycles)-r.deadline for r in late), default=0),
            "first_service": service[0] if service else None,
            "last_service": service[-1] if service else None,
            "max_service_gap": max(gaps, default=0),
            "max_service_run": max(runs, default=0),
            "chip_words": chip_words, "bank_words": bank_words,
        }
    used = sum(len(v) for v in dq_by_channel.values())
    banks = result.memory.banks
    incomplete_frames = len({r.frame for r in result.requests
                             if r.frame is not None and r.deadline is not None and r.deadline <= cycles
                             and (r.completed is None or r.completed > r.deadline)})
    offered = sum(r.original_words for r in result.requests)
    capture_frames = sorted({r.frame for r in result.requests
                             if r.requester == "frame-write" and r.frame is not None
                             and r.deadline is not None and r.deadline <= cycles})
    published_frames = 0
    for frame in capture_frames:
        frame_requests = [r for r in result.requests
                          if r.requester == "frame-write" and r.frame == frame]
        if frame_requests and all(r.completed is not None and r.completed <= r.deadline
                                  for r in frame_requests):
            published_frames += 1
    replay_requests = [r for r in result.requests if r.requester == "scanout"
                       and r.deadline is not None and r.deadline <= cycles]
    replay_frames = sorted({r.frame for r in replay_requests if r.frame is not None})
    replay_underruns = sum(r.completed is None or r.completed > r.deadline
                          for r in replay_requests)
    presentation = {
        "capture_frames": len(capture_frames),
        "published_frames": published_frames,
        "failed_captures": len(capture_frames) - published_frames,
        "replay_frames": len(replay_frames),
        "replay_safe_frames": sum(
            all(r.completed is not None and r.completed <= r.deadline
                for r in replay_requests if r.frame == frame)
            for frame in replay_frames),
        "replay_underruns": replay_underruns,
        "audio_deadline_misses": sum(
            channel["deadline_misses"] for name, channel in channels.items()
            if name in ("audio", "audio-write")),
    }
    return {
        "board_guaranteed": timing.board_guaranteed,
        "device_rated": timing.device_rated,
        "exploratory_overclock": not timing.device_rated,
        "cycles": cycles, "simulated_us": cycles/timing.frequency_mhz,
        "useful_words": used, "useful_bytes": used*2,
        "effective_mb_s": used*2*timing.frequency_mhz/cycles,
        "offered_mb_s": offered*2*timing.frequency_mhz/cycles,
        "unserved_words": offered-used,
        "theoretical_mb_s": timing.frequency_mhz*2,
        "dq_util_pct": 100*used/cycles,
        "leftover_dq_pct": 100*(cycles-used)/cycles,
        "leftover_mb_s": (cycles-used)*2*timing.frequency_mhz/cycles,
        "command_util_pct": 100*sum(c < cycles for c in result.memory.commands)/cycles,
        "dq_turnarounds": result.memory.dq_turnarounds,
        "activates": sum(b.act for c in banks for b in c),
        "precharges": sum(b.pre for c in banks for b in c),
        "row_hits": result.memory.row_hits, "row_misses": result.memory.row_misses,
        "refreshes": result.memory.refreshes,
        "refresh_command_cycles": sum(result.memory.refreshes),
        "refresh_chip_cycles": sum(result.memory.refreshes)*timing.cycles("tRFC"),
        "pending_requests": result.pending, "incomplete_frames": incomplete_frames,
        "channels": channels, "presentation": presentation,
        "chips": [{"words": sum(b.reads+b.writes for b in c), "activates": sum(b.act for b in c),
                   "precharges": sum(b.pre for b in c), "refreshes": result.memory.refreshes[i]}
                  for i,c in enumerate(banks)],
        "banks": [[{"act": b.act, "pre": b.pre, "read_words": b.reads, "write_words": b.writes}
                   for b in c] for c in banks],
    }
