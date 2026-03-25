"""Pydantic models for dungeon generation API."""

from __future__ import annotations

from enum import Enum
from pydantic import BaseModel, Field


# ---------- Enums ----------

class RoomType(str, Enum):
    ENTRANCE = "entrance"
    CORRIDOR = "corridor"
    COMBAT = "combat"
    TREASURE = "treasure"
    TRAP = "trap"
    PUZZLE = "puzzle"
    REST = "rest"
    SHOP = "shop"
    BOSS = "boss"
    SECRET = "secret"
    EVENT = "event"


class RoomShape(str, Enum):
    RECTANGULAR = "rectangular"
    CIRCULAR = "circular"
    L_SHAPED = "l_shaped"
    CROSS = "cross"
    IRREGULAR = "irregular"


class RoomSize(str, Enum):
    SMALL = "small"
    MEDIUM = "medium"
    LARGE = "large"
    HUGE = "huge"


class Direction(str, Enum):
    NORTH = "north"
    SOUTH = "south"
    EAST = "east"
    WEST = "west"


class Difficulty(str, Enum):
    EASY = "easy"
    NORMAL = "normal"
    HARD = "hard"
    NIGHTMARE = "nightmare"
    ABYSS = "abyss"


class MonsterRank(str, Enum):
    MINION = "minion"
    NORMAL = "normal"
    ELITE = "elite"
    MINI_BOSS = "mini_boss"
    BOSS = "boss"


# ---------- Sub-models ----------

class RoomConnection(BaseModel):
    """A connection from this room to another."""
    direction: Direction
    target_room_id: str
    is_locked: bool = False
    lock_type: str | None = None  # "key", "puzzle", "boss_kill"


class MonsterSpawn(BaseModel):
    """A monster placed in a room."""
    monster_id: str
    name: str
    rank: MonsterRank
    level: int
    count: int = 1
    description: str = ""


class ItemDrop(BaseModel):
    """An item placed in a room."""
    item_id: str
    name: str
    rarity: str = "common"
    description: str = ""


class EnvironmentalEffect(BaseModel):
    """Environmental hazard or effect in a room."""
    effect_type: str  # "poison_fog", "darkness", "water", "fire", "ice"
    intensity: float = Field(ge=0.0, le=1.0, default=0.5)
    description: str = ""


class Room(BaseModel):
    """A single dungeon room."""
    id: str
    type: RoomType
    shape: RoomShape = RoomShape.RECTANGULAR
    size: RoomSize = RoomSize.MEDIUM
    name: str = ""
    description: str = ""
    connections: list[RoomConnection] = []
    monsters: list[MonsterSpawn] = []
    items: list[ItemDrop] = []
    environmental: list[EnvironmentalEffect] = []
    is_explored: bool = False


class BossData(BaseModel):
    """Boss encounter data."""
    boss_id: str
    name: str
    title: str
    level: int
    description: str
    phases: int = 1
    special_mechanics: list[str] = []
    lore: str = ""
    loot_table: list[ItemDrop] = []


# ---------- Request / Response ----------

class DungeonGenerateRequest(BaseModel):
    """Request body for dungeon floor generation."""
    floor_number: int = Field(ge=1, le=100, description="Current floor number")
    difficulty: Difficulty = Difficulty.NORMAL
    player_level: int = Field(ge=1, le=100, default=1)
    player_inventory: list[str] = Field(default_factory=list, description="Item IDs the player holds")
    visited_room_types: list[RoomType] = Field(default_factory=list, description="Room types the player has seen recently")
    seed: int | None = Field(default=None, description="RNG seed for reproducibility")


class DungeonGenerateResponse(BaseModel):
    """Response body for dungeon floor generation."""
    floor_number: int
    floor_name: str
    floor_description: str
    rooms: list[Room]
    boss: BossData | None = None
    seed: int


class AdaptRequest(BaseModel):
    """Request body for adaptive difficulty adjustment."""
    player_id: str = "player_1"
    floor_number: int = 1
    deaths: int = 0
    average_clear_time_seconds: float = 0.0
    damage_taken_ratio: float = Field(ge=0.0, le=1.0, default=0.5, description="Avg HP lost per room as ratio")
    healing_item_usage: float = Field(ge=0.0, le=1.0, default=0.3, description="Healing item usage rate")
    exploration_rate: float = Field(ge=0.0, le=1.0, default=0.5, description="Rooms explored / total rooms")
    player_level: int = 1
    current_difficulty: Difficulty = Difficulty.NORMAL


class AdaptResponse(BaseModel):
    """Response body for adaptive difficulty adjustment."""
    recommended_difficulty: Difficulty
    monster_level_offset: int = Field(description="Added to base monster level")
    monster_count_multiplier: float = Field(ge=0.5, le=2.0)
    trap_frequency: float = Field(ge=0.0, le=1.0)
    loot_quality_bonus: float = Field(ge=0.0, le=1.0)
    healing_item_frequency: float = Field(ge=0.0, le=1.0)
    reason: str = ""
