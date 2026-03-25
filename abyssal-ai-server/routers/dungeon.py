"""Dungeon generation API router."""

from fastapi import APIRouter, HTTPException

from models.dungeon import (
    AdaptRequest,
    AdaptResponse,
    DungeonGenerateRequest,
    DungeonGenerateResponse,
)
from services.dungeon_service import DungeonService

router = APIRouter(prefix="/api/dungeon", tags=["dungeon"])

_service = DungeonService()


@router.post("/generate", response_model=DungeonGenerateResponse)
async def generate_dungeon(req: DungeonGenerateRequest) -> DungeonGenerateResponse:
    """Generate a procedural dungeon floor."""
    try:
        return _service.generate_floor(req)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Dungeon generation failed: {e}")


@router.post("/adapt", response_model=AdaptResponse)
async def adapt_difficulty(req: AdaptRequest) -> AdaptResponse:
    """Analyse player behaviour and recommend difficulty adjustments."""
    try:
        return _service.adapt_difficulty(req)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Difficulty adaptation failed: {e}")
