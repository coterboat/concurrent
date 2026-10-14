I'll read the rest of the review packet and the outside-review skill, then check the claims against the diff.The packet is large; I’ll search it for the engine, fortune, join, and camera paths the builder asked us to attack.CANARY: workspace, tools, and skills are visible; findings are from the packet.

### F1 · high · correctness
File: engine/resolve.gd:870
Claim: A commander who storms one land from two lands, or walks into an empty one, is collapsed to a single `Transit` before the take/scramble. The discarded column’s identity is gone, so its follow-on surge (and any other per-column booking keyed off that transit) never runs. Men stay on the taken land; totals still add up. Two attacks into Gate, surges to Beacon and Mill: only one surge fires. Occupied Gate is the same after the walls fall — the join keeps `f["t"]` from the first standing front and `continue`s the rest. Rules 20 melees that reach scramble also get a new `{t, a}` dict instead of the original front (this block is not gated on `map.rules >= 21`).
Evidence: After the defender is gone, surviving fronts are folded by owner into `{"t": f["t"], "a": ...}` and extras only add `a`. Empty-land path always does `invaders = _merge_same_owner(invaders)` then `_take(..., t1.strength)` from that one transit. `_resolve_surges` leaves packets unmerged for rules 21, then `_land_v14` merges them again when the dest is empty. `test_v21` walk-in and two-front cases have no surges; `_conserved` / `_view_agrees` stay green if the men simply never leave.
Fix: Collapse only the combat side (one stack per owner for scramble/spoils). Book surges and the take from every standing front’s own transit (or copy the full first front and keep a list of origins/`fromIds`). Gate the empty-land merge and the post-melee join with `map.rules >= 21`, and `alive.append(f)` for the first front so rules ≤20 still pass the original dict into scramble.

### F2 · medium · correctness
File: game/world3d/diorama.gd:645
Claim: Battle-train horse and guns are `counts=false` and skipped by `_cull`. Nothing in the diff knocks them down when the army’s count hits 0, so a wiped army still shows its horsemen and guns. The changelog/playtest claim they “fall only when the army does”; `v21` only checks the train still standing after three exchanges, never a rout.
Evidence: `_form` marks extras `counts=false`; `_cull` filters `bool(f["counts"])`. No new rout/wipe of non-counting figs. `battle_train` comment restates the claim the code does not implement.
Fix: When an army’s counting pieces hit 0 (or `n` hits 0), topple every fig in that army, including `counts=false`. Keep `_cull` from treating the train as casualties.

### F3 · medium · ux
File: game/board/map_board.gd:200
Claim: A region won in the report, then lost again in the same report, keeps flaring in the old holder’s colours until `REGION_FX` (1.8s) expires. Playtest calls out this sequence.
Evidence: `_region_fx` is set only when `holder != ""` and the holder changed. When the set breaks, `holder` is `""`, so no new fx and the old `_region_fx` is not cleared; `_draw_region_labels` still reads `_region_fx[r]["owner"]` while `region_won` is ≥ 0.
Fix: Clear `_region_fx[r]` (and `_region_seen[r]`) whenever `holder` is empty or no longer that owner, not only when a new holder appears.
