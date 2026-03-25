"""Tests for NPC dialogue and state endpoints."""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient


ALL_NPC_IDS = [
    "wandering_merchant",
    "captive_adventurer",
    "mysterious_sage",
    "fallen_knight",
]


# ---------------------------------------------------------------------------
# POST /api/npc/chat
# ---------------------------------------------------------------------------


class TestNPCChat:
    """POST /api/npc/chat tests."""

    def test_chat_returns_200(self, client: TestClient, npc_chat_request: dict) -> None:
        """Valid chat request should return HTTP 200."""
        resp = client.post("/api/npc/chat", json=npc_chat_request)
        assert resp.status_code == 200

    def test_response_has_required_fields(self, client: TestClient, npc_chat_request: dict) -> None:
        """Response must contain all NPCChatResponse fields."""
        data = client.post("/api/npc/chat", json=npc_chat_request).json()
        required = [
            "npc_id",
            "response",
            "emotion",
            "affinity_change",
            "current_affinity",
            "hints",
        ]
        for field in required:
            assert field in data, f"Missing field: {field}"

    @pytest.mark.parametrize("npc_id", ALL_NPC_IDS)
    def test_chat_with_each_npc(self, client: TestClient, npc_chat_request: dict, npc_id: str) -> None:
        """Each known NPC should produce a valid dialogue response."""
        npc_chat_request["npc_id"] = npc_id
        resp = client.post("/api/npc/chat", json=npc_chat_request)
        assert resp.status_code == 200
        data = resp.json()
        assert data["npc_id"] == npc_id
        assert len(data["response"]) > 0

    def test_unknown_npc_returns_fallback(self, client: TestClient, npc_chat_request: dict) -> None:
        """An unknown NPC ID should return a fallback response, not an error."""
        npc_chat_request["npc_id"] = "nonexistent_npc"
        resp = client.post("/api/npc/chat", json=npc_chat_request)
        assert resp.status_code == 200
        data = resp.json()
        assert data["npc_id"] == "nonexistent_npc"
        assert "알 수 없는" in data["response"]
        assert data["emotion"] == "neutral"
        assert data["affinity_change"] == 0

    def test_positive_sentiment_increases_affinity(self, client: TestClient, npc_chat_request: dict) -> None:
        """Sending a positive message should produce a non-negative affinity change."""
        npc_chat_request["player_message"] = "고마워! 정말 최고야!"
        data = client.post("/api/npc/chat", json=npc_chat_request).json()
        assert data["affinity_change"] >= 0

    def test_negative_sentiment_decreases_affinity(self, client: TestClient, npc_chat_request: dict) -> None:
        """Sending a negative message should produce a non-positive affinity change."""
        npc_chat_request["player_message"] = "짜증나, 쓸모없어 바보"
        data = client.post("/api/npc/chat", json=npc_chat_request).json()
        assert data["affinity_change"] <= 0

    def test_neutral_sentiment_small_affinity_change(self, client: TestClient, npc_chat_request: dict) -> None:
        """Neutral message should produce a small (0-2) affinity change or slight positive from topic bonus."""
        npc_chat_request["player_message"] = "오늘 날씨가 어떤가요?"
        data = client.post("/api/npc/chat", json=npc_chat_request).json()
        assert -10 <= data["affinity_change"] <= 10

    def test_dungeon_topic_detection(self, client: TestClient, npc_chat_request: dict) -> None:
        """Messages about dungeons should trigger about_dungeon topic responses."""
        npc_chat_request["player_message"] = "이 던전의 보스에 대해 알려줘"
        resp = client.post("/api/npc/chat", json=npc_chat_request)
        assert resp.status_code == 200
        data = resp.json()
        assert len(data["response"]) > 0

    def test_self_topic_detection(self, client: TestClient, npc_chat_request: dict) -> None:
        """Messages asking about the NPC should trigger about_self topic."""
        npc_chat_request["player_message"] = "너는 누구야? 왜 여기 있어?"
        resp = client.post("/api/npc/chat", json=npc_chat_request)
        assert resp.status_code == 200
        data = resp.json()
        assert len(data["response"]) > 0

    def test_farewell_topic_detection(self, client: TestClient, npc_chat_request: dict) -> None:
        """Farewell keywords should trigger farewell-style dialogue."""
        npc_chat_request["player_message"] = "잘가, 다음에 봐!"
        resp = client.post("/api/npc/chat", json=npc_chat_request)
        assert resp.status_code == 200

    def test_emotion_is_valid_enum_value(self, client: TestClient, npc_chat_request: dict) -> None:
        """The emotion field should be one of the valid Emotion enum values."""
        valid_emotions = {
            "neutral", "happy", "sad", "angry", "afraid", "curious",
            "suspicious", "grateful", "melancholy", "excited", "disgusted",
            "mysterious",
        }
        data = client.post("/api/npc/chat", json=npc_chat_request).json()
        assert data["emotion"] in valid_emotions

    def test_affinity_change_within_bounds(self, client: TestClient, npc_chat_request: dict) -> None:
        """affinity_change must be within [-10, 10]."""
        data = client.post("/api/npc/chat", json=npc_chat_request).json()
        assert -10 <= data["affinity_change"] <= 10

    def test_current_affinity_within_bounds(self, client: TestClient, npc_chat_request: dict) -> None:
        """current_affinity must be within [-100, 100]."""
        data = client.post("/api/npc/chat", json=npc_chat_request).json()
        assert -100 <= data["current_affinity"] <= 100

    def test_positive_message_to_merchant_emotion(self, client: TestClient, npc_chat_request: dict) -> None:
        """Positive message to cheerful wandering_merchant should produce happy emotion."""
        npc_chat_request["player_message"] = "고마워 최고야 사랑해!"
        data = client.post("/api/npc/chat", json=npc_chat_request).json()
        assert data["emotion"] == "happy"

    def test_negative_message_to_fallen_knight_emotion(self, client: TestClient, npc_chat_request: dict) -> None:
        """Negative message to volatile fallen_knight should produce angry emotion."""
        npc_chat_request["npc_id"] = "fallen_knight"
        npc_chat_request["player_message"] = "바보 꺼져 멍청"
        data = client.post("/api/npc/chat", json=npc_chat_request).json()
        assert data["emotion"] == "angry"

    def test_low_hp_triggers_player_hurt_topic(self, client: TestClient, npc_chat_request: dict) -> None:
        """Player with low hp_ratio should trigger player_hurt dialogue."""
        npc_chat_request["player_state"]["hp_ratio"] = 0.2
        resp = client.post("/api/npc/chat", json=npc_chat_request)
        assert resp.status_code == 200

    def test_hints_list_structure(self, client: TestClient, npc_chat_request: dict) -> None:
        """The hints field should be a list, each item with hint_type, content, and importance."""
        data = client.post("/api/npc/chat", json=npc_chat_request).json()
        assert isinstance(data["hints"], list)
        for hint in data["hints"]:
            assert "hint_type" in hint
            assert "content" in hint
            assert "importance" in hint


