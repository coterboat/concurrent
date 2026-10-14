CANARY: workspace/environment and tool context are visible beyond the packet.

### F1 · high · correctness
File: engine/resolve.gd:773  
Claim: When an invader spends Fortune in a melee against an occupied defender, the rebate is awarded to the invader who spent it, while the defender receives nothing.  
Evidence: The attacker-spend branch says the defender is owed, but writes `rebate[pid]`; `pid` is the commander making the Fortune call.  
Fix: Write the amount to `rebate[defender]`, and add a test where an invader spends that asserts the defender alone receives it.

### F2 · high · ux
File: game/world3d/land_field.gd:46  
Claim: Front names can survive into the next battle. After a melee labels army 0 “from Ridge,” a following ordinary assault can show that stale name on its unrelated army-0 plate.  
Evidence: `_tags` persists on the reused `LandField`; `set_tag()` adds entries and `_make_plates()` reads them, but no engagement, abort, or close path clears `_tags`. `_wipe_words()` only clears the tray’s `_marks`.  
Fix: Clear all field tags before every engagement and on abort/close, updating any existing plate labels immediately.

### F3 · medium · ux
File: game/ui/battle_theater.gd:1107  
Claim: Free-for-all dice are not laid out in field order, despite the stated melee-or-free-for-all behavior. A three-army scramble whose salvo order differs from its screen order leaves pairs right-to-left while their tags point elsewhere.  
Evidence: `_in_field_order()` returns unchanged pairs whenever `not _melee`; `_scramble` is never accepted. The v2.2 probe exercises only a melee.  
Fix: Define and apply a stable screen-order key for scramble pairs too, and probe a scramble whose event order intentionally differs from field order.

### F4 · medium · correctness
File: game/ui/battle_theater.gd:1808  
Claim: In a melee with multiple Fortune calls, the narration can name commanders owed by an earlier call as victims of the current call. For example, after the defender owes red and green, a later red call can incorrectly say green is owed for red’s exchange.  
Evidence: `_show_call()` reads the battle-wide aggregated `_event()["rebate"]` for every individual call and merely excludes the current spender; rebate data is not attached to its originating call.  
Fix: Store each exchange’s recipients and amounts on that Fortune call entry, while retaining the aggregate only for upkeep; narrate from the call-local data.

### F5 · medium · correctness
File: game/world3d/diorama.gd:559  
Claim: A casualty can fall before any musket ball arrives. With all firing-animation random delays near 0.16 seconds, `_shot_at` still uses the undelayed group-center estimate, while tracers start later and may travel farther to randomized aims.  
Evidence: `_shot_at` is set from `_clock + 0.22 + _flight(reach)`, but each shooter later receives `f["t"] = -randf() * 0.16`; actual tracer duration is separately calculated from muzzle to randomized target.  
Fix: Derive the casualty time from the earliest actual tracer’s recorded muzzle time plus its real duration, or trigger the casualty from the first matching tracer-impact callback.
