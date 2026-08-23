"""The simulated console.

This file contains the code that should eventually resemble the hardware.
"""

import math


# Machine Defs
WIDTH, HEIGHT = 640, 480
FPS = 60
AUDIO_RATE = 48_000
AUDIO_FRAMES_PER_TICK = AUDIO_RATE // FPS
AUDIO_BYTES_PER_TICK = AUDIO_FRAMES_PER_TICK * 2 * 2
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

# Simulator Functions
def simulator__make_hdmi_frame(source: memoryview):
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


# Machine Helpers
def make_test_pattern(pixels: memoryview, width: int, height: int):
    for y in range(height):
        green = y * 31 // (height - 1)
        for x in range(width):
            red = x * 31 // (width - 1)
            pixels[y * width + x] = (red << 10) | (green << 5) | 8
    return


# Machine Functions
# Copy bytes from the incoming audio data to the output buffer, wrapping around if necessary.
def take_audio(data: bytes, position: int) -> tuple[bytes, int]:
    end = position + AUDIO_BYTES_PER_TICK
    assert len(data) >= AUDIO_BYTES_PER_TICK
    if end <= len(data):
        return data[position:end], end % len(data)
    return data[position:] + data[:end - len(data)], end % len(data)

# Copy the framebuffer from one buffer to another.
def copy_framebuffer(source: memoryview, target: memoryview):
    target[:] = source
    return

# Fade out the framebuffer by reducing each color channel by 1, clamping at 0.
def decay_framebuffer(pixels: memoryview):
    for i in range(len(pixels)):
        pixel = pixels[i]
        red = (pixel >> 10) & 31
        green = (pixel >> 5) & 31
        blue = pixel & 31
        red = max(red - 1, 0)
        green = max(green - 1, 0)
        blue = max(blue - 1, 0)
        pixels[i] = (red << 10) | (green << 5) | blue
    return

# Put a white dot on the framebuffer at a position determined by the frame number.
def draw_dot(pixels: memoryview, frame: int):
    phase = math.tau * frame / (FPS * 10)
    x = round((WIDTH - 1) * (0.5 + 0.45 * math.sin(3 * phase)))
    y = round((HEIGHT - 1) * (0.5 + 0.45 * math.sin(2 * phase + math.pi / 2)))
    left = max(x - 8, 0)
    right = min(x + 8, WIDTH)
    top = max(y - 8, 0)
    bottom = min(y + 8, HEIGHT)
    white = memoryview(bytearray([0xFF, 0x7F]) * (right - left)).cast("H")
    for row in range(top, bottom):
        start = row * WIDTH + left
        pixels[start:start + right - left] = white
    return

# Run the simulation loop, calling the output function with each frame of audio and video data.
def run(audio: bytes, frame_limit: int | None, simulator__output) -> None:
    global buffer_index

    # Initialize the framebuffer with a test pattern
    make_test_pattern(framebuffer[0], WIDTH, HEIGHT)
    make_test_pattern(framebuffer[1], WIDTH, HEIGHT)

    audio_position = 0
    frame = -1

    # Draw frames...

    while frame_limit is None or frame < frame_limit:
        # Run simulation loop

        # Set up for the next frame.
        frame += 1
        buffer_index = 1 - buffer_index

        # NOW WE ARE RUNNING MACHINE SPACE
        # **************************************
        
        # AUDIO PIPE     
        audio_chunk, audio_position = take_audio(audio, audio_position)
        # VIDEO PIPE
        # do nothing yet
        copy_framebuffer(framebuffer[1 - buffer_index], framebuffer[buffer_index])
        if frame % 4 == 0:
            decay_framebuffer(framebuffer[buffer_index])
        draw_dot(framebuffer[buffer_index], frame)

        # **************************************
        # NOW WE ARE IN SIMULATOR SPACE
        # **************************************
        # Prepare the HDMI frame from the framebuffer
        simulator__make_hdmi_frame(framebuffer[buffer_index])
        # Pump the output pipes
        simulator__output(hdmi_framebuffer, audio_chunk)
