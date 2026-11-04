## v2.6 the war's chips, big enough for a touchpad and older eyes (Alex's call C17, 3 Nov 2026: raise them, in a
## pass of their own). v2.5 measured Auto-place, Clear, Cards, Review, ◀ Recruits, ? Dice, Auto-roll and Skip
## battles at 22 to 24 px on a 1366×768 laptop (docs/v25/v25-pass.md). A war walked from the claims to the
## regroup and a second round's battle; at each step, on each screen below, as facts:
## - every chip stands at least 30 px tall in the screen's own pixels (about 32 on the laptop);
## - none runs off the screen, or over another chip, the dial or the bar's words;
## - the dial (PICK, SEAL, ORDERS, ROLL) is whole;
## - the bar's words stay inside it, his advice at 14 px or more and in full, the tutorial's longest lesson too,
##   and the tally at its longest (its hint cut short, every word in its tooltip, where there's no room);
## and every chip answers a click on it, as do the bigger ways round: the dial, Space, Esc, C
##   SHOT_DIR=/dir ./scripts/shot.sh v26
extends RefCounted

const Session := preload("res://game/core/session.gd")
const Counsel := preload("res://game/core/counsel.gd")
const MapLib := preload("res://engine/map.gd")
const CardsDialog := preload("res://game/ui/cards_dialog.gd")
const PlanDialog := preload("res://game/ui/plan_dialog.gd")

## [the window as the game gets it, its text size, a name]
const SCREENS := [
	[Vector2i(1440, 900), 1.0, "1440"], ## the house standard (CLAUDE.md), Normal text
	[Vector2i(1440, 900), 1.15, "1440 Large"],
	[Vector2i(1366, 705), 1.15, "laptop"], ## a 1366×768 screen: maximized under its title bar and taskbar, at Large (its first launch's)
	[Vector2i(1920, 985), 1.15, "1080p 150%"], ## a 1920×1080 laptop at Windows' 150% (1020 above its taskbar): the same
]
const LEAST := 30.0 ## the least a chip stands, in the screen's own pixels, on any of them

var p
var main: Control
var gs: Control
var s: Node
var _heights := {} ## a chip's words -> {screen: px}, for the table at the end
var _order: Array = [] ## the chips in the order they were met


func run(probe) -> void:
	p = probe
	for k in ["music", "sfx", "ambience", "voices"]:
		Settings.data[k] = 0.0
	Settings.data["speed"] = "fast"
	Settings.data["battles"] = "all"
	Settings.data["roll_yourself"] = true
	Settings.data["dice_help_seen"] = 2 ## (the dice help waits for ? Dice)
	main = load("res://game/main.tscn").instantiate()
	p.get_tree().root.add_child(main)
	await p.frames(5)
	p.get_window().min_size = Vector2i(200, 200)
	main.start_game({"map": "res://maps/known24.json", "seed": 26, "length": "standard", "timer": 0, "deal": "draft", "seats": [
		{"id": "red", "name": "Dad", "kind": "human", "ai": "", "portrait": "player"},
		{"id": "blue", "name": "Captain Oren", "kind": "ai", "ai": "oren", "portrait": "oren"},
		{"id": "green", "name": "Governor Quill", "kind": "ai", "ai": "quill", "portrait": "quill"}]})
	await p.frames(10)
	s = main.session
	gs = main.current
	await _claims()
	await _deployment()
	await _recruits()
	await _orders()
	await _battle()
	await _report()
	await _regroup()
	await _escape()
	_table()
	await _on(SCREENS[0])
	p.log("v26 probe done")


# ------------------------------------------------------------------ the war, step by step

