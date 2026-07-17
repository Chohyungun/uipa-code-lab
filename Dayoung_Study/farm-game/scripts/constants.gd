## 모든 밸런스 수치가 여기에만 존재한다.
## 다른 파일에 숫자를 직접 쓰지 않는다 — 조정이 이 파일 하나 고치는 일이 되도록.
class_name Constants
extends RefCounted

# --- 밭 ---
const FARM_WIDTH := 10
const FARM_HEIGHT := 8

# --- 시간 ---
const DAY_START_HOUR := 6      # 아침 6:00 시작
const DAY_END_HOUR := 2        # 새벽 2:00 강제 종료
const GAME_MINUTES_PER_REAL_SECOND := 1.0   # 현실 10초 = 게임 10분

# --- 체력 ---
const MAX_ENERGY := 60

# --- 시작 상태 ---
const START_MONEY := 200
const START_SEEDS := {"turnip_seed": 5}

# --- 도구 ---
const TOOL_HOE := "hoe"
const TOOL_CAN := "can"
const MAX_TOOL_LEVEL := 3

## 도구 레벨 → 휘두름 1회당 체력 소모.
## 범위 안 칸 수와 무관한 정액이므로, 레벨이 오르면 칸당 효율이 올라간다.
const TOOL_ENERGY := {1: 2, 2: 4, 3: 9}

## 도구 레벨 → 그 레벨로 올리는 데 드는 비용
const TOOL_UPGRADE_COST := {2: 500, 3: 2000}

# --- 작물 ---
const CROPS := {
	"turnip": {
		"name": "순무",
		"days": 3,
		"seed_price": 20,
		"sell_price": 45,
		"color": Color(0.85, 0.9, 0.55),
	},
	"potato": {
		"name": "감자",
		"days": 5,
		"seed_price": 50,
		"sell_price": 105,
		"color": Color(0.75, 0.55, 0.3),
	},
	"pumpkin": {
		"name": "호박",
		"days": 8,
		"seed_price": 120,
		"sell_price": 280,
		"color": Color(0.95, 0.5, 0.1),
	},
}

# --- 화면 (색 도형 플레이스홀더) ---
const TILE_SIZE := 48
const COLOR_UNTILLED := Color(0.35, 0.6, 0.3)   # 풀밭
const COLOR_TILLED := Color(0.45, 0.32, 0.2)    # 갈린 흙
const COLOR_WATERED := Color(0.3, 0.2, 0.12)    # 젖은 흙
const COLOR_GRID := Color(0, 0, 0, 0.15)
const COLOR_PLAYER := Color(0.2, 0.4, 0.9)
const COLOR_FACING := Color(1, 1, 1, 0.7)
const COLOR_SHOP := Color(0.85, 0.75, 0.2)
const COLOR_BIN := Color(0.6, 0.4, 0.7)
const COLOR_BED := Color(0.9, 0.9, 0.95)

# --- 건물 위치 (밭 격자 밖, 좌측 바깥 열) ---
const SHOP_CELL := Vector2i(-1, 0)
const BIN_CELL := Vector2i(-1, 1)
const BED_CELL := Vector2i(-1, 2)

## 작물 id로부터 씨앗 아이템 id를 만든다.
## 인벤토리가 씨앗과 수확물을 같은 사전에 담으므로 구분이 필요하다.
static func seed_id_of(crop_id: String) -> String:
	return crop_id + "_seed"

## 씨앗 아이템 id로부터 작물 id를 되돌린다. 씨앗이 아니면 빈 문자열.
static func crop_id_of_seed(seed_id: String) -> String:
	if seed_id.ends_with("_seed"):
		return seed_id.trim_suffix("_seed")
	return ""
