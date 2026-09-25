#!/usr/bin/env python3
"""Generate CONCURRENT art + audio with the Ludo.ai API.

    python3 tools/ludo/ludo.py                 # everything missing in manifest.json
    python3 tools/ludo/ludo.py icon_attack     # just these ids (regenerates if --force)
    python3 tools/ludo/ludo.py --force id ...

Reads LUDO_API_KEY from the environment or .env.local. Idempotent: an asset whose
output file exists is skipped, and every job carries a stable request_id so a
retried submit returns the original job instead of charging twice.
Stdlib only. One worker per Ludo endpoint (the beta allows one in-flight job each).
"""
import json
import os
import sys
import threading
import time
import urllib.error
import urllib.request

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
API = "https://api.ludo.ai/api"
MANIFEST = os.path.join(os.path.dirname(__file__), "manifest.json")
LEDGER = os.path.join(ROOT, "assets", "ludo_ledger.json")
_ledger_lock = threading.Lock()
_print_lock = threading.Lock()


def log(*parts):
    with _print_lock:
        print(time.strftime("%H:%M:%S"), *parts, flush=True)


def api_key():
    key = os.environ.get("LUDO_API_KEY", "")
    if key:
        return key
    env = os.path.join(ROOT, ".env.local")
    if os.path.exists(env):
        for line in open(env):
            if line.startswith("LUDO_API_KEY="):
                return line.split("=", 1)[1].strip().strip('"')
    sys.exit("LUDO_API_KEY not set")


KEY = None


def call(method, path, body=None, timeout=90):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method)
    req.add_header("Authorization", "ApiKey " + KEY)
    req.add_header("Content-Type", "application/json")
    for attempt in range(6):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                raw = r.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            msg = e.read().decode(errors="replace")
            if e.code in (429, 500, 502, 503, 504) and attempt < 5:
                log("  retry", path, e.code, msg[:120])
                time.sleep(10 * (attempt + 1))
                continue
            raise RuntimeError("%s %s -> %s %s" % (method, path, e.code, msg[:400]))
        except (urllib.error.URLError, TimeoutError) as e:
            if attempt < 5:
                time.sleep(5 * (attempt + 1))
                continue
            raise


def run_job(endpoint, params, request_id):
    body = dict(params)
    body["request_id"] = request_id
    job = call("POST", endpoint, body)
    jid = job["id"]
    while True:
        status = job.get("status")
        if status == "succeeded":
            return job
        if status in ("failed", "canceled"):
            raise RuntimeError("job %s %s: %s" % (jid, status, job.get("error")))
        job = call("GET", "/assets/jobs/%s?wait=55" % jid, timeout=90)


def result_urls(result):
    if isinstance(result, list):
        return [r["url"] for r in result if isinstance(r, dict) and r.get("url")]
    if isinstance(result, dict):
        if result.get("url"):
            return [result["url"]]
        for k in ("results", "images", "audio"):
            if isinstance(result.get(k), list):
                return result_urls(result[k])
    return []


def download(url, dest):
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    tmp = dest + ".part"
    with urllib.request.urlopen(url, timeout=120) as r, open(tmp, "wb") as f:
        f.write(r.read())
    os.replace(tmp, dest)


def ext_of(url, fallback):
    tail = url.split("?")[0].rsplit(".", 1)
    return "." + tail[1].lower() if len(tail) == 2 and len(tail[1]) <= 4 else fallback


def sniff(path):
    """Ludo sometimes names a WAV '.mp3'. Trust the bytes, not the URL."""
    with open(path, "rb") as f:
        head = f.read(16)
    if head[:4] == b"RIFF" and head[8:12] == b"WAVE":
        return ".wav"
    if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
        return ".webp"
    if head[:8] == b"\x89PNG\r\n\x1a\n":
        return ".png"
    if head[:3] == b"ID3" or head[:2] in (b"\xff\xfb", b"\xff\xf3", b"\xff\xf2"):
        return ".mp3"
    if head[:4] == b"OggS":
        return ".ogg"
    return None


