import { EventEmitter } from "node:events";

const MAGIC = Buffer.from("DOTS", "ascii");
const HEADER_BYTES = 12;
const MAX_PAYLOAD_BYTES = 16 * 1024 * 1024;
const MAX_LINE_WIDTH = 16_384;
const MAX_FRAME_HEIGHT = 16_384;

export enum RecordType {
  FrameBegin = 1,
  VideoLine = 2,
  FrameEnd = 3,
  Audio = 4,
}

export interface VideoFrame {
  sequence: number;
  width: number;
  height: number;
  rgba: Uint8Array;
}

export class StreamDecoder extends EventEmitter {
  private pending: Buffer = Buffer.alloc(0);
  private sequence = 0;
  private lines: Buffer[] | undefined;

  push(chunk: Buffer): void {
    this.pending = this.pending.length === 0 ? chunk : Buffer.concat([this.pending, chunk]);

    while (this.pending.length >= HEADER_BYTES) {
      if (!this.pending.subarray(0, 4).equals(MAGIC)) {
        throw new Error("debug stream lost record alignment (expected DOTS magic)");
      }

      const type = this.pending.readUInt8(4) as RecordType;
      const version = this.pending.readUInt8(5);
      const payloadBytes = this.pending.readUInt32LE(8);
      if (version !== 1) {
        throw new Error(`unsupported debug-stream version ${version}`);
      }
      if (payloadBytes > MAX_PAYLOAD_BYTES) {
        throw new Error(`record payload is too large: ${payloadBytes} bytes`);
      }
      if (this.pending.length < HEADER_BYTES + payloadBytes) {
        return;
      }

      const payload = this.pending.subarray(HEADER_BYTES, HEADER_BYTES + payloadBytes);
      this.pending = this.pending.subarray(HEADER_BYTES + payloadBytes);
      this.consume(type, payload);
    }
  }

  private consume(type: RecordType, payload: Buffer): void {
    switch (type) {
      case RecordType.FrameBegin:
        if (payload.length !== 4) throw new Error("FRAME_BEGIN must contain a uint32 sequence");
        this.sequence = payload.readUInt32LE(0);
        this.lines = [];
        return;

      case RecordType.VideoLine: {
        if (!this.lines) throw new Error("VIDEO_LINE received outside a frame");
        if (payload.length < 4) throw new Error("VIDEO_LINE is missing its width");
        const width = payload.readUInt32LE(0);
        if (width > MAX_LINE_WIDTH || payload.length !== 4 + width * 2) {
          throw new Error(`invalid VIDEO_LINE width or payload length: ${width}`);
        }
        if (this.lines.length >= MAX_FRAME_HEIGHT) throw new Error("frame has too many lines");
        this.lines.push(Buffer.from(payload.subarray(4)));
        return;
      }

      case RecordType.FrameEnd:
        if (payload.length !== 0) throw new Error("FRAME_END must have an empty payload");
        if (!this.lines) throw new Error("FRAME_END received without FRAME_BEGIN");
        this.emit("frame", makeFrame(this.sequence, this.lines));
        this.lines = undefined;
        return;

      case RecordType.Audio:
        if (payload.length % 4 !== 0) throw new Error("AUDIO must contain whole stereo s16le sample frames");
        this.emit("audio", Uint8Array.from(payload));
        return;

      default:
        throw new Error(`unknown debug-stream record type ${type}`);
    }
  }
}

function makeFrame(sequence: number, lines: Buffer[]): VideoFrame {
  const width = lines.reduce((largest, line) => Math.max(largest, line.length / 2), 0);
  const height = lines.length;
  const rgba = new Uint8Array(width * height * 4);

  for (let y = 0; y < height; y += 1) {
    const line = lines[y];
    for (let x = 0; x < line.length / 2; x += 1) {
      const pixel = line.readUInt16LE(x * 2);
      const target = (y * width + x) * 4;
      rgba[target] = expand5((pixel >>> 10) & 0x1f);
      rgba[target + 1] = expand5((pixel >>> 5) & 0x1f);
      rgba[target + 2] = expand5(pixel & 0x1f);
      rgba[target + 3] = pixel & 0x8000 ? 255 : 0;
    }
  }

  return { sequence, width, height, rgba };
}

function expand5(value: number): number {
  return (value << 3) | (value >>> 2);
}