func _claims() -> void:
	## the claims: Hurry while the others pick, the advisor's pick (a chip, and the dial) on your turn
	await _until(func(): return gs._seating_now(), 120)
	await _key(KEY_ESCAPE) ## (no more introductions: the rest throw together)
	await _until(func(): return gs._draft_state == "picking", 1800)
	var hurried := false
	var picked := false
	var guard := 0
	while s.phase == Session.Phase.DRAFT and guard < 4000 and not (hurried and picked):
		guard += 1
		if gs._draft_state == "picking" and not gs._claim_wait and s.drafting():
			if not s.is_human(s.draft_turn()) and not hurried:
				p.steady(true, 0.000001) ## (the rival's pick waits while the screens are measured and the chip clicked)
				await _measure("claims_others", "the claims, a rival picking", _bar_chips, _bar_words, _bar_dial)
				await _on(SCREENS[2])
				await _click(_chip(gs.bar, "Hurry"))
				p.ok(gs.draft_fast, "the claims: Hurry ▶▶ hurries the rivals' picks")
				p.steady(false)
				hurried = true
			elif s.is_human(s.draft_turn()) and not picked:
				await p.frames(20)
				await _measure("claims", "the claims, your pick", _bar_chips, _bar_words, _bar_dial)
				await _on(SCREENS[2])
				var mine: int = _lands("red")
				await _click(_chip(gs.bar, "Advisor's pick"))
				await _until(func(): return _lands("red") > mine, 60)
				p.ok(_lands("red") == mine + 1, "the claims: Advisor's pick claims the advisor's choice (%d lands)" % _lands("red"))
				await _until(func(): return s.phase != Session.Phase.DRAFT or (s.is_human(s.draft_turn()) and not gs._claim_wait), 900)
				if s.phase == Session.Phase.DRAFT:
					mine = _lands("red")
					await _click(_bar_dial())
					await _until(func(): return _lands("red") > mine, 60)
					p.ok(_lands("red") == mine + 1, "the claims: and the dial (PICK) does it too (%d lands)" % _lands("red"))
				picked = true
		await p.frames(1)
	p.ok(hurried and picked, "the claims: both chips were met (Hurry %s, Advisor's pick %s)" % [hurried, picked])
	guard = 0
	while s.phase == Session.Phase.DRAFT and guard < 6000:
		guard += 1
		if gs._draft_state == "picking" and s.drafting() and s.is_human(s.draft_turn()) and not gs._claim_wait:
			gs.draft_advise()
		await p.frames(1)


func _deployment() -> void:
	await _until(func(): return s.phase == Session.Phase.OPENING and s.is_human(s.planner) and not gs._seating_now(), 2400)
	await p.frames(30)
	await _measure("deployment", "the deployment", _bar_chips, _bar_words, _bar_dial)
	await _on(SCREENS[2])
	await _place_and_clear("the deployment")
	await _click(_bar_dial())
	await _until(func(): return s.phase == Session.Phase.PLANNING, 900)
	p.ok(s.phase == Session.Phase.PLANNING, "the deployment: the dial (SEAL) seals it (phase %d)" % s.phase)


func _recruits() -> void:
	await _until(func(): return s.phase == Session.Phase.PLANNING and s.plan_step == "reinforce" and s.is_human(s.planner), 2400)
	await p.frames(40)
	await _measure("recruits", "the recruits", _bar_chips, _bar_words, _bar_dial)
	await _long_tally()
	await _on(SCREENS[2])
	await _place_and_clear("the recruits")
	await _click(_chip(gs.bar, "Cards"))
	await p.frames(8)
	var opened: bool = _cards_open()
	await _key(KEY_ESCAPE)
	await p.frames(8)
	p.ok(opened and not _cards_open(), "the recruits: Cards opens the hand, and Esc puts it away")
	await _key(KEY_C)
	await p.frames(8)
	opened = _cards_open()
	await _key(KEY_ESCAPE)
	await p.frames(8)
	p.ok(opened and not _cards_open(), "the recruits: C opens it too")
	await _click(_chip(gs.bar, "Advisor's plan"))
	await p.frames(8)
	opened = _plan_open()
	await _key(KEY_ESCAPE)
	await p.frames(8)
	p.ok(opened and not _plan_open(), "the recruits: ✦ Advisor's plan opens his plan, and Esc keeps your own")
	await _click(_chip(gs.bar, "Auto-place"))
	await p.frames(4)
	await _click(_bar_dial())
	await _until(func(): return s.plan_step == "orders", 120)
	p.ok(s.plan_step == "orders", "the recruits: the ORDERS dial goes on to the orders")


