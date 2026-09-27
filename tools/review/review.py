#!/usr/bin/env python3
"""Accept/reject review tool for generated assets (voice lines, images, video).

Batches live in review/<batch>/ at the repo root:
    batch.json   written by a generator: the items to review, and the actions that finish it
    review.json  written by this tool: the verdicts
    rejected.json written by `apply` (and before a regen action runs): what a generator should re-roll
    runs.log     written by this tool: the output of every action run from the UI

Commands:
    serve  [--port 8765] [--open]   local web UI + JSON API on 127.0.0.1
    status [<batch>]                counts per verdict per group
    apply  <batch> [--dry-run]      copy accepted files to their targets, write rejected.json
    new    <batch> --title "..."    scaffold an empty batch
    sample [--force]                build the review/_sample demo batch

Standard library only. See tools/review/README.md.
"""
from __future__ import annotations

import argparse
import codecs
import filecmp
import hmac
import json
import math
import os
import re
import secrets
import shlex
import shutil
import signal
import subprocess
import struct
import sys
import tempfile
import threading
import time
import wave
import webbrowser
import zlib
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, quote, unquote, urlsplit

TOOL_DIR = Path(__file__).resolve().parent
REPO = TOOL_DIR.parent.parent
REVIEW = REPO / "review"
INDEX_HTML = TOOL_DIR / "index.html"
TOKEN_SLOT = "__REVIEW_TOKEN__"  # index.html carries this; the server swaps in its token

VERDICTS = ("accept", "reject", "pending")
BATCH_RE = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9_.-]*$")
MTIME_EPS = 0.001  # slack for float round-trips through JSON
HISTORY_KEEP = 10

IMAGE_EXTS = (".png", ".webp", ".jpg", ".jpeg", ".gif", ".svg")
VIDEO_EXTS = (".mp4", ".webm", ".mov", ".m4v", ".ogv")
## where a generator may point at the clip behind an image item (a GIF, a poster frame)
VIDEO_META_KEYS = ("video", "video_mp4", "video_webm", "video_mov")

CONTENT_TYPES = {
    ".mp3": "audio/mpeg", ".wav": "audio/wav", ".ogg": "audio/ogg", ".oga": "audio/ogg",
    ".opus": "audio/ogg", ".m4a": "audio/mp4", ".flac": "audio/flac",
    ".png": "image/png", ".webp": "image/webp", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
    ".gif": "image/gif", ".svg": "image/svg+xml", ".json": "application/json",
    ".mp4": "video/mp4", ".m4v": "video/mp4", ".webm": "video/webm", ".mov": "video/quicktime",
    ".ogv": "video/ogg",
}

_LOCK = threading.Lock()  # serialises review.json read-modify-write


class ReviewError(Exception):
    def __init__(self, msg: str, status: int = 400):
        super().__init__(msg)
        self.status = status


# ---------------------------------------------------------------- storage

def ensure_review_root() -> None:
    REVIEW.mkdir(exist_ok=True)
    gd = REVIEW / ".gdignore"
    if not gd.exists():
        gd.touch()


def batch_dir(name: str, must_exist: bool = True) -> Path:
    if not name or not BATCH_RE.match(name):
        raise ReviewError(f"bad batch name: {name!r}")
    d = REVIEW / name
    if must_exist and not (d / "batch.json").is_file():
        raise ReviewError(f"no such batch: {name} (expected {d / 'batch.json'})", 404)
    return d


def list_batch_names() -> list[str]:
    if not REVIEW.is_dir():
        return []
    return sorted(p.name for p in REVIEW.iterdir()
                  if p.is_dir() and BATCH_RE.match(p.name) and (p / "batch.json").is_file())


