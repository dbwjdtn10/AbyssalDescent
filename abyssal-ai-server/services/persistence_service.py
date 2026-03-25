"""File-based persistence for NPC state and game data.

Thread-safe with on-demand save.  Stores data as JSON files in
the configured ``data_dir`` directory.
"""

from __future__ import annotations

import json
import logging
import os
import threading
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)


class PersistenceService:
    """File-based persistence for NPC state and game data.

    Thread-safe with explicit :meth:`flush` to write to disk.
    """

    def __init__(self, data_dir: str = "./data") -> None:
        self._data_dir = Path(data_dir)
        self._data_dir.mkdir(parents=True, exist_ok=True)
        self._lock = threading.Lock()

        # Internal stores keyed by collection name
        self._collections: dict[str, dict[str, dict[str, Any]]] = {}

        # Dedicated NPC state store
        self._npc_states: dict[str, dict[str, Any]] = {}

        # Player state store
        self._player_states: dict[str, dict[str, Any]] = {}

        self._load_all()

    # ------------------------------------------------------------------
    # NPC State helpers
    # ------------------------------------------------------------------

    def _ensure_npc(self, npc_id: str) -> dict[str, Any]:
        """Ensure an NPC entry exists and return it."""
        if npc_id not in self._npc_states:
            self._npc_states[npc_id] = {
                "affinity": 0,
                "emotion": "neutral",
                "conversation_count": 0,
            }
        return self._npc_states[npc_id]

    def get_npc_affinity(self, npc_id: str) -> int:
        with self._lock:
            return self._ensure_npc(npc_id).get("affinity", 0)

    def set_npc_affinity(self, npc_id: str, value: int) -> None:
        with self._lock:
            self._ensure_npc(npc_id)["affinity"] = max(-100, min(100, value))

    def get_npc_emotion(self, npc_id: str) -> str:
        with self._lock:
            return self._ensure_npc(npc_id).get("emotion", "neutral")

    def set_npc_emotion(self, npc_id: str, emotion: str) -> None:
        with self._lock:
            self._ensure_npc(npc_id)["emotion"] = emotion

    def get_npc_conversation_count(self, npc_id: str) -> int:
        with self._lock:
            return self._ensure_npc(npc_id).get("conversation_count", 0)

    def increment_conversation_count(self, npc_id: str) -> int:
        with self._lock:
            state = self._ensure_npc(npc_id)
            state["conversation_count"] = state.get("conversation_count", 0) + 1
            return state["conversation_count"]

    # ------------------------------------------------------------------
    # Player State
    # ------------------------------------------------------------------

    def save_player_state(self, player_id: str, state: dict[str, Any]) -> None:
        with self._lock:
            self._player_states[player_id] = state

    def get_player_state(self, player_id: str) -> dict[str, Any]:
        with self._lock:
            return self._player_states.get(player_id, {})

    # ------------------------------------------------------------------
    # Generic key-value store
    # ------------------------------------------------------------------

    def save(self, collection: str, key: str, data: dict[str, Any]) -> None:
        with self._lock:
            if collection not in self._collections:
                self._collections[collection] = {}
            self._collections[collection][key] = data

    def load(self, collection: str, key: str) -> dict[str, Any] | None:
        with self._lock:
            return self._collections.get(collection, {}).get(key)

    def delete(self, collection: str, key: str) -> None:
        with self._lock:
            col = self._collections.get(collection)
            if col and key in col:
                del col[key]

    # ------------------------------------------------------------------
    # File I/O
    # ------------------------------------------------------------------

    def _collection_path(self, name: str) -> Path:
        return self._data_dir / f"{name}.json"

    def _load_all(self) -> None:
        """Load all persisted data from JSON files on disk."""
        # NPC states
        npc_path = self._collection_path("npc_states")
        if npc_path.exists():
            try:
                with open(npc_path, encoding="utf-8") as f:
                    self._npc_states = json.load(f)
                logger.info("Loaded NPC states from %s", npc_path)
            except (json.JSONDecodeError, OSError) as exc:
                logger.warning("Failed to load NPC states: %s", exc)

        # Player states
        player_path = self._collection_path("player_states")
        if player_path.exists():
            try:
                with open(player_path, encoding="utf-8") as f:
                    self._player_states = json.load(f)
                logger.info("Loaded player states from %s", player_path)
            except (json.JSONDecodeError, OSError) as exc:
                logger.warning("Failed to load player states: %s", exc)

        # Generic collections
        for filepath in self._data_dir.glob("*.json"):
            name = filepath.stem
            if name in ("npc_states", "player_states"):
                continue
            try:
                with open(filepath, encoding="utf-8") as f:
                    self._collections[name] = json.load(f)
                logger.info("Loaded collection '%s' from %s", name, filepath)
            except (json.JSONDecodeError, OSError) as exc:
                logger.warning("Failed to load collection '%s': %s", name, exc)

    def _save_collection(self, collection: str) -> None:
        """Save a single collection to disk."""
        path = self._collection_path(collection)
        if collection == "npc_states":
            data = self._npc_states
        elif collection == "player_states":
            data = self._player_states
        else:
            data = self._collections.get(collection, {})

        try:
            with open(path, "w", encoding="utf-8") as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
        except OSError as exc:
            logger.error("Failed to save collection '%s': %s", collection, exc)

    def flush(self) -> None:
        """Force save all data to disk."""
        with self._lock:
            self._save_collection("npc_states")
            self._save_collection("player_states")
            for name in self._collections:
                self._save_collection(name)
        logger.info("All persistence data flushed to disk.")


# Module-level singleton
persistence_service = PersistenceService()
