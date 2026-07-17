## 게임의 모든 상태와 규칙을 보유한다.
##
## Node가 아니므로 씬 트리 없이 생성·테스트할 수 있다.
## 화면, 입력, 파일에 대해 아무것도 모른다 — 그런 일은 GameState(autoload)가 한다.
class_name FarmModel
extends RefCounted

enum TileState { UNTILLED, TILLED, PLANTED }

var day: int
var hour: int
var minute: int
var money: int
var energy: int
var max_energy: int
var inventory: Dictionary       # item_id(String) → 개수(int)
var tool_levels: Dictionary     # tool_id(String) → 레벨(int)
var tiles: Dictionary           # Vector2i → 밭 칸 사전

func _init() -> void:
	reset_new_game()

func reset_new_game() -> void:
	day = 1
	hour = Constants.DAY_START_HOUR
	minute = 0
	money = Constants.START_MONEY
	max_energy = Constants.MAX_ENERGY
	energy = max_energy
	inventory = Constants.START_SEEDS.duplicate()
	tool_levels = {
		Constants.TOOL_HOE: 1,
		Constants.TOOL_CAN: 1,
	}
	tiles = {}
	for y in Constants.FARM_HEIGHT:
		for x in Constants.FARM_WIDTH:
			tiles[Vector2i(x, y)] = _make_tile()

func _make_tile() -> Dictionary:
	return {
		"state": TileState.UNTILLED,
		"crop_id": "",
		"growth": 0,
		"watered": false,
	}

# --- 밭 칸 ---

func has_cell(cell: Vector2i) -> bool:
	return tiles.has(cell)

## 밭 밖이면 빈 사전을 돌려준다.
## 빈 사전을 돌려주면 렌더링처럼 밭 밖을 훑는 코드가 터지지 않는다.
func get_tile(cell: Vector2i) -> Dictionary:
	return tiles.get(cell, {})

# --- 도구 범위 ---

## 도구가 영향을 미치는 칸 목록. origin은 플레이어가 바라보는 바로 앞 칸.
##
## 밭 밖 칸은 조용히 제외된다. 체력은 정액이므로 가장자리에서 휘두르면 손해지만,
## 그 판단은 플레이어의 몫이다.
func tool_area(origin: Vector2i, facing: Vector2i, level: int) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	match level:
		1:
			candidates.append(origin)
		2:
			for i in 3:
				candidates.append(origin + facing * i)
		3:
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					candidates.append(origin + Vector2i(dx, dy))
		_:
			push_error("알 수 없는 도구 레벨: %d" % level)

	var result: Array[Vector2i] = []
	for cell in candidates:
		if has_cell(cell):
			result.append(cell)
	return result

# --- 체력 ---

func is_exhausted() -> bool:
	return energy <= 0

func tool_energy_cost(tool_id: String) -> int:
	var level: int = tool_levels.get(tool_id, 1)
	return Constants.TOOL_ENERGY[level]

## 체력은 0 아래로 내려가지 않는다.
func spend_energy(amount: int) -> void:
	energy = max(0, energy - amount)

# --- 도구 사용 ---

## 도구를 한 번 휘두른다. 실제로 상태가 바뀐 칸 목록을 돌려준다.
##
## 체력이 1이라도 남아 있으면 행동은 수행된다 (모자라도 거부하지 않고 0까지 깎는다).
## 체력이 0이면 아무것도 하지 못한다.
## 체력은 바뀐 칸 수와 무관하게 휘두름당 정액으로 소모된다 — 헛휘두름도 체력을 먹는다.
func use_tool(origin: Vector2i, facing: Vector2i, tool_id: String) -> Array[Vector2i]:
	if is_exhausted():
		return []

	spend_energy(tool_energy_cost(tool_id))

	var level: int = tool_levels.get(tool_id, 1)
	var cells := tool_area(origin, facing, level)
	var changed: Array[Vector2i] = []

	for cell in cells:
		if _apply_tool_to_cell(cell, tool_id):
			changed.append(cell)
	return changed

## 칸 하나에 도구를 적용한다. 실제로 바뀌었으면 true.
func _apply_tool_to_cell(cell: Vector2i, tool_id: String) -> bool:
	var tile: Dictionary = tiles[cell]
	match tool_id:
		Constants.TOOL_HOE:
			if tile["state"] != TileState.UNTILLED:
				return false
			tile["state"] = TileState.TILLED
			return true
		Constants.TOOL_CAN:
			# 안 갈린 땅에는 물을 줄 수 없다
			if tile["state"] == TileState.UNTILLED:
				return false
			if tile["watered"]:
				return false
			tile["watered"] = true
			return true
		_:
			push_error("알 수 없는 도구: %s" % tool_id)
			return false

