#!/usr/bin/env python3

import sys

if len(sys.argv) != 3:
    print(f"usage: {sys.argv[0]} input.ppm output.hex")
    sys.exit(1)

with open(sys.argv[1], "r") as f:
    tokens = []

    for line in f:
        line = line.split("#", 1)[0]
        tokens.extend(line.split())

if tokens[0] != "P3":
    raise ValueError("expected P3 PPM")

width  = int(tokens[1])
height = int(tokens[2])
maxval = int(tokens[3])

if width != 256 or height != 256:
    raise ValueError(f"expected 256x256, got {width}x{height}")

if maxval != 255:
    raise ValueError(f"expected maxval 255, got {maxval}")

values = list(map(int, tokens[4:]))

if len(values) != width * height * 3:
    raise ValueError(
        f"expected {width * height * 3} colour values, got {len(values)}"
    )

with open(sys.argv[2], "w") as out:
    for i in range(0, len(values), 3):
        r, g, b = values[i:i+3]

        pixel = ((r >> 3) << 11) | \
                ((g >> 3) << 6)  | \
                ((b >> 3) << 1)

        out.write(f"{pixel:04X}\n")