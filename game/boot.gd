extends Control

func _ready() -> void:
	print("CONCURRENT G4 — CLI knife-fight. ./scripts/cli.sh play   Esc quits.")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
