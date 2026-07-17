class_name TestFarmModel
extends RefCounted

const RIGHT := Vector2i(1, 0)
const UP := Vector2i(0, -1)

func run(t: TestLib) -> void:
	_test_new_game(t)
	_test_tiles(t)
	_test_inventory(t)
	_test_tool_area(t)
	_test_tilling(t)
	_test_planting(t)
	_test_watering(t)
	_test_day_advance(t)
	_test_harvest(t)
	_test_clock(t)
	_test_shop(t)
	_test_save_load(t)

func _test_new_game(t: TestLib) -> void:
	print("[새 게임]")
	var m := FarmModel.new()
	t.check("1일차에서 시작", m.day, 1)
	t.check("아침 6시에서 시작", m.hour, 6)
	t.check("분은 0에서 시작", m.minute, 0)
	t.check("시작 돈 200", m.money, 200)
	t.check("체력 가득", m.energy, Constants.MAX_ENERGY)
	t.check("순무 씨앗 5개 보유", m.item_count("turnip_seed"), 5)
	t.check("괭이 Lv1", m.tool_levels[Constants.TOOL_HOE], 1)
	t.check("물뿌리개 Lv1", m.tool_levels[Constants.TOOL_CAN], 1)

func _test_tiles(t: TestLib) -> void:
	print("[밭 칸]")
	var m := FarmModel.new()
	t.check("밭은 80칸", m.tiles.size(), 80)
	t.check("모든 칸이 안 갈린 상태", m.get_tile(Vector2i(0, 0))["state"], FarmModel.TileState.UNTILLED)
	t.check("처음엔 심긴 게 없다", m.get_tile(Vector2i(3, 3))["crop_id"], "")
	t.check_true("(0,0)은 밭 안", m.has_cell(Vector2i(0, 0)))
	t.check_true("(9,7)은 밭 안", m.has_cell(Vector2i(9, 7)))
	t.check("(10,0)은 밭 밖", m.has_cell(Vector2i(10, 0)), false)
	t.check("(-1,0)은 밭 밖", m.has_cell(Vector2i(-1, 0)), false)
	t.check("밭 밖 조회는 빈 사전", m.get_tile(Vector2i(99, 99)), {})

func _test_inventory(t: TestLib) -> void:
	print("[인벤토리]")
	var m := FarmModel.new()
	t.check("없는 아이템은 0개", m.item_count("pumpkin"), 0)
	m.add_item("pumpkin", 3)
	t.check("추가하면 늘어난다", m.item_count("pumpkin"), 3)
	m.add_item("pumpkin", 2)
	t.check("같은 아이템은 합쳐진다", m.item_count("pumpkin"), 5)
	t.check_true("있는 만큼 빼면 성공", m.remove_item("pumpkin", 5))
	t.check("다 빼면 0개", m.item_count("pumpkin"), 0)
	t.check("모자라면 실패한다", m.remove_item("pumpkin", 1), false)
	m.add_item("potato", 2)
	t.check("모자라면 아무것도 안 뺀다", m.remove_item("potato", 5), false)
	t.check("실패 후에도 그대로", m.item_count("potato"), 2)

