## Holds match_seed. Never writes it onto World. No Sprite2D in engine/.
extends Node

const Types := preload("res://engine/types.gd")
const Setup := preload("res://engine/setup.gd")
const Bot := preload("res://engine/bot.gd")
const MapLib := preload("res://engine/map.gd")
const Income := preload("res://engine/income.gd")
const Validate := preload("res://engine/validate.gd")
const Resolve := preload("res://engine/resolve.gd")
const Match := preload("res://engine/match.gd")
const Rng := preload("res://engine/rng.gd")
const ViewEvents := preload("res://game/view_events.gd")
const Telemetry := preload("res://engine/telemetry.gd")

enum Phase { TITLE, OPENING, HOTSEAT, PLANNING, CINEMA, RECAP, GAME_OVER }

signal changed

var match_seed: int = 0
var vs_monkey: bool = false
var teach: bool = false
var map: Types.MapDef
var world: Types.World
var phase: int = Phase.TITLE
var planner: String = "red"
var hotseat_for: String = ""
var opening := {"red": {}, "blue": {}}
var opening_done := {"red": false, "blue": false}
var sheets := {}
var locked := {"red": false, "blue": false}
var selected: String = ""
var draft: int = 1
var error_text: String = ""
var status_text: String = ""
var cinema_events: Array = []
var cinema_index: int = -1
var pre_lock: Types.World
var last_packets: Array = []
var recorded_sheets: Array = []
var setup_dict: Dictionary = {}
var hashes: Array = []
var winner: String = ""
var pending_surge_from: int = -1 ## packet index waiting for surge dest
var send_amount := {} ## from_id -> troops to send (1..N-1)
var telemetry_rounds: Array = []


func new_game(p_vs_monkey: bool, seed: int = 0, p_teach: bool = false, p_map_path: String = "res://maps/knife7.json") -> void:
	vs_monkey = p_vs_monkey
	teach = p_teach and not p_vs_monkey
	match_seed = seed if seed != 0 else int(Time.get_unix_time_from_system())
	map = Types.MapDef.from_file(p_map_path)
	world = Setup.deal_two_player(map, match_seed, true)
	planner = "red"
	opening = {"red": {}, "blue": {}}
	opening_done = {"red": false, "blue": false}
	sheets = {"red": _empty_sheet("red"), "blue": _empty_sheet("blue")}
	locked = {"red": false, "blue": false}
	selected = ""
	draft = 1
	error_text = ""
	status_text = ""
	cinema_events = []
	cinema_index = -1
	last_packets = []
	recorded_sheets = []
	setup_dict = {}
	hashes = []
	winner = ""
	pending_surge_from = -1
	send_amount = {}
	telemetry_rounds = []
	phase = Phase.OPENING
	_auto_select()
	changed.emit()


func view_world() -> Types.World:
	if phase == Phase.CINEMA and pre_lock != null:
		return ViewEvents.apply_through(pre_lock, cinema_events, cinema_index)
	if phase == Phase.OPENING or phase == Phase.PLANNING:
		return _display_world()
	return world


func _display_world() -> Types.World:
	var w: Types.World = world.clone()
	if phase == Phase.OPENING:
		var place: Dictionary = opening.get(planner, {})
		for terr_id in place.keys():
			var ts: Types.TerritoryState = w.get_territory(str(terr_id))
			if ts == null or ts.owner != planner:
				continue
			ts.armies += int(place[terr_id])
		return w
	var sheet: Types.Sheet = current_sheet()
	if sheet.regroup != null:
		var origin: Types.TerritoryState = w.get_territory(sheet.regroup.from_id)
		if origin != null and sheet.regroup.strength <= Income.max_send(origin):
			Validate._apply_regroup_to(w, sheet)
	Validate._apply_placements_to(w, map, sheet)
	for raw in sheet.packets:
		var p: Types.Packet = raw
		var ts: Types.TerritoryState = w.get_territory(p.from_id)
		if ts == null:
			continue
		var keep: int = 0 if ts.garrison >= 1 else 1
		ts.armies = maxi(keep, ts.armies - p.strength)
	return w