func _orders() -> void:
	Counsel.adopt(s, Counsel.draft(s)) ## (the advisor's attacks, so there are battles to watch)
	await p.frames(40)
	await _measure("orders", "the orders", _bar_chips, _bar_words, _bar_dial)
	await _long_advice()
	await _on(SCREENS[2])
	await _click(_chip(gs.bar, "Review"))
	await p.frames(6)
	var shown: bool = gs.drawer.visible
	await _click(_chip(gs.bar, "Review"))
	await p.frames(6)
	p.ok(shown and not gs.drawer.visible, "the orders: Review opens the drawer, and again puts it away")
	var attacks: int = s.sheet().packets.size()
	await _click(_chip(gs.bar, "Recruits"))
	await p.frames(6)
	p.ok(s.plan_step == "reinforce", "the orders: ◀ Recruits goes back to the recruits")
	await _click(_bar_dial())
	await _until(func(): return s.plan_step == "orders", 120)
	p.ok(s.plan_step == "orders" and s.sheet().packets.size() == attacks, "the orders: the dial comes back to them, the %d attacks kept" % attacks)
	await _click(_bar_dial())
	await _until(func(): return s.phase != Session.Phase.PLANNING, 300)
	p.ok(s.phase != Session.Phase.PLANNING, "the orders: the dial (SEAL) seals them (phase %d)" % s.phase)


func _battle() -> void:
	## your battle, waiting for your throw: Auto-roll, ? Dice and Skip battles under the dice
	var th: Control = gs.theater
	await _until(func(): return th.visible and str(th._state) == "ready" and th._human, 4000)
	if not (th.visible and str(th._state) == "ready"):
		p.fail("the battle: none of yours opened on the battlefield")
		return
	await p.frames(30)
	await _measure("battle", "your battle", _battle_chips, _battle_words, _battle_dial)
	await _on(SCREENS[2])
	await _click(_chip(th, "? Dice"))
	await p.frames(4)
	var help: bool = th._help.visible
	await _click(_chip(th, "? Dice"))
	await p.frames(4)
	p.ok(help and not th._help.visible, "the battle: ? Dice opens the dice's rules, and again puts them away")
	await _click(_chip(th, "Auto-roll"))
	await p.frames(4)
	var auto: bool = not th.manual
	await _click(_chip(th, "Roll myself"))
	await p.frames(4)
	p.ok(auto and th.manual, "the battle: Auto-roll rolls on its own, and Roll myself gives the dice back")
	await _until(func(): return str(th._state) == "ready", 300)
	var ex: int = th._exchange
	await _key(KEY_SPACE)
	await p.frames(2)
	p.ok(str(th._state) != "ready" or th._exchange != ex, "the battle: Space throws the dice (%s)" % th._state)
	await _until(func(): return str(th._state) in ["ready", "call", "done"], 600)
	await _click(_chip(th, "Skip battles"))
	await _until(func(): return not th.visible, 120)
	p.ok(not th.visible, "the battle: Skip battles leaves the battlefield, the rest settled on the map")


func _report() -> void:
	## the round's battles on the map: pause and skip are chips
	await _until(func(): return s.phase == Session.Phase.CINEMA and gs.cinema.visible and not gs.theater.visible, 600)
	if s.phase != Session.Phase.CINEMA:
		p.log("the battle report was over before it was seen (phase %d)" % s.phase)
		return
	p.steady(true, 0.000001) ## (the report waits while the screens are measured)
	await _measure("report", "the battle report", _bar_chips, _bar_words, _bar_dial)
	await _on(SCREENS[2])
	await _click(_chip(gs.bar, "❚❚"))
	await p.frames(2)
	var paused: bool = gs.cinema.paused
	await _click(_chip(gs.bar, "❚❚"))
	await p.frames(2)
	p.ok(paused and not gs.cinema.paused, "the battle report: ❚❚ / ▶ pauses it, and again goes on")
	p.steady(false)
	await _click(_chip(gs.bar, "Skip ▶▶"))
	await _until(func(): return s.phase == Session.Phase.RECAP, 600)
	p.ok(s.phase == Session.Phase.RECAP, "the battle report: Skip ▶▶ goes to the round's report (phase %d)" % s.phase)


