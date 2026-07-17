## 현재 상태를 좌상단에 텍스트로 표시한다. 상태를 읽기만 한다.
class_name Hud
extends CanvasLayer

var _label: Label
var _help: Label

func _ready() -> void:
	_label = _make_label(Vector2(12, 8), 15)
	_help = _make_label(Vector2(12, 512), 13)
	_help.text = "방향키=이동/방향전환   스페이스=행동   1=괭이 2=물뿌리개 3=심기   Q=순무 W=감자 E=호박"

	GameState.stats_changed.connect(_refresh)
	GameState.tool_changed.connect(_refresh)
	_refresh()

func _make_label(pos: Vector2, font_size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	add_child(l)
	return l

func _refresh() -> void:
	var m := GameState.model
	_label.text = "\n".join([
		"%d일차   %s" % [m.day, m.time_string()],
		"체력 %d / %d" % [m.energy, m.max_energy],
		"돈 %d" % m.money,
		"손에 든 것: %s        심을 작물: %s" % [_tool_name(), _crop_name()],
		_inventory_line(),
	])

func _tool_name() -> String:
	var m := GameState.model
	match GameState.selected_tool:
		Constants.TOOL_HOE:
			return "괭이 Lv%d" % m.tool_levels[Constants.TOOL_HOE]
		Constants.TOOL_CAN:
			return "물뿌리개 Lv%d" % m.tool_levels[Constants.TOOL_CAN]
		_:
			return "씨앗 (심기)"

func _crop_name() -> String:
	return Constants.CROPS[GameState.selected_crop]["name"]

func _inventory_line() -> String:
	var parts: Array[String] = []
	for item_id in GameState.model.inventory:
		parts.append("%s %d" % [_item_name(item_id), GameState.model.inventory[item_id]])
	return "가방: " + ("비어있음" if parts.is_empty() else "   ".join(parts))

func _item_name(item_id: String) -> String:
	var crop_id := Constants.crop_id_of_seed(item_id)
	if crop_id != "" and Constants.CROPS.has(crop_id):
		return Constants.CROPS[crop_id]["name"] + " 씨앗"
	if Constants.CROPS.has(item_id):
		return Constants.CROPS[item_id]["name"]
	return item_id
