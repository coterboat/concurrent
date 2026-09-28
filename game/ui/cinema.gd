## Plays one round's Event[] back on the board, a beat at a time.
## The log is the engine's; this only chooses pacing, words, dice and sound.
extends Control

const Style := preload("res://game/core/style.gd")
const Types := preload("res://engine/types.gd")
const ViewEvents := preload("res://game/view_events.gd")
const Combat := preload("res://engine/combat.gd")
const DiceStage := preload("res://game/ui/dice_stage.gd")
const MapLib := preload("res://engine/map.gd")
const Moments := preload("res://game/ui/moments.gd")

signal finished
signal shown ## the map now shows a new moment of the report (the roster follows it)

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
var _settled := {} ## v1.12: beat index -> true once a clash's arrows are settled
var _banner: PanelContainer
var _caption: Label
var _sub: Label
var _card: PanelContainer
var _card_title: Label
var _left: _Side
var _right: _Side
var _result: Label
var _dice: Control ## DiceStage: the deciding throw, dropped onto the card
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
var _voice_hold := 0.0 ## seconds the report has waited for a line to finish


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	## caption banner, top of the map
	_banner = PanelContainer.new()
	_banner.add_theme_stylebox_override("panel", Style.flat(Color(0.03, 0.04, 0.07, 0.88), Color(Style.GOLD, 0.6), 1, 8, 14))
	_banner.set_anchors_preset(PRESET_CENTER_TOP)
	_banner.offset_top = 92 ## below the commander strip, so a wide caption never covers it
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
	_dice = DiceStage.new()
	_dice.board = false
	_dice.width = 5.2
	_dice.pitch = 62.0
	_dice.custom_minimum_size = Vector2(220, 110)
	_dice.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_dice)
	_vs = Style.label("", 1, Style.MUTED, "display")
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
	_settled = {}
	_waiting = false
	_theater_off = false
	beats = _build_beats()
	index = -1
	paused = false
	_pause_btn.text = "❚❚ Pause"
	visible = true
	_active = true
	board.interactive = false
	board.flow = true
	board.show_ceiling = false
	board.selected = ""
	board.targets = {}
	board.placements = {}
	board.ghosts = []
	board.orders = []
	board.world = _pre.clone()
	board.refresh()
	Audio.music(Audio.battle_music()) ## v1.13: the endgame carries on into the last battles
	if bool(session.get_meta("opening_cinema", false)):
		advance()
	else:
		_wait = 1.5 ## let THE BATTLES banner have its moment first


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
	board.dimmed = {}
	board.clash = []
	board.orders = []
	board.flow = false
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
			_reveal_result()
	if paused:
		return
	_wait -= delta
	if _wait <= 0.0 and _rolling <= 0.0:
		## v1.10: let a line being spoken finish (a few seconds at most) before the report moves on
		if Audio.voice_playing() and _voice_hold < 4.0:
			_voice_hold += delta
			return
		_voice_hold = 0.0
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
				cashes.append("%s cards for +%d" % [Style.says(_name(str(evs[k]["playerId"])), "trades"), int(evs[k]["value"])])
			elif kind == Types.EVENT_REGROUP_APPLIED:
				moves += 1
			else:
				placed += int(evs[k]["added"])
		elif kind == Types.EVENT_VACATED:
			break
	var opening: bool = bool(session.get_meta("opening_cinema", false))
	## v1.5: a set turned in is news: each gets its own moment, before the recruits muster
	for k in range(0, maxi(0, last_setup) + 1):
		if str(evs[k]["kind"]) == Types.EVENT_SET_CASHED:
			var cp: String = str(evs[k]["playerId"])
			var kinds0: Array = []
			for c in evs[k].get("cards", []):
				kinds0.append(_card_label(str(c)))
			var free0: Array = evs[k].get("lands", [])
			var free_txt := ""
			if not free0.is_empty():
				var fn: Array = []
				for ln in free0:
					fn.append(_hex(str(ln)))
				free_txt = " A free soldier joins them on %s." % ", ".join(fn)
			out.append({"upto": k, "caption": "%s in a set of cards!" % Style.says(_name(cp), "turns"),
				"sub": "%s — %d fresh troops join the colours.%s" % [", ".join(kinds0), int(evs[k]["value"]), free_txt],
				"sound": "turn_in", "delay": 2.4, "cash": cp, "cash_value": int(evs[k]["value"]), "cards": evs[k].get("cards", []), "cash_lands": free0})
	if last_setup >= 0:
		var sub := "%d armies placed" % placed
		if moves > 0:
			sub += ", %d move%s" % [moves, "" if moves == 1 else "s"]
		if not cashes.is_empty():
			sub += ". " + ". ".join(cashes)
		out.append({"upto": last_setup, "caption": "The armies deploy" if opening else "Recruits muster", "sub": sub + ".", "sound": "place", "delay": 1.0, "placed": true})
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
	var stage := ""
	var seen_surge := false
	while i < n:
		var e: Dictionary = evs[i]
		var kind: String = str(e["kind"])
		## v1.5: the stages of the battle report, each announced as it begins
		var st: String = _stage_of(kind, seen_surge)
		if kind == Types.EVENT_SURGE:
			seen_surge = true
			st = "surge"
		if st != "" and st != stage:
			stage = st
			var mark: Dictionary = _stage_beat(st, i - 1)
			if not mark.is_empty():
				out.append(mark)
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
			Types.EVENT_MELEE:
				var to3: String = str(e["to"])
				var names: Array = []
				var froms: Array = [to3]
				var attackers: Array = []
				var human := ""
				for f in e.get("fronts", []):
					var ap: String = str(f["attackerId"])
					attackers.append(ap)
					names.append("%s (%d)" % [_name(ap), int(f["size"])])
					froms.append(str(f["from"]))
					if human == "" and session.is_human(ap):
						human = ap
				var held: bool = int(e.get("defenderLeft", 0)) > 0
				var upto3 := i
				if not held and i + 1 < n and str(evs[i + 1]["kind"]) == Types.EVENT_OCCUPIED:
					upto3 = i + 1
				var outcome: String = ("%s with %d left." % [Style.says(_name(str(e["defenderId"])), "holds"), int(e["defenderLeft"])]) if held else "The defenders are overrun!"
				out.append({"upto": upto3, "caption": "Melee at %s" % _hex(to3), "sub": "%s storm %s's %d at once. %s" % [" and ".join(names), _name(str(e["defenderId"])), int(e["defenderSize"]), outcome],
					"fight": true, "melee": true, "event": e, "a": human if human != "" else attackers[0], "b": str(e["defenderId"]), "attackers": attackers,
					"focus": froms, "resolves": to3, "delay": 2.6, "sound": "melee", "a_won": not held})
				i = upto3
			Types.EVENT_SCRAMBLE:
				var to4: String = str(e["to"])
				var names4: Array = []
				var froms4: Array = [to4]
				var who4: Array = []
				var human4 := ""
				for f in e.get("fronts", []):
					var fp: String = str(f["playerId"])
					who4.append(fp)
					names4.append("%s (%d)" % [_name(fp), int(f["size"])])
					if not froms4.has(str(f["from"])):
						froms4.append(str(f["from"]))
					if human4 == "" and session.is_human(fp):
						human4 = fp
				var upto4 := i
				if i + 1 < n and str(evs[i + 1]["kind"]) == Types.EVENT_OCCUPIED:
					upto4 = i + 1
				var lead4: String = human4 if human4 != "" else str(who4[0])
				var other4: String = str(who4[1]) if str(who4[0]) == lead4 else str(who4[0])
				var after_melee: bool = str(e.get("after", "")) == "melee"
				out.append({"upto": upto4, "caption": ("The victors turn on each other at %s" if after_melee else "Scramble for %s") % _hex(to4),
					"sub": "%s — every man for himself. %s is left standing with %d." % [", ".join(names4), _name(str(e["winnerId"])), int(e["winnerLeft"])],
					"fight": true, "scramble": true, "event": e, "a": lead4, "b": other4, "attackers": who4,
					"focus": froms4, "resolves": to4, "delay": 2.4, "sound": "melee", "a_won": true})
				i = upto4
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
					out.append({"upto": i, "caption": "Walk-in!", "sub": "%s into %s — %s left it bare." % [Style.says(_name(who), "strolls"), _hex(hex), _name(vacated[hex])], "sound": "walkin", "delay": 2.0, "focus": [hex], "flash": hex, "flash_text": "WALK-IN", "resolves": hex, "walkin": who, "victim": vacated[hex]})
				else:
					out.append({"upto": i, "caption": "%s %s" % [Style.says(_name(who), "takes"), _hex(hex)], "sub": "Nobody was home.", "sound": "capture", "delay": 1.1, "focus": [hex], "flash": hex, "flash_text": "+1", "resolves": hex})
			Types.EVENT_SURGE when bool(e.get("joins", false)):
				## v1.10: the second wave finds the land already taken, and marches in to hold it
				out.append({"upto": i, "caption": "The second wave marches in",
					"sub": "%s already fell to %s: %d more from %s join its garrison." % [_hex(str(e["to"])), _name(str(e["playerId"])), int(e["strength"]), _hex(str(e["from"]))],
					"sound": "march", "delay": 1.4, "focus": [str(e["from"]), str(e["to"])], "flash": str(e["to"]), "flash_text": "+%d" % int(e["strength"])})
			Types.EVENT_SURGE:
				## the surge marches like any column, on from the land just taken; its arrow
				## appears (and draws itself out) only when it sets off
				var sp := {"from": str(e["from"]), "to": str(e["to"]), "strength": int(e["strength"]), "owner": str(e["playerId"]), "kind": "attack", "late": true}
				_packets.append(sp)
				out.append({"upto": i, "caption": "%s on!" % Style.says(_name(str(e["playerId"])), "surges"), "sub": "%d push on from %s into %s." % [int(e["strength"]), _hex(str(e["from"])), _hex(str(e["to"]))], "sound": "surge", "sound2": "hoofs", "delay": 1.6, "focus": [str(e["from"]), str(e["to"])], "surge_arrow": sp})
			Types.EVENT_PLAYER_ELIMINATED:
				out.append({"upto": i, "caption": "%s wiped out" % Style.says(_name(str(e["playerId"])), "is"), "sub": "Their banners fall.", "sound": "eliminated", "delay": 2.4, "eliminated": str(e["playerId"])})
			Types.EVENT_CAPITAL_TAKEN:
				## v1.8: a capital falls: the plunder, the levy, and where the court flees to
				var fell: String = str(e["terrId"])
				var by: String = str(e["by"])
				var loot: Array = e.get("cards", [])
				var sub4 := ""
				if int(e.get("levy", 0)) > 0:
					sub4 = "%s raises %d fresh troops in the city" % [_name(by), int(e["levy"])]
					sub4 += (" and carries off %d of %s's cards." % [loot.size(), _name(str(e["playerId"]))]) if not loot.is_empty() else "."
				var up4 := i
				if i + 1 < n and bool((evs[i + 1] as Dictionary).get("capitalLevy", false)):
					up4 = i + 1 ## the levy shows with the fall
				out.append({"upto": up4, "caption": "%s's capital falls!" % _name(str(e["playerId"])), "sub": sub4, "sound": "capital_fall", "delay": 2.6,
					"focus": [fell], "flash": fell, "flash_text": "CAPITAL TAKEN", "capital_taken": str(e["playerId"]), "capital_by": by})
				i = up4
			Types.EVENT_FORTUNE:
				## v1.8: the dice have been cruel to someone: Fortune pays what she owes
				var fp: String = str(e["playerId"])
				out.append({"upto": i, "caption": "Fortune owes %s a favour" % _name(fp), "sub": "The dice have been cruel. ✦ %d in hand: after an exchange that goes badly, throw it again." % int(e.get("fortune", 1)),
					"sound": "fortune_gained" if Audio.has_sfx("fortune_gained") else "war_chest", "delay": 1.8, "fortune_to": fp})
			Types.EVENT_CAPITAL_FOUNDED:
				if str(e.get("why", "")) == "fallen":
					## v1.12 (rules 20): the court's guard comes with it: one fresh troop, the walls manned
					var up5 := i
					var guard := 0
					var dug5 := 0
					while up5 + 1 < n and (bool((evs[up5 + 1] as Dictionary).get("courtGuard", false)) or bool((evs[up5 + 1] as Dictionary).get("court", false))):
						up5 += 1
						guard += int((evs[up5] as Dictionary).get("added", 0)) if bool((evs[up5] as Dictionary).get("courtGuard", false)) else 0
						dug5 = int((evs[up5] as Dictionary).get("garrison", dug5)) if bool((evs[up5] as Dictionary).get("court", false)) else dug5
					var sub5: String = "%s's new capital. They may move it in their next reinforcement phase." % _name(str(e["playerId"]))
					if guard > 0:
						sub5 = "%s's new capital: the court's guard arrives (+%d)%s. They may move it in their next reinforcement phase." % [
							_name(str(e["playerId"])), guard, (" and %d dig in behind the walls" % dug5) if dug5 > 0 else ""]
					out.append({"upto": up5, "caption": "The court flees to %s" % _hex(str(e["terrId"])), "sub": sub5,
						"sound": "banner", "delay": 1.6 if guard == 0 else 2.2, "focus": [str(e["terrId"])], "flash": str(e["terrId"]), "flash_text": "NEW CAPITAL"}) ## v1.13: its flag goes up
					i = up5
			Types.EVENT_CARDS_CAPTURED:
				if bool(e.get("plunder", false)):
					i += 1
					continue ## told with the capital's fall
				var cc: Array = e["cards"]
				var kinds: Array = []
				for c in cc:
					kinds.append(_card_label(str(c)))
				if e.has("split"):
					## v1.9: several took the fallen commander's last lands at once: the dice divide the chest
					var sp: Dictionary = e["split"]
					var order: Array = sp.get("order", [])
					if not order.is_empty() and str(order[0]) == str(e["to"]):
						var parts: Array = []
						var throws: Array = []
						for q in order:
							var got: int = int((sp["shares"] as Dictionary).get(q, 0))
							parts.append("%s throws %d: %s" % [_name(str(q)), int((sp["rolls"] as Dictionary).get(q, 0)), ("%d card%s" % [got, "" if got == 1 else "s"]) if got > 0 else "nothing"])
							throws.append({"pid": str(q), "value": int((sp["rolls"] as Dictionary).get(q, 0))})
						out.append({"upto": i, "caption": "%s's war chest is divided" % _name(str(e["from"])),
							"sub": "Their last lands fell to %d commanders at once, so the dice share out the %d cards. %s." % [order.size(), int(sp.get("of", 0)), "; ".join(parts)],
							"sound": "dice_click", "delay": 4.2, "split_throws": throws})
					if cc.is_empty():
						i += 1
						continue
					out.append({"upto": i, "caption": "%s %s" % [Style.says(_name(str(e["to"])), "takes"), "%d of the cards" % cc.size()],
						"sub": ", ".join(kinds) + ".", "sound": "", "delay": 1.8,
						"cards_to": str(e["to"]), "cards_from": str(e["from"]), "cards": cc})
					i += 1
					continue
				out.append({"upto": i, "caption": "%s %s's war chest" % [Style.says(_name(str(e["to"])), "seizes"), _name(str(e["from"]))],
					"sub": "Every card they held changes hands: %s." % ", ".join(kinds), "sound": "", "delay": 2.8,
					"cards_to": str(e["to"]), "cards_from": str(e["from"]), "cards": cc})
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


