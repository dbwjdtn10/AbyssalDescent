## Static fallback data used when the AI server is unreachable.
##
## All game-facing strings (item names, NPC dialogue, quest descriptions, etc.)
## are written in Korean to match the dark-fantasy theme of Abyssal Descent.
class_name AIFallback
extends Node

# ── Dungeon ──────────────────────────────────────────────────────────────────

## Return a pre-built dungeon layout for the given floor.
func get_fallback_dungeon(floor_num: int) -> Dictionary:
	# Cycle through a handful of hand-crafted templates.
	var templates: Array[Dictionary] = _get_dungeon_templates()
	var idx: int = (floor_num - 1) % templates.size()
	var template: Dictionary = templates[idx].duplicate(true)
	template["floor_number"] = floor_num
	template["fallback"] = true

	# Scale enemy levels based on how many times templates have cycled.
	# Each full cycle adds a gentle linear boost (+3 per cycle).
	var cycles: int = (floor_num - 1) / templates.size()
	var cycle_bonus: int = cycles * 3
	var floor_bonus: int = maxi(0, floor_num - (idx + 1))
	var level_bonus: int = cycle_bonus + floor_bonus
	if level_bonus > 0:
		_scale_enemy_levels(template, level_bonus)

	return template



## Increase enemy levels for repeated template cycles on higher floors.
func _scale_enemy_levels(template: Dictionary, bonus: int) -> void:
	for room: Variant in template.get("rooms", []):
		if not room is Dictionary:
			continue
		for enemy: Variant in (room as Dictionary).get("enemies", []):
			if not enemy is Dictionary:
				continue
			var d: Dictionary = enemy as Dictionary
			d["level"] = d.get("level", 1) + bonus


