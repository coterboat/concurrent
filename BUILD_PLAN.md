# CONCURRENT — Godot Build Plan

> **v1.0 (24 Sep 2026):** the gates below are built through G12 minus G7 (two devices). What shipped and every rule amendment since v0.2 is in [docs/CHANGELOG.md](docs/CHANGELOG.md).

Risk II SameTime. Chassis is Godot 4.5, not TypeScript. Not a new genre.

v0.2 locked the wheel, combat, sheet, queue, and gates. This plan does not reopen them. It translates the kernel onto a machine you and your dad can launch in one click, sit down, and groan at.

Testers: you and him. Design center in the bible is 4. Our path in is **2 humans + Neutral** on the 7-hex knife-fight. That is legal (bible 3.9). That is also how you get a game on the table this week.

---

## 0. What we are actually making

A digital-first board game. Original title, original map names, original region names. Same density of decision as a classic conquest map. Not a licensed clone.

The hook is already in the rules:

> Everyone commits. Attackers leave home empty. The map detonates. The person who stripped a border gets walked.

2026, for this house, is: a Mac that both of you can read from the couch, a sealed sheet that feels like writing orders, a cinema of the queue a Civ 3 player can parse without a spreadsheet, ghost arrows from last round, and a match that replays to the same hash.

We are not adding missions, factions, tech trees, unit types, workers, or diplomacy-as-a-phase. Those fight the wheel. Civ 3 is the **chrome and the comfort**, not a second game stacked on top.

---

## 1. Translation: bible stack → this repo

| Bible layer | Bible stack | This repo |
|---|---|---|
| L0 Kernel | Pure TS, no DOM, no `Math.random` | Pure GDScript in `engine/`. No `Node`, no scenes, no `randi()` / `randf()` / `RandomNumberGenerator` without a derived seed. |
| L1 Harness | CLI, JSON fixtures, `combat_sim`, replays | `godot --headless --script` test runner + `tools/combat_sim.gd`. `match.json` in / out. |
| L2 Knife-fight | 7-hex, phone pads or hotseat-with-pass | **Hotseat-with-pass first.** One Godot window. Hide the sheet, keep the public map. Phones wait until G7. |
| L3 Room | Dumb WS room | Later. LAN two-window is the dad upgrade, not week 1. |
| L4 World map | 28–32 / 5–6 regions | After G6 is true with him. Not before. |

Godot version: **4.5.1 stable** (already on this machine: `~/Downloads/Godot.app`). Renderer: **gl_compatibility** so it runs on whatever Mac he has. Window: 1440×900, UI scale bump ready.

Gates G0–G8 stay. Clocks stay dropped.

---

## 2. The wheel (still do not renegotiate)

Copied from v0.2 so nobody “improves” them in Godot:

1. **Simultaneous commit.** Reinforcements, attacks, and the regroup are sealed before anything resolves.
2. **Attackers vacate.** Strength assigned to an attack is gone from the origin when orders lock. Origins defend with what is left. Never soften this.
3. **Convergence.** Several packets may legally target the same destination. Different owners do not merge. Same owner does.
4. **Fixed queue.** Border clashes → mass / single invasions → spoils → surge. No click-order.
5. **Placement cap.** Armies added to T this round ≤ 1 + friendly neighbors of T (after regroup, before place). Unused income is lost.
6. **Hidden intent, public map.** You see army counts. You do not see sealed orders. Enemy hexes show *max possible garrison after reinforce* (current + cap).

If a later idea fights this list, the idea loses. Including “but Civ 3 did stacked units / culture flip / one more unit type.”

---

## 3. What we steal from dad’s two loves

### From Risk II SameTime (the game)

- The groan when you walk into a vacated origin.
- Writing the whole turn in secret.
- Surge as a second destination on a packet, not a flag, and always last.
- Restricted placement so you cannot dump the bank on one remote hex.

### From Civ 3 (the feel)

Chrome only. After the kernel is honest.