def record(entry):
    ## two generator runs may share the ledger: lock across processes too
    import fcntl
    with _ledger_lock, open(LEDGER + ".lock", "w") as lk:
        fcntl.flock(lk, fcntl.LOCK_EX)
        led = {}
        if os.path.exists(LEDGER):
            led = json.load(open(LEDGER))
        led[entry["id"]] = entry
        tmp = LEDGER + ".tmp"
        json.dump(led, open(tmp, "w"), indent=1, sort_keys=True)
        os.replace(tmp, LEDGER)


MANIFEST_V = {}


def ledger_url(aid, key="url", wait=2400):
    """URL a finished asset was served from; waits for another lane to finish the
    version this manifest asks for (a re-themed portrait must not edit its old self)."""
    t0 = time.time()
    need = MANIFEST_V.get(aid, 1)
    while True:
        with _ledger_lock:
            led = json.load(open(LEDGER)) if os.path.exists(LEDGER) else {}
        if aid in led and led[aid].get(key) and int(led[aid].get("v", 1)) >= need:
            return led[aid][key]
        if time.time() - t0 > wait:
            raise RuntimeError("dependency %s never finished" % aid)
        time.sleep(5)


def existing(out_base):
    d = os.path.dirname(out_base)
    b = os.path.basename(out_base)
    if not os.path.isdir(d):
        return None
    for f in os.listdir(d):
        if f.startswith(b + ".") and not f.endswith((".part", ".import", ".json")):
            return os.path.join(d, f)
    return None


def ledger_v(aid):
    with _ledger_lock:
        led = json.load(open(LEDGER)) if os.path.exists(LEDGER) else {}
    return int(led[aid].get("v", 1)) if aid in led else 0


def local_image(rel):
    """A local file as a base64 data URI (for inputs we prepared ourselves)."""
    import base64
    path = os.path.join(ROOT, rel)
    mime = "image/png" if path.endswith(".png") else "image/webp"
    return "data:%s;base64,%s" % (mime, base64.b64encode(open(path, "rb").read()).decode())


def source(asset, key="from"):
    if asset.get(key + "_file"):
        return local_image(asset[key + "_file"])
    return ledger_url(asset[key])


