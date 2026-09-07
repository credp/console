(function () {
  const vscode = acquireVsCodeApi();
  const canvas = document.getElementById("display");
  const context = canvas.getContext("2d", { alpha: false });
  const empty = document.getElementById("empty");
  const status = document.getElementById("status");
  const dimensions = document.getElementById("dimensions");
  const audioButton = document.getElementById("audio");
  let audioContext;
  let nextAudioTime = 0;

  audioButton.addEventListener("click", async () => {
    audioContext ??= new AudioContext({ sampleRate: 48000, latencyHint: "interactive" });
    await audioContext.resume();
    nextAudioTime = audioContext.currentTime;
    audioButton.textContent = "Audio enabled";
    audioButton.disabled = true;
  });

  window.addEventListener("message", ({ data: message }) => {
    if (message.type === "status") {
      status.textContent = message.text;
    } else if (message.type === "frame") {
      drawFrame(message);
    } else if (message.type === "audio") {
      playAudio(message.samples);
    }
  });

  function drawFrame(frame) {
    if (canvas.width !== frame.width || canvas.height !== frame.height) {
      canvas.width = frame.width;
      canvas.height = frame.height;
    }
    const bytes = toBytes(frame.rgba);
    context.putImageData(new ImageData(new Uint8ClampedArray(bytes), frame.width, frame.height), 0, 0);
    empty.hidden = true;
    dimensions.textContent = `${frame.width}×${frame.height} · frame ${frame.sequence}`;
  }

  function playAudio(value) {
    if (!audioContext || audioContext.state !== "running") return;
    const bytes = toBytes(value);
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    const frames = bytes.byteLength / 4;
    const buffer = audioContext.createBuffer(2, frames, 48000);
    const left = buffer.getChannelData(0);
    const right = buffer.getChannelData(1);
    for (let i = 0; i < frames; i += 1) {
      left[i] = view.getInt16(i * 4, true) / 32768;
      right[i] = view.getInt16(i * 4 + 2, true) / 32768;
    }

    if (nextAudioTime < audioContext.currentTime - 0.05 || nextAudioTime > audioContext.currentTime + 0.5) {
      nextAudioTime = audioContext.currentTime + 0.02;
    }
    const source = audioContext.createBufferSource();
    source.buffer = buffer;
    source.connect(audioContext.destination);
    source.start(nextAudioTime);
    nextAudioTime += frames / 48000;
  }

  function toBytes(value) {
    if (value instanceof Uint8Array) return value;
    if (value instanceof ArrayBuffer) return new Uint8Array(value);
    if (value && Array.isArray(value.data)) return Uint8Array.from(value.data);
    return Uint8Array.from(value);
  }

  vscode.postMessage({ type: "ready" });
})();
