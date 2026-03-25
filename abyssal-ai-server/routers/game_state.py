"""Game state analysis API router — quest triggers and difficulty adjustment."""

from fastapi import APIRouter, HTTPException

from models.dungeon import AdaptRequest, Difficulty
from models.quest_trigger import GameState, QuestTriggerResponse, TriggeredQuest
from services.dungeon_service import DungeonService
from services.game_tips_service import GameTipsService
from services.quest_trigger_service import QuestTriggerService

router = APIRouter(prefix="/api/game", tags=["game"])

_quest_trigger_service = QuestTriggerService()
_dungeon_service = DungeonService()
_tips_service = GameTipsService()


@router.post("/analyze", response_model=QuestTriggerResponse)
async def analyze_game_state(game_state: GameState) -> QuestTriggerResponse:
    """Analyze current game state and return triggered quests, difficulty
    adjustment, and contextual tips.

    This is the main endpoint for the client to call periodically (e.g. on
    floor change, after combat, on NPC interaction) to receive dynamic
    content suggestions.
    """
    try:
        # 1. Check quest triggers
        triggered_quests = _quest_trigger_service.check_triggers(game_state)

        # 2. Compute adaptive difficulty
        adapt_req = AdaptRequest(
            player_id=game_state.player_id,
            floor_number=game_state.current_floor,
            deaths=game_state.deaths,
            average_clear_time_seconds=0.0,  # client can extend later
            damage_taken_ratio=game_state.damage_taken_ratio,
            healing_item_usage=game_state.healing_item_usage,
            exploration_rate=game_state.exploration_rate,
            player_level=game_state.player_level,
            current_difficulty=game_state.current_difficulty,
        )
        adapt_response = _dungeon_service.adapt_difficulty(adapt_req)

        # 3. Generate contextual tips
        tips = _tips_service.get_tips(game_state)

        return QuestTriggerResponse(
            triggered_quests=triggered_quests,
            difficulty_adjustment=adapt_response.model_dump(),
            game_tips=tips,
        )
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Game state analysis failed: {e}",
        )


@router.post("/quest/check-triggers", response_model=list[TriggeredQuest])
async def check_quest_triggers(game_state: GameState) -> list[TriggeredQuest]:
    """Check quest triggers only, without difficulty adjustment or tips.

    Lighter-weight endpoint for frequent polling.
    """
    try:
        return _quest_trigger_service.check_triggers(game_state)
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Quest trigger check failed: {e}",
        )