def build(asset, style, force):
    aid = asset["id"]
    out_base = os.path.join(ROOT, asset["out"])
    have = existing(out_base)
    ver = asset.get("v", 1)
    if have and not force and ledger_v(aid) >= ver:
        return
    kind = asset["kind"]
    rid = "concurrent-%s-v%s" % (aid, ver)
    t0 = time.time()
    extra = {}
    if kind == "edit":
        src = source(asset)
        params = {"image": src, "prompt": asset["prompt"], "n": 1, "augment_prompt": asset.get("augment", True)}
        job = run_job("/assets/image/edit", params, rid)
        url = result_urls(job["result"])[0]
        if asset.get("cutout"):
            cut = run_job("/assets/image/remove-background",
                          {"image": url, "crop": True, "creative_edit": False}, rid + "-cut")
            url = result_urls(cut["result"])[0]
        endpoint = "/assets/image/edit"
    elif kind == "animate":
        src = source(asset)
        params = {"initial_image": src, "motion_prompt": asset["prompt"], "model": asset.get("model", "forge"),
                  "duration": asset.get("duration", 2), "frames": asset.get("frames", 16),
                  "frame_size": asset.get("frame_size", 128), "loop": asset.get("loop", False),
                  "image_type": asset.get("image_type", "sprite")}
        if asset.get("final_same"):
            params["final_image"] = src  ## the loop ends where it began: no reset jump
        elif asset.get("final") or asset.get("final_file"):
            params["final_image"] = source(asset, "final")  ## ends on a known pose
        for k in ("crop", "margin_ratio_mode"):
            if k in asset:
                params[k] = asset[k]
        if asset.get("with_background"):
            params["spritesheet_with_background"] = True
        job = run_job("/assets/sprite/animate", params, rid)
        res = job["result"]
        url = res.get("spritesheet_with_background_url") if asset.get("with_background") and res.get("spritesheet_with_background_url") else res["spritesheet_url"]
        extra = {"cols": res.get("num_cols"), "rows": res.get("num_rows"), "frames": res.get("num_frames")}
        endpoint = "/assets/sprite/animate"
    elif kind == "voice":
        params = {"voice_description": asset["describe"], "text": asset["text"], "type": "human",
                  "augment_prompt": asset.get("augment", True)}
        job = run_job("/audio/voice", params, rid)
        url = result_urls(job["result"])[0]
        endpoint = "/audio/voice"
    elif kind == "speech":
        sample = ledger_url(asset["voice"])
        params = {"text": asset["text"], "sample": sample}
        job = run_job("/audio/speech", params, rid)
        url = result_urls(job["result"])[0]
        endpoint = "/audio/speech"
    elif kind == "styled":
        params = {"style_image": ledger_url(asset["style_from"]), "prompt": asset["prompt"],
                  "image_type": asset.get("type", "art"), "n": 1, "augment_prompt": asset.get("augment", True)}
        job = run_job("/assets/image/style", params, rid)
        url = result_urls(job["result"])[0]
        if asset.get("cutout"):
            cut = run_job("/assets/image/remove-background",
                          {"image": url, "crop": True, "creative_edit": False}, rid + "-cut")
            url = result_urls(cut["result"])[0]
        endpoint = "/assets/image/style"
    elif kind == "image":
        prompt = asset["prompt"]
        if asset.get("style", True):
            prompt = prompt + ". " + style["image"]
        params = {
            "image_type": asset.get("type", "art"),
            "prompt": prompt,
            "art_style": asset.get("art_style", style["art_style"]),
            "perspective": asset.get("perspective", "Any perspective"),
            "aspect_ratio": asset.get("aspect", "ar_1_1"),
            "n": 1,
            "augment_prompt": asset.get("augment", True),
        }
        job = run_job("/assets/image", params, rid)
        url = result_urls(job["result"])[0]
        if asset.get("cutout"):
            cut = run_job("/assets/image/remove-background",
                          {"image": url, "crop": True, "creative_edit": False}, rid + "-cut")
            url = result_urls(cut["result"])[0]
        endpoint = "/assets/image"
    elif kind in ("sfx", "music", "ambiance"):
        endpoint = {"sfx": "/audio/sound-effect", "music": "/audio/music", "ambiance": "/audio/ambiance"}[kind]
        params = {"description": asset["prompt"], "augment_prompt": asset.get("augment", True)}
        if "duration" in asset:
            params["duration"] = asset["duration"]
        if kind == "sfx":
            params["loop"] = asset.get("loop", False)
        job = run_job(endpoint, params, rid)
        url = result_urls(job["result"])[0]
    dest = out_base + ext_of(url, ".bin")
    if have and have != dest:
        os.remove(have)
    download(url, dest)
    real = sniff(dest)
    if real and not dest.endswith(real):
        fixed = out_base + real
        os.replace(dest, fixed)
        dest = fixed
    if extra:
        json.dump(extra, open(out_base + ".json", "w"))
    params = {k: (v[:40] + "...(base64)" if isinstance(v, str) and v.startswith("data:") else v) for k, v in params.items()}
    record({"id": aid, "v": ver, "endpoint": endpoint, "params": params, "job": job.get("id"),
            "credits": job.get("credits_charged"), "url": url, "file": os.path.relpath(dest, ROOT)})
    log("done %-22s %5.0fs  %s" % (aid, time.time() - t0, os.path.relpath(dest, ROOT)))


def worker(queue, style, force, failures):
    for asset in queue:
        try:
            build(asset, style, force)
        except Exception as e:  # keep the rest of the queue moving
            failures.append((asset["id"], str(e)))
            log("FAIL", asset["id"], str(e)[:300])


def main(argv):
    global KEY
    KEY = api_key()
    force = "--force" in argv
    wanted = [a for a in argv if not a.startswith("--")]
    man = json.load(open(MANIFEST))
    for a in man["assets"]:
        MANIFEST_V[a["id"]] = int(a.get("v", 1))
    style = man["style"]
    assets = man["assets"]
    if wanted:
        assets = [a for a in assets if a["id"] in wanted]
    lanes = {}
    lane_of = {"ambiance": "sfx"}
    for a in assets:
        lanes.setdefault(lane_of.get(a["kind"], a["kind"]), []).append(a)
    failures = []
    threads = [threading.Thread(target=worker, args=(q, style, force, failures)) for q in lanes.values()]
    log("lanes:", {k: len(v) for k, v in lanes.items()})
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    if failures:
        log("FAILED:", failures)
        sys.exit(1)
    log("all assets present")


if __name__ == "__main__":
    main(sys.argv[1:])
