## Plays one round's Event[] back on the board, a beat at a time.
## The log is the engine's; this only chooses pacing, words, dice and sound.
extends Control

const Style := preload("res://game/core/style.gd")
const Types := preload("res://engine/types.gd")
const ViewEvents := preload("res://game/view_events.gd")
const Combat := preload("res://engine/combat.gd")

signal finished

var session: Node
var board: Control
var beats: Array = []
var index := -1
var paused := false
var _wait := 0.0
var _events: Array = []
var _pre: Types.World
var _packets: Array = []
var _resolved := {} ## destination -> true once its fight is over
var _banner: PanelContainer
var _caption: Label
var _sub: Label
var _card: PanelContainer
var _card_title: Label
var _left: _Side
var _right: _Side
var _result: Label
var _dice_l: _Die
var _dice_r: _Die
var _vs: Label
var _controls: HBoxContainer
var _pause_btn: Button
var _progress: Label
var _rolling := 0.0
var _roll_final := Vector2i.ZERO
var _active := false
var theater: Control ## the battlefield scene, if the game screen provides one
var theater_hook: Callable ## beat -> bool: open the battlefield for this fight?
var beat_hook: Callable ## beat -> void: reactions (walk-ins, eliminations…)
var bottom_margin := 20.0
var _waiting := false
var _theater_off := false
var _theater_cb: Callable
var _group_first := -1 ## beat index of the first fight on the battlefield now


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	## caption banner, top of the map
	_banner = PanelContainer.new()
	_banner.add_theme_stylebox_override("panel", Style.flat(Color(0.03, 0.04, 0.07, 0.88), Color(Style.GOLD, 0.6), 1, 8, 14))
	_banner.set_anchors_preset(PRESET_CENTER_TOP)
	_banner.offset_top = 14
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_banner)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 0)
	_banner.add_child(bv)
	_caption = Style.label("", 28, Style.CREAM, "display")
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(_caption)
	_sub = Style.label("", 18, Style.PARCH, "italic")
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub.custom_minimum_size = Vector2(520, 0)
	bv.add_child(_sub)
	## battle card, bottom center
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", Style.panel_box(16))
	_card.set_anchors_preset(PRESET_CENTER_BOTTOM)
	_card.offset_bottom = -78 - bottom_margin
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 6)
	_card.add_child(cv)
	_card_title = Style.label("", 22, Style.GOLD, "display")
	_card_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(_card_title)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	cv.add_child(row)
	_left = _Side.new()
	row.add_child(_left)
	_dice_l = _Die.new()
	row.add_child(_dice_l)
	_vs = Style.label("vs", 22, Style.MUTED, "display")
	row.add_child(_vs)
	_dice_r = _Die.new()
	row.add_child(_dice_r)
	_right = _Side.new()
	row.add_child(_right)
	_result = Style.label("", 24, Style.CREAM, "display")
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(_result)
	## controls, bottom center under the card
	_controls = HBoxContainer.new()
	_controls.set_anchors_preset(PRESET_CENTER_BOTTOM)
	_controls.offset_bottom = -18
	_controls.offset_top = -62
	_controls.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_controls.alignment = BoxContainer.ALIGNMENT_CENTER
	_controls.add_theme_constant_override("separation", 10)
	add_child(_controls)
	_pause_btn = Style.chip("❚❚ Pause", func(): _toggle_pause(), Style.CREAM, 17)
	_controls.add_child(_pause_btn)
	_controls.add_child(Style.chip("Next ▶  (Space)", func(): advance(), Style.CREAM, 17))
	_controls.add_child(Style.chip("Skip to results ▶▶", func(): skip(), Style.PARCH, 17))
	_progress = Style.label("", 16, Style.MUTED)
	_controls.add_child(_progress)
	_controls.visible = bottom_margin < 40.0
	visible = false


func play(p_session: Node, p_board: Control) -> void:
	session = p_session
	board = p_board
	if not session.extended.is_connected(_on_extended):
		session.extended.connect(_on_extended)
	_events = session.events
	_pre = session.pre_world
	_packets = []
	_resolved = {}
	_waiting = false
	_theater_off = false
	beats = _build_beats()
	index = -1
	paused = false
	_pause_btn.text = "❚❚ Pause"
	visible = true
	_active = true
	board.interactive = false
	board.show_ceiling = false
	board.selected = ""
	board.targets = {}
	board.placements = {}
	board.ghosts = []
	board.orders = []
	board.world = _pre.clone()
	board.refresh()
	Audio.music("battle")
	advance()


