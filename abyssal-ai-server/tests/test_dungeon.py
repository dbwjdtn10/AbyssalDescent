"""Tests for dungeon generation and adaptive difficulty endpoints."""

from __future__ import annotations

from collections import deque

import pytest
from fastapi.testclient import TestClient


# ---------------------------------------------------------------------------
# /api/dungeon/generate
# ---------------------------------------------------------------------------


class TestDungeonGenerate:
    """POST /api/dungeon/generate tests."""

    def test_generate_returns_200(self, client: TestClient, dungeon_request: dict) -> None:
        """Valid request should return HTTP 200."""
        resp = client.post("/api/dungeon/generate", json=dungeon_request)
        assert resp.status_code == 200

    def test_response_has_required_fields(self, client: TestClient, dungeon_request: dict) -> None:
        """Response must contain all DungeonGenerateResponse fields."""
        data = client.post("/api/dungeon/generate", json=dungeon_request).json()
        assert "floor_number" in data
        assert "floor_name" in data
        assert "floor_description" in data
        assert "rooms" in data
        assert "seed" in data

    def test_floor_number_matches_request(self, client: TestClient, dungeon_request: dict) -> None:
        """Returned floor_number must equal the requested floor_number."""
        data = client.post("/api/dungeon/generate", json=dungeon_request).json()
        assert data["floor_number"] == dungeon_request["floor_number"]

    @pytest.mark.parametrize("difficulty", ["easy", "normal", "hard", "nightmare", "abyss"])
    def test_all_difficulty_levels(self, client: TestClient, dungeon_request: dict, difficulty: str) -> None:
        """Each valid difficulty level should produce a successful response."""
        dungeon_request["difficulty"] = difficulty
        resp = client.post("/api/dungeon/generate", json=dungeon_request)
        assert resp.status_code == 200
        data = resp.json()
        assert len(data["rooms"]) >= 5

    @pytest.mark.parametrize("floor", [5, 10, 15, 20])
    def test_boss_floors_have_boss(self, client: TestClient, dungeon_request: dict, floor: int) -> None:
        """Floors divisible by 5 must include boss data."""
        dungeon_request["floor_number"] = floor
        data = client.post("/api/dungeon/generate", json=dungeon_request).json()
        assert data["boss"] is not None, f"Floor {floor} should have a boss"
        assert "boss_id" in data["boss"]
        assert "name" in data["boss"]
        assert "level" in data["boss"]
        assert data["boss"]["phases"] >= 1

    @pytest.mark.parametrize("floor", [1, 2, 3, 4, 6, 7, 11, 13])
    def test_non_boss_floors_have_no_boss(self, client: TestClient, dungeon_request: dict, floor: int) -> None:
        """Non-boss floors should have boss=None."""
        dungeon_request["floor_number"] = floor
        data = client.post("/api/dungeon/generate", json=dungeon_request).json()
        assert data["boss"] is None, f"Floor {floor} should not have a boss"

    def test_seed_reproducibility(self, client: TestClient, dungeon_request: dict) -> None:
        """Same seed and parameters must produce identical output."""
        dungeon_request["seed"] = 12345
        resp1 = client.post("/api/dungeon/generate", json=dungeon_request).json()
        resp2 = client.post("/api/dungeon/generate", json=dungeon_request).json()
        assert resp1["floor_name"] == resp2["floor_name"]
        assert resp1["seed"] == resp2["seed"]
        assert len(resp1["rooms"]) == len(resp2["rooms"])
        for r1, r2 in zip(resp1["rooms"], resp2["rooms"]):
            assert r1["id"] == r2["id"]
            assert r1["type"] == r2["type"]

    def test_room_count_reasonable(self, client: TestClient, dungeon_request: dict) -> None:
        """Generated floor should contain between 5 and 25 rooms."""
        data = client.post("/api/dungeon/generate", json=dungeon_request).json()
        room_count = len(data["rooms"])
        assert 5 <= room_count <= 25, f"Got {room_count} rooms, expected 5-25"

    def test_rooms_have_required_fields(self, client: TestClient, dungeon_request: dict) -> None:
        """Each room should have id, type, shape, size, and connections."""
        data = client.post("/api/dungeon/generate", json=dungeon_request).json()
        for room in data["rooms"]:
            assert "id" in room
            assert "type" in room
            assert "shape" in room
            assert "size" in room
            assert "connections" in room

    def test_entrance_room_exists(self, client: TestClient, dungeon_request: dict) -> None:
        """There should be at least one entrance room."""
        data = client.post("/api/dungeon/generate", json=dungeon_request).json()
        entrance_rooms = [r for r in data["rooms"] if r["type"] == "entrance"]
        assert len(entrance_rooms) >= 1

    def test_first_room_is_entrance(self, client: TestClient, dungeon_request: dict) -> None:
        """The first room in the list should be of type entrance."""
        data = client.post("/api/dungeon/generate", json=dungeon_request).json()
        assert data["rooms"][0]["type"] == "entrance"

    def test_room_connectivity_all_reachable(self, client: TestClient, dungeon_request: dict) -> None:
        """All rooms must be reachable from the entrance via BFS."""
        data = client.post("/api/dungeon/generate", json=dungeon_request).json()
        rooms = data["rooms"]
        if len(rooms) <= 1:
            return

        # Build adjacency map
        adjacency: dict[str, set[str]] = {r["id"]: set() for r in rooms}
        for room in rooms:
            for conn in room["connections"]:
                adjacency[room["id"]].add(conn["target_room_id"])

        # BFS from first room (entrance)
        visited: set[str] = set()
        queue: deque[str] = deque([rooms[0]["id"]])
        while queue:
            current = queue.popleft()
            if current in visited:
                continue
            visited.add(current)
            for neighbour in adjacency.get(current, []):
                if neighbour not in visited:
                    queue.append(neighbour)

        all_ids = {r["id"] for r in rooms}
        unreachable = all_ids - visited
        assert len(unreachable) == 0, f"Unreachable rooms: {unreachable}"

    def test_environmental_effect_intensity_capped(self, client: TestClient, dungeon_request: dict) -> None:
        """All environmental effect intensities must be in [0.0, 1.0]."""
        data = client.post("/api/dungeon/generate", json=dungeon_request).json()
        for room in data["rooms"]:
            for env in room.get("environmental", []):
                assert 0.0 <= env["intensity"] <= 1.0, (
                    f"Room {room['id']}: intensity {env['intensity']} out of range"
                )

    def test_boss_floor_has_boss_room_type(self, client: TestClient, dungeon_request: dict) -> None:
        """Boss floors should contain at least one room with type='boss'."""
        dungeon_request["floor_number"] = 5
        data = client.post("/api/dungeon/generate", json=dungeon_request).json()
        boss_rooms = [r for r in data["rooms"] if r["type"] == "boss"]
        assert len(boss_rooms) >= 1

    def test_boss_is_last_room(self, client: TestClient, dungeon_request: dict) -> None:
        """On boss floors the boss room should be the last room."""
        dungeon_request["floor_number"] = 10
        data = client.post("/api/dungeon/generate", json=dungeon_request).json()
        assert data["rooms"][-1]["type"] == "boss"


