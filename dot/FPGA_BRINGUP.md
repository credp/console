# FPGA Bring-Up Notes

## Hardware milestones

Bring the system up in small, independently testable stages:

1. Flash an LED.
2. Produce an HDMI test pattern.
3. Produce a continuous audio tone.
4. Loop a PCM audio sample.
5. Implement the multi-plane video compositor.

Keep each stage available as a diagnostic mode after later stages work.

## Video architecture

The proposed hardware target has three 640x360 RGB555 planes, composited in
this order:

1. background
2. dynamic
3. foreground

Bit 15 marks a transparent pixel. The ARM side owns the background and
foreground planes. FPGA logic generates the dynamic plane.

Do not construct or store a complete 1920x1080 framebuffer. Generate HDMI
output on demand from the 640x360 sources:

    background --+
    dynamic -----+--> compositor --> scaler --> HDMI timing --> TMDS
    foreground --+

Composite at source resolution before scaling. A 640x360 composite scales to
1920x1080 by repeating every source pixel three times horizontally and every
source line three times vertically. This uses the complete HDMI image and
requires no fractional scaling or pillarboxing.

Integer vertical scaling is an architectural choice, not just an image-quality
choice. A fractional scaler repeats some logical lines more often than others.
If composition is scheduled from output consumption, those lines accidentally
receive different amounts of preparation time. With exact 3x scaling, every
logical line has the same lifetime and the same composition deadline.

Use two 640-pixel ping-pong line buffers. One is scanned out while the next
source line is fetched and composited. Repeated HDMI lines replay the completed
line buffer rather than reading and compositing the planes again.

Standard exact-60 1080p uses 2,200 HDMI pixel clocks per complete line,
including horizontal blanking. Each logical line is displayed for three HDMI
lines, giving the producer a fixed budget of:

    3 * 2,200 = 6,600 HDMI pixel clocks
    6,600 / 148.5 MHz = 44.44 microseconds

The dynamic compositor must meet that same budget for every active logical
line. Its correctness must not depend on extra time during vertical blanking.

Vertical blanking is still a useful scheduling boundary for the ARM-owned
background and foreground planes. At the frame boundary, swap each requested
active-plane pointer and launch queued blits into the surface that has just
become inactive. That surface is no longer being read by scan-out, so it can be
updated without tearing. The blit may continue beyond vertical blank if memory
arbitration permits, but it must complete before that surface is published at a
later frame boundary.

This work is deliberately separate from dynamic-plane generation. Vertical
blank may also service frame status, acknowledgements, and other housekeeping,
but it does not enlarge the per-line dynamic composition budget.

Line-banked registers belong to the logical-line producer rather than the HDMI
timing generator. The active register bank remains fixed while all 640 source
pixels are read and composited. After the final pixel has actually been written
to the line buffer, the pending bank may become active for the next logical
line. The completed buffer is then repeated three times by HDMI, independently
of later register writes.

These line-end swaps occur while the machine is generating the inactive dynamic
surface. They deliberately allow raster-time changes within that next frame.
For example, the same sprite engine can use one set of registers near the top
of the frame, receive a new position, image, or palette bank at a logical line
boundary, and be reused for a different object farther down the page. Every
pixel on one logical line still sees one coherent register bank.

For ARM updates, use two complete register banks and a publish/acknowledge
handshake. The ARM writes the inactive bank and requests publication. The FPGA
accepts that request only at logical line completion, preventing related values
such as addresses, scroll positions, and palette selection from changing
partway through a line.

Linux interrupt latency is not suitable as the sole source of precisely timed
per-line changes. The ARM can prepare a raster command list or line-tagged
register banks ahead of time, and an internal sequencer can publish them at the
specified logical line boundaries. A line-end interrupt remains useful for
notification, debugging, and less timing-sensitive updates.

Do not confuse the register-bank swap with presentation. Line-end register
swaps shape the inactive dynamic surface currently being generated. Only after
all 360 logical lines are complete does the generator publish that surface as
frame-ready. HDMI may adopt the completed dynamic-surface pointer at its next
frame boundary; until then it continues scanning the previous active surface.

Background and foreground updates become visible through pointer swaps at a
frame boundary. The dynamic plane retains its independent logical-line
generation and buffering schedule.

### Non-blocking presentation

HDMI output must never wait for the machine. The timing generator runs
continuously and always has a complete, immutable set of active plane pointers
and presentation registers.

This does not require retaining a complete composited surface. The complete
640x360 source planes are the retained frame state. When a frame repeats, the
scan-out pipeline follows the same active plane pointers and recomposites their
lines on demand. No 640x360 composite cache or 1920x1080 output framebuffer is
needed.

