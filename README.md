# CONCURRENT

Risk II SameTime. Chassis update. Not a new genre.

Godot 4.5 kernel. Knife-fight is **The Isthmus**. Golden globe is **The Known World**. Testers: two humans and a Neutral doorstop.

## Run

```bash
./scripts/test.sh         # G0–G6 kernel + session
./scripts/probe.sh plan_bugs
./scripts/combat_sim.sh   # capture bands
./scripts/monkey.sh       # 1000 random-legal games
./scripts/cli.sh dump --seed 42 --out match.json
./scripts/cli.sh replay match.json
./scripts/cli.sh play --seed 42     # you are red, monkey is blue
```

Play: open the project in Godot and press Play, or:

```bash
"$HOME/Downloads/Godot.app/Contents/MacOS/Godot" --path .
```

Pick a map on the title screen. **The Isthmus** (7 lands, 5 rounds) teaches the wheel. **The Known World** (24 lands, 8 rounds) is the playtest globe — Neutral sits on The Strait.

**Teach round 1 — sheets open**, then **Hotseat — you and him**. You vs Monkey is the smoke path.

Click your hexes, place +/−, send 1 to N−1, attack/move chips, LOCK. Cinema is Space / click. After cinema, the round board (who got walked, who took what, score). Ghost arrows are last round’s packets at 30%.

Esc on the title screen quits.

## Sit-down (G6)

1. Three-minute rules pass. Wheel only. Neutral is a doorstop, not a third player.
2. **Teach round 1** with the sheet visible together. He is Red, you are Blue, Neutral sits on The Gate.
3. After the first cinema + round board, hotseat for real. Hand the Mac over; the map stays, the sheet hides.
4. Watch for: did he see the cap (`max N` on enemy hexes)? Did a vacated origin get walked? Did cinema make the clash obvious?
5. Stop after one game. Ask: “Want another?” That answer is G6.

Replay: `user://last_match.json`. Tuning log: `user://telemetry.jsonl` (vacate-punish, even-fight captures, lead changes). Godot → Editor → Open User Data Folder.

## Docs

- [BUILD_PLAN.md](BUILD_PLAN.md) — Godot translation of the wheel
- [CONCURRENT_Build_Bible_v0.2.pdf](CONCURRENT_Build_Bible_v0.2.pdf) — rules lock

`engine/` has no Nodes, no scenes, no unseeded RNG. If a later idea fights the wheel, the idea loses.