# --- 심기 ---

## 갈린 땅에 씨앗을 심는다. 씨앗 1개를 소비한다.
## 심기는 도구를 쓰지 않으므로 체력을 소모하지 않는다.
func plant(cell: Vector2i, crop_id: String) -> bool:
	if not has_cell(cell):
		return false
	if not Constants.CROPS.has(crop_id):
		return false

	var tile: Dictionary = tiles[cell]
	if tile["state"] != TileState.TILLED:
		return false

	# 씨앗 차감이 실패하면 땅은 건드리지 않는다
	if not remove_item(Constants.seed_id_of(crop_id), 1):
		return false

	tile["state"] = TileState.PLANTED
	tile["crop_id"] = crop_id
	tile["growth"] = 0
	return true

# --- 수확 ---

func is_harvestable(cell: Vector2i) -> bool:
	var tile := get_tile(cell)
	if tile.is_empty():
		return false
	if tile["state"] != TileState.PLANTED:
		return false
	var needed: int = Constants.CROPS[tile["crop_id"]]["days"]
	return tile["growth"] >= needed

## 다 자란 작물을 수확한다. 수확한 작물 id를 돌려주며, 실패하면 빈 문자열.
##
## 수확한 칸은 TILLED로 복귀한다 — 다시 갈 필요 없이 바로 심을 수 있다.
## 수확은 도구를 쓰지 않으므로 체력을 소모하지 않는다.
func harvest(cell: Vector2i) -> String:
	if not is_harvestable(cell):
		return ""

	var tile: Dictionary = tiles[cell]
	var crop_id: String = tile["crop_id"]

	add_item(crop_id, 1)
	tile["state"] = TileState.TILLED
	tile["crop_id"] = ""
	tile["growth"] = 0
	return crop_id

# --- 시계 ---

## 하루 시작(6:00)부터 흐른 분. 시각 계산의 기준.
func minutes_since_dawn() -> int:
	var h := hour - Constants.DAY_START_HOUR
	if h < 0:
		h += 24   # 자정을 넘긴 경우 (0시, 1시)
	return h * 60 + minute

## 하루의 총 길이(분). 6:00 → 새벽 2:00 = 20시간 = 1200분.
static func day_length_minutes() -> int:
	var h := Constants.DAY_END_HOUR - Constants.DAY_START_HOUR
	if h <= 0:
		h += 24
	return h * 60

## 시간을 진행한다. 하루가 끝났으면(새벽 2:00 도달) true.
func add_minutes(amount: int) -> bool:
	var elapsed := minutes_since_dawn() + amount
	var limit := day_length_minutes()
	if elapsed > limit:
		elapsed = limit

	var total := Constants.DAY_START_HOUR * 60 + elapsed
	@warning_ignore("integer_division")
	hour = (total / 60) % 24
	minute = total % 60

	return elapsed >= limit

func time_string() -> String:
	return "%d:%02d" % [hour, minute]

# --- 하루 넘김 ---

## 침대에서 잔다 — 체력 전량 회복
func sleep() -> void:
	advance_day(false)

## 기절한다 (체력 소진 또는 새벽 2시 도달) — 체력 절반만 회복
func collapse() -> void:
	advance_day(true)

## 하루를 넘긴다. 성장 처리 후 다음 날 아침 6:00으로.
##
## 이 함수는 게임에서 유일하게 상태가 확실히 안정되는 지점이다.
## 저장은 여기서만 일어난다 (GameState가 처리).
func advance_day(collapsed: bool) -> void:
	_grow_crops()
	_dry_tiles()

	day += 1
	hour = Constants.DAY_START_HOUR
	minute = 0
	@warning_ignore("integer_division")
	energy = max_energy / 2 if collapsed else max_energy

## 물을 준 작물만 하루치 자란다. 물을 안 줬으면 멈출 뿐 죽지 않는다.
func _grow_crops() -> void:
	for cell in tiles:
		var tile: Dictionary = tiles[cell]
		if tile["state"] != TileState.PLANTED:
			continue
		if not tile["watered"]:
			continue
		var needed: int = Constants.CROPS[tile["crop_id"]]["days"]
		tile["growth"] = min(tile["growth"] + 1, needed)