func _regroup() -> void:
	await _until(func(): return s.phase == Session.Phase.RECAP and gs.recap.visible, 600)
	await p.frames(70) ## (the report takes Space only after its first moment)
	await _key(KEY_SPACE)
	await _until(func(): return s.phase == Session.Phase.MANEUVER and s.is_human(s.planner), 1200)
	if s.phase != Session.Phase.MANEUVER:
		p.fail("the regroup never came (phase %d)" % s.phase)
		return
	await p.frames(30)
	await _measure("regroup", "the regroup", _bar_chips, _bar_words, _bar_dial)
	await _on(SCREENS[2])
	await _click(_chip(gs.bar, "Advisor's marches"))
	await p.frames(4)
	var marched: int = s.my_moves().size()
	await _click(_chip(gs.bar, "Clear"))
	await p.frames(4)
	p.ok(marched > 0 and s.my_moves().is_empty(), "the regroup: Advisor's marches orders %d, and Clear takes them back" % marched)
	await _click(_bar_dial())
	await _until(func(): return s.phase == Session.Phase.PLANNING, 600)
	p.ok(s.phase == Session.Phase.PLANNING, "the regroup: the dial (MARCH) seals the marches (phase %d)" % s.phase)


func _escape() -> void:
	## the second round: Esc on the battlefield settles the rest, as Skip battles does
	await _until(func(): return s.phase == Session.Phase.PLANNING and s.is_human(s.planner), 1200)
	await p.frames(20)
	s.auto_deploy()
	if s.plan_step != "orders":
		s.begin_orders()
	Counsel.adopt(s, Counsel.draft(s))
	await p.frames(6)
	s.lock()
	var th: Control = gs.theater
	await _until(func(): return th.visible and str(th._state) in ["ready", "rolling", "wait", "call", "done"], 4000)
	if not th.visible:
		p.fail("the second round: no battle opened on the battlefield")
		return
	await p.frames(20)
	if th._help.visible:
		await _click(_chip(th, "? Dice"))
	await _key(KEY_ESCAPE)
	await _until(func(): return not th.visible, 120)
	p.ok(not th.visible, "the second round: Esc on the battlefield settles the rest on the map")


func _long_advice() -> void:
	## the longest words the advisor has, the tutorial's lesson in round 2 (330 characters), with his plan and his
	## pages under them: the bar holds them on every screen, a point smaller where it must, never below 14 px;
	## where even that can't hold them all, they're cut short with … and every word is in their tooltip
	var tut: bool = bool(s.config.get("tutorial", false))
	var r0: int = s.world.round
	s.config["tutorial"] = true
	s.world.round = 2
	var les: Dictionary = Counsel.lesson(s, -1)
	s.config["tutorial"] = tut
	s.world.round = r0
	if str(les.get("text", "")).length() < 300:
		p.fail("the tutorial's round-2 lesson wasn't found (%s)" % str(les.get("key", "")))
		return
	var page2 := {"key": "v26", "text": "And a second page.", "mood": "neutral", "voice": "", "focus": [], "rank": 0}
	gs.bar.set_counsel([les, page2])
	await p.frames(6)
	_cut_ok = true
	await _measure("long_advice", "the longest lesson (%d characters)" % str(les["text"]).length(), _bar_chips, _bar_words, _bar_dial)
	## ...and twice that, more than a bar holds at 14 px: cut short at a word, every word in its tooltip
	var twice: String = str(les["text"]) + " " + str(les["text"])
	gs.bar.set_counsel([{"key": "v26b", "text": twice, "mood": "neutral", "voice": "", "focus": [], "rank": 0}, page2])
	await p.frames(6)
	_cuts = 0
	await _measure("too_long_advice", "twice the longest lesson (%d characters)" % twice.length(), _bar_chips, _bar_words, _bar_dial)
	p.ok(_cuts > 0, "twice the longest lesson: where no size from 14 px up holds it, it's cut short at a word with … (%d of %d screens; in full on the rest)" % [_cuts, SCREENS.size()])
	_cut_ok = false
	gs._update_counsel()
	await p.frames(6)


