#!/usr/bin/env python3
"""Slim a Ludo GLB for the repo: its PNG textures re-encoded as JPEG (a 1024 colour map goes from
about 1.5 MB to 200 KB), everything else byte for byte. Godot reads JPEG in a GLB as it reads PNG.

    python3 tools/ludo/glb_slim.py in.glb out.glb [--q 3]

The import that goes with it (write_import) embeds the textures in Godot's own import, compressed
for the GPU, instead of extracting PNG copies next to the model (which the repo would carry twice).
Stdlib plus ffmpeg.
"""
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile

FF = shutil.which("ffmpeg") or "/opt/homebrew/opt/ffmpeg-full/bin/ffmpeg"


def _pad(b, fill=b"\x00"):
    return b + fill * ((4 - len(b) % 4) % 4)


def read_glb(path):
    data = open(path, "rb").read()
    magic, _ver, _length = struct.unpack("<III", data[:12])
    if magic != 0x46546C67:
        raise ValueError("not a GLB: " + path)
    off = 12
    js, binc = None, b""
    while off < len(data):
        clen, ctype = struct.unpack("<II", data[off:off + 8])
        chunk = data[off + 8:off + 8 + clen]
        if ctype == 0x4E4F534A:
            js = json.loads(chunk)
        elif ctype == 0x004E4942:
            binc = chunk
        off += 8 + clen
    return js, binc


def write_glb(path, js, binc):
    jb = _pad(json.dumps(js, separators=(",", ":")).encode(), b" ")
    bb = _pad(binc)
    total = 12 + 8 + len(jb) + 8 + len(bb)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(jb), 0x4E4F534A))
        f.write(jb)
        f.write(struct.pack("<II", len(bb), 0x004E4942))
        f.write(bb)


def _to_jpeg(data, q, max_size=0, ext="png"):
    with tempfile.TemporaryDirectory() as d:
        src = os.path.join(d, "in." + ext)
        dst = os.path.join(d, "out.jpg")
        open(src, "wb").write(data)
        vf = ["-vf", "scale='min(%d,iw)':-2" % max_size] if max_size else []
        subprocess.run([FF, "-y", "-loglevel", "fatal", "-i", src, *vf, "-q:v", str(q), dst], check=True)
        return open(dst, "rb").read()


def slim(src, dst, q=3, max_size=0):
    """Every PNG texture to JPEG; with max_size, every texture (JPEG too) no wider than that."""
    js, binc = read_glb(src)
    views = js.get("bufferViews", [])
    images = js.get("images", [])
    swap = {}
    for img in images:
        mime = img.get("mimeType")
        if "bufferView" not in img or mime not in ("image/png", "image/jpeg"):
            continue
        if mime == "image/jpeg" and not max_size:
            continue
        v = views[img["bufferView"]]
        start = v.get("byteOffset", 0)
        swap[img["bufferView"]] = _to_jpeg(binc[start:start + v["byteLength"]], q, max_size,
                                           "png" if mime == "image/png" else "jpg")
        img["mimeType"] = "image/jpeg"
    ## rebuild the binary chunk view by view, every view on a 4-byte boundary
    out = bytearray()
    for i, v in enumerate(views):
        start = v.get("byteOffset", 0)
        piece = swap.get(i, binc[start:start + v["byteLength"]])
        while len(out) % 4:
            out.append(0)
        v["byteOffset"] = len(out)
        v["byteLength"] = len(piece)
        out += piece
    if js.get("buffers"):
        js["buffers"][0]["byteLength"] = len(out)
    write_glb(dst, js, bytes(out))
    return os.path.getsize(src), os.path.getsize(dst)


IMPORT = """[remap]

importer="scene"
importer_version=1
type="PackedScene"

[deps]

source_file="res://{res}"

[params]

nodes/root_type=""
nodes/root_name=""
nodes/apply_root_scale=true
nodes/root_scale=1.0
meshes/ensure_tangents=true
meshes/generate_lods=true
meshes/create_shadow_meshes=true
meshes/light_baking=1
animation/import=false
materials/extract=0
gltf/naming_version=2
gltf/embedded_image_handling=2
"""


def write_import(res_path, root):
    """A .import beside the model that embeds its textures (GPU-compressed) rather than extracting them."""
    open(os.path.join(root, res_path + ".import"), "w").write(IMPORT.format(res=res_path))


if __name__ == "__main__":
    a = sys.argv[1:]
    opts = {"--q": 3, "--max": 0}
    for k in opts:
        if k in a:
            i = a.index(k)
            opts[k] = int(a[i + 1])
            a = a[:i] + a[i + 2:]
    before, after = slim(a[0], a[1], opts["--q"], opts["--max"])
    print("%s: %.2f MB -> %.2f MB" % (os.path.basename(a[1]), before / 1e6, after / 1e6))
