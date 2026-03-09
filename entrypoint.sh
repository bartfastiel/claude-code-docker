#!/bin/bash
set -e

SESSION="claude-agent"

echo "[entrypoint] Starting claude-agent container..."

# Restore ~/.claude.json from the most recent (largest) backup if it doesn't exist.
# Claude Code stores its main config at /root/.claude.json (outside the .claude/ dir).
# Since only /root/.claude/ is volume-mounted, this file is lost on container restarts.
# We restore it from the backup that lives inside the mounted volume.
if [ ! -f /root/.claude.json ]; then
    BACKUP=$(ls -S /root/.claude/backups/.claude.json.backup.* 2>/dev/null | head -1)
    if [ -n "$BACKUP" ]; then
        cp "$BACKUP" /root/.claude.json
        echo "[entrypoint] Restored ~/.claude.json from backup: $(basename $BACKUP)"
    fi
fi

# Auth: We rely on the mounted ~/.claude/.credentials.json and ~/.claude.json for OAuth.
# Do NOT inject ANTHROPIC_API_KEY here — it causes an auth conflict warning in Claude Code.
# If you need API key auth instead, set ANTHROPIC_API_KEY in docker-compose.yml environment.

# If tmux session already exists (container restart), just re-attach via ttyd
if tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "[entrypoint] Resuming existing tmux session: $SESSION"
else
    echo "[entrypoint] Creating new tmux session: $SESSION"
    # Start tmux session with a generous terminal size
    tmux new-session -d -s "$SESSION" -x 220 -y 50

    # Give tmux a moment to initialize
    sleep 0.3

    # Launch Claude Code in the session
    # Add --dangerously-skip-permissions for fully autonomous headless mode
    tmux send-keys -t "$SESSION" "cd /workspace && claude" Enter
fi

echo "[entrypoint] Starting ttyd on port 7681..."
echo "[entrypoint] Connect via:"
echo "  Browser/Electron webview: http://localhost:7681"
echo "  WebSocket (programmatic):  ws://localhost:7681/ws"
echo "  WS protocol: send '1' + text to input, receive '0' + text for output"

# ttyd flags:
#   -p 7681          : TCP port
#   -t fontSize=14   : xterm.js font size
#   -t rendererType=canvas : better rendering for animations/colors
#   -W               : NOT used - we want writable (default)
#   --max-clients 0  : unlimited clients (all see same session)
exec ttyd \
    -p 7681 \
    --writable \
    -t fontSize=14 \
    -t rendererType=canvas \
    -t 'theme={"background":"#1a1a2e","foreground":"#e0e0e0","cursor":"#00ff88"}' \
    tmux attach-session -t "$SESSION"
