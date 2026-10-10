extends Control

const TITLE_SFX_PATH: String = "res://assets/sound/suspicious.wav"

## 大脸（bighead）淡入 / 停留 / 淡出的时长（秒）
const BIGHEAD_FADE_IN: float = 0.25
const BIGHEAD_HOLD: float = 1.4
const BIGHEAD_FADE_OUT: float = 0.35

## 正在播的那条 bighead 淡入淡出 Tween（重新点向日葵时先把上一条掐掉）
var _bighead_tween: Tween = null

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_button_pressed() -> void:
	SceneRouter.goto_scene(&"main_menu")


func _on_sunflower_pressed() -> void:
	AudioService.play_sfx(TITLE_SFX_PATH)
	# 点向日葵 → 大脸（bighead）淡入，停 1 秒，再淡出。
	# 它初始在场景里是 visible = false（见 credits_room.tscn）。
	var bighead := get_node_or_null("bighead") as Sprite2D
	if bighead == null:
		push_error("[CreditsRoom] 找不到 bighead 节点")
		return
	_flash_bighead(bighead)


## 让 bighead 淡入 → 停留 BIGHEAD_HOLD 秒 → 淡出并重新隐藏。
##
## 淡入淡出走 CanvasItem.modulate 的 alpha：它作用于**整个节点**（含子节点），
## 不像 self_modulate 只作用于自己。节点本身始终 visible = true，
## 所以这段演出期间点其它按钮不受影响，也免了「可见性开关与动画互相打架」。
##
## 反复点向日葵：先把上一条 Tween 掐掉从头再来，否则两条 Tween 会同时改 alpha。
func _flash_bighead(bighead: Sprite2D) -> void:
	if _bighead_tween != null and _bighead_tween.is_valid():
		_bighead_tween.kill()

	bighead.visible = true
	bighead.modulate.a = 0.0

	_bighead_tween = create_tween()
	_bighead_tween.tween_property(bighead, "modulate:a", 1.0, BIGHEAD_FADE_IN)
	_bighead_tween.tween_interval(BIGHEAD_HOLD)
	_bighead_tween.tween_property(bighead, "modulate:a", 0.0, BIGHEAD_FADE_OUT)
	# 淡出结束后才真正隐藏；alpha 已是 0，这一下不会闪
	_bighead_tween.tween_callback(func() -> void: bighead.visible = false)


func _on_liuxu_pressed() -> void:
	AudioService.play_sfx(TITLE_SFX_PATH)
	var win := get_window()
	if win != null:
		win.gui_release_focus()
	var dialoguer = get_node_or_null("Dialoguer")
	if dialoguer == null:
		push_error("[MainMenu] 找不到 Dialoguer")
		return
	if not dialoguer.typer.load_dialogue("Liuxu"):
		return
	dialoguer.play()
