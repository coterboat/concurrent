#!/usr/bin/env python3
"""Review notes -> the next take (v1.11).

A reviewer's note ("more pause between sentences", "the rifle snaps 180 degrees in one frame")
is the most precise prompt we will ever get. Before v1.11 a redo ignored it and simply rolled
again. Now every redo reads it:

- A voice line keeps its words (they are the subtitle). The note becomes performance marks in
  what the voice is asked to say (the manifest's `speak`): pauses, *stress*, how a sentence ends.
- A picture, animation or film gets its prompt rewritten so the next roll does what the note asks.

Claude does the rewriting when the `claude` command is installed (`claude -p`, one call per redo
run, on the owner's Claude plan), guided by docs/PROMPTING.md. Without it, simple rules apply the
voice lessons and the note is appended to a picture's prompt as a direction.

    python3 tools/ludo/notes.py --try "Here come the surges. Steady now." "more pause"   # dry run
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PROMPTING = os.path.join(ROOT, "docs", "PROMPTING.md")
sys.path.insert(0, os.path.join(ROOT, "tools", "review"))
import review  # noqa: E402  (note_themes: the same themes the review table counts)

## The marks the speech lab found the cloned voices respond to (docs/PROMPTING.md, "Voices").
PAUSE = "... "      ## between two sentences, when a note asks for more pause
STRESS = "*%s*"     ## a stressed word


def themes(note, kind="audio"):
    return review.note_themes(note or "", kind)


def meaningful(note, kind="audio"):
    """A note worth steering by: not empty, not just "redo", not just praise."""
    t = set(themes(note, kind))
    return bool(note and note.strip()) and not t <= {"redo", "praise"}


def words(s):
    """The words of a line, ignoring punctuation, marks and case: a rewrite must keep them."""
    return re.findall(r"[a-z0-9']+", (s or "").lower().replace("’", "'"))


def section(title):
    """One '## ' section of docs/PROMPTING.md (the playbook the rewriter follows)."""
    try:
        text = open(PROMPTING, encoding="utf-8").read()
    except OSError:
        return ""
    m = re.search(r"^## %s.*?(?=^## |\Z)" % re.escape(title), text, re.M | re.S)
    return m.group(0).strip() if m else ""


## ------------------------------------------------------------------ rules (no Claude needed)
def quoted_words(note):
    """Words a note wants stressed: 'Strike', "my", *always*, inTERest."""
    out = re.findall(r"[\"'‘’“”*]([A-Za-z][A-Za-z'-]*)[\"'‘’“”*]", note or "")
    out += [w for w in re.findall(r"\b([a-z]*[A-Z]{2,}[a-z]+|[a-z]+[A-Z]{2,}[a-z]*)\b", note or "")]
    return [w for w in out if len(w) > 1]


def speak_rules(text, note):
    """The voice lessons as plain text edits (the fallback when Claude is not available)."""
    t = set(themes(note, "audio"))
    s = text
    if "pause" in t:
        ## the gap between two sentences: "A. B" -> "A... B" (a "!" or "?" gap stays as it is)
        s = re.sub(r"(?<![.!?])\.(\s+)(?=[A-Z*\"'‘“])", PAUSE.rstrip() + r"\1", s)
    if "fall" in t and not re.search(r"shout|yell|scream", note, re.I):
        s = re.sub(r"!", ".", s)  ## a falling end is a full stop, not an exclamation
    if t & {"stress", "feeling"}:
        for w in quoted_words(note):
            rx = re.compile(r"(?<![*\w])(%s)(?![*\w])" % re.escape(w.strip("*")), re.I)
            s = rx.sub(lambda m: STRESS % m.group(1), s, count=1)
    return s


def prompt_rules(prompt, note):
    """A note appended to a prompt as a direction (the fallback when Claude is not available)."""
    n = re.sub(r"^\s*(very close|close|almost|nearly|good|great)[,.!-]*\s*(but)?\s*", "", note.strip(), flags=re.I)
    n = re.sub(r"^\s*(this is|it's|its)\s+(very\s+)?close[,.]?\s*(but)?\s*", "", n, flags=re.I)
    n = n[:1].upper() + n[1:] if n else n
    return prompt.rstrip(". ") + ". Direction for this take: " + n.rstrip(".") + "."


## ------------------------------------------------------------------ Claude
def claude_bin():
    if os.environ.get("CONCURRENT_NO_CLAUDE"):
        return None
    return shutil.which("claude") or next((p for p in (os.path.expanduser("~/.local/bin/claude"),) if os.path.exists(p)), None)


def claude_json(prompt, timeout=300):
    """One `claude -p` call, no tools, that answers with a JSON object. None if it can't."""
    exe = claude_bin()
    if not exe or os.environ.get("CONCURRENT_NO_CLAUDE"):
        return None
    try:
        r = subprocess.run([exe, "-p", "--output-format", "json", "--max-turns", "1", "--tools", ""],
                           input=prompt, capture_output=True, text=True, timeout=timeout,
                           cwd=tempfile.gettempdir())
    except (OSError, subprocess.TimeoutExpired) as e:
        print("  notes: claude didn't answer (%s); using the plain rules" % type(e).__name__)
        return None
    try:
        outer = json.loads(r.stdout)
        text = outer.get("result", "") if isinstance(outer, dict) else ""
        if isinstance(outer, dict) and outer.get("is_error"):
            raise ValueError(text[:200])
        m = re.search(r"\{.*\}", text, re.S)
        return json.loads(m.group(0)) if m else None
    except (ValueError, json.JSONDecodeError) as e:
        print("  notes: couldn't read claude's answer (%s); using the plain rules" % str(e)[:120])
        return None