def read_json(path: Path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return default


def atomic_write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write("\n")
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def load_batch(name: str) -> tuple[Path, dict]:
    d = batch_dir(name)
    try:
        data = read_json(d / "batch.json", None)
    except json.JSONDecodeError as e:
        raise ReviewError(f"{name}/batch.json is not valid JSON: {e}", 500)
    if not isinstance(data, dict) or not isinstance(data.get("items", []), list):
        raise ReviewError(f"{name}/batch.json must be an object with an 'items' list", 500)
    items = [it for it in data.get("items", []) if isinstance(it, dict) and it.get("id")]
    data["items"] = items
    return d, data


def load_review(d: Path) -> dict:
    try:
        data = read_json(d / "review.json", None)
    except json.JSONDecodeError as e:
        raise ReviewError(f"{d.name}/review.json is not valid JSON: {e}", 500)
    if not isinstance(data, dict):
        data = {}
    if not isinstance(data.get("items"), dict):
        data["items"] = {}
    return data


def item_path(d: Path, item: dict) -> Path | None:
    rel = item.get("file")
    if not rel or not isinstance(rel, str):
        return None
    p = (d / rel).resolve()
    root = d.resolve()
    if root not in p.parents:
        return None  # escapes the batch dir: treat as missing
    return p


def item_kind(item: dict) -> str:
    k = item.get("kind")
    if k in ("audio", "image", "video"):
        return k
    ext = Path(item.get("file") or "").suffix.lower()
    if ext in IMAGE_EXTS:
        return "image"
    if ext in VIDEO_EXTS:
        return "video"
    return "audio"


def batch_file(d: Path, rel) -> Path | None:
    """An existing file inside the batch folder, named relative to that folder or, as some
    generators write it, relative to the repo root (review/<batch>/...)."""
    if not rel or not isinstance(rel, str) or os.path.isabs(rel):
        return None
    root = d.resolve()
    for base in (d, REPO):
        p = (base / rel).resolve()
        if root in p.parents and p.is_file():
            return p
    return None


def companion_video(d: Path, item: dict) -> Path | None:
    """The clip behind a non-video item: `video` or meta.video_mp4 (etc.), or a poster frame
    written next to its clip (x_poster.png -> x.mp4)."""
    if item_kind(item) == "video":
        return None
    meta = item.get("meta") if isinstance(item.get("meta"), dict) else {}
    for rel in [item.get("video")] + [meta.get(k) for k in VIDEO_META_KEYS]:
        p = batch_file(d, rel)
        if p is not None and p.suffix.lower() in VIDEO_EXTS:
            return p
    f = item_path(d, item)
    if f is not None and f.stem.endswith("_poster"):
        for ext in VIDEO_EXTS:
            p = f.with_name(f.stem[: -len("_poster")] + ext)
            if p.is_file():
                return p
    return None


def media_url(name: str, d: Path, p: Path, st=None) -> str:
    st = st or p.stat()
    rel = p.relative_to(d.resolve()).as_posix()
    return f"/media/{quote(name)}/{quote(rel)}?v={st.st_mtime:.3f}"


def merge_item(name: str, d: Path, item: dict, entry: dict | None) -> dict:
    """batch item + its verdict entry + computed status."""
    p = item_path(d, item)
    exists = p is not None and p.is_file()
    st = p.stat() if exists else None
    entry = entry if isinstance(entry, dict) else {}
    verdict = entry.get("verdict", "pending")
    if verdict not in VERDICTS:
        verdict = "pending"
    regenerated = False
    fm = entry.get("file_mtime")
    if exists and verdict in ("accept", "reject") and "file_mtime" in entry:
        # file_mtime null = the verdict was given while the file was missing (a reject);
        # a file showing up since then is a new take.
        regenerated = fm is None or (isinstance(fm, (int, float)) and st.st_mtime > fm + MTIME_EPS)
    if not exists and verdict != "reject":
        status = "missing"  # a rejected missing file stays rejected, so it gets re-rolled
    elif regenerated:
        status = "pending"
    else:
        status = verdict
    out = dict(item)
    out["kind"] = item_kind(item)
    out.update(
        status=status,
        verdict=verdict,
        regenerated=regenerated,
        note=entry.get("note", "") or "",
        edited_text=entry.get("text"),
        decided_at=entry.get("at"),
        history=entry.get("history", []) if isinstance(entry.get("history"), list) else [],
        exists=exists,
        mtime=st.st_mtime if st else None,
        size=st.st_size if st else None,
        url=(f"/media/{quote(name)}/{quote(item['file'])}?v={st.st_mtime:.3f}" if st else None),
    )
    poster = batch_file(d, item.get("poster"))
    if poster is not None:
        out["poster_url"] = media_url(name, d, poster)
    vid = companion_video(d, item)
    if vid is not None:
        vst = vid.stat()
        out.update(video_file=vid.relative_to(d.resolve()).as_posix(), video_size=vst.st_size,
                   video_url=media_url(name, d, vid, vst))
    return out


def merged_batch(name: str) -> dict:
    d, data = load_batch(name)
    rv = load_review(d)["items"]
    items = [merge_item(name, d, it, rv.get(it["id"])) for it in data["items"]]
    return {"batch": name, "title": data.get("title") or name, "items": items,
            "actions": [public_action(a) for a in batch_actions(name, data)]}


def summarize(items: list[dict]) -> dict:
    c = {"total": len(items), "accept": 0, "reject": 0, "pending": 0, "missing": 0, "regenerated": 0}
    for it in items:
        c[it["status"]] += 1
        if it["regenerated"]:
            c["regenerated"] += 1
    c["reviewed"] = c["accept"] + c["reject"]
    return c


def decide(name: str, item_id: str, verdict=None, note=None, text=None) -> dict:
    if verdict is not None and verdict not in VERDICTS:
        raise ReviewError(f"verdict must be one of {', '.join(VERDICTS)}")
    if note is not None and not isinstance(note, str):
        raise ReviewError("note must be a string")
    if text is not None and not isinstance(text, str):
        raise ReviewError("text must be a string")
    with _LOCK:
        d, data = load_batch(name)
        item = next((it for it in data["items"] if it["id"] == item_id), None)
        if item is None:
            raise ReviewError(f"no item {item_id!r} in {name}", 404)
        review = load_review(d)
        entries = review["items"]
        old = entries.get(item_id) if isinstance(entries.get(item_id), dict) else {}
        entry = dict(old)
        before = merge_item(name, d, item, old)
        p = item_path(d, item)
        if verdict is not None:
            if verdict == "accept" and not before["exists"]:
                raise ReviewError("the file is missing; can't accept it", 409)
            if before["regenerated"]:
                # the file changed since this verdict: keep the old call as history
                prev = {k: old[k] for k in ("verdict", "note", "text", "at", "file_mtime") if k in old}
                entry["history"] = (entry.get("history") or [])[-(HISTORY_KEEP - 1):] + [prev]
                entry["note"] = ""
            entry["verdict"] = verdict
            entry["at"] = datetime.now().isoformat(timespec="seconds")
            entry["file_mtime"] = p.stat().st_mtime if before["exists"] else None
        if note is not None:
            entry["note"] = note.strip()
        if text is not None:
            t = text.strip()
            if not t or t == (item.get("text") or "").strip():
                entry.pop("text", None)
            else:
                entry["text"] = t
        entry.setdefault("verdict", "pending")
        entry.setdefault("note", "")
        entries[item_id] = entry
        atomic_write_json(d / "review.json", review)
        return merge_item(name, d, item, entry)


def rejected_entries(items: list[dict]) -> list[dict]:
    return [{"id": it["id"],
             "text": it.get("edited_text") or it.get("text") or "",
             "note": it.get("note") or "",
             "meta": it.get("meta") or {}}
            for it in items if it["status"] == "reject"]


def write_rejected(name: str) -> tuple[Path, int]:
    """review/<batch>/rejected.json from the current verdicts (what a generator re-rolls)."""
    d, _ = load_batch(name)
    rejected = rejected_entries(merged_batch(name)["items"])
    atomic_write_json(d / "rejected.json", rejected)
    return d / "rejected.json", len(rejected)


# ---------------------------------------------------------------- actions
#
# batch.json may declare the commands that finish a review ("actions"). The UI shows them as
# buttons with their options; the browser only ever sends {batch, action, options} and the
# server builds the argv from the declaration: cmd[0] must be "python3" (run as this Python),
# cmd[1] a script inside the repo, and every option must be declared and valid.

OPTION_TYPES = ("bool", "int", "string", "choice")
FLAG_RE = re.compile(r"^--?[A-Za-z0-9][A-Za-z0-9_-]*$")
ACTION_ID_RE = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9_.-]{0,63}$")
STRING_MAX = 500


def builtin_actions(name: str) -> list[dict]:
    """What a batch that declares no actions gets: this tool's own `apply`."""
    return [{"id": "install", "kind": "install", "label": "Install accepted",
             "help": "Copy every accepted file to its target and write rejected.json (review.py apply)",
             "cmd": ["python3", "tools/review/review.py", "apply", name], "builtin": True,
             "options": [{"flag": "--dry-run", "label": "Dry run", "type": "bool", "default": False,
                          "help": "Only list what would be copied"}]}]


