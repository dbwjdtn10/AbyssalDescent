"""Shared pytest fixtures for the Abyssal Descent AI Server test suite."""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from main import app


# ---------------------------------------------------------------------------
# Client fixtures
# ---------------------------------------------------------------------------


@pytest.fixture()
def client() -> TestClient:
    """Synchronous FastAPI test client."""
    return TestClient(app)


# ---------------------------------------------------------------------------
# Common request payloads
# ---------------------------------------------------------------------------


@pytest.fixture()
def dungeon_request() -> dict:
    """Minimal valid DungeonGenerateRequest body."""
    return {
        "floor_number": 3,
        "difficulty": "normal",
        "player_level": 5,
        "player_inventory": [],
        "visited_room_types": [],
        "seed": 42,
    }


@pytest.fixture()
def adapt_request_struggling() -> dict:
    """AdaptRequest for a player who is struggling."""
    return {
        "player_id": "test_player",
        "floor_number": 5,
        "deaths": 6,
        "average_clear_time_seconds": 200.0,
        "damage_taken_ratio": 0.8,
        "healing_item_usage": 0.7,
        "exploration_rate": 0.3,
        "player_level": 4,
        "current_difficulty": "normal",
    }


@pytest.fixture()
def adapt_request_skilled() -> dict:
    """AdaptRequest for a player who is breezing through."""
    return {
        "player_id": "test_player",
        "floor_number": 10,
        "deaths": 0,
        "average_clear_time_seconds": 30.0,
        "damage_taken_ratio": 0.1,
        "healing_item_usage": 0.1,
        "exploration_rate": 0.9,
        "player_level": 12,
        "current_difficulty": "normal",
    }


@pytest.fixture()
def npc_chat_request() -> dict:
    """Minimal valid NPCChatRequest body."""
    return {
        "npc_id": "wandering_merchant",
        "player_message": "안녕하세요!",
        "player_state": {
            "level": 5,
            "current_floor": 3,
            "inventory": [],
            "hp_ratio": 1.0,
            "gold": 100,
        },
        "conversation_history": [],
    }


@pytest.fixture()
def item_request() -> dict:
    """Minimal valid ItemGenerateRequest body."""
    return {
        "floor_number": 5,
        "rarity": "rare",
        "item_type": "weapon",
        "context": "",
    }


@pytest.fixture()
def quest_request() -> dict:
    """Minimal valid QuestGenerateRequest body."""
    return {
        "trigger": "npc_conversation",
        "npc_id": "wandering_merchant",
        "player_state": {},
    }


@pytest.fixture()
def game_state() -> dict:
    """Comprehensive GameState body for /api/game/analyze."""
    return {
        "player_id": "test_player_gs",
        "player_level": 10,
        "current_floor": 10,
        "deaths": 4,
        "total_kills": 60,
        "exploration_rate": 0.75,
        "hp_ratio": 0.6,
        "gold": 500,
        "inventory": ["potion_hp_small", "gem_shadow", "crystal_mana"],
        "npc_affinities": {
            "wandering_merchant": 30,
            "captive_adventurer": 10,
        },
        "floors_cleared": [1, 2, 3, 4, 5],
        "bosses_defeated": ["boss_bone_lord"],
        "active_quest_ids": [],
        "damage_taken_ratio": 0.5,
        "healing_item_usage": 0.3,
        "play_time_minutes": 45.0,
        "consecutive_deaths": 0,
        "rooms_without_rest": 5,
        "elite_kills": 3,
        "secrets_found": 1,
        "current_difficulty": "normal",
    }
