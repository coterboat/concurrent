## v1.8 the rules of the war, and the presets. Every rule a table can change lives here once:
## its name, its choices, what it means; the setup screen draws itself from this, and the
## session reads the chosen values out of the game's config (so saves remember them).
##
## STANDARD is the war we balance around: the most fun version, measured (docs/CHANGELOG.md
## v1.8 has the arena tables). The others are for tables that want something else.
extends RefCounted

## id: config key · name · [[value, label], ...] · help
const RULES := [
	{"id": "deal", "name": "Lands", "choices": [["draft", "Claimed in turn"], ["random", "Dealt at random"]],
		"help": "Claimed in turn: every commander's die drops for the order, then everyone claims one land at a time (your first claim is your capital). Dealt at random is quicker."},
	{"id": "capitals", "name": "Capitals", "choices": [[true, "Every commander keeps a capital"], [false, "No capitals"]],
		"help": "A capital pays 2 recruits a round and fights like a fortress. Take a rival's and plunder half their cards and raise 3 troops there."},
	{"id": "fortune", "name": "Fortune", "choices": [[true, "Bad luck banks a throw-again ✦"], [false, "The dice are the dice"]],
		"help": "Fortune keeps a ledger of your luck. When the dice have robbed you of about half a battle (any fight counts), she owes you a favour: throw a disastrous exchange again, in an assault or a melee (and a good exchange taken from you that way counts toward your next). Start with one, hold up to three."},
	{"id": "levee", "name": "Levée en masse", "choices": [[3, "The commander behind rallies"], [0, "Off"]],
		"help": "A recruit for every three lands you trail the leader by (up to 4 a round). A gentle hand for whoever is losing, so wars stay close."},
	{"id": "firing_line", "name": "Battle odds", "choices": [[true, "Firing line (five fire at once)"], [false, "Every man counts (v1.5)"]],
		"help": "Firing line: at most five men of a side fire in a volley, so a big army wins by staying power. Every man counts: a big army wins nearly every volley."},
	{"id": "battle", "name": "Battles", "choices": [["volleys", "Roll by roll (volleys)"], ["decisive", "One decisive roll"]],
		"help": "Roll by roll you throw the dice yourself, make battle calls and can call on Fortune. One decisive roll settles each battle at once."},
	{"id": "surges", "name": "Surges", "choices": [[true, "Breakthroughs push on"], [false, "No surges"]],
		"help": "Order an attack to push on into the next land if it takes the first."},
	{"id": "terrain", "name": "Map features", "choices": [[true, "Fortresses, passes, ports, supply"], [false, "Plain lands"]],
		"help": "On the maps that have them: fortresses fire a longer line, passes take six at most from one land, ports join by sea, and lands cut off from home feed nobody."},
	{"id": "maneuvers", "name": "Regroup phase", "choices": [[true, "March after the battles"], [false, "No regroup phase"]],
		"help": "After the battles, everyone marches troops one land toward the front."},
	{"id": "cards", "name": "Cards", "choices": [[true, "Capture cards, turn in sets"], [false, "No cards"]],
		"help": "Capture a land in a round to draw a card; three alike or one of each turn in for fresh troops (on the maps that use cards)."},
]

const PRESETS := {
	"standard": {"deal": "draft", "capitals": true, "fortune": true, "levee": 3, "firing_line": true, "battle": "volleys",
		"surges": true, "terrain": true, "maneuvers": true, "cards": true},
	"recruit": {"deal": "random", "capitals": false, "fortune": true, "levee": 3, "firing_line": true, "battle": "volleys",
		"surges": false, "terrain": false, "maneuvers": true, "cards": true},
	"classic": {"deal": "random", "capitals": false, "fortune": false, "levee": 0, "firing_line": false, "battle": "volleys",
		"surges": true, "terrain": false, "maneuvers": true, "cards": true},
}
const PRESET_ORDER := ["standard", "recruit", "classic"]
const PRESET_NAMES := {
	"standard": "Standard — the full war",
	"recruit": "Recruit — a first war, fewer rules",
	"classic": "Classic — Risk II, every man counts",
	"custom": "Custom",
}


static func rule(id: String) -> Dictionary:
	for r in RULES:
		if str(r["id"]) == id:
			return r
	return {}


static func values_of(preset: String) -> Dictionary:
	return (PRESETS.get(preset, PRESETS["standard"]) as Dictionary).duplicate()


static func preset_of(values: Dictionary) -> String:
	## which preset these values are, or "custom"
	for p in PRESET_ORDER:
		var pv: Dictionary = PRESETS[p]
		var same := true
		for k in pv.keys():
			if values.get(k) != pv[k]:
				same = false
				break
		if same:
			return p
	return "custom"


static func label(id: String, value) -> String:
	for c in rule(id).get("choices", []):
		if c[0] == value:
			return str(c[1])
	return str(value)


static func summary(values: Dictionary) -> String:
	## a line for the setup screen: what is on, in a few words
	var bits: Array = []
	bits.append("lands claimed in turn" if values.get("deal") == "draft" else "lands dealt")
	if values.get("capitals", false):
		bits.append("capitals")
	if values.get("fortune", false):
		bits.append("Fortune")
	if int(values.get("levee", 0)) > 0:
		bits.append("levée")
	bits.append("firing line" if values.get("firing_line", true) else "every man counts")
	if values.get("battle", "volleys") == "decisive":
		bits.append("one-roll battles")
	if not values.get("surges", true):
		bits.append("no surges")
	if not values.get("terrain", true):
		bits.append("plain lands")
	if not values.get("maneuvers", true):
		bits.append("no regroup")
	if not values.get("cards", true):
		bits.append("no cards")
	return " · ".join(bits)
