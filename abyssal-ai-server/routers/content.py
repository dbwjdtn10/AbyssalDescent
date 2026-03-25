"""Content generation API router (items, quests)."""

from fastapi import APIRouter, HTTPException

from models.content import (
    ItemGenerateRequest,
    ItemGenerateResponse,
    QuestGenerateRequest,
    QuestGenerateResponse,
)
from services.content_service import ContentService

router = APIRouter(prefix="/api/content", tags=["content"])

_service = ContentService()


@router.post("/item", response_model=ItemGenerateResponse)
async def generate_item(req: ItemGenerateRequest) -> ItemGenerateResponse:
    """Generate a random item based on floor and rarity."""
    try:
        return _service.generate_item(req)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Item generation failed: {e}")


@router.post("/quest", response_model=QuestGenerateResponse)
async def generate_quest(req: QuestGenerateRequest) -> QuestGenerateResponse:
    """Generate a quest from templates, optionally tied to an NPC."""
    try:
        return _service.generate_quest(req)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Quest generation failed: {e}")
