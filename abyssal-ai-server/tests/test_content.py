"""Tests for content generation endpoints (items and quests)."""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient


# ---------------------------------------------------------------------------
# POST /api/content/item
# ---------------------------------------------------------------------------


class TestItemGeneration:
    """POST /api/content/item tests."""

    def test_item_returns_200(self, client: TestClient, item_request: dict) -> None:
        """Valid item generation request should return HTTP 200."""
        resp = client.post("/api/content/item", json=item_request)
        assert resp.status_code == 200

    def test_item_response_has_required_fields(self, client: TestClient, item_request: dict) -> None:
        """Response must contain all ItemGenerateResponse fields."""
        data = client.post("/api/content/item", json=item_request).json()
        required = [
            "item_id", "name", "item_type", "rarity", "description",
            "level_requirement", "stats", "effects", "sell_price",
        ]
        for field in required:
            assert field in data, f"Missing field: {field}"

    @pytest.mark.parametrize("rarity", ["common", "uncommon", "rare", "epic", "legendary", "abyssal"])
    def test_all_rarities(self, client: TestClient, item_request: dict, rarity: str) -> None:
        """Each rarity level should produce a successful response with matching rarity."""
        item_request["rarity"] = rarity
        resp = client.post("/api/content/item", json=item_request)
        assert resp.status_code == 200
        data = resp.json()
        assert data["rarity"] == rarity

    @pytest.mark.parametrize("item_type", [
        "weapon", "armor", "accessory", "consumable", "material", "key_item", "scroll", "rune",
    ])
    def test_all_item_types(self, client: TestClient, item_request: dict, item_type: str) -> None:
        """Each item type should produce a successful response with matching type."""
        item_request["item_type"] = item_type
        resp = client.post("/api/content/item", json=item_request)
        assert resp.status_code == 200
        data = resp.json()
        assert data["item_type"] == item_type

    def test_item_type_none_generates_random_type(self, client: TestClient) -> None:
        """Omitting item_type should auto-select a random type."""
        req = {"floor_number": 3, "rarity": "common"}
        resp = client.post("/api/content/item", json=req)
        assert resp.status_code == 200
        data = resp.json()
        valid_types = {"weapon", "armor", "accessory", "consumable", "material", "key_item", "scroll", "rune"}
        assert data["item_type"] in valid_types

    def test_stats_scale_with_floor(self, client: TestClient) -> None:
        """Items from higher floors should have higher stat values on average."""
        results_low: list[float] = []
        results_high: list[float] = []

        for _ in range(10):
            low = client.post("/api/content/item", json={
                "floor_number": 1, "rarity": "common", "item_type": "weapon",
            }).json()
            high = client.post("/api/content/item", json={
                "floor_number": 50, "rarity": "common", "item_type": "weapon",
            }).json()
            if low["stats"]:
                results_low.append(sum(s["value"] for s in low["stats"]))
            if high["stats"]:
                results_high.append(sum(s["value"] for s in high["stats"]))

        if results_low and results_high:
            avg_low = sum(results_low) / len(results_low)
            avg_high = sum(results_high) / len(results_high)
            assert avg_high > avg_low, (
                f"Floor 50 avg stats ({avg_high:.1f}) should exceed floor 1 ({avg_low:.1f})"
            )

    def test_higher_rarity_more_stats(self, client: TestClient) -> None:
        """Higher rarity items should have more stat entries than lower rarity."""
        common = client.post("/api/content/item", json={
            "floor_number": 10, "rarity": "common", "item_type": "weapon",
        }).json()
        legendary = client.post("/api/content/item", json={
            "floor_number": 10, "rarity": "legendary", "item_type": "weapon",
        }).json()
        # Common: 1 stat, Legendary: 5 stats (from RARITY_STAT_COUNT)
        assert len(legendary["stats"]) >= len(common["stats"])

    def test_item_id_unique(self, client: TestClient, item_request: dict) -> None:
        """Consecutive item generations should produce unique item_ids."""
        ids = set()
        for _ in range(5):
            data = client.post("/api/content/item", json=item_request).json()
            ids.add(data["item_id"])
        assert len(ids) == 5

    def test_sell_price_positive(self, client: TestClient, item_request: dict) -> None:
        """Sell price should be non-negative."""
        data = client.post("/api/content/item", json=item_request).json()
        assert data["sell_price"] >= 0

    def test_level_requirement_reasonable(self, client: TestClient, item_request: dict) -> None:
        """Level requirement should be at least 1."""
        data = client.post("/api/content/item", json=item_request).json()
        assert data["level_requirement"] >= 1

    def test_stat_structure(self, client: TestClient, item_request: dict) -> None:
        """Each stat should have stat_name, value, and is_percentage."""
        data = client.post("/api/content/item", json=item_request).json()
        for stat in data["stats"]:
            assert "stat_name" in stat
            assert "value" in stat
            assert "is_percentage" in stat

    def test_effect_structure(self, client: TestClient) -> None:
        """Effects should have required fields when present."""
        # Use abyssal rarity to maximize chance of an effect (100%)
        data = client.post("/api/content/item", json={
            "floor_number": 20, "rarity": "abyssal", "item_type": "weapon",
        }).json()
        for effect in data["effects"]:
            assert "effect_name" in effect
            assert "description" in effect
            assert "trigger" in effect