func advance() -> void:
	if not _active:
		return
	index += 1
	if index >= beats.size() and not session.pending.is_empty():
		## a paused battle nobody is watching: the officers call it
		session.release_live()
	if index >= beats.size():
		_finish()
		return
	_show(beats[index])


func _on_extended() -> void:
	## The round resolved further (a battle call was made): same prefix, more log.
	if not _active:
		return
	_events = session.events
	_packets = []
	beats = _build_beats()
	if _waiting and theater != null and _group_first >= 0:
		theater.extend(_group_at(_group_first))


func _group_at(first: int) -> Array:
	## Every fight at the same land in a row goes to the battlefield together.
	var group: Array = [beats[first]]
	var land: String = str(beats[first].get("resolves", ""))
	var j: int = first + 1
	while land != "" and j < beats.size() and bool(beats[j].get("fight", false)) and str(beats[j].get("resolves", "")) == land:
		group.append(beats[j])
		j += 1
	return group


func skip() -> void:
	if not _active:
		return
	if not session.pending.is_empty():
		session.release_live()
	if _waiting and theater != null:
		if _theater_cb.is_valid() and theater.finished.is_connected(_theater_cb):
			theater.finished.disconnect(_theater_cb)
		theater.abort()
		_waiting = false
	board.world = ViewEvents.apply_through(_pre, _events, _events.size() - 1)
	board.orders = []
	board.battle = {}
	board.refresh()
	_finish()


func _finish() -> void:
	_active = false
	visible = false
	board.fx.clear()
	board.shake.clear()
	board.battle = {}
	board.orders = []
	board.refresh()
	finished.emit()


func toggle_pause() -> void:
	_toggle_pause()


func progress_text() -> String:
	if index < 0 or beats.is_empty():
		return ""
	return "%d of %d" % [mini(index + 1, beats.size()), beats.size()]


func _toggle_pause() -> void:
	paused = not paused
	_pause_btn.text = "▶ Play" if paused else "❚❚ Pause"


func _unhandled_input(event: InputEvent) -> void:
	if not _active or _waiting:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER or event.keycode == KEY_RIGHT:
			advance()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			skip()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_P:
			_toggle_pause()


func _process(delta: float) -> void:
	if not _active or _waiting:
		return
	if _rolling > 0.0:
		_rolling -= delta
		if _rolling <= 0.0:
			_dice_l.value = _roll_final.x
			_dice_r.value = _roll_final.y
			_dice_l.rolling = false
			_dice_r.rolling = false
			_reveal_result()
		else:
			_dice_l.rolling = true
			_dice_r.rolling = true
	if paused:
		return
	_wait -= delta
	if _wait <= 0.0 and _rolling <= 0.0:
		advance()


# ------------------------------------------------------------------ beats

func _name(pid: String) -> String:
	return session.name_of(pid)


func _hex(id: String) -> String:
	return session.hex_name(id)


