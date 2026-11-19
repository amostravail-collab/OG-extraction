#!/usr/bin/env bash
# 老炮助手版本检查：24 小时内最多联网一次，有新版时输出一行用户提醒。
# 数据源：GitHub API（实时，content 为 base64）；失败回退 jsDelivr CDN（明文，缓存约 12 小时）。
# 任何异常一律静默退出，不阻塞技能主流程。

set -uo pipefail

LOCAL_VERSION="${1:-}"
SKILL_DIR="${2:-}"
[ -n "$LOCAL_VERSION" ] || exit 0
[[ "$LOCAL_VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || exit 0

STATE_DIR="$HOME/.laopao-assistant"
CACHE_FILE="$STATE_DIR/update_check_at"
CACHE_TTL=86400
REPO="amostravail-collab/OG-extraction"
API_URL="${LAOPAO_API_URL:-https://api.github.com/repos/$REPO/contents/UPDATE.json}"
CDN_URL="${LAOPAO_CDN_URL:-https://cdn.jsdelivr.net/gh/$REPO@main/UPDATE.json}"

NOW="$(date +%s)"
if [ -f "$CACHE_FILE" ]; then
  LAST="$(tr -d '[:space:]' < "$CACHE_FILE" 2>/dev/null || true)"
  if [[ "$LAST" =~ ^[0-9]+$ ]] && [ "$NOW" -ge "$LAST" ] && [ $((NOW - LAST)) -lt "$CACHE_TTL" ]; then
    exit 0
  fi
fi
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
printf '%s\n' "$NOW" > "$CACHE_FILE" 2>/dev/null || exit 0

PARSE_JSON='import json,sys
try:
    d = json.load(sys.stdin)
    v = d.get("version", "")
    n = d.get("notice", "")
    if not isinstance(v, str) or not __import__("re").fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", v):
        raise ValueError
    if not isinstance(n, str) or not 1 <= len(n.strip()) <= 40 or any(c in n for c in "\r\n\t"):
        raise ValueError
    print(v + "\t" + n.strip(), end="")
except Exception:
    sys.exit(1)'

parse_payload() {
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$1" | python3 -c "$PARSE_JSON" 2>/dev/null
  elif command -v node >/dev/null 2>&1; then
    printf '%s' "$1" | node -e '
      let raw = "";
      process.stdin.setEncoding("utf8");
      process.stdin.on("data", c => raw += c);
      process.stdin.on("end", () => {
        try {
          const d = JSON.parse(raw);
          const v = d.version, n = d.notice;
          if (typeof v !== "string" || !/^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/.test(v)) process.exit(1);
          if (typeof n !== "string" || n.trim().length < 1 || n.trim().length > 40 || /[\r\n\t]/.test(n)) process.exit(1);
          process.stdout.write(v + "\t" + n.trim());
        } catch (_) { process.exit(1); }
      });' 2>/dev/null
  fi
}

PARSED=""
RAW="$(curl -fsS --max-time 6 "$API_URL" 2>/dev/null || true)"
if [ -n "$RAW" ]; then
  CONTENT="$(printf '%s' "$RAW" | python3 -c 'import json,sys,base64
try:
    print(base64.b64decode(json.load(sys.stdin)["content"]).decode("utf-8"), end="")
except Exception:
    sys.exit(1)' 2>/dev/null || true)"
  [ -n "$CONTENT" ] && PARSED="$(parse_payload "$CONTENT")"
fi
if [ -z "$PARSED" ]; then
  RAW="$(curl -fsS --max-time 6 "$CDN_URL" 2>/dev/null || true)"
  [ -n "$RAW" ] && PARSED="$(parse_payload "$RAW")"
fi
[[ "$PARSED" == *$'\t'* ]] || exit 0
REMOTE_VERSION="${PARSED%%$'\t'*}"
NOTICE="${PARSED#*$'\t'}"

version_is_higher() {
  local rM rm rp lM lm lp
  IFS=. read -r rM rm rp <<< "$1"
  IFS=. read -r lM lm lp <<< "$2"
  if ((10#$rM != 10#$lM)); then
    ((10#$rM > 10#$lM))
  elif ((10#$rm != 10#$lm)); then
    ((10#$rm > 10#$lm))
  else
    ((10#$rp > 10#$lp))
  fi
}

if version_is_higher "$REMOTE_VERSION" "$LOCAL_VERSION"; then
  printf '老炮助手 v%s：%s 回复「1」，我现在帮你更新。\n' "$REMOTE_VERSION" "$NOTICE"
fi
