import os, sys, unittest
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from sdram_model.mapping import decode_address
from sdram_model.model import CommandError, SDRAM, Timing, ns_to_cycles, ns_to_cycles_max
from sdram_model.simulator import metrics, run
from sdram_model.workloads import make_output, make_presentation


class MappingTests(unittest.TestCase):
    def test_requested_interleaves(self):
        a = decode_address(2048, "row-chip-bank-column")
        self.assertEqual((a.chip, a.bank, a.row, a.column), (0,1,0,0))
        a = decode_address(2048, "row-bank-chip-column")
        self.assertEqual((a.chip, a.bank, a.row, a.column), (1,0,0,0))

    def test_physical_geometry_and_1k_experiment(self):
        a = decode_address(2046, "row-chip-bank-column")
        self.assertEqual((a.row, a.column), (0, 1023))
        first = decode_address(0, "stripe-1k-chip-bank")
        half = decode_address(8192, "stripe-1k-chip-bank")
        self.assertEqual((first.chip, first.bank, first.row, first.column), (0,0,0,0))
        self.assertEqual((half.chip, half.bank, half.row, half.column), (0,0,0,512))

    def test_linear_chip_regions(self):
        self.assertEqual(decode_address(0, "linear").chip, 0)
        self.assertEqual(decode_address(64*1024*1024, "linear").chip, 1)

    def test_chip_isolated_bank_interleave(self):
        first = decode_address(0, "chip-row-bank-column")
        next_bank = decode_address(2048, "chip-row-bank-column")
        next_row = decode_address(8192, "chip-row-bank-column")
        other_chip = decode_address(64*1024*1024, "chip-row-bank-column")
        self.assertEqual((first.chip, first.bank, first.row), (0, 0, 0))
        self.assertEqual((next_bank.chip, next_bank.bank, next_bank.row), (0, 1, 0))
        self.assertEqual((next_row.chip, next_row.bank, next_row.row), (0, 0, 1))
        self.assertEqual((other_chip.chip, other_chip.bank, other_chip.row), (1, 0, 0))


class TimingTests(unittest.TestCase):
    def test_ceil_not_round(self):
        self.assertEqual(ns_to_cycles(21, 100), 3)
        self.assertEqual(ns_to_cycles(21, 120), 3)
        self.assertEqual(ns_to_cycles(14, 143), 3)

    def test_cl2_frequency_limit(self):
        with self.assertRaises(ValueError): Timing(120, 2)

    def test_overclock_requires_opt_in_and_is_labeled(self):
        with self.assertRaisesRegex(ValueError, "allow-overclock"): Timing(143,3)
        with self.assertRaisesRegex(ValueError, "allow-overclock"): Timing(150,3)
        timing = Timing(143,3,True)
        self.assertFalse(timing.device_rated)
        self.assertFalse(timing.board_guaranteed)

    def test_refresh_interval_rounds_down(self):
        self.assertEqual(ns_to_cycles_max(7800, 143), 1115)
        self.assertEqual(Timing(100).refresh_interval, 780)


