"""Pydantic models for content generation API (items, quests)."""

from __future__ import annotations

from enum import Enum
from pydantic import BaseModel, Field


# ---------- Item models ----------

class ItemRarity(str, Enum):
    COMMON = "common"
    UNCOMMON = "uncommon"
    RARE = "rare"
    EPIC = "epic"
    LEGENDARY = "legendary"
    ABYSSAL = "abyssal"


class ItemType(str, Enum):
    WEAPON = "weapon"
    ARMOR = "armor"
    ACCESSORY = "accessory"
    CONSUMABLE = "consumable"
    MATERIAL = "material"
    KEY_ITEM = "key_item"
    SCROLL = "scroll"
    RUNE = "rune"


class ItemStat(BaseModel):
    """A single stat modifier on an item."""
    stat_name: str  # "attack", "defense", "hp", "speed", "crit_rate", etc.
    value: float
    is_percentage: bool = False


class ItemEffect(BaseModel):
    """A special effect an item can have."""
    effect_name: str
    description: str
    trigger: str = "on_use"  # "on_use", "on_hit", "passive", "on_equip"
    duration_seconds: float = 0.0
    cooldown_seconds: float = 0.0


class ItemGenerateRequest(BaseModel):
    """Request body for item generation."""
    floor_number: int = Field(ge=1, le=100, default=1)
    rarity: ItemRarity = ItemRarity.COMMON
    item_type: ItemType | None = None
    context: str = Field(default="", description="Contextual info, e.g. 'dropped by fire boss'")


class ItemGenerateResponse(BaseModel):
    """Response body for item generation."""
    item_id: str
    name: str
    item_type: ItemType
    rarity: ItemRarity
    description: str
    lore: str = ""
    level_requirement: int = 1
    stats: list[ItemStat] = []
    effects: list[ItemEffect] = []
    icon_hint: str = ""  # Hint for which icon to use on client side
    sell_price: int = 0


# ---------- Quest models ----------

class QuestType(str, Enum):
    KILL = "kill"
    COLLECT = "collect"
    EXPLORE = "explore"
    ESCORT = "escort"
    DELIVER = "deliver"
    PUZZLE = "puzzle"
    BOSS = "boss"
    HIDDEN = "hidden"


class QuestObjective(BaseModel):
    """A single objective within a quest."""
    objective_id: str
    description: str
    target: str  # target monster/item/location id
    required_count: int = 1
    current_count: int = 0
    is_complete: bool = False


class QuestReward(BaseModel):
    """A reward for completing a quest."""
    reward_type: str  # "gold", "exp", "item", "affinity", "unlock"
    value: str  # amount or item_id
    description: str = ""


class QuestDialogue(BaseModel):
    """Dialogue lines associated with quest stages."""
    stage: str  # "start", "progress", "complete", "fail"
    npc_id: str
    text: str


class QuestGenerateRequest(BaseModel):
    """Request body for quest generation."""
    trigger: str = Field(description="What triggered this quest, e.g. 'npc_conversation', 'item_found', 'floor_enter'")
    npc_id: str | None = None
    player_state: dict = Field(default_factory=dict)


class QuestGenerateResponse(BaseModel):
    """Response body for quest generation."""
    quest_id: str
    title: str
    description: str
    type: QuestType
    objectives: list[QuestObjective]
    rewards: list[QuestReward]
    dialogues: list[QuestDialogue] = []
    time_limit_seconds: int | None = None
    is_hidden: bool = False
    lore: str = ""