func _test_tool_area(t: TestLib) -> void:
	print("[도구 범위]")
	var m := FarmModel.new()

	t.check("Lv1은 1칸", m.tool_area(Vector2i(5, 4), RIGHT, 1), [Vector2i(5, 4)])

	t.check("Lv2 우향은 x가 늘어난다",
		m.tool_area(Vector2i(5, 4), RIGHT, 2),
		[Vector2i(5, 4), Vector2i(6, 4), Vector2i(7, 4)])
	t.check("Lv2 상향은 y가 줄어든다",
		m.tool_area(Vector2i(5, 4), UP, 2),
		[Vector2i(5, 4), Vector2i(5, 3), Vector2i(5, 2)])

	t.check("Lv3은 9칸", m.tool_area(Vector2i(5, 4), RIGHT, 3).size(), 9)
	t.check_true("Lv3은 중심을 포함", m.tool_area(Vector2i(5, 4), RIGHT, 3).has(Vector2i(5, 4)))
	t.check_true("Lv3은 대각선을 포함", m.tool_area(Vector2i(5, 4), RIGHT, 3).has(Vector2i(4, 3)))
	t.check_true("Lv3은 방향과 무관",
		m.tool_area(Vector2i(5, 4), RIGHT, 3) == m.tool_area(Vector2i(5, 4), UP, 3))

	# 가장자리 — 설계 문서가 "가장 문제가 생기기 쉬운 지점"으로 지목한 부분
	t.check("Lv2가 우측 끝을 넘어가면 잘린다",
		m.tool_area(Vector2i(9, 4), RIGHT, 2), [Vector2i(9, 4)])
	t.check("Lv2가 상단 끝을 넘어가면 잘린다",
		m.tool_area(Vector2i(9, 0), UP, 2), [Vector2i(9, 0)])
	t.check("Lv3이 좌상단 모서리면 4칸만 남는다",
		m.tool_area(Vector2i(0, 0), RIGHT, 3).size(), 4)
	t.check("Lv3이 우하단 모서리면 4칸만 남는다",
		m.tool_area(Vector2i(9, 7), RIGHT, 3).size(), 4)
	t.check("origin 자체가 밭 밖이면 빈 목록",
		m.tool_area(Vector2i(-1, 0), RIGHT, 1), [])
	# 상점 칸이 (-1,0)이므로 플레이어가 상점 앞에서 휘두르는 상황이 실제로 발생한다
	t.check("Lv3 origin이 밭 밖이어도 인접한 밭 안 칸은 잡힌다",
		m.tool_area(Vector2i(-1, 0), RIGHT, 3), [Vector2i(0, 0), Vector2i(0, 1)])

func _test_tilling(t: TestLib) -> void:
	print("[밭 갈기]")
	var m := FarmModel.new()
	var changed := m.use_tool(Vector2i(2, 2), RIGHT, Constants.TOOL_HOE)
	t.check("Lv1 괭이는 1칸을 간다", changed, [Vector2i(2, 2)])
	t.check("갈린 칸은 TILLED", m.get_tile(Vector2i(2, 2))["state"], FarmModel.TileState.TILLED)
	t.check("체력 2 소모", m.energy, Constants.MAX_ENERGY - 2)
	t.check("옆 칸은 그대로", m.get_tile(Vector2i(3, 2))["state"], FarmModel.TileState.UNTILLED)

	var before := m.energy
	t.check("이미 갈린 칸은 변화 없음", m.use_tool(Vector2i(2, 2), RIGHT, Constants.TOOL_HOE), [])
	t.check("변화가 없어도 체력은 소모된다", m.energy, before - 2)

	var m2 := FarmModel.new()
	m2.tool_levels[Constants.TOOL_HOE] = 2
	t.check("Lv2 괭이는 3칸을 간다", m2.use_tool(Vector2i(2, 2), RIGHT, Constants.TOOL_HOE).size(), 3)
	t.check("Lv2 괭이 체력 4 소모", m2.energy, Constants.MAX_ENERGY - 4)
	t.check("3칸 모두 갈렸다", m2.get_tile(Vector2i(4, 2))["state"], FarmModel.TileState.TILLED)

	var m3 := FarmModel.new()
	m3.energy = 1
	t.check("체력 1로도 행동은 수행된다", m3.use_tool(Vector2i(2, 2), RIGHT, Constants.TOOL_HOE), [Vector2i(2, 2)])
	t.check("체력은 0에서 멈춘다 (음수 없음)", m3.energy, 0)

	var m4 := FarmModel.new()
	m4.energy = 0
	t.check("체력 0이면 아무것도 못 한다", m4.use_tool(Vector2i(2, 2), RIGHT, Constants.TOOL_HOE), [])
	t.check("체력 0에서 밭도 안 갈린다", m4.get_tile(Vector2i(2, 2))["state"], FarmModel.TileState.UNTILLED)

