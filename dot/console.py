"""The simulated console.

This file contains the code that should eventually resemble the hardware.
"""


# Machine Defs
WIDTH, HEIGHT = 640, 480
FPS = 60
AUDIO_RATE = 48_000
AUDIO_SAMPLES_PER_TICK = AUDIO_RATE // FPS
AUDIO_FRAMES_PER_TICK = AUDIO_SAMPLES_PER_TICK * 2 * 2
assert AUDIO_RATE % FPS == 0
FRAMEBUFFER_BYTES = WIDTH * HEIGHT * 2

display = bytearray(FRAMEBUFFER_BYTES * 2)
display_view = memoryview(display)
framebuffer: list[memoryview] = [
    display_view[:FRAMEBUFFER_BYTES].cast("H"),
    display_view[FRAMEBUFFER_BYTES:].cast("H"),
]
buffer_index = 0

# Simulator Defs
OUTPUT_WIDTH, OUTPUT_HEIGHT = 1920, 1080
hdmi_framebuffer = bytearray(OUTPUT_WIDTH * OUTPUT_HEIGHT * 2)


def make_test_pattern(pixels: memoryview, width: int, height: int):
    for y in range(height):
        green = y * 31 // (height - 1)
        for x in range(width):
            red = x * 31 // (width - 1)
            pixels[y * width + x] = (red << 10) | (green << 5) | 8
    return


def make_hdmi_frame(source: memoryview):
    """Scale 640x480 to 1440x1080 inside a 1920x1080 frame."""
    target = memoryview(hdmi_framebuffer).cast("H")
    left = (OUTPUT_WIDTH - 1440) // 2
    scaled_row = memoryview(bytearray(1440 * 2)).cast("H")

    for source_y in range(HEIGHT):
        source_row = source[source_y * WIDTH:(source_y + 1) * WIDTH]

        scaled_row[0::9] = source_row[0::4]
        scaled_row[1::9] = source_row[0::4]
        scaled_row[2::9] = source_row[0::4]
        scaled_row[3::9] = source_row[1::4]
        scaled_row[4::9] = source_row[1::4]
        scaled_row[5::9] = source_row[2::4]
        scaled_row[6::9] = source_row[2::4]
        scaled_row[7::9] = source_row[3::4]
        scaled_row[8::9] = source_row[3::4]

        first_y = (source_y * OUTPUT_HEIGHT + HEIGHT - 1) // HEIGHT
        last_y = ((source_y + 1) * OUTPUT_HEIGHT + HEIGHT - 1) // HEIGHT
        for output_y in range(first_y, last_y):
            start = output_y * OUTPUT_WIDTH + left
            target[start:start + 1440] = scaled_row
    return


def take_audio(data: bytes, position: int) -> tuple[bytes, int]:
    end = position + AUDIO_FRAMES_PER_TICK
    assert len(data) >= AUDIO_FRAMES_PER_TICK
    if end <= len(data):
        return data[position:end], end % len(data)
    return data[position:] + data[:end - len(data)], end % len(data)


def run(audio: bytes, frame_limit: int | None, output) -> None:
    global buffer_index

    # Initialize the framebuffer with a test pattern
    make_test_pattern(framebuffer[0], WIDTH, HEIGHT)
    make_test_pattern(framebuffer[1], WIDTH, HEIGHT)

    audio_position = 0
    frame = 0

    # Draw frames...

    while frame_limit is None or frame < frame_limit:
        # Run simulation loop

        # NOW WE ARE RUNNING MACHINE SPACE
        # **************************************
        
        # AUDIO PIPE     
        audio_chunk, audio_position = take_audio(audio, audio_position)
        # VIDEO PIPE
        # do nothing yet

        # **************************************
        # NOW WE ARE IN SIMULATOR SPACE
        # **************************************
        # Prepare the HDMI frame from the framebuffer
        make_hdmi_frame(framebuffer[buffer_index])
        # Pump the output pipes
        output(hdmi_framebuffer, audio_chunk)
        # Set up for the next frame.
        frame += 1
        buffer_index = 1 - buffer_index
