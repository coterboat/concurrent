## Engine types. No Node. No UI. No unseeded RNG.
## Field names in to_dict() match the v0.2 bible contract (camelCase).
class_name EngineTypes
extends RefCounted

const CARD_SUN := "sun"
const CARD_MOON := "moon"
const CARD_STAR := "star"
const CARD_WILD := "wild"

const EVENT_REGROUP_APPLIED := "RegroupApplied"
const EVENT_PLACED := "Placed"
const EVENT_VACATED := "Vacated"
const EVENT_CLASH := "Clash"
const EVENT_INVASION := "Invasion"
const EVENT_SPOILS := "Spoils"
const EVENT_SURGE := "Surge"
const EVENT_OCCUPIED := "Occupied"
const EVENT_BECAME_UNOCCUPIED := "BecameUnoccupied"
const EVENT_CARD_DRAWN := "CardDrawn"
const EVENT_PLAYER_ELIMINATED := "PlayerEliminated"
const EVENT_SCORE := "Score"
const EVENT_ROUND_ENDED := "RoundEnded"
const EVENT_ENTRENCHED := "Entrenched"
const EVENT_SET_CASHED := "SetCashed"
const EVENT_CARDS_CAPTURED := "CardsCaptured"

const UNOCCUPIED := ""


class TerritoryDef extends RefCounted:
	var id: String = ""
	var display_name: String = ""
	var region: String = ""
	var adjacent: PackedStringArray = PackedStringArray()


class MapDef extends RefCounted:
	var id: String = ""
	var display_name: String = ""
	var territories: Dictionary = {} ## String -> TerritoryDef
	var region_bonus: Dictionary = {} ## String -> int
	var region_names: Dictionary = {} ## String -> String
	var layout: Dictionary = {} ## String -> Vector2
	var rounds: int = 0
	var starting_pool: int = 0
	var deal_each: int = 0
	var pin_neutral: String = ""
	var neutral_armies: int = 5
	var neutral_leftover: bool = true
	var cards: bool = false
	var neutral_leftover_armies: int = 1
	var min_players: int = 2
	var max_players: int = 5
	var blurb: String = ""
	var battle: String = "decisive" ## "decisive" | "volleys"; the session may override
	var region_colors: Dictionary = {} ## region -> "#rrggbb"
	var region_terrain: Dictionary = {} ## region -> battlefield key
	var pools: Dictionary = {} ## player count (int) -> starting pool

	func territory_ids() -> PackedStringArray:
		var ids: Array = territories.keys()
		ids.sort()
		var out := PackedStringArray()
		for k in ids:
			out.append(str(k))
		return out

	func get_territory(terr_id: String) -> TerritoryDef:
		return territories.get(terr_id, null)

	func is_adjacent(a: String, b: String) -> bool:
		var ta: TerritoryDef = territories.get(a, null)
		if ta == null:
			return false
		return Array(ta.adjacent).has(b)

	static func from_file(path: String) -> MapDef:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			push_error("Cannot open map %s (err %s)" % [path, FileAccess.get_open_error()])
			return null
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("Map JSON is not an object: %s" % path)
			return null
		return from_dict(parsed)

	static func from_dict(data: Dictionary) -> MapDef:
		var m := MapDef.new()
		m.id = str(data.get("id", ""))
		m.display_name = str(data.get("name", m.id))
		var terrs: Variant = data.get("territories", {})
		if typeof(terrs) == TYPE_DICTIONARY:
			for terr_id in terrs.keys():
				var raw: Variant = terrs[terr_id]
				if typeof(raw) != TYPE_DICTIONARY:
					continue
				var t := TerritoryDef.new()
				t.id = str(terr_id)
				t.display_name = str(raw.get("name", terr_id))
				t.region = str(raw.get("region", ""))
				var adj: Variant = raw.get("adjacent", [])
				if typeof(adj) == TYPE_ARRAY:
					for n in adj:
						t.adjacent.append(str(n))
				m.territories[t.id] = t
		var bonuses: Variant = data.get("regionBonus", {})
		if typeof(bonuses) == TYPE_DICTIONARY:
			for region_id in bonuses.keys():
				m.region_bonus[str(region_id)] = int(bonuses[region_id])
		var rnames: Variant = data.get("regionNames", {})
		if typeof(rnames) == TYPE_DICTIONARY:
			for region_id in rnames.keys():
				m.region_names[str(region_id)] = str(rnames[region_id])
		var lay: Variant = data.get("layout", {})
		if typeof(lay) == TYPE_DICTIONARY:
			for terr_id in lay.keys():
				var xy: Variant = lay[terr_id]
				if typeof(xy) == TYPE_ARRAY and xy.size() >= 2:
					m.layout[str(terr_id)] = Vector2(float(xy[0]), float(xy[1]))
		m.rounds = int(data.get("rounds", 0))
		m.starting_pool = int(data.get("startingPool", 0))
		m.deal_each = int(data.get("dealEach", 0))
		m.pin_neutral = str(data.get("pinNeutral", ""))
		m.neutral_armies = int(data.get("neutralArmies", 5))
		m.neutral_leftover = bool(data.get("neutralLeftover", m.id == "knife7"))
		m.cards = bool(data.get("cards", false))
		m.neutral_leftover_armies = int(data.get("neutralLeftoverArmies", 1))
		m.min_players = int(data.get("minPlayers", 2))
		m.max_players = int(data.get("maxPlayers", 5))
		m.blurb = str(data.get("blurb", ""))
		m.battle = str(data.get("battle", "decisive"))
		var rc: Variant = data.get("regionColors", {})
		if typeof(rc) == TYPE_DICTIONARY:
			m.region_colors = rc
		var rt: Variant = data.get("regionTerrain", {})
		if typeof(rt) == TYPE_DICTIONARY:
			m.region_terrain = rt
		var pools: Variant = data.get("pools", {})
		if typeof(pools) == TYPE_DICTIONARY:
			for k in pools.keys():
				m.pools[int(str(k))] = int(pools[k])
		return m


