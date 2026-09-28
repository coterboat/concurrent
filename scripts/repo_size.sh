#!/bin/sh
# How big the repo is, and how fast it grows: ./scripts/repo_size.sh
# A full clone downloads the packed history; a shallow clone (--depth 1) only the current files.
# See docs/ASSETS.md, "Storage", for when to move media to Git LFS (not yet: plain git keeps the
# playtest bot's clone complete, unmetered and free of setup).
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
mb() { awk '{printf "%.0f MB", $1 / 1048576}'; }
pack=$(git count-objects -v | awk '/^size-pack/ {p=$2} /^size:/ {l=$2} END {print (p + l) * 1024}')
tree=$(git ls-tree -r -l HEAD | awk '{s += $4} END {print s}')
work=$( (git diff --name-only HEAD; git ls-files --others --exclude-standard) | sort -u | while read -r f; do [ -f "$f" ] && stat -f %z "$f"; done | awk '{s += $1} END {print s + 0}')
echo "history (a full clone):     $(echo "$pack" | mb)"
echo "current files (HEAD):       $(echo "$tree" | mb)"
echo "changed + new, uncommitted: $(echo "$work" | mb)"
echo "largest files at HEAD:"
git ls-tree -r -l HEAD | sort -k4 -n -r | head -5 | awk '{printf "  %6.1f MB  %s\n", $4 / 1048576, $5}'
echo "comfortable on GitHub below ~1 GB of history; hard limit 100 MB per file."