func _card_label(c: String) -> String:
	## "Infantry (Ridge)" for a v1.6 card, "Infantry" for an old one
	var k: String = c.get_slice("@", 0)
	var nm: String = str({"sun": "Infantry", "moon": "Cavalry", "star": "Artillery", "wild": "Wild"}.get(k, k))
	return nm + ((" (%s)" % _hex(c.get_slice("@", 1))) if c.contains("@") else "")


func _stage_of(kind: String, after_surge: bool) -> String:
	match kind:
		Types.EVENT_CLASH:
			return "surge" if after_surge else "clash"
		Types.EVENT_INVASION, Types.EVENT_MELEE, Types.EVENT_SCRAMBLE, Types.EVENT_SPOILS, Types.EVENT_OCCUPIED:
			return "surge" if after_surge else "assault"
		Types.EVENT_PLAYER_ELIMINATED, Types.EVENT_CARDS_CAPTURED, Types.EVENT_CAPITAL_TAKEN, Types.EVENT_FORTUNE:
			return "reckoning"
	return ""


func _stage_beat(st: String, upto: int) -> Dictionary:
	var t := {
		"clash": ["BORDER CLASHES", "Columns that march on each other meet in the field first."],
		"assault": ["THE ASSAULTS", "Every army reaches its target. Defenders stand; the empty fall to whoever arrives."],
		"surge": ["THE SURGES", "Every breakthrough charges on at once, after all the other battles."],
		"reckoning": ["THE RECKONING", "Lands held dig in, cards are drawn, the fallen are counted."],
	}
	if not t.has(st):
		return {}
	return {"upto": maxi(0, upto), "caption": t[st][0], "sub": t[st][1], "sound": "phase_tap", "delay": 1.1, "stage": st}


