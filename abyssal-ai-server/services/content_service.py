"""Content generation service — template-based item and quest generation.

Produces contextually appropriate items and quests for the dungeon crawler.
Will later be augmented with LLM-based generation.
"""

from __future__ import annotations

import logging
import random
import uuid
from typing import Any

from models.content import (
    ItemEffect,
    ItemGenerateRequest,
    ItemGenerateResponse,
    ItemRarity,
    ItemStat,
    ItemType,
    QuestDialogue,
    QuestGenerateRequest,
    QuestGenerateResponse,
    QuestObjective,
    QuestReward,
    QuestType,
)

logger = logging.getLogger(__name__)

# ---------- Item generation data ----------

ITEM_PREFIXES: dict[ItemRarity, list[str]] = {
    ItemRarity.COMMON: ["낡은", "평범한", "흔한", "무딘"],
    ItemRarity.UNCOMMON: ["단단한", "날카로운", "빛나는", "강화된"],
    ItemRarity.RARE: ["정밀한", "마력이 깃든", "축복받은", "고대의"],
    ItemRarity.EPIC: ["전설적인", "용의", "심연의", "파멸의"],
    ItemRarity.LEGENDARY: ["신화적인", "세계를 가르는", "운명의", "영겁의"],
    ItemRarity.ABYSSAL: ["심연이 삼킨", "공허에서 태어난", "차원을 찢는", "종말의"],
}

WEAPON_NAMES = ["검", "도끼", "창", "단검", "활", "지팡이", "철퇴", "대검", "낫", "쌍검"]
ARMOR_NAMES = ["갑옷", "로브", "가죽 갑옷", "사슬 갑옷", "망토", "투구", "건틀릿", "각반"]
ACCESSORY_NAMES = ["반지", "목걸이", "귀걸이", "팔찌", "부적", "브로치", "벨트", "왕관"]
CONSUMABLE_NAMES = ["포션", "영약", "비약", "묘약", "향유"]
SCROLL_NAMES = ["두루마리", "양피지", "주문서", "봉인문", "마법서"]
RUNE_NAMES = ["룬", "문양석", "각인", "인장"]
MATERIAL_NAMES = ["광석", "결정", "정수", "파편", "핵", "가루", "뼈조각"]

ITEM_NAME_MAP: dict[ItemType, list[str]] = {
    ItemType.WEAPON: WEAPON_NAMES,
    ItemType.ARMOR: ARMOR_NAMES,
    ItemType.ACCESSORY: ACCESSORY_NAMES,
    ItemType.CONSUMABLE: CONSUMABLE_NAMES,
    ItemType.SCROLL: SCROLL_NAMES,
    ItemType.RUNE: RUNE_NAMES,
    ItemType.MATERIAL: MATERIAL_NAMES,
    ItemType.KEY_ITEM: ["열쇠", "오브", "인장", "파편"],
}

WEAPON_LORE = [
    "이 무기에서 미세한 진동이 느껴진다. 마치 살아있는 것처럼.",
    "칼날에 새겨진 문양이 어둠 속에서 희미하게 빛난다.",
    "손잡이를 잡으면 과거 주인의 기억이 스쳐 지나간다.",
    "심연의 깊은 곳에서 단련된 무기. 일반적인 대장간에서는 만들 수 없다.",
    "전설에 의하면, 이 무기는 주인을 선택한다고 한다.",
]

ARMOR_LORE = [
    "오래된 전투의 흔적이 곳곳에 남아있지만, 여전히 견고하다.",
    "착용하면 몸이 가벼워지는 느낌이 든다. 마법이 깃들어 있는 것 같다.",
    "이 방어구의 이전 주인은 어떻게 되었을까. 생각하지 않는 게 좋겠다.",
]

ACCESSORY_LORE = [
    "착용하는 순간, 미세한 마력이 온몸을 감싼다.",
    "어떤 존재의 축복이 담겨 있다. 그 존재가 선한지는 알 수 없다.",
    "이 장신구를 바라보면, 심연의 깊은 곳이 보이는 것 같다.",
]

STAT_POOLS: dict[ItemType, list[str]] = {
    ItemType.WEAPON: ["attack", "crit_rate", "crit_damage", "attack_speed", "armor_penetration"],
    ItemType.ARMOR: ["defense", "hp", "damage_reduction", "elemental_resist"],
    ItemType.ACCESSORY: ["hp", "mp", "crit_rate", "speed", "luck", "exp_bonus"],
    ItemType.CONSUMABLE: ["hp_restore", "mp_restore", "attack_buff", "defense_buff"],
    ItemType.SCROLL: ["magic_damage", "mp_cost"],
    ItemType.RUNE: ["attack", "defense", "hp", "speed"],
    ItemType.MATERIAL: [],
    ItemType.KEY_ITEM: [],
}