func display_armies(terr_id: String) -> int:
	var ts: Types.TerritoryState = view_world().get_territory(terr_id)
	return ts.armies if ts else 0


func current_sheet() -> Types.Sheet:
	return sheets.get(planner, _empty_sheet(planner))


func select_hex(terr_id: String) -> void:
	if phase != Phase.OPENING and phase != Phase.PLANNING:
		return
	if pending_surge_from >= 0:
		_try_surge(terr_id)
		return
	var ts: Types.TerritoryState = world.get_territory(terr_id)
	if ts == null:
		return
	if ts.owner == planner:
		if selected == terr_id:
			add_place(1)
			return
		if phase == Phase.PLANNING and selected != "" and MapLib.is_adjacent(map, selected, terr_id):
			if max_friendly_from(selected, terr_id) >= 1:
				_issue_friendly(selected, terr_id, send_for(selected))
				return
			error_text = friendly_block_reason(selected, terr_id)
			selected = terr_id
			draft = _default_draft(terr_id)
			changed.emit()
			return
		selected = terr_id
		draft = _default_draft(terr_id)
		error_text = ""
		changed.emit()
		return
	if phase == Phase.OPENING:
		error_text = "place on a hex you own"
		changed.emit()
		return
	if selected != "":
		_click_dest(terr_id)
		return


func add_place(delta: int) -> void:
	if selected == "":
		_auto_select()
	if selected == "":
		error_text = "you have no hex to place on"
		changed.emit()
		return
	add_place_on(selected, delta)


func add_place_on(terr_id: String, delta: int) -> void:
	if phase != Phase.OPENING and phase != Phase.PLANNING:
		return
	var ts: Types.TerritoryState = world.get_territory(terr_id)
	if ts == null or ts.owner != planner:
		error_text = "place on a hex you own"
		changed.emit()
		return
	selected = terr_id
	var cap: int = Income.cap_of(world, map, terr_id)
	if phase == Phase.OPENING:
		var cur: int = int(opening[planner].get(terr_id, 0))
		if delta > 0:
			if pool_left() <= 0:
				error_text = "pool empty — leftover is forfeit"
				changed.emit()
				return
			if cur >= cap:
				error_text = "%s cap is %s (1 + friendly neighbors)" % [terr_id, cap]
				changed.emit()
				return
		var nxt: int = maxi(0, mini(cap, cur + delta))
		if nxt == 0:
			opening[planner].erase(terr_id)
		else:
			opening[planner][terr_id] = nxt
		error_text = ""
		changed.emit()
		return
	var sheet: Types.Sheet = current_sheet()
	var cur2: int = int(sheet.placements.get(terr_id, 0))
	if delta > 0:
		if income_left() <= 0:
			error_text = "income spent — unused is lost"
			changed.emit()
			return
		if cur2 >= cap:
			error_text = "%s cap is %s" % [terr_id, cap]
			changed.emit()
			return
	var nxt2: int = maxi(0, mini(cap, cur2 + delta))
	if nxt2 == 0:
		sheet.placements.erase(terr_id)
	else:
		sheet.placements[terr_id] = nxt2
	error_text = ""
	_clamp_packets()
	changed.emit()


func hex_name(terr_id: String) -> String:
	if map == null:
		return terr_id
	var t: Types.TerritoryDef = map.get_territory(terr_id)
	return t.display_name if t else terr_id


func friendly_block_reason(from_id: String, to_id: String) -> String:
	var dest: String = hex_name(to_id)
	var origin: String = hex_name(from_id)
	if map == null or not MapLib.is_adjacent(map, from_id, to_id):
		return "%s is not next to %s" % [dest, origin]
	var from_ts: Types.TerritoryState = world.get_territory(from_id)
	var to_ts: Types.TerritoryState = world.get_territory(to_id)
	if from_ts == null or to_ts == null or from_ts.owner != planner or to_ts.owner != planner:
		return "move is friendly to friendly"
	var sheet: Types.Sheet = current_sheet()
	var from_q: int = int(sheet.placements.get(from_id, 0))
	var to_q: int = int(sheet.placements.get(to_id, 0))
	var cap: int = Income.cap_of(world, map, to_id)
	var room: int = maxi(0, cap - to_q)
	if world.round <= 1:
		if from_q < 1:
			return "round 1 has no regroup — place on %s instead of walking standing armies" % dest
		if room < 1:
			return "%s is at cap %s — minus there before walking from %s" % [dest, cap, origin]
		return "cannot walk %s → %s this round" % [origin, dest]
	if from_ts.armies < 2 and from_q < 1:
		return "must leave 1 on %s" % origin
	if from_q >= 1 and room < 1 and from_ts.armies < 2:
		return "%s is at cap %s" % [dest, cap]
	if from_ts.armies < 2:
		return "must leave 1 on %s — placed troops cannot regroup this round" % origin
	return "cannot walk %s → %s" % [origin, dest]


