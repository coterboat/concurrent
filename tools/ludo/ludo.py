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
    with _ledger_lock:
        led = {}
        if os.path.exists(LEDGER):
            led = json.load(open(LEDGER))
        led[entry["id"]] = entry
        json.dump(led, open(LEDGER, "w"), indent=1, sort_keys=True)


def existing(out_base):
    d = os.path.dirname(out_base)
    b = os.path.basename(out_base)
    if not os.path.isdir(d):
        return None
    for f in os.listdir(d):
        if f.startswith(b + ".") and not f.endswith(".part") and not f.endswith(".import"):
            return os.path.join(d, f)
    return None


def build(asset, style, force):
    aid = asset["id"]
    out_base = os.path.join(ROOT, asset["out"])
    have = existing(out_base)
    if have and not force:
        return
    kind = asset["kind"]
    ver = asset.get("v", 1)
    rid = "concurrent-%s-v%s" % (aid, ver)
    t0 = time.time()
    if kind == "image":
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
    else:
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
    record({"id": aid, "endpoint": endpoint, "params": params, "job": job.get("id"),
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
    style = man["style"]
    assets = man["assets"]
    if wanted:
        assets = [a for a in assets if a["id"] in wanted]
    lanes = {}
    for a in assets:
        lanes.setdefault(a["kind"] if a["kind"] != "ambiance" else "sfx", []).append(a)
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