func _long_tally() -> void:
	## the tally at its longest, late in a war: its count on two lines ("· 2 no room") over the hint with cards in
	## hand. The hint gives way in its column, a point at a time, then cut short with every word in its tooltip, or
	## steps aside where not a word fits; the chips under it stay on the screen
	var bar: Control = gs.bar
	var hint := "3 cards in hand · Click your lands to place them · right-click takes one back"
	(bar.get("_tally") as Label).text = "12 of 12 recruits placed · 2 no room"
	bar.set("_hint", hint)
	(bar.get("_tally_sub") as Label).text = hint
	bar.call("_fit_soon")
	await p.frames(6)
	_hint_ok = true
	await _measure("long_tally", "the longest tally", _bar_chips, _bar_words, _bar_dial)
	## ...and a hint three times that: it gives way, and the chips under it stay
	var thrice := " · ".join([hint, hint, hint])
	bar.set("_hint", thrice)
	(bar.get("_tally_sub") as Label).text = thrice
	bar.call("_fit_soon")
	await p.frames(6)
	_hint_cuts = 0
	await _measure("too_long_tally", "a hint three times the longest", _bar_chips, _bar_words, _bar_dial)
	p.ok(_hint_cuts == SCREENS.size(), "a hint three times the longest: cut short, or stepped aside, on %d of %d screens" % [_hint_cuts, SCREENS.size()])
	_hint_ok = false
	bar.refresh()
	await p.frames(6)


func _place_and_clear(step: String) -> void:
	## Auto-place puts every recruit down, Clear takes them back up
	await _click(_chip(gs.bar, "Auto-place"))
	await p.frames(4)
	var placed: int = s.placed_total()
	var want: int = s.income_total()
	await _click(_chip(gs.bar, "Clear"))
	await p.frames(4)
	p.ok(placed > 0 and placed >= want - s.no_room() and s.placed_total() == 0,
		"%s: Auto-place puts them all down (%d of %d), Clear takes them back (%d)" % [step, placed, want, s.placed_total()])
	await _click(_chip(gs.bar, "Auto-place"))
	await p.frames(4)


# ------------------------------------------------------------------ the measure

func _measure(key: String, step: String, chips: Callable, words: Callable, dial: Callable) -> void:
	## on every screen: each chip's height in the screen's own pixels, none off the screen or over another
	## chip, the dial or the words, and the dial whole
	var least: Array = []
	var short: Array = []
	var bad: Array = []
	var cut: Array = []
	var names: Array = []
	for sc in SCREENS:
		await _on(sc)
		var tag: String = sc[2]
		var vp: Viewport = main.get_viewport()
		var k: float = vp.get_final_transform().get_scale().y
		var vis: Rect2 = vp.get_visible_rect()
		var list: Array = chips.call()
		var low := INF
		var rects: Array = []
		for c in list:
			var b: Control = c
			var r: Rect2 = b.get_global_rect()
			var h: float = r.size.y * k
			var nm: String = _name(b)
			low = minf(low, h)
			_note(nm, tag, h)
			if not names.has(nm):
				names.append(nm)
			if h < LEAST:
				short.append("%s: '%s' %.1f" % [tag, nm, h])
			if not vis.encloses(r):
				bad.append("%s: '%s' off the screen %s in %s" % [tag, nm, str(Rect2i(r)), str(Vector2i(vis.size))])
			rects.append([nm, r])
		for i in rects.size():
			for j in range(i + 1, rects.size()):
				if (rects[i][1] as Rect2).grow(-0.5).intersects((rects[j][1] as Rect2).grow(-0.5)):
					bad.append("%s: '%s' over '%s'" % [tag, rects[i][0], rects[j][0]])
			for o in words.call():
				var oc: Control = o
				if (rects[i][1] as Rect2).grow(-0.5).intersects(oc.get_global_rect().grow(-0.5)):
					bad.append("%s: '%s' over %s" % [tag, rects[i][0], _name(oc)])
		var d: Control = dial.call()
		if d == null or not vis.grow(2.0).encloses(d.get_global_rect()):
			cut.append("%s: %s in %s" % [tag, str(Rect2i(d.get_global_rect())) if d != null else "no dial", str(Vector2i(vis.size))])
		if d == gs.bar.get("_dial"):
			_bar_held(tag, vis, k)
		least.append("%s %.0f" % [tag, low if low < INF else 0.0])
		await _snap("v26_%s_%s" % [key, tag.replace(" ", "_").replace("%", "")])
	p.ok(not names.is_empty() and short.is_empty(), "%s: every chip at least %.0f px tall on every screen (the least: %s; %s)" % [step, LEAST, ", ".join(least), ", ".join(names) if short.is_empty() else "; ".join(short)])
	p.ok(bad.is_empty(), "%s: no chip off the screen, or over another, the dial or the words (%s)" % [step, "none" if bad.is_empty() else "; ".join(bad.slice(0, 4))])
	p.ok(cut.is_empty(), "%s: the dial is whole on every screen%s" % [step, "" if cut.is_empty() else " (" + "; ".join(cut) + ")"])
	if dial.call() == gs.bar.get("_dial"):
		var how := "at 14 px or more, in full or cut short at a word, every word in its tooltip" if _cut_ok or _hint_ok else "his advice at 14 px or more and in full"
		p.ok(_held.is_empty(), "%s: the bar holds its words on every screen, %s (%s)" % [step, how, "; ".join(_sizes) if _held.is_empty() else "; ".join(_held.slice(0, 4))])
	_held = []
	_sizes = []


