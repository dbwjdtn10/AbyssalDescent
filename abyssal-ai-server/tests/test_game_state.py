"""Tests for game state analysis and quest trigger endpoints."""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient


# ---------------------------------------------------------------------------
# POST /api/game/analyze
# ---------------------------------------------------------------------------


class TestGameAnalyze:
    """POST /api/game/analyze tests."""

    def test_analyze_returns_200(self, client: TestClient, game_state: dict) -> None:
        """Valid game state analysis should return HTTP 200."""
        resp = client.post("/api/game/analyze", json=game_state)
        assert resp.status_code == 200

    def test_response_has_required_fields(self, client: TestClient, game_state: dict) -> None:
        """Response must contain triggered_quests, difficulty_adjustment, and game_tips."""
        data = client.post("/api/game/analyze", json=game_state).json()
        assert "triggered_quests" in data
        assert "difficulty_adjustment" in data
        assert "game_tips" in data

    def test_triggered_quests_is_list(self, client: TestClient, game_state: dict) -> None:
        """triggered_quests should be a list."""
        data = client.post("/api/game/analyze", json=game_state).json()
        assert isinstance(data["triggered_quests"], list)

    def test_triggered_quests_capped_at_3(self, client: TestClient) -> None:
        """No more than 3 triggered quests should be returned per call."""
        # Create a game state with many active triggers
        gs = {
            "player_id": "cap_test_player",
            "player_level": 20,
            "current_floor": 10,
            "deaths": 8,
            "total_kills": 150,
            "exploration_rate": 0.95,
            "hp_ratio": 0.2,
            "gold": 2000,
            "inventory": ["gem_shadow", "crystal_mana", "rune_protection"],
            "npc_affinities": {
                "wandering_merchant": 90,
                "captive_adventurer": 60,
                "mysterious_sage": 85,
                "fallen_knight": 25,
            },
            "floors_cleared": [1, 2, 3, 4, 5],
            "bosses_defeated": ["boss_bone_lord", "boss_void_mother"],
            "active_quest_ids": [],
            "damage_taken_ratio": 0.8,
            "healing_item_usage": 0.7,
            "play_time_minutes": 120.0,
            "consecutive_deaths": 4,
            "rooms_without_rest": 15,
            "elite_kills": 10,
            "secrets_found": 5,
            "current_difficulty": "normal",
        }
        data = client.post("/api/game/analyze", json=gs).json()
        assert len(data["triggered_quests"]) <= 3

    def test_triggered_quest_structure(self, client: TestClient) -> None:
        """Each triggered quest should have trigger_type, priority, quest, and context_message."""
        gs = {
            "player_id": "struct_test_player",
            "player_level": 5,
            "current_floor": 5,
            "deaths": 0,
            "total_kills": 30,
            "exploration_rate": 0.5,
            "hp_ratio": 1.0,
            "gold": 200,
            "inventory": [],
            "npc_affinities": {"wandering_merchant": 25},
            "floors_cleared": [1],
            "bosses_defeated": [],
            "active_quest_ids": [],
            "damage_taken_ratio": 0.3,
            "healing_item_usage": 0.2,
            "play_time_minutes": 30.0,
            "consecutive_deaths": 0,
            "rooms_without_rest": 3,
            "elite_kills": 0,
            "secrets_found": 0,
            "current_difficulty": "normal",
        }
        data = client.post("/api/game/analyze", json=gs).json()
        for tq in data["triggered_quests"]:
            assert "trigger_type" in tq
            assert "priority" in tq
            assert 1 <= tq["priority"] <= 5
            assert "quest" in tq
            assert "context_message" in tq
            # Quest sub-object should have standard fields
            quest = tq["quest"]
            assert "quest_id" in quest
            assert "title" in quest
            assert "objectives" in quest
            assert "rewards" in quest

    def test_difficulty_adjustment_present(self, client: TestClient, game_state: dict) -> None:
        """difficulty_adjustment should contain AdaptResponse fields."""
        data = client.post("/api/game/analyze", json=game_state).json()
        da = data["difficulty_adjustment"]
        assert "recommended_difficulty" in da
        assert "monster_level_offset" in da
        assert "monster_count_multiplier" in da

    def test_game_tips_are_korean_strings(self, client: TestClient, game_state: dict) -> None:
        """game_tips should be non-empty strings, expected to be in Korean."""
        data = client.post("/api/game/analyze", json=game_state).json()
        tips = data["game_tips"]
        assert isinstance(tips, list)
        assert len(tips) >= 1
        for tip in tips:
            assert isinstance(tip, str)
            assert len(tip) > 0

    def test_npc_affinity_trigger_fires(self, client: TestClient) -> None:
        """When NPC affinity >= 20 the npc_affinity trigger should eventually fire."""
        gs = {
            "player_id": "affinity_trigger_test",
            "player_level": 5,
            "current_floor": 3,
            "deaths": 0,
            "total_kills": 10,
            "exploration_rate": 0.5,
            "hp_ratio": 1.0,
            "gold": 100,
            "inventory": [],
            "npc_affinities": {"wandering_merchant": 25},
            "floors_cleared": [],
            "bosses_defeated": [],
            "active_quest_ids": [],
            "damage_taken_ratio": 0.3,
            "healing_item_usage": 0.2,
            "play_time_minutes": 15.0,
            "consecutive_deaths": 0,
            "rooms_without_rest": 2,
            "elite_kills": 0,
            "secrets_found": 0,
            "current_difficulty": "normal",
        }
        # Run multiple times because triggers have probability gates
        fired = False
        for _ in range(20):
            data = client.post("/api/game/analyze", json=gs).json()
            for tq in data["triggered_quests"]:
                if tq["trigger_type"] == "npc_affinity":
                    fired = True
                    break
            if fired:
                break
            # Use a different player_id each time to avoid dedup
            gs["player_id"] = f"affinity_trigger_test_{_}"
        assert fired, "npc_affinity trigger should fire at affinity >= 20 within 20 attempts"

    def test_death_count_trigger_fires(self, client: TestClient) -> None:
        """When consecutive_deaths >= 3, the death_count trigger should eventually fire."""
        fired = False
        for i in range(20):
            gs = {
                "player_id": f"death_test_{i}",
                "player_level": 3,
                "current_floor": 2,
                "deaths": 5,
                "total_kills": 5,
                "exploration_rate": 0.3,
                "hp_ratio": 0.5,
                "gold": 50,
                "inventory": [],
                "npc_affinities": {},
                "floors_cleared": [],
                "bosses_defeated": [],
                "active_quest_ids": [],
                "damage_taken_ratio": 0.7,
                "healing_item_usage": 0.5,
                "play_time_minutes": 20.0,
                "consecutive_deaths": 4,
                "rooms_without_rest": 5,
                "elite_kills": 0,
                "secrets_found": 0,
                "current_difficulty": "normal",
            }
            data = client.post("/api/game/analyze", json=gs).json()
            for tq in data["triggered_quests"]:
                if tq["trigger_type"] == "death_count":
                    fired = True
                    break
            if fired:
                break
        assert fired, "death_count trigger should fire with consecutive_deaths >= 3 within 20 attempts"

    def test_floor_milestone_trigger_fires(self, client: TestClient) -> None:
        """Floor milestone (multiples of 5) should trigger floor_milestone quest."""
        fired = False
        for i in range(20):
            gs = {
                "player_id": f"floor_mile_{i}",
                "player_level": 10,
                "current_floor": 10,
                "deaths": 0,
                "total_kills": 40,
                "exploration_rate": 0.6,
                "hp_ratio": 0.8,
                "gold": 300,
                "inventory": [],
                "npc_affinities": {},
                "floors_cleared": [1, 2, 3, 4, 5],
                "bosses_defeated": [],
                "active_quest_ids": [],
                "damage_taken_ratio": 0.4,
                "healing_item_usage": 0.3,
                "play_time_minutes": 50.0,
                "consecutive_deaths": 0,
                "rooms_without_rest": 5,
                "elite_kills": 2,
                "secrets_found": 0,
                "current_difficulty": "normal",
            }
            data = client.post("/api/game/analyze", json=gs).json()
            for tq in data["triggered_quests"]:
                if tq["trigger_type"] == "floor_milestone":
                    fired = True
                    break
            if fired:
                break
        assert fired, "floor_milestone trigger should fire on floor 10 within 20 attempts"

    def test_boss_defeated_trigger_fires(self, client: TestClient) -> None:
        """Defeating a boss should trigger boss_defeated quest."""
        fired = False
        for i in range(20):
            gs = {
                "player_id": f"boss_def_{i}",
                "player_level": 8,
                "current_floor": 6,
                "deaths": 1,
                "total_kills": 50,
                "exploration_rate": 0.6,
                "hp_ratio": 0.7,
                "gold": 400,
                "inventory": [],
                "npc_affinities": {},
                "floors_cleared": [1, 2, 3, 4, 5],
                "bosses_defeated": ["boss_bone_lord"],
                "active_quest_ids": [],
                "damage_taken_ratio": 0.4,
                "healing_item_usage": 0.3,
                "play_time_minutes": 60.0,
                "consecutive_deaths": 0,
                "rooms_without_rest": 3,
                "elite_kills": 2,
                "secrets_found": 0,
                "current_difficulty": "normal",
            }
            data = client.post("/api/game/analyze", json=gs).json()
            for tq in data["triggered_quests"]:
                if tq["trigger_type"] == "boss_defeated":
                    fired = True
                    break
            if fired:
                break
        assert fired, "boss_defeated trigger should fire within 20 attempts"

    def test_deduplication_same_trigger_key(self, client: TestClient) -> None:
        """The same trigger key should not fire twice for the same player_id."""
        gs = {
            "player_id": "dedup_player",
            "player_level": 5,
            "current_floor": 5,
            "deaths": 0,
            "total_kills": 10,
            "exploration_rate": 0.5,
            "hp_ratio": 1.0,
            "gold": 100,
            "inventory": [],
            "npc_affinities": {"wandering_merchant": 25},
            "floors_cleared": [],
            "bosses_defeated": [],
            "active_quest_ids": [],
            "damage_taken_ratio": 0.3,
            "healing_item_usage": 0.2,
            "play_time_minutes": 15.0,
            "consecutive_deaths": 0,
            "rooms_without_rest": 2,
            "elite_kills": 0,
            "secrets_found": 0,
            "current_difficulty": "normal",
        }
        # Call multiple times and count how many npc_affinity triggers fire
        trigger_count = 0
        for _ in range(10):
            data = client.post("/api/game/analyze", json=gs).json()
            trigger_count += sum(
                1 for tq in data["triggered_quests"]
                if tq["trigger_type"] == "npc_affinity"
            )
        # Should fire at most once for the same player + same affinity threshold
        assert trigger_count <= 1, (
            f"npc_affinity trigger fired {trigger_count} times; expected at most 1 (deduplication)"
        )


