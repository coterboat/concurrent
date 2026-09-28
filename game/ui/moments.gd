## v1.13: the war's big moments, found in what the engine already reports, so the battlefield,
## the battle report and the war table can play them harder. Detection only: pure functions of
## the events, the odds and the score history (no Node, no sound); the callers stage them.
##   upset:        the winner had less than an UPSET chance when the fight began
##   last man:     one man left standing, and he won
##   lead change:  the sole leader on points is someone new after a round
##   retaken:      a commander marches back into a capital they lost
extends RefCounted

const Types := preload("res://engine/types.gd")
const Combat := preload("res://engine/combat.gd")

const UPSET := 0.3 ## the winner's chance, before the fight, below which it was against the odds


static func winner_chance(invasion: bool, a0: int, d0: int, a_won: bool, fort: int = 0) -> float:
	## what the side that won was given before the first volley (the odds bar's number)
	var p: float = Combat.capture_rate(a0, d0, Combat.MODE_VOLLEYS, fort) if invasion else Combat.volley_capture_rate(a0, d0, true)
	return p if a_won else 1.0 - p


static func upset(invasion: bool, a0: int, d0: int, a_won: bool, fort: int = 0) -> bool:
	return a0 > 0 and d0 > 0 and winner_chance(invasion, a0, d0, a_won, fort) < UPSET


static func leader(scores: Dictionary) -> String:
	## the sole leader on points ("" when two or more share the top)
	var best := -1
	var who := ""
	var tied := false
	for pid in scores.keys():
		var sc: int = int(scores[pid])
		if sc > best:
			best = sc
			who = str(pid)
			tied = false
		elif sc == best:
			tied = true
	return "" if tied else who


static func lead_change(history: Array) -> Dictionary:
	## {from, to} when the round just scored put a new sole leader on top ({} otherwise). A lead
	## that was shared before counts as a change only if someone now holds it alone.
	if history.size() < 2:
		return {}
	var before: String = leader(history[history.size() - 2].get("score", {}))
	var now: String = leader(history[history.size() - 1].get("score", {}))
	if now == "" or now == before:
		return {}
	return {"from": before, "to": now}


static func retaken(events: Array, capital_log: Array) -> Array:
	## [{land, pid, round}]: a commander marched back into a capital they had lost
	var out: Array = []
	for e in events:
		if str(e.get("kind", "")) != Types.EVENT_OCCUPIED:
			continue
		var land: String = str(e.get("terrId", ""))
		var pid: String = str(e.get("playerId", ""))
		for c in capital_log:
			if str(c.get("land", "")) == land and str(c.get("pid", "")) == pid:
				out.append({"land": land, "pid": pid, "round": int(c.get("round", 0))})
				break
	return out
