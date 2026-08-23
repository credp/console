# Initial A/V Pipeline Bring-Up

## Goal

Build the smallest possible end-to-end audiovisual pipeline for the console
simulator.

The first milestone is deliberately boring:

- generate a static bitmap
- play a known PCM sample
- encode/mux the actual pipeline outputs
- optionally monitor the resulting stream in VLC

Once this works, it becomes the known-good baseline for further video/audio
development.

The initial implementation should avoid inventing infrastructure where existing
tools already solve the problem.

## Canonical Machine Output

### Video

- 1920x1080
- exactly 60.000 Hz
- two framebuffer surfaces
- initial test pattern generated into both surfaces

Exact 60 Hz is intentional. There is no need to inherit the NTSC-derived
60000/1001 timing unless compatibility eventually requires it at an external
boundary.

### Audio

Canonical machine audio format:

- 48,000 Hz
- signed 16-bit PCM
- stereo
- interleaved L/R samples

At exactly 60 frames/sec:

    48000 / 60 = 800 stereo sample frames per video frame

Therefore each video frame corresponds to:

- 800 stereo sample frames
- 1600 individual int16 samples
- 3200 bytes of PCM

This relationship is part of the machine model.

External transports may convert the audio representation if required, but that
conversion must remain outside the canonical machine boundary.

## Startup / Preparation

Before entering the frame loop:

1. Load a suitable audio sample.
2. Convert/render it to canonical 48 kHz signed 16-bit stereo PCM.
3. Store the complete PCM sample in RAM.
4. Generate a static test bitmap.
5. Initialise both framebuffer surfaces with the same bitmap.
6. Create the video and audio pipes.
7. Launch FFmpeg.
8. If requested, arrange for the resulting stream to be monitored by VLC.

The initial audio sample will probably be a public-domain recording of
"Daisy Bell", both for convenience and because of its computer-history
association.

## Runtime

The initial runtime loop should do as little as possible.

For each video frame:

1. Process/output the current video surface.
2. Take the next 800 stereo sample frames from the PCM buffer.
3. Write the resulting 3200 bytes to the audio output.
4. Wrap the audio position when the end of the sample is reached.
5. Advance to the next video frame.

No mixer, tracker, synthesis engine or other audio machinery is required for
bring-up.

Likewise, the initial video content remains static.

## Buffer Representation

Avoid Python lists of Python integers for large binary buffers.

Useful Python types:

- `bytearray` -- mutable contiguous byte storage
- `array.array` -- contiguous typed values
- `memoryview` -- zero-copy views onto objects supporting Python's buffer
  protocol

For example, canonical PCM can naturally be represented as an `array('h')`
after verifying that its item size is 2 bytes.

A `memoryview` can expose the same storage to byte-oriented I/O without copying.

The same principle should be used for framebuffer storage where practical:

    contiguous storage -> typed access -> memoryview -> I/O

## Encoding and Muxing

Do not implement media encoding or MPEG transport inside the simulator.

FFmpeg is external test/output equipment.

Conceptually:

                         +-> raw video pipe --+
    simulator -----------|                    |-> FFmpeg -> MPEG-TS
                         +-> raw audio pipe --+

FFmpeg should:

- consume raw video frames
- consume canonical 48 kHz s16 stereo PCM
- encode the video
- perform any required audio sample-format conversion
- package PCM appropriately if necessary (e.g. SMPTE 302M)
- mux audio and video into MPEG-TS

If SMPTE 302M requires a wider PCM representation, FFmpeg should perform the
conversion from the canonical s16 input where possible. This must not change
the console's audio format.

MPEG-TS is preferred for monitoring because it is naturally streamable and
does not require the output file to be finalised before playback can begin.

## Monitoring

Add:

    --monitor

as a simulator command-line option.

Without `--monitor`, the encoded stream is simply recorded.

With `--monitor`, the exact same encoded output should also be sent to VLC.

Monitoring must not create an alternative rendering path or otherwise change
machine behaviour.

The file remains the artefact; VLC is effectively an oscilloscope attached to
the real output pipeline.

## First Milestone

Success is:

1. simulator starts
2. static bitmap appears through the encoded MPEG-TS path
3. Daisy Bell is audible through the encoded audio path
4. audio runs continuously at the correct rate
5. A/V remains synchronised
6. the resulting stream can be saved
7. `--monitor` allows the same stream to be watched live
