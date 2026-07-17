## 루트 씬. 하위 노드를 코드로 조립한다 (.tscn을 최소로 유지).
extends Node2D

func _ready() -> void:
	var farm := FarmView.new()
	farm.name = "FarmView"
	# 건물 칸이 x=-1에 있으므로 오른쪽으로 밀어 화면 안에 들어오게 한다
	farm.position = Vector2(Constants.TILE_SIZE * 2, Constants.TILE_SIZE * 2)
	add_child(farm)

	# 밭의 자식으로 붙여 좌표계를 공유한다 — 별도 변환이 필요 없다
	var player := Player.new()
	player.name = "Player"
	farm.add_child(player)

	var hud := Hud.new()
	hud.name = "Hud"
	add_child(hud)

	var shop := ShopUi.new()
	shop.name = "ShopUi"
	add_child(shop)
