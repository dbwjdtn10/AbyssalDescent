"""WebSocket router for real-time NPC dialogue streaming."""

from __future__ import annotations

import asyncio
import json
import logging

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from config import get_settings
from models.npc import NPCChatRequest, PlayerState, ChatMessage
from services.llm_service import LLMService
from services.npc_service import NPCService, NPC_DATA

logger = logging.getLogger(__name__)

router = APIRouter(tags=["websocket"])

# Shared NPC service instance (same in-memory state across WS connections)
_service = NPCService()

# Initialize standalone LLM service for WebSocket streaming
_settings = get_settings()
_llm = LLMService(
    api_key=_settings.anthropic_api_key if _settings.llm_enabled else "",
    model=_settings.llm_model,
    temperature=_settings.llm_temperature,
    max_tokens=_settings.llm_max_tokens,
) if _settings.llm_enabled else LLMService()

# Streaming delay per character in seconds (configurable)
CHAR_STREAM_DELAY: float = 0.03


@router.websocket("/ws/npc/chat")
async def ws_npc_chat(websocket: WebSocket) -> None:
    """Stream NPC dialogue responses character by character over WebSocket.

    Expected incoming JSON format (same as POST /api/npc/chat):
        {
            "npc_id": "wandering_merchant",
            "player_message": "...",
            "player_state": {"level": 1, "current_floor": 1, ...},
            "conversation_history": [...]
        }

    Outgoing frames:
        {"type": "start",  "npc_id": "...", "emotion": "..."}
        {"type": "token",  "content": "<single character>"}   (repeated)
        {"type": "end",    "emotion": "...", "affinity_change": N,
                           "current_affinity": N, "hints": [...]}
    """
    await websocket.accept()
    logger.info("WebSocket connected: %s", websocket.client)

    try:
        while True:
            raw = await websocket.receive_text()

            # --- Parse incoming message ---
            try:
                payload = json.loads(raw)
            except json.JSONDecodeError as exc:
                await websocket.send_json(
                    {"type": "error", "detail": f"Invalid JSON: {exc}"}
                )
                logger.warning("WebSocket received invalid JSON from %s", websocket.client)
                continue

            # --- Build NPCChatRequest from payload ---
            try:
                req = NPCChatRequest(
                    npc_id=payload.get("npc_id", ""),
                    player_message=payload.get("player_message", ""),
                    player_state=PlayerState(**payload.get("player_state", {})),
                    conversation_history=[
                        ChatMessage(**m)
                        for m in payload.get("conversation_history", [])
                    ],
                )
            except Exception as exc:
                await websocket.send_json(
                    {"type": "error", "detail": f"Invalid request payload: {exc}"}
                )
                logger.warning("WebSocket bad payload from %s: %s", websocket.client, exc)
                continue

            # --- Generate full response via NPCService ---
            try:
                result = _service.chat(req)
            except Exception as exc:
                await websocket.send_json(
                    {"type": "error", "detail": f"NPC service error: {exc}"}
                )
                logger.error("NPCService error for %s: %s", req.npc_id, exc)
                continue

            # --- Stream: start frame ---
            await websocket.send_json({
                "type": "start",
                "npc_id": result.npc_id,
                "emotion": result.emotion.value,
            })

            # --- Stream: token frames ---
            # Try LLM streaming first; fall back to character-by-character simulation
            streamed_via_llm = False
            npc_data = NPC_DATA.get(req.npc_id)
            if _llm.is_enabled and npc_data is not None:
                try:
                    streamed_text_len = 0
                    for token in _llm.generate_npc_response_stream(
                        npc_name=npc_data["name"],
                        npc_persona=npc_data["persona"],
                        npc_speech_style=npc_data["speech_style"],
                        npc_knowledge=npc_data["knowledge"],
                        player_message=req.player_message,
                        conversation_history=[
                            m.model_dump() for m in req.conversation_history
                        ],
                        player_state=req.player_state.model_dump(),
                        affinity=result.current_affinity,
                        hint_level=_service._get_hint_level(req.npc_id).value,
                    ):
                        await websocket.send_json({
                            "type": "token",
                            "content": token,
                        })
                        streamed_text_len += len(token)
                    if streamed_text_len > 0:
                        streamed_via_llm = True
                        logger.info(
                            "WebSocket LLM-streamed response for NPC %s (%d chars) to %s",
                            result.npc_id, streamed_text_len, websocket.client,
                        )
                except Exception as exc:
                    logger.warning(
                        "LLM streaming failed for NPC %s, falling back to template: %s",
                        req.npc_id, exc,
                    )

            # Fall back to character-by-character streaming from the template response
            if not streamed_via_llm:
                for char in result.response:
                    await websocket.send_json({
                        "type": "token",
                        "content": char,
                    })
                    await asyncio.sleep(CHAR_STREAM_DELAY)

                logger.info(
                    "WebSocket template-streamed response for NPC %s (%d chars) to %s",
                    result.npc_id,
                    len(result.response),
                    websocket.client,
                )

            # --- Stream: end frame ---
            await websocket.send_json({
                "type": "end",
                "emotion": result.emotion.value,
                "affinity_change": result.affinity_change,
                "current_affinity": result.current_affinity,
                "hints": [h.model_dump() for h in result.hints],
            })

    except WebSocketDisconnect:
        logger.info("WebSocket disconnected: %s", websocket.client)
    except Exception as exc:
        logger.error("WebSocket unexpected error for %s: %s", websocket.client, exc)
        try:
            await websocket.close(code=1011, reason=str(exc))
        except Exception:
            pass
