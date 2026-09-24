## Couch colors + colorblind patterns. Not a second rules engine.
extends RefCounted

const BG := Color(0.043, 0.071, 0.125)
const CREAM := Color(0.91, 0.878, 0.816)
const MUTED := Color(0.71, 0.69, 0.64)
const RED := Color(0.76, 0.23, 0.18)
const BLUE := Color(0.18, 0.38, 0.68)
const NEUTRAL := Color(0.45, 0.42, 0.39)
const UNOCC := Color(0.07, 0.09, 0.12)
const PANEL := Color(0.06, 0.08, 0.12, 0.94)
const LOCK_RED := Color(0.72, 0.16, 0.12)


static func owner_fill(owner: String) -> Color:
	match owner:
		"red":
			return RED
		"blue":
			return BLUE
		"green":
			return Color(0.18, 0.55, 0.34)
		"neutral":
			return NEUTRAL
		_:
			return UNOCC


static func region_fill(region: String) -> Color:
	match region:
		"westreach":
			return Color(0.28, 0.40, 0.24)
		"crownlands":
			return Color(0.48, 0.38, 0.18)
		"midsea":
			return Color(0.12, 0.32, 0.42)
		"spine":
			return Color(0.36, 0.34, 0.32)
		"eastshore":
			return Color(0.42, 0.22, 0.24)
		"southrim":
			return Color(0.50, 0.40, 0.22)
		"northshore":
			return Color(0.22, 0.34, 0.40)
		"southshore":
			return Color(0.40, 0.28, 0.18)
		_:
			return Color(0.12, 0.14, 0.16)


static func pattern(owner: String) -> String:
	match owner:
		"red":
			return "hatch"
		"blue":
			return "dots"
		"green":
			return "cross"
		"neutral":
			return "stripes"
		_:
			return "none"
