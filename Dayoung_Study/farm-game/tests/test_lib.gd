class_name TestLib
extends RefCounted

var total := 0
var failures := 0

func check(label: String, actual, expected) -> void:
	total += 1
	if actual == expected:
		print("  PASS  ", label)
	else:
		failures += 1
		print("  FAIL  ", label, " — 기대: ", expected, ", 실제: ", actual)

func check_true(label: String, actual: bool) -> void:
	check(label, actual, true)

func report() -> void:
	print("")
	if failures > 0:
		print("실패 ", failures, " / 전체 ", total)
	else:
		print("전체 통과 ", total, " 개")