func _get_dungeon_templates() -> Array[Dictionary]:
	return [
		{
			"name": "잊혀진 지하묘지",
			"description": "축축한 벽에서 핏빛 이끼가 자라는 지하묘지. 먼 곳에서 쇠사슬 끌리는 소리가 울려 퍼진다.",
			"rooms": [
				{
					"id": "entrance",
					"type": "entrance",
					"name": "균열의 입구",
					"connections": ["hallway_1"],
					"enemies": [],
				},
				{
					"id": "hallway_1",
					"type": "corridor",
					"name": "피의 복도",
					"connections": ["entrance", "combat_1", "treasure_1"],
					"enemies": [
						{"type": "skeleton", "level": 2, "name": "부서진 해골병"},
					],
				},
				{
					"id": "combat_1",
					"type": "combat",
					"name": "학살의 방",
					"connections": ["hallway_1", "rest_1"],
					"enemies": [
						{"type": "skeleton", "level": 2, "name": "해골 전사"},
						{"type": "ghost", "level": 2, "name": "떠도는 원혼"},
					],
				},
				{
					"id": "treasure_1",
					"type": "treasure",
					"name": "잊혀진 보물고",
					"connections": ["hallway_1"],
					"enemies": [],
					"loot": [
						{"name": "녹슨 단검", "type": "weapon", "rarity": "common", "stats": {"attack": 3}},
						{"name": "흐린 치유 물약", "type": "consumable", "rarity": "common", "stats": {"heal": 25}},
					],
				},
				{
					"id": "rest_1",
					"type": "rest",
					"name": "잊혀진 제단",
					"connections": ["combat_1", "boss_room"],
					"enemies": [],
				},
				{
					"id": "boss_room",
					"type": "boss",
					"name": "묘지기의 안식처",
					"connections": ["rest_1"],
					"enemies": [
						{"type": "boss", "level": 3, "name": "묘지기 그림자"},
					],
				},
			],
		},
		{
			"name": "심연의 회랑",
			"description": "끝없이 이어지는 어둠의 회랑. 벽에 새겨진 고대 문양이 희미하게 빛난다.",
			"rooms": [
				{
					"id": "entrance",
					"type": "entrance",
					"name": "심연의 문",
					"connections": ["hub"],
					"enemies": [],
				},
				{
					"id": "hub",
					"type": "corridor",
					"name": "갈림길",
					"connections": ["entrance", "left_combat", "right_combat"],
					"enemies": [
						{"type": "slime", "level": 3, "name": "독액 슬라임"},
					],
				},
				{
					"id": "left_combat",
					"type": "combat",
					"name": "독기의 방",
					"connections": ["hub", "armory", "merge"],
					"enemies": [
						{"type": "slime", "level": 4, "name": "부식 슬라임"},
						{"type": "slime", "level": 3, "name": "독액 슬라임"},
					],
				},
				{
					"id": "armory",
					"type": "treasure",
					"name": "무너진 무기고",
					"connections": ["left_combat"],
					"enemies": [],
					"loot": [
						{"name": "뼈 도끼", "type": "weapon", "rarity": "uncommon", "stats": {"attack": 7}},
					],
				},
				{
					"id": "right_combat",
					"type": "combat",
					"name": "어둠의 감옥",
					"connections": ["hub", "merge"],
					"enemies": [
						{"type": "undead", "level": 4, "name": "저주받은 죄수"},
						{"type": "undead", "level": 3, "name": "갇힌 망자"},
					],
				},
				{
					"id": "merge",
					"type": "rest",
					"name": "잊혀진 제단",
					"connections": ["left_combat", "right_combat", "boss_room"],
					"enemies": [],
				},
				{
					"id": "boss_room",
					"type": "boss",
					"name": "심연의 군주의 옥좌",
					"connections": ["merge"],
					"enemies": [
						{"type": "boss", "level": 4, "name": "심연의 군주 아자렐"},
					],
				},
			],
		},
		{
			"name": "타락한 성소",
			"description": "한때 신성했던 장소가 어둠에 물들었다. 부서진 성상 사이로 검은 안개가 흐른다.",
			"rooms": [
				{
					"id": "entrance",
					"type": "entrance",
					"name": "무너진 정문",
					"connections": ["nave"],
					"enemies": [],
				},
				{
					"id": "nave",
					"type": "corridor",
					"name": "타락한 본당",
					"connections": ["entrance", "side_chapel", "crypt"],
					"enemies": [
						{"type": "cultist", "level": 3, "name": "타락한 수도사"},
					],
				},
				{
					"id": "side_chapel",
					"type": "treasure",
					"name": "약탈된 예배당",
					"connections": ["nave"],
					"enemies": [],
					"loot": [
						{"name": "빛바랜 기도서", "type": "consumable", "rarity": "uncommon", "stats": {"heal": 30}},
					],
				},
				{
					"id": "crypt",
					"type": "combat",
					"name": "성직자의 지하묘",
					"connections": ["nave", "boss_room"],
					"enemies": [
						{"type": "undead", "level": 4, "name": "부활한 사제"},
						{"type": "ghost", "level": 3, "name": "탄식하는 영혼"},
					],
				},
				{
					"id": "boss_room",
					"type": "boss",
					"name": "대사제의 제단",
					"connections": ["crypt"],
					"enemies": [
						{"type": "boss", "level": 6, "name": "타락 대사제 벨리안"},
					],
				},
			],
		},
		{
			"name": "저주받은 광산",
			"description": "버려진 광산 깊은 곳에서 알 수 없는 기운이 뿜어져 나온다. 광부들의 유해가 곳곳에 흩어져 있다.",
			"rooms": [
				{
					"id": "entrance",
					"type": "entrance",
					"name": "광산 입구",
					"connections": ["left_shaft", "right_shaft"],
					"enemies": [],
				},
				{
					"id": "left_shaft",
					"type": "corridor",
					"name": "붕괴된 갱도",
					"connections": ["entrance", "combat_1"],
					"enemies": [
						{"type": "golem", "level": 4, "name": "돌 골렘 파편"},
					],
				},
				{
					"id": "right_shaft",
					"type": "corridor",
					"name": "깊은 수갱",
					"connections": ["entrance", "vein", "combat_2"],
					"enemies": [
						{"type": "bat", "level": 4, "name": "거대 박쥐"},
					],
				},
				{
					"id": "vein",
					"type": "treasure",
					"name": "수정 광맥",
					"connections": ["right_shaft"],
					"enemies": [],
					"loot": [
						{"name": "수정 방패", "type": "armor", "rarity": "uncommon", "stats": {"defense": 6}},
						{"name": "광부의 치유약", "type": "consumable", "rarity": "common", "stats": {"heal": 30}},
					],
				},
				{
					"id": "combat_1",
					"type": "combat",
					"name": "무너진 채굴장",
					"connections": ["left_shaft", "rest"],
					"enemies": [
						{"type": "golem", "level": 5, "name": "흑철 골렘"},
					],
				},
				{
					"id": "combat_2",
					"type": "combat",
					"name": "저주받은 용광로",
					"connections": ["right_shaft", "rest"],
					"enemies": [
						{"type": "elemental", "level": 5, "name": "용암 정령"},
					],
				},
				{
					"id": "rest",
					"type": "rest",
					"name": "오래된 작업실",
					"connections": ["combat_1", "combat_2", "boss_room"],
					"enemies": [],
				},
				{
					"id": "boss_room",
					"type": "boss",
					"name": "광산왕의 심장부",
					"connections": ["rest"],
					"enemies": [
						{"type": "boss", "level": 8, "name": "광산왕 크라그"},
					],
				},
			],
		},
		{
			"name": "영혼의 감옥",
			"description": "수천의 영혼이 갇혀 울부짖는 차원의 감옥. 벽 자체가 고통으로 이루어져 있다.",
			"rooms": [
				{
					"id": "entrance",
					"type": "entrance",
					"name": "감옥 정문",
					"connections": ["corridor"],
					"enemies": [],
				},
				{
					"id": "corridor",
					"type": "corridor",
					"name": "비명의 복도",
					"connections": ["entrance", "cell_block"],
					"enemies": [
						{"type": "ghost", "level": 6, "name": "감시자 유령"},
					],
				},
				{
					"id": "cell_block",
					"type": "combat",
					"name": "독방 구역",
					"connections": ["corridor", "torture", "supply"],
					"enemies": [
						{"type": "undead", "level": 7, "name": "탈옥한 망자"},
						{"type": "ghost", "level": 6, "name": "원한의 영혼"},
					],
				},
				{
					"id": "supply",
					"type": "treasure",
					"name": "간수의 보급고",
					"connections": ["cell_block"],
					"enemies": [],
					"loot": [
						{"name": "간수의 열쇠검", "type": "weapon", "rarity": "rare", "stats": {"attack": 16}},
						{"name": "정화의 성수", "type": "consumable", "rarity": "uncommon", "stats": {"heal": 60}},
					],
				},
				{
					"id": "torture",
					"type": "combat",
					"name": "고문실",
					"connections": ["cell_block", "rest"],
					"enemies": [
						{"type": "demon", "level": 7, "name": "고문관 악마"},
					],
				},
				{
					"id": "rest",
					"type": "rest",
					"name": "은신처",
					"connections": ["torture", "boss_room"],
					"enemies": [],
				},
				{
					"id": "boss_room",
					"type": "boss",
					"name": "감옥장의 처형장",
					"connections": ["rest"],
					"enemies": [
						{"type": "boss", "level": 10, "name": "감옥장 데스모드"},
					],
				},
			],
		},
		{
			"name": "용암의 심장",
			"description": "대지의 핏줄이 흐르는 곳. 녹아내린 바위 사이로 고대의 화염이 춤춘다.",
			"rooms": [
				{
					"id": "entrance",
					"type": "entrance",
					"name": "화산 균열",
					"connections": ["bridge"],
					"enemies": [],
				},
				{
					"id": "bridge",
					"type": "corridor",
					"name": "용암 다리",
					"connections": ["entrance", "forge"],
					"enemies": [
						{"type": "elemental", "level": 8, "name": "화염 정령"},
					],
				},
				{
					"id": "forge",
					"type": "combat",
					"name": "고대 대장간",
					"connections": ["bridge", "treasury", "caldera"],
					"enemies": [
						{"type": "golem", "level": 9, "name": "흑요석 골렘"},
						{"type": "elemental", "level": 8, "name": "마그마 정령"},
					],
				},
				{
					"id": "treasury",
					"type": "treasure",
					"name": "용의 보물고",
					"connections": ["forge"],
					"enemies": [],
					"loot": [
						{"name": "화룡의 비늘갑", "type": "armor", "rarity": "rare", "stats": {"defense": 20}},
						{"name": "불꽃의 정수", "type": "consumable", "rarity": "rare", "stats": {"heal": 80}},
					],
				},
				{
					"id": "caldera",
					"type": "combat",
					"name": "끓는 분화구",
					"connections": ["forge", "rest"],
					"enemies": [
						{"type": "dragon", "level": 9, "name": "화산 드레이크"},
					],
				},
				{
					"id": "rest",
					"type": "rest",
					"name": "냉각된 동굴",
					"connections": ["caldera", "boss_room"],
					"enemies": [],
				},
				{
					"id": "boss_room",
					"type": "boss",
					"name": "화염왕의 옥좌",
					"connections": ["rest"],
					"enemies": [
						{"type": "boss", "level": 12, "name": "화염왕 이그니스"},
					],
				},
			],
		},
		{
			"name": "얼어붙은 심연",
			"description": "영원한 겨울이 지배하는 지하 빙동. 숨결조차 얼어붙는 극한의 냉기가 만연한다.",
			"rooms": [
				{
					"id": "entrance",
					"type": "entrance",
					"name": "빙결의 문",
					"connections": ["frost_hall"],
					"enemies": [],
				},
				{
					"id": "frost_hall",
					"type": "corridor",
					"name": "서리 복도",
					"connections": ["entrance", "frozen_lab", "ice_cave"],
					"enemies": [
						{"type": "elemental", "level": 10, "name": "서리 정령"},
					],
				},
				{
					"id": "frozen_lab",
					"type": "treasure",
					"name": "냉동된 연구실",
					"connections": ["frost_hall"],
					"enemies": [],
					"loot": [
						{"name": "동결의 지팡이", "type": "weapon", "rarity": "rare", "stats": {"attack": 24}},
						{"name": "한빙의 영약", "type": "consumable", "rarity": "uncommon", "stats": {"heal": 90}},
					],
				},
				{
					"id": "ice_cave",
					"type": "combat",
					"name": "빙정석 동굴",
					"connections": ["frost_hall", "frozen_antechamber"],
					"enemies": [
						{"type": "golem", "level": 11, "name": "빙결 골렘"},
						{"type": "elemental", "level": 10, "name": "얼음 정령"},
					],
				},
				{
					"id": "frozen_antechamber",
					"type": "combat",
					"name": "동결 회랑",
					"connections": ["ice_cave", "rest"],
					"enemies": [
						{"type": "undead", "level": 11, "name": "냉기 망자"},
						{"type": "ghost", "level": 10, "name": "빙혼"},
					],
				},
				{
					"id": "rest",
					"type": "rest",
					"name": "따뜻한 샘",
					"connections": ["frozen_antechamber", "boss_room"],
					"enemies": [],
				},
				{
					"id": "boss_room",
					"type": "boss",
					"name": "빙왕의 옥좌",
					"connections": ["rest"],
					"enemies": [
						{"type": "boss", "level": 14, "name": "빙왕 프로스트하트"},
					],
				},
			],
		},
		{
			"name": "심연의 도서관",
			"description": "금지된 지식이 잠든 곳. 책장마다 저주가 서려 있고, 지식을 탐하는 자들의 영혼이 배회한다.",
			"rooms": [
				{
					"id": "entrance",
					"type": "entrance",
					"name": "도서관 정문",
					"connections": ["main_hall"],
					"enemies": [],
				},
				{
					"id": "main_hall",
					"type": "corridor",
					"name": "대열람실",
					"connections": ["entrance", "forbidden_section", "combat_1"],
					"enemies": [
						{"type": "ghost", "level": 12, "name": "방황하는 학자"},
					],
				},
				{
					"id": "forbidden_section",
					"type": "treasure",
					"name": "금서 구역",
					"connections": ["main_hall"],
					"enemies": [],
					"loot": [
						{"name": "금단의 마도서", "type": "accessory", "rarity": "rare", "stats": {"attack": 12, "defense": 8}},
						{"name": "지혜의 영약", "type": "consumable", "rarity": "rare", "stats": {"heal": 100}},
					],
				},
				{
					"id": "combat_1",
					"type": "combat",
					"name": "저주받은 서고",
					"connections": ["main_hall", "combat_2"],
					"enemies": [
						{"type": "cultist", "level": 13, "name": "타락한 사서"},
						{"type": "ghost", "level": 12, "name": "지식에 미친 영혼"},
					],
				},
				{
					"id": "combat_2",
					"type": "combat",
					"name": "의식의 방",
					"connections": ["combat_1", "rest"],
					"enemies": [
						{"type": "demon", "level": 13, "name": "소환된 악마"},
						{"type": "cultist", "level": 13, "name": "광기의 학자"},
					],
				},
				{
					"id": "rest",
					"type": "rest",
					"name": "숨겨진 열람석",
					"connections": ["combat_2", "boss_room"],
					"enemies": [],
				},
				{
					"id": "boss_room",
					"type": "boss",
					"name": "대현자의 서재",
					"connections": ["rest"],
					"enemies": [
						{"type": "boss", "level": 16, "name": "대현자 말라키"},
					],
				},
			],
		},
	]

