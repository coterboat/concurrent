#!/usr/bin/env python3
"""Two or more invaders on one land: sequential fights vs a simultaneous melee.

    python3 tools/melee_sim.py

sequential  (v1.2) invaders fight the defender one at a time in a hashed order; once the
            land falls, later invaders fight the new occupant for the spoils.
split       (v1.3 candidate) every salvo, each invader fights its own volley against the
            defender, who splits his weight across the fronts in proportion to the invaders:
            score = 5 x die + share, share = D x A_i / sum(A). Each volley's loser loses one,
            so a defender can lose two men in one salvo, or win on both fronts.
full        the defender uses his whole army on every front (Risk-style dice per attacker)
merged      what one commander sending the same total would face (reference)
Once the defender is gone the surviving invaders fight for the spoils (ties reroll).
"""
import random

R = random.Random(7)
N = 20000
CASES = [(5, 5, 8), (3, 3, 4), (6, 2, 5), (10, 10, 12), (4, 4, 4), (8, 3, 6), (2, 2, 1), (6, 6, 6), (12, 4, 9), (4, 4, 10)]


def d6():
    return R.randint(1, 6)


def duel(a, d, ties_attacker=True):
    """one volley; True if the attacker side wins it"""
    while True:
        sa = 5 * d6() + a
        sd = 5 * d6() + d
        if sa == sd and not ties_attacker:
            continue
        return sa >= sd


def fight(a, d, ties_attacker=True):
    while a > 0 and d > 0:
        if duel(a, d, ties_attacker):
            d -= 1
        else:
            a -= 1
    return a, d


def spoils(armies):
    """survivors fight it out pairwise; returns (index, left)"""
    alive = [(i, n) for i, n in enumerate(armies) if n > 0]
    while len(alive) > 1:
        (i, a), (j, b) = alive[0], alive[1]
        a, b = fight(a, b, False)
        alive = [(i, a) if a > 0 else (j, b)] + alive[2:]
    return alive[0] if alive else (None, 0)


def sequential(atts, d):
    order = list(range(len(atts)))
    R.shuffle(order)
    left = list(atts)
    owner, hold = None, d
    for i in order:
        if owner is None:
            a, hold = fight(left[i], hold)
            left[i] = a
            if a > 0:
                owner, hold = i, a
                left[i] = 0
        else:
            x, y = fight(left[i], hold, False)
            left[i] = 0
            if x > 0:
                owner, hold = i, x
            else:
                hold = y
    return owner, hold


def melee(atts, d, mode):
    left = list(atts)
    while d > 0 and any(n > 0 for n in left):
        tot = sum(n for n in left if n > 0)
        loss = 0
        for i, a in enumerate(left):
            if a <= 0:
                continue
            share = d if mode == "full" else d * a / tot
            if duel(a, share):
                loss += 1
            else:
                left[i] -= 1
        d = max(0, d - loss)
    if d > 0:
        return None, d
    return spoils(left)


def merged(atts, d):
    a, dd = fight(sum(atts), d)
    return (0, a) if a > 0 else (None, dd)


def main():
    print("%-12s %-11s %-9s %-24s %s" % ("case", "style", "holds", "who takes it", "survivors (winner)"))
    for c in CASES:
        atts, d = list(c[:-1]), c[-1]
        for name, f in [("sequential", lambda: sequential(atts, d)), ("split", lambda: melee(atts, d, "split")),
                        ("full", lambda: melee(atts, d, "full")), ("merged", lambda: merged(atts, d))]:
            holds = 0
            takes = [0] * len(atts)
            surv = 0.0
            for _ in range(N):
                who, left = f()
                surv += left
                if who is None:
                    holds += 1
                else:
                    takes[who] += 1
            t = " / ".join("%3.0f%%" % (100.0 * x / N) for x in takes) if name != "merged" else "%3.0f%% (together)" % (100.0 * takes[0] / N)
            print("%-12s %-11s %5.0f%%   %-24s %.1f" % ("%s v %d" % ("+".join(map(str, atts)), d), name, 100.0 * holds / N, t, surv / N))
        print()


if __name__ == "__main__":
    main()