def _is_int(v) -> bool:
    return isinstance(v, int) and not isinstance(v, bool)


def check_cmd(cmd) -> list[str]:
    """The declared cmd -> the argv prefix to run. Raises ReviewError when it isn't allowed."""
    if not isinstance(cmd, list) or len(cmd) < 2:
        raise ReviewError('cmd must be a list: ["python3", "<script inside the repo>", ...]')
    for c in cmd:
        if not isinstance(c, str) or not c or "\x00" in c:
            raise ReviewError("every cmd element must be a non-empty string")
    if cmd[0] != "python3":
        raise ReviewError('cmd[0] must be "python3"')
    rel = cmd[1]
    if os.path.isabs(rel) or rel.startswith("-"):
        raise ReviewError("cmd[1] must be a script path relative to the repo root")
    p = (REPO / rel).resolve()
    if REPO.resolve() not in p.parents or not p.is_file():
        raise ReviewError(f"cmd[1] {rel!r} is not a file inside the repo")
    return [sys.executable, str(p)] + cmd[2:]


def check_option(o) -> dict:
    if not isinstance(o, dict):
        raise ReviewError("each option must be an object")
    flag, typ = o.get("flag"), o.get("type")
    if not isinstance(flag, str) or not FLAG_RE.match(flag):
        raise ReviewError(f"option flag {flag!r} must look like --name")
    if typ not in OPTION_TYPES:
        raise ReviewError(f"option {flag}: type must be one of {', '.join(OPTION_TYPES)}")
    out = {"flag": flag, "type": typ, "label": str(o.get("label") or flag), "help": str(o.get("help") or "")}
    dflt = o.get("default")
    if typ == "bool":
        if dflt is not None and not isinstance(dflt, bool):
            raise ReviewError(f"option {flag}: default must be true or false")
        out["default"] = bool(dflt)
    elif typ == "int":
        for k in ("min", "max"):
            if o.get(k) is not None and not _is_int(o[k]):
                raise ReviewError(f"option {flag}: {k} must be an integer")
            out[k] = o.get(k)
        if dflt is not None and not _is_int(dflt):
            raise ReviewError(f"option {flag}: default must be an integer")
        if out["min"] is not None and out["max"] is not None and out["min"] > out["max"]:
            raise ReviewError(f"option {flag}: min is above max")
        out["default"] = dflt
        if dflt is not None:
            _check_int(out, dflt)
    elif typ == "string":
        if dflt is not None and not isinstance(dflt, str):
            raise ReviewError(f"option {flag}: default must be a string")
        out["default"] = dflt
    else:
        ch = o.get("choices")
        if (not isinstance(ch, list) or not ch
                or not all(isinstance(c, (str, int, float)) and not isinstance(c, bool) for c in ch)):
            raise ReviewError(f"option {flag}: choices must be a non-empty list of strings or numbers")
        if dflt is not None and dflt not in ch:
            raise ReviewError(f"option {flag}: default {dflt!r} is not one of the choices")
        out["choices"] = list(ch)
        out["default"] = dflt if dflt is not None else ch[0]
    return out


def _check_int(o: dict, v: int) -> None:
    if o.get("min") is not None and v < o["min"]:
        raise ReviewError(f"{o['flag']} must be at least {o['min']} (got {v})")
    if o.get("max") is not None and v > o["max"]:
        raise ReviewError(f"{o['flag']} must be at most {o['max']} (got {v})")


def check_action(a) -> dict:
    """A declared action, validated and normalised. Raises ReviewError with the reason."""
    if not isinstance(a, dict):
        raise ReviewError("each action must be an object")
    aid = a.get("id")
    if not isinstance(aid, str) or not ACTION_ID_RE.match(aid):
        raise ReviewError(f"action id {aid!r} must be a short name ([A-Za-z0-9_.-])")
    check_cmd(a.get("cmd"))
    opts = a.get("options") or []
    if not isinstance(opts, list):
        raise ReviewError("options must be a list")
    options = [check_option(o) for o in opts]
    flags = [o["flag"] for o in options]
    if len(set(flags)) != len(flags):
        raise ReviewError("an option flag is declared twice")
    kind = a.get("kind") or "custom"
    return {"id": aid, "kind": str(kind), "label": str(a.get("label") or aid), "help": str(a.get("help") or ""),
            "cmd": list(a["cmd"]), "options": options, "spends": a.get("spends") is True,
            "builtin": a.get("builtin") is True}


def batch_actions(name: str, data: dict) -> list[dict]:
    """The batch's actions, validated. An invalid one comes back with an "error" (and can't run);
    a batch that declares none gets the built-in install (this tool's `apply`)."""
    raw = data.get("actions")
    if raw is None or raw == []:
        raw = builtin_actions(name)
    if not isinstance(raw, list):
        return [{"id": "actions", "kind": "custom", "label": "actions", "help": "", "cmd": [], "options": [],
                 "spends": False, "builtin": False, "error": "batch.json: \"actions\" must be a list"}]
    out, seen = [], set()
    for i, a in enumerate(raw):
        try:
            act = check_action(a)
            if act["id"] in seen:
                raise ReviewError(f"action id {act['id']!r} is used twice")
            seen.add(act["id"])
        except ReviewError as e:
            aid = a.get("id") if isinstance(a, dict) and isinstance(a.get("id"), str) else f"action{i + 1}"
            label = a.get("label") if isinstance(a, dict) and isinstance(a.get("label"), str) else aid
            act = {"id": aid, "kind": str(a.get("kind") or "custom") if isinstance(a, dict) else "custom",
                   "label": label, "help": "", "cmd": [], "options": [], "spends": False, "builtin": False,
                   "error": str(e)}
        out.append(act)
    return out


def display_cmd(cmd: list[str], extra: list[str] = ()) -> str:
    return shlex.join(list(cmd) + list(extra))


def public_action(a: dict) -> dict:
    """What the UI needs to draw an action (never used to run one)."""
    out = {k: a.get(k) for k in ("id", "kind", "label", "help", "options", "spends", "builtin")}
    out["cmd"] = display_cmd(a["cmd"]) if a.get("cmd") else ""
    if a.get("error"):
        out["error"] = a["error"]
    return out