func _build_beats() -> Array:
	var out: Array = []
	var evs: Array = _events
	var i := 0
	var n := evs.size()
	## 1. reinforcements (and cashed sets, regroups)
	var last_setup := -1
	var cashes: Array = []
	var moves := 0
	var placed := 0
	for k in n:
		var kind: String = str(evs[k]["kind"])
		if kind == Types.EVENT_PLACED or kind == Types.EVENT_REGROUP_APPLIED or kind == Types.EVENT_SET_CASHED:
			last_setup = k
			if kind == Types.EVENT_SET_CASHED:
				cashes.append("%s trades cards for +%d" % [_name(str(evs[k]["playerId"])), int(evs[k]["value"])])
			elif kind == Types.EVENT_REGROUP_APPLIED:
				moves += 1
			else:
				placed += int(evs[k]["added"])
		elif kind == Types.EVENT_VACATED:
			break
	var opening: bool = bool(session.get_meta("opening_cinema", false))
	if last_setup >= 0:
		var sub := "%d armies placed" % placed
		if moves > 0:
			sub += ", %d move%s" % [moves, "" if moves == 1 else "s"]
		if not cashes.is_empty():
			sub += ". " + ". ".join(cashes)
		out.append({"upto": last_setup, "caption": "The armies deploy" if opening else "Reinforcements arrive", "sub": sub + ".", "sound": "place", "delay": 1.0, "placed": true})
		i = last_setup + 1
	if opening:
		return out
	## 2. every packet revealed at once
	var last_vac := -1
	var count := 0
	var emptied: Array = []
	for k in range(i, n):
		var kind: String = str(evs[k]["kind"])
		if kind == Types.EVENT_VACATED:
			last_vac = k
			count += 1
			_packets.append({"from": str(evs[k]["from"]), "to": str(evs[k]["to"]), "strength": int(evs[k]["strength"]), "owner": str(evs[k]["playerId"]), "kind": "attack"})
		elif kind == Types.EVENT_BECAME_UNOCCUPIED and last_vac >= 0 and k == last_vac + 1:
			last_vac = k
			emptied.append(_hex(str(evs[k]["terrId"])))
		else:
			break
	if last_vac >= 0:
		var sub2 := "Every commander marches at once. Attackers leave home."
		if not emptied.is_empty():
			sub2 = "%s left completely empty!" % ", ".join(emptied)
		out.append({"upto": last_vac, "caption": "Orders revealed — %d attack%s" % [count, "" if count == 1 else "s"], "sub": sub2, "sound": "reveal", "sound2": "march", "delay": 1.6, "reveal": true})
		i = last_vac + 1
	else:
		out.append({"upto": i - 1, "caption": "Nobody attacks", "sub": "Every commander held this round.", "sound": "", "delay": 1.2})
	## 3. the queue, in engine order
	var vacated := {}
	for e in _events:
		if str(e["kind"]) == Types.EVENT_VACATED:
			vacated[str(e["from"])] = str(e["playerId"])
	var dug := 0
	var drawn: Array = []
	while i < n:
		var e: Dictionary = evs[i]
		var kind: String = str(e["kind"])
		match kind:
			Types.EVENT_CLASH:
				var cb := _fight_beat(i, "Border clash", _hex(str(e["hexA"])) + " ⇄ " + _hex(str(e["hexB"])),
					str(e["playerA"]), int(e["sizeA"]), int(e["dieA"]), str(e["playerB"]), int(e["sizeB"]), int(e["dieB"]),
					str(e["winnerId"]) == str(e["playerA"]), int(e["winnerRemaining"]), "Both armies meet in the field.", [str(e["hexA"]), str(e["hexB"])], "")
				cb["event"] = e
				out.append(cb)
			Types.EVENT_INVASION:
				var to: String = str(e["to"])
				var upto := i
				if bool(e["attackerWon"]) and i + 1 < n and str(evs[i + 1]["kind"]) == Types.EVENT_OCCUPIED:
					upto = i + 1
				var b := _fight_beat(upto, "Assault on %s" % _hex(to), "",
					str(e["attackerId"]), int(e["attackerSize"]), int(e["attackerDie"]), str(e["defenderId"]), int(e["defenderSize"]), int(e["defenderDie"]),
					bool(e["attackerWon"]), int(e["winnerRemaining"]), "", [str(e["from"]), to], to)
				b["invasion"] = true
				b["attacker_ties"] = true
				b["event"] = e
				out.append(b)
				i = upto
			Types.EVENT_SPOILS:
				var to2: String = str(e["to"])
				var upto2 := i
				if i + 1 < n and str(evs[i + 1]["kind"]) == Types.EVENT_OCCUPIED:
					upto2 = i + 1
				var sb := _fight_beat(upto2, "Fight for %s" % _hex(to2), "",
					str(e["playerA"]), int(e["sizeA"]), int(e["dieA"]), str(e["playerB"]), int(e["sizeB"]), int(e["dieB"]),
					str(e["winnerId"]) == str(e["playerA"]), int(e["winnerRemaining"]), "Two invaders, one prize.", [to2], to2)
				sb["event"] = e
				out.append(sb)
				i = upto2
			Types.EVENT_OCCUPIED:
				var hex: String = str(e["terrId"])
				var who: String = str(e["playerId"])
				if vacated.has(hex) and vacated[hex] != who:
					out.append({"upto": i, "caption": "Walk-in!", "sub": "%s strolls into %s — %s left it bare." % [_name(who), _hex(hex), _name(vacated[hex])], "sound": "walkin", "delay": 2.0, "focus": [hex], "flash": hex, "flash_text": "WALK-IN", "resolves": hex, "walkin": who, "victim": vacated[hex]})
				else:
					out.append({"upto": i, "caption": "%s takes %s" % [_name(who), _hex(hex)], "sub": "Nobody was home.", "sound": "capture", "delay": 1.1, "focus": [hex], "flash": hex, "flash_text": "+1", "resolves": hex})
			Types.EVENT_SURGE:
				_packets.append({"from": str(e["from"]), "to": str(e["to"]), "strength": int(e["strength"]), "owner": str(e["playerId"]), "kind": "attack"})
				out.append({"upto": i, "caption": "%s surges on!" % _name(str(e["playerId"])), "sub": "%d push on from %s into %s." % [int(e["strength"]), _hex(str(e["from"])), _hex(str(e["to"]))], "sound": "surge", "sound2": "hoofs", "delay": 1.4, "focus": [str(e["from"]), str(e["to"])]})
			Types.EVENT_PLAYER_ELIMINATED:
				out.append({"upto": i, "caption": "%s is wiped out" % _name(str(e["playerId"])), "sub": "Their banners fall.", "sound": "eliminated", "delay": 2.4, "eliminated": str(e["playerId"])})
			Types.EVENT_CARDS_CAPTURED:
				out.append({"upto": i, "caption": "Spoils of war", "sub": "%s seizes %s's %d card%s." % [_name(str(e["to"])), _name(str(e["from"])), (e["cards"] as Array).size(), "" if (e["cards"] as Array).size() == 1 else "s"], "sound": "card", "delay": 1.4})
			Types.EVENT_ENTRENCHED:
				dug += 1
			Types.EVENT_CARD_DRAWN:
				drawn.append(_name(str(e["playerId"])))
			Types.EVENT_BECAME_UNOCCUPIED:
				pass
			Types.EVENT_ROUND_ENDED:
				var sub3 := ""
				if dug > 0:
					sub3 = "%d held land%s dug in deeper." % [dug, "" if dug == 1 else "s"]
				if not drawn.is_empty():
					sub3 += " Cards drawn by %s." % ", ".join(drawn)
				out.append({"upto": i, "caption": "The dust settles", "sub": sub3.strip_edges(), "sound": "round", "delay": 1.3, "dig": true})
		i += 1
	return out


