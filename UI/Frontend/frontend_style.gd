class_name FrontendStyle
extends RefCounted

## Shared visual tokens for the temporary brown-and-gold front-end skin.
## Keep values here so selection screens can be reskinned without changing logic.

const CREAM := Color("#F8E7BC")
const CREAM_LIGHT := Color("#FFF4D8")
const BROWN := Color("#4B281E")
const BROWN_DARK := Color("#2F1812")
const BROWN_MUTED := Color("#755748")
const GOLD := Color("#D69A4E")
const GOLD_LIGHT := Color("#FFD98A")
const ORANGE := Color("#C86627")
const ORANGE_LIGHT := Color("#E88635")
const GREEN := Color("#65865A")
const DISABLED := Color("#88796A")
const FOCUS := Color("#FFFDF6")

enum CardState {
	NORMAL,
	SELECTED,
	OCCUPIED,
	CONFIRMED,
}


static func make_box(
	background: Color,
	border: Color,
	border_width: int = 3,
	radius: int = 16,
	padding: Vector4 = Vector4(22.0, 16.0, 22.0, 16.0)
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = padding.x
	style.content_margin_top = padding.y
	style.content_margin_right = padding.z
	style.content_margin_bottom = padding.w
	return style


static func card_style(
	state: CardState,
	hovered: bool,
	focused: bool,
	pressed: bool,
	interactable: bool
) -> StyleBoxFlat:
	var background := CREAM
	var border := GOLD
	var width := 3

	if not interactable:
		background = Color(DISABLED, 0.54)
		border = Color(CREAM, 0.45)
	elif state == CardState.SELECTED:
		background = Color("#F2C880")
		border = ORANGE_LIGHT
		width = 5
	elif state == CardState.OCCUPIED:
		background = Color("#C9BDAA")
		border = BROWN_MUTED
		width = 4
	elif state == CardState.CONFIRMED:
		background = Color("#D8D9A6")
		border = GREEN
		width = 5

	if pressed:
		background = background.darkened(0.16)
		border = ORANGE
	elif focused:
		border = FOCUS
		width = 6
	elif hovered:
		background = background.lightened(0.10)
		border = GOLD_LIGHT
		width = maxi(width, 4)

	var style := make_box(background, border, width, 18, Vector4(20.0, 18.0, 20.0, 18.0))
	if focused:
		style.expand_margin_left = 3.0
		style.expand_margin_top = 3.0
		style.expand_margin_right = 3.0
		style.expand_margin_bottom = 3.0
	elif hovered:
		style.expand_margin_left = 1.0
		style.expand_margin_top = 1.0
		style.expand_margin_right = 1.0
		style.expand_margin_bottom = 1.0
	return style


static func card_title_color(state: CardState, interactable: bool) -> Color:
	if not interactable:
		return Color(CREAM_LIGHT, 0.72)
	if state == CardState.OCCUPIED:
		return BROWN_MUTED
	return BROWN_DARK


static func card_badge(state: CardState, occupied_by: String) -> String:
	match state:
		CardState.SELECTED:
			return "已选"
		CardState.OCCUPIED:
			return "%s 已选" % (occupied_by if not occupied_by.is_empty() else "其他玩家")
		CardState.CONFIRMED:
			return "已确认"
		_:
			return ""