# ── NPC Responses ────────────────────────────────────────────────────────────

## Return a generic NPC dialogue response for the given npc_id.
func get_fallback_npc_response(npc_id: String) -> Dictionary:
	var responses: Dictionary = _get_npc_responses()
	if responses.has(npc_id):
		return responses[npc_id].duplicate(true)

	# Default response for unknown NPCs.
	return {
		"npc_id": npc_id,
		"message": "......어둠이 짙어지고 있군. 조심하게, 이곳에서 오래 머물면 정신이 잠식당하네.",
		"emotion": "neutral",
		"options": [
			{"text": "더 알려주세요.", "id": "ask_more"},
			{"text": "떠나겠습니다.", "id": "leave"},
		],
		"fallback": true,
	}


func _get_npc_responses() -> Dictionary:
	return {
		"merchant": {
			"npc_id": "merchant",
			"message": "어서 오게, 용감한 모험자여. 이 심연에서 살아남으려면 좋은 장비가 필요하지 않겠나? 자네에게 쓸 만한 물건이 있을지도 모르네.",
			"emotion": "friendly",
			"options": [
				{"text": "물건을 보여주세요.", "id": "show_wares"},
				{"text": "이곳에 대해 알려주세요.", "id": "ask_info"},
				{"text": "안녕히 계세요.", "id": "leave"},
			],
			"fallback": true,
		},
		"sage": {
			"npc_id": "sage",
			"message": "오... 또 한 명의 어리석은 영혼이 심연에 발을 들였군. 이곳의 진실을 알고 싶은가? 그 대가는 값비싸다네.",
			"emotion": "mysterious",
			"options": [
				{"text": "진실을 알려주세요.", "id": "ask_truth"},
				{"text": "아래층에 무엇이 있나요?", "id": "ask_below"},
				{"text": "물러나겠습니다.", "id": "leave"},
			],
			"fallback": true,
		},
		"blacksmith": {
			"npc_id": "blacksmith",
			"message": "흠... 자네 장비가 형편없군. 이 심연의 괴물들과 싸우려면 더 나은 무기가 필요할 것이야. 내가 도와주지.",
			"emotion": "gruff",
			"options": [
				{"text": "무기를 강화해주세요.", "id": "upgrade_weapon"},
				{"text": "방어구를 수리해주세요.", "id": "repair_armor"},
				{"text": "다음에 오겠습니다.", "id": "leave"},
			],
			"fallback": true,
		},
		"ghost_npc": {
			"npc_id": "ghost_npc",
			"message": "나는... 기억이... 이 층에서 죽었지... 조심해... 앞에... 함정이...",
			"emotion": "sorrowful",
			"options": [
				{"text": "무슨 함정인가요?", "id": "ask_trap"},
				{"text": "성불하세요.", "id": "bless"},
				{"text": "(조용히 떠난다)", "id": "leave"},
			],
			"fallback": true,
		},
	}

