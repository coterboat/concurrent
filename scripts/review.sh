#!/bin/sh
# The review table: accept or reject what Ludo generated (voices, pictures, films), and install or
# redo from its buttons. Opens in your browser at http://127.0.0.1:8765/
#   ./scripts/review.sh          start it and open it (if it's already running, just open it)
#   ./scripts/review.sh 8770     on another port
# Or double-click "Review Table.command" in the repo folder. Ctrl+C, or closing that window, stops it.
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
PATH="/opt/homebrew/bin:/usr/local/bin:$PATH" ## Finder starts .command files with a bare PATH
PORT="${1:-8765}"
URL="http://127.0.0.1:$PORT/"
if curl -s -o /dev/null --max-time 2 "$URL"; then
	echo "review: already running at $URL (opening it)"
	open "$URL" 2>/dev/null || xdg-open "$URL" 2>/dev/null || start "$URL" 2>/dev/null
	exit 0
fi
## (on Windows `python3` is the Microsoft Store's stub, which only says to install Python: a Python
## that runs, then; the table runs a batch's actions with the same one)
PY=""
for p in python3 python; do
	[ -z "$PY" ] && "$p" -c "" >/dev/null 2>&1 && PY="$p"
done
[ -n "$PY" ] || { echo "review: no Python that runs (python3 or python)"; exit 127; }
exec "$PY" tools/review/review.py serve --port "$PORT" --open