func attack_to(from_id: String, to_id: String) -> void:
	selected = from_id
	var idx: int = _packet_index(from_id, to_id)
	var mx: int = max_send_from(from_id, idx)
	var n: int = int(send_amount.get(from_id, mx))
	if mx >= 1:
		n = clampi(n, 1, mx)
	_issue_attack(from_id, to_id, n)


func regroup_to(from_id: String, to_id: String) -> void:
	selected = from_id
	var n: int = send_for(from_id)
	if n < 1:
		n = max_friendly_from(from_id, to_id)
	_issue_friendly(from_id, to_id, n)


func max_move_from(from_id: String) -> int:
	## Standing armies that can regroup. Round 1 has no regroup.
	## Dug-in hexes may send every mobile soldier.
	if world != null and world.round <= 1:
		return 0
	var ts: Types.TerritoryState = world.get_territory(from_id)
	if ts == null or ts.owner != planner:
		return 0
	return Income.max_send(ts)


func max_friendly_from(from_id: String, to_id: String) -> int:
	## How many can walk friendly-to-friendly right now.
	## Round 1: only queued placements (place on dest instead of origin).
	## Later rounds: those placements plus standing-minus-one as a regroup.
	if phase != Phase.PLANNING:
		return 0
	if map == null or not MapLib.is_adjacent(map, from_id, to_id):
		return 0
	var from_ts: Types.TerritoryState = world.get_territory(from_id)
	var to_ts: Types.TerritoryState = world.get_territory(to_id)
	if from_ts == null or to_ts == null:
		return 0
	if from_ts.owner != planner or to_ts.owner != planner:
		return 0
	var sheet: Types.Sheet = current_sheet()
	var from_q: int = int(sheet.placements.get(from_id, 0))
	var to_q: int = int(sheet.placements.get(to_id, 0))
	var room: int = maxi(0, Income.cap_of(world, map, to_id) - to_q)
	var place_part: int = mini(from_q, room)
	var stand_part: int = max_move_from(from_id)
	return place_part + stand_part


func nudge_send(from_id: String, delta: int) -> void:
	var mx: int = send_cap(from_id)
	if mx < 1:
		error_text = "must leave 1 on %s" % from_id
		changed.emit()
		return
	var cur: int = send_for(from_id)
	send_amount[from_id] = clampi(cur + delta, 1, mx)
	draft = send_amount[from_id]
	error_text = ""
	changed.emit()


func nudge_packet(index: int, delta: int) -> void:
	var sheet: Types.Sheet = current_sheet()
	if index < 0 or index >= sheet.packets.size():
		return
	var p: Types.Packet = sheet.packets[index]
	var mx: int = max_send_from(p.from_id, index)
	if mx < 1:
		return
	p.strength = clampi(p.strength + delta, 1, mx)
	if p.strength > mx:
		p.strength = mx
	error_text = ""
	changed.emit()


func send_for(from_id: String) -> int:
	var mx: int = send_cap(from_id)
	if mx < 1:
		return 0
	var v: int = int(send_amount.get(from_id, mx))
	return clampi(v, 1, mx)


func send_cap(from_id: String, skip_packet: int = -1) -> int:
	## Stepper ceiling: attack leftover, or a legal friendly walk, whichever is larger.
	var cap: int = max_send_from(from_id, skip_packet)
	if map == null:
		return cap
	for n in MapLib.neighbors(map, from_id):
		cap = maxi(cap, max_friendly_from(from_id, n))
	return cap


