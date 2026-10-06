extends Node

## AudioService —— BGM 与音效播放、淡入淡出（ARCHITECTURE.md §2）。
##
## M0 阶段 assets/audio/ 还是空的，所以**一切播放入口都必须能容忍「资源不存在」**：
## 找不到文件时只警告、返回 false，绝不让调用方崩掉。
##
## BGM / SFX 总线在运行时确保存在（项目未提供 default_bus_layout.res 时自动补上），
## 音量以线性值 0..1 对外，内部换算成分贝。

const BUS_BGM: StringName = &"BGM"
const BUS_SFX: StringName = &"SFX"

## 默认淡入淡出时长（秒）
const DEFAULT_FADE: float = 0.8

## 音效播放器池大小（同时播放的音效数量上限）
const SFX_POOL_SIZE: int = 8

var _bgm_player: AudioStreamPlayer = null
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_cursor: int = 0
var _bgm_fade: Tween = null

## 当前 BGM 的资源路径（"" 表示没有在放）
var _bgm_path: String = ""

## 各总线线性音量缓存
var _volumes: Dictionary = {
	BUS_BGM: 1.0,
	BUS_SFX: 1.0,
}


func _ready() -> void:
	_ensure_buses()
	_create_players()

# ---------------------------------------------------------------------------
# BGM
# ---------------------------------------------------------------------------


## 播放 BGM。同一首正在播时不重启；换了曲子则交叉淡入
func play_bgm(stream_or_path: Variant, fade: float = DEFAULT_FADE) -> bool:
	var stream := _resolve_stream(stream_or_path)
	if stream == null:
		return false

	var path := _path_of(stream_or_path)
	if path != "" and path == _bgm_path and _bgm_player.playing:
		return true

	_bgm_player.stream = stream
	_bgm_path = path
	_bgm_player.volume_db = _linear_to_db(0.0) if fade > 0.0 else _linear_to_db(_volumes[BUS_BGM])
	_bgm_player.play()
	if fade > 0.0:
		_kill_fade()
		_bgm_fade = create_tween()
		_bgm_fade.tween_property(_bgm_player, "volume_db", _linear_to_db(_volumes[BUS_BGM]), fade)
	return true


## 停止 BGM；fade > 0 时淡出后再停
func stop_bgm(fade: float = DEFAULT_FADE) -> void:
	if _bgm_player == null or not _bgm_player.playing:
		return
	_kill_fade()
	if fade <= 0.0:
		_bgm_player.stop()
		_bgm_path = ""
		return
	_bgm_fade = create_tween()
	_bgm_fade.tween_property(_bgm_player, "volume_db", _linear_to_db(0.0), fade)
	_bgm_fade.tween_callback(_bgm_player.stop)
	_bgm_path = ""


func is_bgm_playing() -> bool:
	return _bgm_player != null and _bgm_player.playing


## 当前 BGM 的资源路径，未播放时为空串
func get_current_bgm() -> String:
	return _bgm_path

# ---------------------------------------------------------------------------
# 音效
# ---------------------------------------------------------------------------


## 播放一次性音效。volume_db 为相对基准的微调
func play_sfx(stream_or_path: Variant, volume_db: float = 0.0, pitch_scale: float = 1.0) -> bool:
	var stream := _resolve_stream(stream_or_path)
	if stream == null:
		return false
	var player := _next_sfx_player()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.play()
	return true


## 池耗尽时的策略：按游标抢占一路（高频音效不会互相全掐掉）
func _next_sfx_player() -> AudioStreamPlayer:
	for player in _sfx_players:
		if not player.playing:
			return player
	var player := _sfx_players[_sfx_cursor]
	_sfx_cursor = (_sfx_cursor + 1) % _sfx_players.size()
	return player

# ---------------------------------------------------------------------------
# 音量（对外线性 0..1）
# ---------------------------------------------------------------------------


func set_bgm_volume(linear: float) -> void:
	_set_bus_volume(BUS_BGM, linear)
	if _bgm_player != null and _bgm_player.playing:
		_kill_fade()
		_bgm_player.volume_db = _linear_to_db(_volumes[BUS_BGM])


func set_sfx_volume(linear: float) -> void:
	_set_bus_volume(BUS_SFX, linear)


func set_master_volume(linear: float) -> void:
	_set_bus_volume(&"Master", linear)


func get_volume(bus_name: StringName) -> float:
	return float(_volumes.get(bus_name, 1.0))


## 一次性设置三档音量（设置界面「应用」按钮用）
func set_volumes(master: float, bgm: float, sfx: float) -> void:
	set_master_volume(master)
	set_bgm_volume(bgm)
	set_sfx_volume(sfx)

# ---------------------------------------------------------------------------
# 内部实现
# ---------------------------------------------------------------------------


func _ensure_buses() -> void:
	for bus_name in [BUS_BGM, BUS_SFX]:
		if AudioServer.get_bus_index(bus_name) != -1:
			continue
		var index := AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, &"Master")


func _create_players() -> void:
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.name = "BgmPlayer"
	_bgm_player.bus = BUS_BGM
	add_child(_bgm_player)

	for i in SFX_POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.name = "SfxPlayer%d" % i
		player.bus = BUS_SFX
		add_child(player)
		_sfx_players.append(player)


## 接受 AudioStream 实例或 res:// 路径；资源缺失时警告并返回 null
func _resolve_stream(stream_or_path: Variant) -> AudioStream:
	if stream_or_path is AudioStream:
		return stream_or_path
	var path := str(stream_or_path)
	if path.is_empty():
		return null
	if not ResourceLoader.exists(path):
		push_warning("[AudioService] 音频资源不存在：%s" % path)
		return null
	var stream := ResourceLoader.load(path)
	if stream is AudioStream:
		return stream
	push_warning("[AudioService] 不是音频资源：%s" % path)
	return null


func _path_of(stream_or_path: Variant) -> String:
	return str(stream_or_path) if stream_or_path is String or stream_or_path is StringName else ""


func _set_bus_volume(bus_name: StringName, linear: float) -> void:
	var clamped := clampf(linear, 0.0, 1.0)
	_volumes[bus_name] = clamped
	var index := AudioServer.get_bus_index(bus_name)
	if index == -1:
		return
	AudioServer.set_bus_volume_db(index, _linear_to_db(clamped))
	AudioServer.set_bus_mute(index, clamped <= 0.001)
	EventBus.volume_changed.emit(bus_name, clamped)


func _linear_to_db(linear: float) -> float:
	if linear <= 0.001:
		return -80.0
	return linear_to_db(linear)


func _kill_fade() -> void:
	if _bgm_fade != null and _bgm_fade.is_valid():
		_bgm_fade.kill()
	_bgm_fade = null
