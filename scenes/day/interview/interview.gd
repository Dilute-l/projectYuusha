extends Control

## ===========================================================================
## ⚠️ 临时调试代码 —— 只为肉眼检查立绘部件组合，不参与任何玩法逻辑。
##
## 接入正式候选人生成器（scripts/core/generation/candidate_generator.gd）后，
## 把 _ready() 里那一行调用和 _debug_randomize_interviewee() 整段删掉即可。
## ===========================================================================

const INTERVIEWEE_SCENE := preload("res://scenes/day/interview/interviewee.tscn")

## 可用种族，对应 assets/art/portrait/ 里的文件名前缀
const RACES: Array[StringName] = [&"hu", &"el", &"st"]

## 部位编号范围，对应 *_phd1..3 三个文件
const PART_MIN := 1
const PART_MAX := 3


func _ready() -> void:
	_debug_randomize_interviewee()


func _debug_randomize_interviewee() -> void:
	# 场景里已经有 Interviewee 就直接用；没有（当前场景确实没有）就拉一个出来
	var iv := get_node_or_null("Interviewee") as Interviewee
	var spawned := false
	if iv == null:
		iv = INTERVIEWEE_SCENE.instantiate() as Interviewee
		iv.name = "Interviewee"
		spawned = true

	# 随机走 RngService（项目的唯一随机源，纪律见 autoload/rng_service.gd）。
	# 流名带 ticks 是为了「每次进场景都换一套」——纯调试目的。
	# 这里并没有新增随机源，只是向 RngService 要了一条新流。
	# 想改成「同种子复现同一套」就把流名换成固定的 &"debug:portrait"。
	var s := StringName("debug:portrait:%d" % Time.get_ticks_msec())

	iv.race = StringName(RngService.pick(s, RACES))
	iv.eye = RngService.randi_in(s, PART_MIN, PART_MAX)
	iv.hair = RngService.randi_in(s, PART_MIN, PART_MAX)
	iv.mouth = RngService.randi_in(s, PART_MIN, PART_MAX)
	iv.hat = RngService.randi_in(s, PART_MIN, PART_MAX)

	if spawned:
		# 先填数据再入树：_ready() 里那次 apply() 就已经是正确的一套，不会白跑
		add_child(iv)
	else:
		# 场景里已有的实例，_ready() 早就跑过了，得手动重刷
		iv.apply()

	print("[Interview][debug] 随机面试者 race=%s eye=%d hair=%d mouth=%d hat=%d" % [
		iv.race, iv.eye, iv.hair, iv.mouth, iv.hat])


func _on_notice_board_pressed() -> void:
	var dialoguer = get_node_or_null("Dialoguer")
	if dialoguer == null:
		push_error("[MainMenu] 找不到 Dialoguer")
		return
	if not dialoguer.typer.load_dialogue("Boardery"):
		return
	dialoguer.play()