func _fight_beat(upto: int, title: String, subtitle: String, a: String, a_size: int, a_die: int, b: String, b_size: int, b_die: int, a_won: bool, left: int, sub: String, focus: Array, dest: String) -> Dictionary:
	return {
		"upto": upto, "caption": title, "sub": subtitle if subtitle != "" else sub, "fight": true,
		"a": a, "a_size": a_size, "a_die": a_die, "b": b, "b_size": b_size, "b_die": b_die,
		"a_won": a_won, "left": left, "focus": focus, "delay": 1.9, "resolves": dest,
	}


func _show(b: Dictionary) -> void:
	## v1.12: every clash already told has its arrows settled, even one whose card was skipped
	## before its dice landed (the loser's arrow used to stay on the map)
	for k in range(0, mini(index, beats.size())):
		_settle_arrows(beats[k], k)
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
	_banner.visible = not b.has("stage") ## a stage has the big banner of its own
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
		board.orders = []
		for pk in _packets:
			if not bool(pk.get("late", false)):
				board.orders.append(pk.duplicate(true))
	if b.has("surge_arrow"):
		var sa: Dictionary = (b["surge_arrow"] as Dictionary).duplicate(true)
		sa["born"] = board.now()
		sa.erase("late")
		board.orders.append(sa)
	if b.has("resolves") and str(b["resolves"]) != "":
		_resolved[str(b["resolves"])] = true
	for o in board.orders:
		o["alpha"] = 0.28 if _resolved.has(str(o["to"])) else 1.0
		## a surge: the hop that took the land stays lit, so A → B → C reads as one march
		if b.has("surge_arrow") and str(o["to"]) == str(b["surge_arrow"]["from"]) and str(o.get("owner", "")) == str(b["surge_arrow"]["owner"]):
			o["alpha"] = 0.75
	var focus: Array = b.get("focus", [])
	board.battle = {}
	for f in focus:
		board.battle[f] = true
	board.focus_on(focus)
	## the fight that's on: its lands ringed, everyone else dimmed, its arrows bright
	board.dimmed = {}
	board.clash = []
	var ev: Dictionary = b.get("event", {})
	if bool(b.get("fight", false)) or b.has("walkin"):
		for t in board.world.territories.keys():
			if not focus.has(str(t)):
				board.dimmed[str(t)] = true
		var land: String = str(b.get("resolves", ""))
		for o in board.orders:
			var live: bool = (land != "" and str(o["to"]) == land) or (focus.has(str(o["from"])) and focus.has(str(o["to"])))
			if live:
				o["alpha"] = 1.0
			else:
				o["alpha"] = 0.28 if _resolved.has(str(o["to"])) else 0.4
	if str(ev.get("kind", "")) == Types.EVENT_CLASH:
		board.clash = [str(ev["hexA"]), str(ev["hexB"])]
		Audio.sfx("border_clash", -2.0)
		_caption.text = "BORDER CLASH!"
	_card.visible = bool(b.get("fight", false)) and not bool(b.get("melee", false)) and not bool(b.get("scramble", false))
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
	shown.emit()


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
		board.swoop_back(0.6)
		var grp: Array = _group_at(_group_first)
		var last_index: int = _group_first + grp.size() - 1
		_group_first = -1
		index = last_index
		var lb: Dictionary = beats[last_index]
		for g in grp:
			if str(g.get("resolves", "")) != "":
				_resolved[str(g["resolves"])] = true
			_settle_arrows(g)
		for o in board.orders:
			o["alpha"] = 0.28 if _resolved.has(str(o["to"])) else 1.0
		board.world = ViewEvents.apply_through(_pre, _events, int(lb["upto"]))
		board.refresh()
		shown.emit()
		if skip_rest:
			_theater_off = true
		_wait = 0.4
	theater.finished.connect(_theater_cb, CONNECT_ONE_SHOT)
	## the camera swoops down on the fight, then the battlefield opens
	var land: String = str(first.get("resolves", ""))
	var focus: Array = first.get("focus", [])
	board.battle = {}
	board.dimmed = {}
	for f in focus:
		board.battle[f] = true
	for t in board.world.territories.keys():
		if not focus.has(str(t)):
			board.dimmed[str(t)] = true
	board.clash = [str(focus[0]), str(focus[1])] if bool(first.get("event", {}).get("kind", "") == Types.EVENT_CLASH) and focus.size() >= 2 else []
	board.refresh()
	Audio.sfx("zoom_in", -3.0)
	var tw: Tween = board.swoop_to(focus if not focus.is_empty() else [land], 2.8, 0.8)
	var go := func():
		if _waiting and _active:
			theater.set("view", board.world) ## v1.9: Fortune's counts as these fights begin
			theater.play(session, group, human)
	if tw != null:
		tw.finished.connect(go, CONNECT_ONE_SHOT)
	else:
		go.call()


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
	_result.text = ""
	_roll_final = Vector2i(int(b["a_die"]), int(b["b_die"]))
	## the deciding throw, each die made of what its army could afford
	var fast: bool = Settings.battle_delay() < 0.8
	_dice.gravity = 46.0 if fast else 36.0
	_dice.pace = 1.5 if fast else 1.1
	var dur: float = _dice.throw([
		{"value": _roll_final.x, "n": int(b["a_size"]), "tint": Style.seat_color(str(b["a"])), "to": Vector2(-0.8, 0.0), "from": Vector3(-3.4, 2.4, -0.4)},
		{"value": _roll_final.y, "n": int(b["b_size"]), "tint": Style.seat_color(str(b["b"])), "to": Vector2(0.8, 0.0), "from": Vector3(3.4, 2.4, -0.4), "delay": 0.04}])
	_rolling = dur + 0.05
	Audio.sfx("dice_shake", -6.0)
	## the map shows the moment before the result
	board.world = ViewEvents.apply_through(_pre, _events, int(b["upto"]) - (1 if int(b["upto"]) > 0 and str(_events[int(b["upto"])]["kind"]) == Types.EVENT_OCCUPIED else 0) - 1)
	board.refresh()


