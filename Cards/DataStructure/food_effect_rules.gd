class_name FoodEffectRules
extends RefCounted

## Pure immediate effects shared by the real resolver and AI previews.
static func immediate(food_id: String, level: int, energy: int) -> Dictionary:
	if level == 0: return {"energy": 2, "money": 0}
	match food_id:
		"dong_po_bing", "ma_cheng_rou_gao", "sha_wo_dou_si", "yi_chang_xiao_mian", "zhu_xi_wan_gao": return {"energy": 3, "money": 0}
		"jing_zhou_yu_gao": return {"energy": 6, "money": 0}
		"chi_bi_rou_gao", "san_you_shen_xian_ji": return {"energy": 0, "money": 500}
		"re_gan_mian": return {"energy": energy, "money": 0}
	return {}
