## Ugly status board. Couch-readable counts. No Node in engine/.
extends RefCounted

const Types := preload("res://engine/types.gd")
const MapLib := preload("res://engine/map.gd")
const Income := preload("res://engine/income.gd")
const Combat := preload("res://engine/combat.gd")

const LAYOUT := [
	"        beacon — ridge — mill",
	"                   |",
	"                 gate",
	"              /    |    \\",
	"         harbor    |    quarry",
	"              \\    |    /",
	"                docks",
]


static func render(world: Types.World, map: Types.MapDef, viewer_id: String = "red") -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("The Isthmus  round %s  hash %s" % [world.round, _short_hash(world)])
	for row in LAYOUT:
		lines.append(row)
	lines.append("")
	var ids: Array = Array(map.territory_ids())
	for terr_id in ids:
		lines.append(_hex_line(world, map, terr_id, viewer_id))
	if viewer_id != "" and viewer_id != Income.NEUTRAL_ID:
		var inc: int = Income.income_of(world, map, viewer_id)
		lines.append("")
		lines.append("%s income %s   (unused is lost)" % [viewer_id, inc])
	return "\n".join(lines)


static func render_events(events: Array) -> String:
	var lines: PackedStringArray = PackedStringArray()
	for e in events:
		var kind: String = str(e.get("kind", ""))
		match kind:
			Types.EVENT_VACATED:
				lines.append("  vacate  %s %s -> %s  %s  left %s" % [e.get("playerId"), e.get("from"), e.get("to"), e.get("strength"), e.get("originRemaining")])
			Types.EVENT_CLASH:
				lines.append("  clash   %s %s vs %s %s  dice %s-%s  %s keeps %s" % [e.get("playerA"), e.get("sizeA"), e.get("playerB"), e.get("sizeB"), e.get("dieA"), e.get("dieB"), e.get("winnerId"), e.get("winnerRemaining")])
			Types.EVENT_INVASION:
				var word: String = Combat.odds_word(int(e.get("attackerSize", 1)), int(e.get("defenderSize", 1)))
				lines.append("  invade  %s %s -> %s  %s vs %s (%s)  dice %s-%s  %s" % [e.get("attackerId"), e.get("from"), e.get("to"), e.get("attackerSize"), e.get("defenderSize"), word, e.get("attackerDie"), e.get("defenderDie"), "takes" if e.get("attackerWon") else "holds"])
			Types.EVENT_SPOILS:
				lines.append("  spoils  %s at %s  %s vs %s  %s keeps %s" % [e.get("to"), e.get("to"), e.get("playerA"), e.get("playerB"), e.get("winnerId"), e.get("winnerRemaining")])
			Types.EVENT_SURGE:
				lines.append("  surge   %s %s -> %s  %s  left %s" % [e.get("playerId"), e.get("from"), e.get("to"), e.get("strength"), e.get("originRemaining")])
			Types.EVENT_OCCUPIED:
				lines.append("  occupy  %s %s with %s" % [e.get("playerId"), e.get("terrId"), e.get("armies")])
			Types.EVENT_PLACED:
				lines.append("  place   %s %s +%s  now %s  overflow %s" % [e.get("playerId"), e.get("terrId"), e.get("added"), e.get("armies"), e.get("overflow")])
			Types.EVENT_REGROUP_APPLIED:
				lines.append("  regroup %s %s -> %s  %s" % [e.get("playerId"), e.get("from"), e.get("to"), e.get("strength")])
			Types.EVENT_SCORE:
				lines.append("  score   %s  leader %s" % [e.get("scores"), e.get("leader")])
			Types.EVENT_ROUND_ENDED:
				var w: String = str(e.get("winner", ""))
				if w != "":
					lines.append("  end     round %s  winner %s%s" % [e.get("round"), w, " (early)" if e.get("early") else ""])
			Types.EVENT_PLAYER_ELIMINATED:
				lines.append("  out     %s" % e.get("playerId"))
			_:
				pass
	return "\n".join(lines)


static func render_sheet(sheet: Types.Sheet) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("sheet %s" % sheet.player_id)
	if sheet.regroup != null:
		lines.append("  regroup %s -> %s %s" % [sheet.regroup.from_id, sheet.regroup.to_id, sheet.regroup.strength])
	var keys: Array = sheet.placements.keys()
	keys.sort()
	for k in keys:
		lines.append("  place %s %s" % [k, sheet.placements[k]])
	for p in sheet.packets:
		var pkt: Types.Packet = p
		var surge := ""
		if pkt.surge_to != "":
			surge = " surge %s" % pkt.surge_to
		lines.append("  attack %s -> %s %s%s" % [pkt.from_id, pkt.to_id, pkt.strength, surge])
	if keys.is_empty() and sheet.packets.is_empty() and sheet.regroup == null:
		lines.append("  (hold)")
	return "\n".join(lines)


static func _hex_line(world: Types.World, map: Types.MapDef, terr_id: String, viewer_id: String) -> String:
	var ts: Types.TerritoryState = world.get_territory(terr_id)
	var t: Types.TerritoryDef = map.get_territory(terr_id)
	var owner: String = ts.owner if ts.owner != Types.UNOCCUPIED else "—"
	var n: int = ts.armies
	var extra := ""
	if ts.owner == viewer_id:
		extra = "  cap %s" % Income.cap_of(world, map, terr_id)
	elif ts.owner != Types.UNOCCUPIED:
		var cap: int = Income.cap_of(world, map, terr_id)
		extra = "  max %s" % (n + cap)
	var name: String = t.display_name if t else terr_id
	return "  %-8s %-7s %2s%s" % [terr_id, owner, n, extra]


static func _short_hash(world: Types.World) -> String:
	var Hash := load("res://engine/hash.gd")
	return Hash.world_hash(world)
