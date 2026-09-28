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
const EVENT_MELEE := "Melee" ## v1.3: several invaders storm one land at once
const EVENT_MANEUVERED := "Maneuvered" ## v1.3: a move in the regroup phase
const EVENT_CAPITAL_TAKEN := "CapitalTaken" ## v1.8: a commander's capital fell (the captor plunders it)
const EVENT_CAPITAL_FOUNDED := "CapitalFounded"
const EVENT_FORTUNE := "FortuneGained" ## v1.8: Fortune pays a favour she owes (engine/fortune.gd) ## v1.8: a capital named (at deployment, or anew after a fall)
const EVENT_SCRAMBLE := "Scramble" ## v1.4: three or more (or two) armies of different commanders fight for one prize at once

const UNOCCUPIED := ""


class TerritoryDef extends RefCounted:
	var id: String = ""
	var display_name: String = ""
	var region: String = ""
	var adjacent: PackedStringArray = PackedStringArray()
	var traits: PackedStringArray = PackedStringArray() ## v1.7: "fort", "port", "pass"

	func has_trait(t: String) -> bool:
		return Array(traits).has(t)


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
	var wild_cards: bool = true ## v1.3 new games: false (men, horses, cannon only); the session sets it
	var maneuvers: bool = false ## v1.3 new games: true (a regroup phase after the battles)
	var scramble: bool = false ## v1.4 new games: true (spoils are one free-for-all, not a ladder of duels)
	var dig_cap: int = 0 ## v1.4 new games: 2 (v1.5: 3) (no land digs in deeper); 0 = the old ceiling of 1 + neighbours
	var rules: int = 0: ## v1.5 new games: 15 (surges clash head-on and carry a count)
		set(v):
			rules = v
			_amend() ## v1.12: the map as it stood under these rules
	## v1.12: a map can be amended from a rules version on (a new sea lane, a region's bonus), so a
	## save replays on the map it was played on. [{since, lanes: [[a, b]], regionBonus: {id: n}}]
	var amendments: Array = []
	var _base_bonus := {}
	var fire_line: bool = false ## v1.6 new games: at most five men fire in a volley, even volleys are fired again (setup: Battle odds)
	var first_digs_in: bool = false ## the man left behind is locked in as a dug-in defender for good (tried in v1.5; off: it halved the conquests)
	## v1.7 land traits and supply. Off unless the map asks for them, so the first three
	## maps play exactly as they did in v1.6 and old saves are untouched.
	## A pip is worth five men, so a line of six through nine all score the same against a
	## line of five: one is the whole effect, and the tenth man would be the next step.
	var fort_bonus: int = 1 ## extra men in a fortress's defending line (and +1 to its dig-in cap)
	var pass_cap: int = 6 ## most men in one attacking column into a pass (0 = no cap)
	var supply: bool = false ## lands cut off from your main bloc pay no income and take no recruits
	var dominate: float = 0.0 ## v1.8: share of the map that wins at once (0 = the usual four-fifths)
	var levee: int = 0 ## v1.8 levée en masse: a recruit for every this-many lands you trail the leader by (0 = off)
	var surges: bool = true ## v1.8: false = no surge orders (setup: Rules → Surges)
	var capitals: bool = false ## v1.8 new games: every commander keeps a capital (setup: Capitals)
	var fortune: bool = false ## v1.8 new games: bad luck banks favours that throw a bad exchange again (setup: Fortune)

	func territory_ids() -> PackedStringArray:
		var ids: Array = territories.keys()
		ids.sort()
		var out := PackedStringArray()
		for k in ids:
			out.append(str(k))
		return out

	func get_territory(terr_id: String) -> TerritoryDef:
		return territories.get(terr_id, null)

	func _amend() -> void:
		## Put the map back as drawn, then apply every amendment these rules have reached, oldest
		## first. Runs whenever `rules` is set; the same rules always give the same map.
		if amendments.is_empty():
			return
		for a in amendments:
			for pair in a.get("lanes", []):
				_link(str(pair[0]), str(pair[1]), false)
		for r in _base_bonus.keys():
			region_bonus[r] = int(_base_bonus[r])
		for a in amendments:
			if rules < int(a.get("since", 0)):
				continue
			for pair in a.get("lanes", []):
				_link(str(pair[0]), str(pair[1]), true)
			var rb: Dictionary = a.get("regionBonus", {})
			for r in rb.keys():
				if not _base_bonus.has(r):
					_base_bonus[r] = int(region_bonus.get(r, 0))
				region_bonus[r] = int(rb[r])

	func _link(x: String, y: String, on: bool) -> void:
		var tx: TerritoryDef = territories.get(x, null)
		var ty: TerritoryDef = territories.get(y, null)
		if tx == null or ty == null:
			return
		for pr in [[tx, y], [ty, x]]:
			var t: TerritoryDef = pr[0]
			var at: int = Array(t.adjacent).find(pr[1])
			if on and at < 0:
				t.adjacent.append(pr[1])
			elif not on and at >= 0:
				t.adjacent.remove_at(at)

	func lane_live(a: String, b: String) -> bool:
		## a sea lane an amendment added is only there under the rules that added it
		for am in amendments:
			for pair in am.get("lanes", []):
				if (str(pair[0]) == a and str(pair[1]) == b) or (str(pair[0]) == b and str(pair[1]) == a):
					return rules >= int(am.get("since", 0))
		return true

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
				var tr: Variant = raw.get("traits", [])
				if typeof(tr) == TYPE_ARRAY:
					for n in tr:
						t.traits.append(str(n))
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
		m.fort_bonus = int(data.get("fortBonus", 1))
		m.pass_cap = int(data.get("passCap", 6))
		m.supply = bool(data.get("supply", false))
		m.dominate = float(data.get("dominate", 0.0))
		m.levee = int(data.get("levee", 0))
		var am: Variant = data.get("amendments", [])
		if typeof(am) == TYPE_ARRAY:
			m.amendments = am.duplicate(true)
			m.amendments.sort_custom(func(x, y): return int(x.get("since", 0)) < int(y.get("since", 0)))
			## remember every amended bonus as drawn, before any rules touch it
			for a in m.amendments:
				for r in (a.get("regionBonus", {}) as Dictionary).keys():
					if not m._base_bonus.has(r):
						m._base_bonus[r] = int(m.region_bonus.get(r, 0))
			m._amend()
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
	var capital: String = "" ## v1.8: the seat of government ("" = none, or capitals are off)
	var capital_free: bool = false ## v1.8: it fell last round; a new one may be chosen this round
	var fortune: int = 0 ## v1.8: favours in hand (✦)
	var fortune_meter: int = 0 ## v1.8: Fortune's ledger, in hundredths of a battle (100 owes a favour)

	func to_dict() -> Dictionary:
		var d := {
			"name": display_name,
			"color": color,
			"cards": Array(cards),
			"alive": alive,
		}
		## only when set, so worlds from before v1.8 hash exactly as they did
		if capital != "":
			d["capital"] = capital
		if capital_free:
			d["capitalFree"] = true
		if fortune != 0:
			d["fortune"] = fortune
		if fortune_meter != 0:
			d["fortuneMeter"] = fortune_meter
		return d

	func clone() -> PlayerState:
		var p := PlayerState.new()
		p.id = id
		p.display_name = display_name
		p.color = color
		p.cards = cards.duplicate()
		p.alive = alive
		p.capital = capital
		p.capital_free = capital_free
		p.fortune = fortune
		p.fortune_meter = fortune_meter
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
					ps.capital = str(raw.get("capital", ""))
					ps.capital_free = bool(raw.get("capitalFree", false))
					ps.fortune = int(raw.get("fortune", 0))
					ps.fortune_meter = int(raw.get("fortuneMeter", 0))
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
	var surges: Dictionary = {} ## v1.3: land being attacked -> land to surge into (the whole force that takes it)
	var surge_n: Dictionary = {} ## v1.5: land being attacked -> most men to push on (absent = all but the one who stays)
	var capital: String = "" ## v1.8: a new capital, chosen the round after the old one fell
	var fortune_auto: bool = false ## v1.8: officers may call on Fortune by doctrine (AI sheets); a human's favours are theirs to spend

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
		if capital != "":
			d["capital"] = capital
		if fortune_auto:
			d["fortuneAuto"] = true
		if not surges.is_empty():
			var sg := {}
			var sk: Array = surges.keys()
			sk.sort()
			for k in sk:
				sg[str(k)] = str(surges[k])
			d["surges"] = sg
		if not surge_n.is_empty():
			var sn := {}
			var nk: Array = surge_n.keys()
			nk.sort()
			for k in nk:
				sn[str(k)] = int(surge_n[k])
			d["surgeN"] = sn
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
		var surges_raw: Variant = data.get("surges", {})
		if typeof(surges_raw) == TYPE_DICTIONARY:
			for k in surges_raw.keys():
				s.surges[str(k)] = str(surges_raw[k])
		s.capital = str(data.get("capital", ""))
		s.fortune_auto = bool(data.get("fortuneAuto", false))
		var sn_raw: Variant = data.get("surgeN", {})
		if typeof(sn_raw) == TYPE_DICTIONARY:
			for k in sn_raw.keys():
				s.surge_n[str(k)] = int(sn_raw[k])
		var calls_raw: Variant = data.get("calls", {})
		if typeof(calls_raw) == TYPE_DICTIONARY:
			for k in calls_raw.keys():
				var arr: Array = []
				if typeof(calls_raw[k]) == TYPE_ARRAY:
					for c in calls_raw[k]:
						arr.append(str(c))
				s.calls[str(k)] = arr
		return s