SPEECH_ASK = """You direct voice actors for a Napoleonic strategy game. Each line below was generated
by a voice-cloning text-to-speech model and REJECTED by the game's owner, with a note. The model's
only inputs are the text and a voice sample, so the only way to change the delivery is the text:
punctuation, pauses, stress marks and capitals. Rewrite each line's SPOKEN text so the next take
does what the note asks.

Rules (measured on this model, see the playbook):
- Keep every word, in order. Never add, drop or change a word (the words are the subtitle).
- A pause between sentences: "..." (A... B.). It is the only mark that works. Dashes, blank lines,
  SSML <break> tags and [pause] do nothing or get READ ALOUD: never use them.
- A falling end can't be written: keep the full stop. Never add "!" or a trailing "..." unless the
  note asks for a shout; both raise the voice. The redo measures its takes for the falling end.
- Stress: *stars* or CAPITALS are allowed (the subtitle drops the stars) but barely move the voice.
- If the note asks for nothing the text can do (pitch, feeling, "redo"), return the text unchanged:
  the redo rolls several takes and measures them instead.

PLAYBOOK
{playbook}

LINES (JSON)
{items}

Answer with JSON only: {{"<id>": {{"speak": "<the spoken text>", "why": "<a few words>"}}, ...}}"""

PROMPT_ASK = """You write prompts for image, animation and video generators for a Napoleonic strategy
game. Each item below was generated from its PROMPT and REJECTED by the game's owner with a NOTE.
Rewrite each prompt so the next roll fixes what the note says and keeps everything that was right.

Rules:
- Keep the subject, style, framing and every detail the note doesn't touch.
- Say what should be seen, positively and concretely; generators often draw what a "no X" mentions.
- For motion (animation, video), describe the movement through the whole clip, including how it ends.
- Keep it about as long as the original. No markdown.
- Follow the playbook below.

PLAYBOOK
{playbook}

ITEMS (JSON)
{items}

Answer with JSON only: {{"<id>": {{"prompt": "<the new prompt>", "why": "<a few words>"}}, ...}}"""


def rewrite_speech(items):
    """items: [{id, text, note, speak?, who?, context?}] -> {id: (spoken text, why, by)}.
    Only items whose note asks for something; each result keeps the words of `text`."""
    todo = [it for it in items if meaningful(it.get("note"))]
    out = {}
    if not todo:
        return out
    ask = SPEECH_ASK.format(playbook=section("Voices") or "(none yet)", items=json.dumps(
        [{"id": it["id"], "character": it.get("who", ""), "text": it.get("speak") or it["text"],
          "note": it["note"], "when it plays": it.get("context", "")} for it in todo], ensure_ascii=False, indent=1))
    got = claude_json(ask) or {}
    for it in todo:
        r = got.get(it["id"]) if isinstance(got, dict) else None
        cand = r.get("speak") if isinstance(r, dict) else None
        if isinstance(cand, str) and cand.strip() and words(cand) == words(it["text"]):
            out[it["id"]] = (cand.strip(), str(r.get("why", ""))[:120], "claude")
        else:
            if cand:
                print("  notes: %s: claude changed the words; using the plain rules" % it["id"])
            out[it["id"]] = (speak_rules(it.get("speak") or it["text"], it["note"]), "rules: " + ", ".join(themes(it["note"])), "rules")
    return out


def rewrite_prompts(items):
    """items: [{id, kind, prompt, note}] -> {id: (new prompt, why, by)} for notes that ask something."""
    todo = [it for it in items if it.get("prompt") and meaningful(it.get("note"), it.get("kind", "image"))]
    out = {}
    if not todo:
        return out
    ask = PROMPT_ASK.format(playbook=section("Pictures, animation and film") or "(none yet)", items=json.dumps(
        [{"id": it["id"], "kind": it.get("kind", "image"), "prompt": it["prompt"], "note": it["note"]} for it in todo],
        ensure_ascii=False, indent=1))
    got = claude_json(ask) or {}
    for it in todo:
        r = got.get(it["id"]) if isinstance(got, dict) else None
        cand = r.get("prompt") if isinstance(r, dict) else None
        if isinstance(cand, str) and 20 <= len(cand.strip()) <= 4000:
            out[it["id"]] = (cand.strip(), str(r.get("why", ""))[:120], "claude")
        else:
            out[it["id"]] = (prompt_rules(it["prompt"], it["note"]), "the note, appended", "rules")
    return out


if __name__ == "__main__":
    if "--try" in sys.argv:
        i = sys.argv.index("--try")
        text, note = sys.argv[i + 1], sys.argv[i + 2]
        print("themes:", themes(note))
        print("rules :", speak_rules(text, note))
        if "--claude" in sys.argv:
            print("claude:", rewrite_speech([{"id": "x", "text": text, "note": note}]).get("x"))
    else:
        print(__doc__)