| Steal | How | When |
|---|---|---|
| Big readable map | Army counts as large as city pop labels. Owner color + hatch (colorblind). No fog. | G5 |
| Military advisor | Cinema captions, one event per beat, pause. “Red 6 vs Blue 4 at The Gate — toss-up.” Never 91.2%. | G5 |
| F3 / recap | After cinema, a round board: who took what, who got walked, score. | G5 |
| One more turn | Score after 5 rounds on the knife-fight. Early end at 80% or last player standing. He will ask for another. That is G6. | rules already |
| Province names | Original names, not classic-map names. Isthmus of seven. | G0 map data |
| Pass the chair | Hotseat overlay: “Hand the Mac to Dad.” Sheet hidden. Map stays. | G5 |
| Fanfare | Lock drum, dice, capture. After the picture is right. | post-G5 |

Do **not** steal: workers, tech, wonders, unit classes, culture, city production queues, stacked mixed armies, diplomacy screens. Those are a different game.

---

## 4. Engine contract (Godot-shaped, bible-faithful)

Split static map from live state. Do not grow a log onto World and then hash World.

Seed is **not** stored on World. The match (CLI / autoload MatchSession) holds `match_seed`. `resolve_round(world, map, sheets, match_seed) → {world, events}`.

```
engine/types.gd       PlayerId, TerrId, MapDef, World, Packet, Sheet, Event, Card
engine/rng.gd         derive_stream(match_seed, round, battle_key) → RandomNumberGenerator
engine/map.gd         adjacency, region membership, legal neighbors
engine/income.gd      income_of, cap_of, connected_bloc
engine/validate.gd    validate_sheet → PackedStringArray of errors
engine/combat.gd      size + 1d6, winner loss floor(loser/2), keep ≥1, ties
engine/resolve.gd     regroup → place → vacate → A clash → B invasion → C spoils → D surge → upkeep
engine/events.gd      typed event dicts, world_hash(world)
engine/bot.gd         random-legal sheet (week 1, not week 6)
engine/setup.gd       deal, starting pools, Neutral fill
```

Rules that must be visible in code comments, not tribal memory:

- Round 1 has no regroup.
- Just-placed armies may attack this round.
- Income is computed on the **post-regroup** map.
- On lock, packet strength leaves `from`. Those armies do not defend `from`. They do not defend `to` until they win it.
- Same-owner merge before the queue. Keep `surge_to` only if every merged packet named the same one.
- Invasion ties → attacker. Clash and spoils: both sides are attackers, **reroll ties**.
- Winner loses `floor(loser / 2)`, always keeps ≥1. A 0–0 cannot happen. 1v1 winner occupies with 1.
- Owned hex has ≥1 army, or it is unoccupied (`owner = ""`, `armies = 0`). No owned-empty state.
- Walking into unoccupied still requires a packet of ≥1 and still vacates the origin.
- Neutral does not plan, never attacks, only defends with size+1d6. Neutral region bonuses are unpaid.
- Cards: **skip on the 7-map.**

RNG: `battle_key` is a stable id for that fight (sorted packet ids / hex pair), not “whatever we processed next.” Adding an unrelated packet on the other side of the map must not reroll this fight.

Hash for T6: `hash(world snapshot AFTER resolve)`, never `hash(seed + world)`.

Event kinds (required, not later): `RegroupApplied, Placed, Vacated, Clash, Invasion, Spoils, Surge, Occupied, BecameUnoccupied, CardDrawn, PlayerEliminated, Score, RoundEnded`. Combat events carry hexes, players, pre/post sizes, both dice, both totals. Cinema renders this list. Nothing else.

---

## 5. Combat (v0.1 is not a source)

One roll. One thumb. Size in the open.

```
each side: armies + 1d6
higher total wins
invasion ties → attacker
loser is removed
winner loses floor(loser / 2), keeps ≥1
```

`tools/combat_sim.gd` must print bands inside this table before anyone draws a hex. 8k+ fights, invasion ties → attacker:

| Matchup | Capture | Band we want |
|---|---|---|
| 1v1 | ~58% | 55–60 even |
| 3v1 | ~83% | remnant taxes |
| even any size | ~58% | 55–60, stable at 4v4 / 8v8 / 20v20 |
| 6v4 (3:2) | ~83% | ~80 |
| 8v5 | ~91% | high 80s / low 90s |
| 5v8 | ~16% | ≤25 |
| 10v5 (2:1) | ~100% | ~95 |