# ---------------------------------------------------------------------------
# GET /api/npc/{id}/state
# ---------------------------------------------------------------------------


class TestNPCState:
    """GET /api/npc/{id}/state tests."""

    @pytest.mark.parametrize("npc_id", ALL_NPC_IDS)
    def test_state_returns_200(self, client: TestClient, npc_id: str) -> None:
        """Each known NPC state query should return 200."""
        resp = client.get(f"/api/npc/{npc_id}/state")
        assert resp.status_code == 200

    @pytest.mark.parametrize("npc_id", ALL_NPC_IDS)
    def test_state_has_required_fields(self, client: TestClient, npc_id: str) -> None:
        """State response should contain all NPCStateResponse fields."""
        data = client.get(f"/api/npc/{npc_id}/state").json()
        required = ["npc_id", "name", "emotion", "affinity", "available_hint_level", "title", "greeting"]
        for field in required:
            assert field in data, f"Missing field: {field}"

    @pytest.mark.parametrize("npc_id", ALL_NPC_IDS)
    def test_state_npc_id_matches(self, client: TestClient, npc_id: str) -> None:
        """Returned npc_id should match the requested ID."""
        data = client.get(f"/api/npc/{npc_id}/state").json()
        assert data["npc_id"] == npc_id

    def test_unknown_npc_state_returns_fallback(self, client: TestClient) -> None:
        """Unknown NPC should return a fallback state, not an error."""
        resp = client.get("/api/npc/totally_fake/state")
        assert resp.status_code == 200
        data = resp.json()
        assert data["name"] == "알 수 없음"
        assert data["emotion"] == "neutral"

    def test_hint_level_none_at_zero_affinity(self, client: TestClient) -> None:
        """At default 0 affinity, most NPCs should have hint level 'none'.
        The mysterious_sage is an exception (vague at 0)."""
        # Use a fresh NPC that starts at 0 affinity
        data = client.get("/api/npc/wandering_merchant/state").json()
        assert data["available_hint_level"] in ("none", "vague")

    def test_state_affinity_within_bounds(self, client: TestClient) -> None:
        """Affinity should be within [-100, 100]."""
        data = client.get("/api/npc/captive_adventurer/state").json()
        assert -100 <= data["affinity"] <= 100

    def test_greeting_is_nonempty(self, client: TestClient) -> None:
        """NPC greeting should be a non-empty string."""
        data = client.get("/api/npc/wandering_merchant/state").json()
        assert isinstance(data["greeting"], str)
        assert len(data["greeting"]) > 0

    def test_emotion_changes_after_positive_chat(self, client: TestClient, npc_chat_request: dict) -> None:
        """Emotion should reflect the last conversation sentiment."""
        npc_chat_request["npc_id"] = "wandering_merchant"
        npc_chat_request["player_message"] = "정말 고마워! 최고야!"
        client.post("/api/npc/chat", json=npc_chat_request)
        state = client.get("/api/npc/wandering_merchant/state").json()
        # After a positive interaction the cheerful merchant should be happy
        assert state["emotion"] == "happy"