func _test_planting(t: TestLib) -> void:
	print("[심기]")
	var m := FarmModel.new()
	var cell := Vector2i(2, 2)

	t.check("안 갈린 땅에는 못 심는다", m.plant(cell, "turnip"), false)

	m.use_tool(cell, RIGHT, Constants.TOOL_HOE)
	t.check_true("갈린 땅에는 심을 수 있다", m.plant(cell, "turnip"))
	t.check("심으면 PLANTED", m.get_tile(cell)["state"], FarmModel.TileState.PLANTED)
	t.check("심은 작물이 기록된다", m.get_tile(cell)["crop_id"], "turnip")
	t.check("성장은 0에서 시작", m.get_tile(cell)["growth"], 0)
	t.check("씨앗을 1개 쓴다", m.item_count("turnip_seed"), 4)

	t.check("이미 심긴 칸에는 못 심는다", m.plant(cell, "turnip"), false)
	t.check("실패하면 씨앗이 안 준다", m.item_count("turnip_seed"), 4)

	var m2 := FarmModel.new()
	m2.use_tool(Vector2i(1, 1), RIGHT, Constants.TOOL_HOE)
	t.check("없는 씨앗은 못 심는다", m2.plant(Vector2i(1, 1), "pumpkin"), false)
	t.check("실패하면 땅은 그대로 TILLED", m2.get_tile(Vector2i(1, 1))["state"], FarmModel.TileState.TILLED)

	var m3 := FarmModel.new()
	m3.use_tool(Vector2i(1, 1), RIGHT, Constants.TOOL_HOE)
	var before := m3.energy
	m3.plant(Vector2i(1, 1), "turnip")
	t.check("심기는 체력을 안 쓴다", m3.energy, before)

func _test_watering(t: TestLib) -> void:
	print("[물주기]")
	var m := FarmModel.new()
	var cell := Vector2i(2, 2)

	var before := m.energy
	t.check("안 갈린 땅은 물이 안 준다", m.use_tool(cell, RIGHT, Constants.TOOL_CAN), [])
	t.check("헛휘두름도 체력을 쓴다", m.energy, before - 2)

	m.use_tool(cell, RIGHT, Constants.TOOL_HOE)
	t.check("갈린 땅에 물이 준다", m.use_tool(cell, RIGHT, Constants.TOOL_CAN), [cell])
	t.check_true("젖은 상태가 된다", m.get_tile(cell)["watered"])
	t.check("이미 젖었으면 변화 없음", m.use_tool(cell, RIGHT, Constants.TOOL_CAN), [])

	var m2 := FarmModel.new()
	m2.use_tool(cell, RIGHT, Constants.TOOL_HOE)
	m2.plant(cell, "turnip")
	t.check("심긴 칸에도 물이 준다", m2.use_tool(cell, RIGHT, Constants.TOOL_CAN), [cell])

	var m3 := FarmModel.new()
	m3.tool_levels[Constants.TOOL_CAN] = 2
	m3.tool_levels[Constants.TOOL_HOE] = 2
	m3.use_tool(cell, RIGHT, Constants.TOOL_HOE)
	t.check("Lv2 물뿌리개는 3칸", m3.use_tool(cell, RIGHT, Constants.TOOL_CAN).size(), 3)
	t.check("Lv2 물뿌리개 체력 4", m3.energy, Constants.MAX_ENERGY - 4 - 4)

