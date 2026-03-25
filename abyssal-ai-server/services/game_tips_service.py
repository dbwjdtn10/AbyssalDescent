"""Contextual gameplay tips service — generates situational advice in Korean.

Analyses the current game state and returns 1-3 relevant, non-generic tips
that help the player without feeling intrusive.
"""

from __future__ import annotations

import random
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from models.quest_trigger import GameState


class GameTipsService:
    """Generates contextual gameplay tips in Korean based on game state."""

    def get_tips(self, game_state: "GameState") -> list[str]:
        """Return 1-3 contextual tips based on current game state."""
        candidates: list[tuple[str, int]] = []  # (tip, relevance_weight)

        # --- Health-related tips ---
        if game_state.hp_ratio < 0.3:
            candidates.append(("현재 체력이 매우 낮습니다. 전투 전에 반드시 체력을 회복하세요.", 5))
        if game_state.hp_ratio < 0.5 and game_state.healing_item_usage < 0.2:
            candidates.append(("보유한 포션을 아끼지 마세요. 위험한 상황에서 사용하지 않으면 의미가 없습니다.", 4))
        if game_state.healing_item_usage > 0.7:
            candidates.append(("포션 소모가 빠릅니다. 상점에서 포션을 충분히 준비하세요.", 4))

        # --- Death-related tips ---
        if game_state.deaths >= 5:
            candidates.append(("사망 횟수가 많습니다. 전투 전 주변을 먼저 탐색하고 함정을 확인하세요.", 5))
        if game_state.consecutive_deaths >= 3:
            candidates.append(("연속으로 사망했습니다. 장비를 점검하고, 레벨이 충분한지 확인해보세요.", 5))
        if game_state.consecutive_deaths >= 2 and game_state.damage_taken_ratio > 0.6:
            candidates.append(("피해를 많이 받고 있습니다. 방어구를 업그레이드하거나 회피에 집중해보세요.", 4))

        # --- Exploration tips ---
        if game_state.exploration_rate < 0.3:
            candidates.append(("숨겨진 방에 유용한 아이템이 있을 수 있습니다. 탐색률을 높여보세요.", 3))
        if game_state.exploration_rate < 0.5 and game_state.current_floor >= 5:
            candidates.append(("탐색하지 않은 구역에 비밀 통로가 숨어있을 수 있습니다.", 3))
        if game_state.exploration_rate > 0.9:
            candidates.append(("훌륭한 탐색률입니다! 숨겨진 보상을 놓치지 않았을 것입니다.", 2))
        if game_state.secrets_found == 0 and game_state.current_floor >= 3:
            candidates.append(("아직 비밀 방을 발견하지 못했습니다. 벽을 자세히 조사해보세요.", 3))

        # --- NPC affinity tips ---
        high_affinity_npcs = [
            npc_id for npc_id, aff in game_state.npc_affinities.items() if aff >= 40
        ]
        if high_affinity_npcs:
            candidates.append(("호감도가 높은 NPC에게 특별한 퀘스트를 받을 수 있습니다. 대화해보세요.", 3))
        low_affinity_npcs = [
            npc_id for npc_id, aff in game_state.npc_affinities.items() if -20 <= aff < 10
        ]
        if low_affinity_npcs and game_state.current_floor >= 3:
            candidates.append(("NPC와 친해지면 유용한 힌트와 보상을 얻을 수 있습니다.", 2))

        # --- Boss floor approaching ---
        is_boss_floor = game_state.current_floor % 5 == 0
        if is_boss_floor:
            candidates.append(("보스층입니다! 보스의 패턴을 관찰하고 빈틈을 노리세요.", 5))
        else:
            next_boss_floor = ((game_state.current_floor // 5) + 1) * 5
            floors_to_boss = next_boss_floor - game_state.current_floor
            if floors_to_boss <= 2:
                candidates.append(("보스전이 가까워지고 있습니다. 장비와 포션을 점검하세요.", 4))
            if floors_to_boss == 1:
                candidates.append((f"{next_boss_floor}층에 보스가 기다리고 있습니다. 만반의 준비를 하세요.", 5))

        # --- Combat performance tips ---
        if game_state.damage_taken_ratio > 0.7 and game_state.deaths < 3:
            candidates.append(("피해를 많이 받고 있습니다. 방어 장비를 강화해보세요.", 3))
        if game_state.total_kills > 50 and game_state.elite_kills == 0:
            candidates.append(("정예 몬스터를 처치하면 더 좋은 보상을 얻을 수 있습니다.", 2))
        if game_state.elite_kills >= 5:
            candidates.append(("정예 몬스터를 많이 처치했습니다. 특별한 보상이 누적되고 있을 수 있습니다.", 2))

        # --- Economy tips ---
        if game_state.gold < 50 and game_state.current_floor >= 5:
            candidates.append(("골드가 부족합니다. 불필요한 아이템을 판매하거나 보물 방을 찾아보세요.", 3))
        if game_state.gold > 1000:
            candidates.append(("골드가 충분합니다. 상점에서 좋은 장비를 구매해보세요.", 2))

        # --- Inventory tips ---
        if len(game_state.inventory) > 20:
            candidates.append(("인벤토리가 꽉 차가고 있습니다. 불필요한 아이템을 정리하세요.", 3))
        key_items = [i for i in game_state.inventory if "key" in i.lower() or "열쇠" in i]
        if key_items and game_state.exploration_rate < 0.6:
            candidates.append(("열쇠 아이템을 보유하고 있습니다. 잠긴 문을 찾아보세요.", 4))

        # --- Playtime tips ---
        if game_state.play_time_minutes > 120 and game_state.rooms_without_rest > 10:
            candidates.append(("오래 탐험했습니다. 휴식 방에서 잠시 쉬어가세요.", 2))

        # --- Floor progression tips ---
        if game_state.current_floor >= 10 and len(game_state.bosses_defeated) == 0:
            candidates.append(("보스를 아직 처치하지 못했습니다. 보스 방을 찾아 도전해보세요.", 4))
        expected_bosses = game_state.current_floor // 5
        if len(game_state.bosses_defeated) < expected_bosses and expected_bosses > 0:
            candidates.append(("건너뛴 보스가 있습니다. 이전 보스를 처치하면 추가 보상을 받을 수 있습니다.", 3))

        # --- Early game tips ---
        if game_state.current_floor <= 2 and game_state.player_level <= 2:
            candidates.append(("초반에는 무리하지 말고 천천히 탐색하며 경험치를 쌓으세요.", 2))

        # --- Damage taken pattern ---
        if game_state.rooms_without_rest > 15:
            candidates.append(("휴식 없이 너무 오래 전투했습니다. 체력 관리에 주의하세요.", 4))

        if not candidates:
            candidates.append(("심연의 깊은 곳으로 내려갈수록 더 강력한 보상이 기다리고 있습니다.", 1))

        # Sort by relevance weight descending, then pick top 1-3
        candidates.sort(key=lambda x: x[1], reverse=True)

        # Take top candidates but add some randomness to avoid repetition
        top_pool = candidates[:6]  # top 6 most relevant
        num_tips = min(3, len(top_pool))

        # Weighted random selection without replacement
        selected: list[str] = []
        pool = list(top_pool)
        for _ in range(num_tips):
            if not pool:
                break
            weights = [w for _, w in pool]
            total = sum(weights)
            if total == 0:
                break
            r = random.uniform(0, total)
            cumulative = 0.0
            chosen_idx = 0
            for idx, (_, w) in enumerate(pool):
                cumulative += w
                if r <= cumulative:
                    chosen_idx = idx
                    break
            selected.append(pool[chosen_idx][0])
            pool.pop(chosen_idx)

        return selected