RARITY_STAT_COUNT: dict[ItemRarity, int] = {
    ItemRarity.COMMON: 1,
    ItemRarity.UNCOMMON: 2,
    ItemRarity.RARE: 3,
    ItemRarity.EPIC: 4,
    ItemRarity.LEGENDARY: 5,
    ItemRarity.ABYSSAL: 6,
}

RARITY_MULTIPLIER: dict[ItemRarity, float] = {
    ItemRarity.COMMON: 1.0,
    ItemRarity.UNCOMMON: 1.5,
    ItemRarity.RARE: 2.5,
    ItemRarity.EPIC: 4.0,
    ItemRarity.LEGENDARY: 7.0,
    ItemRarity.ABYSSAL: 12.0,
}

EFFECT_TEMPLATES: list[dict[str, Any]] = [
    {"effect_name": "생명력 흡수", "description": "공격 시 피해량의 일부를 체력으로 흡수한다.", "trigger": "on_hit"},
    {"effect_name": "화염 부여", "description": "공격에 화염 속성을 추가한다.", "trigger": "on_equip"},
    {"effect_name": "냉기 저항", "description": "냉기 피해를 감소시킨다.", "trigger": "passive"},
    {"effect_name": "독 면역", "description": "독 상태 이상에 면역이 된다.", "trigger": "passive"},
    {"effect_name": "은신", "description": "일정 시간 적의 감지를 피한다.", "trigger": "on_use", "duration_seconds": 10.0, "cooldown_seconds": 60.0},
    {"effect_name": "광폭화", "description": "공격력이 대폭 증가하지만 방어력이 감소한다.", "trigger": "on_use", "duration_seconds": 15.0, "cooldown_seconds": 120.0},
    {"effect_name": "심연의 축복", "description": "어둠 속성 피해를 흡수하여 체력으로 전환한다.", "trigger": "passive"},
    {"effect_name": "반격", "description": "피격 시 일정 확률로 즉시 반격한다.", "trigger": "on_hit"},
]

ICON_MAP: dict[ItemType, str] = {
    ItemType.WEAPON: "icon_weapon",
    ItemType.ARMOR: "icon_armor",
    ItemType.ACCESSORY: "icon_accessory",
    ItemType.CONSUMABLE: "icon_consumable",
    ItemType.SCROLL: "icon_scroll",
    ItemType.RUNE: "icon_rune",
    ItemType.MATERIAL: "icon_material",
    ItemType.KEY_ITEM: "icon_key",
}

# ---------- Quest generation data ----------