class DeviceTests(unittest.TestCase):
    def setUp(self): self.m = SDRAM(Timing(100, 3))

    def test_state_and_trcd(self):
        self.m.activate(0,0,0,7)
        self.assertEqual(self.m.banks[0][0].row, 7)
        with self.assertRaisesRegex(CommandError, "tRCD"): self.m.access(2,0,0,7,False,1,0)
        self.m.access(3,0,0,7,False,1,0)

    def test_illegal_commands_and_tras(self):
        with self.assertRaises(CommandError): self.m.precharge(0,0,0)
        self.m.activate(0,0,0,1)
        with self.assertRaises(CommandError): self.m.activate(1,0,0,2)
        with self.assertRaisesRegex(CommandError, "tRAS"): self.m.precharge(4,0,0)
        self.m.precharge(5,0,0)

    def test_trp(self):
        self.m.activate(0,0,0,1); self.m.precharge(5,0,0)
        with self.assertRaisesRegex(CommandError, "tRP"): self.m.activate(7,0,0,2)
        self.m.activate(8,0,0,2)

    def test_read_cas_and_shared_dq(self):
        self.m.activate(0,0,0,1)
        start,end = self.m.access(3,0,0,1,False,4,4)
        self.assertEqual((start,end), (6,10))
        self.m.activate(1,1,0,1)
        with self.assertRaisesRegex(CommandError, "DQ collision"): self.m.access(4,1,0,1,False,4,5)

    def test_write_recovery(self):
        self.m.activate(0,0,0,1); self.m.access(3,0,0,1,True,2,0)
        with self.assertRaisesRegex(CommandError, "tWR"): self.m.precharge(5,0,0)
        self.m.precharge(7,0,0)

    def test_turnaround_delays_command_not_write_data(self):
        self.m.activate(0,0,0,1); self.m.access(3,0,0,1,False,2,0)
        with self.assertRaisesRegex(CommandError, "turnaround"):
            self.m.access(6,0,0,1,True,1,1)
        start,_ = self.m.access(9,0,0,1,True,1,1)
        self.assertEqual(start, 9)

    def test_precharge_cannot_interrupt_read_data(self):
        self.m.activate(0,0,0,1); self.m.access(3,0,0,1,False,4,0)
        with self.assertRaisesRegex(CommandError, "interrupt"): self.m.precharge(6,0,0)
        self.m.precharge(10,0,0)

    def test_refresh_requires_idle_and_blocks(self):
        self.m.activate(0,0,0,1)
        with self.assertRaisesRegex(CommandError, "every bank"): self.m.refresh(7,0)
        self.m.precharge(5,0,0); self.m.refresh(8,0)
        with self.assertRaisesRegex(CommandError, "busy"): self.m.activate(10,0,0,2)
        self.m.activate(15,0,0,2)

    def test_other_chip_operates_during_refresh(self):
        self.m.refresh(0,0)
        self.m.activate(1,1,0,3)
        self.m.access(4,1,0,3,False,1,0)

    def test_command_bus(self):
        self.m.activate(0,0,0,1)
        with self.assertRaisesRegex(CommandError, "command bus"): self.m.activate(0,1,0,1)


