import * as net from "node:net";
import * as vscode from "vscode";
import { StreamDecoder, VideoFrame } from "./protocol";

let monitor: DotMonitor | undefined;

export function activate(context: vscode.ExtensionContext): void {
  monitor = new DotMonitor(context);
  context.subscriptions.push(
    monitor,
    vscode.commands.registerCommand("dotViewer.open", () => monitor?.show()),
    vscode.commands.registerCommand("dotViewer.restartListener", () => monitor?.restart()),
    vscode.workspace.onDidChangeConfiguration((event) => {
      if (event.affectsConfiguration("dotViewer.host") || event.affectsConfiguration("dotViewer.port")) {
        void monitor?.restart();
      }
    }),
  );
  void monitor.start();
}

export function deactivate(): void {
  monitor?.dispose();
}

class DotMonitor implements vscode.Disposable {
  private server: net.Server | undefined;
  private client: net.Socket | undefined;
  private panel: vscode.WebviewPanel | undefined;
  private status = "Starting listener…";
  private readonly output = vscode.window.createOutputChannel("DOT Console Viewer");

  constructor(private readonly context: vscode.ExtensionContext) {}

  async start(): Promise<void> {
    const config = vscode.workspace.getConfiguration("dotViewer");
    const host = config.get<string>("host", "127.0.0.1");
    const port = config.get<number>("port", 4600);
    const server = net.createServer((socket) => this.accept(socket));
    this.server = server;

    server.on("error", (error) => this.report(`Listener error: ${error.message}`, true));
    await new Promise<void>((resolve, reject) => {
      server.once("listening", resolve);
      server.once("error", reject);
      server.listen(port, host);
    }).catch((error: Error) => {
      this.report(`Could not listen on ${host}:${port}: ${error.message}`, true);
    });

    if (server.listening) this.report(`Listening on ${host}:${port}`);
  }

  async restart(): Promise<void> {
    this.client?.destroy();
    await closeServer(this.server);
    this.server = undefined;
    await this.start();
  }

  show(): void {
    if (this.panel) {
      this.panel.reveal(vscode.ViewColumn.Beside);
      return;
    }

    const panel = vscode.window.createWebviewPanel(
      "dotConsoleViewer",
      "DOT Console Viewer",
      vscode.ViewColumn.Beside,
      { enableScripts: true, retainContextWhenHidden: true },
    );
    this.panel = panel;
    panel.webview.html = webviewHtml(panel.webview, this.context.extensionUri);
    panel.onDidDispose(() => { this.panel = undefined; });
    panel.webview.onDidReceiveMessage((message) => {
      if (message?.type === "ready") this.post({ type: "status", text: this.status });
    });
  }

  dispose(): void {
    this.client?.destroy();
    this.server?.close();
    this.panel?.dispose();
    this.output.dispose();
  }

  private accept(socket: net.Socket): void {
    this.client?.destroy();
    this.client = socket;
    socket.setNoDelay(true);
    const peer = `${socket.remoteAddress ?? "unknown"}:${socket.remotePort ?? 0}`;
    this.report(`Simulator connected from ${peer}`);
    if (vscode.workspace.getConfiguration("dotViewer").get<boolean>("openOnConnect", true)) this.show();

    const decoder = new StreamDecoder();
    decoder.on("frame", (frame: VideoFrame) => {
      this.post({ type: "frame", ...frame });
    });
    decoder.on("audio", (samples: Uint8Array) => {
      this.post({ type: "audio", samples });
    });

    socket.on("data", (chunk) => {
      try {
        decoder.push(chunk);
      } catch (error) {
        this.report(`Stream error: ${error instanceof Error ? error.message : String(error)}`, true);
        socket.destroy();
      }
    });
    socket.on("close", () => {
      if (this.client === socket) this.client = undefined;
      this.report("Simulator disconnected");
    });
    socket.on("error", (error) => this.report(`Connection error: ${error.message}`, true));
  }

  private report(text: string, isError = false): void {
    this.status = text;
    this.output.appendLine(text);
    this.post({ type: "status", text });
    if (isError) void vscode.window.showErrorMessage(`DOT Console Viewer: ${text}`);
  }

  private post(message: unknown): void {
    if (this.panel) void this.panel.webview.postMessage(message);
  }
}

function closeServer(server: net.Server | undefined): Promise<void> {
  if (!server?.listening) return Promise.resolve();
  return new Promise((resolve) => server.close(() => resolve()));
}

function webviewHtml(webview: vscode.Webview, extensionUri: vscode.Uri): string {
  const script = webview.asWebviewUri(vscode.Uri.joinPath(extensionUri, "media", "viewer.js"));
  const style = webview.asWebviewUri(vscode.Uri.joinPath(extensionUri, "media", "viewer.css"));
  const nonce = Math.random().toString(36).slice(2);
  return `<!doctype html>
<html lang="en"><head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src ${webview.cspSource}; script-src 'nonce-${nonce}';">
  <link rel="stylesheet" href="${style}">
  <title>DOT Console Viewer</title>
</head><body>
  <main><canvas id="display"></canvas><p id="empty">Waiting for a video frame…</p></main>
  <footer><span id="status">Starting…</span><span id="dimensions"></span><button id="audio" type="button">Enable audio</button></footer>
  <script nonce="${nonce}" src="${script}"></script>
</body></html>`;
}
