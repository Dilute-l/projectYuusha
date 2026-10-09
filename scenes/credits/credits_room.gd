extends Control

const TITLE_SFX_PATH: String = "res://assets/sound/squeak.mp3"
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
	var win := get_window()
	if win != null:
		win.gui_release_focus()
	var dialoguer = get_node_or_null("Dialoguer")
	if dialoguer == null:
		push_error("[MainMenu] 找不到 Dialoguer")
		return
	if not dialoguer.typer.load_dialogue("Sunflower"):
		return
	dialoguer.play()