class OutputWorkloadTests(unittest.TestCase):
    def test_timed_channels_and_channel_metrics(self):
        timing = Timing(100,3)
        reqs,horizon = make_output(frequency_mhz=100,duration_us=100,burst=8,
            width=320,height=200,refresh_hz=60,input_frame_hz=30,
            scanout_fifo_words=128,scanout_refill_words=32,
            audio_rate=48000,audio_channels=2,audio_bits=16,
            audio_fifo_words=64,video_write_buffer_words=128,audio_write_buffer_words=32,
            scanout_base=0,write_base=64*1024*1024,
            audio_base=60*1024*1024,audio_write_base=62*1024*1024)
        self.assertEqual({r.requester for r in reqs}, {"scanout","audio","frame-write","audio-write"})
        self.assertTrue(any(r.arrival > 0 for r in reqs))
        result = run(reqs,timing,"linear","edf-row-hit","open",horizon=horizon)
        report = metrics(result,timing)
        self.assertEqual(report["cycles"], horizon)
        self.assertIn("leftover_mb_s", report)
        self.assertEqual(set(report["channels"]), {"scanout","audio","frame-write","audio-write"})
        self.assertIn("max_wait_us", report["channels"]["frame-write"])
        self.assertIn("max_latency_us", report["channels"]["scanout"])
        self.assertIn("min_deadline_slack_us", report["channels"]["scanout"])

    def _presentation(self, mode, bits=16, background=0, *,
                      active_fraction=1.0, live_capture_timing=False):
        return make_presentation(frequency_mhz=130,duration_us=20_000,burst=8,
            width=320,height=200,refresh_hz=60,input_frame_hz=60,
            scanout_fifo_words=128,scanout_refill_words=32,
            audio_rate=48000,audio_channels=2,audio_bits=16,
            audio_fifo_words=64,video_write_buffer_words=128,
            audio_write_buffer_words=32,scanout_base=0,write_base=32*1024*1024,
            audio_base=60*1024*1024,audio_write_base=62*1024*1024,
            presentation_mode=mode,bits_per_pixel=bits,
            background_mb_s=background, active_fraction=active_fraction,
            live_capture_timing=live_capture_timing)

    def test_capture_and_replay_are_exclusive(self):
        capture, _ = self._presentation("capture")
        replay, _ = self._presentation("replay")
        self.assertIn("frame-write", {r.requester for r in capture})
        self.assertNotIn("scanout", {r.requester for r in capture})
        self.assertIn("scanout", {r.requester for r in replay})
        self.assertNotIn("frame-write", {r.requester for r in replay})

    def test_capture_replay_alternates_and_packs_pixels(self):
        reqs, _ = self._presentation("capture-replay", bits=8)
        capture_frames = {r.frame for r in reqs if r.requester == "frame-write"}
        replay_frames = {r.frame for r in reqs if r.requester == "scanout"}
        self.assertEqual(capture_frames, {0})
        self.assertEqual(replay_frames, {1})
        frame_words = 320*200//2
        self.assertLessEqual(sum(r.original_words for r in reqs if r.requester == "frame-write"),
                             frame_words)

    def test_background_is_paced_and_publication_reported(self):
        reqs, horizon = self._presentation("capture", background=10)
        background = [r for r in reqs if r.requester == "background"]
        self.assertTrue(background)
        self.assertTrue(any(r.arrival > 0 for r in background))
        self.assertEqual(sum(r.original_words for r in background), 100_000)
        timing = Timing(130, 3)
        report = metrics(run(reqs, timing, "stripe-1k-bank-chip", "edf-row-hit",
                             "open", horizon=horizon), timing)
        self.assertIn("published_frames", report["presentation"])
        self.assertEqual(report["presentation"]["replay_frames"], 0)

    def test_soft_grant_does_not_deadlock_opposite_direction(self):
        reqs, horizon = self._presentation("capture", background=10)
        for request in reqs:
            if request.requester == "background":
                request.write = False
        timing = Timing(130, 3)
        report = metrics(run(
            reqs, timing, "stripe-1k-bank-chip", "edf-row-hit", "open",
            horizon=horizon, deadline_guard=2048, scheduler_lookahead=8,
            grant_words={"frame-write":256, "background":256}), timing)
        self.assertEqual(report["presentation"]["failed_captures"], 0)
        self.assertGreater(report["channels"]["background"]["service_pct"], 99)

    def test_watermark_scheduler_capture_and_replay(self):
        timing = Timing(130, 3)
        for mode in ("capture", "replay"):
            reqs, horizon = self._presentation(mode, background=10)
            report = metrics(run(
                reqs, timing, "stripe-1k-bank-chip", "watermark", "open",
                horizon=horizon, deadline_guard=512, scheduler_lookahead=8,
                watermark_low_words=32, watermark_high_words=96,
                grant_words={"scanout":32, "frame-write":32,
                             "background":32}), timing)
            self.assertEqual(report["presentation"]["failed_captures"], 0)
            self.assertEqual(report["presentation"]["replay_underruns"], 0)

    def test_live_capture_uses_active_time_and_blanking(self):
        requests, _ = self._presentation(
            "capture", active_fraction=0.8, live_capture_timing=True)
        video = [request for request in requests
                 if request.requester == "frame-write" and request.frame == 0]
        self.assertTrue(video)
        self.assertEqual(video[0].arrival, 0)
        self.assertLess(video[-1].arrival, video[-1].frame_deadline)


if __name__ == "__main__": unittest.main()
