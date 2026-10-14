The packet is incomplete in the message I was shown, so I am reading the rest of the diff before judging replay determinism, rules 21, and the client paths.CANARY: I can see tools, a workspace path, and skill files beyond this packet. The findings below are from the packet diff only.

### F1 · high · correctness
File: game/ui/cinema.gd:885
Claim: Under rules 21, a two-pronged attack whose defender marches out on only one border deletes the column that was not in the clash. Ridge and Harbor both march on the Gate, and the Gate marches out at Ridge. The clash is Ridge vs the Gate. Both red orders have `to == win_to` (the Gate). `_settle_arrows` keeps the first of those orders, writes the clash's `winnerRemaining` onto it, and `continue`s past `keep.append` for the second, so Harbor's arrow and its marching column disappear even though Harbor never fought. Whichever red order is first can also be the one that is shrunk, so the untouched stack is shown with the fought column's survivor count.
Evidence: `if win_done: continue` sits above `keep.append(o)` and matches only `owner == wid` and `to == win_to`. The loser branch does the same for every order with `to == loser_to`. Rules 21 no longer merges those orders before the report (`resolve.gd` skips `_merge_same_owner` when `rules >= 21`). `test_v21._clash_by_border` checks engine size 9, not the arrows.
Fix: Drop or resize only the order whose `from`/`to` is the clash pair. Leave every other order, including a second column into the same land, untouched. Same rule for the loser.

### F2 · high · correctness
File: engine/resolve.gd:890
Claim: A one-sided or split surge is thrown away when that commander's fronts take the land. Ridge storms the Gate and surges on to the Quarry; Harbor storms the Gate with no surge (or surges to the Beacon). Both fronts stand. The join builds one transit with `_merge_same_owner`, which the decision says keeps a surge only when the fronts agree. A blank versus the Quarry, or the Quarry versus the Beacon, is a disagreement, so nobody marches on and both stacks sit on the Gate. The same helper is used for an empty-land walk-in, so two columns walking into an empty land with different onward orders lose them too. `_surge_together` only fires when both fronts already name the Quarry, and it never checks a one-sided surge.
Evidence: `alive.append({..., "t": _merge_same_owner(ts2)[0], "a": men})` in the rules `>= 21` melee ending, and `invaders = _merge_same_owner(invaders)` in `_land_v14` before the walk-in. The decision states the agree-or-drop rule.
Fix: Join only fronts that share a next step. Fronts with no surge stay and add their survivors. Each distinct surge target leaves as its own column with that front's survivors. Do this in one helper used by the melee ending and the empty-land landing.

### F3 · medium · correctness
File: game/world3d/diorama.gd:250
Claim: Taking a recruit back does not take the figure off the table. `_lift` sets `alive = false` and `state = "lift"`, but this diff gives `_place` no `lift` arm, does not hide the mesh, and does not advance `t`. The node is `queue_free`d only on a later `_muster`, and only if `t > 0.6`. After a single +1/−1 with no later garrison change, the mesh keeps its last transform. `v203` treats `state == "lift"` after 45 frames as "lifted off" and never checks that the node moved or left the scene.
Evidence: `_lift` only assigns `alive`, `state`, and `t`. The free loop at the start of `_muster` is the only consumer. The `_place` hunk changes the march duration and does not mention `lift`.
Fix: Animate `lift` in the same loop that advances every other figure (raise, hide, then free after the fixed time), and make the probe assert the node is gone or hidden, not merely flagged.

### F4 · medium · correctness
File: game/core/last_round.gd:123
Claim: A rules 20 (or any older) attack that set out from two lands loses the fate on the column that is not the front's single `from`. Those games still merge into one melee front. Ghosts used to match that front by commander. The new check requires `fromIds` or else `[from]`, and nothing in this diff writes `fromIds`. The Harbor ghost no longer matches the Ridge front, so the thrown-back / fell-back / clash mark for that column is skipped. Rules 21 is fine only because each front keeps its own `from`.
Evidence: `ff = f.get("fromIds", [f.get("from", "")])` then `if g.has("from") and not ff.has(str(g["from"])): continue`, with no `map.rules` gate.
Fix: Gate the from-land filter on rules `>= 21`. For older fronts, keep matching by commander, or match when `fromIds` is absent.

### F5 · medium · correctness
File: game/board/map_board.gd:359
Claim: Skip during "Show my battles" does not give the view back. Opening a battle calls `swoop_to`, which returns a tween that is not stored on `_lean_tw` or `_back_tw`. `skip` calls `restore_view`, which only kills those two. The swoop keeps writing zoom and offset and finishes in the battle frame. `stand_back` also treats any still-valid `_back_tw` as in flight; a finished Godot tween stays valid, so a later return home is skipped when `_at_fit` is already false.
Evidence: `swoop_to` kills `_lean_tw` and `_back_tw` but does not assign its own tween. `restore_view` kills only those fields. `stand_back`'s at-fit branch is `if not (_at_fit or _back_tw.is_valid())`.
Fix: Keep one camera tween. Have `swoop_to`, `swoop_back`, and `_glide` store it after killing the previous one. Have `restore_view` kill that tween. In `stand_back`, test `is_running()`, not `is_valid()`.

### F6 · medium · correctness
File: game/world3d/land_field.gd:470
Claim: Horse and guns disappear while the army is still fighting. `battle_train(army size)` is written only onto the single biggest group. `_cull` is per group, and the new filter ignores pieces with `counts == false`, so casualties never remove the train. When that host group's share hits 0, the group's wipe (the share `== 0` branch the decision relies on) tops the train with it. Any other group of that army is still on the field, with men and no train. A 40-man battle broken into groups, which this loop exists to handle, does that. The v21 probe only asserts a train when a whole army's `n` is already 0.
Evidence: `big["horse"]` / `big["guns"]` / `big["train"] = true` on the max-share group only. `_cull`'s line filter adds `and bool(f["counts"])`.
Fix: Tie the train to the army. Move it onto a surviving group if the host group dies, and topple it only when that army's total men hit 0.
