## 격자 위를 한 칸씩 이동한다.
##
## 위치가 곧 타일 좌표이므로 "지금 어느 칸에 도구를 쓰는가"에 모호함이 없다.
## 설계에서 격자 이동을 택한 이유가 이 단순함이다.
class_name Player
extends Node2D

## 심기는 도구가 아니지만 같은 선택 슬롯을 쓴다
const ACTION_PLANT := "plant"

## 이동 키를 누르고 있을 때 반복 이동하는 간격(초)
const MOVE_REPEAT_DELAY := 0.14

var cell := Vector2i(0, 0)
var facing := Vector2i(0, 1)   # 아래를 향해 시작

var _move_cooldown := 0.0

func _ready() -> void:
	_sync_position()

func _process(delta: float) -> void:
	# 상점 창이 열려 있으면 조작하지 않는다
	if GameState.shop_open:
		return

	_move_cooldown = max(0.0, _move_cooldown - delta)
	_handle_select()
	_handle_move()
	_handle_action()

## 1=괭이, 2=물뿌리개, 3=심기 / Q,W,E=작물 선택
func _handle_select() -> void:
	if Input.is_key_pressed(KEY_1):
		GameState.select_tool(Constants.TOOL_HOE)
	elif Input.is_key_pressed(KEY_2):
		GameState.select_tool(Constants.TOOL_CAN)
	elif Input.is_key_pressed(KEY_3):
		GameState.select_tool(ACTION_PLANT)

	if Input.is_key_pressed(KEY_Q):
		GameState.select_crop("turnip")
	elif Input.is_key_pressed(KEY_W):
		GameState.select_crop("potato")
	elif Input.is_key_pressed(KEY_E):
		GameState.select_crop("pumpkin")

func _handle_move() -> void:
	var dir := Vector2i.ZERO
	if Input.is_action_pressed("ui_up"):
		dir = Vector2i(0, -1)
	elif Input.is_action_pressed("ui_down"):
		dir = Vector2i(0, 1)
	elif Input.is_action_pressed("ui_left"):
		dir = Vector2i(-1, 0)
	elif Input.is_action_pressed("ui_right"):
		dir = Vector2i(1, 0)

	if dir == Vector2i.ZERO:
		_move_cooldown = 0.0
		return
	if _move_cooldown > 0.0:
		return

	# 방향이 바뀌면 그 자리에서 돌아본다 — 이동 없이 방향만 전환
	if facing != dir:
		facing = dir
		_move_cooldown = MOVE_REPEAT_DELAY
		queue_redraw()
		return

	var target := cell + dir
	if _can_stand_on(target):
		cell = target
		_sync_position()
	_move_cooldown = MOVE_REPEAT_DELAY

## 서 있을 수 있는 칸인가. 밭 안이거나 상점/출하함/침대 칸이면 가능.
func _can_stand_on(target: Vector2i) -> bool:
	if GameState.model.has_cell(target):
		return true
	return target in [Constants.SHOP_CELL, Constants.BIN_CELL, Constants.BED_CELL]

func _handle_action() -> void:
	if not Input.is_action_just_pressed("ui_accept"):
		return

	var target := front_cell()

	# 침대 앞이면 잔다
	if target == Constants.BED_CELL:
		GameState.sleep()
		return

	# 상점 앞이면 창을 연다
	if target == Constants.SHOP_CELL:
		GameState.open_shop()
		return

	# 출하함 앞이면 가방의 작물을 전부 판다
	if target == Constants.BIN_CELL:
		GameState.sell_all()
		return

	# 다 자란 작물 앞이면 도구와 무관하게 수확한다.
	# 다 자란 작물에 물을 주거나 밭을 갈 이유가 없으므로 모호함이 없다.
	if GameState.model.is_harvestable(target):
		GameState.harvest(target)
		return

	if GameState.selected_tool == ACTION_PLANT:
		GameState.plant(target, GameState.selected_crop)
	else:
		GameState.use_tool(target, facing, GameState.selected_tool)

func front_cell() -> Vector2i:
	return cell + facing

func _sync_position() -> void:
	position = Vector2(cell) * Constants.TILE_SIZE
	queue_redraw()

func _draw() -> void:
	var size := float(Constants.TILE_SIZE)
	# 몸통 — 칸보다 살짝 작게 그려 격자가 보이도록
	draw_rect(Rect2(Vector2.ONE * 6, Vector2.ONE * (size - 12)), Constants.COLOR_PLAYER)
	# 바라보는 방향 표시 — 몸통 가장자리의 작은 사각형
	var marker := Rect2(
		Vector2.ONE * (size / 2.0 - 4) + Vector2(facing) * (size / 2.0 - 7),
		Vector2.ONE * 8
	)
	draw_rect(marker, Constants.COLOR_FACING)