If bands drift, we are allowed to touch **winner loss** second, size+1d6 only if they drift. We are not allowed to restack edges, add a 2× mid-fight, or bring back volleys.

UI may show a band on the sheet: **long shot / toss-up / likely / lock**. Do not print percents.

---

## 6. Knife-fight map (ships first)

7 territories, 2 regions, one choke. Cards off.

**The Isthmus**

| Id | Name | Region | Bonus region |
|---|---|---|---|
| beacon | Beacon | northshore | northshore = 2 |
| ridge | Ridge | northshore | |
| mill | Mill | northshore | |
| gate | The Gate | *(none — the choke)* | — |
| harbor | Harbor | southshore | southshore = 2 |
| docks | Docks | southshore | |
| quarry | Quarry | southshore | |

Adjacency (undirected):

```
beacon — ridge — mill
           |
         gate
        /  |  \
   harbor  |  quarry
        \  |  /
         docks
```

- `beacon: ridge`
- `ridge: beacon, mill, gate`
- `mill: ridge`
- `gate: ridge, harbor, docks, quarry`
- `harbor: gate, docks`
- `docks: harbor, gate, quarry`
- `quarry: gate, docks`

North cannot reach south except through The Gate. Interiors (Beacon, Mill) still matter in a 5-round game because the cap punishes dumping on an isolated tip, and vacate-punish on Ridge/Gate is the whole show.

**2p + Neutral setup (dad path)**

Bible starting pools are 3p/35, 4p/30, 5p/25. Two-player is Neutral, not a halved 3p.

Starting point, tune only against play:

- Deal: shuffle 7 ids, 3 to Red, 3 to Blue, leftover → Neutral.
- If the leftover is not The Gate, swap so Neutral sits on The Gate. Doorstop belongs on the choke. (If that feels too scripted after one session, revert to pure shuffle.)
- Red / Blue place a pool of **18** each, simultaneous, capped. Overflow forfeit.
- Neutral does not place. Neutral armies on The Gate: **5**.
- After a scattered deal, a second simultaneous placement pass before round 1, as the bible says. No exemption.
- Round limit: **5**. Score = territories + region bonuses currently held. Ties: most regions, then most armies.
- Early end: 80% of 7 is 6 territories at upkeep, or last player with a territory.

If 18/5 snowballs or stalls, income and Neutral size are the knobs. Vacate is not.

**Also ship, same kernel:** 1 human + 2 random-legal bots, no Neutral, 3-way deal of 2/2/2 + 1 unoccupied. That is how you test clash/spoils without waiting for a third human.

---

## 7. Repo layout

```
concurrent/
  project.godot
  icon.svg
  engine/                 # L0 — zero scene imports, zero Node
    types.gd
    rng.gd
    map.gd
    income.gd
    validate.gd
    combat.gd
    resolve.gd
    events.gd
    bot.gd
    setup.gd
    hash.gd
  maps/
    knife7.json
  tests/
    runner.gd             # godot --headless --script res://tests/runner.gd
    test_combat_bands.gd  # G1
    test_t1_vacate.gd
    test_t2_mutual.gd
    test_t3_mass_spoils.gd
    test_t4_illegal.gd
    test_t5_cap.gd
    test_t6_determinism.gd
    test_t7_surge_last.gd
    test_t8_three_way.gd
    test_properties.gd    # P1–P4, monkey 1000
    fixtures/
  tools/
    combat_sim.gd
  game/                   # L2 — the only place Nodes live
    main.tscn
    match_session.gd      # holds match_seed, never puts it on World
    map_view.gd
    sheet_ui.gd
    cinema.gd
    ghost_arrows.gd
    hotseat.gd
    hud.gd
  docs/
    CONCURRENT_Build_Bible_v0.2.pdf
    BUILD_PLAN.md
  README.md               # one command to knife-fight, once G5 exists
```

`engine/` may not `preload` anything under `game/`. Tests import `engine/` only. If a PR puts a Sprite2D in `resolve.gd`, it is rejected.

No addons for G0–G4. No GUT until we feel pain. Headless script in, printed TAP-ish out, exit code 0/1.

---

## 8. Sequence (clocks dropped, gates kept)

Dad is the G6 instrument. Bots are how we know `resolve.gd` does not leak armies.

