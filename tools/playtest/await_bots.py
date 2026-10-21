#!/usr/bin/env python3
"""Wait for the playtest bots' verdict on a push to main, then print what they found.

Two bots answer every push (both commit as "bug clerk"):
  the playtester's verdict   "bugs: <sha> N open, M fixed"   (playtest/BUGS.md, a report when red)
  the play critic's review   "bugs: review <sha> <slug>"      (playtest/reviews/)
On the last run the verdict came about 25 min after the push, and the review about 50 min after that.

    scripts/await_bots.sh                 # the newest push: wait for both, then pull and print the digest
    scripts/await_bots.sh --after <sha>   # wait for the next push after <sha> first (the loop)
    scripts/await_bots.sh --digest <sha>  # print what the bots said about <sha>, no waiting
                                          #   (scripts/sync_main.sh prints it when their commits come in)

It fetches every minute and never merges: once both are in it fast-forwards main with
scripts/sync_main.sh (never touching uncommitted work). If the review doesn't come within
--grace minutes of the verdict, it goes on without it. Exit: 0 both in, 3 verdict only,
4 timed out, 2 couldn't start.

The scheduled worker (and any session that picks the work up) claims a push first, so one push
is worked once, by one session:

    scripts/await_bots.sh --claim         # exit 0: yours; pulled, and the digest printed. Exit 1: nothing
                                          #   to do (the bots haven't answered the newest push, it's been
                                          #   handled, or another session holds the claim), and why
    scripts/await_bots.sh --done <sha>    # the work is in: mark it handled, drop the claim
    scripts/await_bots.sh --release       # stopping without finishing: drop the claim, try again later

The claim (.git/await_bots.lock) goes stale after --stale hours; handled pushes are listed in
.git/await_bots.handled. Neither is versioned: they belong to this checkout.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
BOT = "bug clerk"
VERDICT = re.compile(r"^bugs: ([0-9a-f]{7,40}) (\d+) open, (\d+) fixed")
REVIEW = re.compile(r"^bugs: review ([0-9a-f]{7,40}) (\S+)")


def git(*args, check=True):
    r = subprocess.run(["git", "-C", ROOT] + list(args), capture_output=True, text=True)
    if check and r.returncode != 0:
        raise RuntimeError("git %s: %s" % (" ".join(args), r.stderr.strip()))
    return r.stdout


def fetch():
    """origin/main, as scripts/sync_main.sh fetches it (the remote's URL, else SSH)."""
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0")
    if subprocess.run(["git", "-C", ROOT, "fetch", "-q", "origin", "main"], env=env, capture_output=True).returncode == 0:
        return True
    url = git("remote", "get-url", "origin", check=False).strip()
    ssh = re.sub(r"^https://github.com/", "git@github.com:", url)
    if ssh == url:
        return False
    env["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes -o ConnectTimeout=6"
    return subprocess.run(["git", "-C", ROOT, "fetch", "-q", ssh, "+refs/heads/main:refs/remotes/origin/main"],
                          env=env, capture_output=True).returncode == 0


def pushes(since=None):
    """[(sha, subject)] of the owner's commits on origin/main, oldest first, that the bots test:
    not the bots' own, and not playtest/ only (the CI ping ignores those)."""
    rng = ("%s..origin/main" % since) if since else "origin/main"
    out = []
    for line in git("log", "--reverse", "--format=%H%x09%an%x09%s", rng, "-n", "400").splitlines():
        sha, author, subject = line.split("\t", 2)
        if author == BOT:
            continue
        files = [f for f in git("show", "--name-only", "--format=", sha).splitlines() if f]
        if files and all(f.startswith("playtest/") for f in files):
            continue
        out.append((sha, subject))
    return out


def answers(since):
    """{sha7: {"verdict": (commit, open, fixed), "review": (commit, slug), "reviews": [commit, ...],
    "last": unix time}} from the bots' commits after `since`: the newest verdict and review, every
    review, and when the bots last said anything about it. A push can get more than one verdict
    (cd3b208: "0 open" at 12:09, the review at 12:42, then "4 open" at 12:54 from the critic's play)."""
    got = {}
    for line in git("log", "--format=%H%x09%an%x09%ct%x09%s", "%s..origin/main" % since).splitlines():
        sha, author, at, subject = line.split("\t", 3)
        if author != BOT:
            continue
        m = VERDICT.match(subject) or REVIEW.match(subject)
        if not m:
            continue
        g = got.setdefault(m.group(1)[:7], {"reviews": [], "last": 0})
        g["last"] = max(g["last"], int(at))
        if VERDICT.match(subject):
            g.setdefault("verdict", (sha, int(m.group(2)), int(m.group(3))))
        else:
            g.setdefault("review", (sha, m.group(2)))
            g["reviews"].append(sha)
    return got


def ledger():
    """(open rows, fixed rows) of playtest/BUGS.md on origin/main, each row its cells."""
    text = git("show", "origin/main:playtest/BUGS.md", check=False)
    rows, part = {"open": [], "fixed": []}, None
    for line in text.splitlines():
        if line.startswith("## "):
            part = line[3:].strip().lower()
            continue
        if part in rows and line.startswith("| B-"):
            rows[part].append([c.strip() for c in line.strip().strip("|").split("|")])
    return rows["open"], rows["fixed"]


def files_of(commit, prefix):
    return [f for f in git("show", "--name-only", "--format=", commit).splitlines() if f.startswith(prefix) and not f.endswith("README.md")]


def digest(sha, got):
    s7 = sha[:7]
    out = ["", "=" * 72, "The bots on %s (%s)" % (s7, git("log", "-1", "--format=%s", sha).strip()), "=" * 72]
    v = got.get("verdict")
    if v:
        out.append("PLAYTESTER: %d open, %d fixed   (%s)" % (v[1], v[2], v[0][:7]))
        for f in files_of(v[0], "playtest/reports/"):
            out.append("  report: " + f)
        opened, fixed = ledger()
        for row in opened:
            out.append("  OPEN  %s  %s  %s  (first seen %s; open now)" % (row[0], row[1], row[2], row[3] if len(row) > 3 else "?"))
        for row in fixed:
            if len(row) > 2 and row[2][:7] == s7:
                out.append("  fixed %s  %s" % (row[0], row[1][:110]))
        if not opened:
            out.append("  no open bugs")
    else:
        out.append("PLAYTESTER: nothing yet")
    if got.get("reviews"):
        for f in [f for c in got["reviews"] for f in files_of(c, "playtest/reviews/")]:
            out.append("PLAY CRITIC: " + f)
            body = git("show", "origin/main:" + f, check=False).rstrip()
            out += ["  " + ln for ln in body.splitlines()]
    else:
        out.append("PLAY CRITIC: no review")
    out += ["", "Next (CLAUDE.md, \"The bots' loop\"): the open bugs first; then the critic's ui/ux notes;",
            "its ideas (new behaviour) go to the owner as a question. When it's in: scripts/await_bots.sh --done %s" % s7]
    return "\n".join(out)


def _gitdir():
    return os.path.join(ROOT, git("rev-parse", "--git-dir").strip())


LOCK = lambda: os.path.join(_gitdir(), "await_bots.lock")
HANDLED = lambda: os.path.join(_gitdir(), "await_bots.handled")


def handled():
    """{sha7: {"bugs": [...], "reviews": [...]}}: what each worked push's claim saw"""
    out = {}
    try:
        for ln in open(HANDLED()):
            ln = ln.strip()
            if not ln:
                continue
            h = json.loads(ln) if ln.startswith("{") else {"sha": ln, "bugs": None, "reviews": None}
            out[h["sha"][:7]] = h
    except (OSError, ValueError):
        pass
    return out


def seen(got):
    """what there is to work on: the open B-numbers and the review files"""
    return {"bugs": sorted(row[0] for row in ledger()[0]),
            "reviews": sorted(f for c in got.get("reviews", []) for f in files_of(c, "playtest/reviews/"))}


SETTLE = 20 ## minutes the bots must have been quiet about a push before it's claimed


def claim(stale_h, grace_min, timeout_min):
    """(exit code, message): take the newest push once the bots are done with it (a verdict and a
    review, then SETTLE minutes of quiet; or a verdict and no review for --grace minutes) and nobody
    has it. A push already worked is taken again only if the bots have since named a bug or written a
    review that its claim didn't see."""
    mine = pushes()
    if not mine:
        return 1, "no push to work on"
    sha, subject = mine[-1]
    got = answers(sha).get(sha[:7], {})
    now = seen(got)
    was = handled().get(sha[:7])
    if was is not None:
        new = [b for b in now["bugs"] if b not in (was.get("bugs") or now["bugs"])] + \
              [r for r in now["reviews"] if r not in (was.get("reviews") or now["reviews"])]
        if not new:
            return 1, "%s (%s) is already handled; waiting for the next push" % (sha[:7], subject)
    if os.path.exists(LOCK()):
        try:
            lk = json.load(open(LOCK()))
        except (OSError, ValueError):
            lk = {}
        age = time.time() - float(lk.get("at", 0))
        if age < stale_h * 3600:
            return 1, "%s is claimed by another session (%s, %.0f min ago)" % (str(lk.get("sha", "?"))[:7], lk.get("by", "?"), age / 60)
    pushed_at = int(git("log", "-1", "--format=%ct", sha).strip())
    if not got.get("verdict"):
        late = (time.time() - pushed_at) / 60
        more = "; over %d min: check the bots" % timeout_min if late > timeout_min else ""
        return 1, "the playtester hasn't answered %s (%s) yet (%.0f min since the commit%s)" % (sha[:7], subject, late, more)
    quiet = (time.time() - got["last"]) / 60
    if not got.get("review"):
        if quiet < grace_min:
            return 1, "the playtester answered %s; waiting for the play critic (%.0f of %d min)" % (sha[:7], quiet, grace_min)
    elif quiet < SETTLE:
        return 1, "both bots answered %s; waiting until they've been quiet %d min (%.0f so far), in case more comes" % (sha[:7], SETTLE, quiet)
    json.dump({"sha": sha, "at": time.time(), "by": os.environ.get("CLAUDE_SESSION_ID") or "pid %d" % os.getpid(),
               "bugs": now["bugs"], "reviews": now["reviews"]}, open(LOCK(), "w"))
    out = sync()
    return 0, "claimed %s (%s)\n%s\n%s" % (sha[:7], subject, out, digest(sha, got))


def done(sha):
    """mark it worked, with what its claim saw (so a bug named later reopens it)"""
    sha = git("rev-parse", sha).strip()
    try:
        lk = json.load(open(LOCK()))
    except (OSError, ValueError):
        lk = {}
    if lk.get("sha", "")[:7] != sha[:7]:
        lk = dict(seen(answers(sha + "~1").get(sha[:7], {})))
    with open(HANDLED(), "a") as f:
        f.write(json.dumps({"sha": sha, "bugs": lk.get("bugs"), "reviews": lk.get("reviews"), "at": time.time()}) + "\n")
    if os.path.exists(LOCK()):
        os.remove(LOCK())
    return "%s handled; claim dropped" % sha[:7]


def sync():
    ## through sh: Windows can't run a .sh itself (WinError 193)
    r = subprocess.run(["sh", os.path.join(ROOT, "scripts", "sync_main.sh")], capture_output=True, text=True)
    return (r.stdout + r.stderr).strip()


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--sha", help="the push to wait for (default: the newest)")
    ap.add_argument("--after", help="wait for the next push after this commit, then for its answers")
    ap.add_argument("--digest", metavar="SHA", help="print what the bots said about SHA and stop")
    ap.add_argument("--local", action="store_true", help="don't fetch (scripts/sync_main.sh just did)")
    ap.add_argument("--claim", action="store_true", help="take the newest answered push to work on (exit 1: nothing to do, and why)")
    ap.add_argument("--done", metavar="SHA", help="mark SHA handled and drop the claim")
    ap.add_argument("--release", action="store_true", help="drop the claim without marking anything handled")
    ap.add_argument("--stale", type=float, default=6.0, help="hours after which a claim is stale (default 6)")
    ap.add_argument("--every", type=int, default=60, help="seconds between fetches (default 60)")
    ap.add_argument("--timeout", type=int, default=240, help="minutes to wait for the bots once the push is known (default 240)")
    ap.add_argument("--grace", type=int, default=90, help="minutes to wait for the review after the verdict (default 90)")
    ap.add_argument("--push-wait", type=int, default=720, help="with --after: minutes to wait for the push (default 720)")
    a = ap.parse_args(argv)

    if a.done:
        print("await_bots: " + done(a.done))
        return 0
    if a.release:
        if os.path.exists(LOCK()):
            os.remove(LOCK())
        print("await_bots: claim dropped")
        return 0
    if not a.local and not fetch():
        print("await_bots: couldn't reach GitHub; working from the last fetch")
    if a.claim:
        code, msg = claim(a.stale, a.grace, a.timeout)
        print(("await_bots: " if code else "") + msg)
        return code
    if a.digest:
        sha = git("rev-parse", a.digest).strip()
        print(digest(sha, answers(git("rev-parse", sha + "~1").strip()).get(sha[:7], {})))
        return 0

    if a.after:
        base = git("rev-parse", a.after).strip()
        t0 = time.time()
        while not pushes(base):
            if time.time() - t0 > a.push_wait * 60:
                print("await_bots: no push after %s in %d min" % (base[:7], a.push_wait))
                return 4
            time.sleep(a.every)
            fetch()
        sha = pushes(base)[-1][0]
    elif a.sha:
        sha = git("rev-parse", a.sha).strip()
    else:
        mine = pushes()
        if not mine:
            print("await_bots: no push to wait for")
            return 2
        sha = mine[-1][0]
    print("await_bots: waiting for the playtester and the play critic on %s (%s)" % (sha[:7], git("log", "-1", "--format=%s", sha).strip()), flush=True)

    t0 = time.time()
    verdict_at = None
    while True:
        later = [s for s, _ in pushes(sha)]
        got = answers(sha)
        ## a push after this one supersedes it: the bots test the newest
        newest = next((s for s in reversed([sha] + later) if s[:7] in got), sha)
        mine = got.get(newest[:7], {})
        if mine.get("verdict") and verdict_at is None:
            verdict_at = time.time()
            print("await_bots: the playtester answered (%d open, %d fixed); waiting for the play critic" % mine["verdict"][1:], flush=True)
        if mine.get("verdict") and mine.get("review"):
            code = 0
            break
        if verdict_at and time.time() - verdict_at > a.grace * 60:
            print("await_bots: no review %d min after the verdict; going on without it" % a.grace)
            code = 3
            break
        if time.time() - t0 > a.timeout * 60:
            print("await_bots: nothing complete after %d min" % a.timeout)
            code = 4
            break
        time.sleep(a.every)
        fetch()
    print(sync())
    print(digest(newest, got.get(newest[:7], {})))
    return code


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except RuntimeError as e:
        print("await_bots: %s" % e)
        sys.exit(2)