class TerritoryState extends RefCounted:
	var owner: String = EngineTypes.UNOCCUPIED
	var armies: int = 0 ## mobile. Marches, attacks, places.
	var garrison: int = 0 ## dug-in. Never marches. Holds the hex.

	func to_dict() -> Dictionary:
		var owner_val: Variant = null if owner == EngineTypes.UNOCCUPIED else owner
		var d := {"owner": owner_val, "armies": armies}
		if garrison > 0:
			d["garrison"] = garrison
		return d

	func clone() -> TerritoryState:
		var t := TerritoryState.new()
		t.owner = owner
		t.armies = armies
		t.garrison = garrison
		return t

	func held() -> int:
		return armies + garrison


class PlayerState extends RefCounted:
	var id: String = ""
	var display_name: String = ""
	var color: String = ""
	var cards: PackedStringArray = PackedStringArray()
	var alive: bool = true

	func to_dict() -> Dictionary:
		return {
			"name": display_name,
			"color": color,
			"cards": Array(cards),
			"alive": alive,
		}

	func clone() -> PlayerState:
		var p := PlayerState.new()
		p.id = id
		p.display_name = display_name
		p.color = color
		p.cards = cards.duplicate()
		p.alive = alive
		return p


class World extends RefCounted:
	var map_id: String = ""
	var round: int = 0
	var territories: Dictionary = {} ## String -> TerritoryState
	var players: Dictionary = {} ## String -> PlayerState
	var sets_cashed: int = 0

	func get_territory(terr_id: String) -> TerritoryState:
		return territories.get(terr_id, null)

	func clone() -> World:
		var w := World.new()
		w.map_id = map_id
		w.round = round
		w.sets_cashed = sets_cashed
		for terr_id in territories.keys():
			var ts: TerritoryState = territories[terr_id]
			w.territories[str(terr_id)] = ts.clone()
		for pid in players.keys():
			var ps: PlayerState = players[pid]
			w.players[str(pid)] = ps.clone()
		return w

	func set_hex(terr_id: String, owner: String, armies: int, garrison: int = 0) -> void:
		var ts: TerritoryState = territories.get(terr_id, null)
		if ts == null:
			ts = TerritoryState.new()
			territories[terr_id] = ts
		if owner == EngineTypes.UNOCCUPIED or (armies < 1 and garrison < 1):
			ts.owner = EngineTypes.UNOCCUPIED
			ts.armies = 0
			ts.garrison = 0
		else:
			ts.owner = owner
			ts.armies = maxi(0, armies)
			ts.garrison = maxi(0, garrison)

	func to_dict() -> Dictionary:
		var terrs := {}
		var terr_ids: Array = territories.keys()
		terr_ids.sort()
		for terr_id in terr_ids:
			var ts: TerritoryState = territories[terr_id]
			terrs[str(terr_id)] = ts.to_dict()
		var pls := {}
		var pids: Array = players.keys()
		pids.sort()
		for pid in pids:
			var ps: PlayerState = players[pid]
			pls[str(pid)] = ps.to_dict()
		return {
			"mapId": map_id,
			"round": round,
			"territories": terrs,
			"players": pls,
			"setsCashed": sets_cashed,
		}

	static func from_dict(data: Dictionary) -> World:
		var w := World.new()
		w.map_id = str(data.get("mapId", ""))
		w.round = int(data.get("round", 1))
		w.sets_cashed = int(data.get("setsCashed", 0))
		var terrs: Variant = data.get("territories", {})
		if typeof(terrs) == TYPE_DICTIONARY:
			for terr_id in terrs.keys():
				var raw: Variant = terrs[terr_id]
				var ts := TerritoryState.new()
				if typeof(raw) == TYPE_DICTIONARY:
					var owner_val: Variant = raw.get("owner", null)
					if owner_val == null:
						ts.owner = EngineTypes.UNOCCUPIED
					else:
						ts.owner = str(owner_val)
					ts.armies = int(raw.get("armies", 0))
					ts.garrison = int(raw.get("garrison", 0))
				w.territories[str(terr_id)] = ts
		var pls: Variant = data.get("players", {})
		if typeof(pls) == TYPE_DICTIONARY:
			for pid in pls.keys():
				var raw: Variant = pls[pid]
				var ps := PlayerState.new()
				ps.id = str(pid)
				if typeof(raw) == TYPE_DICTIONARY:
					ps.display_name = str(raw.get("name", pid))
					ps.color = str(raw.get("color", ""))
					var cards: Variant = raw.get("cards", [])
					if typeof(cards) == TYPE_ARRAY:
						for c in cards:
							ps.cards.append(str(c))
					ps.alive = bool(raw.get("alive", true))
				w.players[str(pid)] = ps
		return w

	static func empty_from_map(map: MapDef) -> World:
		var w := World.new()
		w.map_id = map.id
		w.round = 0
		w.sets_cashed = 0
		for terr_id in map.territory_ids():
			var ts := TerritoryState.new()
			ts.owner = EngineTypes.UNOCCUPIED
			ts.armies = 0
			ts.garrison = 0
			w.territories[terr_id] = ts
		return w


