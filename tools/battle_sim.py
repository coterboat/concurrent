#!/usr/bin/env python3
"""Compare battle styles: capture %, survivors and rolls per fight.

    python3 tools/battle_sim.py

decisive   armies + 1d6, one roll; winner loses floor(loser/2) (bible v0.2)
volleys    each volley: 5 x d6 + armies; lower score loses one (v1.1 default)
+1 per N   whole-number size bonuses, shown for why they were rejected: they snowball
Ties go to the attacker throughout (invasion rules).
"""
import random

R = random.Random(11)
N = 20000
CASES = [(1, 1), (2, 1), (3, 1), (4, 4), (8, 8), (12, 12), (20, 20), (6, 4), (8, 5), (5, 8), (10, 5), (3, 5)]


def decisive(a, d):
    x = a + R.randint(1, 6)
    y = d + R.randint(1, 6)
    if x >= y:
        return True, max(1, a - d // 2), 1
    return False, max(1, d - a // 2), 1


def volleys(a, d, bonus):
    n = 0
    while a > 0 and d > 0:
        n += 1
        if R.randint(1, 6) + bonus(a) >= R.randint(1, 6) + bonus(d):
            d -= 1
        else:
            a -= 1
    return a > 0, (a if a > 0 else d), n


def row(name, f):
    win, rem, rolls = [], [], []
    for a, d in CASES:
        w = r = k = 0
        for _ in range(N):
            won, left, n = f(a, d)
            w += won
            r += left
            k += n
        win.append("%5.0f%%" % (100.0 * w / N))
        rem.append("%6.1f" % (r / N))
        rolls.append("%6.1f" % (k / N))
    print(name.ljust(14), "win ", " ".join(win))
    print(" " * 14, "left", " ".join(rem))
    print(" " * 14, "rols", " ".join(rolls))


print(" " * 20 + " ".join(("%dv%d" % c).rjust(6) for c in CASES))
row("decisive", decisive)
row("volleys x5", lambda a, d: volleys(a, d, lambda s: s / 5.0))
row("+1 per 5", lambda a, d: volleys(a, d, lambda s: s // 5))
row("+1 per 3", lambda a, d: volleys(a, d, lambda s: s // 3))
