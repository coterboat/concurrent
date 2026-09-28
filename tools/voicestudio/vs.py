#!/usr/bin/env python3
"""A small client for a local VoiceStudio (github.com/debpalash/VoiceStudio), the open-source
speech studio running k2-fsa's OmniVoice on this Mac. Free and local: no credits, no key.

    python3 tools/voicestudio/vs.py --health
    python3 tools/voicestudio/vs.py --say "Hold the line." --ref ref.wav --ref-text "…" --out take.wav

Start VoiceStudio first (its app, or `bun run dev` in its folder); it serves http://127.0.0.1:3900.
Stdlib only.
"""
import json
import os
import sys
import uuid
import urllib.error
import urllib.request

URL = os.environ.get("VOICESTUDIO_URL", "http://127.0.0.1:3900")


def health(timeout=5):
    """{"status": "ok", "device": …} or None if VoiceStudio isn't running."""
    try:
        with urllib.request.urlopen(URL + "/health", timeout=timeout) as r:
            return json.loads(r.read())
    except (urllib.error.URLError, OSError, ValueError):
        return None


def _multipart(fields, files):
    boundary = "----vs" + uuid.uuid4().hex
    out = []
    for k, v in fields.items():
        if v is None:
            continue
        out.append(("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n" % (boundary, k, v)).encode())
    for k, path in files.items():
        with open(path, "rb") as f:
            data = f.read()
        out.append(("--%s\r\nContent-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\nContent-Type: application/octet-stream\r\n\r\n"
                    % (boundary, k, os.path.basename(path))).encode() + data + b"\r\n")
    out.append(("--%s--\r\n" % boundary).encode())
    return b"".join(out), "multipart/form-data; boundary=" + boundary


def generate(text, out_path, ref_audio=None, ref_text=None, instruct=None, seed=None, speed=1.0,
             language="English", timeout=900, **extra):
    """Speak `text` into out_path (a WAV). With ref_audio + ref_text it clones that voice; with
    instruct ("male, elderly, low pitch, british accent") it designs one. Returns the response
    headers that matter: {seed, duration, gen_time}."""
    fields = {"text": text, "language": language, "ref_text": ref_text, "instruct": instruct,
              "seed": seed, "speed": speed}
    fields.update(extra)
    files = {"ref_audio": ref_audio} if ref_audio else {}
    body, ctype = _multipart(fields, files)
    req = urllib.request.Request(URL + "/generate", data=body, method="POST", headers={"Content-Type": ctype})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        data = r.read()
        h = r.headers
    tmp = out_path + ".part"
    with open(tmp, "wb") as f:
        f.write(data)
    os.replace(tmp, out_path)
    return {"seed": h.get("x-seed"), "duration": float(h.get("x-audio-duration") or 0), "gen_time": float(h.get("x-gen-time") or 0)}


if __name__ == "__main__":
    a = sys.argv
    if "--health" in a:
        print(health() or "VoiceStudio is not running at %s" % URL)
    elif "--say" in a:
        def opt(n, d=None):
            return a[a.index(n) + 1] if n in a else d
        print(generate(opt("--say"), opt("--out", "take.wav"), ref_audio=opt("--ref"), ref_text=opt("--ref-text"),
                       instruct=opt("--instruct"), seed=opt("--seed")))
    else:
        print(__doc__)
