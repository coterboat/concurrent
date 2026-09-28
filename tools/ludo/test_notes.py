#!/usr/bin/env python3
"""Tests for review notes -> the next take (notes.py) and ludo.py's extra takes. No Ludo or Claude calls.

    python3 tools/ludo/test_notes.py
"""
import os
import sys
import unittest

sys.dont_write_bytecode = True
os.environ["CONCURRENT_NO_CLAUDE"] = "1"
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import notes  # noqa: E402
import ludo  # noqa: E402


class SpeechRules(unittest.TestCase):
    def test_the_levers(self):
        cases = [
            ("Here come the surges. Steady now.", "More pause between sentences", "Here come the surges... Steady now."),
            ("They are exactly where I expected. Strike.", "More pause between expected and Strike, more menace to 'Strike'",
             "They are exactly where I expected... *Strike*."),
            ("Next! You were always going to lose.", "Inflection is wrong - downwards for both. *always* should be emphasized",
             "Next. You were *always* going to lose."),
            ("Throw again!", "Again needs to be shouted out, downward inflection", "Throw again!"),
            ("Your call, commander.", "redo", "Your call, commander."),
        ]
        for text, note, want in cases:
            with self.subTest(note=note):
                self.assertEqual(notes.speak_rules(text, note), want)

    def test_a_rewrite_keeps_the_words(self):
        items = [{"id": "a", "text": "Gone. Taken, like that.", "note": "More pause after Gone."},
                 {"id": "b", "text": "Fall back.", "note": "Redo"}]
        got = notes.rewrite_speech(items)
        self.assertEqual(set(got), {"a"}, "a bare 'redo' asks the text for nothing")
        speak, why, how = got["a"]
        self.assertEqual(how, "rules")
        self.assertEqual(notes.words(speak), notes.words(items[0]["text"]))
        self.assertIn("...", speak)

    def test_meaningful(self):
        self.assertFalse(notes.meaningful(""))
        self.assertFalse(notes.meaningful("Redo"))
        self.assertFalse(notes.meaningful("perfect"))
        self.assertTrue(notes.meaningful("More menace"))

    def test_prompt_fallback_appends_the_note(self):
        got = notes.rewrite_prompts([{"id": "p", "kind": "video", "prompt": "A general at his map table.",
                                      "note": "Very close, but he should smile at the player at the end"}])
        prompt, why, how = got["p"]
        self.assertEqual(how, "rules")
        self.assertTrue(prompt.startswith("A general at his map table. Direction for this take: He should smile"))


class LudoTakes(unittest.TestCase):
    def test_extra_takes_expand_with_their_own_ids(self):
        a = {"id": "line18_varek_win_v3", "kind": "speech", "v": 4, "text": "Next.", "out": "review/v18_voices/varek/win_v3"}
        img = {"id": "pic", "kind": "image", "out": "assets/art/pic"}
        got = ludo.with_takes([a, img], 3)
        self.assertEqual([x["id"] for x in got], ["line18_varek_win_v3", "line18_varek_win_v3~t2", "line18_varek_win_v3~t3", "pic"])
        self.assertEqual(got[1]["out"], "review/v18_voices/varek/.takes/win_v3.t2")
        self.assertEqual(ludo.MANIFEST_V["line18_varek_win_v3~t3"], 4)
        self.assertEqual(ludo.with_takes([dict(a, takes=2)])[1]["id"], "line18_varek_win_v3~t2", "a manifest `takes` works too")
        self.assertEqual(len(ludo.with_takes([a])), 1)

    def test_the_voice_says_speak_when_set(self):
        self.assertEqual(ludo.spoken({"text": "Gone."}), "Gone.")
        self.assertEqual(ludo.spoken({"text": "Gone. Taken.", "speak": "Gone... Taken."}), "Gone... Taken.")


class RankTakes(unittest.TestCase):
    """A redo whose note asked for a falling end puts the best-falling take first (real clips)."""

    def test_falling_take_becomes_take_1(self):
        import json
        import shutil
        import tempfile
        import v18_content as v18
        root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
        rising = os.path.join(root, "assets", "voice13", "varek", "win_v3.mp3")     ## ends +1.7 st
        falling = os.path.join(root, "assets", "voice", "advisor", "sealed_v4.mp3")  ## ends -3.5 st
        if not (os.path.exists(rising) and os.path.exists(falling)):
            self.skipTest("the reference clips aren't installed")
        tmp = tempfile.mkdtemp()
        old = v18.BATCH_DIR
        try:
            v18.BATCH_DIR = tmp
            os.makedirs(os.path.join(tmp, "varek", ".takes"))
            shutil.copy2(rising, os.path.join(tmp, "varek", "win.mp3"))
            shutil.copy2(falling, os.path.join(tmp, "varek", ".takes", "win.t2.mp3"))
            v18.rank_takes([("varek", "win", "line18_varek_win")], {"line18_varek_win": "fall"})
            with open(os.path.join(tmp, "varek", "win.mp3"), "rb") as a, open(falling, "rb") as b:
                self.assertEqual(a.read(), b.read(), "the falling take is take 1 now")
            info = json.load(open(os.path.join(tmp, "take_info.json")))
            self.assertTrue(info["varek/win.mp3"].startswith("falls"), info)
            self.assertTrue(info["varek/.takes/win.t2.mp3"].startswith("rises"), info)
            self.assertEqual(v18.want_of("Needs to end on downward inflection"), "fall")
            self.assertEqual(v18.want_of("More pause between sentences"), "pause")
            self.assertIsNone(v18.want_of("More menace"))
        finally:
            v18.BATCH_DIR = old
            shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    unittest.main(verbosity=1)