The dynamic plane therefore requires two complete 640x360 surfaces. Scan-out
reads the immutable active dynamic surface while the hardware generator writes
the next frame into the inactive dynamic surface. At the frame boundary, swap
them only if generation has completed; otherwise retain the active pointer and
repeat the old frame. Once swapped, the old active surface becomes the next
generation target.

Without this retained dynamic surface, advancing the generator destroys the
state needed to reconstruct the previous frame. An ephemeral dynamic line
stream would therefore require a full dynamic-frame or composite cache to
support exact repeat-last-frame behaviour. Double-buffering the dynamic source
plane is sufficient and still avoids storing a composited or 1920x1080 output
surface.

The machine builds its next state in inactive surfaces and register banks, then
publishes a frame-ready request. At the HDMI frame boundary:

- if a complete new machine frame is ready, atomically adopt its pointers and
  presentation state, acknowledge it, and release the previously active
  surfaces;
- if no new frame is ready, change nothing and scan out the previous frame
  again.

Never expose a partly generated frame merely to keep nominal machine speed.
Machine progress and presentation progress are separate: the HDMI frame counter
continues at exactly 60 Hz even when the machine-frame sequence number does not
advance. Maintain counters for repeated and missed machine frames so lag is
observable without disturbing output timing.

Once a new frame has been accepted, its planes remain immutable until scan-out
has finished with them. The compositor must still satisfy every logical-line
deadline; the repeat-last-frame policy handles a late machine publication, not
an avoidable line-buffer underflow after publication.

## Audio architecture

The canonical machine format is:

- 48,000 Hz
- signed 16-bit PCM
- stereo
- interleaved left/right

At exactly 60 frames per second, each video frame corresponds to 800 stereo
sample frames, or 3,200 bytes.

Use a small, statically allocated ring buffer. The simulator currently uses
four video frames of audio storage (12,800 bytes). Audio timing and digital
silence should remain valid even when no sample is playing.

## Clock model

A useful logical active-pixel clock for 640x360 is 13.824 MHz:

    640 * 360 * 60 = 13,824,000

This gives:

- 640 ticks per source line
- 230,400 ticks per video frame
- 288 ticks per 48 kHz stereo sample frame
- 800 audio sample frames per video frame

The simulator need not call an empty tick function 13.824 million times per
second. Advance directly between scheduled events while maintaining the same
master-clock count and divider relationships.

HDMI timing belongs to the output/simulator boundary and should not dictate the
machine clock.

## Memory and blitter

Two external memory cards are available, one on each DE10-Nano I/O port. One
card is intended for deterministic HDMI and audio output storage. Avoid storing
a 1080p output framebuffer; source planes, line buffers, and audio buffers have
far lower bandwidth requirements.

A future blitter can provide controlled movement between ARM memory and video
memory. Initial operations need only include:

- rectangle copy
- rectangle fill
- readback to ARM memory

Possible later operations include masked sprite copy, plane-to-plane copy, and
scrolling. Use command-shaped registers containing source, destination plane,
coordinates, dimensions, strides, operation, start, and status. Preserve clear
ownership rather than allowing the ARM and FPGA to write the same active plane
without arbitration.

## Boot and FPGA reconfiguration

The normal system image should contain a small, known-good recovery bitstream.
It should:

- establish stable HDMI timing without Linux
- display a small DOT boot splash
- output correctly clocked digital silence
- place HPS-to-FPGA bridges in a documented safe state
- expose a hardware ABI and build identifier to the ARM
- avoid depending on initialized external framebuffer memory

The splash should make the state obvious, for example:

    DOT
    FPGA READY
    WAITING FOR ARM
    build <ID>

Linux may subsequently load the operational RBF through the Cyclone V FPGA
Manager. Runtime reconfiguration must quiesce users, disable affected bridges,
load the bitstream and matching device-tree description, restore the bridges,
and restart the relevant software. Keep the recovery bitstream bootable so a
bad experimental image cannot prevent the ARM from accepting a replacement.

A later partial-reconfiguration design could keep HDMI timing, silent-audio
fallback, bridge safety, and reconfiguration control in a permanent shell while
replacing only the machine-specific region.

## Reproducible Linux image

The ARM-side Linux build should be pinned and reproducible. Buildroot is a
reasonable starting point. A release should produce:

- bootloader
- device tree and overlays
- Linux kernel
- root filesystem
- recovery and operational FPGA bitstreams
- ARM application
- complete SD-card image
- manifest containing versions and checksums

Version the hardware/software interface explicitly. The ARM application should
read the FPGA ABI/build register and reject incompatible hardware rather than
continuing with an incorrect register or memory layout.
