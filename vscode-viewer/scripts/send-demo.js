const net = require("node:net");

const host = process.env.DOT_VIEWER_HOST || "127.0.0.1";
const port = Number(process.env.DOT_VIEWER_PORT || 4600);
const width = 640;
const height = 360;
let sequence = 0;
let phase = 0;
let timer;

connect();

function connect() {
  const socket = net.createConnection({ host, port });
  socket.once("connect", () => {
    console.log(`Connected to DOT Console Viewer at ${host}:${port}`);
    sendFrame(socket);
    timer = setInterval(() => sendFrame(socket), 1000 / 60);
  });
  socket.once("error", (error) => {
    socket.destroy();
    if (error.code === "ECONNREFUSED") {
      process.stdout.write(`Waiting for the viewer listener at ${host}:${port}…\r`);
      setTimeout(connect, 500);
      return;
    }
    console.error(`Could not connect to ${host}:${port}: ${error.message}`);
    process.exitCode = 1;
  });
  socket.once("close", () => {
    if (timer) {
      clearInterval(timer);
      timer = undefined;
      console.log("\nViewer disconnected; waiting for it to return.");
      setTimeout(connect, 500);
    }
  });
}

function sendFrame(socket) {
  const begin = Buffer.alloc(4);
  begin.writeUInt32LE(sequence++);
  send(socket, 1, begin);
  for (let y = 0; y < height; y += 1) {
    const line = Buffer.alloc(4 + width * 2);
    line.writeUInt32LE(width);
    for (let x = 0; x < width; x += 1) {
      const red = (x + phase) * 31 / width & 31;
      const green = y * 31 / height & 31;
      const blue = 8;
      line.writeUInt16LE(0x8000 | red << 10 | green << 5 | blue, 4 + x * 2);
    }
    send(socket, 2, line);
  }
  send(socket, 3, Buffer.alloc(0));

  const audio = Buffer.alloc(800 * 4);
  for (let i = 0; i < 800; i += 1) {
    const sample = Math.round(Math.sin((phase * 800 + i) * Math.PI * 2 * (440 * (40.0*(phase % 720))) / 48000) * 4000);
    audio.writeInt16LE(sample, i * 4);
    audio.writeInt16LE(sample, i * 4 + 2);
  }
  send(socket, 4, audio);
  phase += 1;
}

function send(socket, type, payload) {
  const header = Buffer.alloc(12);
  header.write("DOTS", 0, "ascii");
  header.writeUInt8(type, 4);
  header.writeUInt8(1, 5);
  header.writeUInt32LE(payload.length, 8);
  socket.write(header);
  socket.write(payload);
}
