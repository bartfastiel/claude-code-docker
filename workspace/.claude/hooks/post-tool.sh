#!/bin/bash
# Claude Code hook: fires after every tool use (Bash, Read, Write, etc.)
# Useful for Electron to track what Claude is doing programmatically

INPUT=$(cat)
ELECTRON_HOOK_URL="${ELECTRON_HOOK_URL:-http://host.docker.internal:3741/hook}"

curl -sf -X POST "$ELECTRON_HOOK_URL/post-tool" \
    -H "Content-Type: application/json" \
    -d "$INPUT" &

exit 0