def build_argv(action: dict, options) -> tuple[list[str], list[str]]:
    """(argv to run, the option args as shown). Only declared options, each validated."""
    if action.get("error"):
        raise ReviewError(f"action {action['id']!r} can't run: {action['error']}")
    argv = check_cmd(action["cmd"])
    if options is None:
        options = {}
    if not isinstance(options, dict):
        raise ReviewError("options must be an object of {flag: value}")
    decl = {o["flag"]: o for o in action["options"]}
    for flag in options:
        if flag not in decl:
            raise ReviewError(f"unknown option {flag!r} for {action['id']}")
    extra: list[str] = []
    for o in action["options"]:
        flag = o["flag"]
        if flag not in options or options[flag] is None:
            continue  # not sent: the script's own default applies
        v, t = options[flag], o["type"]
        if t == "bool":
            if not isinstance(v, bool):
                raise ReviewError(f"{flag} must be true or false")
            if v:
                extra.append(flag)
        elif t == "int":
            if isinstance(v, str) and re.fullmatch(r"\s*-?\d{1,12}\s*", v):
                v = int(v)
            elif isinstance(v, float) and v.is_integer():
                v = int(v)
            if not _is_int(v):
                raise ReviewError(f"{flag} must be a whole number")
            _check_int(o, v)
            extra += [flag, str(v)]
        elif t == "string":
            if not isinstance(v, str):
                raise ReviewError(f"{flag} must be a string")
            if v == "":
                continue
            if len(v) > STRING_MAX or any(ord(c) < 32 or ord(c) == 127 for c in v):
                raise ReviewError(f"{flag}: at most {STRING_MAX} characters on one line")
            if v.startswith("-"):
                raise ReviewError(f"{flag}: the value may not start with '-'")
            extra += [flag, v]
        else:
            match = next((c for c in o["choices"] if c == v or str(c) == str(v)), None)
            if match is None or isinstance(v, (bool, list, dict)):
                raise ReviewError(f"{flag} must be one of: {', '.join(str(c) for c in o['choices'])}")
            extra += [flag, str(match)]
    return argv + extra, extra


# ---------------------------------------------------------------- runs

RUN_KEEP = 5            # finished runs remembered per batch
OUTPUT_KEEP = 2_000_000  # characters of output kept in memory per run (runs.log has it all)
KILL_GRACE = 3.0        # seconds between SIGTERM and SIGKILL on cancel


class Run:
    def __init__(self, batch: str, action: dict, argv: list[str], shown: str):
        self.id = secrets.token_hex(6)
        self.batch = batch
        self.action = action["id"]
        self.kind = action["kind"]
        self.label = action["label"]
        self.argv = argv
        self.cmd = shown
        self.started_at = datetime.now().isoformat(timespec="seconds")
        self.t0 = time.monotonic()
        self.t1: float | None = None
        self.status = "running"
        self.code: int | None = None
        self.cancel_requested = False
        self.proc: subprocess.Popen | None = None
        self.done = threading.Event()
        self._lock = threading.Lock()
        self._chunks: list[str] = []
        self._size = 0   # characters in _chunks
        self._base = 0   # characters dropped from the front

    def append(self, s: str) -> None:
        if not s:
            return
        with self._lock:
            self._chunks.append(s)
            self._size += len(s)
            while self._size > OUTPUT_KEEP and len(self._chunks) > 1:
                c = self._chunks.pop(0)
                self._size -= len(c)
                self._base += len(c)

    def read(self, frm: int) -> tuple[str, int, bool]:
        """(output from offset `frm`, the next offset, whether the start was dropped)."""
        with self._lock:
            end = self._base + self._size
            truncated = frm < self._base
            frm = min(max(frm, self._base), end)
            parts, pos = [], end
            for c in reversed(self._chunks):
                if pos <= frm:
                    break
                start = pos - len(c)
                parts.append(c[max(0, frm - start):])
                pos = start
            return "".join(reversed(parts)), end, truncated

    def elapsed(self) -> float:
        return (self.t1 if self.t1 is not None else time.monotonic()) - self.t0

    def info(self, frm: int | None = None) -> dict:
        out = {"id": self.id, "batch": self.batch, "action": self.action, "kind": self.kind,
               "label": self.label, "cmd": self.cmd, "status": self.status, "code": self.code,
               "started_at": self.started_at, "elapsed": round(self.elapsed(), 1),
               "log": f"review/{self.batch}/runs.log"}
        if frm is not None:
            text, nxt, truncated = self.read(frm)
            out.update(output=text, next=nxt, truncated=truncated)
        return out


_RUNS: dict[str, Run] = {}
_BATCH_RUNS: dict[str, list[str]] = {}
_RUNS_LOCK = threading.Lock()


def runs_for(name: str) -> list[Run]:
    """Newest first."""
    with _RUNS_LOCK:
        return [_RUNS[i] for i in reversed(_BATCH_RUNS.get(name, [])) if i in _RUNS]


def get_run(run_id: str) -> Run:
    run = _RUNS.get(run_id)
    if run is None:
        raise ReviewError(f"no run {run_id!r} (runs are kept in memory until the server restarts)", 404)
    return run


def _signal_run(run: Run, sig) -> None:
    p = run.proc
    if p is None or p.poll() is not None:
        return
    try:
        if os.name == "posix":
            os.killpg(p.pid, sig)  # the whole group: a script's own children (ludo.py, Godot) too
        elif sig == signal.SIGTERM:
            p.terminate()
        else:
            p.kill()
    except (ProcessLookupError, PermissionError, OSError):
        pass


def _open_log(d: Path):
    try:
        return open(d / "runs.log", "a", encoding="utf-8")
    except OSError:
        return None


def _pump(run: Run, logf) -> None:
    dec = codecs.getincrementaldecoder("utf-8")(errors="replace")
    fd = run.proc.stdout.fileno()

    def out(s: str) -> None:
        run.append(s)
        if logf:
            try:
                logf.write(s)
                logf.flush()
            except OSError:
                pass

    try:
        while True:
            try:
                b = os.read(fd, 65536)
            except OSError:
                b = b""
            if not b:
                break
            out(dec.decode(b))
        out(dec.decode(b"", final=True))
    finally:
        code = run.proc.wait()
        try:
            run.proc.stdout.close()
        except OSError:
            pass
        t1 = time.monotonic()
        status = "cancelled" if run.cancel_requested else ("ok" if code == 0 else "failed")
        out(f"\n[{status} · exit {code} · {t1 - run.t0:.1f}s]\n")  # before the status flips: a poll that
        run.code, run.t1 = code, t1                                  # sees it finished has all the output
        run.status = status
        if logf:
            try:
                logf.close()
            except OSError:
                pass
        run.done.set()


