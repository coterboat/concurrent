## Deterministic hashing. No Godot.hash() — that is not a match-replay contract.
## No Node. No UI. No unseeded RNG.
class_name EngineHash
extends RefCounted

const FNV_OFFSET_32 := 2166136261
const FNV_PRIME_32 := 16777619


static func fnv1a_32(text: String) -> int:
	var h := FNV_OFFSET_32
	for i in text.length():
		h ^= text.unicode_at(i)
		h = (h * FNV_PRIME_32) & 0xFFFFFFFF
	return h


static func fnv1a_32_hex(text: String) -> String:
	return "%08x" % fnv1a_32(text)


static func canonical(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if value else "false"
		TYPE_INT:
			return str(value)
		TYPE_FLOAT:
			# JSON numbers from files may arrive as floats. Canonicalize as ints when whole.
			var f := float(value)
			if f == floor(f) and f >= float(-9223372036854775808) and f <= float(9223372036854775807):
				return str(int(f))
			return str(f)
		TYPE_STRING:
			return JSON.stringify(value)
		TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY:
			var parts: PackedStringArray = PackedStringArray()
			for item in value:
				parts.append(canonical(item))
			return "[" + ",".join(parts) + "]"
		TYPE_DICTIONARY:
			var keys: Array = value.keys()
			keys.sort()
			var parts: PackedStringArray = PackedStringArray()
			for k in keys:
				parts.append(JSON.stringify(str(k)) + ":" + canonical(value[k]))
			return "{" + ",".join(parts) + "}"
		_:
			return JSON.stringify(str(value))


static func of_dict(data: Dictionary) -> String:
	return fnv1a_32_hex(canonical(data))


static func world_hash(world: RefCounted) -> String:
	return of_dict(world.to_dict())


static func mix_battle(match_seed: int, round: int, battle_key: String) -> int:
	## 32-bit seed for RandomNumberGenerator. Material is explicit so an
	## unrelated packet on the other side of the map cannot change this fight.
	var material := "%s|%s|%s" % [match_seed, round, battle_key]
	return fnv1a_32(material)
