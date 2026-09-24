## Headless knife-fight. dump / replay / play vs monkey.
## Seed stays off World. No engine UI imports the other way.
extends SceneTree

const Types := preload("res://engine/types.gd")
const Bot := preload("res://engine/bot.gd")
const Setup := preload("res://engine/setup.gd")
const MapLib := preload("res://engine/map.gd")
const Income := preload("res://engine/income.gd")
const Validate := preload("res://engine/validate.gd")
const Resolve := preload("res://engine/resolve.gd")
const Match := preload("res://engine/match.gd")
const Ascii := preload("res://tools/ascii.gd")
const Rng := preload("res://engine/rng.gd")
const YOU := "red"
const MONKEY := "blue"


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var cmd := "help"
	if args.size() > 0 and not str(args[0]).begins_with("--"):
		cmd = str(args[0])
		args.remove_at(0)
	var flags: Dictionary = _parse_flags(args)
	match cmd:
		"dump":
			_cmd_dump(flags)
		"replay":
			_cmd_replay(flags)
		"play":
			_cmd_play(flags)
		_:
			_help()
			quit(0 if cmd == "help" else 1)


func _parse_flags(args: PackedStringArray) -> Dictionary:
	var flags := {"seed": 42, "out": "match.json", "path": "", "three": false}
	var i := 0
	while i < args.size():
		var a: String = str(args[i])
		if a == "--seed" and i + 1 < args.size():
			flags["seed"] = int(args[i + 1])
			i += 2
		elif a == "--out" and i + 1 < args.size():
			flags["out"] = str(args[i + 1])
			i += 2
		elif a == "--path" and i + 1 < args.size():
			flags["path"] = str(args[i + 1])
			i += 2
		elif a == "--3p" or a == "--three":
			flags["three"] = true
			i += 1
		elif not a.begins_with("--") and flags["path"] == "":
			flags["path"] = a
			i += 1
		else:
			i += 1
	return flags


func _help() -> void:
	print("CONCURRENT knife-fight CLI")
	print("  ./scripts/cli.sh dump [--seed N] [--out match.json] [--3p]")
	print("  ./scripts/cli.sh replay match.json")
	print("  ./scripts/cli.sh play [--seed N]     # you are red, monkey is blue")
	print("Replay hashes the world after each resolve. Seed is not stored on World.")


func _cmd_dump(flags: Dictionary) -> void:
	var map: Types.MapDef = Types.MapDef.from_file("res://maps/knife7.json")
	var seed: int = int(flags["seed"])
	var rec: Dictionary = Match.record_monkey(map, seed, bool(flags["three"]))
	if not rec.get("ok", false):
		print("dump aborted: %s" % " ".join(rec.get("violations", PackedStringArray())))
		quit(1)
		return
	var out: String = str(flags["out"])
	var err: String = Match.save(out, rec)
	if err != "":
		print(err)
		quit(1)
		return
	print("wrote %s  rounds=%s  finalHash=%s" % [out, rec.get("rounds"), rec.get("finalHash")])
	var replayed: Dictionary = Match.replay(map, rec)
	if Match.hashes_match(rec, replayed):
		print("replay ok  same hashes")
		quit(0)
	else:
		print("replay FAIL  recorded %s  got %s  %s" % [rec.get("finalHash"), replayed.get("final_hash"), replayed.get("error")])
		quit(1)


func _cmd_replay(flags: Dictionary) -> void:
	var path: String = str(flags["path"])
	if path == "":
		path = str(flags["out"])
	var rec: Dictionary = Match.load(path)
	if rec.is_empty():
		print("cannot read %s" % path)
		quit(1)
		return
	var map: Types.MapDef = Types.MapDef.from_file("res://maps/knife7.json")
	var replayed: Dictionary = Match.replay(map, rec)
	if not replayed.get("ok", false):
		print("replay FAIL  %s" % replayed.get("error"))
		quit(1)
		return
	if Match.hashes_match(rec, replayed):
		print("replay ok  %s  rounds=%s  finalHash=%s" % [path, replayed["hashes"].size(), replayed["final_hash"]])
		quit(0)
	else:
		print("replay FAIL  recorded %s  got %s" % [rec.get("finalHash"), replayed.get("final_hash")])
		quit(1)


func _cmd_play(flags: Dictionary) -> void:
	var map: Types.MapDef = Types.MapDef.from_file("res://maps/knife7.json")
	var seed: int = int(flags["seed"])
	var world: Types.World = Setup.deal_knife7_two_player(map, seed, true)
	print("CONCURRENT  you are red  monkey is blue  Neutral sits on The Gate")
	print("seed %s  (not on the map)" % seed)
	print("")
	_opening(world, map, seed)
	print(Ascii.render(world, map, YOU))
	var setup: Dictionary = world.to_dict()
	var recorded_sheets: Array = []
	var hashes: Array = []
	while true:
		if not _alive(world, YOU):
			print("you have no territories.")
			break
		var human: Types.Sheet = _prompt_sheet(world, map)
		var bot_rng: RefCounted = Rng.derive_stream(seed, world.round, "bot|" + MONKEY)
		var monkey: Types.Sheet = Bot.legal_sheet(world, map, MONKEY, bot_rng)
		var sheets: Array = [human, monkey]
		var round_dicts: Array = [human.to_dict(), monkey.to_dict()]
		recorded_sheets.append(round_dicts)
		var result: Dictionary = Resolve.resolve_round(world, map, sheets, seed)
		if not result["errors"].is_empty():
			print("resolve refused: %s" % " ".join(result["errors"]))
			recorded_sheets.pop_back()
			continue
		world = result["world"]
		hashes.append(load("res://engine/hash.gd").world_hash(world))
		print("")
		print(Ascii.render_events(result["events"]))
		print("")
		print(Ascii.render(world, map, YOU))
		var winner: String = _winner(result["events"])
		if winner != "":
			print("")
			print("winner: %s" % winner)
			break
	var rec := {
		"mapId": map.id,
		"matchSeed": seed,
		"setup": setup,
		"sheets": recorded_sheets,
		"hashes": hashes,
		"finalHash": hashes[hashes.size() - 1] if hashes.size() > 0 else "",
	}
	var out: String = str(flags["out"])
	var err: String = Match.save(out, rec)
	if err == "":
		print("wrote %s  finalHash=%s" % [out, rec["finalHash"]])
	quit(0)


