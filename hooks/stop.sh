#!/bin/bash
# Claude Code hook: fires when Claude finishes a response (Stop event)
# Lets Electron know Claude is done and ready for next input

INPUT=$(cat)
ELECTRON_HOOK_URL="${ELECTRON_HOOK_URL:-http://host.docker.internal:3741/hook}"

curl -sf -X POST "$ELECTRON_HOOK_URL/stop" \
    -H "Content-Type: application/json" \
    -d "$INPUT" &

exit 0
