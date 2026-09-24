## Shared builders for queue fixtures. No Node.
extends RefCounted

const Types := preload("res://engine/types.gd")
const Resolve := preload("res://engine/resolve.gd")
const Hash := preload("res://engine/hash.gd")
const Income := preload("res://engine/income.gd")
const Validate := preload("res://engine/validate.gd")

const COLORS := {
	"red": "#c23b2e",
	"green": "#2e8b57",
	"blue": "#2e5aa6",
	"neutral": "#6b6560",
}


static func knife7() -> Types.MapDef:
	return Types.MapDef.from_file("res://maps/knife7.json")


static func player(id: String) -> Types.PlayerState:
	var p := Types.PlayerState.new()
	p.id = id
	p.display_name = id.capitalize()
	p.color = COLORS.get(id, "#888888")
	p.alive = true
	return p


static func paint(map: Types.MapDef, hexes: Dictionary, extra_players: Array = []) -> Types.World:
	var w: Types.World = Types.World.empty_from_map(map)
	w.round = 1
	var needed := {}
	for terr_id in hexes.keys():
		var pair: Array = hexes[terr_id]
		var owner: String = str(pair[0])
		var armies: int = int(pair[1])
		w.set_hex(str(terr_id), owner, armies)
		if owner != Types.UNOCCUPIED:
			needed[owner] = true
	for pid in extra_players:
		needed[str(pid)] = true
	var pids: Array = needed.keys()
	pids.sort()
	for pid in pids:
		w.players[pid] = player(pid)
	return w


static func pkt(from_id: String, to_id: String, strength: int, surge_to: String = "") -> Types.Packet:
	var p := Types.Packet.new()
	p.from_id = from_id
	p.to_id = to_id
	p.strength = strength
	p.surge_to = surge_to
	return p


static func sheet(player_id: String, packets: Array = [], placements: Dictionary = {}, regroup = null) -> Types.Sheet:
	var s := Types.Sheet.new()
	s.player_id = player_id
	s.packets = packets
	s.placements = placements
	s.regroup = regroup
	return s


static func resolve(world: Types.World, map: Types.MapDef, sheets: Array, seed: int = 1) -> Dictionary:
	return Resolve.resolve_round(world, map, sheets, seed)


static func kinds(events: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for e in events:
		out.append(str(e.get("kind", "")))
	return out


static func first(events: Array, kind: String) -> Dictionary:
	for e in events:
		if str(e.get("kind", "")) == kind:
			return e
	return {}


static func all_of(events: Array, kind: String) -> Array:
	var out: Array = []
	for e in events:
		if str(e.get("kind", "")) == kind:
			out.append(e)
	return out


static func index_of_kind(events: Array, kind: String) -> int:
	for i in events.size():
		if str(events[i].get("kind", "")) == kind:
			return i
	return -1


static func owner_of(world: Types.World, terr_id: String) -> String:
	var ts: Types.TerritoryState = world.get_territory(terr_id)
	return ts.owner if ts else ""


static func armies_of(world: Types.World, terr_id: String) -> int:
	var ts: Types.TerritoryState = world.get_territory(terr_id)
	return ts.armies if ts else -1