func _bar_chips() -> Array:
	## every chip on the bar: the tally's, the advisor's plan and the pages of his advice
	var out: Array = []
	for c in gs.bar.find_children("*", "Button", true, false):
		var b: Button = c
		if b.is_visible_in_tree() and not b.is_queued_for_deletion():
			out.append(b)
	return out


func _bar_words() -> Array:
	## what a chip mustn't cover on the bar: the dial, its three coins, the tally's words, the advisor, his words
	## and his dispatches
	var out: Array = [gs.bar.get("_dial"), gs.bar.get("_tally_title"), gs.bar.get("_tally"), gs.bar.get("_tally_sub"), gs.bar.get("_counsel"), gs.bar.advisor, gs.bar.commander]
	out.append_array(gs.bar.get("_coins"))
	out.append_array((gs.bar.get("_log") as Node).get_children())
	return out.filter(func(c): return c != null and (c as Control).is_visible_in_tree() and not (c as Node).is_queued_for_deletion() and (c as Control).size.y > 2 and (not (c is Label) or (c as Label).text != ""))


var _held: Array = [] ## the bar's words that ran off it, screen by screen
var _sizes: Array = [] ## his advice's size on each screen, in its pixels
var _cut_ok := false ## (the longest lesson: cut short where it must be, every word in its tooltip)
var _hint_ok := false ## (the longest tally: its hint the same)
var _cuts := 0 ## screens where his advice was cut short, rightly
var _hint_cuts := 0 ## ...and the tally's hint


func _bar_held(tag: String, vis: Rect2, k: float) -> void:
	## the bar's words on the screen and inside the bar, his advice never under 14 px, and in full (or, for the
	## longest lesson, cut short with every word in its tooltip)
	var bar_r: Rect2 = (gs.bar as Control).get_global_rect()
	for c in _bar_words():
		if c is Label:
			var r: Rect2 = (c as Control).get_global_rect()
			if not vis.encloses(r) or r.position.y < bar_r.position.y or r.end.y > bar_r.end.y + 0.5:
				_held.append("%s: '%s' runs off %s" % [tag, (c as Label).text.left(24), str(Rect2i(r))])
	var counsel: Label = gs.bar.get("_counsel")
	var said: String = str(gs.bar.get("_said"))
	var fs: int = counsel.get_theme_font_size("font_size")
	var cut: bool = counsel.text != said
	if cut and (not _cut_ok or counsel.tooltip_text != said or not counsel.text.ends_with("…")):
		_held.append("%s: his advice cut to %d of %d words%s" % [tag, counsel.text.split(" ").size(), said.split(" ").size(), "" if counsel.tooltip_text == said else ", not all in its tooltip"])
	elif cut:
		_cuts += 1
	if fs * k < 13.5:
		_held.append("%s: his advice at %.1f px" % [tag, fs * k])
	_sizes.append("%s %d (%.0f px)%s" % [tag, fs, fs * k, (", %d of %d words, all in its tooltip" % [counsel.text.split(" ").size(), said.split(" ").size()]) if cut else ""])
	var sub: Label = gs.bar.get("_tally_sub")
	var hint: String = str(gs.bar.get("_hint"))
	if sub.text != hint and (not _hint_ok or sub.tooltip_text != hint or not (sub.text.ends_with("…") or not sub.visible)):
		_held.append("%s: the tally's hint cut%s" % [tag, "" if sub.tooltip_text == hint else ", not all in its tooltip"])
	elif sub.text != hint:
		_hint_cuts += 1
	if _hint_ok:
		var sfs: int = sub.get_theme_font_size("font_size")
		_sizes.append("the hint %s" % ("%d (%.0f px)%s" % [sfs, sfs * k, ", cut short" if sub.text != hint else ""] if sub.visible else "stepped aside"))