class Packet extends RefCounted:
	var from_id: String = ""
	var to_id: String = ""
	var strength: int = 0
	var surge_to: String = "" ## empty = none
	var stance: String = "" ## standing battle orders: "" / hold | careful | bold | judgment

	func to_dict() -> Dictionary:
		var d := {"from": from_id, "to": to_id, "strength": strength}
		if surge_to != "":
			d["surgeTo"] = surge_to
		if stance != "":
			d["stance"] = stance
		return d

	static func from_dict(data: Dictionary) -> Packet:
		var p := Packet.new()
		p.from_id = str(data.get("from", ""))
		p.to_id = str(data.get("to", ""))
		p.strength = int(data.get("strength", 0))
		p.surge_to = str(data.get("surgeTo", ""))
		p.stance = str(data.get("stance", ""))
		return p


class Regroup extends RefCounted:
	var from_id: String = ""
	var to_id: String = ""
	var strength: int = 0

	func to_dict() -> Dictionary:
		return {"from": from_id, "to": to_id, "strength": strength}

	static func from_dict(data: Dictionary) -> Regroup:
		var r := Regroup.new()
		r.from_id = str(data.get("from", ""))
		r.to_id = str(data.get("to", ""))
		r.strength = int(data.get("strength", 0))
		return r


class Sheet extends RefCounted:
	var player_id: String = ""
	var regroup: Regroup = null
	var cash_set: PackedStringArray = PackedStringArray()
	var placements: Dictionary = {} ## String -> int
	var packets: Array = [] ## Array of Packet
	var calls: Dictionary = {} ## battle key -> Array of calls made live ("p" press, "r" reserves, "f" fall back)

	func to_dict() -> Dictionary:
		var place := {}
		var keys: Array = placements.keys()
		keys.sort()
		for k in keys:
			place[str(k)] = int(placements[k])
		var pkts: Array = []
		for p in packets:
			pkts.append((p as Packet).to_dict())
		var d := {
			"playerId": player_id,
			"placements": place,
			"packets": pkts,
		}
		if regroup != null:
			d["regroup"] = regroup.to_dict()
		if cash_set.size() > 0:
			d["cashSet"] = Array(cash_set)
		if not calls.is_empty():
			var c := {}
			var ck: Array = calls.keys()
			ck.sort()
			for k in ck:
				c[str(k)] = Array(calls[k]).duplicate()
			d["calls"] = c
		return d

	static func from_dict(data: Dictionary) -> Sheet:
		var s := Sheet.new()
		s.player_id = str(data.get("playerId", ""))
		if data.has("regroup") and typeof(data["regroup"]) == TYPE_DICTIONARY:
			s.regroup = Regroup.from_dict(data["regroup"])
		var cash: Variant = data.get("cashSet", [])
		if typeof(cash) == TYPE_ARRAY:
			for c in cash:
				s.cash_set.append(str(c))
		var place: Variant = data.get("placements", {})
		if typeof(place) == TYPE_DICTIONARY:
			for k in place.keys():
				s.placements[str(k)] = int(place[k])
		var pkts: Variant = data.get("packets", [])
		if typeof(pkts) == TYPE_ARRAY:
			for raw in pkts:
				if typeof(raw) == TYPE_DICTIONARY:
					s.packets.append(Packet.from_dict(raw))
		var calls_raw: Variant = data.get("calls", {})
		if typeof(calls_raw) == TYPE_DICTIONARY:
			for k in calls_raw.keys():
				var arr: Array = []
				if typeof(calls_raw[k]) == TYPE_ARRAY:
					for c in calls_raw[k]:
						arr.append(str(c))
				s.calls[str(k)] = arr
		return s
