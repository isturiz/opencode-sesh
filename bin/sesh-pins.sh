#!/usr/bin/env bash
# Persistent pins shared by the fzf picker and the opencode TUI plugin.
set -euo pipefail
umask 077

PINS_FILE=${SESH_PINS_FILE:-"${XDG_DATA_HOME:-$HOME/.local/share}/sesh/pins.json"}
JQ_BIN=${SESH_JQ:-jq}
empty='{"sessions":[],"directories":[]}'
action=${1:-}
value=${2:-}

read_pins() {
  if [ -f "$PINS_FILE" ]; then
    local pins=''
    pins=$("$JQ_BIN" -ces '
      if length != 1 then error("invalid pins") else .[0] end
      | select(type == "object")
      | {sessions: .sessions, directories: .directories}
      | select(all(.[]; type == "array" and all(.[]; type == "string")))
    ' "$PINS_FILE" 2>/dev/null) || { echo 'sesh: cannot read pins; leaving them unchanged' >&2; return 1; }
    printf '%s\n' "$pins"
  elif [ -e "$PINS_FILE" ] || [ -L "$PINS_FILE" ]; then
    echo 'sesh: cannot read pins; leaving them unchanged' >&2
    return 1
  else
    printf '%s\n' "$empty"
  fi
}

case "$action" in
  read) read_pins; exit 0 ;;
  toggle-session)
    [[ "$value" =~ ^ses_[A-Za-z0-9]+$ ]] || exit 2
    field=sessions ;;
  toggle-directory)
    [[ "$value" == /* && "$value" != *$'\n'* ]] || exit 2
    field=directories ;;
  *) echo 'usage: sesh-pins.sh read|toggle-session ID|toggle-directory PATH' >&2; exit 2 ;;
esac

mkdir -p "$(dirname "$PINS_FILE")"
lock="$PINS_FILE.lock"
for ((attempt = 0; attempt < 50; attempt++)); do
  if mkdir "$lock" 2>/dev/null; then printf '%s\n' "$$" > "$lock/pid"; break; fi
  # Only the owner removes a lock; stale reclamation can race a new owner.
  [ "$attempt" -lt 49 ] || { printf 'sesh: pins lock is busy: %s; if it persists, stop all sesh pickers and OpenCode instances before removing this lock directory\n' "$lock" >&2; exit 1; }
  sleep 0.1
done
tmp=''
cleanup() { [ -z "$tmp" ] || rm -f "$tmp"; rm -f "$lock/pid"; rmdir "$lock" 2>/dev/null || true; }
trap cleanup EXIT
tmp=$(mktemp "${PINS_FILE}.XXXXXX")
read_pins | "$JQ_BIN" -c --arg field "$field" --arg value "$value" '
  .[$field] |= (if index($value) then map(select(. != $value)) else . + [$value] end)
' > "$tmp"
mv -f "$tmp" "$PINS_FILE"
tmp=''
read_pins
