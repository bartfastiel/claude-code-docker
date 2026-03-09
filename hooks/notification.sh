#!/bin/bash
# Claude Code hook: fires on claude notifications (permission requests, status updates, etc.)
# Receives JSON via stdin, POSTs to Electron's HTTP server
# Configure ELECTRON_HOOK_URL in the container environment

INPUT=$(cat)
ELECTRON_HOOK_URL="${ELECTRON_HOOK_URL:-http://host.docker.internal:3741/hook}"

# Fire and forget — don't block Claude
curl -sf -X POST "$ELECTRON_HOOK_URL/notification" \
    -H "Content-Type: application/json" \
    -d "$INPUT" &

exit 0
