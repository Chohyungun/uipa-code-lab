## GameState 통합 테스트.
##
## 여기서 검증하는 것은 규칙이 아니라 배선이다 — 파일이 실제로 써지고 읽히는가,
## 하루 넘김이 저장을 부르는가, 손상된 파일에도 게임이 켜지는가.
## 규칙 자체는 TestFarmModel이 담당한다.
##
## GameState는 Node지만 모델 준비와 파일 입출력을 _init에서 하므로
## 트리에 붙이지 않고도 이 부분들을 검증할 수 있다.
## (트리가 필요한 것은 시계를 돌리는 _process뿐이다.)
class_name TestGameState
extends RefCounted

const GameStateScript := preload("res://scripts/game_state.gd")
const SAVE_PATH := "user://save.json"

func run(t: TestLib) -> void:
	_test_save_on_day_advance(t)
	_test_load_on_boot(t)
	_test_corrupt_save(t)

func _delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

func _test_save_on_day_advance(t: TestLib) -> void:
	print("[GameState: 하루 넘김 시 저장]")
	_delete_save()

	var gs = GameStateScript.new()
	t.check("처음엔 저장 파일이 없다", FileAccess.file_exists(SAVE_PATH), false)

	gs.use_tool(Vector2i(2, 2), Vector2i(1, 0), Constants.TOOL_HOE)
	t.check("도구를 써도 아직 저장 안 됨", FileAccess.file_exists(SAVE_PATH), false)

	gs.sleep()
	t.check_true("자면 저장 파일이 생긴다", FileAccess.file_exists(SAVE_PATH))

	var data = JSON.parse_string(FileAccess.open(SAVE_PATH, FileAccess.READ).get_as_text())
	t.check_true("저장 파일이 유효한 JSON이다", typeof(data) == TYPE_DICTIONARY)
	t.check("저장된 일차가 2다", int(data["day"]), 2)
	gs.free()

func _test_load_on_boot(t: TestLib) -> void:
	print("[GameState: 부팅 시 불러오기]")
	# 앞 테스트가 남긴 저장 파일(2일차, (2,2)이 갈린 상태)을 이어받는다
	var gs = GameStateScript.new()
	t.check("저장된 일차를 이어받는다", gs.model.day, 2)
	t.check("갈아둔 밭이 남아있다",
		gs.model.get_tile(Vector2i(2, 2))["state"], FarmModel.TileState.TILLED)
	t.check("안 건드린 칸은 그대로",
		gs.model.get_tile(Vector2i(9, 7))["state"], FarmModel.TileState.UNTILLED)
	gs.free()

	_delete_save()
	var gs2 = GameStateScript.new()
	t.check("저장 파일이 없으면 1일차", gs2.model.day, 1)
	t.check("저장 파일이 없으면 돈 200", gs2.model.money, 200)
	gs2.free()

func _test_corrupt_save(t: TestLib) -> void:
	print("[GameState: 손상된 저장 파일]")
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string("이건 JSON이 아니다 {{{")
	f.close()

	# 손상된 파일 때문에 게임이 못 켜지면 안 된다 — 새 게임으로 시작해야 한다
	var gs = GameStateScript.new()
	t.check("손상된 파일이면 새 게임으로 시작한다", gs.model.day, 1)
	t.check("손상된 파일이어도 밭은 정상", gs.model.tiles.size(), 80)
	gs.free()
	_delete_save()
