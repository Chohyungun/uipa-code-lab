## 상점 창. 열려 있는 동안 플레이어 조작과 시계가 멈춘다.
class_name ShopUi
extends CanvasLayer

var _panel: PanelContainer
var _rows: VBoxContainer

func _ready() -> void:
	_build()
	visible = false
	GameState.shop_opened.connect(_open)

func _build() -> void:
	_panel = PanelContainer.new()
	_panel.position = Vector2(190, 110)
	_panel.custom_minimum_size = Vector2(400, 0)
	add_child(_panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	_panel.add_child(margin)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 5)
	margin.add_child(_rows)

func _open() -> void:
	visible = true
	_refresh()

func _close() -> void:
	visible = false
	GameState.close_shop()

func _refresh() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()

	_add_title("상점        소지금 %d원" % GameState.model.money)
	for crop_id in Constants.CROPS:
		var crop: Dictionary = Constants.CROPS[crop_id]
		_add_button(
			"%s 씨앗  —  %d원  (%d일 성장, %d원에 팔림)"
				% [crop["name"], crop["seed_price"], crop["days"], crop["sell_price"]],
			_buy.bind(crop_id),
			GameState.model.money >= int(crop["seed_price"])
		)

	_add_title("")
	_add_title("도구 업그레이드")
	_add_tool_row(Constants.TOOL_HOE, "괭이")
	_add_tool_row(Constants.TOOL_CAN, "물뿌리개")

	_add_title("")
	_add_button("닫기", _close, true)

func _add_tool_row(tool_id: String, label: String) -> void:
	var level: int = GameState.model.tool_levels[tool_id]
	var cost := GameState.model.upgrade_cost(tool_id)
	if cost < 0:
		_add_title("   %s Lv%d — 최대 레벨" % [label, level])
		return
	var next_cells: int = [1, 3, 9][level]    # 다음 레벨이 한 번에 처리하는 칸 수
	var next_energy: int = Constants.TOOL_ENERGY[level + 1]
	_add_button(
		"%s Lv%d → Lv%d  —  %d원  (한 번에 %d칸, 체력 %d)"
			% [label, level, level + 1, cost, next_cells, next_energy],
		_upgrade.bind(tool_id),
		GameState.model.can_upgrade(tool_id)
	)

func _add_title(text: String) -> void:
	var l := Label.new()
	l.text = text
	_rows.add_child(l)

func _add_button(text: String, handler: Callable, enabled: bool) -> void:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.pressed.connect(handler)
	_rows.add_child(b)

func _buy(crop_id: String) -> void:
	GameState.buy_seed(crop_id, 1)
	_refresh()

func _upgrade(tool_id: String) -> void:
	GameState.upgrade_tool(tool_id)
	_refresh()
