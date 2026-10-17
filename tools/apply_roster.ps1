# 把 roster_editor 导出的 roster_plan.json 写成 data/days/day_XX.tres
# ASCII-only source on purpose (PS 5.1 reads BOM-less .ps1 as ANSI).
#
#   pwsh -File tools/apply_roster.ps1 -From "$HOME\Downloads\roster_plan.json"            # 只预览，不写盘
#   pwsh -File tools/apply_roster.ps1 -From "$HOME\Downloads\roster_plan.json" -Apply     # 真的写进去
#   ... -Apply -Backup                                                                   # 写之前把旧的存成 .bak
#
# 只动 -Days 里那几天（默认 1..10）。

param(
	[Parameter(Mandatory = $true)][string]$From,
	[switch]$Apply,
	[switch]$Backup,
	[int[]]$Days = @(1, 2, 3, 4, 5, 6, 7, 8, 9, 10)
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$utf8 = New-Object System.Text.UTF8Encoding($false)
$candDir = Join-Path $root 'data\candidates'
$dayDir = Join-Path $root 'data\days'

if (-not (Test-Path -LiteralPath $From)) { throw "roster_plan.json not found: $From" }
$plan = Get-Content -Raw -LiteralPath $From -Encoding UTF8 | ConvertFrom-Json

function DayIdsOf([int]$d) {
	$node = $plan.days
	if (-not $node) { return @() }
	$prop = $node.PSObject.Properties | Where-Object { $_.Name -eq "$d" } | Select-Object -First 1
	if (-not $prop) { return @() }
	$out = @()
	foreach ($v in @($prop.Value)) { if ("$v" -ne '') { $out += "$v" } }
	return $out
}
function SlotOf([int]$d, [int]$count) {
	$node = $plan.slots
	if ($node) {
		$prop = $node.PSObject.Properties | Where-Object { $_.Name -eq "$d" } | Select-Object -First 1
		if ($prop -and "$($prop.Value)" -match '^\d+$') { return [int]$prop.Value }
	}
	return [Math]::Max(1, $count - 1)
}

## json 里带 uids 就用它（工具导出的 json 会带），保持资源 uid 不漂移
function UidOf([int]$d) {
	$node = $plan.uids
	if (-not $node) { return '' }
	$prop = $node.PSObject.Properties | Where-Object { $_.Name -eq "$d" } | Select-Object -First 1
	if ($prop -and "$($prop.Value)" -match '^uid://') { return "$($prop.Value)" }
	return ''
}

## 生成和 roster_editor.html 完全一致的 .tres 文本
function BuildTres([int]$d, [string[]]$ids, [int]$slots, [string]$uid) {
	$L = New-Object System.Collections.Generic.List[string]
	$head = '[gd_resource type="Resource" script_class="DayConfig" format=3'
	if ($uid) { $head = $head + ' uid="' + $uid + '"' }
	$L.Add($head + ']')
	$L.Add('')
	$L.Add('[ext_resource type="Script" path="res://scripts/resources/candidate_resource.gd" id="1_cand"]')
	for ($i = 0; $i -lt $ids.Count; $i++) {
		$L.Add('[ext_resource type="Resource" path="res://data/candidates/' + $ids[$i] + '.tres" id="' + ($i + 2) + '_c' + $i + '"]')
	}
	$scriptId = ($ids.Count + 2).ToString() + '_script'
	$L.Add('[ext_resource type="Script" path="res://scripts/resources/day_config.gd" id="' + $scriptId + '"]')
	$L.Add('')
	$L.Add('[resource]')
	$L.Add('script = ExtResource("' + $scriptId + '")')
	$L.Add('day_index = ' + $d)
	$refs = @()
	for ($i = 0; $i -lt $ids.Count; $i++) { $refs += 'ExtResource("' + ($i + 2) + '_c' + $i + '")' }
	$L.Add('candidates = Array[ExtResource("1_cand")]([' + ($refs -join ', ') + '])')
	$L.Add('slots = ' + $slots)
	$tut = 0
	if ($d -eq 1) { $tut = 1 }
	$L.Add('tutorial_step = ' + $tut)
	$L.Add('')
	return ($L -join "`n")
}

## 读现有 day 文件里的名单（只用来打印对比）
function OldIdsOf([string]$path) {
	if (-not (Test-Path -LiteralPath $path)) { return @() }
	$t = [System.IO.File]::ReadAllText($path, $utf8)
	$out = @()
	foreach ($m in [regex]::Matches($t, 'res://data/candidates/([A-Za-z0-9_]+)\.tres')) { $out += $m.Groups[1].Value }
	return $out
}

## 读现有 day 文件的 slots（没写就是 3 —— DayConfig 的默认值）
function OldSlotsOf([string]$path) {
	if (-not (Test-Path -LiteralPath $path)) { return 3 }
	$t = [System.IO.File]::ReadAllText($path, $utf8)
	$m = [regex]::Match($t, '(?m)^slots = (\d+)')
	if ($m.Success) { return [int]$m.Groups[1].Value }
	return 3
}
function OldUidOf([string]$path) {
	if (-not (Test-Path -LiteralPath $path)) { return '' }
	$t = [System.IO.File]::ReadAllText($path, $utf8)
	$m = [regex]::Match($t, '^\[gd_resource[^\]]*uid="(uid://[^"]+)"')
	if ($m.Success) { return $m.Groups[1].Value }
	return ''
}

$problems = @()
$rows = @()
foreach ($d in $Days) {
	$ids = DayIdsOf $d
	$slots = SlotOf $d $ids.Count
	foreach ($id in $ids) {
		if (-not (Test-Path -LiteralPath (Join-Path $candDir ($id + '.tres')))) {
			$problems += "Day $d : data/candidates/$id.tres 不存在"
		}
	}
	if (($ids | Sort-Object -Unique).Count -ne $ids.Count) { $problems += "Day $d : 名单里有重复的人" }
	$path = Join-Path $dayDir ('day_' + $d.ToString('00') + '.tres')
	$old = OldIdsOf $path
	$uid = UidOf $d
	if (-not $uid -and (Test-Path -LiteralPath $path)) { $uid = OldUidOf $path }
	$rows += [pscustomobject]@{
		Day = $d; Path = $path
		Old = ($old -join ', ')
		New = ($ids -join ', ')
		Slots = $slots
		Uid = $uid
		Text = (BuildTres $d $ids $slots $uid)
		Changed = ((($old -join ',') -ne ($ids -join ',')) -or ((OldSlotsOf $path) -ne $slots))
	}
}

if ($problems.Count) {
	Write-Output '发现问题，什么都没写：'
	$problems | ForEach-Object { Write-Output ('  ! ' + $_) }
	exit 1
}

Write-Output ("=== 计划：{0} 天，共 {1} 位 ===" -f $rows.Count, (($rows | ForEach-Object { (DayIdsOf $_.Day).Count } | Measure-Object -Sum).Sum))
foreach ($r in $rows) {
	$flag = '  '
	if ($r.Changed) { $flag = '* ' }
	Write-Output ("{0}Day {1,2}  slots={2}  {3}" -f $flag, $r.Day, $r.Slots, $r.New)
	if ($r.Changed) { Write-Output ("      旧：" + $(if ($r.Old) { $r.Old } else { '(空)' })) }
}

if (-not $Apply) {
	Write-Output ''
	Write-Output '上面带 * 的是会改写的天。确认没问题就加 -Apply 真写盘。'
	return
}

foreach ($r in $rows) {
	if (-not $r.Changed) { continue }
	if ($Backup -and (Test-Path -LiteralPath $r.Path)) {
		Copy-Item -LiteralPath $r.Path -Destination ($r.Path + '.bak') -Force
	}
	[System.IO.File]::WriteAllText($r.Path, $r.Text, $utf8)
	Write-Output ("写了 " + $r.Path.Substring($root.Length + 1).Replace('\', '/'))
}
Write-Output '完成。回 Godot 里点一下资源管理器（或让我 scan 一次）就会重新导入。'
