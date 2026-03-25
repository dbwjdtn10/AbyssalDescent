"""Dynamic quest trigger engine — analyses game state and fires quest triggers.

Each trigger has a probability gate so quests feel organic rather than
deterministic.  The service reuses ContentService.generate_quest() to build
the actual quest payload and wraps it with trigger metadata.
"""

from __future__ import annotations

import logging
import random
import uuid
from typing import Any

from models.content import (
    QuestDialogue,
    QuestGenerateRequest,
    QuestGenerateResponse,
    QuestObjective,
    QuestReward,
    QuestType,
)
from models.quest_trigger import GameState, TriggeredQuest
from services.content_service import ContentService

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Inline quest templates used exclusively by the trigger system
# ---------------------------------------------------------------------------

TRIGGER_QUEST_TEMPLATES: dict[str, list[dict[str, Any]]] = {
    "npc_affinity_20": [
        {
            "title": "친밀한 대화",
            "description": "NPC와의 우호적인 관계가 새로운 의뢰를 열었습니다.",
            "type": QuestType.COLLECT,
            "objectives": [
                {"description": "NPC가 요청한 재료 수집", "target": "npc_request_material", "required_count": 2},
            ],
            "rewards": [
                {"reward_type": "affinity", "value": "10", "description": "NPC 호감도 +10"},
                {"reward_type": "gold", "value": "150", "description": "150 골드"},
            ],
            "lore": "신뢰가 쌓이자 NPC가 마음을 열기 시작했습니다.",
        },
    ],
    "npc_affinity_50": [
        {
            "title": "동맹자의 부탁",
            "description": "깊은 신뢰를 바탕으로 NPC가 중요한 임무를 맡겼습니다.",
            "type": QuestType.DELIVER,
            "objectives": [
                {"description": "NPC의 중요 물품 전달", "target": "npc_important_parcel", "required_count": 1},
                {"description": "전달 대상 NPC 찾기", "target": "find_recipient_npc", "required_count": 1},
            ],
            "rewards": [
                {"reward_type": "exp", "value": "800", "description": "경험치 800"},
                {"reward_type": "affinity", "value": "15", "description": "NPC 호감도 +15"},
                {"reward_type": "item", "value": "npc_special_gift", "description": "NPC의 특별 선물"},
            ],
            "lore": "NPC의 과거와 연결된 중요한 물건이다. 이것을 전달하면 숨겨진 이야기가 밝혀질 것이다.",
        },
    ],
    "npc_affinity_80": [
        {
            "title": "운명을 함께하는 자",
            "description": "NPC와의 깊은 유대가 전설적인 퀘스트를 해금했습니다.",
            "type": QuestType.BOSS,
            "objectives": [
                {"description": "NPC의 숙적 처치", "target": "npc_nemesis", "required_count": 1},
                {"description": "봉인된 유물 회수", "target": "sealed_artifact", "required_count": 1},
            ],
            "rewards": [
                {"reward_type": "exp", "value": "2000", "description": "경험치 2000"},
                {"reward_type": "affinity", "value": "25", "description": "NPC 호감도 +25"},
                {"reward_type": "item", "value": "legendary_npc_weapon", "description": "NPC의 전설 무기"},
            ],
            "lore": "NPC가 오랫동안 감춰온 마지막 비밀. 이 퀘스트를 완료하면 NPC의 진정한 결말을 볼 수 있다.",
        },
    ],
    "death_mercy": [
        {
            "title": "심연의 자비",
            "description": "심연이 반복된 죽음을 지켜보고 있었습니다. 구원의 손길이 내려옵니다.",
            "type": QuestType.COLLECT,
            "objectives": [
                {"description": "심연의 부활석 수집", "target": "revival_stone", "required_count": 1},
            ],
            "rewards": [
                {"reward_type": "item", "value": "abyss_revival_charm", "description": "심연의 부활 부적"},
                {"reward_type": "item", "value": "potion_hp_large", "description": "상급 체력 포션 x3"},
                {"reward_type": "exp", "value": "300", "description": "경험치 300"},
            ],
            "lore": "심연은 강한 자를 원한다. 너무 빨리 쓰러지는 자에게는 한 번의 기회를 더 준다.",
        },
        {
            "title": "망자의 안내",
            "description": "이전에 쓰러진 모험자의 영혼이 길을 안내합니다.",
            "type": QuestType.EXPLORE,
            "objectives": [
                {"description": "망자의 길표를 따라가기", "target": "ghost_marker", "required_count": 3},
                {"description": "안전한 경로 발견", "target": "safe_passage", "required_count": 1},
            ],
            "rewards": [
                {"reward_type": "unlock", "value": "safe_route", "description": "안전한 경로 개방"},
                {"reward_type": "exp", "value": "500", "description": "경험치 500"},
            ],
            "lore": "이 심연에서 쓰러진 모든 자들의 기억이 남아있다. 그들의 실패가 너의 길을 밝힌다.",
        },
    ],
    "exploration_reward": [
        {
            "title": "탐험가의 증표",
            "description": "이 층의 대부분을 탐색했습니다. 숨겨진 보물이 모습을 드러냅니다.",
            "type": QuestType.COLLECT,
            "objectives": [
                {"description": "탐험가의 인장 조각 수집", "target": "explorer_seal_fragment", "required_count": 3},
            ],
            "rewards": [
                {"reward_type": "item", "value": "explorer_compass", "description": "탐험가의 나침반 (탐색 보조)"},
                {"reward_type": "gold", "value": "500", "description": "500 골드"},
                {"reward_type": "exp", "value": "600", "description": "경험치 600"},
            ],
            "lore": "이 던전의 모든 구석을 탐색한 자만이 발견할 수 있는 고대의 보물이다.",
        },
    ],
    "item_collection": [
        {
            "title": "수집가의 도전",
            "description": "특정 아이템을 모아 강력한 조합 아이템을 만들 수 있습니다.",
            "type": QuestType.COLLECT,
            "objectives": [
                {"description": "핵심 재료 추가 수집", "target": "combination_material", "required_count": 2},
                {"description": "고대 제단에서 조합", "target": "ancient_altar_combine", "required_count": 1},
            ],
            "rewards": [
                {"reward_type": "item", "value": "combined_artifact", "description": "조합된 유물"},
                {"reward_type": "exp", "value": "700", "description": "경험치 700"},
            ],
            "lore": "흩어진 조각들이 하나의 형태를 이루려 한다. 고대의 힘이 깨어나고 있다.",
        },
    ],
    "floor_milestone": [
        {
            "title": "심연의 시험",
            "description": "깊은 층에 도달했습니다. 심연이 당신을 시험합니다.",
            "type": QuestType.KILL,
            "objectives": [
                {"description": "심연의 시험관 처치", "target": "abyss_examiner", "required_count": 1},
                {"description": "시험의 증표 획득", "target": "trial_proof", "required_count": 1},
            ],
            "rewards": [
                {"reward_type": "exp", "value": "1000", "description": "경험치 1000"},
                {"reward_type": "item", "value": "abyss_trial_badge", "description": "심연의 시험 뱃지"},
                {"reward_type": "gold", "value": "800", "description": "800 골드"},
            ],
            "lore": "매 5층마다 심연은 강한 자를 시험한다. 시험을 통과한 자만이 더 깊이 내려갈 자격을 얻는다.",
        },
        {
            "title": "잊혀진 수호자",
            "description": "이 층의 고대 수호자가 깨어나 도전자를 기다립니다.",
            "type": QuestType.BOSS,
            "objectives": [
                {"description": "고대 수호자 발견", "target": "ancient_guardian_loc", "required_count": 1},
                {"description": "수호자 처치 또는 설득", "target": "ancient_guardian", "required_count": 1},
            ],
            "rewards": [
                {"reward_type": "exp", "value": "1500", "description": "경험치 1500"},
                {"reward_type": "item", "value": "guardian_essence", "description": "수호자의 정수"},
            ],
            "lore": "이 수호자는 던전이 만들어지기 전부터 이곳을 지켰다. 싸움을 피할 수도, 받아들일 수도 있다.",
        },
    ],
    "low_health_frequency": [
        {
            "title": "치유의 샘",
            "description": "자주 부상당하는 당신에게 치유의 샘 위치가 밝혀집니다.",
            "type": QuestType.EXPLORE,
            "objectives": [
                {"description": "치유의 샘 위치 탐색", "target": "healing_spring_loc", "required_count": 1},
            ],
            "rewards": [
                {"reward_type": "item", "value": "healing_spring_water", "description": "치유의 샘물 x5"},
                {"reward_type": "item", "value": "regen_amulet", "description": "재생의 부적"},
            ],
            "lore": "이 심연에도 생명의 기운이 남아있는 곳이 있다. 치유의 샘은 그 마지막 잔재이다.",
        },
    ],
    "boss_defeated": [
        {
            "title": "보스의 유산",
            "description": "보스를 쓰러뜨린 후 숨겨진 방이 열렸습니다.",
            "type": QuestType.EXPLORE,
            "objectives": [
                {"description": "보스의 비밀 방 탐색", "target": "boss_secret_room", "required_count": 1},
                {"description": "보스의 일지 수집", "target": "boss_journal", "required_count": 1},
            ],
            "rewards": [
                {"reward_type": "exp", "value": "1200", "description": "경험치 1200"},
                {"reward_type": "item", "value": "boss_legacy_item", "description": "보스의 유산 (특수 장비)"},
                {"reward_type": "unlock", "value": "boss_lore_entry", "description": "보스 스토리 해금"},
            ],
            "lore": "보스가 쓰러지면서 봉인되어 있던 공간이 열렸다. 그곳에는 보스의 과거가 기록되어 있다.",
        },
        {
            "title": "연쇄 반응",
            "description": "보스를 처치한 여파로 인근 구역에 변화가 일어났습니다.",
            "type": QuestType.KILL,
            "objectives": [
                {"description": "각성한 정예 몬스터 처치", "target": "awakened_elite", "required_count": 3},
            ],
            "rewards": [
                {"reward_type": "exp", "value": "900", "description": "경험치 900"},
                {"reward_type": "gold", "value": "600", "description": "600 골드"},
            ],
            "lore": "보스의 죽음이 주변 몬스터를 각성시켰다. 강해진 적들이 복수를 위해 몰려온다.",
        },
    ],
    "elite_hunter": [
        {
            "title": "정예 사냥꾼",
            "description": "정예 몬스터를 다수 처치한 당신에게 특별한 도전이 주어집니다.",
            "type": QuestType.KILL,
            "objectives": [
                {"description": "특수 정예 몬스터 처치", "target": "special_elite", "required_count": 2},
            ],
            "rewards": [
                {"reward_type": "item", "value": "elite_hunter_trophy", "description": "정예 사냥꾼의 트로피"},
                {"reward_type": "exp", "value": "1000", "description": "경험치 1000"},
            ],
            "lore": "강한 자에게는 더 강한 적이 나타난다. 정예 중의 정예가 당신을 노리고 있다.",
        },
    ],
    "long_session": [
        {
            "title": "심연의 휴식처",
            "description": "오래 탐험한 당신을 위해 안전한 휴식처가 나타났습니다.",
            "type": QuestType.EXPLORE,
            "objectives": [
                {"description": "숨겨진 안식처 발견", "target": "hidden_sanctuary", "required_count": 1},
            ],
            "rewards": [
                {"reward_type": "item", "value": "sanctuary_blessing", "description": "안식처의 축복 (전체 회복)"},
                {"reward_type": "gold", "value": "200", "description": "200 골드"},
            ],
            "lore": "심연 속에도 빛이 닿는 곳이 있다. 지친 모험자를 위한 마지막 쉼터.",
        },
    ],
    "gold_milestone": [
        {
            "title": "부유한 모험자",
            "description": "상당한 재화를 모았습니다. 특별한 거래의 기회가 찾아옵니다.",
            "type": QuestType.DELIVER,
            "objectives": [
                {"description": "비밀 상인 만남", "target": "secret_merchant", "required_count": 1},
                {"description": "특수 거래 완료", "target": "special_trade", "required_count": 1},
            ],
            "rewards": [
                {"reward_type": "item", "value": "merchant_exclusive", "description": "상인 전용 희귀 아이템"},
                {"reward_type": "exp", "value": "400", "description": "경험치 400"},
            ],
            "lore": "심연의 깊은 곳에서 활동하는 비밀 상인이 재화가 풍부한 모험자를 찾고 있다.",
        },
    ],
    "no_quest_active": [
        {
            "title": "심연의 속삭임",
            "description": "퀘스트 없이 방황하는 당신에게 심연이 길을 제시합니다.",
            "type": QuestType.EXPLORE,
            "objectives": [
                {"description": "심연의 표식 따라가기", "target": "abyss_sign", "required_count": 3},
            ],
            "rewards": [
                {"reward_type": "exp", "value": "500", "description": "경험치 500"},
                {"reward_type": "gold", "value": "300", "description": "300 골드"},
            ],
            "lore": "목적 없이 심연을 헤매는 자에게 심연 자체가 방향을 알려준다.",
        },
    ],
    "secret_hunter": [
        {
            "title": "비밀의 수호자",
            "description": "많은 비밀을 발견한 당신에게 최후의 비밀이 모습을 드러냅니다.",
            "type": QuestType.HIDDEN,
            "objectives": [
                {"description": "최후의 비밀 방 입장", "target": "ultimate_secret_room", "required_count": 1},
                {"description": "비밀의 열쇠 조합", "target": "secret_key_combine", "required_count": 1},
            ],
            "rewards": [
                {"reward_type": "item", "value": "secret_keeper_crown", "description": "비밀 수호자의 왕관"},
                {"reward_type": "exp", "value": "1500", "description": "경험치 1500"},
            ],
            "lore": "모든 비밀에는 끝이 있다. 마지막 비밀을 풀면 이 던전의 진정한 모습을 볼 수 있다.",
        },
    ],
    "kill_milestone": [
        {
            "title": "학살자의 낙인",
            "description": "수많은 몬스터를 처치한 당신에게 심연의 낙인이 새겨집니다.",
            "type": QuestType.KILL,
            "objectives": [
                {"description": "낙인에 끌려온 강적 처치", "target": "mark_attracted_enemy", "required_count": 1},
            ],
            "rewards": [
                {"reward_type": "item", "value": "slayer_mark", "description": "학살자의 낙인 (공격력 증가)"},
                {"reward_type": "exp", "value": "800", "description": "경험치 800"},
            ],
            "lore": "피의 냄새가 심연의 깊은 곳까지 닿았다. 강한 자를 찾아 무언가가 올라오고 있다.",
        },
    ],
    "first_floor_clear": [
        {
            "title": "첫 발걸음",
            "description": "첫 번째 층을 클리어했습니다. 심연의 진정한 시작입니다.",
            "type": QuestType.EXPLORE,
            "objectives": [
                {"description": "2층 입구의 비문 해독", "target": "floor2_inscription", "required_count": 1},
            ],
            "rewards": [
                {"reward_type": "exp", "value": "200", "description": "경험치 200"},
                {"reward_type": "item", "value": "beginner_talisman", "description": "초심자의 부적"},
            ],
            "lore": "첫 번째 시험을 통과한 자에게 심연은 작은 선물을 준다.",
        },
    ],
}