func _bar_dial() -> Control:
	return gs.bar.get("_dial")


func _battle_chips() -> Array:
	var out: Array = []
	for c in gs.theater.find_children("*", "Button", true, false):
		var b: Button = c
		if b.is_visible_in_tree() and not b.is_queued_for_deletion():
			out.append(b)
	return out


func _battle_words() -> Array:
	## the battlefield's: the dial (ROLL), the advisor at your elbow and the battle's count under him
	var out: Array = [gs.theater.get("_dial"), gs.theater.get("_advisor"), gs.theater.get("_progress")]
	return out.filter(func(c): return c != null and (c as Control).is_visible_in_tree() and (c as Control).size.y > 2 and (not (c is Label) or (c as Label).text != ""))


func _battle_dial() -> Control:
	return gs.theater.get("_dial")


func _name(c: Control) -> String:
	var t: Variant = c.get("text")
	if t != null and str(t) != "":
		return str(t)
	return c.get_class() if c.tooltip_text == "" else c.tooltip_text.left(20)


func _note(nm: String, tag: String, h: float) -> void:
	## the chip's least height on this screen, under its words (one chip whatever its count: "Cards (3)")
	var key: String = "Cards" if nm.begins_with("Cards") else nm
	if not _heights.has(key):
		_heights[key] = {}
		_order.append(key)
	_heights[key][tag] = minf(float(_heights[key].get(tag, INF)), h)


func _table() -> void:
	## each chip's height, screen by screen (the CHANGELOG's before and after)
	var head: Array = []
	for sc in SCREENS:
		head.append(str(sc[2]))
	p.log("chip heights, px: " + " | ".join(head))
	for key in _order:
		var row: Array = []
		for sc in SCREENS:
			row.append("%.1f" % float(_heights[key].get(sc[2], 0.0)))
		p.log("  %s: %s" % [key, " | ".join(row)])


# ------------------------------------------------------------------ the screens

func _on(sc: Array) -> void:
	var win: Window = p.get_window()
	var size: Vector2i = sc[0]
	if win.size != size or absf(win.content_scale_factor - float(sc[1])) > 0.001:
		win.mode = Window.MODE_WINDOWED
		win.size = size
		Settings.data["ui_scale"] = sc[1]
		Settings.apply()
		await p.frames(10)
		if win.size != size:
			p.log("%s: the window is %s here (asked %s)" % [sc[2], str(win.size), str(size)])


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = p.get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_DIR") + "/" + name + ".png")


# ------------------------------------------------------------------ the hand on the mouse and the keys

func _click(c: Control) -> void:
	## a real click at the middle of it, through the window, as a player's
	if c == null:
		p.fail("a chip to click was missing")
		return
	var vp: Viewport = p.get_viewport()
	var pos: Vector2 = vp.get_final_transform() * c.get_global_rect().get_center()
	var mv := InputEventMouseMotion.new()
	mv.position = pos
	mv.global_position = pos
	vp.push_input(mv)
	await p.frames(2)
	var under: Control = vp.call("gui_get_hovered_control") if vp.has_method("gui_get_hovered_control") else null ## (Godot 4.4 on)
	if under != null and under != c and not c.is_ancestor_of(under):
		p.log("the click on '%s' at %s finds %s '%s' over it" % [_name(c), str(Vector2i(pos)), under.get_class(), _name(under)])
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = pos
		e.global_position = pos
		vp.push_input(e)
		await p.frames(1)


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		p.get_viewport().push_input(e)
		await p.frames(1)


func _chip(from: Node, words: String) -> Button:
	for c in from.find_children("*", "Button", true, false):
		var b: Button = c
		if b.is_visible_in_tree() and not b.is_queued_for_deletion() and b.text.contains(words):
			return b
	return null


func _until(cond: Callable, most: int) -> void:
	var guard := 0
	while not cond.call() and guard < most:
		guard += 1
		await p.frames(1)


func _lands(pid: String) -> int:
	return MapLib.player_territory_ids(s.world, pid).size()


func _cards_open() -> bool:
	for c in gs.get_children():
		if c is CardsDialog and not c.is_queued_for_deletion():
			return true
	return false


func _plan_open() -> bool:
	for c in gs.get_children():
		if c is PlanDialog and not c.is_queued_for_deletion():
			return true
	return false