# ---------------------------------------------------------------------------
# /api/dungeon/adapt
# ---------------------------------------------------------------------------


class TestDungeonAdapt:
    """POST /api/dungeon/adapt tests."""

    def test_adapt_returns_200(self, client: TestClient, adapt_request_struggling: dict) -> None:
        """Valid adapt request should return HTTP 200."""
        resp = client.post("/api/dungeon/adapt", json=adapt_request_struggling)
        assert resp.status_code == 200

    def test_adapt_response_has_required_fields(self, client: TestClient, adapt_request_struggling: dict) -> None:
        """Response body must contain all AdaptResponse fields."""
        data = client.post("/api/dungeon/adapt", json=adapt_request_struggling).json()
        required = [
            "recommended_difficulty",
            "monster_level_offset",
            "monster_count_multiplier",
            "trap_frequency",
            "loot_quality_bonus",
            "healing_item_frequency",
            "reason",
        ]
        for field in required:
            assert field in data, f"Missing field: {field}"

    def test_struggling_player_gets_easier_difficulty(
        self, client: TestClient, adapt_request_struggling: dict
    ) -> None:
        """A struggling player (many deaths, high damage taken) should get
        a difficulty equal to or lower than the current difficulty."""
        data = client.post("/api/dungeon/adapt", json=adapt_request_struggling).json()
        difficulties = ["easy", "normal", "hard", "nightmare", "abyss"]
        current_idx = difficulties.index(adapt_request_struggling["current_difficulty"])
        recommended_idx = difficulties.index(data["recommended_difficulty"])
        assert recommended_idx <= current_idx, (
            f"Expected {data['recommended_difficulty']} <= "
            f"{adapt_request_struggling['current_difficulty']}"
        )

    def test_skilled_player_gets_harder_difficulty(
        self, client: TestClient, adapt_request_skilled: dict
    ) -> None:
        """A skilled player (no deaths, low damage) should get a difficulty
        equal to or higher than the current difficulty."""
        data = client.post("/api/dungeon/adapt", json=adapt_request_skilled).json()
        difficulties = ["easy", "normal", "hard", "nightmare", "abyss"]
        current_idx = difficulties.index(adapt_request_skilled["current_difficulty"])
        recommended_idx = difficulties.index(data["recommended_difficulty"])
        assert recommended_idx >= current_idx

    def test_monster_count_multiplier_in_range(
        self, client: TestClient, adapt_request_struggling: dict
    ) -> None:
        """monster_count_multiplier must be within [0.5, 2.0]."""
        data = client.post("/api/dungeon/adapt", json=adapt_request_struggling).json()
        assert 0.5 <= data["monster_count_multiplier"] <= 2.0

    def test_trap_frequency_in_range(self, client: TestClient, adapt_request_skilled: dict) -> None:
        """trap_frequency must be within [0.0, 1.0]."""
        data = client.post("/api/dungeon/adapt", json=adapt_request_skilled).json()
        assert 0.0 <= data["trap_frequency"] <= 1.0

    def test_loot_quality_bonus_in_range(self, client: TestClient, adapt_request_skilled: dict) -> None:
        """loot_quality_bonus must be within [0.0, 1.0]."""
        data = client.post("/api/dungeon/adapt", json=adapt_request_skilled).json()
        assert 0.0 <= data["loot_quality_bonus"] <= 1.0

    def test_healing_item_frequency_in_range(
        self, client: TestClient, adapt_request_struggling: dict
    ) -> None:
        """healing_item_frequency must be within [0.0, 1.0]."""
        data = client.post("/api/dungeon/adapt", json=adapt_request_struggling).json()
        assert 0.0 <= data["healing_item_frequency"] <= 1.0

    def test_reason_is_nonempty_string(self, client: TestClient, adapt_request_struggling: dict) -> None:
        """The reason field should be a non-empty string."""
        data = client.post("/api/dungeon/adapt", json=adapt_request_struggling).json()
        assert isinstance(data["reason"], str)
        assert len(data["reason"]) > 0
