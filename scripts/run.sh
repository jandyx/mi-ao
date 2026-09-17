#!/bin/zsh
# Copyright (c) 2026 FanXeon@Poemcoder with Codex
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib/project.sh"
CODEX_ACCESSIBILITY_SCRIPT="${MI_AO_CODEX_ACCESSIBILITY_SCRIPT:-$ROOT/scripts/codex-accessibility.sh}"
OPEN_BIN="${MI_AO_OPEN_BIN:-/usr/bin/open}"

needs_codex_compatibility=true
previous_argument=""
for argument in "$@"; do
  case "$argument" in
    --help|-h|--no-submit|--force-submit)
      needs_codex_compatibility=false
      ;;
  esac
  # Codex CLI 目标不经过 Codex App，无需辅助功能兼容参数。
  if [[ "$previous_argument" == "--submit-target" && "$argument" == "codex-cli" ]]; then
    needs_codex_compatibility=false
  fi
  previous_argument="$argument"
done

if $needs_codex_compatibility && [[ "${MI_AO_CODEX_ACCESSIBILITY_READY:-0}" != "1" ]]; then
  "$CODEX_ACCESSIBILITY_SCRIPT" ensure
fi

if [[ ! -x "$INSTALLED_BIN" ]]; then
  "$ROOT/scripts/install-app.sh"
fi

if [[ "${MI_AO_LAUNCH_VIA_OPEN:-0}" == "1" ]]; then
  RUNTIME_LOG_FILE="${MI_AO_RUNTIME_LOG_FILE:-}"
  [[ -n "$RUNTIME_LOG_FILE" ]] || {
    echo "错误：LaunchServices 启动缺少 MI_AO_RUNTIME_LOG_FILE。" >&2
    exit 1
  }
  exec "$OPEN_BIN" -n -W -g \
    --stdout "$RUNTIME_LOG_FILE" \
    --stderr "$RUNTIME_LOG_FILE" \
    "$INSTALL_APP" \
    --args run "$@"
fi

exec "$INSTALLED_BIN" run "$@"