def start_run(name: str, action_id: str, options=None) -> Run:
    d, data = load_batch(name)
    action = next((a for a in batch_actions(name, data) if a["id"] == action_id), None)
    if action is None:
        raise ReviewError(f"no action {action_id!r} in {name}", 404)
    argv, extra = build_argv(action, options)
    shown = display_cmd(action["cmd"], extra)
    with _RUNS_LOCK:
        busy = next((_RUNS[i] for i in _BATCH_RUNS.get(name, []) if i in _RUNS and _RUNS[i].status == "running"), None)
        if busy is not None:
            raise ReviewError(f"“{busy.label}” is still running for {name}: wait for it or cancel it", 409)
        run = Run(name, action, argv, shown)
        ids = _BATCH_RUNS.setdefault(name, [])
        ids.append(run.id)
        _RUNS[run.id] = run
        while len(ids) > RUN_KEEP:
            _RUNS.pop(ids.pop(0), None)
        logf = _open_log(d)
        head = f"$ {shown}\n"
        if logf:
            logf.write(f"\n===== {run.started_at}  {name} · {run.label}  (run {run.id}) =====\n{head}")
            logf.flush()
        run.append(head)
        try:
            if action["kind"] == "regen":
                ## the generator re-rolls what rejected.json lists: make it match the verdicts now
                rj, n = write_rejected(name)
                msg = f"review: wrote {rj.relative_to(REPO)} ({n} to re-roll)\n"
                run.append(msg)
                if logf:
                    logf.write(msg)
            kw: dict = {"start_new_session": True} if os.name == "posix" else \
                {"creationflags": getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)}
            run.proc = subprocess.Popen(argv, cwd=str(REPO), stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                        stderr=subprocess.STDOUT, env=dict(os.environ, PYTHONUNBUFFERED="1"), **kw)
        except (OSError, ReviewError) as e:
            run.append(f"review: couldn't start it: {e}\n[failed]\n")
            run.status, run.t1 = "failed", time.monotonic()
            if logf:
                logf.write(f"review: couldn't start it: {e}\n[failed]\n")
                logf.close()
            run.done.set()
            return run
        threading.Thread(target=_pump, args=(run, logf), name=f"run-{run.id}", daemon=True).start()
    return run


def cancel_run(run_id: str) -> Run:
    run = get_run(run_id)
    if run.status != "running" or run.proc is None:
        return run
    run.cancel_requested = True
    _signal_run(run, signal.SIGTERM)
    kill = getattr(signal, "SIGKILL", signal.SIGTERM)
    t = threading.Timer(KILL_GRACE, lambda: run.status == "running" and _signal_run(run, kill))
    t.daemon = True
    t.start()
    return run


def cancel_all_runs() -> None:
    for run in list(_RUNS.values()):
        if run.status == "running":
            cancel_run(run.id)


# ---------------------------------------------------------------- server