func _fight_beat(upto: int, title: String, subtitle: String, a: String, a_size: int, a_die: int, b: String, b_size: int, b_die: int, a_won: bool, left: int, sub: String, focus: Array, dest: String) -> Dictionary:
	return {
		"upto": upto, "caption": title, "sub": subtitle if subtitle != "" else sub, "fight": true,
		"a": a, "a_size": a_size, "a_die": a_die, "b": b, "b_size": b_size, "b_die": b_die,
		"a_won": a_won, "left": left, "focus": focus, "delay": 1.9, "resolves": dest,
	}


func _show(b: Dictionary) -> void:
	if bool(b.get("fight", false)) and not _theater_off and theater != null and theater_hook.is_valid() and bool(theater_hook.call(b)):
		_open_theater(b)
		return
	if bool(b.get("fight", false)) and bool((b.get("event", {}) as Dictionary).get("pending", false)):
		## paused for a call nobody will make here: officers decide, then show it
		session.release_live()
		if index < beats.size():
			b = beats[index]
	if beat_hook.is_valid():
		beat_hook.call(b)
	var delay_base: float = Settings.battle_delay()
	_caption.text = str(b.get("caption", ""))
	_sub.text = str(b.get("sub", ""))
	_sub.visible = _sub.text != ""
	_progress.text = "%d / %d" % [index + 1, beats.size()]
	var s: String = str(b.get("sound", ""))
	if s != "":
		Audio.sfx(s)
	if b.has("sound2"):
		get_tree().create_timer(0.5).timeout.connect(func(): Audio.sfx(str(b["sound2"]), -4.0))
	if bool(b.get("reveal", false)):
		board.orders = _packets.duplicate(true)
	if b.has("resolves") and str(b["resolves"]) != "":
		_resolved[str(b["resolves"])] = true
	for o in board.orders:
		o["alpha"] = 0.28 if _resolved.has(str(o["to"])) else 1.0
	var focus: Array = b.get("focus", [])
	board.battle = {}
	for f in focus:
		board.battle[f] = true
	board.focus_on(focus)
	_card.visible = bool(b.get("fight", false))
	if _card.visible:
		_start_fight(b)
	else:
		_apply(b)
	_wait = delay_base * float(b.get("delay", 1.0))
	if bool(b.get("placed", false)):
		for e in _events.slice(0, int(b["upto"]) + 1):
			if str(e["kind"]) == Types.EVENT_PLACED and int(e["added"]) > 0:
				board.float_text(str(e["terrId"]), "+%d" % int(e["added"]), Style.GOLD, 1.8, 24)
	if bool(b.get("dig", false)):
		for e in _events:
			if str(e["kind"]) == Types.EVENT_ENTRENCHED:
				board.pulse_token(str(e["terrId"]), 0.7)


