"""Deterministic synthetic and real-time output-channel workloads."""

from dataclasses import dataclass
from decimal import Decimal, ROUND_FLOOR
import random


@dataclass
class Request:
    id: int
    requester: str
    address: int
    words: int
    write: bool
    arrival: int = 0
    deadline: int | None = None
    frame: int | None = None
    started: int | None = None
    completed: int | None = None
    original_words: int = 0
    max_burst: int = 8
    fifo_kind: str | None = None
    fifo_capacity: int = 0
    flow_words_per_cycle: float = 0
    end_of_frame: bool = False
    frame_deadline: int | None = None

    def __post_init__(self):
        if not self.original_words:
            self.original_words = self.words


def make(name: str, count: int, words: int, working_set: int, stride: int,
         seed: int = 1) -> list[Request]:
    reqs: list[Request] = []
    rng = random.Random(seed)

    def add(who: str, address: int, write: bool = False, arrival: int = 0):
        reqs.append(Request(len(reqs), who, address % max(2, working_set), words, write, arrival))

    if name in ("seq-read", "seq-write", "framebuffer", "scanout"):
        size = {"framebuffer": 360*200*2, "scanout": 1280*720*2}.get(name, working_set)
        for i in range(count):
            add(name, (i * words * 2) % size, name == "seq-write")
    elif name == "two-streams":
        for i in range(count):
            add("stream-a", i * words * 2)
            add("stream-b", working_set // 2 + i * words * 2)
    elif name == "mixed-random":
        for i in range(count):
            add("stream", i * words * 2)
            if i % 4 == 0:
                add("random", rng.randrange(0, working_set // 2) * 2)
    elif name in ("stride", "bank-conflict"):
        actual = stride if name == "stride" else 16 * 1024
        for i in range(count):
            add(name, i * actual)
    else:
        raise ValueError(f"unknown workload {name!r}")
    return reqs


def _cycle(words: int, words_per_second: float, frequency_mhz: float) -> int:
    value = Decimal(words) * Decimal(str(frequency_mhz * 1_000_000)) / Decimal(str(words_per_second))
    return int(value.to_integral_value(rounding=ROUND_FLOOR))


def _stream_cycle(words: int, frame_words: int, frame_hz: float,
                  active_fraction: float, frequency_mhz: float) -> int:
    """Map a stream word to time while preserving inter-frame blanking."""
    frame, within = divmod(words, frame_words)
    frame_cycles = frequency_mhz * 1_000_000 / frame_hz
    return int(frame*frame_cycles + within*frame_cycles*active_fraction/frame_words)


PRESENTATION_MODES = ("capture", "replay", "capture-replay", "stress")


def make_presentation(*, frequency_mhz: float, duration_us: float, burst: int,
                width: int, height: int, refresh_hz: float,
                input_frame_hz: float, scanout_fifo_words: int, scanout_refill_words: int,
                audio_rate: int, audio_channels: int, audio_bits: int,
                audio_fifo_words: int, video_write_buffer_words: int,
                audio_write_buffer_words: int, scanout_base: int, write_base: int,
                audio_base: int, audio_write_base: int,
                presentation_mode: str = "capture", bits_per_pixel: int = 16,
                background_mb_s: float = 0, background_write: bool = True,
                background_base: int = 96*1024*1024,
                video_request_words: int = 256,
                background_request_words: int = 256,
                active_fraction: float = 1.0,
                live_capture_timing: bool = False) -> tuple[list[Request], int]:
    """Create the traffic seen by the presentation-memory controller.

    Live HDMI bypasses this memory. Capture and replay are therefore mutually
    exclusive except in the deliberately pessimistic ``stress`` mode. The
    ``capture-replay`` mode alternates frame states to exercise transitions.
    Pixels are tightly packed into 16-bit SDRAM words. Initial FIFO contents
    give replay/audio requests their deadline lead time.
    """
    if presentation_mode not in PRESENTATION_MODES:
        raise ValueError(f"unknown presentation mode {presentation_mode!r}")
    if not 1 <= bits_per_pixel <= 32:
        raise ValueError("bits per pixel must be between 1 and 32")
    if background_mb_s < 0:
        raise ValueError("background bandwidth must be non-negative")
    if video_request_words <= 0 or background_request_words <= 0:
        raise ValueError("request grants must be positive")
    if not 0 < active_fraction <= 1:
        raise ValueError("active fraction must be in (0, 1]")
    horizon = max(1, int(duration_us * frequency_mhz))
    if scanout_refill_words <= 0:
        raise ValueError("scanout refill must be positive")
    reqs: list[Request] = []

    def add(channel, address, write, arrival, deadline, frame=None, words=None,
            fifo_kind=None, fifo_capacity=0, flow_words_per_cycle=0,
            end_of_frame=False, frame_deadline=None):
        reqs.append(Request(0, channel, address, words or burst, write,
                            max(0, arrival), deadline, frame, max_burst=burst,
                            fifo_kind=fifo_kind, fifo_capacity=fifo_capacity,
                            flow_words_per_cycle=flow_words_per_cycle,
                            end_of_frame=end_of_frame,
                            frame_deadline=frame_deadline))

    frame_words = (width * height * bits_per_pixel + 15) // 16
    scan_rate = frame_words * refresh_hz
    active_scan_rate = scan_rate / active_fraction
    scan_words = int(scan_rate * duration_us / 1_000_000)
    for offset in range(0, scan_words, video_request_words):
        frame = offset // frame_words
        replay_frame = (presentation_mode in ("replay", "stress") or
                        (presentation_mode == "capture-replay" and frame % 2 == 1))
        if replay_frame:
            words = min(video_request_words, scan_words-offset,
                        frame_words-(offset % frame_words))
            # Completion of the grouped request is compared with consumption
            # of its final word, not its first word.
            due = _stream_cycle(offset + words + scanout_fifo_words,
                                frame_words, refresh_hz, active_fraction,
                                frequency_mhz)
            refill_end = (offset // scanout_refill_words + 1) * scanout_refill_words
            arrival = _stream_cycle(refill_end, frame_words, refresh_hz,
                                    active_fraction, frequency_mhz)
            add("scanout", scanout_base + (offset % frame_words) * 2,
                False, arrival, due, frame, words, "read", scanout_fifo_words,
                active_scan_rate/(frequency_mhz*1_000_000))

    words_per_sample = (audio_bits + 15) // 16
    audio_word_rate = audio_rate * audio_channels * words_per_sample
    audio_words = int(audio_word_rate * duration_us / 1_000_000)
    for offset in range(0, audio_words, burst):
        due = _cycle(offset + audio_fifo_words, audio_word_rate, frequency_mhz)
        arrival = _cycle(offset, audio_word_rate, frequency_mhz)
        add("audio", audio_base + offset * 2, False, arrival, due)

    if input_frame_hz > 0:
        write_rate = frame_words * input_frame_hz
        active_write_rate = write_rate / active_fraction
        write_words = int(write_rate * duration_us / 1_000_000)
        for offset in range(0, write_words, video_request_words):
            frame = offset // frame_words
            capture_frame = (presentation_mode in ("capture", "stress") or
                             (presentation_mode == "capture-replay" and frame % 2 == 0))
            if not capture_frame:
                continue
            frame_start_word = frame * frame_words
            within_frame = offset - frame_start_word
            frame_start = _stream_cycle(frame_start_word, frame_words,
                                        input_frame_hz, active_fraction, frequency_mhz)
            if live_capture_timing:
                arrival = _stream_cycle(offset, frame_words, input_frame_hz,
                                        active_fraction, frequency_mhz)
            else:
                request_word = max(frame_start_word,
                                   offset-video_write_buffer_words)
                arrival = _stream_cycle(request_word, frame_words, input_frame_hz,
                                        active_fraction, frequency_mhz)
            # The write-side BRAM fills behind the presentation request point.
            # Each grant must drain before that finite capacity is exhausted;
            # the last grant must also complete before atomic publication.
            publish_deadline = _stream_cycle((frame + 1) * frame_words,
                                             frame_words, input_frame_hz,
                                             active_fraction, frequency_mhz)
            deadline = min(
                publish_deadline,
                _stream_cycle(offset + video_write_buffer_words, frame_words,
                              input_frame_hz, active_fraction, frequency_mhz))
            # Alternate physical capture targets. A buffer is only considered
            # published by the report if every request meets this deadline.
            target = write_base + (frame % 2) * frame_words * 2
            words = min(video_request_words, write_words-offset,
                        frame_words-within_frame)
            add("frame-write", target + within_frame * 2, True, arrival, deadline, frame,
                words,
                "write", video_write_buffer_words,
                active_write_rate/(frequency_mhz*1_000_000),
                within_frame+words >= frame_words, publish_deadline)

        # Audio is produced in frame-tick-sized epochs too. This is an ideal
        # on-demand delivery contract, not a model of machine-side latency.
        audio_write_words = int(audio_word_rate * duration_us / 1_000_000)
        words_per_frame = audio_word_rate / input_frame_hz
        for offset in range(0, audio_write_words, burst):
            frame = int(offset / words_per_frame)
            frame_start_word = int(frame * words_per_frame)
            frame_start = _cycle(frame_start_word, audio_word_rate, frequency_mhz)
            within_frame = offset - frame_start_word
            arrival = frame_start + _cycle(max(0, within_frame-audio_write_buffer_words),
                                           audio_word_rate, frequency_mhz)
            deadline = _cycle(int((frame+1)*words_per_frame), audio_word_rate, frequency_mhz)
            add("audio-write", audio_write_base + offset*2, True, arrival, deadline, frame)

    if background_mb_s:
        background_words_s = background_mb_s * 1_000_000 / 2
        background_words = int(background_words_s * duration_us / 1_000_000)
        working_words = 8 * 1024 * 1024
        for offset in range(0, background_words, background_request_words):
            arrival = _cycle(offset, background_words_s, frequency_mhz)
            add("background", background_base + (offset % working_words) * 2,
                background_write, arrival, None,
                words=min(background_request_words, background_words-offset))

    reqs.sort(key=lambda r: (r.arrival, r.requester, r.address))
    for i, req in enumerate(reqs):
        req.id = i
    return reqs, horizon


def make_output(*, frequency_mhz: float, duration_us: float, burst: int,
                width: int, height: int, refresh_hz: float,
                input_frame_hz: float, scanout_fifo_words: int, scanout_refill_words: int,
                audio_rate: int, audio_channels: int, audio_bits: int,
                audio_fifo_words: int, video_write_buffer_words: int,
                audio_write_buffer_words: int, scanout_base: int, write_base: int,
                audio_base: int, audio_write_base: int) -> tuple[list[Request], int]:
    """Compatibility wrapper for the old simultaneous stress workload."""
    return make_presentation(
        frequency_mhz=frequency_mhz, duration_us=duration_us, burst=burst,
        width=width, height=height, refresh_hz=refresh_hz,
        input_frame_hz=input_frame_hz, scanout_fifo_words=scanout_fifo_words,
        scanout_refill_words=scanout_refill_words, audio_rate=audio_rate,
        audio_channels=audio_channels, audio_bits=audio_bits,
        audio_fifo_words=audio_fifo_words,
        video_write_buffer_words=video_write_buffer_words,
        audio_write_buffer_words=audio_write_buffer_words,
        scanout_base=scanout_base, write_base=write_base,
        audio_base=audio_base, audio_write_base=audio_write_base,
        presentation_mode="stress", bits_per_pixel=16,
        video_request_words=burst)


WORKLOADS = ("seq-read", "seq-write", "two-streams", "framebuffer", "scanout",
             "mixed-random", "stride", "bank-conflict", "output")