class Handler(BaseHTTPRequestHandler):
    server_version = "ConcurrentReview/1.0"
    protocol_version = "HTTP/1.1"
    verbose = False

    def log_message(self, fmt, *args):
        if self.verbose:
            sys.stderr.write("[review] " + (fmt % args) + "\n")

    # -- helpers
    def _host_ok(self) -> bool:
        # Refuse requests addressed to any other host name (DNS-rebinding guard).
        host = (self.headers.get("Host") or "").strip().lower()
        if host.startswith("["):
            hostname = host[1:host.find("]")] if "]" in host else host
        else:
            hostname = host.rsplit(":", 1)[0] if ":" in host else host
        return hostname in ("127.0.0.1", "localhost", "::1", "")

    def _origin_ok(self) -> bool:
        # A page on another site can still POST here from the user's browser: refuse any
        # request that says it comes from somewhere other than this server's own page.
        origin = self.headers.get("Origin")
        if origin is None:
            return True
        port = self.server.server_address[1]
        return origin in (f"http://127.0.0.1:{port}", f"http://localhost:{port}", f"http://[::1]:{port}")

    def _token_ok(self) -> bool:
        got = (self.headers.get("X-Review-Token") or "").encode()
        return hmac.compare_digest(got, self.server.token.encode())

    def _send_bytes(self, status: int, body: bytes, ctype: str, extra: dict | None = None, head=False):
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if not head:
            self.wfile.write(body)

    def _json(self, status: int, obj, head=False):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self._send_bytes(status, body, "application/json; charset=utf-8", head=head)

    def _error(self, status: int, msg: str, head=False):
        self._json(status, {"error": msg}, head=head)

    def _send_file(self, path: Path, head=False):
        st = path.stat()
        size = st.st_size
        ctype = CONTENT_TYPES.get(path.suffix.lower(), "application/octet-stream")
        start, end, status = 0, size - 1, 200
        rng = self.headers.get("Range")
        if rng:
            m = re.fullmatch(r"\s*bytes=(\d*)-(\d*)\s*", rng)
            if m and (m.group(1) or m.group(2)):
                if m.group(1):
                    start = int(m.group(1))
                    end = min(int(m.group(2)), size - 1) if m.group(2) else size - 1
                else:
                    start, end = max(0, size - int(m.group(2))), size - 1
                if start >= size or start > end:
                    self.send_response(416)
                    self.send_header("Content-Range", f"bytes */{size}")
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                    return
                status = 206
            # multi-range / malformed: ignore it and send the whole file (RFC 9110 allows this)
        length = max(0, end - start + 1)
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(length))
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Last-Modified", self.date_time_string(st.st_mtime))
        if status == 206:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()
        if head or length == 0:
            return
        with open(path, "rb") as f:
            f.seek(start)
            remaining = length
            while remaining > 0:
                chunk = f.read(min(65536, remaining))
                if not chunk:
                    break
                self.wfile.write(chunk)
                remaining -= len(chunk)

    # -- routes
    def _route_get(self, head=False):
        if not self._host_ok():
            return self._error(403, "forbidden host", head)
        url = urlsplit(self.path)
        path = url.path
        if path in ("/", "/index.html"):
            try:
                html = INDEX_HTML.read_text(encoding="utf-8")
            except FileNotFoundError:
                return self._error(500, f"missing {INDEX_HTML}", head)
            body = html.replace(TOKEN_SLOT, self.server.token).encode("utf-8")
            return self._send_bytes(200, body, "text/html; charset=utf-8", head=head, extra={
                "X-Frame-Options": "DENY", "Content-Security-Policy": "frame-ancestors 'none'",
                "X-Content-Type-Options": "nosniff", "Referrer-Policy": "no-referrer"})
        if path == "/api/runs":
            name = (parse_qs(url.query).get("batch") or [""])[0]
            batch_dir(name)
            return self._json(200, {"runs": [r.info() for r in runs_for(name)]}, head)
        if path.startswith("/api/run/"):
            run = get_run(unquote(path[len("/api/run/"):]).strip("/"))
            try:
                frm = int((parse_qs(url.query).get("from") or ["0"])[0])
            except ValueError:
                raise ReviewError("from must be a number")
            return self._json(200, run.info(frm), head)
        if path == "/api/batches":
            out = []
            for name in list_batch_names():
                try:
                    mb = merged_batch(name)
                    out.append({"batch": name, "title": mb["title"], "counts": summarize(mb["items"])})
                except ReviewError as e:
                    out.append({"batch": name, "title": name, "error": str(e)})
            return self._json(200, {"batches": out, "root": str(REVIEW)}, head)
        if path.startswith("/api/batch/"):
            name = unquote(path[len("/api/batch/"):]).strip("/")
            return self._json(200, merged_batch(name), head)
        if path.startswith("/media/"):
            rest = path[len("/media/"):]
            name, _, rel = rest.partition("/")
            d = batch_dir(unquote(name))
            p = (d / unquote(rel)).resolve()
            if d.resolve() not in p.parents or not p.is_file():
                return self._error(404, "no such file", head)
            return self._send_file(p, head)
        if path == "/favicon.ico":
            return self._send_bytes(204, b"", "image/x-icon", head=head)
        return self._error(404, "not found", head)

    def _guard(self, fn, *a, **kw):
        try:
            fn(*a, **kw)
        except ReviewError as e:
            self._error(e.status, str(e))
        except _DROPPED:
            pass  # browsers drop media connections all the time
        except Exception as e:  # keep the server alive; report the failure
            sys.stderr.write(f"[review] error on {self.command} {self.path}: {e!r}\n")
            try:
                self._error(500, f"{type(e).__name__}: {e}")
            except Exception:
                pass

    def do_GET(self):
        self._guard(self._route_get)

    def do_HEAD(self):
        self._guard(self._route_get, head=True)

    def do_POST(self):
        self._guard(self._route_post)

    def _route_post(self):
        if not self._host_ok():
            return self._error(403, "forbidden host")
        path = urlsplit(self.path).path
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            return self._error(400, "bad Content-Length")
        if length > 1_000_000:
            return self._error(413, "request too large")
        raw = self.rfile.read(length) if length > 0 else b""
        m = re.fullmatch(r"/api/run/([0-9a-f]{1,32})/cancel", path)
        if path not in ("/api/decide", "/api/run") and not m:
            return self._error(404, "not found")
        # every POST changes state: it must come from this server's own page
        if not self._origin_ok():
            return self._error(403, "cross-origin request refused")
        if not self._token_ok():
            return self._error(403, "missing or stale X-Review-Token: reload the page")
        if "application/json" not in (self.headers.get("Content-Type") or ""):
            return self._error(415, "send application/json")
        try:
            body = json.loads(raw.decode("utf-8") or "{}")
        except (UnicodeDecodeError, json.JSONDecodeError):
            return self._error(400, "body is not JSON")
        if not isinstance(body, dict):
            return self._error(400, "body must be a JSON object")
        if m:
            return self._json(200, {"ok": True, "run": cancel_run(m.group(1)).info()})
        if path == "/api/run":
            if not isinstance(body.get("batch"), str) or not isinstance(body.get("action"), str):
                return self._error(400, "need {batch, action, options?}")
            run = start_run(body["batch"], body["action"], body.get("options"))
            return self._json(200, {"ok": True, "run": run.info()})
        if not body.get("batch") or not body.get("id"):
            return self._error(400, "need {batch, id, verdict?, note?, text?}")
        item = decide(str(body["batch"]), str(body["id"]),
                      verdict=body.get("verdict"), note=body.get("note"), text=body.get("text"))
        return self._json(200, {"ok": True, "item": item})


_DROPPED = (BrokenPipeError, ConnectionResetError, ConnectionAbortedError, TimeoutError)


class Server(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, *a, **kw):
        super().__init__(*a, **kw)
        # new each start: the served page carries it, every POST must echo it back
        self.token = secrets.token_urlsafe(24)

    def handle_error(self, request, client_address):
        # a browser closing an idle keep-alive or a half-read media stream is not an error
        if isinstance(sys.exc_info()[1], _DROPPED):
            return
        super().handle_error(request, client_address)


def cmd_serve(args) -> int:
    ensure_review_root()
    Handler.verbose = args.verbose
    try:
        httpd = Server(("127.0.0.1", args.port), Handler)
    except OSError as e:
        print(f"can't bind 127.0.0.1:{args.port}: {e} (another review server running? try --port)",
              file=sys.stderr)
        return 1
    url = f"http://127.0.0.1:{args.port}/"
    names = list_batch_names()
    print(f"review: serving {url}  ({len(names)} batch{'es' if len(names) != 1 else ''} in {REVIEW})")
    print("review: Ctrl+C to stop", flush=True)
    if args.open:
        threading.Timer(0.4, lambda: webbrowser.open(url)).start()
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nreview: stopped")
    finally:
        cancel_all_runs()  # don't leave a generator running with nobody watching it
        httpd.server_close()
    return 0


# ---------------------------------------------------------------- status / apply / new

def _table(rows: list[list], header: list[str]) -> str:
    widths = [max(len(str(r[i])) for r in [header] + rows) for i in range(len(header))]
    fmt = lambda r: "  ".join(str(c).ljust(widths[0]) if i == 0 else str(c).rjust(widths[i])
                              for i, c in enumerate(r))
    return "\n".join(["  " + fmt(header)] + ["  " + fmt(r) for r in rows])


