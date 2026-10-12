#!/bin/sh
# mdrun.sh - run a Markdown app with docker compose (Mac / Linux)
#
#   The front matter of the .md is the compose file. This script only cuts it out,
#   renames a top-level "entangled:" key to "x-entangled:" (compose rejects unknown
#   top-level keys; Entangled in the container still reads the original .md),
#   and passes it to docker compose on stdin. Nothing is written to the host.
#
# usage:
#   mdrun.sh app.md                  build, start, wait until healthy, open the x-open URL
#   mdrun.sh app.md open             open the x-open URL in the browser
#   mdrun.sh app.md down             stop and remove
#   mdrun.sh app.md COMMAND [args]   any other docker compose command (logs -f, ps, ...)
#
# options (anywhere on the command line):
#   --no-open    do not open the browser after "up" (or set MDRUN_NO_OPEN=1)
#
# The .md file name is exported as MDFS_SRC, so the front matter can use
#   build: { args: { MDFS_SRC: ${MDFS_SRC} } }
# for .md files not named app.md.
set -eu

fail() { echo "mdrun: $1" >&2; exit "${2:-1}"; }

# Take --no-open out of the arguments (the rest is passed to docker compose).
no_open=${MDRUN_NO_OPEN:-}
for a in "$@"; do
  shift
  if [ "$a" = --no-open ]; then no_open=1; else set -- "$@" "$a"; fi
done

[ $# -ge 1 ] || fail "usage: $0 app.md [up|open|down|COMMAND] [args...] [--no-open]" 2
f=$1; shift
cmd=${1:-up}; [ $# -gt 0 ] && shift

[ -f "$f" ] || fail "file not found: $f"
dir=$(cd "$(dirname "$f")" && pwd)
MDFS_SRC=$(basename "$f"); export MDFS_SRC

# Front matter = lines between the first-line '---' and the next '---' (CRLF tolerated).
fm_raw() {
  awk '{ sub(/\r$/, "") }
       NR == 1 && /^---$/ { f = 1; next }
       f && /^---$/ { e = 1; exit }
       f { print }
       END { exit !e }' "$f"
}
fm() { fm_raw | sed 's/^entangled:/x-entangled:/'; }

fm_raw >/dev/null || fail "no front matter in $f"

compose() { fm | docker compose -f - --project-directory "$dir" "$@"; }

app_url() { fm | sed -n 's/^x-open:[[:space:]]*//p' | head -n 1 | tr -d "\"'"; }

open_url() {
  url=$1
  if [ "$(uname -s)" = Darwin ]; then
    open "$url"
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" >/dev/null 2>&1 &
  else
    echo "mdrun: open $url"
  fi
}

case $cmd in
  up)
    compose up --build --wait "$@"
    url=$(app_url)
    # no x-open in the front matter: nothing to open, which is fine for "up"
    if [ -n "$url" ] && [ -z "$no_open" ]; then open_url "$url"; fi
    ;;
  open)
    url=$(app_url)
    [ -n "$url" ] || fail "no x-open URL in the front matter of $f"
    open_url "$url"
    ;;
  *)
    compose "$cmd" "$@"
    ;;
esac
