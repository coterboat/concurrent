I'll review the packet against the diff, starting with the rest of the change and the review instructions.The packet is split. I'll read the rest of the diff and check rules-21 fronts, older-save replay, and conservation.CANARY: not packet-only. This session has tools and a workspace that holds the packet, not the game repository.

### F1 · high · correctness
File: game/board/map_board.gd:909
Claim: A rules 20 two-column attack draws the merged army and one of the columns again. Ridge 9 and Harbor 9 into The Gate, with The Gate marching on Ridge, is one clash of 18. `clash_sides` paints 18 on the Ridge–Gate arrow, and `clash_hides` only suppresses that pair, so Harbor→Gate stays on the board at 9 until the dice land. Through the charge, and for a whole watched battle, the map shows 27. The v202 rules-20 probe only asserts the clash arrow’s 18.
Evidence: `clash_hides` returns true only for `(clash_fx.a, clash_fx.b)`. `clash_sides` stores `sizeA`/`sizeB` (18 under rules 20, per `tests/test_v21.gd` and `tools/shots/v202.gd`). `cinema.gd` still appends every packet to `board.orders`, and `_settle_arrows` drops the sibling only once the outcome is applied (`one_column` is false below rules 21, and the order it keeps is the first packet, not the column on that border).
Fix: Whenever the number on a clash comes from a merged army, hide every order of that commander bound for the contested land for the whole telling, and carry the survivors on the border column. One merged stack must not also be drawn as its parts.

### F2 · medium · correctness
File: game/ui/battle_theater.gd:738
Claim: A melee that is not all one commander is still titled as one army per front. Dad from Ridge and Harbor plus Ysolde from Beacon is three fronts and two commanders; the battle subtitle is "3 armies storm it at once". The report caption was updated (`_melee_names` / "from two sides"), and this line was only special-cased when `_one_commander()` is true.
Evidence: The `else` branch still does `"%d armies storm it at once" % _fronts.size()`. `_one_commander()` is false as soon as any front has a different `attackerId`.
Fix: Count distinct commanders everywhere a melee is called a number of armies (this subtitle, and the odds line’s attacker count if that is also a front count). Name a second front of someone already shown the way the one-commander branch already does.
