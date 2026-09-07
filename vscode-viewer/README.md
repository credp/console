# DOT Console Viewer

A minimal VS Code extension that listens for the console's native output,
assembles self-describing video lines into frames, displays them in a webview
canvas, and plays native PCM audio through the Web Audio API.

## Run it

```sh
npm install
npm run compile
```

Open the `vscode-viewer` directory itself as the VS Code workspace and press
**F5** with the **Run DOT Console Viewer** launch configuration selected. This
opens a second window titled **Extension Development Host**. In that second
window, run **DOT Console: Open Viewer** from the Command Palette.

The listener starts automatically inside the Extension Development Host on
`127.0.0.1:4600`; its host and port are configurable as `dotViewer.host` and
`dotViewer.port`. The **DOT Console Viewer** output channel in that window must
say `Listening on 127.0.0.1:4600` before a producer can connect.

To exercise the complete path without the simulator:

```sh
npm run demo
```

Run this in either window's terminal after the Extension Development Host has
started. The demo is a producer, not the listener; it now waits and retries if
the extension is not listening yet.

Click **Enable audio** once in the viewer. Browsers require a user gesture
before audio playback can begin.

## Debug stream, version 1

The transport is TCP. Every record starts with this 12-byte little-endian
header:

| Offset | Size | Meaning |
| ---: | ---: | --- |
| 0 | 4 | ASCII `DOTS` |
| 4 | 1 | record type |
| 5 | 1 | protocol version (`1`) |
| 6 | 2 | reserved, zero |
| 8 | 4 | payload byte count |

Record types:

| Type | Name | Payload |
| ---: | --- | --- |
| 1 | `FRAME_BEGIN` | `uint32` machine-frame sequence |
| 2 | `VIDEO_LINE` | `uint32 width`, then exactly `width` native pixels |
| 3 | `FRAME_END` | empty |
| 4 | `AUDIO` | any whole number of native stereo sample frames |

Each video line self-describes its width. Frame height is the number of lines
between `FRAME_BEGIN` and `FRAME_END`; the displayed frame width is the widest
line. Pixels are native little-endian RGB1555: bit 15 is alpha (`1` opaque),
then five bits each of red, green, and blue. Shorter lines leave transparent
black pixels at their right edge.

Audio remains native 48 kHz signed 16-bit little-endian stereo PCM, interleaved
left then right. Audio records need not align with video records, although one
60 Hz frame naturally corresponds to 800 stereo sample frames (3,200 bytes).

The envelope is deliberately independent of VS Code. A simulator or FPGA-side
bridge can produce the same stream, and another monitor can consume it later.
