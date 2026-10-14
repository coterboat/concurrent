## Illustrated rules, one idea per page. Works as a screen or as an in-game overlay.
extends Control

const Style := preload("res://game/core/style.gd")

var main: Control
var overlay := false
var start_page := 0
var page := 0
var _art: TextureRect
var _title: Label
var _body: Label
var _count: Label
var _prev: Button
var _next: Button

const PAGES := [
	["The big idea", "howto_sealed",
	"Every commander writes their orders in secret, at the same time. Nobody moves first. When everyone has sealed their orders, they all happen at once.\n\nThat is the whole game: you are always guessing what everyone else is about to do."],
	["The round", "howto_sealed",
	"Every round has four phases, each announced as it begins:\n\n•  REINFORCEMENT PHASE — place your fresh recruits (and turn in cards).\n•  ORDERS PHASE — choose your attacks and surges, then seal them.\n•  THE BATTLES — everyone's orders happen at once: border clashes first, then the assaults, then every surge together, then the reckoning.\n•  REGROUP PHASE — march troops one land toward the front.\n\nIn hotseat games each commander places and orders in private, behind the cover screen."],
	["Recruits", "howto_cards",
	"Each round you get new armies: one for every three lands you hold (at least 3), a little extra for a big connected empire, and a bonus for every region you hold completely.\n\nYou can place at most 1 + (the number of your own lands touching it) on any single land — so a lonely outpost can't become a fortress overnight. Anything you don't place is lost."],
	["Attack — and leave home", "howto_march",
	"To attack, pick one of your lands and send armies at a neighboring land. Those armies LEAVE HOME the moment orders are sealed. They do not defend the land they left.\n\nEvery land keeps its garrison at home (the gold shield, see Digging in); everyone else may march. Several of your attacks on the same target join together into one force."],
	["The walk-in", "howto_walkin",
	"While your armies are away, somebody else may attack the land you just emptied. If you left one army behind, one attacker might be all it takes.\n\nThis is the groan the game is built on. The faded ghost arrows on the map show where everyone marched last round."],
	["Battles", "howto_clash",
	"Roll by roll (the usual way): each volley, both sides roll a die, multiply it by five and add the men in their firing line (at most five). The lower score loses one man; an even volley is fired again. Roll until one side is gone — or the attacker calls it off (next page). In your own battles you press ROLL.\n\nOne decisive roll (a setup option): armies plus one die, higher total wins, and the winner loses half the loser's size. Both styles give the same odds.\n\nTwo lands attacking each other meet in the field first — a border clash. On the map their two arrows meet on the border, and when the dice land the winner's drives the loser's back and carries on to the land it marched on, with the men still standing.\n\nA melee: when two or more commanders storm the same land, they all fight at once. Every salvo each front fires its own volley, and the defenders' whole firing line answers every front, so a defender can lose a man on every front at once, or win them all. (Without the firing line, a setup option, the defenders split their strength across the fronts.)\n\nYour own columns from different lands are separate fronts too: storm a land from two sides and it's a melee, the defenders holding both. Your fronts never fight each other: whichever stand when the walls fall take the land together. A border clash is fought only by the column crossing that border."],
	["The dice", "howto_dice",
	"Every volley, each side throws a die. Its pips count five men apiece, and the men in its firing line are added on top: at most five fire at once. 4 pips and a full line make 20 + 5 = 25. The higher total wins the volley and the loser loses one man; an even volley is fired again. The sums are on a brass plate on the table's rail under every pair of dice, and the bar at the top shows your chance of winning from here.\n\nSo a big army doesn't win every volley: its extra men are its staying power, the men it can lose while the other side runs out. Two to one still wins almost always; seven against six is only a slight favourite.\n\nYou can see it in the dice, too. A lone holdout throws whittled wood, a company throws old bone, a regiment ivory with its colours in the pips, a brigade lacquer with brass edges, and a grand army of thirty or more throws gold, with gem pips and the imperial star."],
	["Every man for himself", "howto_scramble",
	"When the defenders of a land fall and two or more invaders are still standing, or two armies march into the same empty land, the victors fight it out all at once: a scramble.\n\nEvery army duels every other each salvo, splitting its men among its foes in proportion to their size, so three armies throw three duels at a time. There is no retreat. The last army standing takes the land (and may surge on, if it was ordered to)."],
	["Press, reserves, or fall back", "howto_march",
	"An assault is fought in exchanges of three volleys. After each one, the attacker makes the call:\n\n•  PRESS ON — roll the next exchange.\n•  RESERVES — every soldier still at home who could march joins the fight (once per battle). Home keeps its last man, or just its dug-in defenders — but it is weaker if someone comes for it.\n•  FALL BACK — the survivors march home and the defender holds. If home has fallen, they fall back to your strongest land next to the battle; with nowhere to go, they're cut off and fight on.\n\nWatch your own battles and you make every call. Otherwise your officers follow the standing order on the attack: officer's judgment, to the last man, all in, or fall back if it turns. Border clashes and fights for the spoils have no calls — they're fought to the end."],
	["Surge", "howto_surge",
	"Order a surge like any march: drag from the land you're attacking to the next land beyond it (or press Surge onward on the attack's card). If you take the first land, the men who took it (from every direction) press on together into the second. Click the surge's arrow to choose how many: any number, up to all who survive but the one who stays.\n\nAll surges happen at once, after every other battle — THE SURGES stage of the battle report. Two surges running at each other's lands meet head-on in a border clash.\n\nA surge into a land you also attack directly is a second wave. It arrives after that assault: if the land has already fallen, its men march in to hold it; if it still stands, they storm what is left."],
	["The regroup phase", "howto_march",
	"After the battles, everyone marches troops between their own lands at the same time: drag from one of your lands onto a neighbour of yours. Each soldier moves one land and no further. Those who just arrived stay put, and dug-in defenders never leave.\n\nFeed the front, shore up a land that faces a big stack, or pull back from one that's lost. Then the next round's orders begin."],
	["Digging in", "howto_dugin",
	"Every land keeps a garrison: the men on the gold shield beside its number. They never march. On a land with nobody dug in yet, the one man who must stay behind stands in the garrison, so the shield always shows who stays home and the big number shows exactly who can march.\n\nEvery round you keep a land, one more man digs in, up to three (fewer on a land with few neighbours of yours). Fresh conquests start with just the man who stays.\n\nBoth defend; the field army falls first and the garrison last."],
	["Capitals", "howto_capital",
	"Every commander keeps a capital, marked with a crown. After a random deal you name yours at deployment (the advisor pencils one in; choose 'Make this our capital' on any of your lands to move it). When lands are claimed in turn, your first claim is your capital.\n\n•  It pays the treasury: 2 recruits every round you hold it.\n•  It is a fortress: its defenders fire a line of six, and one more man may dig in there.\n•  On maps with supply, the road home runs to your capital.\n\nIf it falls, the captor plunders it: half your cards (drawn by lot) and 3 fresh troops raised in the city on the spot. The court flees at once to the land deepest among your own, with its guard: one fresh troop, and the garrison there dug in to the full. In your next reinforcement phase you may move it anywhere you hold."],
	["Fortune", "howto_fortune",
	"The dice keep no memory, but Fortune keeps a ledger. Every exchange of every fight you are in is weighed against the odds before it was thrown, and each time the dice have cost you about half a battle's worth, Fortune owes you a favour: ✦. A battle you fell back from counts too. Everyone starts the war with one and can hold three; the stars are beside every commander's name, and the next one fills with gold as the dice owe you.\n\nEvery fight counts toward the next favour: assaults, border clashes, melees, and the scramble for the spoils.\n\nSpend it in a battle you are watching. When an exchange goes badly for you (it ended the battle, or cost you two more men than it cost them), the call plate offers ✦ Fortune (T): that exchange never happened, your fallen stand again, and the dice fly once more. Once a battle for each commander, attacker or defender, and in a melee too, where the exchange is thrown again for everyone in it. Clashes and scrambles have no calls, so no rethrows there.\n\nWhen someone calls on Fortune against you, the exchange they threw away had gone your way: Fortune owes you for it, half what it was worth, toward your next favour.\n\nThe AI commanders earn and spend by the same rules. Your favours are only ever spent by you: skip the battle and they stay in your pocket."],
	["Cards and winning", "howto_cards",
	"On the bigger maps, capturing at least one land in a round earns a card: infantry, cavalry or artillery, each naming a land. Open your hand with the Cards button (or C): three alike, or one of each, turn in for fresh troops: 4, then 6, 8, 10, then 5 more each time anyone turns a set in. Every card naming a land you hold also puts a free soldier there.\n\nTake a commander's last land and you seize their war chest: every card they held is yours. If their last lands fell to several of you in the same round, each victor throws a die and the cards are shared out in proportion to the throws.\n\nThe game ends after the last round: your score is your lands plus the bonus of each region you hold. Holding 80% of the map, or being the last one standing, wins at once."],
	["Fortresses, passes and ports", "howto_fort",
	"Some maps give certain lands a standing character, marked with a small brass emblem on the land itself and spelled out on its card.\n\n•  FORTRESS — its defenders fire a line of six instead of five, and one more man than usual may dig in there. It only tells once the fort holds more than five: five men fire five wherever they stand. Garrison it properly and it is the hardest ground on the map.\n•  PASS — no more than six may storm it from any one land, however many you have there: a surge into it is six at most, and the reserves only top the column back up to six. A huge stack cannot simply roll through; come at it from two lands at once and you bring twelve.\n•  PORT — two of your own ports are joined by sea. Troops may march between them in the regroup phase, and supply runs along them. You cannot attack down a sea link: ships carry the baggage train, not the assault.\n\nOn the land in 3D (L) they stand as buildings: a star fort on a fortress, a blockhouse on a pass, a quay on a port's shore, and a palace flying its commander's colours where a capital stands."],
	["Supply", "howto_supply",
	"On some maps an army needs a road home.\n\nYour empire's main body — the largest run of your own lands, joined by land borders or by your own ports — is IN SUPPLY. Any land of yours cut off from it is not: it pays no income and takes no recruits. The map says CUT OFF across it.\n\nIt still fights. It still holds its ground, and its garrison still digs in. It simply feeds nobody until you join it up again.\n\nSo a conquest that reaches too far is worth nothing until the road behind it is yours, and cutting a neighbour's chain in the middle can strand half their empire without fighting for a single one of those lands."],
	["Reading the map", "howto_march",
	"While you plan, the map says what it knows. Hover any land to read it in words.\n\n•  LAST ROUND'S COLUMNS stay on the map, faint. One that failed ends in a mark where it was stopped: a red cross, thrown back; a pale chevron, fell back (it points the way they went); a broken banner, beaten in a scramble. One beaten in a border clash stops halfway, where the columns met.\n•  A SWORD PLATE on a land of yours: the most one enemy could bring against it next round, shown when that could clearly outnumber you. Your capital rings crimson as soon as it could be outnumbered at all. Place recruits or keep men home, and it updates.\n•  ≤N on an enemy land that borders yours: the most it could hold once its commander places recruits. Hover any other enemy land to see its ceiling too.
•  AN AMBER RING (maps with supply): this land holds the road home for others. Lose it and they're cut off.\n•  THE PIPS beside a region's bonus: one per land, in its holder's colour. A pulsing ring marks the last land someone needs.\n•  THE LAND IN 3D (L, or the 3D chip): the map can stand on its own ground: hills, woods and rivers, a village in every land, every land's garrison beside its token, and in the battle report the columns marching their arrows. Everything above still reads the same; L puts the chart back.\n\nThe roster shows what each commander raises next round (+N)."],
	["Claiming the lands", "howto_draft",
	"A new game can deal the lands at random, or have the commanders claim them in turn (choose it on the setup screen, or in Settings).\n\nClaimed in turn: every commander's die drops onto the map, and the highest throw chooses first (ties throw again). Then everyone claims one free land at a time, round the table, until each holds as many as the deal would give. Build a region, crowd a rival, or grab the choke points. Then everyone deploys as usual."],
]


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.05, 0.97 if overlay else 1.0)
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(bg)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 48)
	add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	m.add_child(v)
	var head := HBoxContainer.new()
	head.add_child(Style.label("How to Play", 44, Style.CREAM, "display"))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	if not overlay:
		head.add_child(Style.button("Play the Tutorial", func():
			Settings.set_value("seen_tutorial", true) ## v1.14: as the title's button does (it kept offering it)
			main.start_tutorial(), 0))
	head.add_child(Style.button("Close" if overlay else "Back", func(): _close(), 140))
	v.add_child(head)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 30)
	v.add_child(row)
	_art = TextureRect.new()
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_art.size_flags_stretch_ratio = 1.1
	row.add_child(_art)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_theme_constant_override("separation", 14)
	row.add_child(tv)
	_title = Style.label("", 38, Style.GOLD, "display")
	tv.add_child(_title)
	_body = Style.label("", 23, Style.CREAM)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(460, 0)
	tv.add_child(_body)
	var nav := HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 20)
	v.add_child(nav)
	_prev = Style.button("◀  Previous", func(): _go(-1), 200)
	nav.add_child(_prev)
	_count = Style.label("", 20, Style.MUTED)
	nav.add_child(_count)
	_next = Style.button("Next  ▶", func(): _go(1), 200)
	nav.add_child(_next)
	page = clampi(start_page, 0, PAGES.size() - 1)
	_show()


func _go(d: int) -> void:
	if page + d >= PAGES.size():
		_close()
		return
	page = clampi(page + d, 0, PAGES.size() - 1)
	Audio.sfx("pass", -6.0)
	_show()


func _show() -> void:
	var p: Array = PAGES[page]
	_title.text = p[0]
	_art.texture = Style.tex("res://assets/art/%s.webp" % p[1])
	_body.text = p[2]
	_count.text = "%d / %d" % [page + 1, PAGES.size()]
	_prev.disabled = page == 0
	_next.text = "Done" if page == PAGES.size() - 1 else "Next  ▶"


func _close() -> void:
	if overlay:
		queue_free()
	else:
		main.show_title()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_RIGHT:
			_go(1)
		elif event.keycode == KEY_LEFT:
			_go(-1)
		elif event.keycode == KEY_ESCAPE:
			_close()
		else:
			return
		get_viewport().set_input_as_handled()
