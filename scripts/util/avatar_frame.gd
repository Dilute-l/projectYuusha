class_name AvatarFrame
extends RefCounted

## 头像框的**美术出处与几何**（ARCHITECTURE.md §12.4）。
##
## 一套三张同坐标系的 300x300 图，叠起来就是组队界面上的一个头像：
##
##     Background  底板（实心）—— 头像的「底色」，进队染绿 / 不进队染红就是染它
##     Portrait    候选人的整身立绘（`PortraitComposer.portrait_texture()`，300x300 原位）
##     Frame       手绘方框，中间是一块**透空**的取景窗
##
## ⚠️ 立绘**不缩放、不居中**（§12.4）：它按自己的 300x300 坐标系原位贴上去，
##   只有取景窗里那一块看得见，窗外的（腿 / 矮人帽子的边）交给裁切切掉。
##   所以这里唯一需要量的常量只有 WINDOW，其余全是「照着画布摆」。
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
