extends HeritagePixelCanvas

const CLOSED := "res://InheritanceTasks/Art/Pixel/v1/runtime/craft/huangmei_xi-closed.png"

func paint() -> void:
	if artwork.version >= 3:
		paint_background()
		if not bool(visual_state.get("listening",true)):
			paint_avatar(Rect2(340,124,320,320),action())
		return
	if bool(visual_state.get("listening", true)):
		paint_asset(CLOSED, Rect2(0, 0, 1000, 600))
	else:
		paint_background()
		paint_avatar(Rect2(300, 120, 400, 400), action())
	# All lyrics, video, microphone state and scoring remain real foreground Controls.