class QuestTriggerService:
    """Analyses game state and returns dynamically triggered quests.

    Each trigger condition has a probability gate so the same game state
    will not always produce the same quests, making the experience feel
    organic.
    """

    def __init__(self) -> None:
        self._content_service = ContentService()
        # Track which trigger types already fired per player to limit repeats
        self._fired_triggers: dict[str, set[str]] = {}

    def _get_fired(self, player_id: str) -> set[str]:
        return self._fired_triggers.setdefault(player_id, set())

    def _mark_fired(self, player_id: str, trigger_key: str) -> None:
        self._fired_triggers.setdefault(player_id, set()).add(trigger_key)

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def check_triggers(self, game_state: GameState) -> list[TriggeredQuest]:
        """Check all trigger conditions against game state.

        Returns list of triggered quest suggestions, sorted by priority
        (highest first).  Duplicates with active quests are filtered out.
        """
        triggered: list[TriggeredQuest] = []

        triggered.extend(self._check_npc_affinity_triggers(game_state))
        triggered.extend(self._check_death_triggers(game_state))
        triggered.extend(self._check_exploration_triggers(game_state))
        triggered.extend(self._check_floor_milestone_triggers(game_state))
        triggered.extend(self._check_combat_triggers(game_state))
        triggered.extend(self._check_boss_defeated_triggers(game_state))
        triggered.extend(self._check_health_triggers(game_state))
        triggered.extend(self._check_item_triggers(game_state))
        triggered.extend(self._check_economy_triggers(game_state))
        triggered.extend(self._check_session_triggers(game_state))
        triggered.extend(self._check_no_quest_triggers(game_state))
        triggered.extend(self._check_secret_triggers(game_state))
        triggered.extend(self._check_kill_milestone_triggers(game_state))
        triggered.extend(self._check_first_clear_triggers(game_state))

        # Filter out quests whose IDs collide with active quests
        active_ids = set(game_state.active_quest_ids)
        triggered = [
            t for t in triggered
            if t.quest.quest_id not in active_ids
        ]

        # Sort by priority descending
        triggered.sort(key=lambda t: t.priority, reverse=True)

        # Cap at 3 quests per analysis call to avoid overwhelming the player
        return triggered[:3]

    # ------------------------------------------------------------------
    # Private trigger checkers
    # ------------------------------------------------------------------

    def _check_npc_affinity_triggers(self, gs: GameState) -> list[TriggeredQuest]:
        results: list[TriggeredQuest] = []
        for npc_id, affinity in gs.npc_affinities.items():
            # Threshold 80
            key_80 = f"npc_affinity_80_{npc_id}"
            if affinity >= 80 and key_80 not in self._get_fired(gs.player_id):
                if random.random() < 0.85:
                    quest = self._build_quest("npc_affinity_80", gs, npc_id=npc_id)
                    results.append(TriggeredQuest(
                        trigger_type="npc_affinity",
                        priority=5,
                        quest=quest,
                        context_message=f"{npc_id}와(과)의 호감도가 80에 도달했습니다. 전설적인 퀘스트가 해금되었습니다!",
                    ))
                    self._mark_fired(gs.player_id, key_80)

            # Threshold 50
            key_50 = f"npc_affinity_50_{npc_id}"
            if 50 <= affinity < 80 and key_50 not in self._get_fired(gs.player_id):
                if random.random() < 0.70:
                    quest = self._build_quest("npc_affinity_50", gs, npc_id=npc_id)
                    results.append(TriggeredQuest(
                        trigger_type="npc_affinity",
                        priority=4,
                        quest=quest,
                        context_message=f"{npc_id}와(과)의 호감도가 50에 도달했습니다. 새로운 의뢰가 생겼습니다.",
                    ))
                    self._mark_fired(gs.player_id, key_50)

            # Threshold 20
            key_20 = f"npc_affinity_20_{npc_id}"
            if 20 <= affinity < 50 and key_20 not in self._get_fired(gs.player_id):
                if random.random() < 0.55:
                    quest = self._build_quest("npc_affinity_20", gs, npc_id=npc_id)
                    results.append(TriggeredQuest(
                        trigger_type="npc_affinity",
                        priority=3,
                        quest=quest,
                        context_message=f"{npc_id}와(과)의 관계가 개선되어 간단한 의뢰를 받았습니다.",
                    ))
                    self._mark_fired(gs.player_id, key_20)
        return results

    def _check_death_triggers(self, gs: GameState) -> list[TriggeredQuest]:
        results: list[TriggeredQuest] = []
        # Consecutive deaths >= 3 → mercy quest
        if gs.consecutive_deaths >= 3:
            key = f"death_mercy_consec_{gs.current_floor}"
            if key not in self._get_fired(gs.player_id) and random.random() < 0.80:
                quest = self._build_quest("death_mercy", gs)
                results.append(TriggeredQuest(
                    trigger_type="death_count",
                    priority=5,
                    quest=quest,
                    context_message="연속 사망이 감지되었습니다. 심연이 구원의 기회를 제공합니다.",
                ))
                self._mark_fired(gs.player_id, key)
        # Total deaths >= 5 (but not consecutive trigger already)
        elif gs.deaths >= 5:
            key = f"death_mercy_total_{gs.deaths // 5}"
            if key not in self._get_fired(gs.player_id) and random.random() < 0.60:
                quest = self._build_quest("death_mercy", gs)
                results.append(TriggeredQuest(
                    trigger_type="death_count",
                    priority=4,
                    quest=quest,
                    context_message=f"총 {gs.deaths}회 사망했습니다. 심연이 당신의 고통을 지켜보고 있습니다.",
                ))
                self._mark_fired(gs.player_id, key)
        return results

    def _check_exploration_triggers(self, gs: GameState) -> list[TriggeredQuest]:
        results: list[TriggeredQuest] = []
        if gs.exploration_rate > 0.80:
            key = f"exploration_high_{gs.current_floor}"
            if key not in self._get_fired(gs.player_id) and random.random() < 0.65:
                quest = self._build_quest("exploration_reward", gs)
                results.append(TriggeredQuest(
                    trigger_type="exploration_high",
                    priority=3,
                    quest=quest,
                    context_message=f"탐색률이 {gs.exploration_rate*100:.0f}%에 도달했습니다. 숨겨진 보물의 위치가 드러납니다.",
                ))
                self._mark_fired(gs.player_id, key)
        return results

    def _check_floor_milestone_triggers(self, gs: GameState) -> list[TriggeredQuest]:
        results: list[TriggeredQuest] = []
        if gs.current_floor % 5 == 0 and gs.current_floor > 0:
            key = f"floor_milestone_{gs.current_floor}"
            if key not in self._get_fired(gs.player_id) and random.random() < 0.75:
                quest = self._build_quest("floor_milestone", gs)
                results.append(TriggeredQuest(
                    trigger_type="floor_milestone",
                    priority=4,
                    quest=quest,
                    context_message=f"{gs.current_floor}층에 도달했습니다. 심연의 특별한 시험이 시작됩니다.",
                ))
                self._mark_fired(gs.player_id, key)
        return results

    def _check_combat_triggers(self, gs: GameState) -> list[TriggeredQuest]:
        results: list[TriggeredQuest] = []
        # Elite hunter trigger
        if gs.elite_kills >= 5:
            key = f"elite_hunter_{gs.elite_kills // 5}"
            if key not in self._get_fired(gs.player_id) and random.random() < 0.60:
                quest = self._build_quest("elite_hunter", gs)
                results.append(TriggeredQuest(
                    trigger_type="elite_hunter",
                    priority=3,
                    quest=quest,
                    context_message=f"정예 몬스터를 {gs.elite_kills}마리 처치했습니다. 더 강한 적이 도전장을 내밀었습니다.",
                ))
                self._mark_fired(gs.player_id, key)
        return results

    def _check_boss_defeated_triggers(self, gs: GameState) -> list[TriggeredQuest]:
        results: list[TriggeredQuest] = []
        for boss_id in gs.bosses_defeated:
            key = f"boss_defeated_{boss_id}"
            if key not in self._get_fired(gs.player_id) and random.random() < 0.75:
                quest = self._build_quest("boss_defeated", gs)
                results.append(TriggeredQuest(
                    trigger_type="boss_defeated",
                    priority=4,
                    quest=quest,
                    context_message=f"보스 '{boss_id}'를 처치한 여파로 새로운 탐색 기회가 열렸습니다.",
                ))
                self._mark_fired(gs.player_id, key)
        return results

    def _check_health_triggers(self, gs: GameState) -> list[TriggeredQuest]:
        results: list[TriggeredQuest] = []
        # Frequently low HP + high healing usage
        if gs.hp_ratio < 0.4 and gs.healing_item_usage > 0.5:
            key = f"low_health_freq_{gs.current_floor}"
            if key not in self._get_fired(gs.player_id) and random.random() < 0.50:
                quest = self._build_quest("low_health_frequency", gs)
                results.append(TriggeredQuest(
                    trigger_type="low_health_frequency",
                    priority=4,
                    quest=quest,
                    context_message="체력이 자주 낮아지고 있습니다. 치유의 샘에 대한 단서가 발견되었습니다.",
                ))
                self._mark_fired(gs.player_id, key)
        return results

    def _check_item_triggers(self, gs: GameState) -> list[TriggeredQuest]:
        results: list[TriggeredQuest] = []
        # Check for special item combinations
        special_items = {"gem_shadow", "crystal_mana", "rune_protection"}
        collected_special = special_items.intersection(set(gs.inventory))
        if len(collected_special) >= 2:
            key = f"item_collection_{len(collected_special)}"
            if key not in self._get_fired(gs.player_id) and random.random() < 0.60:
                quest = self._build_quest("item_collection", gs)
                results.append(TriggeredQuest(
                    trigger_type="item_collected",
                    priority=3,
                    quest=quest,
                    context_message="특수 아이템 조합이 가능합니다. 고대 제단을 찾아보세요.",
                ))
                self._mark_fired(gs.player_id, key)
        return results

    def _check_economy_triggers(self, gs: GameState) -> list[TriggeredQuest]:
        results: list[TriggeredQuest] = []
        if gs.gold >= 1000:
            key = f"gold_milestone_{gs.gold // 1000}"
            if key not in self._get_fired(gs.player_id) and random.random() < 0.45:
                quest = self._build_quest("gold_milestone", gs)
                results.append(TriggeredQuest(
                    trigger_type="gold_milestone",
                    priority=2,
                    quest=quest,
                    context_message="상당한 재화를 보유하고 있습니다. 비밀 상인이 접근해옵니다.",
                ))
                self._mark_fired(gs.player_id, key)
        return results

    def _check_session_triggers(self, gs: GameState) -> list[TriggeredQuest]:
        results: list[TriggeredQuest] = []
        if gs.play_time_minutes >= 90 and gs.rooms_without_rest >= 12:
            key = f"long_session_{int(gs.play_time_minutes) // 90}"
            if key not in self._get_fired(gs.player_id) and random.random() < 0.55:
                quest = self._build_quest("long_session", gs)
                results.append(TriggeredQuest(
                    trigger_type="long_session",
                    priority=2,
                    quest=quest,
                    context_message="오랜 탐험으로 지쳐가고 있습니다. 안식처의 기운이 느껴집니다.",
                ))
                self._mark_fired(gs.player_id, key)
        return results

    def _check_no_quest_triggers(self, gs: GameState) -> list[TriggeredQuest]:
        results: list[TriggeredQuest] = []
        if len(gs.active_quest_ids) == 0 and gs.current_floor >= 2:
            key = f"no_quest_{gs.current_floor}"
            if key not in self._get_fired(gs.player_id) and random.random() < 0.70:
                quest = self._build_quest("no_quest_active", gs)
                results.append(TriggeredQuest(
                    trigger_type="no_quest_active",
                    priority=2,
                    quest=quest,
                    context_message="현재 진행 중인 퀘스트가 없습니다. 심연이 새로운 목표를 제시합니다.",
                ))
                self._mark_fired(gs.player_id, key)
        return results

    def _check_secret_triggers(self, gs: GameState) -> list[TriggeredQuest]:
        results: list[TriggeredQuest] = []
        if gs.secrets_found >= 3:
            key = f"secret_hunter_{gs.secrets_found // 3}"
            if key not in self._get_fired(gs.player_id) and random.random() < 0.50:
                quest = self._build_quest("secret_hunter", gs)
                results.append(TriggeredQuest(
                    trigger_type="secret_hunter",
                    priority=3,
                    quest=quest,
                    context_message=f"비밀 방을 {gs.secrets_found}개 발견했습니다. 최후의 비밀이 기다립니다.",
                ))
                self._mark_fired(gs.player_id, key)
        return results

    def _check_kill_milestone_triggers(self, gs: GameState) -> list[TriggeredQuest]:
        results: list[TriggeredQuest] = []
        if gs.total_kills >= 100:
            key = f"kill_milestone_{gs.total_kills // 100}"
            if key not in self._get_fired(gs.player_id) and random.random() < 0.55:
                quest = self._build_quest("kill_milestone", gs)
                results.append(TriggeredQuest(
                    trigger_type="kill_milestone",
                    priority=3,
                    quest=quest,
                    context_message=f"총 {gs.total_kills}마리를 처치했습니다. 심연이 당신의 힘을 인정합니다.",
                ))
                self._mark_fired(gs.player_id, key)
        return results

    def _check_first_clear_triggers(self, gs: GameState) -> list[TriggeredQuest]:
        results: list[TriggeredQuest] = []
        if 1 in gs.floors_cleared and len(gs.floors_cleared) == 1:
            key = "first_floor_clear"
            if key not in self._get_fired(gs.player_id) and random.random() < 0.90:
                quest = self._build_quest("first_floor_clear", gs)
                results.append(TriggeredQuest(
                    trigger_type="first_floor_clear",
                    priority=3,
                    quest=quest,
                    context_message="첫 번째 층을 클리어했습니다! 심연의 여정이 본격적으로 시작됩니다.",
                ))
                self._mark_fired(gs.player_id, key)
        return results

    # ------------------------------------------------------------------
    # Quest building helper
    # ------------------------------------------------------------------

    def _build_quest(
        self,
        template_key: str,
        gs: GameState,
        npc_id: str | None = None,
    ) -> QuestGenerateResponse:
        """Build a QuestGenerateResponse from a trigger template."""
        templates = TRIGGER_QUEST_TEMPLATES.get(template_key, [])
        if not templates:
            # Fallback to ContentService random quest
            return self._content_service.generate_quest(
                QuestGenerateRequest(
                    trigger=template_key,
                    npc_id=npc_id,
                    player_state={"level": gs.player_level, "floor": gs.current_floor},
                )
            )

        template = random.choice(templates)
        quest_id = f"quest_trig_{uuid.uuid4().hex[:10]}"

        objectives = [
            QuestObjective(
                objective_id=f"{quest_id}_obj_{i}",
                description=obj["description"],
                target=obj["target"],
                required_count=obj["required_count"],
            )
            for i, obj in enumerate(template["objectives"])
        ]

        rewards = [QuestReward(**r) for r in template["rewards"]]

        # Scale rewards based on floor / level
        scaled_rewards: list[QuestReward] = []
        for reward in rewards:
            if reward.reward_type in ("exp", "gold"):
                try:
                    base_val = int(reward.value)
                    scaled_val = int(base_val * (1 + gs.current_floor * 0.05))
                    scaled_rewards.append(QuestReward(
                        reward_type=reward.reward_type,
                        value=str(scaled_val),
                        description=f"{reward.description.split()[0]} {scaled_val}",
                    ))
                except (ValueError, IndexError):
                    scaled_rewards.append(reward)
            else:
                scaled_rewards.append(reward)

        # Build dialogues from NPC data if available
        dialogues: list[QuestDialogue] = []
        effective_npc = npc_id or "wandering_merchant"
        for stage in ("start", "complete"):
            dialogues.append(QuestDialogue(
                stage=stage,
                npc_id=effective_npc,
                text=self._get_trigger_dialogue(template_key, stage),
            ))

        return QuestGenerateResponse(
            quest_id=quest_id,
            title=template["title"],
            description=template["description"],
            type=template["type"],
            objectives=objectives,
            rewards=scaled_rewards,
            dialogues=dialogues,
            time_limit_seconds=None,
            is_hidden=template["type"] == QuestType.HIDDEN,
            lore=template.get("lore", ""),
        )

    @staticmethod
    def _get_trigger_dialogue(template_key: str, stage: str) -> str:
        """Return contextual dialogue text for a triggered quest."""
        dialogues: dict[str, dict[str, str]] = {
            "npc_affinity_20": {
                "start": "음, 너한테 부탁할 게 있는데... 해줄 수 있어?",
                "complete": "고마워! 역시 믿을 만한 사람이야.",
            },
            "npc_affinity_50": {
                "start": "너니까 부탁하는 거야. 중요한 일이야.",
                "complete": "...정말 고맙다. 너 같은 사람은 처음이야.",
            },
            "npc_affinity_80": {
                "start": "너와 함께라면 해낼 수 있을 거야. 내 마지막 비밀을 알려줄게.",
                "complete": "드디어... 끝났어. 너 덕분이야. 진심으로.",
            },
            "death_mercy": {
                "start": "심연이 너에게 한 번의 기회를 더 준다. 낭비하지 마.",
                "complete": "살아남았군. 심연도 인정한 것 같다.",
            },
            "exploration_reward": {
                "start": "이 층의 비밀을 거의 다 밝혀냈군. 마지막 보물이 널 기다리고 있어.",
                "complete": "대단해! 이 층의 모든 비밀을 밝혀냈어!",
            },
            "floor_milestone": {
                "start": "심연의 시험이 시작된다. 각오해라.",
                "complete": "시험을 통과했다. 더 깊은 곳으로 갈 자격을 얻었다.",
            },
            "boss_defeated": {
                "start": "보스가 쓰러지면서 새로운 길이 열렸다. 탐색해보자.",
                "complete": "보스의 유산을 찾았군. 그 힘을 잘 사용해.",
            },
            "low_health_frequency": {
                "start": "자꾸 다치고 있군. 치유의 샘이 근처에 있다는 소문이 있어.",
                "complete": "치유의 샘을 찾았다! 이제 좀 더 안전하게 탐험할 수 있을 거야.",
            },
            "item_collection": {
                "start": "가지고 있는 아이템들이 반응하고 있어. 고대 제단을 찾아봐.",
                "complete": "조합에 성공했다! 새로운 유물의 힘을 느낄 수 있어.",
            },
            "elite_hunter": {
                "start": "강한 적을 많이 쓰러뜨렸군. 더 강한 놈이 네 냄새를 맡았어.",
                "complete": "최강의 정예를 쓰러뜨렸다. 진정한 사냥꾼이야.",
            },
            "long_session": {
                "start": "지쳐 보이는군. 근처에 안전한 곳이 있다.",
                "complete": "잘 쉬었나? 다시 출발할 준비가 됐겠군.",
            },
            "gold_milestone": {
                "start": "크크크... 재화가 두둑하군. 특별한 거래를 제안하지.",
                "complete": "좋은 거래였어. 그 물건, 잘 사용해.",
            },
            "no_quest_active": {
                "start": "목적 없이 헤매고 있군. 심연이 길을 보여주고 있어.",
                "complete": "심연의 표식을 따라왔군. 새로운 길이 열렸다.",
            },
            "secret_hunter": {
                "start": "많은 비밀을 밝혔군. 마지막 비밀이 남았다.",
                "complete": "모든 비밀을 풀었다. 이 던전의 진실이 드러났다.",
            },
            "kill_milestone": {
                "start": "피의 냄새가 심연을 깨웠다. 낙인이 새겨졌다.",
                "complete": "낙인의 힘을 얻었다. 대가도 있을 것이다.",
            },
            "first_floor_clear": {
                "start": "첫 번째 시험을 통과했군. 진짜는 지금부터야.",
                "complete": "좋은 출발이야. 앞으로도 이 기세를 유지해.",
            },
        }
        return dialogues.get(template_key, {}).get(stage, "...")
