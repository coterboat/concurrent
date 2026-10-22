#!/usr/bin/env python3
"""Tests for ludo.py's job handling (v2.4): no network, no credits.

    python3 tools/ludo/test_ludo.py

Ludo answers a generation call with a queued job and charges for it at once, so a job that is
let go is paid for and lost. These pin down that run_job collects every job it submits, and what
v24_content.py asks for (the faces' reactions) and installs (the take the owner kept).
"""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ludo  # noqa: E402


class Fake:
    """The POST answer, then the polls' answers in turn (an Exception is raised, not returned)."""

    def __init__(self, first, polls):
        self.first = first
        self.polls = list(polls)
        self.posted = []
        self.polled = 0

    def call(self, method, path, body=None, timeout=90):
        self.posted.append((method, path, body))
        return self.first

    def poll(self, jid):
        self.polled += 1
        nxt = self.polls.pop(0)
        if isinstance(nxt, Exception):
            raise nxt
        return nxt


class RunJob(unittest.TestCase):
    def setUp(self):
        self._call, self._sleep, self._wait, self._log = ludo.call, ludo.time.sleep, ludo.JOB_WAIT, ludo.log
        ludo.time.sleep = lambda s: None
        ludo.log = lambda *a: None

    def tearDown(self):
        ludo.call, ludo.time.sleep, ludo.JOB_WAIT, ludo.log = self._call, self._sleep, self._wait, self._log

    def run_with(self, fake):
        ludo.call = fake.call
        return ludo.run_job("/assets/sprite/animate", {"motion_prompt": "nods"}, "concurrent-x-v1", poll=fake.poll)

    def test_a_queued_job_is_waited_for(self):
        done = {"id": "j1", "status": "succeeded", "result": {"spritesheet_url": "u"}, "credits_charged": 9}
        fake = Fake({"id": "j1", "status": "queued", "poll_after_ms": 2000},
                    [{"id": "j1", "status": "queued"}, {"id": "j1", "status": "running"}, done])
        self.assertEqual(self.run_with(fake), done)
        self.assertEqual(fake.polled, 3)
        self.assertEqual(fake.posted[0][2]["request_id"], "concurrent-x-v1")

    def test_a_dropped_connection_does_not_drop_the_job(self):
        done = {"id": "j2", "status": "succeeded", "result": {}}
        fake = Fake({"id": "j2", "status": "queued"},
                    [OSError("TLS record"), RuntimeError("GET -> 502"), {"id": "j2", "status": "running"}, done])
        self.assertEqual(self.run_with(fake), done)
        self.assertEqual(fake.polled, 4)

    def test_every_spelling_of_a_dead_job_fails_it(self):
        for status in ("failed", "canceled", "cancelled", "error"):
            fake = Fake({"id": "j3", "status": "queued"}, [{"id": "j3", "status": status, "error": "moderation"}])
            with self.assertRaises(RuntimeError) as ctx:
                self.run_with(fake)
            self.assertIn("j3", str(ctx.exception))
            self.assertIn(status, str(ctx.exception))

    def test_an_unknown_status_is_waited_on_until_the_deadline(self):
        ludo.JOB_WAIT = 0.0
        fake = Fake({"id": "j4", "status": "processing"}, [])
        with self.assertRaises(RuntimeError) as ctx:
            self.run_with(fake)
        self.assertIn("j4", str(ctx.exception))
        self.assertIn("again", str(ctx.exception))

    def test_an_answer_without_a_job_says_so(self):
        fake = Fake({"message": "AI model currently unavailable"}, [])
        with self.assertRaises(RuntimeError) as ctx:
            self.run_with(fake)
        self.assertIn("without a job", str(ctx.exception))


class Inputs(unittest.TestCase):
    def test_a_big_picture_goes_up_under_a_megapixel(self):
        if ludo._pil() is None:
            self.skipTest("no Pillow here (the Mac uses sips)")
        d = tempfile.mkdtemp()
        src = os.path.join(d, "big.png")
        ludo._pil().new("RGBA", (1100, 1000), (200, 100, 50, 255)).save(src)
        old = ludo.log
        ludo.log = lambda *a: None
        try:
            out = ludo.fit_megapixel(src)
        finally:
            ludo.log = old
        w, h = ludo.image_size(out)
        self.assertNotEqual(out, src)
        self.assertLess(w * h, 1000000)
        self.assertEqual((w % 2, h % 2), (0, 0))
        self.assertEqual(ludo.fit_megapixel(out), out)  ## already small enough: sent as is

    def test_an_animation_rolls_its_takes(self):
        a = {"id": "v24_react_hask_win", "kind": "animate", "takes": 2, "v": 3, "out": "assets/raw/v24/faces/hask_win"}
        got = ludo.with_takes([a])
        self.assertEqual([x["id"] for x in got], ["v24_react_hask_win", "v24_react_hask_win~t2"])
        self.assertEqual(got[1]["out"], "assets/raw/v24/faces/.takes/hask_win.t2")
        self.assertEqual(ludo.MANIFEST_V["v24_react_hask_win~t2"], 3)


