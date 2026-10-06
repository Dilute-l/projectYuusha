class_name GameConfig
extends RefCounted

## 全局配置常量（ARCHITECTURE.md §8）。
##
## 纯常量容器：不实例化、不进 Autoload，任何脚本直接 `GameConfig.TOTAL_DAYS` 取用。

## 一局「讨伐季」的总天数：第 1..10 天，每天都必须完成一次招人
const TOTAL_DAYS: int = 10

## 存档格式版本，写进 RunState.version，用于读档时的兼容判断
const SAVE_VERSION: int = 1

## 存档目录与路径
const SAVE_DIR: String = "user://saves"
const SAVE_SLOT_FORMAT: String = "user://saves/slot_%d.json"
const AUTO_SAVE_PATH: String = "user://saves/auto.json"

## 手动存档槽位数量（自动存档另算，占 auto.json）
const MAX_SAVE_SLOTS: int = 3

## 静态数据根目录，由 DataDB 扫描
const DATA_ROOT: String = "res://data"

## 过场遮罩淡入淡出默认时长（秒）
const TRANSITION_FADE: float = 0.25


## 第 n 号存档槽的文件路径
static func slot_path(slot: int) -> String:
	return SAVE_SLOT_FORMAT % slot


## 合法的存档槽位：1..MAX_SAVE_SLOTS
static func is_valid_slot(slot: int) -> bool:
	return slot >= 1 and slot <= MAX_SAVE_SLOTS


## 合法的天数：1..TOTAL_DAYS
static func is_valid_day(day: int) -> bool:
	return day >= 1 and day <= TOTAL_DAYS