func max_send_from(from_id: String, skip_packet: int = -1) -> int:
	## Attacks may include just-placed armies. Dug-in hexes may send every mobile.
	var w: Types.World = world.clone()
	var sheet: Types.Sheet = current_sheet()
	if sheet.regroup != null:
		var origin: Types.TerritoryState = w.get_territory(sheet.regroup.from_id)
		if origin != null and sheet.regroup.strength <= Income.max_send(origin):
			Validate._apply_regroup_to(w, sheet)
	Validate._apply_placements_to(w, map, sheet)
	var ts: Types.TerritoryState = w.get_territory(from_id)
	if ts == null or ts.owner != planner:
		return 0
	var n: int = ts.armies
	var i := 0
	for raw in sheet.packets:
		if i != skip_packet:
			var p: Types.Packet = raw
			if p.from_id == from_id:
				n -= p.strength
		i += 1
	var keep: int = 0 if ts.garrison >= 1 else 1
	return maxi(0, n - keep)


func display_garrison(terr_id: String) -> int:
	var ts: Types.TerritoryState = view_world().get_territory(terr_id)
	return ts.garrison if ts else 0


func remove_packet_at(index: int) -> void:
	var sheet: Types.Sheet = current_sheet()
	if index < 0 or index >= sheet.packets.size():
		return
	sheet.packets.remove_at(index)
	pending_surge_from = -1
	changed.emit()


func _auto_select() -> void:
	if world == null or map == null:
		return
	var owned: PackedStringArray = MapLib.player_territory_ids(world, planner)
	if owned.is_empty():
		selected = ""
		return
	if selected != "" and Array(owned).has(selected):
		return
	selected = owned[0]
	draft = _default_draft(selected)


func nudge_draft(delta: int) -> void:
	draft = maxi(1, draft + delta)
	changed.emit()


func hold_and_lock() -> void:
	if phase == Phase.OPENING:
		opening[planner] = {}
		_lock_opening()
		return
	sheets[planner] = _empty_sheet(planner)
	_lock_plan()


func lock() -> void:
	error_text = ""
	status_text = ""
	if phase == Phase.OPENING:
		_lock_opening()
	elif phase == Phase.PLANNING:
		_lock_plan()


func seated() -> void:
	if phase != Phase.HOTSEAT:
		return
	planner = hotseat_for
	selected = ""
	pending_surge_from = -1
	send_amount = {}
	if opening_done["red"] and opening_done["blue"]:
		phase = Phase.PLANNING
	elif not opening_done[planner]:
		phase = Phase.OPENING
	else:
		phase = Phase.PLANNING
	_auto_select()
	changed.emit()


func cinema_next() -> void:
	if phase == Phase.RECAP:
		_cinema_done()
		return
	if phase != Phase.CINEMA:
		return
	if cinema_index < cinema_events.size() - 1:
		cinema_index += 1
		_skip_quiet_cinema()
		changed.emit()
		return
	_enter_recap()


func cinema_skip() -> void:
	if phase == Phase.RECAP:
		_cinema_done()
		return
	if phase != Phase.CINEMA:
		return
	if cinema_events.is_empty():
		_cinema_done()
		return
	cinema_index = cinema_events.size() - 1
	_enter_recap()


func _skip_quiet_cinema() -> void:
	## Entrench is on the recap, not a click per hex.
	while cinema_index < cinema_events.size() - 1:
		var kind: String = str(cinema_events[cinema_index].get("kind", ""))
		if kind != Types.EVENT_ENTRENCHED:
			return
		cinema_index += 1


func recap_lines() -> PackedStringArray:
	return ViewEvents.recap(cinema_events, map)


func recap_title() -> String:
	var n: int = 0
	for e in cinema_events:
		if str(e.get("kind", "")) == Types.EVENT_ROUND_ENDED:
			n = int(e.get("round", 0))
	if n < 1 and world != null:
		n = maxi(1, world.round - 1)
	if winner != "":
		return "Round %s  ·  %s wins" % [n, winner]
	return "Round %s board" % n


