/**
 * Claude Agent WebSocket Client
 *
 * Connects to the ttyd WebSocket and allows programmatic interaction with Claude.
 *
 * ttyd WebSocket protocol:
 *   Client → Server:
 *     '1' + text   : keyboard input (send text to terminal)
 *     '2' + json   : resize terminal {"columns": N, "rows": N}
 *   Server → Client:
 *     '0' + text   : terminal output (vt100/ansi escape sequences)
 *     '1' + text   : window title change
 *     '2' + json   : server preferences
 */

import WebSocket from 'ws';
import { EventEmitter } from 'events';
import * as http from 'http';

const TTYD_WS_URL = 'ws://localhost:7681/ws';
const HOOK_SERVER_PORT = 3741;

export interface ClaudeHookEvent {
  type: 'notification' | 'post-tool' | 'stop';
  data: Record<string, unknown>;
}

export class ClaudeAgentClient extends EventEmitter {
  private ws: WebSocket | null = null;
  private outputBuffer = '';
  private hookServer: http.Server | null = null;

  /**
   * Connect to the ttyd WebSocket terminal.
   * Also starts a local HTTP server to receive Claude hook events.
   */
  async connect(): Promise<void> {
    await this.startHookServer();
    await this.connectWebSocket();
  }

  disconnect() {
    this.ws?.close();
    this.hookServer?.close();
  }

  /**
   * Send text input to Claude (as if typing on a keyboard).
   * Append '\n' (Enter) to submit.
   */
  sendInput(text: string) {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
      throw new Error('WebSocket not connected');
    }
    // ttyd protocol: '1' prefix = keyboard input
    this.ws.send('1' + text);
  }

  /**
   * Send a complete message to Claude and press Enter.
   */
  sendMessage(message: string) {
    this.sendInput(message + '\n');
  }

  /**
   * Resize the terminal window.
   */
  resize(columns: number, rows: number) {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) return;
    this.ws.send('2' + JSON.stringify({ columns, rows }));
  }

  private connectWebSocket(): Promise<void> {
    return new Promise((resolve, reject) => {
      this.ws = new WebSocket(TTYD_WS_URL);

      this.ws.on('open', () => {
        console.log('[ClaudeClient] Connected to ttyd WebSocket');
        // Set a comfortable terminal size
        this.resize(220, 50);
        resolve();
      });

      this.ws.on('message', (data: Buffer | string) => {
        const msg = data.toString();
        if (!msg.length) return;

        const type = msg[0];
        const payload = msg.slice(1);

        switch (type) {
          case '0': // terminal output
            this.outputBuffer += payload;
            this.emit('output', payload);
            break;
          case '1': // window title
            this.emit('title', payload);
            break;
          case '2': // server preferences (json)
            try {
              const prefs = JSON.parse(payload);
              this.emit('preferences', prefs);
            } catch { /* ignore */ }
            break;
        }
      });

      this.ws.on('error', (err) => {
        console.error('[ClaudeClient] WebSocket error:', err);
        this.emit('error', err);
        reject(err);
      });

      this.ws.on('close', () => {
        console.log('[ClaudeClient] WebSocket disconnected');
        this.emit('disconnected');
      });
    });
  }

  /**
   * Local HTTP server that receives hook events POSTed by Claude Code hooks inside Docker.
   * Claude hooks POST to http://host.docker.internal:3741/hook/<type>
   */
  private startHookServer(): Promise<void> {
    return new Promise((resolve) => {
      this.hookServer = http.createServer((req, res) => {
        if (req.method !== 'POST') {
          res.writeHead(405).end();
          return;
        }

        let body = '';
        req.on('data', (chunk) => { body += chunk; });
        req.on('end', () => {
          res.writeHead(200).end('ok');
          try {
            const data = JSON.parse(body);
            const type = req.url?.replace('/hook/', '') as ClaudeHookEvent['type'];
            this.emit('hook', { type, data } as ClaudeHookEvent);

            if (type === 'stop') {
              this.emit('claude:done', data);
            } else if (type === 'notification') {
              this.emit('claude:notification', data);
            } else if (type === 'post-tool') {
              this.emit('claude:tool', data);
            }
          } catch { /* ignore malformed */ }
        });
      });

      this.hookServer.listen(HOOK_SERVER_PORT, '0.0.0.0', () => {
        console.log(`[ClaudeClient] Hook server listening on :${HOOK_SERVER_PORT}`);
        resolve();
      });
    });
  }
}

// --- Usage example ---
async function main() {
  const client = new ClaudeAgentClient();

  client.on('output', (text: string) => {
    process.stdout.write(text); // stream terminal output
  });

  client.on('claude:done', (data: unknown) => {
    console.log('\n[hook] Claude finished responding:', data);
  });

  client.on('claude:notification', (data: unknown) => {
    console.log('\n[hook] Claude notification:', data);
  });

  await client.connect();

  // Wait for Claude to initialize (first prompt to appear)
  await new Promise(resolve => setTimeout(resolve, 3000));

  console.log('\n[demo] Sending math question...');
  client.sendMessage('What is 1337 * 42? Show the calculation.');

  // Keep running - press Ctrl+C to exit
  process.on('SIGINT', () => {
    client.disconnect();
    process.exit(0);
  });
}

main().catch(console.error);
