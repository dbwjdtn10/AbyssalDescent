"""NPC dialogue API router."""

import logging

from fastapi import APIRouter, Header, HTTPException

from models.npc import NPCChatRequest, NPCChatResponse, NPCStateResponse
from services.npc_service import NPCService
from services.security_service import security_service

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/npc", tags=["npc"])

_service = NPCService()


@router.post("/chat", response_model=NPCChatResponse)
async def chat_with_npc(
    req: NPCChatRequest,
    x_api_key: str | None = Header(None, alias="X-API-Key"),
) -> NPCChatResponse:
    """NPC에게 메시지를 보내고 응답을 받습니다."""
    logger.info(
        "NPC chat request: npc_id=%s message_len=%d floor=%d",
        req.npc_id,
        len(req.player_message),
        req.player_state.current_floor,
    )

    # Router-level security pre-check (service has its own deeper check)
    violation = security_service.get_violation_type(req.player_message)
    if violation is not None:
        logger.warning(
            "Router-level security block for NPC %s: violation=%s",
            req.npc_id,
            violation,
        )

    try:
        return _service.chat(req, client_api_key=x_api_key)
    except Exception as e:
        logger.exception("NPC chat failed for npc_id=%s", req.npc_id)
        raise HTTPException(status_code=500, detail=f"NPC chat failed: {e}")


@router.get("/{npc_id}/state", response_model=NPCStateResponse)
async def get_npc_state(npc_id: str) -> NPCStateResponse:
    """NPC의 현재 감정 및 호감도 상태를 조회합니다."""
    logger.info("NPC state request: npc_id=%s", npc_id)
    try:
        return _service.get_state(npc_id)
    except Exception as e:
        logger.exception("NPC state query failed for npc_id=%s", npc_id)
        raise HTTPException(status_code=500, detail=f"NPC state query failed: {e}")