func pool_left() -> int:
	var base: int = Setup.remaining_pool(world, planner, 2, map)
	var spent := 0
	for k in opening[planner].keys():
		spent += int(opening[planner][k])
	return maxi(0, base - spent)


func income_left() -> int:
	var inc: int = Income.income_of(_preview_world(), map, planner)
	var spent := 0
	for k in current_sheet().placements.keys():
		spent += int(current_sheet().placements[k])
	return maxi(0, inc - spent)


func origin_will_remain(from_id: String) -> int:
	var w: Types.World = _preview_world()
	var ts: Types.TerritoryState = w.get_territory(from_id)
	if ts == null:
		return 0
	var n: int = ts.armies
	for p in current_sheet().packets:
		var pkt: Types.Packet = p
		if pkt.from_id == from_id:
			n -= pkt.strength
	return n


func _empty_sheet(pid: String) -> Types.Sheet:
	var s := Types.Sheet.new()
	s.player_id = pid
	return s


func _default_draft(terr_id: String) -> int:
	var mx: int = send_cap(terr_id)
	return mx if mx >= 1 else 1


func _click_dest(terr_id: String) -> void:
	if phase != Phase.PLANNING:
		changed.emit()
		return
	if not MapLib.is_adjacent(map, selected, terr_id):
		error_text = "%s is not next to %s" % [terr_id, selected]
		changed.emit()
		return
	var dest: Types.TerritoryState = world.get_territory(terr_id)
	if dest.owner == planner:
		_issue_friendly(selected, terr_id, send_for(selected))
		return
	attack_to(selected, terr_id)


func _packet_index(from_id: String, to_id: String) -> int:
	var sheet: Types.Sheet = current_sheet()
	for i in sheet.packets.size():
		var p: Types.Packet = sheet.packets[i]
		if p.from_id == from_id and p.to_id == to_id:
			return i
	return -1


func _clamp_packets() -> void:
	if phase != Phase.PLANNING:
		return
	var sheet: Types.Sheet = current_sheet()
	var i := 0
	while i < sheet.packets.size():
		var p: Types.Packet = sheet.packets[i]
		var mx: int = max_send_from(p.from_id, i)
		if mx < 1:
			sheet.packets.remove_at(i)
			if pending_surge_from == i:
				pending_surge_from = -1
			elif pending_surge_from > i:
				pending_surge_from -= 1
			continue
		if p.strength > mx:
			p.strength = mx
		i += 1


func _issue_attack(from_id: String, to_id: String, strength: int) -> void:
	var dest: Types.TerritoryState = world.get_territory(to_id)
	if dest == null or dest.owner == planner:
		error_text = "attack a hex that is not yours"
		changed.emit()
		return
	if not MapLib.is_adjacent(map, from_id, to_id):
		error_text = "not adjacent"
		changed.emit()
		return
	var idx: int = _packet_index(from_id, to_id)
	var mx: int = max_send_from(from_id, idx)
	if mx < 1:
		error_text = "must leave 1 on %s — cannot empty a held hex" % hex_name(from_id)
		changed.emit()
		return
	if strength < 1:
		strength = mx
	var amt: int = clampi(strength, 1, mx)
	if idx >= 0:
		var existing: Types.Packet = current_sheet().packets[idx]
		existing.strength = amt
		pending_surge_from = idx
		error_text = ""
		status_text = "sending %s. optional: click past %s to surge" % [existing.strength, hex_name(to_id)]
		changed.emit()
		return
	var pkt := Types.Packet.new()
	pkt.from_id = from_id
	pkt.to_id = to_id
	pkt.strength = amt
	current_sheet().packets.append(pkt)
	pending_surge_from = current_sheet().packets.size() - 1
	error_text = ""
	status_text = "sending %s. optional: click past %s to surge" % [pkt.strength, hex_name(to_id)]
	changed.emit()


