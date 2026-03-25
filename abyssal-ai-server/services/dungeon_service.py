"""Dungeon generation service — procedural floor layout using seed-based RNG.

Produces a connected graph of rooms with monsters, items, and environmental
effects.  Boss rooms appear every 5 floors.  The generator respects the
player's visited_room_types to reduce repetition.
"""

from __future__ import annotations

import hashlib
import logging
import random
from typing import Sequence

from models.dungeon import (
    AdaptRequest,
    AdaptResponse,
    BossData,
    Difficulty,
    Direction,
    DungeonGenerateRequest,
    DungeonGenerateResponse,
    EnvironmentalEffect,
    ItemDrop,
    MonsterRank,
    MonsterSpawn,
    Room,
    RoomConnection,
    RoomShape,
    RoomSize,
    RoomType,
)

logger = logging.getLogger(__name__)

# ---------- Floor theme data ----------

FLOOR_THEMES: dict[str, dict] = {
    "catacombs": {
        "name_templates": [
            "잊혀진 지하묘지 {n}층",
            "망자의 회랑 {n}층",
            "뼈의 미궁 {n}층",
        ],
        "desc_templates": [
            "차가운 돌벽 사이로 죽은 자들의 속삭임이 울려 퍼진다. 바닥에는 오래된 해골이 흩어져 있고, 희미한 인광이 길을 비춘다.",
            "축축한 공기와 부패의 냄새가 가득하다. 벽에 새겨진 고대 문양이 어둠 속에서 희미하게 빛난다.",
        ],
        "env_types": ["darkness", "poison_fog"],
        "monster_pool": [
            ("해골 전사", "skeleton_warrior"),
            ("구울", "ghoul"),
            ("해골 마법사", "skeleton_mage"),
            ("망령", "wraith"),
        ],
    },
    "abyss": {
        "name_templates": [
            "심연의 균열 {n}층",
            "어둠의 심장부 {n}층",
            "공허의 회랑 {n}층",
        ],
        "desc_templates": [
            "현실의 경계가 무너진 공간. 보라빛 균열 사이로 이세계의 바람이 불어온다. 발아래 바닥이 천천히 부식되고 있다.",
            "빛조차 삼키는 완전한 어둠. 그 속에서 무언가가 움직인다. 벽에서 촉수 같은 그림자가 꿈틀거린다.",
        ],
        "env_types": ["darkness", "void_corruption"],
        "monster_pool": [
            ("심연의 감시자", "abyss_watcher"),
            ("공허 촉수", "void_tentacle"),
            ("그림자 추적자", "shadow_stalker"),
            ("심연 비명자", "abyss_screamer"),
        ],
    },
    "fire": {
        "name_templates": [
            "불꽃의 단층 {n}층",
            "용암 동굴 {n}층",
            "화염의 제단 {n}층",
        ],
        "desc_templates": [
            "뜨거운 열기가 피부를 태운다. 벽의 균열에서 용암이 흐르고, 공기가 아지랑이처럼 일렁인다.",
            "바닥 아래로 끓는 용암이 보인다. 열기에 금속 장비가 달아오르고, 온몸에 땀이 흐른다.",
        ],
        "env_types": ["fire", "heat"],
        "monster_pool": [
            ("화염 정령", "fire_elemental"),
            ("용암 골렘", "lava_golem"),
            ("화염 박쥐 무리", "fire_bat_swarm"),
            ("불의 사제", "fire_priest"),
        ],
    },
    "ice": {
        "name_templates": [
            "동결된 회랑 {n}층",
            "서리의 미궁 {n}층",
            "얼음 심연 {n}층",
        ],
        "desc_templates": [
            "모든 것이 얼어붙은 세계. 벽면의 얼음 속에 과거 모험자들의 얼어붙은 모습이 보인다.",
            "숨을 쉴 때마다 하얀 입김이 피어오른다. 바닥의 검은 얼음 아래로 무언가가 헤엄치고 있다.",
        ],
        "env_types": ["ice", "frost"],
        "monster_pool": [
            ("서리 거미", "frost_spider"),
            ("얼음 골렘", "ice_golem"),
            ("냉기 망령", "frost_wraith"),
            ("동결 마법사", "cryo_mage"),
        ],
    },
    "corruption": {
        "name_templates": [
            "오염된 성역 {n}층",
            "타락의 정원 {n}층",
            "금단의 실험실 {n}층",
        ],
        "desc_templates": [
            "벽과 바닥이 살아있는 것처럼 맥동한다. 기이한 보라빛 점액이 모든 곳을 뒤덮고, 알 수 없는 눈동자들이 벽에서 깜빡인다.",
            "어둠의 마법으로 변이된 생물들이 우글거린다. 공기 자체가 독으로 물들어 있고, 오래된 마법진이 불길하게 빛난다.",
        ],
        "env_types": ["poison_fog", "corruption"],
        "monster_pool": [
            ("변이체", "mutant"),
            ("오염된 기사", "corrupted_knight"),
            ("포자 괴물", "spore_beast"),
            ("점액 슬라임", "toxic_slime"),
        ],
    },
}