def cmd_status(args) -> int:
    names = [args.batch] if args.batch else list_batch_names()
    if not names:
        print(f"no batches in {REVIEW}")
        return 0
    for name in names:
        mb = merged_batch(name)
        items = mb["items"]
        groups: dict[str, list] = {}
        for it in items:
            groups.setdefault(str(it.get("group") or "-"), []).append(it)
        header = ["group", "accepted", "rejected", "pending", "missing", "total"]
        rows = []
        for g in sorted(groups):
            c = summarize(groups[g])
            rows.append([g, c["accept"], c["reject"], c["pending"], c["missing"], c["total"]])
        c = summarize(items)
        if len(groups) > 1:
            rows.append(["(all)", c["accept"], c["reject"], c["pending"], c["missing"], c["total"]])
        print(f"{name} — {mb['title']}   {c['reviewed']}/{c['total']} reviewed")
        print(_table(rows, header))
        if c["regenerated"]:
            print(f"  {c['regenerated']} regenerated since their verdict (counted as pending: needs a listen)")
        print()
    return 0


def _repo_target(target: str) -> Path | None:
    if not target or not isinstance(target, str) or os.path.isabs(target):
        return None
    p = (REPO / target).resolve()
    return p if REPO.resolve() in p.parents else None


def cmd_apply(args) -> int:
    name = args.batch
    d, _ = load_batch(name)
    mb = merged_batch(name)
    dry = args.dry_run
    tag = "[dry-run] " if dry else ""
    copied = unchanged = skipped = 0
    warnings: list[str] = []
    for it in mb["items"]:
        if it["verdict"] == "accept" and it["status"] == "missing":
            warnings.append(f"{it['id']}: accepted but its file is missing — skipped")
            skipped += 1
            continue
        if it["status"] != "accept":
            continue
        src = item_path(d, it)
        dest = _repo_target(it.get("target"))
        if dest is None:
            warnings.append(f"{it['id']}: target {it.get('target')!r} is missing or outside the repo — skipped")
            skipped += 1
            continue
        if src.suffix.lower() != dest.suffix.lower():
            stale = dest if dest.exists() else None
            dest = dest.with_suffix(src.suffix)
            msg = (f"{it['id']}: target says {Path(it['target']).suffix} but the file is {src.suffix}; "
                   f"copying to {dest.relative_to(REPO)}")
            if stale:
                msg += f" (the old {stale.relative_to(REPO)} is still there)"
            warnings.append(msg)
        rel = dest.relative_to(REPO)
        if dest.exists() and filecmp.cmp(src, dest, shallow=False):
            unchanged += 1
            print(f"  {tag}=  {rel}  (unchanged)")
            continue
        verb = "overwrite" if dest.exists() else "new"
        print(f"  {tag}+  {rel}  ({verb})")
        if not dry:
            dest.parent.mkdir(parents=True, exist_ok=True)
            tmp = dest.with_name(f".{dest.name}.tmp")
            shutil.copy2(src, tmp)
            os.replace(tmp, dest)
        copied += 1

    rejected = rejected_entries(mb["items"])
    rj = d / "rejected.json"
    if not dry:
        atomic_write_json(rj, rejected)

    c = summarize(mb["items"])
    for w in warnings:
        print(f"  ! {w}")
    print(f"{tag}{name}: {'would copy' if dry else 'copied'} {copied}, unchanged {unchanged}, "
          f"skipped {skipped}  ·  {c['accept']} accepted, {c['reject']} rejected, "
          f"{c['pending']} pending, {c['missing']} missing")
    print(f"{tag}{'would write' if dry else 'wrote'} {rj.relative_to(REPO)} ({len(rejected)} to re-roll)")
    if c["regenerated"]:
        print(f"  {c['regenerated']} item(s) were regenerated after their verdict and were not applied: "
              "give them a listen first")
    return 0


def cmd_new(args) -> int:
    ensure_review_root()
    d = batch_dir(args.batch, must_exist=False)
    bj = d / "batch.json"
    if bj.exists():
        print(f"{bj.relative_to(REPO)} already exists", file=sys.stderr)
        return 1
    d.mkdir(parents=True, exist_ok=True)
    atomic_write_json(bj, {"batch": args.batch, "title": args.title or args.batch, "items": []})
    print(f"created {bj.relative_to(REPO)} — put media next to it and list them under \"items\"")
    return 0


# ---------------------------------------------------------------- sample batch

def _write_wav(path: Path, seconds: float, base_hz: float, seed: int) -> None:
    """A soft, speech-ish babble of tone syllables so durations are real."""
    rate = 22050
    n = int(seconds * rate)
    frames = bytearray()
    syl = 0.19  # syllable length (s)
    for i in range(n):
        t = i / rate
        k = int(t / syl)
        pos = (t % syl) / syl
        # every 5th syllable is a short pause, like a word gap
        on = ((k * 7 + seed) % 5) != 0
        env = math.sin(math.pi * pos) ** 1.5 if on else 0.0
        pitch = base_hz * (1 + 0.12 * math.sin(k * 1.7 + seed))
        s = math.sin(2 * math.pi * pitch * t) + 0.3 * math.sin(4 * math.pi * pitch * t)
        fade = min(1.0, t / 0.05, (seconds - t) / 0.08)
        v = int(max(-1, min(1, 0.28 * env * s * fade)) * 32767)
        frames += struct.pack("<h", v)
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(bytes(frames))


def _say_wav(path: Path, text: str, voice: str, rate: int, pad: float = 0.0) -> bool:
    """Real spoken words for the demo, from the Mac's own voices (say + afconvert). Returns
    False where those aren't available, and the caller falls back to tone babble."""
    say, conv = shutil.which("say"), shutil.which("afconvert")
    if not say or not conv:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".aiff")
    try:
        subprocess.run([say, "-v", voice, "-r", str(rate), "-o", str(tmp), text], check=True, capture_output=True)
        subprocess.run([conv, "-f", "WAVE", "-d", "LEI16@22050", str(tmp), str(path)], check=True, capture_output=True)
    except (subprocess.CalledProcessError, OSError):
        return False
    finally:
        if tmp.exists():
            tmp.unlink()
    if pad > 0:
        ## the deliberately-too-long take: trailing dead air, as a glitchy generation might have
        with wave.open(str(path), "rb") as r:
            params, frames = r.getparams(), r.readframes(r.getnframes())
        with wave.open(str(path), "wb") as w:
            w.setparams(params)
            w.writeframes(frames + b"\x00" * int(pad * params.framerate) * params.sampwidth * params.nchannels)
    return True


