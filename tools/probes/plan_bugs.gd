## Screenshot cases: duplicate attack, Beacon→Ridge send 2, round-1 lock.
## Run via: ./scripts/probe.sh plan_bugs
extends RefCounted

const SessionTest := preload("res://tests/test_session.gd")


func run(p) -> void:
	var t: RefCounted = SessionTest.new()
	t._plan_bugs(Callable(p, "ok"), p.get_tree())
	await p.frames(1)