| Gate | You may not proceed until | What “done” looks like here |
|---|---|---|
| **G0 Scaffold** | Project opens, `engine/` compiles, rng has no unseeded roll, types exist, knife7.json loads. | `godot --headless --script res://tests/runner.gd` runs and says G0 ok. |
| **G1 Combat** | `combat_sim` prints bands inside §5. 1v1 never double-wipes. | Paste the table in the PR body. |
| **G2 Queue** | T1–T8 green on 7-map fixtures, including three-way clash → mass → spoils. | Fixture JSON + event log reconstructible. |
| **G3 Monkey** | Random-legal bot plays 1,000 games. Properties: no negatives, army accounting, every hex owned or unoccupied, determinism. | 1000 in headless, < 30s. |
| **G4 CLI** | You can play a knife-fight against the monkey and dump `match.json`. | Headless or ugly print map is fine. |
| **G5 Visible** | Ugly client: sheet + map + cinema + ghost arrows of last round. Cap readout on enemy hexes. Hotseat pass. | You can teach him the sheet without explaining code. |
| **G6 Human** | Two humans finish. Vacate-punish happens. They ask for another. | This is you and him. Three humans is a bonus, not the gate. |
| **G7 Room** | Two devices submit sheets at the same time at a table with one shared cinema. | Only if G6 is true and passing the Mac is the complaint. |
| **G8 World** | 28–32 map only after G6. Tune income/regions against bot telemetry + those humans. | Steal Civ 3 “world map” scale here, not earlier. |

Out of this plan until G6 is true: factions, paper port, diplomacy-as-a-phase, fortification markers, cards, phones, Ludo, netcode, 3D, shaders-as-product.

---

## 9. Tests (port T1–T8 literally)

Write these as fixtures, not as “we’ll eyeball it.”

- **T1 Vacate-punish.** Red origin 5 sends 4. Green sends 3 at that origin. After lock Red origin has 1. If Green wins, Green owns it even if Red’s packet later wins elsewhere.
- **T2 Mutual strike.** Clash packets fight each other before either leftover garrison is used as a defender.
- **T3 Mass then spoils.** Red 5 and Blue 5 both hit Green 3. One owner remains.
- **T4 Illegal leftover.** Origin 3, two packets of 2. Rejected.
- **T5 Cap.** Isolated hex accepts at most 1 reinforcement. Overflow vanishes.
- **T6 Determinism.** Same setup + matchSeed + sheets → same world hash and same event list.
- **T7 Surge last.** Surge target that is also a primary is resolved as a primary first.
- **T8 Three-way.** Clash survivor continues into a hex that a third player also hit. Log is reconstructible from events.

**P1–P4.** Fuzz random legal sheets: no negative armies, Σ armies + in-transit accounted, no owned-empty hex, `validate_sheet` rejects what `resolve_round` would choke on.

---

## 10. UI that serves the wheel (G5, not G0)

Map is a status board. Counts readable from the couch. Vacated origins look vacated the **moment of lock**, before dice.

Enemy hexes show `current` and `max possible after cap`. Hidden reinforce is bounded, not fog.

Sheet lists each packet with origin-remaining in **red** if it will sit at 1.

Ghost arrows: last round’s packets stay on the map at 30% while you plan this round. Teaching tool, now required.

Cinema steps the queue. Pause. One event per beat. Space / click to continue. The log is the same `Event[]` the engine emitted. Advisor voice is a caption, not a second rules engine.

Odds as words, not percents.

Colorblind patterns on owners (hatch / dots / stripes), not color alone. Red/Blue/Neutral for 2p; add a third pattern for the monkey seat.

Lock is irreversible for that round. Big button. No undo. Timeout later; for two humans in a living room, lock-when-ready is enough.

Hotseat: after lock, fade the sheet, show “Hand the Mac to ___.” Public map remains. Do not leak the locked sheet on screen.

First art is flat polygons, region tint, a gate icon on The Gate. If it looks like a prototype, good. If it looks like a 4X, we spent the week on the wrong layer.

---

## 11. Tune vs leave