def _write_png(path: Path, size: int = 128) -> None:
    """A little crest: brass disc on navy, crimson band. Pure zlib/struct."""
    rows = []
    c = (size - 1) / 2
    for y in range(size):
        row = bytearray([0])  # filter: none
        for x in range(size):
            dx, dy = (x - c) / c, (y - c) / c
            r = math.hypot(dx, dy)
            if r < 0.78:
                col = (184, 65, 47) if abs(dy) < 0.16 else (217, 178, 95)
                if 0.70 < r:
                    col = (120, 92, 40)
            elif r < 0.86:
                col = (239, 230, 207)
            else:
                col = (15, 21, 34)
            row += bytes(col) + b"\xff"
        rows.append(bytes(row))
    raw = zlib.compress(b"".join(rows), 9)

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", raw) + chunk(b"IEND", b""))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)


def cmd_sample(args) -> int:
    ensure_review_root()
    d = REVIEW / "_sample"
    if (d / "batch.json").exists() and not args.force:
        print(f"{d.relative_to(REPO)} already exists (use --force to rebuild it; this clears its verdicts)")
        return 1
    if d.exists():
        shutil.rmtree(d)
    out = "review/_sample/out"
    items = [
        ("advisor.capture.v1", "audio", "advisor", "capture · variant 1", "Another land for the empire!",
         "advisor/capture_v1.wav", f"{out}/voice/advisor/capture_v1.mp3", 2.2, 220,
         {"voice": "voice_advisor", "context": "we took a land"}),
        ("advisor.loss.v1", "audio", "advisor", "loss · variant 1", "We have lost the river crossing, my lord.",
         "advisor/loss_v1.wav", f"{out}/voice/advisor/loss_v1.wav", 3.0, 200,
         {"voice": "voice_advisor", "context": "an enemy took one of our lands"}),
        ("advisor.victory.v1", "audio", "advisor", "victory · variant 1", "The empire endures. Glory to the crown!",
         "advisor/victory_v1.wav", f"{out}/voice/advisor/victory_v1.wav", 2.8, 240,
         {"voice": "voice_advisor", "context": "we won the match"}),
        ("varek.taunt.v1", "audio", "varek", "taunt · variant 1", "Your walls will not hold.",
         "varek/taunt_v1.wav", f"{out}/voice/varek/taunt_v1.wav", 9.0, 130,
         {"voice": "voice_varek", "context": "Varek attacks one of your forts"}),
        ("varek.defeat.v1", "audio", "varek", "defeat · variant 1", "This is not over.",
         "varek/defeat_v1.wav", f"{out}/voice/varek/defeat_v1.wav", None, 0,
         {"voice": "voice_varek", "context": "Varek is eliminated"}),
        ("hask.greet.v1", "audio", "hask", "greeting · variant 1",
         "The northern clans stand ready to march at your command.",
         "hask/greet_v1.wav", f"{out}/voice/hask/greet_v1.wav", 1.2, 160,
         {"voice": "voice_hask", "context": "Hask is chosen as an ally"}),
    ]
    ## spoken by the Mac's own voices where it has them: (voice, words per minute, dead air)
    speak = {"advisor.capture.v1": ("Daniel", 170, 0), "advisor.loss.v1": ("Daniel", 165, 0),
             "advisor.victory.v1": ("Daniel", 170, 0), "varek.taunt.v1": ("Daniel", 120, 6.5),
             "hask.greet.v1": ("Daniel", 520, 0)}
    batch_items = []
    for i, (iid, kind, group, label, text, f, target, secs, hz, meta) in enumerate(items):
        if secs:
            v = speak.get(iid)
            if not (v and _say_wav(d / f, text, v[0], v[1], v[2])):
                _write_wav(d / f, secs, hz, seed=i)
        batch_items.append({"id": iid, "kind": kind, "group": group, "label": label, "text": text,
                            "file": f, "target": target, "meta": meta})
    _write_png(d / "images" / "crest.png")
    batch_items.append({"id": "icon.crest.v1", "kind": "image", "group": "icons", "label": "crest · variant 1",
                        "text": "a brass imperial crest with a crimson band, flat, on navy",
                        "file": "images/crest.png", "target": f"{out}/icons/crest.png",
                        "meta": {"context": "HUD faction badge"}})
    horn = REPO / "assets" / "icons" / "horn.png"
    if horn.is_file():
        shutil.copy2(horn, d / "images" / "horn.png")
        batch_items.append({"id": "icon.horn.v1", "kind": "image", "group": "icons", "label": "horn · variant 1",
                            "text": "a brass war horn, painterly, transparent background",
                            "file": "images/horn.png", "target": f"{out}/icons/horn.png",
                            "meta": {"context": "the rally order button"}})
    atomic_write_json(d / "batch.json", {"batch": "_sample", "title": "Sample batch (demo)", "items": batch_items})
    print(f"built {d.relative_to(REPO)} with {len(batch_items)} items "
          "(one file deliberately missing, one line far too long, one too short)")
    return 0


# ---------------------------------------------------------------- main

def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="review.py", description="Accept/reject review for generated assets.")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("serve", help="serve the review UI on 127.0.0.1")
    p.add_argument("--port", type=int, default=8765)
    p.add_argument("--open", action="store_true", help="open the UI in your browser")
    p.add_argument("--verbose", action="store_true", help="log every request")
    p.set_defaults(fn=cmd_serve)
    p = sub.add_parser("status", help="counts per verdict per group")
    p.add_argument("batch", nargs="?")
    p.set_defaults(fn=cmd_status)
    p = sub.add_parser("apply", help="copy accepted files to their targets; write rejected.json")
    p.add_argument("batch")
    p.add_argument("--dry-run", action="store_true")
    p.set_defaults(fn=cmd_apply)
    p = sub.add_parser("new", help="scaffold an empty batch")
    p.add_argument("batch")
    p.add_argument("--title", default="")
    p.set_defaults(fn=cmd_new)
    p = sub.add_parser("sample", help="build the review/_sample demo batch")
    p.add_argument("--force", action="store_true")
    p.set_defaults(fn=cmd_sample)
    args = ap.parse_args(argv)
    try:
        return args.fn(args)
    except ReviewError as e:
        print(f"review: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
