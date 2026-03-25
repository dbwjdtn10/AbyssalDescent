"""Pydantic models for quest trigger and game state analysis API."""

from __future__ import annotations

from pydantic import BaseModel, Field

from models.content import QuestGenerateResponse
from models.dungeon import AdaptResponse, Difficulty


class GameState(BaseModel):
    """Full snapshot of the current game state sent by the client."""

    player_id: str = "player_1"
    player_level: int = Field(ge=1, le=100, default=1)
    current_floor: int = Field(ge=1, le=100, default=1)
    deaths: int = Field(ge=0, default=0)
    total_kills: int = Field(ge=0, default=0)
    exploration_rate: float = Field(ge=0.0, le=1.0, default=0.5, description="탐색한 방 비율 (0.0~1.0)")
    hp_ratio: float = Field(ge=0.0, le=1.0, default=1.0, description="현재 체력 비율")
    gold: int = Field(ge=0, default=0)
    inventory: list[str] = Field(default_factory=list, description="보유 아이템 ID 목록")
    npc_affinities: dict[str, int] = Field(default_factory=dict, description="NPC 호감도 (npc_id -> 수치)")
    floors_cleared: list[int] = Field(default_factory=list, description="클리어한 층 목록")
    bosses_defeated: list[str] = Field(default_factory=list, description="처치한 보스 ID 목록")
    active_quest_ids: list[str] = Field(default_factory=list, description="진행 중인 퀘스트 ID (중복 방지)")
    damage_taken_ratio: float = Field(ge=0.0, le=1.0, default=0.5, description="평균 피해 비율")
    healing_item_usage: float = Field(ge=0.0, le=1.0, default=0.3, description="힐링 아이템 사용률")
    play_time_minutes: float = Field(ge=0.0, default=0.0, description="총 플레이 시간(분)")
    consecutive_deaths: int = Field(ge=0, default=0, description="연속 사망 횟수")
    rooms_without_rest: int = Field(ge=0, default=0, description="휴식 없이 탐험한 방 수")
    elite_kills: int = Field(ge=0, default=0, description="정예 몬스터 처치 수")
    secrets_found: int = Field(ge=0, default=0, description="발견한 비밀 방 수")
    current_difficulty: Difficulty = Field(default=Difficulty.NORMAL, description="현재 난이도")


class TriggeredQuest(BaseModel):
    """A quest that was triggered by game state analysis."""

    trigger_type: str = Field(description="트리거 종류 (예: npc_affinity, death_count, ...)")
    priority: int = Field(ge=1, le=5, description="우선순위 (5가 가장 높음)")
    quest: QuestGenerateResponse = Field(description="생성된 퀘스트 데이터")
    context_message: str = Field(description="이 퀘스트가 나타난 이유 (한국어)")


class QuestTriggerResponse(BaseModel):
    """Full response for game state analysis."""

    triggered_quests: list[TriggeredQuest] = Field(default_factory=list)
    difficulty_adjustment: dict = Field(default_factory=dict, description="난이도 조정 결과 (AdaptResponse)")
    game_tips: list[str] = Field(default_factory=list, description="상황별 게임 팁 (한국어)")
