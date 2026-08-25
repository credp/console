# Audio Pipeline Simulation & Test Bed Architecture
**Target Spec:** Raw, headless 16-bit, 48kHz, Stereo PCM data mapped to a 60fps video stream.

New ideas for improving the sim, to make it easier to use it for proving designs without hardware getting in the way

## Just look at [section 3](#3-discrete-event-simulation-engine-model) & [section 4](#4-hardware-emulation-architecture-multi-process--mailboxes), the rest are just notes.

---

## 1. Raw Audio Sample Extraction (Linux Stream Capture)

On **Ubuntu 24.04 LTS** (which utilizes PipeWire with a native PulseAudio compatibility layer), you can extract a pure, headless, bit-exact streaming reference track straight from Spotify. This avoids metadata tags or audio container chunks (like RIFF/WAV headers) that would otherwise break raw data arrays.

### Finding the Audio Source Monitor
```bash
pactl list short sources | grep monitor
```

### Direct Byte Stream Capture Command
The following command taps the monitor stream, handles the sample-rate conversion from Spotify's native 44.1kHz up to **48kHz**, sets up signed 16-bit little-endian serialization (`s16le`), enforces stereo grouping, and dumps the raw bytes straight to disk:
```bash
parec -d <YOUR_MONITOR_SOURCE> --rate=48000 --format=s16le --channels=2 > test_stream.pcm
```

---

## 2. Mathematical Pipeline Constraints & Alignment

To achieve deterministic execution and a flawless looping test bed, the size of your RAM data buffer must map directly to video frames. 

* **Audio Sample Alignment:** 1 frame = 4 bytes (2 channels × 2 bytes per sample).
* **Video Cadence Framing:** At 60fps, 48,000Hz yields exactly **800 audio frames per video frame**.
* **Video Boundary Calculation:** 800 audio frames × 4 bytes = **3,200 bytes per video interval**.

### Guarding Against Glitches
To ensure that looping back to index `0` doesn't cause a channel swap (inverting left/right phases) or a massive digital click, the total file size must be perfectly divisible by **3,200 bytes**. You can pad to boundaries and apply a linear fadeout to smoothly eliminate step-discontinuities at the wrap-around threshold using a utility script.

---

## 3. Discrete Event Simulation Engine Model

The simulation operates as an offline, deterministic **Next-Event Time Advance (NETA)** framework. Rather than running real-time or wasting host CPU cycles stepping a virtual clock sequentially, individual Intellectual Property (IP) blocks declare the next virtual cycle they care about. The engine teleports the simulation clock to the earliest scheduled cycle.

### Core Principles
1. **No Performance Optimization Needed:** Because the entire simulation loops offline and writes directly to file descriptors or pipes, execution speed does not affect the output. 
2. **Deterministic Bug Hunting:** Every single run of the engine is mathematically identical. Any pop, frame slip, stutter, or glitch present in the final output video is guaranteed to be a logic error in your code rather than OS scheduling jitter or host environment latency.

---

## 4. Hardware Emulation Architecture (Multi-Process & Mailboxes)

To simulate clean hardware execution while entirely bypassing Python's Global Interpreter Lock (GIL), individual IP block units are run inside isolated **`multiprocessing.Process`** contexts. They interact via explicit, unidirectional hardware paths and mailboxes.

### Layout Topology
* **Strict Pin-Out Emulation:** Blocks have absolutely zero knowledge of or access to other blocks' states or memory blocks. This completely prevents blocks from modifying shared resources out of order.
* **Mailbox FIFOs:** Integrated communication lines (`multiprocessing.SimpleQueue`) mimic real hardware registers. Blocks drop bytes into explicit outward ports or poll inputs during active windows (like the HDMI Data Island blanking intervals).
* **Clock Routing Synchronization:** Synchronization between processes is managed by a centralized engine utilizing low-overhead `multiprocessing.Pipe` links, preserving the exact sequencing logic you would expect from real silicon.

```python
# Conceptual Topology Pattern
[ Audio DMA Block ] --(Explicit Mailbox/FIFO Path)--> [ HDMI Packetizer Block ]
         ^                                                      ^

         |----(NETA Engine Sync Clock Line via Pipes)-----------|
```

---

## 5. Offline Rendering Execution Pipeline

The final block in your chain routes the simulated audio and video streams straight out of the Python engine into an `ffmpeg` instance via standard pipes. This maps your exact 800-to-1 processing ratio flawlessly.

### Multi-Stream Pipe Syntax
```bash
ffmpeg -f rawvideo -pix_fmt rgb24 -s 1920x1080 -r 60 -i pipe:3 \
       -f s16le -ar 48000 -ac 2 -i pipe:4 \
       -c:v libx264 -c:a aac -pix_fmt yuv420p final_render_test.mp4
```

### Interleave Starvation Safety
To prevent pipeline stalls or OS pipe buffer overflows, the loop maintains strict data interleave discipline. For every **1 Video Frame** written to `pipe:3`, exactly **800 Audio Frames (3,200 bytes)** of your extracted Spotify reference data are injected into `pipe:4` before iterating back to the next cycle calculation.