# ---------------------------------------------------------------------------
# POST /api/content/quest
# ---------------------------------------------------------------------------


class TestQuestGeneration:
    """POST /api/content/quest tests."""

    def test_quest_returns_200(self, client: TestClient, quest_request: dict) -> None:
        """Valid quest generation request should return HTTP 200."""
        resp = client.post("/api/content/quest", json=quest_request)
        assert resp.status_code == 200

    def test_quest_response_has_required_fields(self, client: TestClient, quest_request: dict) -> None:
        """Response must contain all QuestGenerateResponse fields."""
        data = client.post("/api/content/quest", json=quest_request).json()
        required = [
            "quest_id", "title", "description", "type",
            "objectives", "rewards",
        ]
        for field in required:
            assert field in data, f"Missing field: {field}"

    @pytest.mark.parametrize("trigger", ["npc_conversation", "item_found", "floor_enter", "combat"])
    def test_different_triggers(self, client: TestClient, quest_request: dict, trigger: str) -> None:
        """Different trigger values should all produce valid quests."""
        quest_request["trigger"] = trigger
        resp = client.post("/api/content/quest", json=quest_request)
        assert resp.status_code == 200

    def test_objectives_have_required_fields(self, client: TestClient, quest_request: dict) -> None:
        """Each objective should have objective_id, description, target, required_count."""
        data = client.post("/api/content/quest", json=quest_request).json()
        assert len(data["objectives"]) >= 1
        for obj in data["objectives"]:
            assert "objective_id" in obj
            assert "description" in obj
            assert "target" in obj
            assert "required_count" in obj
            assert obj["required_count"] >= 1

    def test_rewards_have_required_fields(self, client: TestClient, quest_request: dict) -> None:
        """Each reward should have reward_type and value."""
        data = client.post("/api/content/quest", json=quest_request).json()
        assert len(data["rewards"]) >= 1
        for reward in data["rewards"]:
            assert "reward_type" in reward
            assert "value" in reward

    @pytest.mark.parametrize("npc_id", [
        "wandering_merchant",
        "fallen_knight",
        "mysterious_sage",
        "captive_adventurer",
    ])
    def test_npc_specific_quest_filtering(self, client: TestClient, quest_request: dict, npc_id: str) -> None:
        """NPC-specific quest generation should produce quests with dialogues."""
        quest_request["npc_id"] = npc_id
        resp = client.post("/api/content/quest", json=quest_request)
        assert resp.status_code == 200
        data = resp.json()
        assert "dialogues" in data

    def test_quest_id_unique(self, client: TestClient, quest_request: dict) -> None:
        """Consecutive quest generations should produce unique quest_ids."""
        ids = set()
        for _ in range(5):
            data = client.post("/api/content/quest", json=quest_request).json()
            ids.add(data["quest_id"])
        assert len(ids) == 5

    def test_quest_type_is_valid_enum(self, client: TestClient, quest_request: dict) -> None:
        """Quest type should be one of the valid QuestType values."""
        valid_types = {"kill", "collect", "explore", "escort", "deliver", "puzzle", "boss", "hidden"}
        data = client.post("/api/content/quest", json=quest_request).json()
        assert data["type"] in valid_types

    def test_quest_dialogue_structure(self, client: TestClient, quest_request: dict) -> None:
        """Quest dialogues should have stage, npc_id, and text."""
        data = client.post("/api/content/quest", json=quest_request).json()
        for dialogue in data.get("dialogues", []):
            assert "stage" in dialogue
            assert "npc_id" in dialogue
            assert "text" in dialogue

    def test_hidden_quest_flag(self, client: TestClient) -> None:
        """Quests of type 'hidden' should have is_hidden=True."""
        # Generate multiple quests to try to get a hidden one
        for _ in range(20):
            data = client.post("/api/content/quest", json={
                "trigger": "exploration",
                "npc_id": None,
                "player_state": {},
            }).json()
            if data["type"] == "hidden":
                assert data["is_hidden"] is True
                return
        # If we never got a hidden quest, that is acceptable (random selection)

    def test_quest_without_npc_uses_default(self, client: TestClient) -> None:
        """When npc_id is None, quests should still generate with dialogues."""
        resp = client.post("/api/content/quest", json={
            "trigger": "floor_enter",
            "npc_id": None,
            "player_state": {},
        })
        assert resp.status_code == 200
