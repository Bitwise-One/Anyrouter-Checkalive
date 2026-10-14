#!/usr/bin/env bash
# keepalive.sh - Health-check a single Anyrouter token using OpenAI Codex CLI
# Usage: keepalive.sh <token> [base_url] [model] [wire_api]
# Prints ALL output (including errors, retries, stack traces) for diagnostics.
set -euo pipefail

TOKEN="${1:?Usage: $0 <token> [base_url] [model] [wire_api]}"
BASE_URL="${2:-https://anyrouter.top/v1}"
MODEL="${3:-gpt-6-astra}"
WIRE_API="${4:-responses}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPTS_FILE="$SCRIPT_DIR/prompts.txt"

# Pick a random non-empty, non-comment prompt line
pick_prompt() {
    if [ -f "$PROMPTS_FILE" ]; then
        local prompts=()
        while IFS= read -r line; do
            [[ -z "$line" || "$line" == \#* ]] && continue
            prompts+=("$line")
        done < "$PROMPTS_FILE"
        if [ ${#prompts[@]} -gt 0 ]; then
            echo "${prompts[$((RANDOM % ${#prompts[@]}))]}"
            return
        fi
    fi
    echo "Write a one-line Python function to check if a string is a palindrome."
}

PROMPT=$(pick_prompt)

# --- Atomically write Codex config.toml ---
# Routes Codex to the Anyrouter OpenAI-compatible endpoint and forces API-key
# auth (no interactive ChatGPT login). The token is NOT written to disk; it is
# passed via the ANYROUTER_TOKEN env var referenced by env_key below.
CONFIG_DIR="$HOME/.codex"
CONFIG_FILE="$CONFIG_DIR/config.toml"
TMP_FILE="$CONFIG_DIR/config.toml.tmp.$$.$(date +%s%N)"

mkdir -p "$CONFIG_DIR"

cat > "$TMP_FILE" << EOF
model = "$MODEL"
model_provider = "anyrouter"
preferred_auth_method = "apikey"
forced_login_method = "api"

[model_providers.anyrouter]
name = "Anyrouter"
base_url = "$BASE_URL"
env_key = "ANYROUTER_TOKEN"
wire_api = "$WIRE_API"
EOF
mv "$TMP_FILE" "$CONFIG_FILE"

# --- Run health check ---
OUTPUT_FILE=$(mktemp)
EXIT_CODE=0

# 120s timeout: if codex enters infinite retry, kill it.
# codex exec is non-interactive by default (never pauses for approval).
# -s read-only: model cannot modify files (safe for a health check)
# --skip-git-repo-check: allow running outside a git repository (local testing)
ANYROUTER_TOKEN="$TOKEN" timeout 120 codex exec \
    -m "$MODEL" \
    -s read-only \
    --skip-git-repo-check \
    "$PROMPT" > "$OUTPUT_FILE" 2>&1 || EXIT_CODE=$?

# --- Print ALL output for diagnostics ---
echo "  Prompt: ${PROMPT:0:60}..."
echo "  --- Codex output (exit_code=$EXIT_CODE) ---"
cat "$OUTPUT_FILE" | sed 's/^/    /'
echo "  --- End output ---"

# --- Evaluate result ---
OUTPUT_CONTENT=$(cat "$OUTPUT_FILE" 2>/dev/null || true)

# Clean up (best-effort; must never affect the pass/fail verdict)
rm -f "$OUTPUT_FILE" "$CONFIG_FILE" 2>/dev/null || true

# 1. Non-zero exit code is a clear failure (includes timeout exit 124)
if [ "$EXIT_CODE" -ne 0 ]; then
    echo "  FAILED (non-zero exit: $EXIT_CODE)"
    exit 1
fi

# 2. Empty response is a failure
if [ -z "$OUTPUT_CONTENT" ]; then
    echo "  FAILED (empty response)"
    exit 1
fi

echo "  SUCCESS"
exit 0