func _issue_friendly(from_id: String, to_id: String, strength: int) -> void:
	## Friendly walk. Round 1 has no kernel regroup — just-placed armies
	## reallocate onto the destination (still capped). Later rounds may also
	## regroup standing armies, always leaving 1 on origin.
	var mx: int = max_friendly_from(from_id, to_id)
	if mx < 1:
		error_text = friendly_block_reason(from_id, to_id)
		changed.emit()
		return
	if not MapLib.is_adjacent(map, from_id, to_id):
		error_text = "not adjacent"
		changed.emit()
		return
	var dest: Types.TerritoryState = world.get_territory(to_id)
	if dest == null or dest.owner != planner:
		error_text = "regroup is friendly to friendly"
		changed.emit()
		return
	var want: int = clampi(maxi(1, strength), 1, mx)
	var sheet: Types.Sheet = current_sheet()
	var from_q: int = int(sheet.placements.get(from_id, 0))
	var to_q: int = int(sheet.placements.get(to_id, 0))
	var room: int = maxi(0, Income.cap_of(world, map, to_id) - to_q)
	var shift: int = mini(want, mini(from_q, room))
	if shift > 0:
		from_q -= shift
		if from_q <= 0:
			sheet.placements.erase(from_id)
		else:
			sheet.placements[from_id] = from_q
		sheet.placements[to_id] = to_q + shift
		want -= shift
	var reg: int = 0
	if want > 0 and world.round > 1:
		reg = mini(want, max_move_from(from_id))
	if world.round <= 1 or reg < 1:
		if sheet.regroup != null and sheet.regroup.from_id == from_id and sheet.regroup.to_id == to_id:
			sheet.regroup = null
		if world.round <= 1:
			sheet.regroup = null
	else:
		var rg := Types.Regroup.new()
		rg.from_id = from_id
		rg.to_id = to_id
		rg.strength = reg
		sheet.regroup = rg
	error_text = ""
	status_text = ""
	_clamp_packets()
	changed.emit()


func _issue_regroup(from_id: String, to_id: String, strength: int) -> void:
	_issue_friendly(from_id, to_id, strength)


func _try_surge(terr_id: String) -> void:
	var idx: int = pending_surge_from
	pending_surge_from = -1
	if idx < 0 or idx >= current_sheet().packets.size():
		select_hex(terr_id)
		return
	var pkt: Types.Packet = current_sheet().packets[idx]
	if terr_id != pkt.from_id and MapLib.is_adjacent(map, pkt.to_id, terr_id):
		pkt.surge_to = terr_id
		error_text = "surge %s" % terr_id
	elif world.get_territory(terr_id).owner == planner:
		selected = terr_id
		draft = _default_draft(terr_id)
		error_text = ""
	changed.emit()


func _preview_world() -> Types.World:
	var w: Types.World = world.clone()
	var sheet: Types.Sheet = current_sheet()
	if phase == Phase.PLANNING:
		Validate._apply_regroup_to(w, sheet)
		Validate._apply_placements_to(w, map, sheet)
	return w


func _lock_opening() -> void:
	opening_done[planner] = true
	if vs_monkey and not opening_done["blue"]:
		var rng: RefCounted = Rng.derive_stream(match_seed, 0, "open|blue")
		opening["blue"] = Bot.opening_placements(world, map, "blue", rng)
		opening_done["blue"] = true
	if opening_done["red"] and opening_done["blue"]:
		Setup.apply_opening(world, map, opening)
		setup_dict = world.to_dict()
		if vs_monkey or _teaching():
			planner = "red"
			selected = ""
			pending_surge_from = -1
			send_amount = {}
			phase = Phase.PLANNING
			_auto_select()
			if _teaching():
				status_text = "Teaching: both of you can see this sheet."
			changed.emit()
			return
		_hand_off("red")
		return
	_hand_off("blue" if planner == "red" else "red")


func _lock_plan() -> void:
	var sheet: Types.Sheet = current_sheet()
	if world.round <= 1:
		sheet.regroup = null
	_clamp_packets()
	var errs: PackedStringArray = Validate.validate_sheet(world, map, sheet)
	if errs.size() > 0:
		error_text = " ".join(errs)
		changed.emit()
		return
	locked[planner] = true
	if vs_monkey and not locked["blue"]:
		var rng: RefCounted = Rng.derive_stream(match_seed, world.round, "bot|blue")
		sheets["blue"] = Bot.legal_sheet(world, map, "blue", rng)
		locked["blue"] = true
	if locked["red"] and locked["blue"]:
		_resolve_and_cinema()
		return
	_hand_off("blue" if planner == "red" else "red")