# ── Items ────────────────────────────────────────────────────────────────────

## Return a fallback item definition based on rarity.
func get_fallback_item(rarity: String) -> Dictionary:
	var items_by_rarity: Dictionary = _get_items_by_rarity()
	if items_by_rarity.has(rarity):
		var pool: Array = items_by_rarity[rarity]
		# Pick a pseudo-random entry from the pool.
		var idx: int = randi() % pool.size()
		var item: Dictionary = pool[idx].duplicate(true)
		item["fallback"] = true
		return item

	# Unknown rarity – return a basic common item.
	return {
		"name": "낡은 천 조각",
		"type": "material",
		"rarity": "common",
		"description": "특별할 것 없는 낡은 천 조각이다.",
		"stats": {},
		"fallback": true,
	}


func _get_items_by_rarity() -> Dictionary:
	return {
		"common": [
			{
				"name": "녹슨 단검",
				"type": "weapon",
				"rarity": "common",
				"description": "세월의 흔적이 짙은 낡은 단검. 그래도 쥐어볼 만하다.",
				"stats": {"attack": 3, "speed": 5},
			},
			{
				"name": "가죽 조끼",
				"type": "armor",
				"rarity": "common",
				"description": "얇은 가죽으로 만든 조끼. 최소한의 방어만 가능하다.",
				"stats": {"defense": 2, "hp": 5},
			},
			{
				"name": "흐린 치유 물약",
				"type": "consumable",
				"rarity": "common",
				"description": "약간 탁한 빛깔의 치유 물약. 소량의 생명력을 회복한다.",
				"stats": {"heal": 15},
			},
		],
		"uncommon": [
			{
				"name": "뼈 도끼",
				"type": "weapon",
				"rarity": "uncommon",
				"description": "거대한 괴물의 뼈로 만든 도끼. 묵직한 타격감이 느껴진다.",
				"stats": {"attack": 7, "speed": 3},
			},
			{
				"name": "사슬 갑옷 조각",
				"type": "armor",
				"rarity": "uncommon",
				"description": "부서진 사슬 갑옷의 일부. 아직 쓸만한 부분이 남아있다.",
				"stats": {"defense": 5, "hp": 10},
			},
			{
				"name": "해독 부적",
				"type": "accessory",
				"rarity": "uncommon",
				"description": "독에 대한 저항력을 부여하는 작은 부적.",
				"stats": {"poison_resist": 30},
			},
		],
		"rare": [
			{
				"name": "심연의 검",
				"type": "weapon",
				"rarity": "rare",
				"description": "심연의 어둠을 품은 검. 칼날에서 검은 안개가 피어오른다.",
				"stats": {"attack": 14, "speed": 4, "dark_damage": 5},
			},
			{
				"name": "망자의 갑주",
				"type": "armor",
				"rarity": "rare",
				"description": "죽은 기사의 갑옷. 착용자에게 망자의 의지를 전한다.",
				"stats": {"defense": 10, "hp": 25, "undead_resist": 15},
			},
			{
				"name": "피의 반지",
				"type": "accessory",
				"rarity": "rare",
				"description": "진홍빛 보석이 박힌 반지. 적을 쓰러뜨리면 생명력을 흡수한다.",
				"stats": {"lifesteal": 5, "attack": 3},
			},
		],
		"epic": [
			{
				"name": "파멸의 대검",
				"type": "weapon",
				"rarity": "epic",
				"description": "고대 악마에게 축복받은 대검. 휘두를 때마다 절망의 울음소리가 들린다.",
				"stats": {"attack": 25, "speed": 2, "dark_damage": 12, "fear": 10},
			},
			{
				"name": "심연왕의 왕관",
				"type": "accessory",
				"rarity": "epic",
				"description": "심연의 군주가 쓰던 왕관의 파편. 착용자에게 강대한 어둠의 힘을 부여한다.",
				"stats": {"attack": 10, "defense": 8, "dark_damage": 15, "hp": 50},
			},
		],
		"legendary": [
			{
				"name": "종말의 낫 - 에레보스",
				"type": "weapon",
				"rarity": "legendary",
				"description": "태초의 어둠에서 태어난 낫. 이것을 쥔 자는 삶과 죽음의 경계에 선다.",
				"stats": {"attack": 40, "speed": 5, "dark_damage": 25, "lifesteal": 15, "fear": 20},
			},
		],
	}