## 아침이 되면 모든 칸이 마른다 — 매일 다시 물을 줘야 하는 이유
func _dry_tiles() -> void:
	for cell in tiles:
		tiles[cell]["watered"] = false

# --- 상점 ---

## 씨앗을 산다. 돈이 모자라면 아무것도 하지 않는다.
func buy_seed(crop_id: String, amount: int) -> bool:
	if amount <= 0:
		return false
	if not Constants.CROPS.has(crop_id):
		return false

	var cost: int = Constants.CROPS[crop_id]["seed_price"] * amount
	if money < cost:
		return false

	money -= cost
	add_item(Constants.seed_id_of(crop_id), amount)
	return true

## 가방의 모든 수확물을 판다. 씨앗은 팔지 않는다. 번 돈을 돌려준다.
func sell_all() -> int:
	var earned := 0
	for crop_id in Constants.CROPS:
		var count := item_count(crop_id)
		if count <= 0:
			continue
		earned += int(Constants.CROPS[crop_id]["sell_price"]) * count
		remove_item(crop_id, count)
	money += earned
	return earned

## 다음 레벨로 올리는 비용. 이미 최대 레벨이면 -1.
func upgrade_cost(tool_id: String) -> int:
	var level: int = tool_levels.get(tool_id, 1)
	if level >= Constants.MAX_TOOL_LEVEL:
		return -1
	return Constants.TOOL_UPGRADE_COST[level + 1]

func can_upgrade(tool_id: String) -> bool:
	var cost := upgrade_cost(tool_id)
	return cost >= 0 and money >= cost

## 도구를 다음 레벨로 올린다. 설계상 소요 시간 없이 즉시 적용된다.
func upgrade_tool(tool_id: String) -> bool:
	if not can_upgrade(tool_id):
		return false
	money -= upgrade_cost(tool_id)
	tool_levels[tool_id] = tool_levels.get(tool_id, 1) + 1
	return true

# --- 인벤토리 ---

func item_count(item_id: String) -> int:
	return inventory.get(item_id, 0)

func add_item(item_id: String, amount: int) -> void:
	if amount <= 0:
		return
	inventory[item_id] = item_count(item_id) + amount

## 모자라면 아무것도 빼지 않고 false를 돌려준다 (부분 차감 금지).
func remove_item(item_id: String, amount: int) -> bool:
	if amount <= 0:
		return false
	if item_count(item_id) < amount:
		return false
	inventory[item_id] = item_count(item_id) - amount
	if inventory[item_id] == 0:
		inventory.erase(item_id)
	return true

# --- 저장 / 불러오기 ---
#
# JSON은 Vector2i를 키로 쓸 수 없으므로 "x,y" 문자열로 바꿔 저장한다.
# 또한 JSON은 모든 수를 float으로 되돌리므로 불러올 때 int로 되돌려야 한다 —
# 안 그러면 growth가 1.0이 되어 비교가 조용히 어긋난다.

static func _cell_to_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]

static func _key_to_cell(key: String) -> Vector2i:
	var parts := key.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))

func to_dict() -> Dictionary:
	var tile_data := {}
	for cell in tiles:
		var tile: Dictionary = tiles[cell]
		tile_data[_cell_to_key(cell)] = {
			"state": int(tile["state"]),
			"crop_id": tile["crop_id"],
			"growth": int(tile["growth"]),
			"watered": bool(tile["watered"]),
		}

	return {
		"day": day,
		"hour": hour,
		"minute": minute,
		"money": money,
		"energy": energy,
		"max_energy": max_energy,
		"inventory": inventory.duplicate(),
		"tool_levels": tool_levels.duplicate(),
		"tiles": tile_data,
	}

func from_dict(data: Dictionary) -> void:
	day = int(data["day"])
	hour = int(data["hour"])
	minute = int(data["minute"])
	money = int(data["money"])
	energy = int(data["energy"])
	max_energy = int(data["max_energy"])

	inventory = {}
	for item_id in data["inventory"]:
		inventory[item_id] = int(data["inventory"][item_id])

	tool_levels = {}
	for tool_id in data["tool_levels"]:
		tool_levels[tool_id] = int(data["tool_levels"][tool_id])

	tiles = {}
	for key in data["tiles"]:
		var tile: Dictionary = data["tiles"][key]
		tiles[_key_to_cell(key)] = {
			"state": int(tile["state"]),
			"crop_id": tile["crop_id"],
			"growth": int(tile["growth"]),
			"watered": bool(tile["watered"]),
		}