class Faces(unittest.TestCase):
    """v24_content.py: the reactions it asks for, and that Install puts the kept take in the game."""

    def setUp(self):
        import v24_content
        self.v = v24_content

    def test_every_face_and_mood_is_asked_for(self):
        v = self.v
        names = {v.name_of(w, c) for w, c in v.ITEMS}
        for who in ("varek", "ysolde", "quill", "oren", "hask", "imre"):
            for clip in ("win", "lose", "taunt", "dead"):
                self.assertIn("%s_%s" % (who, clip), names)
        for clip in ("win", "lose", "dead"):
            self.assertIn("advisor_" + clip, names)
            for who in v.PLAYERS:
                self.assertIn("%s_%s" % (who, clip), names)
        self.assertIn("you_lioness_idle", names)
        self.assertEqual(len(v.ITEMS), 6 * 4 + 3 + 6 * 3 + 1)

    def test_every_take_has_its_own_number(self):
        v = self.v
        self.assertEqual([(k, e["id"], kk) for k, e, kk in v.sources("hask", "win")],
                         [(1, "v24_react_hask_win", 1), (2, "v24_react_hask_win", 2)])
        got = [(k, e["id"], kk) for k, e, kk in v.sources("you_lioness", "idle")]
        self.assertEqual(got, [(1, "v24_loop_you_lioness_idle", 1), (2, "v24_loop_you_lioness_idle", 2),
                               (3, "v24_loop_you_lioness_idle_hydra", 1), (4, "v24_loop_you_lioness_idle_hydra", 2)])
        self.assertEqual(v.review_of("you_lioness", "idle", 4), "faces/.takes/you_lioness_idle.t4")

    def test_a_reaction_comes_home_and_a_fall_stays_down(self):
        v = self.v
        for who, clip in v.ITEMS:
            e = v.entry(who, clip)
            if v.is_loop(who, clip):
                self.assertEqual((e["model"], e["duration"]), ("forge", 2))
                continue
            self.assertEqual((e["model"], e["image_type"], e["frame_size"]), ("hydra", "portrait", -9))
            down = clip == "dead" and who != "advisor"
            self.assertEqual(bool(e.get("final_same")), not down, e["id"])
            self.assertEqual(v.BACK in e["prompt"], not down, e["id"])
            self.assertIn("inside the frame", e["prompt"])
            self.assertNotIn("blazing", e["prompt"])
            self.assertNotIn("{pos}", e["prompt"])

    def test_install_copies_the_take_that_was_kept(self):
        v = self.v
        d = tempfile.mkdtemp()
        game = os.path.join(d, "game")
        os.makedirs(os.path.join(d, "faces", ".takes"))
        for stem, body in (("faces/hask_win", b"take one"), ("faces/.takes/hask_win.t2", b"take two"),
                           ("faces/quill_lose", b"rejected")):
            for ext in (".sheet.webp", ".sheet.json"):
                with open(os.path.join(d, stem + ext), "wb") as f:
                    f.write(body + ext.encode())
        items = [{"id": "hask_win", "status": "accept", "file": "faces/hask_win.webp", "src": "faces/.takes/hask_win.t2.webp",
                  "target": os.path.join(game, "hask_win.webp")},
                 {"id": "quill_lose", "status": "reject", "file": "faces/quill_lose.webp", "note": "glassy eyes",
                  "target": os.path.join(game, "quill_lose.webp")}]
        saved = v.batch_dir, v.merged, v.godot_import
        v.batch_dir, v.merged, v.godot_import = (lambda: d), (lambda: items), (lambda: None)
        try:
            v.install(False)
        finally:
            v.batch_dir, v.merged, v.godot_import = saved
        self.assertEqual(open(os.path.join(game, "hask_win.webp"), "rb").read(), b"take two.sheet.webp")
        self.assertEqual(open(os.path.join(game, "hask_win.json"), "rb").read(), b"take two.sheet.json")
        self.assertFalse(os.path.exists(os.path.join(game, "quill_lose.webp")))
        import json
        self.assertEqual([r["id"] for r in json.load(open(os.path.join(d, "rejected.json")))], ["quill_lose"])


if __name__ == "__main__":
    unittest.main(verbosity=1)
