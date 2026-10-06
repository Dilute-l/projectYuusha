@tool
extends EditorScript

## 点击掩码生成工具
## ================
##
## 用途：给一张贴图生成「有尺寸」的 BitMap 点击掩码资源，供
## TextureButton.texture_click_mask 使用。
##
## 为什么需要它
## ------------
## 在 FileSystem 面板里「新建 → 资源 → BitMap」拿到的是一个 0×0 的空 BitMap。
## 0×0 的 BitMap 有两个致命问题：
##   1. 双击打开底部 BitMap 面板会报
##      "The Image width specified (0 pixels) must be greater than 0 pixels."
##      （面板内部用 convert_to_image() 渲染预览），而且面板没法给它定尺寸；
##   2. 当作 click mask 用时，get_bitv() 在 0 尺寸上永远越界返回 false，
##      按钮会完全点不动。
## 所以必须先用 create() / create_from_image_alpha() 给它尺寸。
##
## 怎么用
## ------
## 1. 改下面三个变量，指向你的按钮贴图和想要的输出路径
## 2. 在 Godot 脚本编辑器里打开本文件
## 3. 菜单「文件 → 运行」（快捷键 Ctrl+Shift+X）
## 4. 看底部 Output 面板的打印
##
## 产出的 .tres 可以直接拖到 TextureButton 的 texture_click_mask；
## 双击它能在底部 BitMap 面板里手工微调。
##
## 注意
## ----
## 掩码是「快照」。换了贴图（尺寸或轮廓变了）就要重跑一次，否则点击区域
## 会和看到的图形对不上——而且不会报任何错，很难查。

## ★ 源贴图：改成你要生成掩码的按钮图
var source_texture := "res://assets/art/btn_phd.png"

## ★ 输出路径。小掩码用 .tres（文本、可 diff）；很大的掩码可改成 .res
var output_mask := "res://assets/art/phd_click_mask.tres"

## ★ alpha 阈值：alpha 大于它的像素算「可点击」。
## 调大可以排除抗锯齿的软边缘。
var alpha_threshold := 0.1


func _run() -> void:
	if _generate(source_texture, output_mask, alpha_threshold):
		print("完成。双击 %s 可在底部 BitMap 面板里手工编辑。" % output_mask)


## 核心逻辑。返回 true 表示掩码已成功保存。
func _generate(tex_path: String, out_path: String, threshold: float) -> bool:
	# 先判存在：直接 load() 一个不存在的路径会让 Godot 抛一条引擎级红字错误，
	# 路径打错时会被那条红字带偏，看不到下面这条真正有用的提示。
	if not ResourceLoader.exists(tex_path):
		printerr("找不到贴图：", tex_path)
		return false

	# 用 as 转换而不是类型化赋值：路径指向非贴图资源时得到 null，
	# 由下面的判空处理，而不是抛类型错误。
	var tex := load(tex_path) as Texture2D
	if tex == null:
		printerr("加载到的不是贴图：", tex_path)
		return false

	var img := tex.get_image()
	if img == null or img.get_width() == 0 or img.get_height() == 0:
		printerr("贴图没有可用图像（尺寸为 0）：", tex_path)
		return false

	# create_from_image_alpha 会把掩码尺寸自动设为图片尺寸，
	# 正好满足 TextureButton「掩码尺寸必须等于贴图尺寸」的要求。
	var mask := BitMap.new()
	mask.create_from_image_alpha(img, threshold)

	var size := mask.get_size()
	var total := size.x * size.y
	var lit := mask.get_true_bit_count()
	var pct := 100.0 * float(lit) / float(maxi(total, 1))

	print("源图 %s %s → 掩码 %s，可点击像素 %d / %d (%.1f%%)" % [
		tex_path, img.get_size(), size, lit, total, pct])

	if lit == 0:
		printerr("掩码全空：这张贴图可能没有 alpha 通道（不透明矩形）。")
		return false
	if lit == total:
		printerr("掩码全满：贴图是不透明矩形，这样的掩码没有意义——")
		printerr("要么换成透明背景的按钮图，要么改用 Control._has_point() 画几何形状。")
		return false

	var dir := out_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		var mk := DirAccess.make_dir_recursive_absolute(dir)
		if mk != OK:
			printerr("创建目录失败 %s：%d" % [dir, mk])
			return false

	var err := ResourceSaver.save(mask, out_path)
	if err != OK:
		printerr("保存失败 %s：%d" % [out_path, err])
		return false

	print("已保存：", out_path)
	return true