| Knob | Touch? | Why |
|---|---|---|
| Vacate | No | The game. |
| Tie → attacker (invasion only) | No | The one thumb. Clash/spoils already reroll. |
| Size + 1d6 | Only if bands drift | Do not restack edges. |
| Winner loss = floor(loser/2) | Yes, second | Bloodiness lever. |
| Income and region values | Yes | Snowball lever. |
| Cap formula | Rarely | It is doing hidden-info work. |
| Round count / 80% early end | Yes | Length lever. 5 on knife-fight is the start. |
| Surge exists and goes last | No | Breakthrough reward, no pre-empt. |
| Cards on 7-map | Skip | Noise until the wheel is visible. |
| 2p pool 18 / Neutral 5 | Yes | First number we will be wrong about. |
| Neutral on The Gate | Maybe | Scripted choke vs pure shuffle. Play once each way. |
| Garrison (dug-in) | Shipped | Auto +1 per held round. Cap = 1 + friendly neighbors, +1 if you hold the region. Neutral does not dig. Fresh captures are naked. Dug-in hexes may send every mobile soldier. |
| Factions / missions / paper | After G6 | Not how this becomes the game he loved. |

---

## 12. Telemetry (or you are not tuning)

Log per match, from the monkey and from you two. JSONL next to `match.json`.

| Metric | First target |
|---|---|
| Rounds to end (knife-fight) | 4–5 median, not a round-2 wipe |
| Vacate-punish frequency | ≥1 event in ≥40% of human games |
| Lead changes after round 3 | >0 in most games |
| Attacker capture at even sizes | 55–60% |
| Attacker capture at 3:2 | 75–85% |
| Games a human wants to replay immediately | qualitative gate G6 |

His quote after game 1 is data. “I didn’t see the walk-in” means ghost arrows and vacated-state failed, not that we need a tooltip encyclopedia.

---

## 13. Definition of done, v0.2 playable on Godot

- G6 is true on the knife-fight map. You and him finished. Vacate-punish happened. He asked for another.
- `combat_sim` is in the repo and still prints bands inside the table in §5.
- A `match.json` plus `match_seed` replays to the same world hash.
- No unseeded RNG in `engine/`. Seed is not on public World pre-lock.
- README starts the client in one command (`godot project.godot` or a exported `.app` on the Mac).
- You did not add a hook to justify the project. The walk-in on a vacated origin is the hook.

---

## 14. PR / slice plan

Each slice is independently playable-as-test or playable-as-game. Do not merge UI before T1–T8.

| PR | Title | Files | Depends | Done when |
|---|---|---|---|---|
| 0 | Scaffold Godot 4.5 + engine types + seeded rng | `project.godot`, `engine/types.gd`, `engine/rng.gd`, `engine/hash.gd`, `maps/knife7.json`, `tests/runner.gd` | — | Headless runner exits 0 |
| 1 | Combat kernel + band sim | `engine/combat.gd`, `tools/combat_sim.gd`, `tests/test_combat_bands.gd` | 0 | Bands inside §5, 1v1 never double-wipe |
| 2 | Map, income, cap, validate | `engine/map.gd`, `income.gd`, `validate.gd`, `setup.gd`, T4 T5 | 0 | Illegal leftover rejected, isolated cap = 1 |
| 3 | resolve_round + events + T1–T8 | `engine/resolve.gd`, `events.gd`, all T fixtures | 1, 2 | T1–T8 green |
| 4 | Random-legal bot + 1000 monkey + P1–P4 | `engine/bot.gd`, `tests/test_properties.gd` | 3 | 1000 games, properties hold, T6 hash stable |
| 5 | Headless knife-fight + match.json dump/replay | `tools/cli.gd` or `tests/play_monkey.gd` | 4 | Replay hash matches |
| 6 | Ugly map + sheet + lock + hotseat pass | `game/*` minus cinema polish | 5 | Two people can enter a legal sheet |
| 7 | Cinema + ghost arrows + cap readout + advisor captions | `game/cinema.gd`, `ghost_arrows.gd` | 6 | Queue is visible; vacated origins look empty at lock |
| 8 | Sit-down with dad (G6) | telemetry JSONL, README | 7 | He asks for another |
| 9 | World map + cards + room | later | G6 true | Not this plan |

---

## 15. First session with him (script, not a hope)

After G5, before we invent features:

