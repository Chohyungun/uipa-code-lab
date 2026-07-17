## 밭을 색 도형으로 그린다. GameState.model을 읽기만 하고 변경하지 않는다.
##
## 이미지 에셋 없이 _draw()로 그리므로 .tscn에 노드를 배치할 필요가 없다.
## 나중에 스프라이트로 바꿀 때 이 파일만 고치면 되고 모델은 건드리지 않는다.
class_name FarmView
extends Node2D

func _ready() -> void:
	GameState.farm_changed.connect(queue_redraw)

func _draw() -> void:
	var model := GameState.model
	for y in Constants.FARM_HEIGHT:
		for x in Constants.FARM_WIDTH:
			var cell := Vector2i(x, y)
			_draw_cell(cell, model.get_tile(cell))

	_draw_building(Constants.SHOP_CELL, Constants.COLOR_SHOP, "상점")
	_draw_building(Constants.BIN_CELL, Constants.COLOR_BIN, "출하함")
	_draw_building(Constants.BED_CELL, Constants.COLOR_BED, "침대")

func _draw_cell(cell: Vector2i, tile: Dictionary) -> void:
	var rect := _cell_rect(cell)
	draw_rect(rect, _ground_color(tile))
	draw_rect(rect, Constants.COLOR_GRID, false, 1.0)
	if tile["state"] == FarmModel.TileState.PLANTED:
		_draw_crop(rect, tile)

func _ground_color(tile: Dictionary) -> Color:
	if tile["state"] == FarmModel.TileState.UNTILLED:
		return Constants.COLOR_UNTILLED
	return Constants.COLOR_WATERED if tile["watered"] else Constants.COLOR_TILLED

## 작물은 원으로 그린다. 성장할수록 커지고, 다 자라면 테두리가 붙는다.
func _draw_crop(rect: Rect2, tile: Dictionary) -> void:
	var crop: Dictionary = Constants.CROPS[tile["crop_id"]]
	var ratio := clampf(float(tile["growth"]) / float(crop["days"]), 0.0, 1.0)
	var radius := lerpf(Constants.TILE_SIZE * 0.12, Constants.TILE_SIZE * 0.36, ratio)
	draw_circle(rect.get_center(), radius, crop["color"])
	# 다 자란 작물은 흰 테두리로 표시 — 수확할 때가 됐다는 신호
	if ratio >= 1.0:
		draw_arc(rect.get_center(), radius + 3, 0, TAU, 24, Color.WHITE, 2.0)

func _draw_building(cell: Vector2i, color: Color, label: String) -> void:
	var rect := _cell_rect(cell)
	draw_rect(rect, color)
	draw_rect(rect, Color(0, 0, 0, 0.4), false, 1.0)
	var font := ThemeDB.fallback_font
	draw_string(font, rect.position + Vector2(3, Constants.TILE_SIZE - 6),
		label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.BLACK)

func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(
		Vector2(cell) * Constants.TILE_SIZE,
		Vector2.ONE * Constants.TILE_SIZE
	)
