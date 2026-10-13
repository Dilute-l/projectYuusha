class_name AvatarFrame
extends RefCounted

## 头像框的**美术出处与几何**（ARCHITECTURE.md §12.4）。
##
## 一套三张同坐标系的 300x300 图，叠起来就是组队界面上的一个头像：
##
##     Background  底板（实心）—— 头像的「底色」，进队染绿 / 不进队染红就是染它
##     Portrait    候选人的整身立绘（`PortraitComposer.portrait_texture()`）
##     Frame       手绘方框，中间是一块**透空**的取景窗
##
## ⚠️ 立绘**不取景、不居中**（§12.4）：它按自己的坐标系原位贴上去，
##   只有取景窗里那一块看得见，窗外的（腿 / 矮人帽子的边）交给裁切切掉。
##   所以这里唯一需要量的常量只有 WINDOW，其余全是「照着画布摆」。
##
## ⚠️ 立绘有自己的画布尺寸（`PortraitComposer.CANVAS`），比本头像框的画布大 ——
##   要乘 `PORTRAIT_SCALE` 才落到本坐标系里。见那个常量的说明。
##
## 本类不认识节点也不碰 GameState：只报常量、贴图和几个换算函数，
## 控件（FramedAvatar）和自检都拿它当唯一出处。

## 方框（压在立绘之上的那一张）
const FRAME_PATH := "res://assets/art/interview/avatar_frame_phd.png"

## 底板（垫在立绘之下、决定头像底色的一张）
const BACKGROUND_PATH := "res://assets/art/interview/avatar_frame_background_phd.png"

## 「进队 / 不进队」两个按钮的美术
const APPROVE_BUTTON_PATH := "res://assets/art/interview/team_select_approve_phd.png"
const REJECT_BUTTON_PATH := "res://assets/art/interview/team_select_reject_phd.png"

## 三张图的画布边长（它们是同一个坐标系的三层）
const CANVAS := 300

## 立绘画布 → 头像框画布 的缩放系数。
##
## 立绘与头像框**曾经是同一张 300x300 的画布**，立绘 1:1 原位贴上去、取景窗量多少就露多少。
## 后来立绘重画成了 `PortraitComposer.CANVAS × CANVAS_H`（600×675，整整两倍），
## 头像框那三张 300x300 的美术没跟着放大 —— 于是两边差了这么一倍：
## 立绘必须先折算回头像框坐标系，取景窗 `WINDOW`（画在头像框坐标系里）才对得上人物的脸。
##
## ⚠️ 漏掉这一步的后果就是「头像里只剩立绘的左上角」：600x675 的图按 1:1 铺在
##   300x300 的框里，窗口只框到画布左上角那一小块（脸和眼睛都在窗口外面）。
##
## 系数取 0.6（不是刚好对折的 0.5）：取景窗是「头肩像」的画幅，脸占窗口约 3/4 宽最像
## 原来那版（旧的 300x300 素材脸占约 7 成）—— 0.5 会小一圈，0.75 起发梢就被裁到了。
## ⚠️ **人脸在立绘画布上的高度是各画各的**，本类不做任何「自动找脸」的居中：
##   人类 / 精灵把脸画在画布上方（`stems_for` 那套眼 / 发 / 嘴），矮人的脸画在
##   画布最底部（帽子占满上方）——这是**设计意图**，不是素材没对齐。
##   所以矮人在这个头像框里看到的是他的帽子（脸被窗口下沿裁在下面），
##   这是「矮人 = 大帽子」的既定观感；要改的只有重画素材，不是这里的常量。
const PORTRAIT_SCALE := 0.6

## 取景窗：方框**内沿**围出来的那块透明区域（单位 = 画布像素）。
##
## 是**量出来的**，不是估的：逐行找左边框的内沿、逐列找上边框的内沿，取各行的交集 ——
## 手绘边框是歪的，只有取交集才能保证窗口里一个框像素都不落进来。
## 自检会拿 FRAME_PATH 这张图重算一遍（窗口内不得有框的不透明像素），对不上就红。
const WINDOW := Rect2(26, 23, 254, 249)

## 两个按钮图上「真的有画」的那一块。透明留白要裁掉，
## 否则按钮控件会带着一圈空白，既摆不准也点不到。
const APPROVE_ART := Rect2(34, 77, 222, 144)
const REJECT_ART := Rect2(44, 77, 222, 144)


static func frame_texture() -> Texture2D:
	return load(FRAME_PATH)


static func background_texture() -> Texture2D:
	return load(BACKGROUND_PATH)


## 把画布坐标换算到「这个头像渲染成 px 像素」时的控件坐标
static func scale_for(px: float) -> float:
	return px / float(CANVAS)


## 取景窗落在控件上的矩形：裁切容器就摆在这里，立绘按 `-position` 垫进去。
static func window_rect(px: float) -> Rect2:
	var k := scale_for(px)
	return Rect2(WINDOW.position * k, WINDOW.size * k)


## 按「摆出来的宽度」算美术块的控件尺寸（保持美术自己的宽高比）。
##
## 按钮只给宽度就够了：两个按钮图裁出来都是 222x144，
## 高度跟着宽度走才不会把人像/字拉扁。
static func size_for_width(art: Rect2, width: float) -> Vector2:
	return Vector2(width, width * art.size.y / art.size.x)