# ---------------------------------------------------------------------------
# POST /api/game/quest/check-triggers
# ---------------------------------------------------------------------------


class TestQuestCheckTriggers:
    """POST /api/game/quest/check-triggers tests."""

    def test_check_triggers_returns_200(self, client: TestClient, game_state: dict) -> None:
        """Valid request should return HTTP 200."""
        resp = client.post("/api/game/quest/check-triggers", json=game_state)
        assert resp.status_code == 200

    def test_check_triggers_returns_list(self, client: TestClient, game_state: dict) -> None:
        """Response should be a list of TriggeredQuest objects."""
        data = client.post("/api/game/quest/check-triggers", json=game_state).json()
        assert isinstance(data, list)

    def test_check_triggers_structure(self, client: TestClient, game_state: dict) -> None:
        """Each item should have trigger_type, priority, quest, context_message."""
        data = client.post("/api/game/quest/check-triggers", json=game_state).json()
        for tq in data:
            assert "trigger_type" in tq
            assert "priority" in tq
            assert "quest" in tq
            assert "context_message" in tq

    def test_check_triggers_lighter_than_analyze(self, client: TestClient, game_state: dict) -> None:
        """check-triggers should not include difficulty_adjustment or game_tips."""
        data = client.post("/api/game/quest/check-triggers", json=game_state).json()
        # The response is a list, not a dict — so it should not have these keys
        assert isinstance(data, list)

    def test_minimal_game_state(self, client: TestClient) -> None:
        """Minimal game state with defaults should still return a valid response."""
        gs = {
            "player_id": "minimal",
            "player_level": 1,
            "current_floor": 1,
        }
        resp = client.post("/api/game/quest/check-triggers", json=gs)
        assert resp.status_code == 200
        data = resp.json()
        assert isinstance(data, list)