QUEST_TEMPLATES: list[dict[str, Any]] = [
    {
        "title": "잃어버린 유물",
        "description": "던전 어딘가에 고대 유물이 잠들어 있다. 찾아서 되돌려야 한다.",
        "type": QuestType.COLLECT,
        "objectives": [
            {"description": "고대 유물 조각 수집", "target": "ancient_relic_fragment", "required_count": 3},
        ],
        "rewards": [
            {"reward_type": "exp", "value": "500", "description": "경험치 500"},
            {"reward_type": "item", "value": "relic_restored", "description": "복원된 고대 유물"},
        ],
        "lore": "이 유물은 한때 이 던전을 봉인하는 데 사용되었다. 부서진 지금도 미약한 힘이 남아있다.",
    },
    {
        "title": "어둠의 정화",
        "description": "심연의 오염이 퍼지고 있다. 오염원을 파괴하고 이 구역을 정화해야 한다.",
        "type": QuestType.KILL,
        "objectives": [
            {"description": "오염된 결정 파괴", "target": "corrupted_crystal", "required_count": 5},
            {"description": "오염의 근원 처치", "target": "corruption_source", "required_count": 1},
        ],
        "rewards": [
            {"reward_type": "gold", "value": "300", "description": "300 골드"},
            {"reward_type": "exp", "value": "800", "description": "경험치 800"},
            {"reward_type": "affinity", "value": "10", "description": "NPC 호감도 +10"},
        ],
        "lore": "심연의 오염은 생명체를 변이시킨다. 방치하면 이 층 전체가 삼켜질 것이다.",
    },
    {
        "title": "잊혀진 길",
        "description": "고대 지도에 표시된 숨겨진 통로를 탐색하라.",
        "type": QuestType.EXPLORE,
        "objectives": [
            {"description": "숨겨진 통로 발견", "target": "hidden_passage", "required_count": 1},
            {"description": "고대 비문 해독", "target": "ancient_inscription", "required_count": 2},
        ],
        "rewards": [
            {"reward_type": "exp", "value": "600", "description": "경험치 600"},
            {"reward_type": "unlock", "value": "shortcut_floor_next", "description": "다음 층 지름길 개방"},
        ],
        "lore": "이 통로는 던전이 만들어지기 전부터 존재했다. 누가, 왜 만들었는지는 아무도 모른다.",
    },
    {
        "title": "상인의 부탁",
        "description": "리라가 특별한 재료를 구해달라고 부탁했다.",
        "type": QuestType.COLLECT,
        "objectives": [
            {"description": "심연의 꽃 채집", "target": "abyss_flower", "required_count": 3},
            {"description": "리라에게 전달", "target": "deliver_to_lira", "required_count": 1},
        ],
        "rewards": [
            {"reward_type": "gold", "value": "200", "description": "200 골드"},
            {"reward_type": "affinity", "value": "15", "description": "리라 호감도 +15"},
            {"reward_type": "item", "value": "merchant_special_potion", "description": "상인의 특제 포션"},
        ],
        "lore": "심연의 꽃은 어둠 속에서만 피는 기이한 식물이다. 리라는 이것으로 특별한 포션을 만든다고 한다.",
    },
    {
        "title": "기사의 시련",
        "description": "다르크가 자신의 타락에 맞서기 위해 시련을 제안했다.",
        "type": QuestType.BOSS,
        "objectives": [
            {"description": "다르크와 모의전투 수행", "target": "spar_with_dark", "required_count": 1},
            {"description": "심연의 결정 정화", "target": "purify_crystal", "required_count": 1},
        ],
        "rewards": [
            {"reward_type": "exp", "value": "1000", "description": "경험치 1000"},
            {"reward_type": "affinity", "value": "20", "description": "다르크 호감도 +20"},
            {"reward_type": "item", "value": "knight_blessing", "description": "기사의 축복 (버프)"},
        ],
        "lore": "다르크는 자신의 타락을 멈출 방법을 찾고 있다. 강한 전사와의 교전이 그의 의지를 되살릴 수 있을지도 모른다.",
    },
    {
        "title": "현자의 수수께끼",
        "description": "에른이 던진 수수께끼를 풀어야 한다. 답은 던전 어딘가에 있다.",
        "type": QuestType.PUZZLE,
        "objectives": [
            {"description": "첫 번째 비문 발견", "target": "riddle_inscription_1", "required_count": 1},
            {"description": "두 번째 비문 발견", "target": "riddle_inscription_2", "required_count": 1},
            {"description": "에른에게 답 전달", "target": "answer_to_sage", "required_count": 1},
        ],
        "rewards": [
            {"reward_type": "exp", "value": "700", "description": "경험치 700"},
            {"reward_type": "affinity", "value": "15", "description": "에른 호감도 +15"},
            {"reward_type": "item", "value": "sage_amulet", "description": "현자의 부적"},
        ],
        "lore": "에른의 수수께끼에는 언제나 진실이 숨어있다. 이번에도 그럴까?",
    },
    {
        "title": "생존자 구출",
        "description": "던전 깊은 곳에서 생존자의 신호가 감지되었다.",
        "type": QuestType.ESCORT,
        "objectives": [
            {"description": "생존자 위치 도달", "target": "survivor_location", "required_count": 1},
            {"description": "생존자를 안전지대까지 호위", "target": "escort_survivor", "required_count": 1},
        ],
        "rewards": [
            {"reward_type": "gold", "value": "500", "description": "500 골드"},
            {"reward_type": "exp", "value": "900", "description": "경험치 900"},
            {"reward_type": "item", "value": "survivor_gratitude_ring", "description": "감사의 반지"},
        ],
        "lore": "심연에서 생존자를 발견하는 것은 극히 드문 일이다. 아직 살아있다면 서둘러야 한다.",
    },
    {
        "title": "심연의 메아리",
        "description": "심연 깊은 곳에서 들려오는 속삭임의 정체를 밝혀라.",
        "type": QuestType.HIDDEN,
        "objectives": [
            {"description": "심연의 속삭임 위치 탐색", "target": "whisper_source", "required_count": 1},
            {"description": "심연의 조각 획득", "target": "abyss_fragment", "required_count": 1},
        ],
        "rewards": [
            {"reward_type": "exp", "value": "1200", "description": "경험치 1200"},
            {"reward_type": "item", "value": "echo_of_abyss", "description": "심연의 메아리 (특수 아이템)"},
        ],
        "lore": "심연이 말을 건다. 그것은 경고인가, 초대인가. 혹은 그 너머의 무언가인가.",
    },
]

