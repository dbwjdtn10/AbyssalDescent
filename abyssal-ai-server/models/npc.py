"""Pydantic models for NPC dialogue API."""

from __future__ import annotations

from enum import Enum
from pydantic import BaseModel, Field


class Emotion(str, Enum):
    NEUTRAL = "neutral"
    HAPPY = "happy"
    SAD = "sad"
    ANGRY = "angry"
    AFRAID = "afraid"
    CURIOUS = "curious"
    SUSPICIOUS = "suspicious"
    GRATEFUL = "grateful"
    MELANCHOLY = "melancholy"
    EXCITED = "excited"
    DISGUSTED = "disgusted"
    MYSTERIOUS = "mysterious"


class HintLevel(str, Enum):
    NONE = "none"
    VAGUE = "vague"
    MODERATE = "moderate"
    DETAILED = "detailed"
    COMPLETE = "complete"


# ---------- Conversation history ----------

class ChatMessage(BaseModel):
    """A single message in conversation history."""
    role: str = Field(description="'player' or 'npc'")
    content: str
    emotion: Emotion | None = None


class PlayerState(BaseModel):
    """Snapshot of player state sent with chat requests."""
    level: int = 1
    current_floor: int = 1
    inventory: list[str] = Field(default_factory=list)
    hp_ratio: float = Field(ge=0.0, le=1.0, default=1.0)
    gold: int = 0


# ---------- Request / Response ----------

class NPCChatRequest(BaseModel):
    """Request body for NPC conversation."""
    npc_id: str
    player_message: str = Field(min_length=1, max_length=1000)
    player_state: PlayerState = Field(default_factory=PlayerState)
    conversation_history: list[ChatMessage] = Field(default_factory=list)


class Hint(BaseModel):
    """An optional hint the NPC may give."""
    hint_type: str  # "dungeon", "boss", "item", "secret", "lore"
    content: str
    importance: str = "low"  # "low", "medium", "high"


class NPCChatResponse(BaseModel):
    """Response body for NPC conversation."""
    npc_id: str
    response: str
    emotion: Emotion
    affinity_change: int = Field(ge=-10, le=10, default=0)
    current_affinity: int = Field(ge=-100, le=100, default=0)
    hints: list[Hint] = Field(default_factory=list)
    animation_trigger: str | None = None  # For client-side animation cues


class NPCStateResponse(BaseModel):
    """Response body for NPC state query."""
    npc_id: str
    name: str
    emotion: Emotion
    affinity: int = Field(ge=-100, le=100, default=0)
    available_hint_level: HintLevel = HintLevel.NONE
    title: str = ""
    greeting: str = ""