BOSS_DATA: dict[int, dict] = {
    5: {
        "boss_id": "boss_bone_lord",
        "name": "뼈의 군주 오시리안",
        "title": "깨어난 망자의 왕",
        "description": "수천 개의 해골이 합쳐져 만들어진 거대한 존재. 빈 눈구멍에서 푸른 불꽃이 타오르고, 거대한 뼈 검을 휘두른다.",
        "phases": 2,
        "special_mechanics": ["bone_shield", "summon_skeletons", "bone_storm"],
        "lore": "한때 이 던전을 지배했던 왕의 잔재. 죽어서도 왕좌를 지키려는 집착이 그를 언데드로 만들었다.",
    },
    10: {
        "boss_id": "boss_void_mother",
        "name": "공허의 어머니",
        "title": "심연에서 온 자",
        "description": "거대한 눈동자 하나가 공중에 떠 있다. 그 주위로 수십 개의 촉수가 꿈틀거리며 공간을 왜곡시킨다.",
        "phases": 3,
        "special_mechanics": ["void_gaze", "tentacle_slam", "dimension_shift", "madness_aura"],
        "lore": "심연의 가장 깊은 곳에서 기어올라온 존재. 그 눈을 보는 자는 광기에 물든다고 전해진다.",
    },
    15: {
        "boss_id": "boss_flame_tyrant",
        "name": "화염 폭군 이그니스",
        "title": "천 개의 불꽃을 삼킨 자",
        "description": "끊임없이 타오르는 거인. 그가 걸을 때마다 바닥이 녹아내리고, 그의 포효는 화염의 파도를 일으킨다.",
        "phases": 2,
        "special_mechanics": ["magma_eruption", "flame_breath", "inferno_slam"],
        "lore": "고대의 화염 신전을 지키던 수호자. 신전이 심연에 삼켜진 후, 분노로 미쳐버렸다.",
    },
    20: {
        "boss_id": "boss_frozen_empress",
        "name": "동결의 여제 글라시아",
        "title": "영원한 겨울의 지배자",
        "description": "순백의 갑옷을 입은 아름다운 여인. 하지만 그녀의 눈동자는 텅 비어있고, 그녀가 손을 뻗으면 모든 것이 얼어붙는다.",
        "phases": 3,
        "special_mechanics": ["absolute_zero", "ice_clone", "blizzard", "frozen_throne"],
        "lore": "사랑하는 이를 잃은 슬픔으로 모든 감정을 얼려버린 고대 여왕. 그녀의 눈물은 아직도 얼음이 되어 떨어진다.",
    },
}

# Fallback boss template for floors not in the explicit table
DEFAULT_BOSS_TEMPLATE = {
    "boss_id": "boss_floor_{n}",
    "name": "심연의 수호자",
    "title": "{n}층의 지배자",
    "description": "이 층을 지배하는 강력한 존재. 심연의 힘에 의해 끊임없이 강화되고 있다.",
    "phases": 2,
    "special_mechanics": ["dark_slash", "shadow_step", "abyss_roar"],
    "lore": "심연이 깊어질수록, 수호자도 강해진다. 이 자의 정체는 아무도 모른다.",
}