1. One 3-minute rules pass. Wheel only. No cards. Neutral is a doorstop, not a third player.
2. You take Blue, he takes Red, Neutral sits on The Gate.
3. You play round 1 with the sheet visible together (teaching). Then hotseat for real.
4. Watch for: did he see the cap on your hexes? Did a vacated origin get walked? Did cinema make the clash obvious?
5. Stop after one game. Ask: “Want another?” That answer is G6. Notes go in telemetry, not into a new system.

If he says the map is ugly, we keep it. If he says he couldn’t tell who was attacking, cinema failed. If he says attacking feels stupid because he left home empty — that is the game working.

---

## 16. Maps (G8 sketches, one golden)

Original names. Not a licensed globe. The Isthmus stays the teaching knife-fight.

| Map | Lands | Regions | Why it exists | Status |
|---|---|---|---|---|
| **The Isthmus** | 7 | 2 + choke | Teach vacate-punish in 5 rounds. | Shipped (knife7) |
| The Ring | 12 | hub + rim | Geometry toy. Too abstract for dad. | Sketched, not built |
| The Archipelago | 16 | 4 chains | Every attack is a landing. Later, as a second playlist map. | Sketched, not built |
| **The Known World** | 24 | 6 × 4 | Compact globe. Two theaters, a sea belt, a lockable south. | **Golden. Built (known24).** |
| The World | 30 | 6 | Full Risk scale. Needs pan/zoom and 3–4 seats. | After Known World is fun |

**The Known World (golden)**

```
Westreach     Crownlands      The Spine       Eastshore
 Firth—Cairn    Vale—Keep      Pass—Peak       Haven
   |      |       |     |        |     |         |
 Moor — Wold    Marsh—Throne   Rift—Crest      Silk
                  |                    |         |
               ---- Midsea: Shoal—The Strait—Sound—Reef ----
                  |                    |         |
               Dune — Oasis — Cape — Lagoon     Steppe—Lantern
                        Southern Rim
```

- West cannot be ignored: it feeds Midsea and the Crownlands.
- Midsea is the prize (+4). Neutral sits on **The Strait** (5), same job as The Gate.
- Southern Rim is the Australia: cheap to lock (+2), painful to pry open, only attaches through Midsea.
- Northern land route West→Crownlands→Spine→East exists. Midsea is the shortcut, not the only door. That is a world, not another isthmus.
- 2p deal: 9 / 9 / Neutral on The Strait / 5 unoccupied walk-ins. Pool **30**. **8** rounds. Early end at 80% (20 lands).

Tune bonuses and the 30-pool against telemetry, not vibes. Vacate stays.

---

## 17. From fun project to fun game

Do not start G7 (two devices) or internet until the Mac game is something he asks for.

| Stage | What | Done when |
|---|---|---|
| **G8a Known World** | 24-land globe, map picker, region wash, generic deal. | You can finish vs Monkey on it. |
| **G8b Read it from the couch** | Sheet grouped by region. Smaller labels. Region names on the map. Collapse hex cards. | 9 owned lands do not feel like a spreadsheet. |
| **G8c Tune** | Pool 30, Midsea +4, Neutral 5, 8 rounds. Telemetry: rounds-to-end 6–8, vacate-punish still happens. | Snowball and stall are both rare. |
| **G9 Feel** | Lock drum, dice click, capture sting. Recap looks like a board, not a log. Polygons stay. | It sounds like a game in the other room. |
| **G10 Four seats** | Green + gold. 4p deal of 6 each on Known World. Hotseat pass names. | Design-center player count can sit down. |
| **G11 Cards** | On Known World / The World only. Still skipped on The Isthmus. | A set cash is a decision, not noise. |
| **G12 Product** | Export a `.app`. Title that is the game, not the debugger. Teach path is the tutorial. | He launches it without you. |
| **G7 Room** | Two pads, one cinema. Unpark only when passing the Mac is the complaint. | Simultaneous commit is physically simultaneous. |
| **G8 World (30)** | Full globe after 24 is loved. Pan/zoom. | Same kernel, bigger board. |

Still out until the table is fun: factions, missions, tech, 3D, netcode-as-product, paper port, Ludo-as-identity.

The walk-in on a vacated origin is still the hook. A bigger map is more places to leave home empty, not a different game.