func _test_day_advance(t: TestLib) -> void:
	print("[하루 넘김]")
	var cell := Vector2i(2, 2)
	var dry := Vector2i(4, 4)

	var m := FarmModel.new()
	m.use_tool(cell, RIGHT, Constants.TOOL_HOE)
	m.plant(cell, "turnip")
	m.use_tool(cell, RIGHT, Constants.TOOL_CAN)
	m.use_tool(dry, RIGHT, Constants.TOOL_HOE)
	m.plant(dry, "turnip")
	# dry에는 물을 주지 않는다

	m.sleep()
	t.check("2일차가 된다", m.day, 2)
	t.check("아침 6시로 리셋", m.hour, 6)
	t.check("분도 0으로 리셋", m.minute, 0)
	t.check("물 준 작물은 자란다", m.get_tile(cell)["growth"], 1)
	t.check("물 안 준 작물은 안 자란다", m.get_tile(dry)["growth"], 0)
	t.check("물 안 준 작물이 죽지는 않는다", m.get_tile(dry)["state"], FarmModel.TileState.PLANTED)
	t.check("젖은 상태는 아침에 마른다", m.get_tile(cell)["watered"], false)
	t.check("자고 나면 체력 전량", m.energy, Constants.MAX_ENERGY)

	var m2 := FarmModel.new()
	m2.energy = 0
	m2.collapse()
	t.check("기절해도 다음 날이 된다", m2.day, 2)
	t.check("기절하면 체력 절반", m2.energy, Constants.MAX_ENERGY / 2)

	var m3 := FarmModel.new()
	m3.use_tool(cell, RIGHT, Constants.TOOL_HOE)
	m3.plant(cell, "turnip")
	for i in 5:
		m3.use_tool(cell, RIGHT, Constants.TOOL_CAN)
		m3.sleep()
	t.check("성장은 필요 일수를 넘지 않는다", m3.get_tile(cell)["growth"], 3)

	var m4 := FarmModel.new()
	t.check("시작할 땐 안 지쳤다", m4.is_exhausted(), false)
	m4.energy = 0
	t.check_true("체력 0이면 지친 상태", m4.is_exhausted())

func _test_harvest(t: TestLib) -> void:
	print("[수확]")
	var cell := Vector2i(2, 2)

	var m := FarmModel.new()
	m.use_tool(cell, RIGHT, Constants.TOOL_HOE)
	m.plant(cell, "turnip")

	t.check("덜 자라면 수확 불가", m.is_harvestable(cell), false)
	t.check("덜 자란 걸 수확하면 빈 문자열", m.harvest(cell), "")
	t.check("실패해도 작물은 그대로", m.get_tile(cell)["state"], FarmModel.TileState.PLANTED)

	for i in 3:
		m.use_tool(cell, RIGHT, Constants.TOOL_CAN)
		m.sleep()

	t.check_true("다 자라면 수확 가능", m.is_harvestable(cell))
	t.check("수확하면 작물 id를 돌려준다", m.harvest(cell), "turnip")
	t.check("수확물이 인벤토리에 들어간다", m.item_count("turnip"), 1)
	t.check("수확 후 TILLED로 복귀", m.get_tile(cell)["state"], FarmModel.TileState.TILLED)
	t.check("수확 후 작물 정보가 지워진다", m.get_tile(cell)["crop_id"], "")
	t.check("수확 후 성장도 초기화", m.get_tile(cell)["growth"], 0)
	t.check("같은 칸을 두 번 수확할 수 없다", m.harvest(cell), "")
	t.check_true("수확한 칸에 바로 심을 수 있다", m.plant(cell, "turnip"))

	var m2 := FarmModel.new()
	m2.use_tool(cell, RIGHT, Constants.TOOL_HOE)
	m2.plant(cell, "turnip")
	for i in 3:
		m2.use_tool(cell, RIGHT, Constants.TOOL_CAN)
		m2.sleep()
	var before := m2.energy
	m2.harvest(cell)
	t.check("수확은 체력을 안 쓴다", m2.energy, before)

	t.check("빈 칸은 수확할 게 없다", m2.harvest(Vector2i(7, 7)), "")
	t.check("밭 밖은 수확할 게 없다", m2.harvest(Vector2i(-1, 0)), "")

