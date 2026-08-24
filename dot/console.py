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

# replace the dot with a 16x16 space invader sprite, 2 bytes per pixel, 16x16 pixels
player_sprite = memoryview(bytearray.fromhex(
    "0080008000800080000000800080008000800080008000000080008000800080"
    "0080008000800000ff7f000000800080008000800000ff7f0000008000800080"
    "00800080008000800000ff7f0000000000000000ff7f00000080008000800080"
    "0080008000800000ff7fff7fff7fff7fff7fff7fff7fff7f0000008000800080"
    "008000800000ff7fff7f0000ff7fff7fff7fff7f0000ff7fff7f000000800080"
    "00800000ff7fff7fff7fff7fff7fff7fff7fff7fff7fff7fff7fff7f00000080"
    "0000ff7fff7f0000ff7fff7fff7fff7fff7fff7fff7fff7f0000ff7fff7f0000"
    "ff7fff7fff7fff7fff7fff7fff7fff7fff7fff7fff7fff7fff7fff7fff7fff7f"
    "ff7f0000ff7fff7fff7fff7fff7fff7fff7fff7fff7fff7fff7fff7f0000ff7f"
    "ff7f0000ff7f00000000ff7fff7fff7fff7fff7fff7f00000000ff7f0000ff7f"
    "ff7f0000ff7f0000008000000000008000800000000000800000ff7f0000ff7f"
    "00800080008000800000ff7fff7f00000000ff7fff7f00000080000000800080"
    "0080008000800000ff7fff7f0000008000800000ff7fff7f0000008000800080"
    "008000800000ff7fff7f000000800080008000800000ff7fff7f000000800080"
    "00800000ff7fff7f00000080008000800080008000800000ff7fff7f00000080"
    "0080008000000000008000800080008000800080008000800000000000800080"
)).cast("H")


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

def make_decay_LUT() -> list[int]:
    lut = [0] * 65536

    for pixel in range(65536):
        red = (pixel >> 10) & 31
        green = (pixel >> 5) & 31
        blue = pixel & 31
        red = max(red - 1, 0)
        green = max(green - 1, 0)
        blue = max(blue - 1, 0)
        lut[pixel] = (red << 10) | (green << 5) | blue
    return lut

# Fade out the framebuffer by reducing each color channel by 1, clamping at 0.
def decay_framebuffer(pixels: memoryview, lut: list[int] | None = None):
    if lut is not None:
        for i in range(len(pixels)):
            pixels[i] = lut[pixels[i]]
        return
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

def position_from_frame(frame: int) -> tuple[int, int]:
    phase = math.tau * frame / (FPS * 10)
    x = round((WIDTH - 1) * (0.5 + 0.45 * math.sin(3 * phase)))
    y = round((HEIGHT - 1) * (0.5 + 0.45 * math.sin(2 * phase + math.pi / 2)))
    return x, y

# Put a white dot on the framebuffer centered on a specified position.
def draw_dot(pixels: memoryview, x: int, y: int):
    left = max(x - 8, 0)
    right = min(x + 8, WIDTH)
    top = max(y - 8, 0)
    bottom = min(y + 8, HEIGHT)
    white = memoryview(bytearray([0xFF, 0x7F]) * (right - left)).cast("H")
    for row in range(top, bottom):
        start = row * WIDTH + left
        pixels[start:start + right - left] = white
    return

# Draw a sprite on the framebuffer at a specified position, skipping pixels with the alpha bit set.
# Position is the top-left corner of the sprite. The sprite is 16x16 pixels, 2 bytes per pixel, with the alpha bit in the high bit of each pixel.
def draw_sprite(pixels: memoryview, sprite: memoryview, x: int, y: int):
    sprite_width = 16
    sprite_height = 16
    for row in range(sprite_height):
        for col in range(sprite_width):
            pixel_value = sprite[row * sprite_width + col]
            if pixel_value & 0x8000 != 0:  # Alpha bit is set, skip this pixel
                continue
            target_x = x + col
            target_y = y + row
            if 0 <= target_x < WIDTH and 0 <= target_y < HEIGHT:
                pixels[target_y * WIDTH + target_x] = pixel_value
    return

# Run the simulation loop, calling the output function with each frame of audio and video data.
def run(audio: bytes, frame_limit: int | None, simulator__output) -> None:
    global buffer_index

    # Simulator Init Code
    # nothing yet

    # Machine Init Code

    # Initialize the framebuffer with a test pattern
    make_test_pattern(framebuffer[0], WIDTH, HEIGHT)
    make_test_pattern(framebuffer[1], WIDTH, HEIGHT)
    # Build a lookup table for decaying the framebuffer
    LUT = make_decay_LUT()

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
            decay_framebuffer(framebuffer[buffer_index], LUT)
        # Get a position in screen space based upon the frame number
        x,y = position_from_frame(frame)
        #draw_dot(framebuffer[buffer_index], x, y)
        draw_sprite(framebuffer[buffer_index], player_sprite, x, y)

        # **************************************
        # NOW WE ARE IN SIMULATOR SPACE
        # **************************************
        # Prepare the HDMI frame from the framebuffer
        simulator__make_hdmi_frame(framebuffer[buffer_index])
        # Pump the output pipes
        simulator__output(hdmi_framebuffer, audio_chunk)
