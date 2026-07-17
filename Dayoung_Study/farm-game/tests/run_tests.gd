## 헤드리스 테스트 러너.
##
## 실행: godot --headless --path . --script res://tests/run_tests.gd
##
## 새 class_name 스크립트를 추가한 뒤에는 전역 클래스 등록을 위해
## 먼저 godot --headless --path . --import 를 한 번 돌려야 한다.
extends SceneTree

func _init() -> void:
	var t := TestLib.new()

	TestFarmModel.new().run(t)
	TestGameState.new().run(t)

	t.report()
	quit(1 if t.failures > 0 else 0)