ROOM_DESCRIPTIONS: dict[RoomType, list[str]] = {
    RoomType.ENTRANCE: [
        "거대한 돌문이 뒤에서 천천히 닫힌다. 되돌아갈 수 없다.",
        "차가운 바람이 아래에서 불어온다. 심연이 너를 부르고 있다.",
    ],
    RoomType.CORRIDOR: [
        "좁고 긴 통로. 벽에 긁힌 자국이 가득하다.",
        "희미한 횃불이 벽을 비추고 있다. 누군가 최근에 여기를 지나갔다.",
        "천장에서 물이 떨어진다. 이끼 낀 돌바닥이 미끄럽다.",
    ],
    RoomType.COMBAT: [
        "넓은 공간. 바닥에 오래된 핏자국이 있다. 무언가의 기척이 느껴진다.",
        "부서진 무기와 갑옷 조각이 흩어져 있다. 여기서 많은 전투가 벌어졌다.",
        "어둠 속에서 으르렁거리는 소리가 들린다.",
    ],
    RoomType.TREASURE: [
        "빛나는 무언가가 방 한가운데에 놓여 있다. 함정일까?",
        "오래된 보물상자가 먼지를 뒤집어쓴 채 놓여 있다.",
    ],
    RoomType.TRAP: [
        "바닥의 타일 일부가 살짝 들려 있다. 주의해야 한다.",
        "벽에 작은 구멍들이 일정한 간격으로 뚫려 있다. 누군가의 함정이다.",
    ],
    RoomType.PUZZLE: [
        "벽에 고대 문자가 새겨져 있다. 어떤 의미가 있는 것 같다.",
        "방 한가운데에 기이한 장치가 놓여 있다. 올바른 순서로 작동시켜야 한다.",
    ],
    RoomType.REST: [
        "안전한 느낌이 드는 작은 방. 모닥불의 흔적이 남아 있다.",
        "다른 모험자가 남긴 야영지. 아직 온기가 남아 있다.",
    ],
    RoomType.SHOP: [
        "벽에 물건들이 진열되어 있다. 누군가가 이곳에서 장사를 하고 있다.",
    ],
    RoomType.BOSS: [
        "거대한 문 너머에서 압도적인 기운이 느껴진다. 각오해야 한다.",
        "바닥에 새겨진 거대한 마법진이 붉게 빛나고 있다.",
    ],
    RoomType.SECRET: [
        "숨겨진 통로를 발견했다. 오래전 누군가가 의도적으로 감춘 공간이다.",
    ],
    RoomType.EVENT: [
        "기이한 에너지가 이 방을 감싸고 있다. 무슨 일이 일어날 것 같다.",
        "벽에 걸린 그림의 눈동자가 움직인 것 같다.",
    ],
}

ITEM_TEMPLATES: list[dict] = [
    {"item_id": "potion_hp_small", "name": "하급 체력 포션", "rarity": "common", "description": "붉은 액체가 담긴 작은 병. 체력을 소량 회복한다."},
    {"item_id": "potion_hp_medium", "name": "중급 체력 포션", "rarity": "uncommon", "description": "진한 붉은 빛의 포션. 상당량의 체력을 회복한다."},
    {"item_id": "scroll_identify", "name": "감정 두루마리", "rarity": "common", "description": "아이템의 정체를 밝혀주는 마법 두루마리."},
    {"item_id": "crystal_mana", "name": "마나 결정", "rarity": "uncommon", "description": "푸른 빛의 결정. 마나를 회복시켜 준다."},
    {"item_id": "key_rusty", "name": "녹슨 열쇠", "rarity": "common", "description": "오래되어 녹슨 열쇠. 어딘가의 문을 열 수 있을 것이다."},
    {"item_id": "gem_shadow", "name": "그림자 보석", "rarity": "rare", "description": "어둠을 머금은 보석. 빛을 흡수하는 듯하다."},
    {"item_id": "rune_protection", "name": "수호의 룬", "rarity": "rare", "description": "새기면 일정 시간 방어력이 증가하는 고대 룬."},
]