func _test_clock(t: TestLib) -> void:
	print("[시계]")
	var m := FarmModel.new()
	t.check("시작 시각 표시", m.time_string(), "6:00")
	t.check("30분 지나도 하루는 안 끝난다", m.add_minutes(30), false)
	t.check("30분 뒤", m.time_string(), "6:30")
	m.add_minutes(30)
	t.check("60분이면 시가 넘어간다", m.time_string(), "7:00")
	t.check("시가 정확히 7", m.hour, 7)
	t.check("분이 0으로 리셋", m.minute, 0)

	# 6:00 → 새벽 2:00 은 20시간 = 1200분
	var m2 := FarmModel.new()
	t.check("1199분까지는 안 끝난다", m2.add_minutes(1199), false)
	t.check("1:59 표시", m2.time_string(), "1:59")

	var m3 := FarmModel.new()
	t.check_true("1200분이면 하루가 끝난다", m3.add_minutes(1200))

	var m4 := FarmModel.new()
	t.check_true("넘겨도 하루가 끝난다", m4.add_minutes(2000))
	t.check("넘겨도 2:00에서 멈춘다", m4.time_string(), "2:00")

	var m5 := FarmModel.new()
	m5.add_minutes(18 * 60)   # 6:00 + 18시간 = 24:00 → 0:00
	t.check("자정은 0시로 표시", m5.time_string(), "0:00")
	m5.add_minutes(60)
	t.check("자정 이후 1시", m5.time_string(), "1:00")

func _test_shop(t: TestLib) -> void:
	print("[상점]")
	var m := FarmModel.new()
	t.check_true("씨앗을 살 수 있다", m.buy_seed("turnip", 2))
	t.check("돈이 줄어든다", m.money, 200 - 40)
	t.check("씨앗이 늘어난다", m.item_count("turnip_seed"), 7)

	t.check("돈이 모자라면 못 산다", m.buy_seed("pumpkin", 10), false)
	t.check("실패하면 돈이 그대로", m.money, 200 - 40)
	t.check("실패하면 씨앗도 그대로", m.item_count("pumpkin_seed"), 0)
	t.check("없는 작물은 못 산다", m.buy_seed("banana", 1), false)
	t.check("0개는 못 산다", m.buy_seed("turnip", 0), false)

	var m2 := FarmModel.new()
	m2.add_item("turnip", 3)
	m2.add_item("pumpkin", 1)
	t.check("판 금액을 돌려준다", m2.sell_all(), 3 * 45 + 280)
	t.check("돈이 늘어난다", m2.money, 200 + 3 * 45 + 280)
	t.check("판 작물은 가방에서 사라진다", m2.item_count("turnip"), 0)
	t.check("씨앗은 팔리지 않는다", m2.item_count("turnip_seed"), 5)

	var m3 := FarmModel.new()
	t.check("팔 게 없으면 0원", m3.sell_all(), 0)
	t.check("팔 게 없으면 돈이 그대로", m3.money, 200)

	var m4 := FarmModel.new()
	t.check("Lv2 비용은 500", m4.upgrade_cost(Constants.TOOL_HOE), 500)
	t.check("돈이 모자라면 업그레이드 불가", m4.can_upgrade(Constants.TOOL_HOE), false)
	t.check("불가능하면 실패한다", m4.upgrade_tool(Constants.TOOL_HOE), false)
	t.check("실패하면 레벨 그대로", m4.tool_levels[Constants.TOOL_HOE], 1)

	m4.money = 500
	t.check_true("돈이 있으면 가능", m4.can_upgrade(Constants.TOOL_HOE))
	t.check_true("업그레이드 성공", m4.upgrade_tool(Constants.TOOL_HOE))
	t.check("레벨이 오른다", m4.tool_levels[Constants.TOOL_HOE], 2)
	t.check("돈이 빠진다", m4.money, 0)
	t.check("다른 도구는 안 오른다", m4.tool_levels[Constants.TOOL_CAN], 1)
	t.check("Lv3 비용은 2000", m4.upgrade_cost(Constants.TOOL_HOE), 2000)

	m4.money = 2000
	m4.upgrade_tool(Constants.TOOL_HOE)
	t.check("Lv3까지 오른다", m4.tool_levels[Constants.TOOL_HOE], 3)
	t.check("최대 레벨이면 비용 -1", m4.upgrade_cost(Constants.TOOL_HOE), -1)
	t.check("최대 레벨이면 업그레이드 불가", m4.can_upgrade(Constants.TOOL_HOE), false)
	m4.money = 99999
	t.check("돈이 많아도 최대를 넘지 못한다", m4.upgrade_tool(Constants.TOOL_HOE), false)
	t.check("최대에서 레벨이 안 변한다", m4.tool_levels[Constants.TOOL_HOE], 3)

	# 업그레이드하면 체력 효율이 오른다 — 성장 루프의 핵심
	var m5 := FarmModel.new()
	t.check("Lv1 괭이 체력 2", m5.tool_energy_cost(Constants.TOOL_HOE), 2)
	m5.money = 500
	m5.upgrade_tool(Constants.TOOL_HOE)
	t.check("Lv2 괭이 체력 4 (3칸 → 칸당 1.33)", m5.tool_energy_cost(Constants.TOOL_HOE), 4)
	t.check("Lv2 괭이는 3칸을 간다", m5.use_tool(Vector2i(2, 2), RIGHT, Constants.TOOL_HOE).size(), 3)

