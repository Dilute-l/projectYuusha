# Build tools/roster_editor.html from tools/roster_editor.template.html + the live data in data/.
# ASCII-only source on purpose (PS 5.1 reads BOM-less .ps1 as ANSI).
#
#   pwsh -File tools/build_roster_editor.ps1      (or just  .\tools\build_roster_editor.ps1)
#
# 改了 data/candidates/*.tres 或 data/asks/*.json 之后重跑一次，工具里的数据就刷新了。

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$utf8 = New-Object System.Text.UTF8Encoding($false)
$candDir = Join-Path $root 'data\candidates'
$askDir = Join-Path $root 'data\asks'
$template = Join-Path $PSScriptRoot 'roster_editor.template.html'
$outFile = Join-Path $PSScriptRoot 'roster_editor.html'

if (-not (Test-Path -LiteralPath $template)) { throw "missing template: $template" }

function FieldOf([string]$text, [string]$key) {
	$m = [regex]::Match($text, "(?m)^$([regex]::Escape($key)) = (.*)$")
	if (-not $m.Success) { return $null }
	$v = $m.Groups[1].Value.Trim()
	$q = [regex]::Match($v, '^&?"(.*)"$')
	if ($q.Success) { return $q.Groups[1].Value }
	return $v
}

$candidates = @()
foreach ($f in (Get-ChildItem -LiteralPath $candDir -File -Filter 'c_*.tres' | Sort-Object Name)) {
	if ($f.Name -notmatch '^c_(ct|md|dl)_\d+\.tres$') { continue }
	$group = $matches[1]
	$t = [System.IO.File]::ReadAllText($f.FullName, $utf8)

	# ext_resource id -> res:// path
	$ext = @{}
	foreach ($m in [regex]::Matches($t, '\[ext_resource [^\]]*path="res://([^"]+)" id="([^"]+)"\]')) {
		$ext[$m.Groups[2].Value] = $m.Groups[1].Value
	}
	function ExtName([string]$ref) {
		$m = [regex]::Match($ref, '^ExtResource\("([^"]+)"\)$')
		if (-not $m.Success) { return '' }
		$p = $ext[$m.Groups[1].Value]
		if (-not $p) { return '' }
		return [System.IO.Path]::GetFileNameWithoutExtension($p)
	}
	function RefList([string]$key) {
		$m = [regex]::Match($t, "(?m)^$([regex]::Escape($key)) = Array\[[^\]]*\]\(\[(.*?)\]\)")
		$out = @()
		if (-not $m.Success) { return $out }
		foreach ($r in [regex]::Matches($m.Groups[1].Value, '(ExtResource|SubResource)\("([^"]+)"\)')) {
			$out += [pscustomobject]@{ Kind = $r.Groups[1].Value; Key = $r.Groups[2].Value }
		}
		return $out
	}

	# sub_resource: id -> @{ Desc; Ask }
	$subs = [ordered]@{}
	foreach ($m in [regex]::Matches($t, '(?s)\[sub_resource type="Resource" id="([^"]+)"\]\s*script = ExtResource\("[^"]+"\)\s*description = "(.*?)"\s*ask_path = "([^"]+)"')) {
		$subs[$m.Groups[1].Value] = [pscustomobject]@{
			Desc = $m.Groups[2].Value
			Ask  = $m.Groups[3].Value
		}
	}

	# 条目顺序：先 experience 再 skill（和简历上的排法一致）
	$entries = @()
	foreach ($pair in @(@{ Kind = 'experience'; List = (RefList 'experience') }, @{ Kind = 'skill'; List = (RefList 'skill') })) {
		foreach ($ref in $pair.List) {
			if ($ref.Kind -ne 'SubResource') { continue }
			$s = $subs[$ref.Key]
			if (-not $s) { continue }
			$askLines = @()
			$askFile = $s.Ask
			if ($askFile -and $askFile.StartsWith('res://')) {
				$local = Join-Path $root ($askFile.Replace('res://', '').Replace('/', '\'))
				if (Test-Path -LiteralPath $local) {
					try {
						$parsed = Get-Content -Raw -LiteralPath $local -Encoding UTF8 | ConvertFrom-Json
						foreach ($line in $parsed) {
							$item = [ordered]@{ who = [string]$line.speaker_name; text = [string]$line.text }
							if ($line.PSObject.Properties.Name -contains 'popup' -and $line.popup) { $item.popup = [string]$line.popup }
							if ($line.PSObject.Properties.Name -contains 'popup_stamp' -and $line.popup_stamp) { $item.stamp = [string]$line.popup_stamp }
							$askLines += [pscustomobject]$item
						}
					} catch {
						Write-Warning ("ask json parse failed: " + $local)
					}
				} else {
					Write-Warning ("ask json missing: " + $askFile)
				}
			}
			$entries += [pscustomobject]@{
				kind = $pair.Kind
				desc = $s.Desc
				ask  = $askLines
			}
		}
	}

	$traits = @()
	foreach ($r in (RefList 'traits')) { if ($r.Kind -eq 'ExtResource') { $name = ExtName ('ExtResource("' + $r.Key + '")'); if ($name) { $traits += $name } } }

	$level = FieldOf $t 'level'
	if (-not $level) { $level = '1' }
	$fakeLevel = FieldOf $t 'fake_level'
	if (-not $fakeLevel) { $fakeLevel = '0' }

	$candidates += [pscustomobject][ordered]@{
		id      = $f.BaseName
		name    = [string](FieldOf $t 'display_name')
		group   = $group
		job     = ExtName ([string](FieldOf $t 'job'))
		race    = ExtName ([string](FieldOf $t 'race'))
		level   = [int]$level
		fake    = [int]$fakeLevel
		dispr   = [string](FieldOf $t 'display_race')
		gender  = [string](FieldOf $t 'gender')
		age     = [int](FieldOf $t 'age')
		str     = [int](FieldOf $t 'strength')
		int     = [int](FieldOf $t 'intelligence')
		wis     = [int](FieldOf $t 'wisdom')
		traits  = $traits
		stamp   = [bool](FieldOf $t 'resume_stamp')
		declaration = [string](FieldOf $t 'team_declaration')
		judgment    = [string](FieldOf $t 'judgment')
		entries = $entries
	}
}

if ($candidates.Count -eq 0) { throw "no candidates parsed from $candDir" }

# 池子之外的卡（旧占位 c_0001.. 之类）：只留 id + 名字，用来显示/校验 data/days 里读到的名单
$others = @()
foreach ($f in (Get-ChildItem -LiteralPath $candDir -File -Filter 'c_*.tres' | Sort-Object Name)) {
	if ($f.Name -notmatch '^c_\d+\.tres$') { continue }
	$t = [System.IO.File]::ReadAllText($f.FullName, $utf8)
	$others += [pscustomobject][ordered]@{
		id   = $f.BaseName
		name = [string](FieldOf $t 'display_name')
	}
}

$payload = [pscustomobject][ordered]@{
	generatedAt = (Get-Date).ToString('s')
	count       = $candidates.Count
	candidates  = $candidates
	others      = $others
}
$json = $payload | ConvertTo-Json -Depth 12 -Compress
# 内嵌进 <script> 里，把 "<" 转义掉最保险（也顺手避开 "</script>"）
$json = $json.Replace('<', '\u003c')

$tpl = [System.IO.File]::ReadAllText($template, $utf8)
if (-not $tpl.Contains('__ROSTER_DATA__')) { throw "template has no __ROSTER_DATA__ placeholder" }
$html = $tpl.Replace('__ROSTER_DATA__', $json)
[System.IO.File]::WriteAllText($outFile, $html, $utf8)

$askCount = ($candidates | ForEach-Object { $_.entries } | ForEach-Object { $_.ask } | Measure-Object).Count
Write-Output ("built " + $outFile)
Write-Output ("  candidates : " + $candidates.Count)
Write-Output ("  others     : " + $others.Count + "  (legacy placeholder cards: display/validate only)")
Write-Output ("  resume rows: " + (($candidates | ForEach-Object { $_.entries.Count } | Measure-Object -Sum).Sum))
Write-Output ("  ask lines  : " + $askCount)
Write-Output ("  size       : " + [math]::Round((Get-Item -LiteralPath $outFile).Length / 1KB, 1) + " KB")
