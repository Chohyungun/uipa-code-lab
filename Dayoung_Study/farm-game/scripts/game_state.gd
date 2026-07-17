## autoload 껍데기.
##
## Godot의 autoload는 Node를 상속해야 하므로 순수 모델(FarmModel)을 그대로 autoload할 수 없다.
## 이 클래스는 모델 인스턴스를 하나 들고, 노드여야만 할 수 있는 일만 한다:
## 시계 진행(_process), 신호 발신, 파일 입출력.
##
## 규칙은 판단하지 않는다. 모델에 전달하고 결과를 신호로 알릴 뿐이다.
extends Node

const SAVE_PATH := "user://save.json"

## 밭 칸의 상태가 바뀌었다 (다시 그려야 함)
signal farm_changed

## 시각/체력/돈/인벤토리가 바뀌었다 (HUD를 갱신해야 함)
signal stats_changed

## 선택된 도구나 작물이 바뀌었다
signal tool_changed

## 하루가 넘어갔다. collapsed가 true면 기절해서 넘어간 것.
signal day_advanced(collapsed: bool)

## 상점 창이 열렸다
signal shop_opened

var model: FarmModel

## 현재 손에 든 도구
var selected_tool := Constants.TOOL_HOE

## 심을 때 사용할 작물
var selected_crop := "turnip"

## 상점 창이 열려 있는 동안에는 플레이어가 움직이지 않는다
var shop_open := false

## 개발용 시계 배속. 1.0 = 현실 10초당 게임 10분.
var clock_speed := 1.0

## 아직 게임 시간으로 환산되지 않은 실제 경과 시간(분 단위 소수)
var _minute_carry := 0.0

## 모델 준비와 저장 파일 로드는 씬 트리가 필요 없는 일이므로 _init에서 한다.
## _ready에 두면 트리에 붙는 시점까지 model이 null이라, 다른 노드가 먼저 읽을 위험이 있다.
func _init() -> void:
	model = FarmModel.new()
	if not load_game():
		print("저장 파일이 없어 새 게임을 시작합니다")

## 실제 시간을 게임 시간으로 환산한다.
## Node만 _process를 받을 수 있으므로 이 일은 모델이 아니라 여기서 한다.
func _process(delta: float) -> void:
	if shop_open:
		return   # 상점 창이 열려 있으면 시간이 멈춘다

	_minute_carry += delta * Constants.GAME_MINUTES_PER_REAL_SECOND * clock_speed
	if _minute_carry < 1.0:
		return

	var whole := int(_minute_carry)
	_minute_carry -= whole

	var day_over := model.add_minutes(whole)
	stats_changed.emit()
	if day_over:
		_advance_day(true)   # 새벽 2시 도달 → 기절

# --- 행동 ---

func use_tool(origin: Vector2i, facing: Vector2i, tool_id: String) -> void:
	var changed := model.use_tool(origin, facing, tool_id)
	if not changed.is_empty():
		farm_changed.emit()
	stats_changed.emit()

	# 체력이 0이 되는 순간 기절한다.
	# "체력이 모자라면 행동을 거부한다"는 규칙을 쓰지 않는 이유:
	# 그러면 체력이 0에 닿기 전에 모든 행동이 막혀 기절이 영영 일어나지 않고,
	# 아무것도 못 하는데 하루도 안 끝나는 상태에 빠진다.
	if model.is_exhausted():
		_advance_day(true)

func plant(cell: Vector2i, crop_id: String) -> void:
	if model.plant(cell, crop_id):
		farm_changed.emit()
		stats_changed.emit()

func harvest(cell: Vector2i) -> void:
	if model.harvest(cell) != "":
		farm_changed.emit()
		stats_changed.emit()

func select_tool(tool_id: String) -> void:
	if selected_tool == tool_id:
		return
	selected_tool = tool_id
	tool_changed.emit()

func select_crop(crop_id: String) -> void:
	if selected_crop == crop_id:
		return
	selected_crop = crop_id
	tool_changed.emit()

# --- 하루 넘김 ---

## 침대에서 잔다 (체력 전량 회복)
func sleep() -> void:
	_advance_day(false)

func _advance_day(collapsed: bool) -> void:
	model.advance_day(collapsed)
	day_advanced.emit(collapsed)
	farm_changed.emit()
	stats_changed.emit()
	# 하루 넘김은 상태가 확실히 안정되는 유일한 지점이므로 여기서만 저장한다
	save_game()

# --- 상점 ---

func open_shop() -> void:
	shop_open = true
	shop_opened.emit()

func close_shop() -> void:
	shop_open = false

func buy_seed(crop_id: String, amount: int) -> void:
	if model.buy_seed(crop_id, amount):
		stats_changed.emit()

func sell_all() -> int:
	var earned := model.sell_all()
	if earned > 0:
		stats_changed.emit()
	return earned

func upgrade_tool(tool_id: String) -> void:
	if model.upgrade_tool(tool_id):
		stats_changed.emit()
		tool_changed.emit()

# --- 저장 / 불러오기 ---
#
# 파일 입출력은 Node인 GameState가 담당한다. 모델은 파일을 모른다.

func save_game() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("저장 실패: %s" % FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify(model.to_dict()))
	file.close()

## 저장 파일을 불러온다. 성공하면 true.
func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("불러오기 실패: %s" % FileAccess.get_open_error())
		return false

	var text := file.get_as_text()
	file.close()

	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("저장 파일이 손상되었습니다. 새 게임을 시작합니다.")
		return false

	model.from_dict(data)
	farm_changed.emit()
	stats_changed.emit()
	return true