func _open_theater(first: Dictionary) -> void:
	_group_first = index
	var group: Array = _group_at(index)
	var human := false
	for g in group:
		if session.is_human(str(g["a"])) or session.is_human(str(g["b"])):
			human = true
	## the map shows the moment before the first fight
	board.world = ViewEvents.apply_through(_pre, _events, int(first["upto"]) - (1 if str(_events[int(first["upto"])]["kind"]) == Types.EVENT_OCCUPIED else 0) - 1)
	board.refresh()
	_waiting = true
	_banner.visible = false
	_card.visible = false
	_theater_cb = func(skip_rest: bool):
		if skip_rest and not session.pending.is_empty():
			session.release_live() ## the officers call whatever is left
		_waiting = false
		_banner.visible = true
		var grp: Array = _group_at(_group_first)
		var last_index: int = _group_first + grp.size() - 1
		_group_first = -1
		index = last_index
		var lb: Dictionary = beats[last_index]
		for g in grp:
			if str(g.get("resolves", "")) != "":
				_resolved[str(g["resolves"])] = true
		for o in board.orders:
			o["alpha"] = 0.28 if _resolved.has(str(o["to"])) else 1.0
		board.world = ViewEvents.apply_through(_pre, _events, int(lb["upto"]))
		board.refresh()
		if skip_rest:
			_theater_off = true
		_wait = 0.4
	theater.finished.connect(_theater_cb, CONNECT_ONE_SHOT)
	theater.play(session, group, human)


func _apply(b: Dictionary) -> void:
	board.world = ViewEvents.apply_through(_pre, _events, int(b["upto"]))
	if b.has("flash"):
		board.float_text(str(b["flash"]), str(b.get("flash_text", "")), Style.GOLD if str(b.get("flash_text", "")) != "WALK-IN" else Style.CRIMSON.lightened(0.3), 2.0, 30)
		board.pulse_token(str(b["flash"]), 1.0)
	board.refresh()


var _fight: Dictionary = {}


func _start_fight(b: Dictionary) -> void:
	_fight = b
	var inv: bool = bool(b.get("invasion", false))
	_card_title.text = str(b["caption"])
	_left.setup(str(b["a"]), _name(str(b["a"])), int(b["a_size"]), "attacks" if inv else "")
	_right.setup(str(b["b"]), _name(str(b["b"])), int(b["b_size"]), "defends" if inv else "")
	_dice_l.tint = Style.seat_color(str(b["a"]))
	_dice_r.tint = Style.seat_color(str(b["b"]))
	_result.text = ""
	_roll_final = Vector2i(int(b["a_die"]), int(b["b_die"]))
	_rolling = clampf(Settings.battle_delay() * 0.5, 0.35, 1.0)
	Audio.sfx("dice")
	## the map shows the moment before the result
	board.world = ViewEvents.apply_through(_pre, _events, int(b["upto"]) - (1 if int(b["upto"]) > 0 and str(_events[int(b["upto"])]["kind"]) == Types.EVENT_OCCUPIED else 0) - 1)
	board.refresh()