func _opening(world: Types.World, map: Types.MapDef, seed: int) -> void:
	print(Ascii.render(world, map, YOU))
	var pool: int = Setup.remaining_pool(world, YOU, 2, map)
	print("Opening placement. Pool %s. Cap is 1 + friendly neighbors. Overflow vanishes." % pool)
	print("  place <hex> <n>   lock")
	var human := {}
	while true:
		var line: String = _read("open> ").strip_edges()
		if line == "":
			continue
		var parts: PackedStringArray = line.split(" ", false)
		var cmd: String = str(parts[0]).to_lower()
		if cmd == "help" or cmd == "?":
			print("place <hex> <n>   lock   map")
		elif cmd == "map":
			print(Ascii.render(world, map, YOU))
		elif (cmd == "place" or cmd == "p") and parts.size() >= 3:
			human[str(parts[1])] = int(parts[2])
			print("  queued %s" % human)
		elif cmd == "lock" or cmd == "l":
			break
		elif cmd == "quit" or cmd == "q":
			quit(0)
			return
		else:
			print("unknown. try place / lock")
	var rng: RefCounted = Rng.derive_stream(seed, 0, "open|" + MONKEY)
	var bot_open: Dictionary = Bot.opening_placements(world, map, MONKEY, rng)
	Setup.apply_opening(world, map, {YOU: human, MONKEY: bot_open})
	print("opening locked.")


func _prompt_sheet(world: Types.World, map: Types.MapDef) -> Types.Sheet:
	var sheet := Types.Sheet.new()
	sheet.player_id = YOU
	print("")
	print("plan round %s.  place / attack / regroup / sheet / hold / lock" % world.round)
	print("  attack <from> <to> <n> [surge]")
	while true:
		var line: String = _read("plan> ").strip_edges()
		if line == "":
			continue
		var parts: PackedStringArray = line.split(" ", false)
		var cmd: String = str(parts[0]).to_lower()
		if cmd == "help" or cmd == "?":
			print("place <hex> <n>")
			print("attack <from> <to> <n> [surgeHex]")
			print("regroup <from> <to> <n>")
			print("sheet  hold  lock  map  clear  quit")
		elif cmd == "map":
			print(Ascii.render(world, map, YOU))
		elif cmd == "sheet" or cmd == "s":
			print(Ascii.render_sheet(sheet))
		elif cmd == "clear":
			sheet = Types.Sheet.new()
			sheet.player_id = YOU
			print("cleared")
		elif (cmd == "place" or cmd == "p") and parts.size() >= 3:
			sheet.placements[str(parts[1])] = int(parts[2])
			print(Ascii.render_sheet(sheet))
		elif (cmd == "attack" or cmd == "a") and parts.size() >= 4:
			var p := Types.Packet.new()
			p.from_id = str(parts[1])
			p.to_id = str(parts[2])
			p.strength = int(parts[3])
			if parts.size() >= 5:
				p.surge_to = str(parts[4])
			sheet.packets.append(p)
			print(Ascii.render_sheet(sheet))
		elif (cmd == "regroup" or cmd == "g" or cmd == "r") and parts.size() >= 4:
			var rg := Types.Regroup.new()
			rg.from_id = str(parts[1])
			rg.to_id = str(parts[2])
			rg.strength = int(parts[3])
			sheet.regroup = rg
			print(Ascii.render_sheet(sheet))
		elif cmd == "hold" or cmd == "h":
			sheet = Types.Sheet.new()
			sheet.player_id = YOU
			print("hold sheet. lock to confirm.")
		elif cmd == "lock" or cmd == "l":
			var errs: PackedStringArray = Validate.validate_sheet(world, map, sheet)
			if errs.size() > 0:
				print("illegal: %s" % " ".join(errs))
				continue
			return sheet
		elif cmd == "quit" or cmd == "q":
			quit(0)
			return sheet
		else:
			print("unknown. help for commands")
	return sheet


func _alive(world: Types.World, pid: String) -> bool:
	var ps: Types.PlayerState = world.players.get(pid, null)
	return ps != null and ps.alive and MapLib.player_territory_ids(world, pid).size() > 0


func _winner(events: Array) -> String:
	for i in range(events.size() - 1, -1, -1):
		var e: Dictionary = events[i]
		if str(e.get("kind", "")) == Types.EVENT_ROUND_ENDED:
			return str(e.get("winner", ""))
	return ""


func _read(prompt: String) -> String:
	print(prompt)
	return OS.read_string_from_stdin()