func _test_save_load(t: TestLib) -> void:
	print("[저장/불러오기]")
	var m := FarmModel.new()
	m.use_tool(Vector2i(2, 2), RIGHT, Constants.TOOL_HOE)
	m.plant(Vector2i(2, 2), "turnip")
	m.use_tool(Vector2i(2, 2), RIGHT, Constants.TOOL_CAN)
	m.use_tool(Vector2i(5, 5), RIGHT, Constants.TOOL_HOE)
	m.money = 1234
	m.tool_levels[Constants.TOOL_CAN] = 2
	m.add_item("pumpkin", 3)
	m.add_minutes(150)
	m.day = 7
	m.energy = 21

	# JSON 왕복을 거친다 — Vector2i 키가 살아남는지가 핵심
	var json := JSON.stringify(m.to_dict())
	var parsed = JSON.parse_string(json)
	t.check_true("JSON으로 직렬화된다", parsed != null)

	var loaded := FarmModel.new()
	loaded.from_dict(parsed)

	t.check("일차가 복원된다", loaded.day, 7)
	t.check("시각이 복원된다", loaded.time_string(), m.time_string())
	t.check("돈이 복원된다", loaded.money, 1234)
	t.check("체력이 복원된다", loaded.energy, 21)
	t.check("최대 체력이 복원된다", loaded.max_energy, m.max_energy)
	t.check("도구 레벨이 복원된다", loaded.tool_levels[Constants.TOOL_CAN], 2)
	t.check("괭이 레벨도 복원된다", loaded.tool_levels[Constants.TOOL_HOE], 1)
	t.check("인벤토리가 복원된다", loaded.item_count("pumpkin"), 3)
	t.check("씨앗도 복원된다", loaded.item_count("turnip_seed"), m.item_count("turnip_seed"))

	t.check("밭 칸 수가 같다", loaded.tiles.size(), 80)
	t.check("심긴 칸이 복원된다", loaded.get_tile(Vector2i(2, 2))["state"], FarmModel.TileState.PLANTED)
	t.check("작물 id가 복원된다", loaded.get_tile(Vector2i(2, 2))["crop_id"], "turnip")
	t.check_true("젖은 상태가 복원된다", loaded.get_tile(Vector2i(2, 2))["watered"])
	t.check("갈린 칸이 복원된다", loaded.get_tile(Vector2i(5, 5))["state"], FarmModel.TileState.TILLED)
	t.check("안 건드린 칸도 복원된다", loaded.get_tile(Vector2i(9, 7))["state"], FarmModel.TileState.UNTILLED)

	# 불러온 뒤에도 게임이 굴러가는지 — JSON은 모든 수를 float으로 되돌리므로
	# growth가 1.0이 되면 조용히 이상하게 동작한다
	loaded.use_tool(Vector2i(2, 2), RIGHT, Constants.TOOL_CAN)
	loaded.sleep()
	t.check("불러온 뒤에도 작물이 자란다", loaded.get_tile(Vector2i(2, 2))["growth"], 1)
	t.check("불러온 뒤에도 하루가 넘어간다", loaded.day, 8)