func _reveal_result() -> void:
	var b: Dictionary = _fight
	if b.is_empty():
		return
	var ta: int = int(b["a_size"]) + int(b["a_die"])
	var tb: int = int(b["b_size"]) + int(b["b_die"])
	_left.total(ta)
	_right.total(tb)
	var a_won: bool = bool(b["a_won"])
	var winner: String = str(b["a"]) if a_won else str(b["b"])
	var loser: String = str(b["b"]) if a_won else str(b["a"])
	var inv: bool = bool(b.get("invasion", false))
	var ev: Dictionary = b.get("event", {})
	var txt := ""
	if int(ev.get("reservesAdded", 0)) > 0:
		txt = "Reserves +%d!  " % int(ev["reservesAdded"])
		Audio.sfx("reserves", -4.0)
	if inv and bool(ev.get("fellBack", false)):
		txt += "%s falls back to %s — %d saved" % [_name(str(b["a"])), _hex(str(ev.get("refuge", ""))), int(ev.get("attackerLeft", 0))]
		Audio.sfx("retreat")
	elif inv:
		if a_won:
			txt += "%s takes %s with %d left" % [_name(winner), _hex(str(b["resolves"])), int(b["left"])]
			if ta == tb:
				txt += "  (ties go to the attacker)"
			Audio.sfx("capture")
		else:
			txt += "%s holds! %d remain" % [_name(winner), int(b["left"])]
			Audio.sfx("hold")
	else:
		txt = "%s wins with %d left — %s is destroyed" % [_name(winner), int(b["left"]), _name(loser)]
		Audio.sfx("clash")
	_result.text = txt
	_result.add_theme_color_override("font_color", Style.seat_color(winner).lightened(0.35))
	_apply(b)
	if inv and a_won:
		board.float_text(str(b["resolves"]), "Captured", Style.GOLD, 1.8, 26)
	board.pulse_token(str(b["resolves"]) if str(b["resolves"]) != "" else str((b["focus"] as Array)[0]), 0.8)


# ------------------------------------------------------------------ widgets

class _Side extends VBoxContainer:
	const Style := preload("res://game/core/style.gd")
	var _mark: _Mark
	var _name: Label
	var _size: Label
	var _role: Label

	func _init() -> void:
		alignment = BoxContainer.ALIGNMENT_CENTER
		custom_minimum_size = Vector2(170, 0)
		add_theme_constant_override("separation", 0)
		_mark = _Mark.new()
		_mark.custom_minimum_size = Vector2(0, 40)
		add_child(_mark)
		_name = Style.label("", 20, Style.CREAM, "bold")
		_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(_name)
		_size = Style.label("", 30, Style.CREAM, "display")
		_size.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(_size)
		_role = Style.label("", 15, Style.MUTED, "italic")
		_role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(_role)

	func setup(pid: String, who: String, n: int, role: String) -> void:
		_mark.pid = pid
		_mark.queue_redraw()
		_name.text = who
		_name.add_theme_color_override("font_color", Style.seat_color(pid).lightened(0.35))
		_size.text = Style.plural(n, "army", "armies")
		_role.text = role
		set_meta("n", n)

	func total(t: int) -> void:
		_size.text = "%d + die = %d" % [int(get_meta("n", 0)), t]


class _Mark extends Control:
	const Style := preload("res://game/core/style.gd")
	var pid := ""

	func _draw() -> void:
		if pid == "":
			return
		Style.draw_shape(self, Style.seat_shape(pid), size * 0.5, 17.0, Style.seat_color(pid), Style.CREAM, 2.0)


class _Die extends Control:
	var value := 1
	var rolling := false
	var tint := Color.WHITE
	var _tick := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(64, 64)

	func _process(delta: float) -> void:
		if rolling:
			_tick += delta
			if _tick > 0.06:
				_tick = 0.0
				value = randi_range(1, 6)
				queue_redraw()
		elif _tick != -1.0:
			_tick = -1.0
			queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2(6, 6), size - Vector2(12, 12))
		var wob := 0.0
		if rolling:
			wob = randf_range(-0.12, 0.12)
		draw_set_transform(size * 0.5, wob, Vector2.ONE)
		var rr := Rect2(-r.size * 0.5, r.size)
		var body := StyleBoxFlat.new()
		body.bg_color = Color(0.96, 0.93, 0.85)
		body.border_color = tint.darkened(0.2)
		body.set_border_width_all(4)
		body.set_corner_radius_all(9)
		body.shadow_color = Color(0, 0, 0, 0.4)
		body.shadow_size = 4
		draw_style_box(body, rr)
		var pips := {
			1: [Vector2(0, 0)],
			2: [Vector2(-1, -1), Vector2(1, 1)],
			3: [Vector2(-1, -1), Vector2(0, 0), Vector2(1, 1)],
			4: [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)],
			5: [Vector2(-1, -1), Vector2(1, -1), Vector2(0, 0), Vector2(-1, 1), Vector2(1, 1)],
			6: [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 1), Vector2(1, 1)],
		}
		for p in pips[clampi(value, 1, 6)]:
			draw_circle(p * r.size.x * 0.27, 5.0, Color(0.12, 0.08, 0.06))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
