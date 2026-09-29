#!/bin/sh
# Bring local main up to date with GitHub, so files the playtest bot (or another agent) pushed are
# here before we work: ./scripts/sync_main.sh
#
# Claude Code runs it at the start of every session and before every prompt (.claude/settings.json,
# with --hook: quiet unless something came in, and at most one fetch a minute).
# - Fetches origin/main: over the remote's own URL, else over SSH (GitHub Desktop keeps its https
#   credentials to itself, so a plain `git fetch` in a terminal can't log in).
# - Fast-forwards only: never merges, rebases, stashes or touches uncommitted work. If main has
#   local commits GitHub hasn't seen, or a changed file would be overwritten, it says so and stops.
HOOK=0
[ "$1" = "--hook" ] && HOOK=1
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 0
say() { echo "$@"; }
[ "$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" = "main" ] || { [ $HOOK = 1 ] || say "sync: not on main; nothing done"; exit 0; }

STAMP="$(git rev-parse --git-dir)/sync_main.stamp"
if [ $HOOK = 1 ] && [ -f "$STAMP" ] && [ $(( $(date +%s) - $(stat -f %m "$STAMP" 2>/dev/null || echo 0) )) -lt 60 ]; then
	exit 0
fi
touch "$STAMP"

URL="$(git remote get-url origin 2>/dev/null)"
SSH_URL="$(echo "$URL" | sed -E 's#^https://github.com/#git@github.com:#')"
fetched=0
GIT_TERMINAL_PROMPT=0 git fetch -q origin main 2>/dev/null && fetched=1
if [ $fetched = 0 ] && [ "$SSH_URL" != "$URL" ]; then
	GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=6" \
		git fetch -q "$SSH_URL" "+refs/heads/main:refs/remotes/origin/main" 2>/dev/null && fetched=1
fi
if [ $fetched = 0 ]; then
	[ $HOOK = 1 ] || say "sync: couldn't reach GitHub (offline?); working on the local copy"
	exit 0
fi

behind=$(git rev-list --count HEAD..origin/main)
ahead=$(git rev-list --count origin/main..HEAD)
if [ "$behind" = 0 ]; then
	if [ $HOOK = 0 ]; then
		if [ "$ahead" = 0 ]; then say "sync: main is up to date with GitHub"; else say "sync: main is up to date with GitHub ($ahead local commit(s) not pushed yet)"; fi
	fi
	exit 0
fi
if [ "$ahead" != 0 ]; then
	say "sync: GitHub's main has $behind commit(s) this main doesn't, and this main has $ahead GitHub doesn't."
	say "      Not merging on my own: pull in GitHub Desktop (or git pull) and resolve it there."
	git log --format='      %h %an: %s' HEAD..origin/main | head -8
	exit 0
fi
old=$(git rev-parse --short HEAD)
if git merge -q --ff-only origin/main 2>/dev/null; then
	say "sync: pulled $behind commit(s) from GitHub's main ($old -> $(git rev-parse --short HEAD)):"
	git log --format='      %h %an: %s' "$old..HEAD" | head -8
	pt=$(git diff --name-only "$old" HEAD -- playtest/ | head -6)
	[ -n "$pt" ] && { say "      new from the playtest bot:"; echo "$pt" | sed 's/^/        /'; say "      Read playtest/BUGS.md: the open bugs are the first job."; }
	# what the bots said, for each push they answered (tools/playtest/await_bots.py)
	for sha in $(git log --author="bug clerk" --format=%s "$old..HEAD" | sed -nE 's/^bugs: (review )?([0-9a-f]{7,40}) .*/\2/p' | sort -u); do
		python3 "$ROOT/tools/playtest/await_bots.py" --digest "$sha" --local 2>/dev/null
	done
else
	say "sync: GitHub's main has $behind new commit(s), but a local change would be overwritten; not pulled."
	git diff --name-only HEAD origin/main | head -6 | sed 's/^/      /'
fi
exit 0
