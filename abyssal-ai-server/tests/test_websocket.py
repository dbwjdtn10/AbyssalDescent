"""Tests for WebSocket NPC chat streaming at /ws/npc/chat."""

from __future__ import annotations

import json

import pytest
from fastapi.testclient import TestClient


class TestWebSocketNPCChat:
    """WebSocket /ws/npc/chat tests."""

    def test_websocket_connection(self, client: TestClient) -> None:
        """WebSocket should accept connections."""
        with client.websocket_connect("/ws/npc/chat") as ws:
            # If we get here without error, connection succeeded
            pass

    def test_streaming_frame_order(self, client: TestClient) -> None:
        """Frames should arrive in order: start, token(s), end."""
        with client.websocket_connect("/ws/npc/chat") as ws:
            ws.send_json({
                "npc_id": "wandering_merchant",
                "player_message": "안녕!",
                "player_state": {"level": 1, "current_floor": 1},
                "conversation_history": [],
            })

            frames: list[dict] = []
            # Collect all frames until we see "end"
            while True:
                frame = ws.receive_json()
                frames.append(frame)
                if frame.get("type") == "end":
                    break

            assert len(frames) >= 3, "Expected at least start, one token, and end"
            assert frames[0]["type"] == "start"
            assert frames[-1]["type"] == "end"

            # All middle frames should be tokens
            for f in frames[1:-1]:
                assert f["type"] == "token"

    def test_start_frame_content(self, client: TestClient) -> None:
        """Start frame should contain npc_id and emotion."""
        with client.websocket_connect("/ws/npc/chat") as ws:
            ws.send_json({
                "npc_id": "wandering_merchant",
                "player_message": "안녕!",
                "player_state": {},
                "conversation_history": [],
            })

            frame = ws.receive_json()
            assert frame["type"] == "start"
            assert frame["npc_id"] == "wandering_merchant"
            assert "emotion" in frame

    def test_token_frames_have_content(self, client: TestClient) -> None:
        """Each token frame should have a non-empty content field."""
        with client.websocket_connect("/ws/npc/chat") as ws:
            ws.send_json({
                "npc_id": "captive_adventurer",
                "player_message": "무슨 이야기를 해줄래?",
                "player_state": {"level": 5, "current_floor": 3},
                "conversation_history": [],
            })

            saw_token = False
            while True:
                frame = ws.receive_json()
                if frame["type"] == "token":
                    saw_token = True
                    assert "content" in frame
                    assert len(frame["content"]) == 1  # single character
                if frame["type"] == "end":
                    break

            assert saw_token, "Should have received at least one token frame"

    def test_end_frame_content(self, client: TestClient) -> None:
        """End frame should contain emotion, affinity_change, current_affinity, and hints."""
        with client.websocket_connect("/ws/npc/chat") as ws:
            ws.send_json({
                "npc_id": "mysterious_sage",
                "player_message": "이 심연은 뭐야?",
                "player_state": {},
                "conversation_history": [],
            })

            end_frame = None
            while True:
                frame = ws.receive_json()
                if frame["type"] == "end":
                    end_frame = frame
                    break

            assert end_frame is not None
            assert "emotion" in end_frame
            assert "affinity_change" in end_frame
            assert "current_affinity" in end_frame
            assert "hints" in end_frame

    def test_response_reconstructed_matches_npc(self, client: TestClient) -> None:
        """Concatenating token contents should produce the full NPC response."""
        with client.websocket_connect("/ws/npc/chat") as ws:
            ws.send_json({
                "npc_id": "fallen_knight",
                "player_message": "안녕",
                "player_state": {},
                "conversation_history": [],
            })

            chars: list[str] = []
            npc_id_from_start = None
            while True:
                frame = ws.receive_json()
                if frame["type"] == "start":
                    npc_id_from_start = frame["npc_id"]
                elif frame["type"] == "token":
                    chars.append(frame["content"])
                elif frame["type"] == "end":
                    break

            full_text = "".join(chars)
            assert len(full_text) > 0, "Full response text should not be empty"
            assert npc_id_from_start == "fallen_knight"

    def test_invalid_json_returns_error(self, client: TestClient) -> None:
        """Sending invalid JSON should return an error frame, not crash."""
        with client.websocket_connect("/ws/npc/chat") as ws:
            ws.send_text("this is not json{{{")
            frame = ws.receive_json()
            assert frame["type"] == "error"
            assert "Invalid JSON" in frame["detail"]

    def test_missing_required_fields_returns_error(self, client: TestClient) -> None:
        """Sending JSON missing required fields should return an error frame."""
        with client.websocket_connect("/ws/npc/chat") as ws:
            # Send valid JSON but missing player_message (min_length=1)
            ws.send_json({
                "npc_id": "wandering_merchant",
                # player_message omitted
            })
            frame = ws.receive_json()
            assert frame["type"] == "error"
            assert "detail" in frame

    def test_empty_player_message_returns_error(self, client: TestClient) -> None:
        """Empty player_message (violates min_length=1) should return error."""
        with client.websocket_connect("/ws/npc/chat") as ws:
            ws.send_json({
                "npc_id": "wandering_merchant",
                "player_message": "",
                "player_state": {},
                "conversation_history": [],
            })
            frame = ws.receive_json()
            assert frame["type"] == "error"

    def test_multiple_messages_in_session(self, client: TestClient) -> None:
        """Multiple messages in a single WebSocket session should all get responses."""
        with client.websocket_connect("/ws/npc/chat") as ws:
            for msg in ["안녕!", "던전에 대해 알려줘", "잘가!"]:
                ws.send_json({
                    "npc_id": "wandering_merchant",
                    "player_message": msg,
                    "player_state": {},
                    "conversation_history": [],
                })

                # Drain all frames until "end"
                got_end = False
                while True:
                    frame = ws.receive_json()
                    if frame["type"] == "end":
                        got_end = True
                        break
                assert got_end, f"Expected end frame for message: {msg}"