func _settle_arrows(b: Dictionary, k: int = -1) -> void:
	## v1.6: a column that lost a border clash no longer marches: its arrow goes, and the
	## winner's arrow carries only the men still standing. Once per clash (k: its beat).
	var ev: Dictionary = b.get("event", {})
	if str(ev.get("kind", "")) != Types.EVENT_CLASH:
		return
	if k < 0:
		k = beats.find(b)
	if k >= 0:
		if _settled.has(k):
			return
		_settled[k] = true
	var wid: String = str(ev.get("winnerId", ""))
	var a_pid: String = str(ev.get("playerA", ""))
	var b_pid: String = str(ev.get("playerB", ""))
	var ha: String = str(ev.get("hexA", ""))
	var hb: String = str(ev.get("hexB", ""))
	var loser: String = b_pid if wid == a_pid else a_pid
	var loser_to: String = ha if loser == b_pid else hb
	var win_to: String = hb if wid == a_pid else ha
	var keep: Array = []
	var win_done := false
	for o in board.orders:
		if str(o.get("owner", "")) == loser and str(o["to"]) == loser_to:
			continue
		if str(o.get("owner", "")) == wid and str(o["to"]) == win_to:
			if win_done:
				continue
			win_done = true
			o["strength"] = int(ev.get("winnerRemaining", o["strength"]))
		keep.append(o)
	board.orders = keep
	board.refresh()


