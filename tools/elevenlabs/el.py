#!/usr/bin/env python3
"""A small client for the ElevenLabs API (https://api.elevenlabs.io). Stdlib only.

The key is ELEVENLABS_API_KEY (or ELEVEN_LABS_API_KEY), from the environment or .env.local (like
LUDO_API_KEY). It's sent
as the xi-api-key header and never printed or logged.

    python3 tools/elevenlabs/el.py --account    # the plan, credits left, voice slots, and whether v4 is there
"""
import base64
import json
import os
import sys
import urllib.error
import urllib.request
import uuid

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
API = "https://api.elevenlabs.io"
V4 = "eleven_v4"
DESIGN_MODEL = "eleven_ttv_v3"
PRICE_PER_1K = 0.08 ## USD per 1,000 characters, v4 on the API (Sep 2026; $0.022 on sale to 12 Oct)


NAMES = ("ELEVENLABS_API_KEY", "ELEVEN_LABS_API_KEY")


def key():
    for n in NAMES:
        if os.environ.get(n):
            return os.environ[n]
    env = os.path.join(ROOT, ".env.local")
    if os.path.exists(env):
        for line in open(env):
            line = line.strip()
            if line.startswith("export "):
                line = line[7:]
            for n in NAMES:
                ## v2.3: KEY=value, or KEY: value (how the Windows PC's file is written)
                for sep in ("=", ":"):
                    if line.startswith(n + sep):
                        return line.split(sep, 1)[1].strip().strip('"').strip("'")
    return ""


class Error(Exception):
    pass


def _call(method, path, body=None, ctype=None, accept="application/json", timeout=300):
    k = key()
    if not k:
        raise Error("ELEVENLABS_API_KEY isn't set: add a line ELEVENLABS_API_KEY=… to .env.local")
    headers = {"xi-api-key": k, "Accept": accept}
    if ctype:
        headers["Content-Type"] = ctype
    req = urllib.request.Request(API + path, data=body, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.read()
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")[:400]
        raise Error("%s %s: HTTP %d %s" % (method, path.split("?")[0], e.code, detail))


def get(path):
    return json.loads(_call("GET", path))


def post_json(path, payload, accept="application/json"):
    raw = _call("POST", path, json.dumps(payload).encode(), "application/json", accept)
    return raw if accept != "application/json" else json.loads(raw)


def account():
    """{tier, used, limit, left, voices_used, voice_limit, can_clone}"""
    s = get("/v1/user/subscription")
    used, limit = int(s.get("character_count", 0)), int(s.get("character_limit", 0))
    return {"tier": s.get("tier", "?"), "used": used, "limit": limit, "left": limit - used,
            "voices_used": s.get("voice_slots_used", s.get("voice_count")), "voice_limit": s.get("voice_limit"),
            "can_clone": s.get("can_use_instant_voice_cloning", True)}


def account_or_none():
    """account(), or None (with a note) when the key may not read the account (no user_read):
    the run goes on without its credit check"""
    try:
        return account()
    except Error as e:
        if "missing the permission" not in str(e):
            raise
        print("elevenlabs: this key can't read the account (user_read), so there's no credit check before spending")
        return None


def models():
    return {m["model_id"]: m for m in get("/v1/models")}


def clone(name, files, description=""):
    """An instant voice clone from local audio files -> voice_id"""
    boundary = "----el" + uuid.uuid4().hex
    parts = []
    for k, v in (("name", name), ("description", description), ("remove_background_noise", "false")):
        parts.append(("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n" % (boundary, k, v)).encode())
    for p in files:
        with open(p, "rb") as f:
            data = f.read()
        parts.append(("--%s\r\nContent-Disposition: form-data; name=\"files\"; filename=\"%s\"\r\nContent-Type: audio/mpeg\r\n\r\n"
                      % (boundary, os.path.basename(p))).encode() + data + b"\r\n")
    parts.append(("--%s--\r\n" % boundary).encode())
    out = json.loads(_call("POST", "/v1/voices/add", b"".join(parts), "multipart/form-data; boundary=" + boundary))
    return out["voice_id"]


def design(description, text, seed=None):
    """Voice design: 3 previews of a voice made from a description, speaking `text` (100-1000 chars).
    -> [(generated_voice_id, mp3 bytes)]"""
    payload = {"voice_description": description, "text": text, "model_id": DESIGN_MODEL}
    if seed is not None:
        payload["seed"] = seed
    out = post_json("/v1/text-to-voice/design", payload)
    return [(p["generated_voice_id"], base64.b64decode(p["audio_base_64"])) for p in out.get("previews", [])]


def save_design(name, description, generated_voice_id):
    return post_json("/v1/text-to-voice", {"voice_name": name, "voice_description": description,
                                           "generated_voice_id": generated_voice_id})["voice_id"]


def speak(voice_id, text, seed=None, model=V4):
    """mp3 bytes (44.1 kHz). Tries text-to-speech; if the model only speaks through text-to-dialogue,
    uses that with a single speaker."""
    q = "?output_format=mp3_44100_128"
    body = {"text": text, "model_id": model}
    if seed is not None:
        body["seed"] = seed
    try:
        return post_json("/v1/text-to-speech/%s%s" % (voice_id, q), body, accept="audio/mpeg")
    except Error as e:
        if "model" not in str(e).lower():
            raise
        dbody = {"inputs": [{"text": text, "voice_id": voice_id}], "model_id": model}
        if seed is not None:
            dbody["seed"] = seed
        return post_json("/v1/text-to-dialogue" + q, dbody, accept="audio/mpeg")


def sound_effect(text, seconds=None, influence=0.5):
    """mp3 bytes (44.1 kHz) of a sound effect described by `text` (0.5-30 s; None lets it choose)"""
    body = {"text": text, "prompt_influence": influence}
    if seconds:
        body["duration_seconds"] = max(0.5, min(30.0, float(seconds)))
    return post_json("/v1/sound-generation?output_format=mp3_44100_128", body, accept="audio/mpeg")


def delete_voice(voice_id):
    _call("DELETE", "/v1/voices/%s" % voice_id)


if __name__ == "__main__":
    if "--account" in sys.argv:
        try:
            a = account()
            m = models()
        except Error as e:
            sys.exit("elevenlabs: %s" % e)
        print("plan %s: %d of %d credits used (%d left); voices %s of %s; instant cloning: %s"
              % (a["tier"], a["used"], a["limit"], a["left"], a["voices_used"], a["voice_limit"], a["can_clone"]))
        print("v4 (%s): %s" % (V4, "available" + (", speaks text-to-speech" if m.get(V4, {}).get("can_do_text_to_speech") else "")
                               if V4 in m else "NOT listed for this key (models: %s)" % ", ".join(sorted(m))))
    else:
        print(__doc__)
