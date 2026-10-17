@tool
extends McpTestSuite

## CandidateResource 上两个「不上纸面」的字段：fake_level（造假程度参考值）与
## display_race（简历上印的种族名）。
##
## ⚠️ 这里**只断言字段本身**：candidate_resource.gd 不是 @tool 脚本，在编辑器里
## 它加载出来是 placeholder 实例，**方法调不通**（`shown_race_name()` 会报
## "Attempt to call a method on a placeholder instance"）。那半个行为要靠跑起来的
## 游戏验：`DataDB.get_candidate(&"c_ct_0011").shown_race_name()`，
## 空 → 种族名、填了 → 覆盖、race 本身不变。

const CAND := "res://data/candidates/"


func suite_name() -> String:
	return "candidate_fields"


func test_fake_level_read_from_tres() -> void:
	var c: CandidateResource = load(CAND + "c_ct_0003.tres")
	assert_true(c != null, "c_ct_0003 能加载")
	assert_eq(c.fake_level, 3, "c_ct_0003 的 fake_level 应为 3（文件夹标 fake3）")
	assert_eq(c.display_race, "", "没填 display_race 时是空串")


func test_fake_level_defaults_to_zero() -> void:
	var c: CandidateResource = load(CAND + "c_ct_0011.tres")
	assert_true(c != null, "c_ct_0011 能加载")
	assert_eq(c.fake_level, 0, "没写 fake_level 的老文件 → 0")


func test_fake_level_is_not_a_trait() -> void:
	# 同一份数据里特质那边还是 fake2 —— 两个字段互不替代
	var c: CandidateResource = load(CAND + "c_ct_0003.tres")
	var trait_ids: Array[String] = []
	for t in c.traits:
		trait_ids.append(String(t.id))
	assert_true(trait_ids.has("trait.fake2"), "特质里仍然是 trait.fake2（和 fake_level=3 不同源）")


func test_display_race_is_a_plain_string_field() -> void:
	var c: CandidateResource = load(CAND + "c_ct_0011.tres")
	c.display_race = "仙灵"
	assert_eq(c.display_race, "仙灵", "display_race 是可读可写的普通字符串")
	assert_true(c.race != null, "写 display_race 不影响 race 字段存在")
	assert_eq(String(c.race.id), "race.el", "race 还是精灵（玩法判定读的是它）")