func _reveal_result() -> void:
	call_deferred("emit_signal", "shown")
	_settle_arrows(_fight)
	var b: Dictionary = _fight
	if b.is_empty():
		return
	var ta: int = int(b["a_size"]) + int(b["a_die"])
	var tb: int = int(b["b_size"]) + int(b["b_die"])
	var a_won: bool = bool(b["a_won"])
	var ev0: Dictionary = b.get("event", {})
	if (ev0.get("rolls", []) as Array).size() > 0 and (ev0["rolls"][0] as Dictionary).has("sa"):
		## volleys: the card tells the whole fight, men in and men left
		var a_end: int = int(b["left"]) if a_won else int(ev0.get("attackerLeft", 0))
		var b_end: int = 0 if a_won else int(b["left"])
		_left.tally(int(b["a_size"]) + int(ev0.get("reservesAdded", 0)), a_end)
		_right.tally(int(b["b_size"]), b_end)
	else:
		_left.total(ta)
		_right.total(tb)
	_dice.mark(0, "win" if a_won else "lose")
	_dice.mark(1, "lose" if a_won else "win")
	var winner: String = str(b["a"]) if a_won else str(b["b"])
	var loser: String = str(b["b"]) if a_won else str(b["a"])
	var inv: bool = bool(b.get("invasion", false))
	var ev: Dictionary = b.get("event", {})
	var txt := ""
	## v1.13: a fight won against the odds says so on the card, and on the map
	var fell0: bool = inv and bool(ev.get("fellBack", false))
	var fort0: int = MapLib.defender_bonus(_pre, session.map, str(b.get("resolves", ""))) if inv and _pre != null else 0
	var against: bool = not fell0 and Moments.upset(inv, int(b["a_size"]), int(b["b_size"]), a_won, fort0)
	if against:
		txt = "Against the odds!  "
		Audio.sfx("fanfare_order", -8.0)
	if int(ev.get("reservesAdded", 0)) > 0:
		txt = "Reserves +%d!  " % int(ev["reservesAdded"])
		Audio.sfx("reserves", -4.0)
	if inv and bool(ev.get("fellBack", false)):
		txt += "%s back to %s — %d saved" % [Style.says(_name(str(b["a"])), "falls"), _hex(str(ev.get("refuge", ""))), int(ev.get("attackerLeft", 0))]
		Audio.sfx("retreat")
	elif inv:
		if a_won:
			txt += "%s %s with %d left" % [Style.says(_name(winner), "takes"), _hex(str(b["resolves"])), int(b["left"])]
			if ta == tb:
				txt += "  (ties go to the attacker)"
			Audio.sfx("capture")
		else:
			txt += "%s! %d remain" % [Style.says(_name(winner), "holds"), int(b["left"])]
			Audio.sfx("hold")
	else:
		txt = "%s with %d left — %s destroyed" % [Style.says(_name(winner), "wins"), int(b["left"]), Style.says(_name(loser), "is")]
		Audio.sfx("clash")
	_result.text = txt
	_result.add_theme_color_override("font_color", Style.seat_color(winner).lightened(0.35))
	if not (inv and bool(ev.get("fellBack", false))):
		var cheering: int = int(b["left"])
		get_tree().create_timer(0.3).timeout.connect(func(): Audio.cheer(cheering, -12.0)) ## a distant cheer, as big as the army that won
	_apply(b)
	if inv and a_won:
		board.float_text(str(b["resolves"]), "Against the odds!" if against else "Captured", Style.GOLD, 1.8, 26)
	elif against:
		board.float_text(str(b["resolves"]) if str(b["resolves"]) != "" else str((b["focus"] as Array)[0]), "Against the odds!", Style.GOLD, 1.8, 26)
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

	func tally(start: int, end: int) -> void:
		_size.text = "%d → %d" % [start, end]


class _Mark extends Control:
	const Style := preload("res://game/core/style.gd")
	var pid := ""

	func _draw() -> void:
		if pid == "":
			return
		Style.draw_shape(self, Style.seat_shape(pid), size * 0.5, 17.0, Style.seat_color(pid), Style.CREAM, 2.0)
