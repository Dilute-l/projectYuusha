extends Control

var _phase: int = DayPhase.Phase.DAY_BRIEFING

signal phase_finished()

func set_phase(new_phase: int) -> void:
	_phase = new_phase

func _ready() -> void:
	EventBus.day_phase_entered.connect(set_phase)
