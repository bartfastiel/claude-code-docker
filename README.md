# Claude Code in Docker

A **persistent, 24/7 Claude Code CLI agent** running in Docker — accessible interactively from a browser or Electron webview, and controllable programmatically from Node.js/TypeScript via WebSocket.

Built for use cases like autonomous GitHub issue agents that can also be talked to by a human at any time.

```
┌─────────────────────────────────────────────────────────────┐
│                     Docker Container                        │
│                                                             │
│   ┌─────────────────────────────────────────────────────┐  │
│   │              tmux session "claude-agent"            │  │
│   │              $ claude  (interactive CLI)            │  │
│   └──────────────────────┬──────────────────────────────┘  │
│                           │                                 │
│   ┌───────────────────────▼─────────────────────────────┐  │
│   │         ttyd  ·  port 7681  ·  WebSocket            │  │
│   └─────────────────────────────────────────────────────┘  │
│                                                             │
│   Claude Code Hooks  →  POST to your app on port 3741       │
└─────────────────────────────────────────────────────────────┘
         │                              │
         ▼                              ▼
  Human (browser /              Electron / Node.js
  Electron webview)             WebSocket client
```

## Features

- **Persistent session** — Claude keeps running when you disconnect; reconnect anytime and see the exact terminal state you left
- **Interactive** — full colors, animations, and keyboard input, exactly as if Claude were running in your local terminal
- **Dual access** — same WebSocket endpoint works for both humans (via browser/webview) and programs (via Node.js WS client)
- **Structured events** — Claude Code hooks POST lifecycle events (`Stop`, `PostToolUse`, `Notification`) to your app over HTTP
- **Host credentials** — mounts your local `~/.claude/` config so no re-authentication is needed inside the container

## Quick Start

**Prerequisites:** Docker, Docker Compose, and a working [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installation on your host machine (so credentials exist in `~/.claude/`).

```bash
git clone https://github.com/bartfastiel/claude-code-docker
cd claude-code-docker

docker compose up -d
```

Then open **http://localhost:7681** in your browser. Claude Code will be waiting at the prompt.

To stop:
```bash
docker compose down
```

The tmux session — and Claude's conversation — persists across browser disconnects. Only `docker compose down` ends the session.

## How It Works

### Persistence: tmux

[tmux](https://github.com/tmux/tmux) runs Claude Code in a named session (`claude-agent`). The session lives independently of any connected client, so closing the browser tab or disconnecting from the WebSocket has zero effect on the running Claude process.

### Terminal access: ttyd

[ttyd](https://github.com/tsl0922/ttyd) attaches to the tmux session and exposes it over WebSocket on port 7681. Every client that connects sees the same live terminal — you can have a browser tab open while your Electron app is also connected.

### Authentication

The container mounts two files directly from your host:

| Host path | Container path | Purpose |
|---|---|---|
| `~/.claude/` | `/root/.claude/` | Credentials, settings, history |
| `~/.claude.json` | `/root/.claude.json` | Main Claude Code config (session state) |

No login is required inside the container. When the OAuth token refreshes on your host, the container immediately uses the new token.

> **Note:** `~/.claude.json` sits *outside* the `~/.claude/` directory, so it must be mounted separately. The entrypoint also auto-restores it from backup if it goes missing.

## Programmatic Control

### WebSocket protocol (ttyd)

Connect to `ws://localhost:7681/ws` from any WebSocket client.

| Direction | Byte prefix | Meaning |
|---|---|---|
| Client → Server | `1` | Keyboard input (text to send to the terminal) |
| Client → Server | `2` | Resize: `{"columns": N, "rows": N}` |
| Server → Client | `0` | Terminal output (ANSI/VT100 escape sequences) |
| Server → Client | `1` | Window title change |
| Server → Client | `2` | Server preferences (JSON) |

**Send a message to Claude:**
```js
ws.send('1' + 'What is the answer to everything?\n');
```

**Resize the terminal:**
```js
ws.send('2' + JSON.stringify({ columns: 220, rows: 50 }));
```

**Read Claude's response:**
```js
ws.on('message', (data) => {
  const type = data[0];   // '0' = output
  const text = data.slice(1);
  if (type === '0') process.stdout.write(text);
});
```

See [`electron-example/claude-ws-client.ts`](electron-example/claude-ws-client.ts) for a full TypeScript client with typed events.

### Claude Code Hooks

Claude Code fires hooks at lifecycle events. The hooks in [`workspace/.claude/settings.json`](workspace/.claude/settings.json) POST JSON to your app:

| Hook | POST endpoint | When it fires |
|---|---|---|
| `Stop` | `/hook/stop` | Claude finishes a response |
| `PostToolUse` | `/hook/post-tool` | After every tool call (Bash, Read, Write, …) |
| `Notification` | `/hook/notification` | Permission requests and status updates |

Your app listens on `http://0.0.0.0:3741` (reachable from inside Docker as `host.docker.internal:3741`).

```ts
// Minimal hook server
http.createServer((req, res) => {
  let body = '';
  req.on('data', chunk => body += chunk);
  req.on('end', () => {
    res.writeHead(200).end('ok');
    const event = JSON.parse(body);
    console.log(req.url, event); // e.g. /hook/stop { ... }
  });
}).listen(3741);
```

## Autonomous / Headless Mode

For a fully autonomous agent that never pauses to ask for permission, add `--dangerously-skip-permissions` to the `claude` command in [`entrypoint.sh`](entrypoint.sh):

```bash
tmux send-keys -t "$SESSION" "cd /workspace && claude --dangerously-skip-permissions" Enter
```

## Useful Commands

```bash
# See what Claude is currently doing
docker exec claude-agent tmux capture-pane -t claude-agent -p

# Send a message to Claude programmatically (without WebSocket)
docker exec claude-agent tmux send-keys -t claude-agent "your message here" Enter

# View container logs (ttyd + entrypoint output)
docker logs claude-agent

# Restart without losing the Claude session
docker compose restart

# Open a shell inside the container
docker exec -it claude-agent bash
```

## Repository Layout

```
.
├── Dockerfile                        # Ubuntu 24.04 + Node.js 22 + ttyd + Claude Code CLI
├── entrypoint.sh                     # Starts tmux, restores config, launches Claude + ttyd
├── docker-compose.yml                # Volume mounts, port, restart policy
├── hooks/                            # Hook scripts (POST to your app)
│   ├── notification.sh
│   ├── post-tool.sh
│   └── stop.sh
├── workspace/
│   └── .claude/
│       ├── settings.json             # Hook configuration (project-scoped)
│       └── hooks/                    # Hook scripts deployed inside the container
└── electron-example/
    └── claude-ws-client.ts           # TypeScript WebSocket client for Electron/Node.js
```

## License

MIT