NPC_QUEST_DIALOGUE: dict[str, dict[str, list[str]]] = {
    "wandering_merchant": {
        "start": [
            "있잖아, 부탁 하나만 할게! 심연의 꽃이 필요한데... 구해다 주면 좋은 거 줄게~",
            "거래 제안! 내가 필요한 걸 구해다 주면, 특별한 물건을 만들어 줄 수 있어.",
        ],
        "progress": [
            "어떻게 되고 있어? 빨리 구해다 줘~ 기다리는 거 힘들단 말이야!",
            "아직이야? 에이~ 믿고 있을게!",
        ],
        "complete": [
            "와아! 고마워! 약속대로, 여기 특별한 거 줄게! 후후~",
            "역시 내 눈은 틀리지 않았어! 최고의 파트너야!",
        ],
        "fail": [
            "아... 실패했어? 괜찮아, 다음에 다시 해보자.",
        ],
    },
    "captive_adventurer": {
        "start": [
            "...부탁이 있다. 이 근처에 내 동료의 유품이 있을 거야. 찾아줄 수 있겠나.",
            "이 일을 해줄 수 있겠어? 나 혼자서는... 갈 수가 없으니까.",
        ],
        "progress": [
            "아직 찾지 못했어? ...서두르지 않아도 돼. 하지만 조심해.",
            "그 근처에 강한 놈이 있을 수 있어. 준비를 철저히 해.",
        ],
        "complete": [
            "찾아줬구나... 고맙다. 정말로. 이건 네가 가져. 나보다 너한테 더 필요할 거야.",
            "...감사한다. 네 덕에 동료에게 면목이 선다.",
        ],
        "fail": [
            "...괜찮아. 네 탓이 아니야.",
        ],
    },
    "mysterious_sage": {
        "start": [
            "수수께끼를 좋아하나? 이것을 풀어봐라. 답은... 네가 걷는 길 위에 있다.",
            "질문 하나. 답을 찾으면 다시 와라.",
        ],
        "progress": [
            "아직 답을 모르겠나? 눈을 감고, 귀를 열어라.",
            "답은 항상 가까이에 있다. 다만 볼 줄 모를 뿐.",
        ],
        "complete": [
            "정답이다. 하지만 진정한 답은 따로 있지. 이것을 가져가라.",
            "훌륭하다. 네 안의 빛이 조금 더 밝아졌구나.",
        ],
        "fail": [
            "틀렸다. 하지만 실패도 배움이다. 다시 와라.",
        ],
    },
    "fallen_knight": {
        "start": [
            "모험자, 네게 부탁이 있다. 기사로서 차마 말하기 어렵지만... 내 힘을 시험해 줄 수 있겠는가.",
            "내 안의 어둠이 커지고 있다. 강한 자와 겨뤄야... 이성을 유지할 수 있어.",
        ],
        "progress": [
            "준비는 되었나? 전력을 다해라. 봐주면 내가 화를 낸다.",
            "서두를 필요는 없지만... 내 안의 어둠은 기다려주지 않는다.",
        ],
        "complete": [
            "...훌륭했다. 네 덕에 잠시나마 어둠을 밀어낼 수 있었다. 이 은혜, 잊지 않겠다.",
            "네가 이겼군. 아니... 우리 둘 다 이긴 거다. 고맙다, 전우여.",
        ],
        "fail": [
            "...아직 부족하군. 하지만 네 용기는 인정한다. 더 강해져서 다시 와라.",
        ],
    },
}