# ── Quests ───────────────────────────────────────────────────────────────────

## Return a generic fallback quest.
func get_fallback_quest() -> Dictionary:
	var quests: Array[Dictionary] = _get_quest_templates()
	var idx: int = randi() % quests.size()
	var quest: Dictionary = quests[idx].duplicate(true)
	quest["fallback"] = true
	return quest


func _get_quest_templates() -> Array[Dictionary]:
	return [
		{
			"id": "fallback_quest_purge",
			"title": "어둠의 정화",
			"description": "이 층에 도사리고 있는 어둠의 원천을 찾아 파괴하라.",
			"type": "combat",
			"objectives": [
				{
					"description": "어둠의 핵 파괴",
					"type": "kill",
					"target": "dark_core",
					"count": 1,
					"current": 0,
				},
			],
			"rewards": {
				"experience": 100,
				"gold": 50,
				"items": [
					{"name": "정화의 부적", "type": "accessory", "rarity": "uncommon"},
				],
			},
		},
		{
			"id": "fallback_quest_rescue",
			"title": "잃어버린 영혼 구출",
			"description": "심연에 갇힌 방랑자의 영혼을 찾아 구출하라. 그는 중요한 정보를 알고 있다.",
			"type": "rescue",
			"objectives": [
				{
					"description": "갇힌 영혼 발견",
					"type": "find",
					"target": "trapped_soul",
					"count": 1,
					"current": 0,
				},
				{
					"description": "속박의 사슬 파괴",
					"type": "interact",
					"target": "soul_chain",
					"count": 3,
					"current": 0,
				},
			],
			"rewards": {
				"experience": 150,
				"gold": 30,
				"items": [],
			},
		},
		{
			"id": "fallback_quest_collect",
			"title": "고대의 파편 수집",
			"description": "이 층에 흩어진 고대 유물의 파편을 모아라. 모두 모으면 강력한 힘이 깨어날 것이다.",
			"type": "collect",
			"objectives": [
				{
					"description": "고대 파편 수집",
					"type": "collect",
					"target": "ancient_fragment",
					"count": 5,
					"current": 0,
				},
			],
			"rewards": {
				"experience": 120,
				"gold": 75,
				"items": [
					{"name": "고대의 정수", "type": "material", "rarity": "rare"},
				],
			},
		},
		{
			"id": "fallback_quest_survive",
			"title": "죽음의 시련",
			"description": "끊임없이 밀려오는 망자의 무리에서 살아남아라. 시련을 통과한 자만이 더 깊은 곳으로 나아갈 수 있다.",
			"type": "survival",
			"objectives": [
				{
					"description": "망자의 파도 5회 격퇴",
					"type": "survive",
					"target": "undead_wave",
					"count": 5,
					"current": 0,
				},
			],
			"rewards": {
				"experience": 200,
				"gold": 100,
				"items": [
					{"name": "불굴의 반지", "type": "accessory", "rarity": "rare"},
				],
			},
		},
	]
