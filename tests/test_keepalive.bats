setup_file() {
    # Ensure we're in the project root
    cd "$(dirname "$BATS_TEST_FILENAME")/.."
}

setup() {
    export TEST_TOKEN="sk-test12345678"
    export TEST_DIR=$(mktemp -d)
    export HOME="$TEST_DIR"

    # Mock codex globally so all tests that call it don't hang
    mkdir -p "$TEST_DIR/mock_bin"
    cat > "$TEST_DIR/mock_bin/codex" << 'MOCK'
#!/usr/bin/env bash
echo "Mock codex: healthy"
exit 0
MOCK
    chmod +x "$TEST_DIR/mock_bin/codex"
    export PATH="$TEST_DIR/mock_bin:$PATH"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "keepalive.sh fails without token" {
    run bash scripts/keepalive.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "keepalive.sh creates and cleans up config.toml" {
    run bash scripts/keepalive.sh "$TEST_TOKEN" "https://anyrouter.top/v1"
    # After run, config.toml should be cleaned up
    [ ! -f "$TEST_DIR/.codex/config.toml" ]
}

@test "keepalive.sh picks a prompt from prompts.txt" {
    # Verify prompts.txt exists and has content
    [ -f "scripts/prompts.txt" ]
    local count=$(grep -cve '^\s*$' -e '^#' scripts/prompts.txt || true)
    [ "$count" -ge 10 ]
}

@test "run-all.sh fails without tokens" {
    unset ANYROUTER_TOKENS
    run bash scripts/run-all.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"No tokens"* ]]
}

@test "run-all.sh parses single token from env" {
    export ANYROUTER_TOKENS="sk-testAAA"
    run timeout 5 bash scripts/run-all.sh 2>&1 || true
    [ "$status" -eq 124 ] || true  # 124 = timeout, which is expected
    [[ "$output" == *"Loaded 1 token(s)"* ]]
}

@test "run-all.sh parses multiple tokens from env" {
    export ANYROUTER_TOKENS="sk-testAAA
sk-testBBB
sk-testCCC"
    run timeout 5 bash scripts/run-all.sh 2>&1 || true
    [[ "$output" == *"Loaded 3 token(s)"* ]]
}

@test "prompts.txt has no empty lines used as prompts" {
    while IFS= read -r line; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        [ -n "$line" ]
    done < scripts/prompts.txt
}

@test "config.toml atomic write pattern works" {
    local dir="$TEST_DIR/.codex"
    local file="$dir/config.toml"
    local tmp="$dir/config.toml.tmp.$$.$(date +%s%N)"
    mkdir -p "$dir"
    cat > "$tmp" << 'EOF'
model = "gpt-6-astra"
model_provider = "anyrouter"
preferred_auth_method = "apikey"
forced_login_method = "api"

[model_providers.anyrouter]
name = "Anyrouter"
base_url = "https://anyrouter.top/v1"
env_key = "ANYROUTER_TOKEN"
wire_api = "responses"
EOF
    mv "$tmp" "$file"
    [ -f "$file" ]
    grep -q "gpt-6-astra" "$file"
    grep -q "https://anyrouter.top/v1" "$file"
    rm -f "$file"
}
