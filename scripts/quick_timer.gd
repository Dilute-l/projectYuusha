class_name QuickTimer
extends Node

signal timeout

@export var process_callback: = Timer.TIMER_PROCESS_IDLE
@export_range(0.001, 4096.0, 0.001, "suffix:s") var wait_time: = 1.0
@export var one_shot: bool
@export var autostart: bool
@export var ignore_time_scale: bool

var paused: bool
var time_left: float
var running: bool


func _ready() -> void :
	if autostart:
		start()


func _process(delta: float) -> void :
	if process_callback == Timer.TIMER_PROCESS_IDLE and not is_stopped():
		if ignore_time_scale:
			delta /= Engine.time_scale
		advance(delta)


func _physics_process(delta: float) -> void :
	if process_callback == Timer.TIMER_PROCESS_PHYSICS and not is_stopped():
		if ignore_time_scale:
			delta /= Engine.time_scale
		advance(delta)


func is_stopped() -> bool:
	return paused or not running


func start(time_sec: = -1.0, retain_overflow: = false) -> void :
	if time_sec > 0.0:
		wait_time = time_sec
	time_left = wait_time + time_left if retain_overflow else wait_time
	running = true


func stop() -> void :
	running = false


func advance(delta: float) -> void :
	time_left -= delta
	if time_left <= 0.0:
		if one_shot:
			stop()
			timeout.emit()
		else:
			while time_left <= 0.0 and wait_time > 0.0:
				time_left += wait_time
				timeout.emit()
