#!/usr/bin/env python3
"""v1.8b voices: Fortune. The advisor when we call on her, when a rival does, and when she
owes us; each commander's line as they call on her. Same flow as v18_content.py, its own
review batch (review/v18b_voices):

    python3 tools/ludo/v18b_content.py            # lines.json + manifest entries
    python3 tools/ludo/ludo.py $(python3 tools/ludo/v18b_content.py --ids)
    python3 tools/ludo/v18b_content.py --batch
    python3 tools/review/review.py serve --open
    python3 tools/ludo/v18b_content.py --install  # or --regen for the rejected
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import v18_content as base  # noqa: E402

base.BATCH = "v18b_voices"
base.BATCH_DIR = os.path.join(base.ROOT, "review", base.BATCH)
base.PLAN = os.path.join(os.path.dirname(__file__), "v18b_plan.json")
base.EXTRA = []
base.CONTEXT.update({
    "fortune_us": "you call on Fortune: the exchange is thrown again",
    "fortune_them": "a rival calls on Fortune in a battle against you",
    "fortune_gained": "Fortune owes you a favour after bad luck",
    "fortune": "they call on Fortune: the exchange is thrown again",
})
base.NEW = {
    "advisor": {
        "fortune_us": ["Fortune, favour us now! Throw again!",
                       "Once more, lads! Fortune is with us!",
                       "That never happened, Commander. Throw again!"],
        "fortune_them": ["They have called on Fortune. The cheek of it.",
                         "Fortune favours them. For now.",
                         "They have bought themselves another throw. Steady, Commander."],
        "fortune_gained": ["Fortune owes us one, Commander. The dice have been cruel.",
                           "The dice have robbed us once too often. Fortune is in our debt.",
                           "A favour banked. Spend it when the dice turn on us."],
    },
    "varek": {"fortune": ["Again. Properly, this time.", "Fortune owes me. I am collecting."]},
    "ysolde": {"fortune": ["No. We do that again.", "Fortune serves me, like everyone else."]},
    "quill": {"fortune": ["I would like a refund, please!", "A clerical error! Again!"]},
    "oren": {"fortune": ["Do-over! That one did not count!", "Fortune loves a dashing cavalryman!"]},
    "hask": {"fortune": ["Throw the bones again, lads! Ha!", "The sea owes the Bear a better wind!"]},
    "imre": {"fortune": ["Recalculating.", "That result was noise. Again."]},
}


def main():
    base.main()


if __name__ == "__main__":
    main()