func _teaching() -> bool:
	return teach and world != null and world.round <= 1


func _hand_off(next_id: String) -> void:
	if vs_monkey:
		return
	if _teaching():
		planner = next_id
		selected = ""
		pending_surge_from = -1
		send_amount = {}
		status_text = "Teaching: both of you can see this sheet."
		if not opening_done[planner]:
			phase = Phase.OPENING
		else:
			phase = Phase.PLANNING
		_auto_select()
		changed.emit()
		return
	hotseat_for = next_id
	phase = Phase.HOTSEAT
	changed.emit()


func _resolve_and_cinema() -> void:
	pre_lock = world.clone()
	var pair: Array = [sheets["red"], sheets["blue"]]
	var result: Dictionary = Resolve.resolve_round(world, map, pair, match_seed)
	if not result["errors"].is_empty():
		error_text = " ".join(result["errors"])
		locked[planner] = false
		changed.emit()
		return
	var round_dicts: Array = [sheets["red"].to_dict(), sheets["blue"].to_dict()]
	recorded_sheets.append(round_dicts)
	last_packets = []
	for s in pair:
		var sh: Types.Sheet = s
		for p in sh.packets:
			var pkt: Types.Packet = p
			last_packets.append({"from": pkt.from_id, "to": pkt.to_id, "strength": pkt.strength, "owner": sh.player_id, "surgeTo": pkt.surge_to})
	cinema_events = result["events"]
	world = result["world"]
	hashes.append(load("res://engine/hash.gd").world_hash(world))
	winner = _winner(cinema_events)
	sheets = {"red": _empty_sheet("red"), "blue": _empty_sheet("blue")}
	locked = {"red": false, "blue": false}
	selected = ""
	pending_surge_from = -1
	send_amount = {}
	if cinema_events.is_empty():
		_enter_recap()
		return
	cinema_index = 0
	_skip_quiet_cinema()
	phase = Phase.CINEMA
	changed.emit()


func _enter_recap() -> void:
	telemetry_rounds.append(Telemetry.summarize_events(cinema_events))
	phase = Phase.RECAP
	changed.emit()


func _cinema_done() -> void:
	if winner != "":
		phase = Phase.GAME_OVER
		_write_match()
		changed.emit()
		return
	planner = "red"
	if vs_monkey:
		phase = Phase.PLANNING
		_auto_select()
		changed.emit()
		return
	_hand_off("red")


func _write_match() -> void:
	if setup_dict.is_empty():
		return
	var rec := {
		"mapId": map.id,
		"matchSeed": match_seed,
		"setup": setup_dict,
		"sheets": recorded_sheets,
		"hashes": hashes,
		"finalHash": hashes[hashes.size() - 1] if hashes.size() > 0 else "",
	}
	Match.save("user://last_match.json", rec)
	var early := false
	for raw in telemetry_rounds:
		if typeof(raw) == TYPE_DICTIONARY and bool(raw.get("early", false)):
			early = true
	var tel: Dictionary = Telemetry.from_play({
		"mapId": map.id,
		"matchSeed": match_seed,
		"vsMonkey": vs_monkey,
		"teach": teach,
		"rounds": telemetry_rounds,
		"winner": winner,
		"early": early,
		"hashes": hashes,
	})
	Telemetry.append("user://telemetry.jsonl", tel)


func _winner(events: Array) -> String:
	for i in range(events.size() - 1, -1, -1):
		var e: Dictionary = events[i]
		if str(e.get("kind", "")) == Types.EVENT_ROUND_ENDED:
			return str(e.get("winner", ""))
	return ""


func cinema_caption() -> String:
	if cinema_index < 0 or cinema_index >= cinema_events.size():
		return ""
	return ViewEvents.caption(cinema_events[cinema_index])


func cinema_highlights() -> PackedStringArray:
	if cinema_index < 0 or cinema_index >= cinema_events.size():
		return PackedStringArray()
	return ViewEvents.involved_hexes(cinema_events[cinema_index])
