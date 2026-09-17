#!/bin/zsh
# Copyright (c) 2026 FanXeon@Poemcoder with Codex
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TEMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEMP_ROOT"' EXIT

FAKE_BIN="$TEMP_ROOT/bin"
mkdir -p "$FAKE_BIN" "$TEMP_ROOT/zdot"
# 用户的 ~/.zshenv 可能改写 PATH（例如把 Homebrew 前置），用空 ZDOTDIR 隔离。
export ZDOTDIR="$TEMP_ROOT/zdot"

# preflight 依赖的其他命令仍走真实 PATH；这里只前置一个假 codex。
cat > "$FAKE_BIN/codex" <<'EOS'
#!/bin/zsh
case "$1" in
  --version) echo "codex-cli 0.154.0" ;;
  login)
    if [[ "${FAKE_CODEX_LOGGED_IN:-1}" == "1" ]]; then
      echo "Logged in using ChatGPT"
    else
      echo "Not logged in" >&2
      exit 1
    fi
    ;;
esac
EOS
chmod +x "$FAKE_BIN/codex"

output="$(PATH="$FAKE_BIN:$PATH" "$ROOT/scripts/preflight.sh")"
[[ "$output" == *"Codex CLI 已安装：0.154.0"* ]]
[[ "$output" == *"Codex CLI 登录状态：Logged in using ChatGPT"* ]]
[[ "$output" == *"预检通过"* ]]

output="$(FAKE_CODEX_LOGGED_IN=0 PATH="$FAKE_BIN:$PATH" "$ROOT/scripts/preflight.sh")"
[[ "$output" == *"Codex CLI 尚未登录"* ]]
[[ "$output" == *"预检通过"* ]]

# 没有 codex 时只提示，不计入失败。
EMPTY_BIN="$TEMP_ROOT/empty"
mkdir -p "$EMPTY_BIN"
for tool in uname xcode-select swift sed head curl codesign plutil whisper-cli brew tmux awk; do
  real="$(command -v "$tool" 2>/dev/null || true)"
  [[ -n "$real" ]] && ln -sf "$real" "$EMPTY_BIN/$tool"
done
output="$(PATH="$EMPTY_BIN:/usr/bin:/bin" "$ROOT/scripts/preflight.sh")"
[[ "$output" == *"Codex CLI 未安装"* ]]
[[ "$output" == *"预检通过"* ]]

echo "Preflight Codex CLI shell tests: OK"