class ContentService:
    """Template-based content (item & quest) generation."""

    def generate_item(self, req: ItemGenerateRequest) -> ItemGenerateResponse:
        """Generate a random item matching the request parameters."""
        item_type = req.item_type or random.choice([
            ItemType.WEAPON, ItemType.ARMOR, ItemType.ACCESSORY,
            ItemType.CONSUMABLE, ItemType.SCROLL, ItemType.RUNE,
        ])

        prefix = random.choice(ITEM_PREFIXES.get(req.rarity, ITEM_PREFIXES[ItemRarity.COMMON]))
        base_name = random.choice(ITEM_NAME_MAP.get(item_type, ["물건"]))
        name = f"{prefix} {base_name}"

        item_id = f"item_{uuid.uuid4().hex[:12]}"

        # Stats
        stat_pool = STAT_POOLS.get(item_type, [])
        stat_count = min(RARITY_STAT_COUNT.get(req.rarity, 1), len(stat_pool)) if stat_pool else 0
        chosen_stats = random.sample(stat_pool, stat_count) if stat_count > 0 else []
        mult = RARITY_MULTIPLIER.get(req.rarity, 1.0)
        base_power = req.floor_number * 2 + 5

        stats: list[ItemStat] = []
        for s in chosen_stats:
            is_pct = s in ("crit_rate", "crit_damage", "damage_reduction", "elemental_resist",
                           "exp_bonus", "armor_penetration", "luck")
            if is_pct:
                value = round(random.uniform(1, 5) * mult + req.floor_number * 0.5, 1)
            else:
                value = round((base_power + random.uniform(-3, 5)) * mult, 1)
            stats.append(ItemStat(stat_name=s, value=value, is_percentage=is_pct))

        # Effects (higher rarity → more likely)
        effects: list[ItemEffect] = []
        effect_chance = {
            ItemRarity.COMMON: 0.05,
            ItemRarity.UNCOMMON: 0.15,
            ItemRarity.RARE: 0.4,
            ItemRarity.EPIC: 0.7,
            ItemRarity.LEGENDARY: 0.95,
            ItemRarity.ABYSSAL: 1.0,
        }
        if random.random() < effect_chance.get(req.rarity, 0.1):
            eff_template = random.choice(EFFECT_TEMPLATES)
            effects.append(ItemEffect(**eff_template))

        # Lore
        if item_type == ItemType.WEAPON:
            lore = random.choice(WEAPON_LORE)
        elif item_type == ItemType.ARMOR:
            lore = random.choice(ARMOR_LORE)
        elif item_type == ItemType.ACCESSORY:
            lore = random.choice(ACCESSORY_LORE)
        else:
            lore = ""

        # Context-aware description
        description_parts = [f"{req.rarity.value} 등급의 {base_name}."]
        if req.context:
            description_parts.append(req.context)
        if effects:
            description_parts.append(f"특수 효과: {effects[0].effect_name}.")
        description = " ".join(description_parts)

        level_req = max(1, req.floor_number - 2)
        sell_price = int(base_power * mult * random.uniform(5, 15))

        logger.info("Generated item: %s (%s, %s)", name, item_type.value, req.rarity.value)

        return ItemGenerateResponse(
            item_id=item_id,
            name=name,
            item_type=item_type,
            rarity=req.rarity,
            description=description,
            lore=lore,
            level_requirement=level_req,
            stats=stats,
            effects=effects,
            icon_hint=ICON_MAP.get(item_type, "icon_default"),
            sell_price=sell_price,
        )

    def generate_quest(self, req: QuestGenerateRequest) -> QuestGenerateResponse:
        """Generate a quest from templates."""
        # Pick a template — optionally filter by NPC
        candidates = QUEST_TEMPLATES[:]
        if req.npc_id == "wandering_merchant":
            candidates = [t for t in candidates if "상인" in t["title"] or "유물" in t["title"]] or candidates
        elif req.npc_id == "fallen_knight":
            candidates = [t for t in candidates if "기사" in t["title"] or "정화" in t["title"]] or candidates
        elif req.npc_id == "mysterious_sage":
            candidates = [t for t in candidates if "수수께끼" in t["title"] or "메아리" in t["title"]] or candidates
        elif req.npc_id == "captive_adventurer":
            candidates = [t for t in candidates if "구출" in t["title"] or "유물" in t["title"]] or candidates

        template = random.choice(candidates)
        quest_id = f"quest_{uuid.uuid4().hex[:10]}"

        objectives = [
            QuestObjective(
                objective_id=f"{quest_id}_obj_{i}",
                description=obj["description"],
                target=obj["target"],
                required_count=obj["required_count"],
            )
            for i, obj in enumerate(template["objectives"])
        ]

        rewards = [
            QuestReward(**r) for r in template["rewards"]
        ]

        # Build dialogues from NPC data
        dialogues: list[QuestDialogue] = []
        npc_id = req.npc_id or "wandering_merchant"
        npc_dialogues = NPC_QUEST_DIALOGUE.get(npc_id, {})
        for stage in ("start", "progress", "complete", "fail"):
            lines = npc_dialogues.get(stage, [])
            if lines:
                dialogues.append(QuestDialogue(stage=stage, npc_id=npc_id, text=random.choice(lines)))

        logger.info("Generated quest: %s (type=%s, trigger=%s)", template["title"], template["type"].value, req.trigger)

        return QuestGenerateResponse(
            quest_id=quest_id,
            title=template["title"],
            description=template["description"],
            type=template["type"],
            objectives=objectives,
            rewards=rewards,
            dialogues=dialogues,
            time_limit_seconds=None,
            is_hidden=template["type"] == QuestType.HIDDEN,
            lore=template.get("lore", ""),
        )