class DungeonService:
    """Procedural dungeon floor generator."""

    def _get_theme(self, floor_number: int) -> str:
        """Pick a floor theme based on depth."""
        if floor_number <= 5:
            return "catacombs"
        elif floor_number <= 10:
            return "abyss"
        elif floor_number <= 15:
            return "fire"
        elif floor_number <= 20:
            return "ice"
        else:
            return "corruption"

    def _difficulty_multiplier(self, difficulty: Difficulty) -> float:
        return {
            Difficulty.EASY: 0.7,
            Difficulty.NORMAL: 1.0,
            Difficulty.HARD: 1.3,
            Difficulty.NIGHTMARE: 1.6,
            Difficulty.ABYSS: 2.0,
        }[difficulty]

    def _room_count(self, floor_number: int, difficulty: Difficulty, rng: random.Random) -> int:
        base = 6 + floor_number // 3
        base = min(base, 20)
        noise = rng.randint(-1, 2)
        return max(5, int(base * self._difficulty_multiplier(difficulty) + noise))

    def _pick_room_types(
        self,
        count: int,
        is_boss_floor: bool,
        visited: Sequence[RoomType],
        rng: random.Random,
    ) -> list[RoomType]:
        """Decide room types for the floor, reducing recently visited types."""
        types: list[RoomType] = [RoomType.ENTRANCE]

        if is_boss_floor:
            types.append(RoomType.BOSS)
            count -= 1  # reserve boss slot

        # Weighted pool
        pool: list[tuple[RoomType, float]] = [
            (RoomType.COMBAT, 30),
            (RoomType.CORRIDOR, 20),
            (RoomType.TREASURE, 10),
            (RoomType.TRAP, 10),
            (RoomType.PUZZLE, 8),
            (RoomType.REST, 7),
            (RoomType.EVENT, 8),
            (RoomType.SECRET, 4),
            (RoomType.SHOP, 3),
        ]

        # Lower weight for recently-visited types
        visited_set = set(visited)
        adjusted: list[tuple[RoomType, float]] = []
        for rt, w in pool:
            if rt in visited_set:
                adjusted.append((rt, w * 0.4))
            else:
                adjusted.append((rt, w))

        remaining = count - 1  # minus entrance
        for _ in range(remaining):
            total = sum(w for _, w in adjusted)
            roll = rng.uniform(0, total)
            cumulative = 0.0
            chosen = adjusted[0][0]
            for rt, w in adjusted:
                cumulative += w
                if roll <= cumulative:
                    chosen = rt
                    break
            types.append(chosen)

        return types

    def _build_connections(self, rooms: list[Room], rng: random.Random) -> None:
        """Create a connected graph — every room reachable from entrance."""
        directions_list = list(Direction)

        # Linear chain first to guarantee connectivity
        for i in range(len(rooms) - 1):
            d = directions_list[i % len(directions_list)]
            opposite = {
                Direction.NORTH: Direction.SOUTH,
                Direction.SOUTH: Direction.NORTH,
                Direction.EAST: Direction.WEST,
                Direction.WEST: Direction.EAST,
            }
            rooms[i].connections.append(
                RoomConnection(direction=d, target_room_id=rooms[i + 1].id)
            )
            rooms[i + 1].connections.append(
                RoomConnection(direction=opposite[d], target_room_id=rooms[i].id)
            )

        # Add some extra cross-links for variety
        extra = rng.randint(1, max(1, len(rooms) // 3))
        for _ in range(extra):
            a = rng.randint(0, len(rooms) - 1)
            b = rng.randint(0, len(rooms) - 1)
            if a == b:
                continue
            already = {c.target_room_id for c in rooms[a].connections}
            if rooms[b].id in already:
                continue
            d = rng.choice(directions_list)
            rooms[a].connections.append(
                RoomConnection(direction=d, target_room_id=rooms[b].id)
            )

    def _populate_room(
        self,
        room: Room,
        floor_number: int,
        difficulty: Difficulty,
        theme_key: str,
        rng: random.Random,
    ) -> None:
        """Fill a room with monsters, items, and environmental effects."""
        theme = FLOOR_THEMES[theme_key]
        mult = self._difficulty_multiplier(difficulty)

        # Description
        descs = ROOM_DESCRIPTIONS.get(room.type, [""])
        room.description = rng.choice(descs)

        # Monsters (combat, boss, trap rooms)
        if room.type in (RoomType.COMBAT, RoomType.TRAP, RoomType.EVENT):
            num_monsters = rng.randint(1, max(1, int(3 * mult)))
            for j in range(num_monsters):
                m_name, m_id = rng.choice(theme["monster_pool"])
                level = max(1, floor_number + rng.randint(-1, 2))
                rank = MonsterRank.NORMAL
                if rng.random() < 0.15 * mult:
                    rank = MonsterRank.ELITE
                    m_name = "정예 " + m_name
                room.monsters.append(
                    MonsterSpawn(
                        monster_id=f"{m_id}_{room.id}_{j}",
                        name=m_name,
                        rank=rank,
                        level=level,
                        count=rng.randint(1, 2) if rank == MonsterRank.NORMAL else 1,
                        description=f"{m_name}이(가) 적의를 드러내며 다가온다.",
                    )
                )

        # Items
        if room.type in (RoomType.TREASURE, RoomType.SECRET, RoomType.REST, RoomType.SHOP):
            num_items = rng.randint(1, 3)
            for _ in range(num_items):
                tmpl = rng.choice(ITEM_TEMPLATES)
                room.items.append(ItemDrop(**tmpl))
        elif room.type == RoomType.COMBAT and rng.random() < 0.3:
            tmpl = rng.choice(ITEM_TEMPLATES)
            room.items.append(ItemDrop(**tmpl))

        # Environmental effects
        if room.type in (RoomType.TRAP, RoomType.COMBAT, RoomType.BOSS) or rng.random() < 0.2:
            if theme["env_types"]:
                etype = rng.choice(theme["env_types"])
                room.environmental.append(
                    EnvironmentalEffect(
                        effect_type=etype,
                        intensity=round(min(1.0, rng.uniform(0.2, 0.8 * mult)), 2),
                        description=f"{etype} 효과가 이 방을 감싸고 있다.",
                    )
                )

    def generate_floor(self, req: DungeonGenerateRequest) -> DungeonGenerateResponse:
        """Generate a full dungeon floor."""
        seed = req.seed if req.seed is not None else int(
            hashlib.sha256(f"floor-{req.floor_number}-{req.player_level}".encode()).hexdigest(), 16
        ) % (2**31)
        rng = random.Random(seed)

        theme_key = self._get_theme(req.floor_number)
        theme = FLOOR_THEMES[theme_key]
        is_boss_floor = req.floor_number % 5 == 0

        # Floor meta
        floor_name = rng.choice(theme["name_templates"]).format(n=req.floor_number)
        floor_desc = rng.choice(theme["desc_templates"])

        # Room layout
        count = self._room_count(req.floor_number, req.difficulty, rng)
        room_types = self._pick_room_types(count, is_boss_floor, req.visited_room_types, rng)
        rng.shuffle(room_types)

        # Ensure entrance is first and boss is last
        if RoomType.ENTRANCE in room_types:
            room_types.remove(RoomType.ENTRANCE)
            room_types.insert(0, RoomType.ENTRANCE)
        if is_boss_floor and RoomType.BOSS in room_types:
            room_types.remove(RoomType.BOSS)
            room_types.append(RoomType.BOSS)

        rooms: list[Room] = []
        shapes = list(RoomShape)
        sizes = list(RoomSize)
        for i, rt in enumerate(room_types):
            room = Room(
                id=f"room_{req.floor_number}_{i:02d}",
                type=rt,
                shape=rng.choice(shapes),
                size=rng.choice(sizes),
                name=f"{floor_name} — 방 {i + 1}",
            )
            self._populate_room(room, req.floor_number, req.difficulty, theme_key, rng)
            rooms.append(room)

        self._build_connections(rooms, rng)

        # Boss data
        boss: BossData | None = None
        if is_boss_floor:
            bdata = BOSS_DATA.get(req.floor_number, DEFAULT_BOSS_TEMPLATE)
            boss_level = max(req.floor_number, req.player_level) + 3
            boss = BossData(
                boss_id=bdata["boss_id"].format(n=req.floor_number) if "{n}" in bdata["boss_id"] else bdata["boss_id"],
                name=bdata["name"],
                title=bdata["title"].format(n=req.floor_number) if "{n}" in bdata["title"] else bdata["title"],
                level=boss_level,
                description=bdata["description"],
                phases=bdata["phases"],
                special_mechanics=bdata["special_mechanics"],
                lore=bdata["lore"],
                loot_table=[
                    ItemDrop(item_id=f"boss_loot_{req.floor_number}_1", name="보스의 핵심", rarity="epic",
                             description="보스를 쓰러뜨린 증거. 강력한 힘이 깃들어 있다."),
                    ItemDrop(item_id=f"boss_loot_{req.floor_number}_2", name="심연의 결정", rarity="rare",
                             description="심연의 에너지가 응축된 결정체."),
                ],
            )

        logger.info("Generated floor %d (%s) with %d rooms, seed=%d", req.floor_number, theme_key, len(rooms), seed)
        return DungeonGenerateResponse(
            floor_number=req.floor_number,
            floor_name=floor_name,
            floor_description=floor_desc,
            rooms=rooms,
            boss=boss,
            seed=seed,
        )

    def adapt_difficulty(self, req: AdaptRequest) -> AdaptResponse:
        """Analyse player behaviour and recommend difficulty tweaks."""
        score = 0.0

        # Dying a lot → easier
        if req.deaths >= 5:
            score -= 2.0
        elif req.deaths >= 3:
            score -= 1.0
        elif req.deaths == 0:
            score += 0.5

        # Damage taken ratio
        if req.damage_taken_ratio > 0.7:
            score -= 1.0
        elif req.damage_taken_ratio < 0.3:
            score += 1.0

        # Healing usage
        if req.healing_item_usage > 0.6:
            score -= 0.5
        elif req.healing_item_usage < 0.2:
            score += 0.5

        # Exploration
        if req.exploration_rate > 0.8:
            score += 0.5

        # Map score to difficulty
        difficulties = list(Difficulty)
        current_idx = difficulties.index(req.current_difficulty)
        if score <= -2.0 and current_idx > 0:
            new_diff = difficulties[current_idx - 1]
        elif score >= 2.0 and current_idx < len(difficulties) - 1:
            new_diff = difficulties[current_idx + 1]
        else:
            new_diff = req.current_difficulty

        monster_offset = int(score)
        monster_mult = round(max(0.5, min(2.0, 1.0 + score * 0.15)), 2)
        trap_freq = round(max(0.0, min(1.0, 0.3 + score * 0.1)), 2)
        loot_bonus = round(max(0.0, min(1.0, 0.5 - score * 0.1)), 2)  # inverse: harder ⇒ less bonus
        heal_freq = round(max(0.0, min(1.0, 0.5 - score * 0.1)), 2)

        reasons: list[str] = []
        if score < -1:
            reasons.append("플레이어가 고전 중입니다. 난이도를 낮춥니다.")
        elif score > 1:
            reasons.append("플레이어가 쉽게 진행 중입니다. 도전을 강화합니다.")
        else:
            reasons.append("현재 난이도가 적절합니다.")

        return AdaptResponse(
            recommended_difficulty=new_diff,
            monster_level_offset=monster_offset,
            monster_count_multiplier=monster_mult,
            trap_frequency=trap_freq,
            loot_quality_bonus=loot_bonus,
            healing_item_frequency=heal_freq,
            reason=" ".join(reasons),
        )
